#

require 'rufus-scheduler'
require 'uri'
require 'api'

require 'helper/swagger'

module Hanlon
  module WebService
    class App
      include ProjectHanlon::Logging

      CHUNK_SIZE = 2**26      # 64MB chunk size
      IMAGE_SLICE_REF = ProjectHanlon::Slice::Image.new([])

      def initialize

        #config = ProjectHanlon::Config::Server.instance
        config = $config
        if config.nil?
          abort("Aborting hanlon server")
        end

        #ToDo::Sankar:Implement - this logic should be generic to allow static html pages and through http error pages
        #if SERVICE_CONFIG[:config][:swagger_ui] && SERVICE_CONFIG[:config][:swagger_ui][:allow_access]

        if ProjectHanlon::Helper::Swagger.allow_swagger_access
          @filenames = [ '', '.html', 'index.html', '/index.html' ]
          @rack_static = ::Rack::Static.new(
              lambda { [404, {}, ['http error 404 - file not found']] }, {
              :root => File.expand_path('../../public', __FILE__),
              :urls => %w[/]
          })
        end
        # starts up a set of tasks (using the rufus-scheduler gem) that will maintain
        # (and monitor) the system
        start_scheduled_tasks
      end

      class FileStreamer
        def initialize(path, file_size, start_offset, end_offset)
          # initialize some parameters
          @path = path
          @start_offset = start_offset
          @end_offset = end_offset
          @file_size = file_size
        end

        def each(&blk)
          # open the file (and seek to the starting position,
          # if necessary
          open(@path, "rb") do |file|
            file.seek(@start_offset) if @start_offset > 0
            # determine the remaining length to read
            remaining_len = @end_offset-@start_offset+1
            # while there remains something to read
            while remaining_len > 0
              # read as much as you can (up to the CHUNK_SIZE)
              part = file.read([CHUNK_SIZE, remaining_len].min)
              # break out of the loop if nothing was read
              break unless part
              # otherwise, reduce the remaining length by what was
              # just read from the file
              remaining_len -= part.length
              # and yield to return what we just read
              yield part
            end
          end
        end
      end

      def get_file_contents(path, env)
        if /\.rpm$/.match(path)
          file_type = "application/x-rpm"
        else
          file_type = "application/octet-stream"
        end
        # response["Connection"] = 'close'
        # response["Accept-Ranges"] = 'bytes'
        file_size = File.size?(path)
        start_offset = nil
        end_offset = nil
        http_range = env['HTTP_RANGE']
        if http_range
          vals = http_range.split(/\s+|=|-|\//)
          start_offset = vals[1].to_i
          end_offset = vals[2].to_i
        else
          start_offset = 0
          end_offset = file_size - 1
        end
        body = FileStreamer.new(path, file_size, start_offset, end_offset)
        header = { 'Content-Type' => file_type, 'Connection' => 'close', 'Accept-Ranges' => 'bytes',
        'Content-Length' => end_offset-start_offset+1 }
        # and return the result
        ["200", header, body]
      end

      def is_static_path?(request_path_str)
        slices = ObjectSpace.each_object(Class).select { |klass| klass < ProjectHanlon::Slice }
        # then construct a regular expression that will filter out paths containing
        # those strings
        regex_str = "#{slices.map { |a| a.new([]).slice_name }.join('|')}"
        /^([\/]+v1)\/(#{regex_str})(.*)$/.match(request_path_str)
      end

      def call(env)

        request_path = env['PATH_INFO']

        #if SERVICE_CONFIG[:config][:swagger_ui] && SERVICE_CONFIG[:config][:swagger_ui][:allow_access]

        if ProjectHanlon::Helper::Swagger.allow_swagger_access
          # in cases where the URL entered by the user ended with a slash,
          # the paths can have a duplicate first directory in the front of
          # the request path.  The following is a hack to deal with that
          # issue (should it arise).  First, parse out the first two
          # "fields" (using the '/' as a separator) using a regex
          match = /^(\/[^\/]+)(\/[^\/]+)(.*)$/.match(request_path)

          # if there was a match, and if the first two fields are identical,
          # then remove the first and keep just the second and third as the
          # new value for the 'request_path'
          if match && match[1] == match[2]
            request_path = match[2] + match[3]
          end

          # check to see if the requested resource can be loaded as a static file
          @filenames.each do |path|
            response = @rack_static.call(env.merge({'PATH_INFO' => request_path + path}))
            return response unless [ 404, 405 ].include?(response[0])
          end
        end

        request_path_str = URI.unescape(request_path)
        matches_image = /^([\/]+v1)(\/image)(\/.*)$/.match(request_path_str)

        static_path = ProjectHanlon.config.hanlon_static_path
        matches_static = /^([\/]+v1)(\/static)(\/.*)$/.match(request_path_str)

        # if the request path matches the path for an image resource, then
        # get the contents of that image resource; else if a path was
        # configured for static content and the request path doesn't look
        # like the path to access a slice, try to return it from the
        # configured static content directory
        if matches_image
          # if here, it's a component from an image file
          matches_windows = /^(\/windows)\/([^\/]+)(\/.*)$/.match(matches_image[3])
          if matches_windows
            image_uuid = matches_windows[2]
            image = IMAGE_SLICE_REF.get_object("images", :images, image_uuid)
            return Rack::Response.new("Image not found: Image UUID = #{image_uuid})\n", 400) unless image
            return Rack::Response.new("Incorrect type: Image #{image_uuid}) not a Windows image\n", 500) unless image.respond_to?(:base_image_uuid)
            base_uuid = image.base_image_uuid
            partial_path = File.join(matches_windows[1], base_uuid, matches_windows[3])
          else
            partial_path = matches_image[3]
          end
          file = File.join(ProjectHanlon.config.image_path, partial_path)
          # otherwise, if we got this far and the requested resource is actually a file,
          # return the file contents (if there are any)
          return get_file_contents(file, env) if File.exist?(file) && File.file?(file)
        elsif matches_static
          # if here, then it's a request from something from the static path
          unless static_path && !static_path.empty?
            return Rack::Response.new("Server Error: static path not set\n", 500)
          end
          # if we got to here, then the hanlon_static_path directory was set and the
          # request path looks like a request for static content; so we'll try
          # to serve up the referenced file; first get the filename we should access
          file = File.join(static_path, matches_static[3])
          # unless we can find the file in question and it's a file, return a
          # "file not found" error (this could occur, for example, if the file is
          # actually a directory, not a file or if the file itself does not exist)
          unless File.exist?(file) && File.file?(file)
            return Rack::Response.new("File not found: #{File.join(ProjectHanlon.config.base_path, request_path_str)}\n", 404)
          end
          # otherwise, if we got this far, return the file contents (if there are any)
          return get_file_contents(file, env)
        end

        # if not, then load it via the api
        @@base_uri = env['SCRIPT_NAME']

        Hanlon::WebService::API.call(env)
      end

      def self.base_uri
        @@base_uri
      end

      # define a class-method that can be used to shut down any periodic tasks
      # that might be running
      def self.stop_periodic_tasks
        # collect together the set of jobs we have running
        jobs = Rufus::Scheduler.singleton.jobs(:tag => 'periodic_hanlon_tasks')
        jobs.push *(Rufus::Scheduler.singleton.jobs(:tag => 'track_hanlon_tasks'))
        # and for each job, shut them down
        jobs.each { |job|
          puts "Shutting down job => #{job.id}"
          job.kill && job.unschedule
        }
      end

      private

      def start_scheduled_tasks
        node_timeout = ProjectHanlon.config.node_expire_timeout
        node_timeout ||= DEFAULT_NODE_EXPIRE_TIMEOUT
        min_cycle_time = ProjectHanlon.config.daemon_min_cycle_time
        min_cycle_time ||= DEFAULT_MIN_CYCLE_TIME
        begin
          # check to make sure there isn't already a set of 'periodic_hanlon_tasks'
          # running; if there is, then skip this step
          if Rufus::Scheduler.singleton.jobs(:tag => 'periodic_hanlon_tasks')
            # start a thread that will remove any inactive nodes from the nodes list
            # (inactive nodes haven't checked in for a while and aren't bound to a model
            # via an active_model instance)

            puts ">> Starting new thread to remove inactive nodes; cycle time => #{min_cycle_time}, timeout => #{node_timeout}"
            logger.debug ">> Starting new thread to remove inactive nodes; cycle time => #{min_cycle_time}, timeout => #{node_timeout}"

            Rufus::Scheduler.singleton.every "#{min_cycle_time}s", :tag => 'periodic_hanlon_tasks' do
              begin
                engine = ProjectHanlon::Engine.instance
                engine.remove_expired_nodes(node_timeout)
              rescue Exception => e
                #puts "At 1...#{e.message}"
                logger.error "At 1...#{e.message}"
              end
            end
          end

          # check to make sure there isn't already a 'track_hanlon_tasks' thread
          # running; if there is, then skip this step
          if Rufus::Scheduler.singleton.jobs(:tag => 'track_hanlon_tasks')
            # start a thread to monitor the Hanlon-related tasks we just started (above)
            puts ">> Starting new thread to print status of Hanlon-related jobs..."
            logger.debug ">> Starting new thread to print status of Hanlon-related jobs..."

            Rufus::Scheduler.singleton.every "5m", :tag => 'track_hanlon_tasks' do
              begin
                job_ids = Rufus::Scheduler.singleton.jobs(:tag => 'periodic_hanlon_tasks').map{ |job| job.id }
                puts "  >> At #{Time.now}; Hanlon-related jobs running => [#{job_ids.join(', ')}]"
                logger.debug "  >> At #{Time.now}; Hanlon-related jobs running => [#{job_ids.join(', ')}]"
              rescue Exception => e
                #puts "At 2...#{e.message}"
                logger.error "At 2...#{e.message}"
              end
            end

            # collect together jobs that are running and print out their IDs
            job_ids = Rufus::Scheduler.singleton.jobs(:tag => 'periodic_hanlon_tasks').map { |job| job.id }
            job_ids.push *(Rufus::Scheduler.singleton.jobs(:tag => 'track_hanlon_tasks').map { |job| job.id })
            puts "  >> At #{Time.now}; All jobs running => [#{job_ids.join(', ')}]"
            logger.debug "  >> At #{Time.now}; All jobs running => [#{job_ids.join(', ')}]"
          end
        rescue Exception => e
          #puts "At 3...#{e.message}"
          logger.error "At 3...#{e.message}"
        end
      end

    end
  end
end
