
# ToDo::Sankar::Refactor - rename this to api_proxy or slice_proxy
# this module invokes slices from CLI, ideally it should be a restful proxy
# change log to act as a restful proxy under util/api_proxy

require 'helpers/http_helper'
require 'stack'

# @todo danielp 2012-10-24: this shouldn't include the database tooling.
class ProjectHanlon::Slice < ProjectHanlon::Object
  include ProjectHanlon::HttpHelper
  include ProjectHanlon::Logging

  attr_accessor :uri_root, :hidden
  attr_accessor :verbose
  attr_accessor :debug

  # Initializes the Slice Base
  # @param [Array] args
  def initialize(args = nil)
    @command_array = []
    @command_array = args if args
    @command_help_text = ""
    @prev_args = ProjectHanlon::Stack.new
    @hidden = true

    Diagnostics::Tracer.watch_object($config)

    this_config = ProjectHanlon.config
    Diagnostics::Tracer.watch_object(this_config)

    @uri_root = $config.hanlon_uri + $config.websvc_root

    @data = get_data if $app_type=="server"
  end

  def self.additional_fields
    %w"   "
  end

  # Return the name of this slice - essentially, the final classname without
  # the leading hierarchy, in Ruby "filename" format rather than "classname"
  # format.  Not cached, because this is seldom used, and is never on the
  # hot path.
  def slice_name
    self.class.name.
        split('::').
        last.
        scan(/[[:upper:]][[:lower:]]*/).
        join('_').
        downcase
  end

  def slice_commands
    fail "Unfortunately, the #{slice_name} slice chose not to define any commands!"
  end
  private 'slice_commands'

  # Default call method for a slice
  # Used by {./bin/project_hanlon}
  # Parses the #command_array and determines the action based on slice_commands for child object
  def slice_call
    begin
      #puts slice_commands
      eval_command(slice_commands)
    rescue => e
      if @debug
        raise e
      else
        slice_error(e)
      end
    end
  end

  def coercively_equal(want, have)
    case want
      when Symbol, String
        want.to_s == have.to_s

      when Regexp
        have =~ want

      when Array
        # We simply ignore `nil` values in the array, as per the original code.
        want.reject(&:nil?).any? {|x| coercively_equal(x, have) }

      else
        fail "unknown coercive comparator class #{want.class}"
    end
  end
  private 'coercively_equal'

  def eval_command(command_hash)
    unless @command_array.count > 0
      # No commands or arguments are left, we need to call the :default action
      if command_hash[:default]
        # No command specified using calling (default)
        return eval_action(command_hash, :default)
      else
        # No (default) action defined
        raise ProjectHanlon::Error::Slice::Generic, "No Default Action"
      end
    end


    command_hash.each do |k,v|
      if coercively_equal(k, @command_array.first)
        @prev_args.push(@command_array.shift)
        return eval_action(command_hash, k)
      end
    end

    # We did not find a match, we call :else
    if command_hash[:else]
      return eval_action(command_hash, :else)
    else
      # No (else) action defined
      raise ProjectHanlon::Error::Slice::InvalidCommand, "System Error: no else action for slice"
    end
  end

  def eval_action(command_hash, command_action)
    case command_hash[command_action]
      when Symbol
        # Symbol reroutes to another command
        @command_array.unshift(command_hash[command_action].to_s)
        eval_command(command_hash)
      when String
        # String calls a method
        self.send(command_hash[command_action])
      when Hash
        # A hash is iterated
        eval_command(command_hash[command_action])
      else
        raise "InvalidActionSlice"
    end
  end

  def success_types
    {
        :generic => {
            :http_code => 200,
            :message => "Ok"
        },
        :created => {
            :http_code => 201,
            :message => "Created"
        },
        :updated => {
            :http_code => 202,
            :message => "Updated"
        },
        :removed => {
            :http_code => 202,
            :message => "Removed"
        }
    }
  end

  # Called when a slice action triggers an error
  # Returns a json string representing a [Hash] with metadata including error code and message
  # @param [Hash] error
  def slice_error(error)
    return_hash = {}
    log_level = :error
    if error.class.ancestors.include?(ProjectHanlon::Error::Slice::Generic)
      return_hash["std_err_code"] = error.std_err
      return_hash["err_class"] = error.class.to_s
      return_hash["result"] = error.message
      return_hash["http_err_code"] = error.http_err_code
      log_level = error.log_severity
    else
      # We use old style if error is String
      return_hash["std_err_code"] = 1
      return_hash["result"] = error
    end

    @command = "null" if @command == nil
    return_hash["slice"] = self.class.to_s
    return_hash["command"] = @command
    list_help(return_hash)
    logger.send log_level, "Slice Error: #{return_hash.inspect}"
  end

  def list_help(return_hash = nil)
    if return_hash != nil
      print "[#{slice_name}] "
      print "[#{return_hash["command"]}] ".red
      print "<-#{return_hash["result"]}\n".yellow
    end
    if @command_help_text && @command_help_text.length > 0
      puts "\nCommand help:\n" +  @command_help_text
    end
  end

  # Return a hash mapping symbolic command names to option data; this is the
  # internal counterpart to `command_option_data`, which imposes the semantics
  # around searching this map.
  def all_command_option_data
    fail "The #{slice_name} command has not defined any command options!"
  end
  private 'all_command_option_data'

  def command_option_data(command)
    # The original version of this would raise an exception (Errno::ENOENT)
    # when the file didn't exist on disk; this roughly mirrors those semantics
    # albeit without preserving the exact exception.  I don't think anyone
    # cares, since nothing in Hanlon catches it specifically. --daniel 2013-04-16
    all_command_option_data[command.to_sym] or
        fail "Unknown command #{command} was looked up in `command_option_data`"
  end

  def get_options(options = { }, optparse_options = { })
    optparse_options[:banner] ||= "hanlon [command] [options...]"
    optparse_options[:width] ||= 32
    optparse_options[:indent] ||= ' ' * 4
    OptionParser.new(optparse_options[:banner], optparse_options[:width], optparse_options[:indent]) do |opts|
      opts.banner = optparse_options[:banner]
      optparse_options[:options_items].each do |opt_item|
        options[opt_item[:name]] = opt_item[:default]
        opts.on(opt_item[:short_form], opt_item[:long_form], "#{opt_item[:description]} #{" - required" if opt_item[:required] && optparse_options[:list_required]}") do |param|
          options[opt_item[:name]] = param ? param : true
        end
      end
      opts.on('-h', '--help', 'Display this screen.') do
        print "Usage: "
        puts opts
        exit
      end
    end
  end

  def get_options_web
    begin
      return Hash[sanitize_hash(JSON.parse(@command_array.shift)).map { |(k, v)| [k.to_sym, v] }]
    rescue JSON::ParserError => e
      # TODO: Determine if logging appropriate
      puts e.message
      return {}
    rescue Exception => e
      # TODO: Determine if throwing exception appropriate
      raise e
    end
  end

  def validate_options(validate_options = { })
    #validate_options[:logic] ||= :require_all
    validate_options[:logic] ||= :require_none
    option_names = validate_options[:options].map { |key, value| key }
    case validate_options[:logic]
      when :require_one
        count = 0
        validate_options[:option_items].each do
        |opt_item|
          count += 1 if opt_item[:required] && validate_arg(validate_options[:options][opt_item[:name]])
        end
        raise ProjectHanlon::Error::Slice::MissingArgument, "Must provide one option from #{option_names.inspect}." if count < 1
      when :require_all
        validate_options[:option_items].each do
        |opt_item|
          raise ProjectHanlon::Error::Slice::MissingArgument, "Must Provide: [#{opt_item[:description]}]" if opt_item[:required] && !validate_arg(validate_options[:options][opt_item[:name]])
        end
    end

  end

  # Returns all child templates from prefix
  def get_child_templates(namespace)
    if [Symbol, String].include? namespace.class
      namespace.gsub!(/::$/, '') if namespace.is_a? String
      namespace = ::Object.full_const_get namespace
    end

    namespace.class_children.map do |child|
      new_object             = child.new({ })
      new_object.is_template = true
      new_object
    end.reject do |object|
      object.hidden
    end
  end

  alias :get_child_types :get_child_templates

  # Checks to make sure an arg is a format that supports a noun (uuid, etc))
  def validate_arg(*arg)
    arg.each do |a|
      return false unless a && (a.to_s =~ /^\{.*\}$/) == nil && a != '' && a != {}
    end
  end

  # used by slices to parse and validate the options for a particular subcommand
  def parse_and_validate_options(option_items, logic = nil, optparse_options = { })
    options = {}
    uuid = @prev_args.peek(0)
    # Get our optparse object passing our options hash, option_items hash, and our banner
    optparse_options[:options_items] = option_items
    optparse = get_options(options, optparse_options)
    # set the command help text to the string output from optparse
    @command_help_text << optparse.to_s
    @command_help_text << "\t#{optparse_options[:note]}" if optparse_options[:note]
    # parse our ARGV with the optparse unless options are already set from get_options_web
    optparse.parse!(@command_array) unless option_items.any? { |k| options[k] }
    # validate required options, we use the :require_one logic to check if at least one :required value is present
    validate_options(:option_items => option_items, :options => options, :logic => logic)
    return uuid, options
  end

  # used by the slices to print out detailed usage for individual subcommands
  def print_subcommand_help(command, contained_resource, option_items, optparse_options = { })
    optparse_options[:banner] = ( option_items.select { |elem| elem[:uuid_is] == "required" }.length > 0 ?
        "hanlon #{slice_name} (#{slice_name.upcase}_UUID) #{contained_resource} #{command} (UUID) (options...)" :
        "hanlon #{slice_name} (#{slice_name.upcase}_UUID) #{contained_resource} #{command} (options...)")
    print_command_help(command, option_items, optparse_options)
  end

  # used by the slices to print out detailed usage for individual commands
  def print_command_help(command, option_items, optparse_options = { })
    unless optparse_options[:banner] && !optparse_options[:banner].empty?
      optparse_options[:banner] = ( option_items.select { |elem| elem[:uuid_is] == "required" }.length > 0 ?
          "hanlon #{slice_name} #{command} (UUID) (options...)" :
          "hanlon #{slice_name} #{command} (options...)")
    end
    optparse_options[:options_items] = option_items
    usage_lines = get_options({}, optparse_options).to_s.split("\n")
    usage_lines << "\t#{optparse_options[:note]}" if optparse_options[:note]
    if usage_lines
      puts "Usage: #{usage_lines[0]}"
      usage_lines[1..usage_lines.size].each { |line|
        puts line
      } if usage_lines.length > 1
    end
  end

  # used by slices to ensure that the usage of options for any given
  # subcommand is consistent with the usage declared in the option_items
  # Hash map for that subcommand
  def check_option_usage(option_items, options, uuid_included, exclusive_choice)
    selected_option_names = options.keys
    selected_options = option_items.select{ |item| selected_option_names.include?(item[:name]) }
    if exclusive_choice && selected_options.length > 1
      # if it's an exclusive choice and more than one option was chosen, it's an error
      raise ProjectHanlon::Error::Slice::SliceCommandParsingFailed,
            "Only one of the #{options.map { |key, val| key }.inspect} flags may be used"
    end
    # check all of the flags that were passed to see if the UUID was included
    # if it's required for that flag (and if it was not if it is not allowed
    # for that flag)
    selected_options.each { |selected_option|
      if (!uuid_included && selected_option[:uuid_is] == "required")
        raise ProjectHanlon::Error::Slice::SliceCommandParsingFailed,
              "Must specify a UUID value when using the '#{selected_option[:name]}' option"
      elsif (uuid_included &&  selected_option[:uuid_is] == "not_allowed")
        raise ProjectHanlon::Error::Slice::SliceCommandParsingFailed,
              "Cannot specify a UUID value when using the '#{selected_option[:name]}' option"
      end
    }
  end

  # used by the slices to throw an error when an error occurred while attempting to parse
  # a slice command line
  def throw_syntax_error
    command_str = "hanlon #{slice_name} #{@prev_args.join(" ")}"
    command_str << " " + @command_array.join(" ") if @command_array && @command_array.length > 0
    raise ProjectHanlon::Error::Slice::SliceCommandParsingFailed,
          "failed to parse slice command: '#{command_str}'; check usage"
  end

  # used by the slices to throw an error when a UUID was expected in a slice command
  # but no UUID value was found
  def throw_missing_uuid_error
    raise ProjectHanlon::Error::Slice::MissingArgument,
          "Expected UUID argument missing; a UUID is required for this command"
  end

  # used by slices to support an error indicating that an operation is not
  # supported by that slice
  def throw_get_by_uuid_not_supported
    raise ProjectHanlon::Error::Slice::NotImplemented,
          "there is no 'get_by_uuid' operation defined for the #{slice_name} slice"
  end

  # used by slices to construct a typical @slice_command hash map based on
  # an input set of function names
  def get_command_map(help_cmd_name, get_all_cmd_name, get_by_uuid_cmd_name,
                      add_cmd_name, update_cmd_name, remove_all_cmd_name, remove_by_uuid_cmd_name)
    return_all = ["all", '{}', /^\{.*\}$/, nil]
    cmd_map = {}
    get_all_cmd_name = "throw_missing_uuid_error" unless get_all_cmd_name
    remove_all_cmd_name = "throw_missing_uuid_error" unless remove_all_cmd_name
    get_by_uuid_cmd_name = "throw_get_by_uuid_not_supported" unless get_by_uuid_cmd_name
    raise ProjectHanlon::Error::Slice::MissingArgument,
          "A 'help_cmd_name' parameter must be included" unless help_cmd_name

    # add a get action if non-nil values for the get-related command names
    # were included in the input arguments
    cmd_map[:get] = {
        return_all                      => get_all_cmd_name,
        :default                        => get_all_cmd_name,
        ["--help", "-h"]                => help_cmd_name,
        /^(?!^(all|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/ => {
            [/^\{.*\}$/]                    => get_by_uuid_cmd_name,
            :default                        => get_by_uuid_cmd_name,
            :else                           => "throw_syntax_error"
        }
    } if (get_all_cmd_name && get_by_uuid_cmd_name)
    # add an add action if a non-nil value for the add_cmd_name parameter
    # was included in the input arguments
    cmd_map[:add] = {
        :default         => add_cmd_name,
        :else            => add_cmd_name,
        ["--help", "-h"] => help_cmd_name
    } if add_cmd_name
    # add an update action if a non-nil value for the update_cmd_name
    # parameter names was included in the input arguments
    cmd_map[:update] = {
        :default                        => "throw_missing_uuid_error",
        ["--help", "-h"]                => help_cmd_name,
        /^(?!^(all|\-\-help|\-h)$)\S+$/ => {
            :else                           => update_cmd_name,
            :default                        => update_cmd_name
        }
    } if update_cmd_name
    # add an update action if a non-nil value for the remove_cmd_name
    # parameter names was included in the input arguments
    cmd_map[:remove] = {
        ["all"]                         => remove_all_cmd_name,
        :default                        => "throw_missing_uuid_error",
        ["--help", "-h"]                => help_cmd_name,
        /^(?!^(all|\-\-help|\-h)$)\S+$/ => {
            [/^\{.*\}$/]                    => remove_by_uuid_cmd_name,
            :else                           => "throw_syntax_error",
            :default                        => remove_by_uuid_cmd_name
        }
    } if (remove_all_cmd_name && remove_by_uuid_cmd_name)
    # add a few more elements that are common between slices
    cmd_map[:default] = :get
    cmd_map[:else] = :get
    cmd_map[["--help", "-h"]] = help_cmd_name
    # and return the result
    cmd_map
  end

  # Gets a selection of objects for slice
  # @param noun [String] name of the object for logging
  # @param collection [Symbol] collection for object

  def get_object(noun, collection, uuid = nil)
    logger.debug "Query #{noun} called"

    # If uuid provided just grab and return
    if uuid
      return return_objects_using_uuid(collection, uuid)
    end

    return_objects(collection)
  end

  # Return objects using a filter
  # @param filter [Hash] contains key/values used for filtering
  # @param collection [Symbol] collection symbol
  def return_objects_using_filter(collection, filter_hash)
    @data.fetch_objects_by_filter(collection, filter_hash)
  end

  # Return all objects (no filtering)
  def return_objects(collection)
    @data.fetch_all_objects(collection)
  end

  # Return objects using uuid
  # @param filter [Hash] contains key/values used for filtering
  # @param collection [Symbol] collection symbol
  def return_objects_using_uuid(collection, uuid)
    @data.fetch_object_by_uuid_pattern(collection, uuid)
  end

  def print_object_array(object_array, title = nil, options = { })
    # This is for backwards compatibility
    title = options[:title] unless title
    puts title if title
    unless object_array.count > 0
      puts "< none >".red
    end
    if @verbose
      object_array.each do |obj|
        obj.instance_variables.each do |iv|
          unless iv.to_s.start_with?("@_")
            key = iv.to_s.sub("@", "")
            print "#{key}: "
            print "#{obj.instance_variable_get(iv)}  ".green
          end
        end
        print "\n"
      end
    else
      print_array  = []
      header       = []
      line_colors  = []
      header_color = :white

      if (object_array.count == 1 || options[:style] == :item) && options[:style] != :table
        object_array.each do
        |object|
          puts print_single_item(object)
        end
      else
        object_array.each do |obj|
          print_array << obj.print_items
          header = obj.print_header
          line_colors << obj.line_color
          header_color = obj.header_color
        end
        # If we have more than one item we use table view, otherwise use item view
        print_array.unshift header if header != []
        puts print_table(print_array, line_colors, header_color)
      end
    end
  end

  def add_uri_to_object_hash(object_hash, field_name="@uuid", additional_uri_path = nil)
    noun = object_hash["@noun"]
    if additional_uri_path
      object_hash["@uri"] = "#{@uri_root}/#{noun}/#{additional_uri_path}/#{object_hash[field_name]}"
    else
      object_hash["@uri"] = "#{@uri_root}/#{noun}/#{object_hash[field_name]}"
    end
    object_hash.each do |k, v|
      if object_hash[k].class == Array
        object_hash[k].each do |item|
          if item.class == Hash
            add_uri_to_object_hash(item)
          end
        end
      end
    end

    object_hash
  end

  def add_field_to_query_string(uri_string, fieldname, value)
    # if there's already a query string in this uri_string, then
    # just append to it, otherwise start a new query string
    /^[a-z]+:\/\/[^\?]+\?\S+$/.match(uri_string) ? uri_string << "&#{fieldname}=#{value}" : uri_string << "?#{fieldname}=#{value}"
  end

  def print_single_item(obj)
    print_array  = []
    header       = []
    line_color   = []
    print_output = ""
    header_color = :white

    if obj.respond_to?(:print_item) && obj.respond_to?(:print_item_header)
      print_array = obj.print_item
      header      = obj.print_item_header
    else
      print_array = obj.print_items
      header      = obj.print_header
    end
    line_color   = obj.line_color
    header_color = obj.header_color

    print_array.each_with_index do |val, index|
      if header_color
        print_output << " " + "#{header[index]}".send(header_color)
      else
        print_output << " " + "#{header[index]}"
      end
      print_output << " => "
      if line_color
        print_output << " " + "#{val}".send(line_color) + "\n"
      else
        print_output << " " + "#{val}" + "\n"
      end

    end
    print_output + "\n"
  end

  def print_table(print_array, line_colors, header_color)
    table = ""
    print_array.each_with_index do |line, li|
      line_string = ""
      line.each_with_index do |col, ci|
        # /\e\[(\d+)(;\d+)*m/
        # Removes foreground and/or background colors
        max_col = print_array.collect { |x| x[ci].gsub(/\e\[(\d+)(;\d+)*m/, '').length }.max
        if li == 0
          if header_color
            line_string << "#{col.center(max_col)}  ".send(header_color)
          else
            line_string << "#{col.center(max_col)}  "
          end
        else
          if line_colors[li-1]
            line_string << "#{col.ljust(max_col)}  ".send(line_colors[li-1])
          else
            line_string << "#{col.ljust(max_col)}  "
          end
        end
      end
      table << line_string + "\n"
    end
    table
  end

  def expand_response_with_uris(http_response)
    http_response.map { |response_elem|

      if response_elem.has_key?("@uri")

        uri = URI.parse response_elem["@uri"]
        http = Net::HTTP.new(uri.host, uri.port)
        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)

        JSON.parse(response.body)["response"]
      else
        response_elem
      end
    }
  end
end

def tag_matcher_hash_array_to_obj_array(hash_array, tagrule_uuid, sort_fieldname = nil)
  # If a sort_field name is provided, sort the hash_array
  if sort_fieldname
    hash_array = sort_hash_array(hash_array, sort_fieldname)
  end
  hash_array.map { |hash| class_from_string(hash["@classname"]).new(hash, tagrule_uuid) }
end

def hash_array_to_obj_array(hash_array, sort_fieldname = nil)
  # If a sort_field name is provided, sort the hash_array
  if sort_fieldname
    hash_array = sort_hash_array(hash_array, sort_fieldname)
  end
  hash_array.map { |hash_val| class_from_string(hash_val["@classname"]).new(hash_val) }
end

def sort_hash_array(hash_array, sort_fieldname)
  # If the sort_fieldname in the first element of the hash array is a String,
  # convert it to lower case for case insensitive sorting
  if hash_array.first["@#{sort_fieldname}"].is_a? String
    hash_array = hash_array.sort_by { |elem| elem["@#{sort_fieldname}"].downcase }
  else
    hash_array = hash_array.sort_by { |elem| elem["@#{sort_fieldname}"] }
  end
end

def hash_to_obj(hash)
  class_from_string(hash["@classname"]).new(hash)
end

def class_from_string(str)
  str.split('::').inject(Object) do |mod, class_name|
    mod.const_get(class_name)
  end
end

require 'slice/slice_dep'
