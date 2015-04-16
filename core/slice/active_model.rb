require "json"
require "policy/base"

# Root ProjectHanlon namespace
module ProjectHanlon
  class Slice

    # ProjectHanlon Slice Active_Model
    class ActiveModel < ProjectHanlon::Slice

      def initialize(args)
        super(args)
        @hidden     = false
        @policies   = ProjectHanlon::Policies.instance
        @uri_string = ProjectHanlon.config.hanlon_uri + ProjectHanlon.config.websvc_root + '/active_model'
      end

      def slice_commands
        # get the slice commands map for this slice (based on the set of
        # commands that are typical for most slices)
        commands = get_command_map(
            "active_model_help",
            "get_all_active_models",
            "get_active_model_by_uuid",
            nil,
            nil,
            "remove_all_active_models",
            "remove_active_model_by_uuid")
        # and add a few more commands specific to this slice; first remove the default line that
        # handles the lines where a UUID is passed in as part of a "get_active_model_by_uuid" command
        tmp_map = commands[:get].delete(/^(?!^(all|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/)
        # then add a slightly different version of this line back in; one that incorporates
        # the other flags we might pass in as part of a "get_all_nodes" or "get_node_by_uuid" command
        commands[:get][/^(?!^(all|\-\-hw_id|\-i|\-\-policy|\-o|\-\-node_uuid|\-n|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/] = tmp_map
        # and modify one of those entries to ensure that we get into that method, even if both
        # a UUID and a :hw_id, a :node_uuid, or both were passed in; will let us handle the resulting
        # error more cleanly
        commands[:get][/^(?!^(all|\-\-hw_id|\-i|\-\-policy|\-o|\-\-node_uuid|\-n|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/][:else] = "get_active_model_by_uuid"
        # add in a couple of lines to that handle those flags properly
        commands[:get][["-o", "--policy"]] = "get_all_active_models"
        [["-i", "--hw_id"],["-n", "--node_uuid"]].each { |val|
          commands[:get][val] = "get_active_model_by_uuid"
        }
        # next, remove the default line that handles the commands where the user is wanting to
        # remove an active_model instance by (active_model) uuid
        tmp_map = commands[:remove].delete(/^(?!^(all|\-\-help|\-h)$)\S+$/)
        # then add a slightly different version of this line back in; one that incorporates
        # the other flags we might pass in as part of a "remove_active_model_by_uuid" command
        commands[:remove][/^(?!^(all|\-\-hw_id|\-i|\-\-policy|\-o|\-\-node_uuid|\-n|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/] = tmp_map
        # and modify one of those entries to ensure that we get into that method, even if both
        # a UUID and a :hw_id, a :node_uuid, or both were passed in; will let us handle the resulting
        # error more cleanly
        commands[:remove][/^(?!^(all|\-\-hw_id|\-i|\-\-policy|\-o|\-\-node_uuid|\-n|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/][:else] = "remove_active_model_by_uuid"
        # and add in a couple of lines that handle these flags properly
        [["-i", "--hw_id"], ["-n", "--node_uuid"]].each { |val|
          commands[:remove][val] = "remove_active_model_by_uuid"
        }
        # finally, add in a couple of lines to properly handle "get_active_model_logs" commands
        commands[:logs] = "get_logs"
        commands[:logs][/^(?!^(\-\-hw_id|\-i|\-\-node_uuid|\-n|\{\}|\{.*\}|nil)$)\S+$/] = "get_active_model_logs"
        commands[:get][/^(?!^(all|\-\-hw_id|\-i|\-\-policy|\-o|\-\-node_uuid|\-n|\-\-help|\-h|\{\}|\{.*\}|nil)$)\S+$/][:logs] = "get_active_model_logs"

        commands
      end

      def active_model_help
        if @prev_args.length > 1
          command = @prev_args.peek(1)
          begin
            # load the option items for this command (if they exist) and print them
            option_items = command_option_data(command)
            # need to handle the usage for the 'get' and and "remove" commands a bit differently;
            # the active_model can be identified it's UUID or by either the UUID or the Hardware ID
            # of the node bound to it, but only one (so the UUID is optional, but required if neither
            # the UUID nor the Hardware ID of the bound node are included)
            optparse_options = { }
            optparse_options[:banner] = "hanlon active_model_help #{command} [UUID] (options...)" if ['get', 'remove'].include?(command)
            optparse_options[:note] = "Note; one (and only one) of the active_model UUID, the HW_ID of the bound node,\n\t  or the UUID of the bound node must be provided" if ['get', 'remove'].include?(command)
            print_command_help(command, option_items, optparse_options)
            return
          rescue
          end
        end
        # if here, then either there are no specific options for the current command or we've
        # been asked for generic help, so provide generic help
        puts get_active_model_help
      end

      def get_active_model_help
        # if here, then either there are no specific options for the current command or we've
        # been asked for generic help, so provide generic help
        puts "Active Model Slice: used to view active models or active model logs (and to remove active models).".red
        puts "Active Model Commands:".yellow
        puts "\thanlon active_model [get] [all]                            " + "View all active models".yellow
        puts "\thanlon active_model [get] (UUID) [logs]                    " + "View specific active model (log)".yellow
        puts "\thanlon active_model [get] --node_uuid,-n NODE_UUID [logs]  " + "View (log for) active_model bound to node".yellow
        puts "\thanlon active_model [get] --hw_id,-i HW_ID [logs]          " + "View (log for) active_model bound to node".yellow
        puts "\thanlon active_model logs                                   " + "Prints an aggregate view of active model logs".yellow
        puts "\thanlon active_model remove (UUID)                          " + "Remove specific active model".yellow
        puts "\thanlon active_model remove --node_uuid,-n NODE_UUID        " + "Remove active_model bound to node".yellow
        puts "\thanlon active_model remove --hw_id,-i HW_ID                " + "Remove active_model bound to node".yellow
        puts "\thanlon active_model --help|-h                              " + "Display this screen".yellow
      end

      def all_command_option_data
        {
            :get_all => [
                { :name        => :policy,
                  :default     => nil,
                  :short_form  => '-o',
                  :long_form   => '--policy POLICY_UUID',
                  :description => 'Show only nodes bound by this policy instance',
                  :uuid_is     => 'not_allowed',
                  :required    => false
                }
            ],
            :get => [
                { :name        => :hw_id,
                  :default     => nil,
                  :short_form  => '-i',
                  :long_form   => '--hw_id HW_ID',
                  :description => 'The HW_ID of the node bound to the active_model instance',
                  :uuid_is     => 'required',
                  :required    => false
                },
                { :name        => :node_uuid,
                  :default     => nil,
                  :short_form  => '-n',
                  :long_form   => '--node_uuid NODE_UUID',
                  :description => 'The UUID of the node bound to the active_model instance',
                  :uuid_is     => 'required',
                  :required    => false
                }
            ],
            :remove => [
                { :name        => :hw_id,
                  :default     => nil,
                  :short_form  => '-i',
                  :long_form   => '--hw_id HW_ID',
                  :description => 'The HW_ID of the node bound to the active_model to remove',
                  :uuid_is     => 'required',
                  :required    => false
                },
                { :name        => :node_uuid,
                  :default     => nil,
                  :short_form  => '-n',
                  :long_form   => '--node_uuid NODE_UUID',
                  :description => 'The UUID of the node bound to the active_model to remove',
                  :uuid_is     => 'required',
                  :required    => false
                },
            ]
        }.freeze
      end

      def get_all_active_models
        @command = :get_all_active_models
        # check for cases where we read too far into the @command_array; if
        # the argument at the top of the @prev_args stack starts with a '-'
        # or a '--', then push it back onto the end of the @command_array
        # for further parsing
        last_parsed = @prev_args.peek
        if last_parsed && /^(\-|\-\-).+$/.match(last_parsed)
          @command_array.unshift(last_parsed)
          @prev_args.pop
        end
        # load the appropriate option items for the subcommand we are handling
        option_items = command_option_data(:get_all)
        # parse and validate the options that were passed in as part of this
        # subcommand (this method will return a UUID value, if present, and the
        # options map constructed from the @commmand_array)
        tmp, options = parse_and_validate_options(option_items, :require_all, :banner => "hanlon active_model [get] [all] (options...)")
        includes_uuid = true if tmp && !['get','all'].include?(tmp)
        # check for usage errors (the boolean value at the end of this method
        # call is used to indicate whether the choice of options from the
        # option_items hash must be an exclusive choice)
        check_option_usage(option_items, options, includes_uuid, false)
        # construct the query, and return the results
        uri_string = @uri_string
        # add in the policy UUID, if one was provided
        policy_uuid = options[:policy]
        add_field_to_query_string(uri_string, "policy", policy_uuid) if policy_uuid && !policy_uuid.empty?
        # get the nodes from the RESTful API (as an array of objects)
        uri = URI.parse uri_string
        result = hnl_http_get(uri)
        unless result.blank?
          # convert it to a sorted array of objects (from an array of hashes)
          sort_fieldname = 'node_uuid'
          result = hash_array_to_obj_array(expand_response_with_uris(result), sort_fieldname)
        end
        # and print the result
        print_object_array(result, "Active Models:", :style => :table)
      end

      def get_active_model_by_uuid
        @command = :get_active_model_by_uuid
        # check for cases where we read too far into the @command_array; if
        # the argument at the top of the @prev_args stack starts with a '-'
        # or a '--', then push it back onto the end of the @command_array
        # for further parsing
        last_parsed = @prev_args.peek
        if last_parsed && /^(\-|\-\-).+$/.match(last_parsed)
          @command_array.unshift(last_parsed)
          @prev_args.pop
          if @command_array[-1] == "logs"
            # if here, then the user was actually looking for logs but
            # the parsing brought us into the wrong method; redirect to
            # the right one
            return get_active_model_logs
          end
        end
        # load the appropriate option items for the subcommand we are handling
        option_items = command_option_data(:get)
        # parse and validate the options that were passed in as part of this
        # subcommand (this method will return a UUID value, if present, and the
        # options map constructed from the @commmand_array)
        tmp, options = parse_and_validate_options(option_items, :require_all, :banner => "hanlon node [get] [UUID] (options...)",
                                                  :note => "Note; one (and only one) of the active_model UUID, the HW_ID of the bound node,\n\t  or the UUID of the bound node must be provided")
        active_model_uuid = ( tmp && tmp != "get" ? tmp : nil)
        # remove any missing (non-specified) fields from the options available (the :hw_id and :node_uuid
        # options to this command)
        hw_id = options[:hw_id]
        node_uuid = options[:node_uuid]
        # throw an error if more than one of the active_model_uuid, :hw_id or
        # :node_uuid parameters were provided in this command
        num_identifier_fields = [active_model_uuid, node_uuid, hw_id].select { |val| val }.size
        raise ProjectHanlon::Error::Slice::InputError, "Usage Error: one (and only one) node identifier can be used select an active_model" if num_identifier_fields > 1
        # check for usage errors (the boolean value at the end of this method call is used to
        # indicate whether the choice of options from the option_items hash must be an
        # exclusive choice); will assume that the UUID of the node was provided (or that
        # an equivalent :hw_id option was provided, if both of these parameters are missing
        # we wouldn't gotten this far), so the third argument is set to true
        check_option_usage(option_items, options, true, false)
        # save the @uri_string to a local variable
        uri_string = @uri_string
        # if a active_model_uuid was provided, then add it to the uri_string
        uri_string << "/#{active_model_uuid}" if active_model_uuid
        # if either the bound node's UUID or the hardware ID was provided, add them to the
        # query string
        add_field_to_query_string(uri_string, "node_uuid", node_uuid) if node_uuid && !node_uuid.empty?
        add_field_to_query_string(uri_string, "hw_id", hw_id) if hw_id && !hw_id.empty?
        uri = URI.parse(uri_string)
        # and get the results of the appropriate RESTful request using that URI
        result = hnl_http_get(uri)
        # finally, based on the options selected, print the results
        print_object_array(hash_array_to_obj_array([result]), "Active Model:")
      end

      def get_active_model_logs
        @command = :get_active_model_logs
        # if there are still arguments left, then user was looking for the logs for
        # a specific active_model instance (based on the hardware_id or node_uuid
        # of the node that active_model is bound to), to print that
        if @command_array.size == 3
          node_sel_flag = @command_array[0]
          hardware_id = @command_array[1] if ['--hw_id','-i'].include?(node_sel_flag)
          node_uuid = @command_array[1] if ['--node_uuid','-n'].include?(node_sel_flag)
          if hardware_id || node_uuid
            uri = URI.parse(@uri_string + "?hw_id=#{hardware_id}") if hardware_id
            uri = URI.parse(@uri_string + "?node_uuid=#{node_uuid}") if node_uuid
            # and get the results of the appropriate RESTful request using that URI
            result = hnl_http_get(uri)
          else
            raise ProjectHanlon::Error::Slice::SliceCommandParsingFailed,
                  "Unexpected arguments found in command #{@command} -> #{@command_array.inspect}"
          end
        elsif @command_array.size == 0
          # if we get this far, then the user was looking for the active_model logs for
          # a specific active_model (based on the UUID of that active_model instance);
          # in that case, the UUID is the top element of the @prev_args stack
          uuid = @prev_args.peek(1)
          # catches the case where a UUID was not included
          return get_logs unless uuid
          # setup a URI to retrieve the active_model in question
          uri = URI.parse(@uri_string + '/' + uuid)
          # and get the results of the appropriate RESTful request using that URI
          result = hnl_http_get(uri)
        else
          raise ProjectHanlon::Error::Slice::SliceCommandParsingFailed,
                "Unexpected arguments found in command #{@command} -> #{@command_array.inspect}"
        end
        # convert the result into an active_model instance, then use that instance to
        # print out the logs for that instance
        active_model_ref = hash_to_obj(result)
        print_object_array(active_model_ref.print_log, "Active Model Logs (#{active_model_ref.uuid}):", :style => :table)
      end

      def remove_all_active_models
        @command = :remove_all_active_models
        raise ProjectHanlon::Error::Slice::MethodNotAllowed, "This method has been deprecated"
      end

      def remove_active_model_by_uuid
        @command = :remove_active_model_by_uuid
        # check for cases where we read too far into the @command_array; if
        # the argument at the top of the @prev_args stack starts with a '-'
        # or a '--', then push it back onto the end of the @command_array
        # for further parsing
        last_parsed = @prev_args.peek
        if last_parsed && /^(\-|\-\-).+$/.match(last_parsed)
          @command_array.unshift(last_parsed)
          @prev_args.pop
        end
        # load the appropriate option items for the subcommand we are handling
        option_items = command_option_data(:remove)
        # parse and validate the options that were passed in as part of this
        # subcommand (this method will return a UUID value, if present, and the
        # options map constructed from the @commmand_array)
        tmp, options = parse_and_validate_options(option_items, :require_all, :banner => "hanlon node remove [UUID] (options...)",
                                                  :note => "Note; one (and only one) of the active_model UUID, the HW_ID of the bound node,\n\t  or the UUID of the bound node must be provided")
        active_model_uuid = ( tmp && tmp != "remove" ? tmp : nil)
        # remove any missing (non-specified) fields from the options available (the :hw_id and :node_uuid
        # options to this command)
        hw_id = options[:hw_id]
        node_uuid = options[:node_uuid]
        # throw an error if more than one of the active_model_uuid, :hw_id or
        # :node_uuid parameters were provided in this command
        num_identifier_fields = [active_model_uuid, node_uuid, hw_id].select { |val| val }.size
        raise ProjectHanlon::Error::Slice::InputError, "Usage Error: one (and only one) node identifier can be used select an active_model" if num_identifier_fields > 1
        # check for usage errors (the boolean value at the end of this method call is used to
        # indicate whether the choice of options from the option_items hash must be an
        # exclusive choice); will assume that the UUID of the node was provided (or that
        # an equivalent :hw_id option was provided, if both of these parameters are missing
        # we wouldn't gotten this far), so the third argument is set to true
        check_option_usage(option_items, options, true, false)
        # save the @uri_string to a local variable
        uri_string = @uri_string
        # if a active_model_uuid was provided, then add it to the uri_string
        uri_string << "/#{active_model_uuid}" if active_model_uuid
        # if either the bound node's UUID or the hardware ID was provided, add them to the
        # query string
        add_field_to_query_string(uri_string, "node_uuid", node_uuid) if node_uuid && !node_uuid.empty?
        add_field_to_query_string(uri_string, "hw_id", hw_id) if hw_id && !hw_id.empty?
        uri = URI.parse(uri_string)
        result = hnl_http_delete(uri)
        puts result
      end

      def get_logs
        @command = :get_logs
        uri = URI.parse(@uri_string + '/logs')
        # and get the results of the appropriate RESTful request using that URI
        result = hnl_http_get(uri)
        # finally, based on the options selected, print the results
        lcl_slice_obj_ref = ProjectHanlon::PolicyTemplate::Base.new({})
        print_object_array(lcl_slice_obj_ref.print_log_all(result), "All Active Model Logs:", :style => :table)
      end

    end
  end
end


