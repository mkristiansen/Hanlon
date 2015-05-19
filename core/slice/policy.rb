require 'data'
require 'utility'
require 'policies'
require 'json'

# Root namespace for policy objects
# used to find them in object space for type checking
POLICY_PREFIX = "ProjectHanlon::PolicyTemplate::"

# Root ProjectHanlon namespace
module ProjectHanlon
  class Slice

    # ProjectHanlon Slice Policy (NEW))
    # Used for policy management
    class Policy < ProjectHanlon::Slice

      # Initializes ProjectHanlon::Slice::Policy including #slice_commands, #slice_commands_help
      # @param [Array] args
      def initialize(args)
        super(args)
        @hidden     = false
        @policies   = ProjectHanlon::Policies.instance
        @uri_string = ProjectHanlon.config.hanlon_uri + ProjectHanlon.config.websvc_root + '/policy'
      end

      def self.additional_fields
        %w"@line_number @bind_counter"
      end

      def slice_commands
        # get the slice commands map for this slice (based on the set
        # of commands that are typical for most slices)
        commands = get_command_map(
            "policy_help",
            "get_all_policies",
            "get_policy_by_uuid",
            "add_policy",
            "update_policy",
            "remove_all_policies",
            "remove_policy_by_uuid")
        # and add any additional commands specific to this slice
        commands[:get].delete(/^(?!^(all|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/)
        commands[:get][:else] = "get_policy_by_uuid"
        commands[:get][[/^(temp|template|templates|types)$/]] = "get_policy_templates"
        commands
      end

      def policy_help
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
        # if here, then either there are no specific options for the current command or we've
        # been asked for generic help, so provide generic help
        puts get_policy_help
      end

      def get_policy_help
        return ["Policy Slice:".red,
                "Used to view, create, update, and remove policies.".red,
                "Policy commands:".yellow,
                "\thanlon policy [get] [all]                      " + "View all policies".yellow,
                "\thanlon policy [get] (UUID)                     " + "View a specific policy".yellow,
                "\thanlon policy [get] templates|types            " + "View available policy templates".yellow,
                "\thanlon policy add (options...)                 " + "Create a new policy".yellow,
                "\thanlon policy update (UUID) (options...)       " + "Update an existing policy".yellow,
                "\thanlon policy remove (UUID)|all                " + "Remove existing policy(s)".yellow,
                "\thanlon policy --help|-h                        " + "Display this screen".yellow].join("\n")
      end

      def all_command_option_data
        {
            :add  =>  [
                { :name        => :template,
                  :default     => nil,
                  :short_form  => '-p',
                  :long_form   => '--template TEMPLATE_NAME',
                  :description => 'The policy template name to use.',
                  :uuid_is     => 'not_allowed',
                  :required    => true
                },
                { :name        => :label,
                  :default     => nil,
                  :short_form  => '-l',
                  :long_form   => '--label POLICY_LABEL',
                  :description => 'A label to name this policy.',
                  :uuid_is     => 'not_allowed',
                  :required    => true
                },
                { :name        => :model_uuid,
                  :default     => nil,
                  :short_form  => '-m',
                  :long_form   => '--model-uuid MODEL_UUID',
                  :description => 'The model to attach to the policy.',
                  :uuid_is     => 'not_allowed',
                  :required    => true
                },
                { :name        => :tags,
                  :default     => nil,
                  :short_form  => '-t',
                  :long_form   => '--tags TAG{,TAG,TAG}',
                  :description => 'Policy tags. Comma delimited.',
                  :uuid_is     => 'not_allowed',
                  :required    => true
                },
                { :name        => :broker_uuid,
                  :default     => 'none',
                  :short_form  => '-b',
                  :long_form   => '--broker-uuid BROKER_UUID',
                  :description => 'The broker to attach to the policy [default: none].',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                },
                { :name        => :line_number,
                  :default     => nil,
                  :short_form  => '-n',
                  :long_form   => '--number LINE_NO',
                  :description => 'Line number in policy rules table [default: nil].',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                },
                { :name        => :enabled,
                  :default     => false,
                  :short_form  => '-e',
                  :long_form   => '--enabled ENABLED_FLAG',
                  :description => 'Should policy be enabled (true|false) [default: false]?',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                },
                { :name        => :maximum,
                  :default     => '0',
                  :short_form  => '-x',
                  :long_form   => '--maximum MAXIMUM_COUNT',
                  :description => 'Sets the policy maximum count for nodes [default: 0].',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                }
            ],
            :update  =>  [
                { :name        => :label,
                  :default     => nil,
                  :short_form  => '-l',
                  :long_form   => '--label POLICY_LABEL',
                  :description => 'A label to name this policy.',
                  :uuid_is     => 'required',
                  :required    => true
                },
                { :name        => :model_uuid,
                  :default     => nil,
                  :short_form  => '-m',
                  :long_form   => '--model-uuid MODEL_UUID',
                  :description => 'The model to attached to the policy.',
                  :uuid_is     => 'required',
                  :required    => true
                },
                { :name        => :broker_uuid,
                  :default     => nil,
                  :short_form  => '-b',
                  :long_form   => '--broker-uuid BROKER_UUID',
                  :description => 'The broker attached to the policy [default: none].',
                  :uuid_is     => 'required',
                  :required    => true
                },
                { :name        => :tags,
                  :default     => nil,
                  :short_form  => '-t',
                  :long_form   => '--tags TAG{,TAG,TAG}',
                  :description => 'Policy tags. Comma delimited.',
                  :uuid_is     => 'required',
                  :required    => true
                },
                { :name        => :enabled,
                  :default     => nil,
                  :short_form  => '-e',
                  :long_form   => '--enabled ENABLED_FLAG',
                  :description => 'Should policy be enabled (true|false) [default: false]?',
                  :uuid_is     => 'required',
                  :required    => true
                },
                { :name        => :maximum,
                  :default     => nil,
                  :short_form  => '-x',
                  :long_form   => '--maximum MAXIMUM_COUNT',
                  :description => 'Sets the policy maximum count for nodes [default: 0].',
                  :uuid_is     => 'required',
                  :required    => true
                },
                { :name        => :new_line_number,
                  :default     => nil,
                  :short_form  => '-n',
                  :long_form   => '--new-line-number NEW_NUM',
                  :description => 'New line number in policy rules table.',
                  :uuid_is     => 'required',
                  :required    => true
                }
            ]
        }.freeze
      end

      # Returns all policy instances
      def get_all_policies
        @command = :get_all_policies
        raise ProjectHanlon::Error::Slice::SliceCommandParsingFailed,
              "Unexpected arguments found in command #{@command} -> #{@command_array.inspect}" if @command_array.length > 0
        # get the policies from the RESTful API (as an array of objects)
        uri = URI.parse @uri_string
        result = hnl_http_get(uri)
        unless result.blank?
          # convert it to a sorted array of objects (from an array of hashes)
          sort_fieldname = 'line_number'
          result = hash_array_to_obj_array(expand_response_with_uris(result), sort_fieldname)
        end
        # and print the result
        print_object_array(result, "Policies:", :style => :table)
      end

      # Returns the policy templates available
      def get_policy_templates
        @command = :get_policy_templates
        # get the policy templates from the RESTful API (as an array of objects)
        uri = URI.parse @uri_string + '/templates'
        result = hnl_http_get(uri)
        unless result.blank?
          # convert it to a sorted array of objects (from an array of hashes)
          sort_fieldname = 'template'
          result = hash_array_to_obj_array(expand_response_with_uris(result), sort_fieldname)
        end
        # and print the result
        print_object_array(result, "Policy Templates:", :style => :table)
      end

      def get_policy_by_uuid
        @command = :get_policy_by_uuid
        # the UUID is the first element of the @command_array
        policy_uuid = @command_array.first
        # setup the proper URI depending on the options passed in
        uri = URI.parse(@uri_string + '/' + policy_uuid)
        # and get the results of the appropriate RESTful request using that URI
        result = hnl_http_get(uri)
        # finally, based on the options selected, print the results
        print_object_array(hash_array_to_obj_array([result]), "Policy:")
      end

      def add_policy
        @command = :add_policy
        includes_uuid = false
        # load the appropriate option items for the subcommand we are handling
        option_items = command_option_data(:add)
        # parse and validate the options that were passed in as part of this
        # subcommand (this method will return a UUID value, if present, and the
        # options map constructed from the @commmand_array)
        tmp, options = parse_and_validate_options(option_items, :require_all, :banner => "hanlon policy add (options...)")
        includes_uuid = true if tmp && tmp != "add"
        # check for usage errors (the boolean value at the end of this method
        # call is used to indicate whether the choice of options from the
        # option_items hash must be an exclusive choice)
        check_option_usage(option_items, options, includes_uuid, false)
        # assign default values for (missing) optional parameters
        options[:maximum] = "0" if !options[:maximum]
        options[:broker_uuid] = "none" if !options[:broker_uuid]
        options[:enabled] = "false" if !options[:enabled]
        # setup the POST (to create the requested policy) and return the results
        uri = URI.parse @uri_string
        json_data = {
            "template" => options[:template],
            "label" => options[:label],
            "model_uuid" => options[:model_uuid],
            "tags" => options[:tags],
            "broker_uuid" => options[:broker_uuid],
            "line_number" => options[:line_number],
            "enabled" => options[:enabled],
            "maximum" => options[:maximum]
        }.to_json
        result = hnl_http_post_json_data(uri, json_data)
        print_object_array(hash_array_to_obj_array([result]), "Policy Created:")
      end

      def update_policy
        @command = :update_policy
        includes_uuid = false
        # load the appropriate option items for the subcommand we are handling
        option_items = command_option_data(:update)
        # parse and validate the options that were passed in as part of this
        # subcommand (this method will return a UUID value, if present, and the
        # options map constructed from the @commmand_array)
        policy_uuid, options = parse_and_validate_options(option_items, :require_one, :banner => "hanlon policy update UUID (options...)")
        includes_uuid = true if policy_uuid
        # check for usage errors (the boolean value at the end of this method
        # call is used to indicate whether the choice of options from the
        # option_items hash must be an exclusive choice)
        check_option_usage(option_items, options, includes_uuid, false)
        # add properties passed in from command line to the json_data
        # hash that we'll be passing in as the body of the request
        body_hash = {}
        body_hash["label"] = options[:label] if options[:label]
        body_hash["model_uuid"] = options[:model_uuid] if options[:model_uuid]
        body_hash["tags"] = options[:tags] if options[:tags]
        body_hash["broker_uuid"] = options[:broker_uuid] if options[:broker_uuid]
        body_hash["enabled"] = options[:enabled] if options[:enabled]
        body_hash["maximum"] = options[:maximum] if options[:maximum]
        body_hash["new_line_number"] = options[:new_line_number] if options[:new_line_number]
        json_data = body_hash.to_json
        # setup the PUT (to update the indicated policy) and return the results
        uri = URI.parse @uri_string + "/#{policy_uuid}"
        result = hnl_http_put_json_data(uri, json_data)
        print_object_array(hash_array_to_obj_array([result]), "Policy Updated:")
      end

      def remove_all_policies
        @command = :remove_all_policies
        raise ProjectHanlon::Error::Slice::MethodNotAllowed, "This method has been deprecated"
      end

      def remove_policy_by_uuid
        @command = :remove_policy_by_uuid
        # the UUID was the last "previous argument"
        policy_uuid = @prev_args.peek(0)
        # setup the DELETE (to update the remove the indicated policy) and return the results
        uri = URI.parse @uri_string + "/#{policy_uuid}"
        result = hnl_http_delete(uri)
        puts result
      end

    end
  end
end
