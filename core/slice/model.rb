require 'json'
require 'model/base'

# Root ProjectHanlon namespace
module ProjectHanlon
  class Slice

    # ProjectHanlon Slice Model
    class Model < ProjectHanlon::Slice

      # Root namespace for model objects; used to find them
      # in object space in order to gather meta-data for creating models
      SLICE_MODEL_PREFIX = "ProjectHanlon::ModelTemplate::"

      # Initializes ProjectHanlon::Slice::Model including #slice_commands, #slice_commands_help
      # @param [Array] args
      def initialize(args)
        super(args)
        @hidden = false
        @uri_string = ProjectHanlon.config.hanlon_uri + ProjectHanlon.config.websvc_root + '/model'
      end

      def slice_commands
        # get the slice commands map for this slice (based on the set
        # of commands that are typical for most slices)
        commands = get_command_map(
            "model_help",
            "get_all_models",
            "get_model_by_uuid",
            "add_model",
            "update_model",
            "remove_all_models",
            "remove_model_by_uuid")
        # and add any additional commands specific to this slice
        commands[:get].delete(/^(?!^(all|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/)
        commands[:get][:else] = "get_model_by_uuid"
        commands[:get][[/^(temp|template|templates|types)$/]] = "get_all_templates"

        commands
      end

      def all_command_option_data
        {
            :add => [
                { :name        => :template,
                  :default     => false,
                  :short_form  => '-t',
                  :long_form   => '--template MODEL_TEMPLATE',
                  :description => 'The model template to use for the new model.',
                  :uuid_is     => 'not_allowed',
                  :required    => true
                },
                { :name        => :label,
                  :default     => false,
                  :short_form  => '-l',
                  :long_form   => '--label MODEL_LABEL',
                  :description => 'The label to use for the new model.',
                  :uuid_is     => 'not_allowed',
                  :required    => true
                },
                { :name        => :image_uuid,
                  :default     => false,
                  :short_form  => '-i',
                  :long_form   => '--image-uuid IMAGE_UUID',
                  :description => 'The image UUID to use for the new model.',
                  :uuid_is     => 'not_allowed',
                  :required    => true
                },
                { :name        => :optional_yaml,
                  :default     => false,
                  :short_form  => '-o',
                  :long_form   => '--option YAML_FILE',
                  :description => 'Use optional yaml file to create model',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                }

            ],
            :update => [
                { :name        => :label,
                  :default     => false,
                  :short_form  => '-l',
                  :long_form   => '--label MODEL_LABEL',
                  :description => 'The new label to use for the model.',
                  :uuid_is     => 'required',
                  :required    => true
                },
                { :name        => :image_uuid,
                  :default     => false,
                  :short_form  => '-i',
                  :long_form   => '--image-uuid IMAGE_UUID',
                  :description => 'The new image UUID to use for the model.',
                  :uuid_is     => 'required',
                  :required    => true
                },
                { :name        => :change_metadata,
                  :default     => false,
                  :short_form  => '-c',
                  :long_form   => '--change-metadata [YAML_FILE]',
                  :description => 'Used to trigger a change in the model\'s meta-data',
                  :uuid_is     => 'required',
                  :required    => true
                }
            ]
        }.freeze
      end

      def model_help
        if @prev_args.length > 1
          command = @prev_args.peek(1)
          begin
            # load the option items for this command (if they exist) and print them
            option_items = command_option_data(command)
            # this line adjusts the help output width for the help on the 'update' command
            # (for all others, a width of 32 will be used for the summary section of the
            # commmand help)
            optparse_options = (command == 'update' ? {:width => 34} : { })
            print_command_help(command, option_items, optparse_options)
            return
          rescue
          end
        end
        # if here, then either there are no specific options for the current command or we've
        # been asked for generic help, so provide generic help
        puts get_model_help
      end

      def get_model_help
        return ["Model Slice: used to add, view, update, and remove models.".red,
                "Model Commands:".yellow,
                "\thanlon model [get] [all]                 " + "View all models".yellow,
                "\thanlon model [get] (UUID)                " + "View specific model instance".yellow,
                "\thanlon model [get] template|templates    " + "View list of model templates".yellow,
                "\thanlon model add (options...)            " + "Create a new model instance".yellow,
                "\thanlon model update (UUID) (options...)  " + "Update a specific model instance".yellow,
                "\thanlon model remove (UUID)|all           " + "Remove existing model(s)".yellow,
                "\thanlon model --help                      " + "Display this screen".yellow].join("\n")
      end

      def get_all_models
        @command = :get_all_models
        # get the models from the RESTful API (as an array of objects)
        uri = URI.parse @uri_string
        result = hnl_http_get(uri)
        unless result.blank?
          # convert it to a sorted array of objects (from an array of hashes)
          sort_fieldname = 'label'
          result = hash_array_to_obj_array(expand_response_with_uris(result), sort_fieldname)
        end
        # and print the result
        print_object_array(result, "Models:", :style => :table)
      end

      def get_model_by_uuid
        @command = :get_model_by_uuid
        # the UUID is the first element of the @command_array
        model_uuid = @command_array.first
        # setup the proper URI depending on the options passed in
        uri = URI.parse(@uri_string + '/' + model_uuid)
        # and get the results of the appropriate RESTful request using that URI
        result = hnl_http_get(uri)
        # finally, based on the options selected, print the results
        print_object_array(hash_array_to_obj_array([result]), "Model:")
      end

      def get_all_templates
        @command = :get_all_templates
        # get the model templates from the RESTful API (as an array of objects)
        uri = URI.parse @uri_string + '/templates'
        result = hnl_http_get(uri)
        unless result.blank?
          # convert it to a sorted array of objects (from an array of hashes)
          sort_fieldname = 'name'
          result = hash_array_to_obj_array(expand_response_with_uris(result), sort_fieldname)
        end
        # and print the result
        print_object_array(result, "Model Templates:", :style => :table)
      end

      def add_model
        @command = :add_model
        includes_uuid = false
        # load the appropriate option items for the subcommand we are handling
        option_items = command_option_data(:add)
        # check the command arguments; should have pairs of arguments that look like
        # ['-option', 'value'] (or ['--option', 'value']); if find an option that doesn't start
        # with a dash or a value that does, then we've found the error
        args_array = @command_array.dup
        while args_array.size > 0
          opt = args_array.delete_at(0)
          val = (args_array.size > 0 ? args_array.delete_at(0) : nil)
          # make sure the option starts with a dash (and throw an error if it does not)
          unless /^-.*$/.match(opt)
            set_command_help_text(option_items)
            raise ProjectHanlon::Error::Slice::InputError, "Missing option for value '#{opt}'"
          end
          # make we found a value and that the value doesn't start with a dash (and throw an error if it does)
          unless val && /^[^-].*$/.match(val)
            set_command_help_text(option_items)
            raise ProjectHanlon::Error::Slice::InputError, "Missing value for option '#{opt}'"
          end
        end
        command_hash = Hash[*@command_array]
        template_name = command_hash["-t"] || command_hash["--template"]
        option_items = option_items.map { |option|
          option[:name] == :image_uuid ? (option[:required] = false; option) : option
        } if ["boot_local", "discover_only"].include?(template_name)
        # parse and validate the options that were passed in as part of this
        # subcommand (this method will return a UUID value, if present, and the
        # options map constructed from the @commmand_array)
        tmp, options = parse_and_validate_options(option_items, :require_all, :banner => "hanlon model add (options...)", :width => 40)
        includes_uuid = true if tmp && tmp != "add"
        # check for usage errors (the boolean value at the end of this method
        # call is used to indicate whether the choice of options from the
        # option_items hash must be an exclusive choice)
        check_option_usage(option_items, options, includes_uuid, false)
        optional_yaml_file = options[:optional_yaml]
        template = options[:template]
        label = options[:label]
        image_uuid = options[:image_uuid]
        # use the arguments passed in to create a new model
        model = get_model_using_template_name(template)
        raise ProjectHanlon::Error::Slice::InputError, "Invalid model template [#{template}] " unless model
        # read in the req_metadata_params (either from the YAML file if one was provided
        # or from the CLI, will ask for any parameters required but not provided via the
        # YAML file in the )
        metadata_hash = {}
        begin
          metadata_hash = YAML.load(File.read(optional_yaml_file)) if optional_yaml_file
        rescue Exception => e
          raise ProjectHanlon::Error::Slice::InputError, "Cannot read from options file '#{optional_yaml_file}'"
        end
        req_metadata_params = model.cli_get_metadata_params(metadata_hash)
        raise ProjectHanlon::Error::Slice::UserCancelled, "User cancelled model creation" unless req_metadata_params
        # setup the POST (to create the requested policy) and return the results
        uri = URI.parse @uri_string
        body_hash = {
            "template" => template,
            "label" => label,
            "image_uuid" => image_uuid,
        }
        body_hash["req_metadata_params"] = req_metadata_params
        json_data = body_hash.to_json
        result = hnl_http_post_json_data(uri, json_data)
        print_object_array(hash_array_to_obj_array([result]), "Model Created:")
      end

      def update_model
        @command = :update_model
        includes_uuid = false
        # load the appropriate option items for the subcommand we are handling
        option_items = command_option_data(:update)
        # parse and validate the options that were passed in as part of this
        # subcommand (this method will return a UUID value, if present, and the
        # options map constructed from the @commmand_array)
        model_uuid, options = parse_and_validate_options(option_items, :require_one, :banner => "hanlon model update UUID (options...)", :width => 34)
        includes_uuid = true if model_uuid
        # check for usage errors (the boolean value at the end of this method
        # call is used to indicate whether the choice of options from the
        # option_items hash must be an exclusive choice)
        check_option_usage(option_items, options, includes_uuid, false)
        label = options[:label]
        image_uuid = options[:image_uuid]
        change_metadata = options[:change_metadata]
        optional_yaml_file = (change_metadata && change_metadata.is_a?(String) ? change_metadata : nil)
        # now, use the values that were passed in to update the indicated model
        uri = URI.parse(@uri_string + '/' + model_uuid)
        # and get the results of the appropriate RESTful request using that URI
        result = hnl_http_get(uri)
        model = hash_to_obj(result)
        # if the user requested a change to the meta-data hash associated with the
        # indicated model, then gather that new meta-data from the user
        req_metadata_params = nil
        if change_metadata
          metadata_hash = {}
          begin
            metadata_hash = YAML.load(File.read(optional_yaml_file)) if optional_yaml_file
          rescue Exception => e
            raise ProjectHanlon::Error::Slice::InputError, "Cannot read from options file '#{optional_yaml_file}'"
          end
          req_metadata_params = model.cli_get_metadata_params(metadata_hash)
          raise ProjectHanlon::Error::Slice::UserCancelled, "User cancelled model update" unless req_metadata_params
        end
        # add properties passed in from command line to the json_data
        # hash that we'll be passing in as the body of the request
        body_hash = {}
        body_hash["label"] = label if label
        body_hash["image_uuid"] = image_uuid if image_uuid
        if change_metadata
          body_hash["req_metadata_params"] = req_metadata_params
        end
        json_data = body_hash.to_json
        # setup the PUT (to update the indicated policy) and return the results
        result = hnl_http_put_json_data(uri, json_data)
        print_object_array(hash_array_to_obj_array([result]), "Model Updated:")
      end

      def remove_all_models
        @command = :remove_all_models
        raise ProjectHanlon::Error::Slice::MethodNotAllowed, "This method has been deprecated"
      end

      def remove_model_by_uuid
        @command = :remove_model_by_uuid
        # the UUID was the last "previous argument"
        model_uuid = @prev_args.peek(0)
        # setup the DELETE (to remove the indicated model) and return the results
        uri = URI.parse @uri_string + "/#{model_uuid}"
        result = hnl_http_delete(uri)
        puts result
      end

      def get_image(image_uuid)
        uri = URI.parse ProjectHanlon.config.hanlon_uri + ProjectHanlon.config.websvc_root + "/image/#{image_uuid}"
        # and get the results of the appropriate RESTful request using that URI
        result = hnl_http_get(uri)
        # finally, return the result (as an image object)
        image = hash_to_obj(result)
        if image && (image.class != Array || image.length > 0)
          return image
        end
        nil
      end

      def get_model_using_template_name(template_name)
        get_child_types(SLICE_MODEL_PREFIX).each { |template|
          return template if template.name.to_s == template_name
        }
        nil
      end

      def set_command_help_text(option_items)
        options = {}
        # Get our optparse object passing our options hash, option_items hash, and our banner
        optparse_options = {:banner => "hanlon model add (options...)", :width => 40}
        optparse_options[:options_items] = option_items
        optparse = get_options(options, optparse_options)
        # set the command help text to the string output from optparse
        @command_help_text << optparse.to_s
      end

    end
  end
end
