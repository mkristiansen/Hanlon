require 'bzip2/ffi'
require 'image_service/base'
require 'json'
require 'rubygems/package'
require 'yaml'
require 'zlib'

# Root ProjectHanlon namespace
module ProjectHanlon
  class Slice

    # TODO - add inspection to prevent duplicate MK's with identical version to be added

    # ProjectHanlon Slice Image
    # Used for image management
    class Image < ProjectHanlon::Slice

      attr_reader :image_types
      DECOMP_METHOD_HASH = { 'tar' => nil,
                             'gzip' => Zlib::GzipReader.method(:wrap),
                             'bzip2' => Bzip2::FFI::Reader.method(:open)
      }
      SUPPORTED_TYPES = DECOMP_METHOD_HASH.keys

      # Initializes ProjectHanlon::Slice::Model including #slice_commands, #slice_commands_help
      # @param [Array] args
      def initialize(args)
        super(args)
        @hidden = false
        @uri_string = ProjectHanlon.config.hanlon_uri + ProjectHanlon.config.websvc_root + '/image'
        # get the available image types (input type must match one of these)
        @image_types = {
            :mk =>       {
                :desc => 'MicroKernel ISO',
                :classname => 'ProjectHanlon::ImageService::MicroKernel',
                :method => 'add_mk'
            },
            :os =>        {
                :desc => 'OS Install ISO',
                :classname => 'ProjectHanlon::ImageService::OSInstall',
                :method => 'add_os'
            },
            :win =>        {
                :desc => 'Windows Install ISO',
                :classname => 'ProjectHanlon::ImageService::WindowsInstall',
                :method => 'add_win'
            },
            :esxi =>      {
                :desc => 'VMware Hypervisor ISO',
                :classname => 'ProjectHanlon::ImageService::VMwareHypervisor',
                :method => 'add_esxi'
            },
            :xenserver => {
                :desc => 'XenServer Hypervisor ISO',
                :classname => 'ProjectHanlon::ImageService::XenServerHypervisor',
                :method => 'add_xenserver'
            }
        }
      end

      def self.additional_fields
        %w"@local_image_path @status @status_message"
      end

      def slice_commands
        # get the slice commands map for this slice (based on the set
        # of commands that are typical for most slices)
        commands = get_command_map(
            'image_help',
            'get_images',
            'get_image_by_uuid',
            'add_image',
            nil,
            nil,
            'remove_image')
        # and add a few more commands specific to this slice; first remove the default line that
        # handles the lines where a UUID is passed in as part of a "get_node_by_uuid" command
        commands[:get].delete(/^(?!^(all|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/)
        # then add a slightly different version of this line back in; one that incorporates
        # the other flags we might pass in as part of a "get_all_nodes" command
        commands[:get][/^(?!^(all|\-\-hidden|\-i|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/] = 'get_image_by_uuid'
        # and add in a couple of lines to that handle those flags properly
        commands[:get][['-i', '--hidden']] = 'get_images'
        commands
      end

      def all_command_option_data
        {
            :get_all => [
                { :name        => :show_hidden,
                  :default     => nil,
                  :short_form  => '-i',
                  :long_form   => '--hidden',
                  :description => 'Return all images (including hidden images)',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                }
            ],
            :add => [
                { :name        => :type,
                  :default     => nil,
                  :short_form  => '-t',
                  :long_form   => '--type TYPE',
                  :description => 'The type of image (mk, os, win, esxi, or xenserver)',
                  :uuid_is     => 'not_allowed',
                  :required    => true
                },
                { :name        => :path,
                  :default     => nil,
                  :short_form  => '-p',
                  :long_form   => '--path /path/to/iso',
                  :description => 'The local path to the image ISO',
                  :uuid_is     => 'not_allowed',
                  :required    => true
                },
                { :name        => :name,
                  :default     => nil,
                  :short_form  => '-n',
                  :long_form   => '--name IMAGE_NAME',
                  :description => 'The logical name to use (required; os images only)',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                },
                { :name        => :version,
                  :default     => nil,
                  :short_form  => '-v',
                  :long_form   => '--version VERSION',
                  :description => 'The version to use (required; os images only)',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                },
                { :name        => :docker_image,
                  :default     => nil,
                  :short_form  => '-d',
                  :long_form   => '--docker-image /path/to/img',
                  :description => 'The local path to MK image (required; mk images only)',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                },
                { :name        => :ssh_keyfile,
                  :default     => nil,
                  :short_form  => '-k',
                  :long_form   => '--ssh-keyfile /path/to/key',
                  :description => 'The local path to public key file (optional; mk images only)',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                },
                { :name        => :mk_password,
                  :default     => nil,
                  :short_form  => '-m',
                  :long_form   => '--mk-password PASSWORD',
                  :description => 'The microkernel password (optional; mk images only)',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                }
            ]
        }.freeze
      end

      def image_help
        if @prev_args.length > 1
          command = @prev_args.peek(1)
          begin
            # load the option items for this command (if they exist) and print them
            option_items = command_option_data(command)
            print_command_help(command, option_items)
            return
          rescue
          end
        end
        puts 'Image Slice: used to add, view, and remove Images.'.red
        puts 'Image Commands:'.yellow
        puts '\thanlon image [get] [all] [--hidden,-i]    ' + 'View all images (detailed list)'.yellow
        puts '\thanlon image [get] (UUID)                 ' + 'View details of specified image'.yellow
        puts '\thanlon image add (options...)             ' + 'Add a new image to the system'.yellow
        puts '\thanlon image remove (UUID)                ' + 'Remove existing image from the system'.yellow
        puts '\thanlon image --help|-h                    ' + 'Display this screen'.yellow
      end

      #Lists details for all images
      def get_images
        @command = :get_images
        # set a flag indicating whether or not the user wants to see all images,
        # including the hidden ones
        show_hidden = (@prev_args.peek(0) == '-i' || @prev_args.peek(0) == '--hidden')
        # get the images from the RESTful API (as an array of objects)
        uri_str = ( show_hidden ? "#{@uri_string}?hidden=true" : @uri_string )
        uri = URI.parse uri_str
        result = hnl_http_get(uri)
        unless result.blank?
          # convert it to a sorted array of objects (from an array of hashes)
          sort_fieldname = 'filename'
          result = hash_array_to_obj_array(expand_response_with_uris(result), sort_fieldname)
        end
        # and print the result
        print_object_array(result, 'Images:', :style => :table)
      end

      #Lists details for a specific image
      def get_image_by_uuid
        @command = :get_image_by_uuid
        # the UUID was the last "previous argument"
        image_uuid = @prev_args.peek(0)
        # setup the proper URI depending on the options passed in
        uri = URI.parse(@uri_string + '/' + image_uuid)
        # and get the results of the appropriate RESTful request using that URI
        result = hnl_http_get(uri)
        # finally, based on the options selected, print the results
        print_object_array(hash_array_to_obj_array([result]), 'Image:')
      end

      #Add an image
      def add_image
        @command = :add_image
        includes_uuid = false
        # load the appropriate option items for the subcommand we are handling
        option_items = command_option_data(:add)
        # parse and validate the options that were passed in as part of this
        # subcommand (this method will return a UUID value, if present, and the
        # options map constructed from the @commmand_array)
        tmp, options = parse_and_validate_options(option_items, :require_all, :banner => 'hanlon image add (options...)')
        includes_uuid = true if tmp && tmp != 'add'
        # check for usage errors (the boolean value at the end of this method
        # call is used to indicate whether the choice of options from the
        # option_items hash must be an exclusive choice)
        check_option_usage(option_items, options, includes_uuid, false)
        image_type = options[:type]
        # Note; the following expression will expand the path that is passed in into an
        # absolute directory in the case where a relative path (with respect to the current
        # working directory) was passed in.  If the user passed in an absolute path to the file,
        # then this expression will leave that absolute path unchanged
        iso_path = File.expand_path(options[:path], Dir.pwd)
        docker_image = options[:docker_image]
        ssh_keyfile = options[:ssh_keyfile]
        mk_password = options[:mk_password]
        os_name = options[:name]
        os_version = options[:version]

        # setup the POST (to create the requested policy) and return the results
        uri = URI.parse @uri_string

        body_hash = {
            'type' => image_type,
            'path' => iso_path
        }
        # if the SSH public key and/or path to the docker image were included,
        # add them to the body_hash
        body_hash['docker_image'] = docker_image if docker_image
        body_hash['ssh_keyfile'] = ssh_keyfile if ssh_keyfile
        body_hash['mk_password'] = mk_password if mk_password
        # if OS name and version were included, add them to the body_hash
        body_hash['name'] = os_name if os_name
        body_hash['version'] = os_version if os_version
        json_data = body_hash.to_json
        puts 'Attempting to add, please wait...'.green
        result = hnl_http_post_json_data(uri, json_data)
        # if got a single hash map back, then print the details
        return print_object_array(hash_array_to_obj_array([result]), 'Image Added:') unless result.is_a?(Array)
        # otherwise print the table containing the results
        unless result.blank?
          # convert it to a sorted array of objects (from an array of hashes)
          sort_fieldname = 'wim_index'
          result = hash_array_to_obj_array(expand_response_with_uris(result), sort_fieldname)
        end
        print_object_array(result, 'Images:', :style => :table)
      end

      def remove_image
        @command = :remove_image
        # the UUID was the last "previous argument"
        image_uuid = @prev_args.peek(0)
        # setup the DELETE (to remove the indicated image) and return the results
        uri = URI.parse @uri_string + "/#{image_uuid}"
        result = hnl_http_delete(uri)
        puts result
      end

      # utility methods (used to add various types of images)

      def add_mk(new_image, iso_path, image_path, docker_image, ssh_keyfile, mk_password)
        # ensure a path was passed in for the docker_image
        raise ProjectHanlon::Error::Slice::MissingArgument, 'path to docker image must be included for MK images' unless docker_image && docker_image != ""
        begin
          # get the filetype for the docker_image
          docker_filetype = get_file_type(docker_image)
          # ensure it's a supported filetype
          raise ProjectHanlon::Error::Slice::InputError, "Unsupported file type '#{docker_filetype}' detected for Docker image '#{docker_image}'; supported types are #{SUPPORTED_TYPES}" unless SUPPORTED_TYPES.include?(docker_filetype)
          # get the version information from the docker_image
          os_version = get_docker_version_info(docker_image, DECOMP_METHOD_HASH[docker_filetype])
        rescue Errno::ENOENT, Errno::EACCES => e
          # if the file does not exist or file cannot be opened for reading due to permissions,
          # then throw an error that will be caught by Hanlon and reported properly
          raise ProjectHanlon::Error::Slice::InputError, "Image file '#{docker_image}' cannot be opened for reading (#{e.message})"
        rescue ProjectHanlon::Error::Slice::InputError => e
          # if the underlying method calls raised an error, then add information about which docker_image
          # was being processed and rethrow the error in a form that Hanlon will detect and handle properly
          raise ProjectHanlon::Error::Slice::InputError, "Image file '#{docker_image}' #{e.message}"
        end
        # if no version tag was found, raise an exception
        raise ProjectHanlon::Error::Slice::MissingArgument, 'MK Docker images must include a version tag' unless os_version && os_version != ""
        # otherwise add the Microkernel image to Hanlon
        new_image.add(iso_path, image_path, {:os_version => os_version, :docker_image => docker_image,
                                             :ssh_keyfile => ssh_keyfile, :mk_password => mk_password})
      end

      def add_esxi(new_image, iso_path, image_path)
        new_image.add(iso_path, image_path)
      end

      def add_xenserver(new_image, iso_path, image_path)
        new_image.add(iso_path, image_path)
      end

      def add_win(new_image, iso_path, image_path)
        new_image.add(iso_path, image_path)
      end

      def add_os(new_image, iso_path, image_path, os_name, os_version)
        raise ProjectHanlon::Error::Slice::MissingArgument,
              'image name must be included for OS images' unless os_name && os_name != ''
        raise ProjectHanlon::Error::Slice::MissingArgument,
              'image version must be included for OS images' unless os_version && os_version != ''
        new_image.add(iso_path, image_path, {:os_version => os_version, :os_name => os_name})
      end

      def insert_image(image_obj)
        image_obj = @data.persist_object(image_obj)
        image_obj.refresh_self
      end

      def get_file_type(file_path)
        png_regex = Regexp.new("\x89PNG".force_encoding('binary'))
        jpg_regex = Regexp.new("\xff\xd8\xff\xe0\x00\x10JFIF".force_encoding('binary'))
        jpg2_regex = Regexp.new("\xff\xd8\xff\xe1(.*){2}Exif".force_encoding('binary'))
        case IO.read(file_path, 10)
          when /^GIF8/
            'gif'
          when /^#{png_regex}/
            'png'
          when /^#{jpg_regex}/
            'jpg'
          when /^#{jpg2_regex}/
            'jpg'
          else
            mime_type = `file #{file_path} --mime-type`.gsub("\n", '') # Works on linux and mac
            raise ProjectHanlon::Error::Slice::InputError, "Filetype could not be detected for '#{file_path}'" if !mime_type
            mime_type.split(':')[1].split('/')[1].gsub('x-', '').gsub(/jpeg/, 'jpg').gsub(/text/, 'txt').gsub(/x-/, '')
        end
      end

      def get_docker_version_info(docker_image, zip_method = nil)
        version = nil
        File.open(docker_image, 'rb') { |image|
          return get_docker_version_from_tar(image) unless zip_method
          zip_method.call(image) { |file|
            if file.class == Bzip2::FFI::Reader
              io = StringIO.new(file.read)
            else
              io = file
            end
            version = get_docker_version_from_tar(io)
          }
        }
        version
      end

      def get_docker_version_from_tar(file)
        version = nil
        is_docker_image = false
        semantic_versioned_image = false
         Gem::Package::TarReader.new(file) { |tar|
           tar.seek('repositories') { |entry|
             # if get to here, then the tarfile has a repositories entry in it,
             # so we'll say it's a Docker image
             is_docker_image = true
             # read that file and parse the version info (if it exists) from it
             repo_info = entry.read
             # if it's a Docker file, that entry should be a JSON file
             # containing a Hash map (in JSON form) with the tag as the
             # key of the first value in that Hash
             begin
               contents_as_hash = JSON.parse(repo_info)
               # if the contents retrieved from the 'repositories' file are nil or
               # the contents parsed are not a Hash, then this isn't a Docker image
               raise ProjectHanlon::Error::Slice::InputError, "does not contain a Docker image ('repositories' file does not contain a JSON Hash)" unless contents_as_hash and contents_as_hash.is_a?(Hash)
               first_value = contents_as_hash.values[0]
               # if the first_value in the Hash is nil or is not itself a Hash, then this isn't a Docker image
               raise ProjectHanlon::Error::Slice::InputError, "does not contain a Docker image ('repositories' entry does not include a version)" unless first_value and first_value.is_a?(Hash)
               # Note; in this code we're assuming that the contents of the 'repositories' file contains a JSON
               # string that looks something like this:
               #     {"gliderlabs/alpine":{"latest":"2cc966a5578a2339d7aa9c729d6d51c655ac2b68a716ecff05c56a91a05c89d7"}}
               # we could do more testing of the format of the value we found, but for now we'll just assume that
               # if we found a JSON string containing a hash where the first value is a Hash we're on the right track.
               # As such, if we get this far, then take the first key from the first value and return that as the version
               # for the docker image file
               version = first_value.keys[0]
             rescue JSON::ParserError => e
               # if we get here, then we weren't able to parse the 'repositories' entry as a JSON string, so it's
               # not a Docker image; throw an appropriate error
               raise ProjectHanlon::Error::Slice::InputError, "does not contain a Docker image ('repositories' entry cannot be parsed as a JSON string)"
             end
             # test to see if the version we found looks like a Microkernel version that is
             # supported by Hanlon (Hanlon supports a 'pseudo-semantic' version for it's Micorkernel);
             # a true semantic version string might look something like this:
             #    3.0.0-18-ge369408-dirty
             # but that string isn't useable as a version string in Docker, so instead we've shifted over
             # to using a version string that can be used as a Docker tag:
             #    3.0.0_18-ge369408-dirty
             # the difference is subtle, but significant; our Microkernel versions are no longer truly a
             # semantic version, but we are using a version string within Hanlon that is consistent with the
             # version string used for that same Microkernel image within Docker...hopefully the difference
             # from previous versions of Hanlon are not too difficult to sort out ;)
             semantic_versioned_image = true if version && /^(\d+\.\d+\.\d+)(_([0-9A-Za-z-]+))*$/.match(version)
           }
           # throw errors if either the image passed in does not contain a 'repositories' entry (in which
           # case it's not a Docker image) or the version that we found in the image is tagged with is not
           # a semantic version (in which case the code used by Hanlon to determine which is the 'newest'
           # Microkernel will not work properly)
           raise ProjectHanlon::Error::Slice::InputError, "does not contain a Docker image ('repositories' entry cannot be found)" unless is_docker_image
           raise ProjectHanlon::Error::Slice::InputError, "is tagged with the invalid version '#{version}' (Docker Microkernel Images must be tagged with a semantic version)" unless semantic_versioned_image
         }
        version
      end

    end
  end
end
