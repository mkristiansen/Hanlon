#

require 'json'
require 'api_utils'
require 'rubyipmi'

module Hanlon
  module WebService
    module Node

      class APIv1 < Grape::API

        version :v1, :using => :path, :vendor => "hanlon"
        format :json
        default_format :json
        SLICE_REF = ProjectHanlon::Slice::Node.new([])

        rescue_from ProjectHanlon::Error::Slice::InvalidUUID,
                    ProjectHanlon::Error::Slice::InvalidCommand,
                    ProjectHanlon::Error::Slice::MissingArgument,
                    ProjectHanlon::Error::Slice::InputError,
                    Grape::Exceptions::Validation do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from ProjectHanlon::Error::Slice::CouldNotRegisterNode do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(404, e.class.name, e.message).to_json,
              404,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from :all do |e|
          #raise e
          Rack::Response.new(
              Hanlon::WebService::Response.new(500, e.class.name, e.message).to_json,
              500,
              { "Content-type" => "application/json" }
          )
        end

        helpers do

          def content_type_header
            settings[:content_types][env['api.format']]
          end

          def api_format
            env['api.format']
          end

          def is_uuid?(string_)
            string_ =~ /^[A-Za-z0-9]{1,22}$/
          end

          def validate_param(param)
            Hanlon::WebService::Utils::validate_parameter(param)
          end

          def slice_success_response(slice, command, response, options = {})
            Hanlon::WebService::Utils::hnl_slice_success_response(slice, command, response, options)
          end

          def slice_success_object(slice, command, response, options = {})
            Hanlon::WebService::Utils::hnl_slice_success_object(slice, command, response, options)
          end

          def filter_hnl_response(response, filter_str)
            Hanlon::WebService::Utils::filter_hnl_response(response, filter_str)
          end

          def get_power_status(ipmi_args, node, options_hash = { })
            # extract the username and password from the input ipmi_args hash
            ipmi_username = ipmi_args['ipmi_username']
            ipmi_password = ipmi_args['ipmi_password']
            # attempt to get the IP address of the BMC from the facts reported back to Hanlon by the Microkernel
            ipmi_ip_address = node.attributes_hash['mk_ipmi_IP_Address']
            # if we didn't find that IP address in the list of facts for this node, then throw
            # an error (you can't get the power status if the node doesn't have an attached BMC)
            raise ProjectHanlon::Error::Slice::CommandFailed, "BMC for node with UUID [#{node.uuid}] does not exist; power state cannot be determined" unless ipmi_ip_address
            # if we get this far, then grab the IPMI username, password, and preferred IPMI command
            # (freeipmi, ipmitool or, if unspecified, whichever is found first) from the server configuration
            config_hash = $config.to_hash
            config_hash.keys.each{ |key| config_hash.store(key[1..-1], config_hash.delete(key)) }
            ipmi_username = config_hash['ipmi_username'] unless ipmi_username
            ipmi_password = config_hash['ipmi_password'] unless ipmi_password
            ipmi_utility = config_hash['ipmi_utility']
            begin
              if options_hash.empty?
                conn = Rubyipmi.connect(ipmi_username, ipmi_password, ipmi_ip_address, ipmi_utility)
              else
                conn = Rubyipmi.connect(ipmi_username, ipmi_password, ipmi_ip_address, ipmi_utility, options_hash)
              end
              current_power_status = conn.chassis.power.status
            rescue RuntimeError => e
              raise ProjectHanlon::Error::Slice::CommandFailed, "IPMI power command '#{power_command}' failed with error '#{e.message}'"
            end
            raise ProjectHanlon::Error::Slice::CommandFailed, "BMC command failed; power state cannot be determined" unless current_power_status
            slice_success_response(SLICE_REF, :get_node_powerstatus, {'UUID' => node.uuid, 'BMC IP' => ipmi_ip_address, 'Status' => current_power_status}, :success_type => :generic)
          end

          def run_power_cmd(ipmi_args, node, options_hash = { })
            # extract the username, password and power command to apply
            # from the input ipmi_args hash
            ipmi_username = ipmi_args['ipmi_username']
            ipmi_password = ipmi_args['ipmi_password']
            power_command = ipmi_args['power_command']
            # attempt to get the IP address of the BMC from the facts reported back to Hanlon by the Microkernel
            ipmi_ip_address = node.attributes_hash['mk_ipmi_IP_Address']
            # if we didn't find that IP address in the list of facts for this node, then throw
            # an error (you can't get the power status if the node doesn't have an attached BMC)
            raise ProjectHanlon::Error::Slice::CommandFailed, "BMC for node with UUID [#{node.uuid}] does not exist; power state cannot be controlled through node slice" unless ipmi_ip_address
            # check the value of the power_command, throw an error if it's unrecognized
            unless ['on','off','reset','cycle','softShutdown'].include?(power_command)
              raise ProjectHanlon::Error::Slice::CommandFailed, "Unrecognized power command [#{power_command}]; valid values are 'on', 'off', 'reset', 'cycle' or 'softShutdown'"
            end
            # if we get this far, then grab the IPMI username, password, and preferred IPMI command
            # (freeipmi, ipmitool or, if unspecified, whichever is found first) from the server configuration
            config_hash = $config.to_hash
            config_hash.keys.each{ |key| config_hash.store(key[1..-1], config_hash.delete(key)) }
            ipmi_username = config_hash['ipmi_username'] unless ipmi_username
            ipmi_password = config_hash['ipmi_password'] unless ipmi_password
            ipmi_utility = config_hash['ipmi_utility']
            begin
              if options_hash.empty?
                conn = Rubyipmi.connect(ipmi_username, ipmi_password, ipmi_ip_address, ipmi_utility)
              else
                conn = Rubyipmi.connect(ipmi_username, ipmi_password, ipmi_ip_address, ipmi_utility, options_hash)
              end
              cmd_status = conn.chassis.power.command(power_command)
            rescue RuntimeError => e
              raise ProjectHanlon::Error::Slice::CommandFailed, "IPMI power command '#{power_command}' failed with error '#{e.message}'"
            end
            raise ProjectHanlon::Error::Slice::CommandFailed, "IPMI power command '#{power_command}' failed against BMC '#{ipmi_ip_address}' using '#{ipmi_utility}'" unless cmd_status
            slice_success_response(SLICE_REF, :update_node_powerstatus, {'UUID' => node.uuid, 'BMC IP' => ipmi_ip_address, 'Status' => power_command}, :success_type => :generic)
          end

          # used to set and cancel rebinding actions associated with a particular node
          def set_rebinding_action(node, action)
            # check the value of the action, throw an error if it's unrecognized
            unless ['set','cancel'].include?(action)
              raise ProjectHanlon::Error::Slice::CommandFailed, "Unrecognized rebind action [#{action}]; valid values are 'set' or 'cancel'"
            end
            # check the value of the action, throw an error if the
            # action type is unrecognized
            unless ['set','cancel'].include?(action)
              raise ProjectHanlon::Error::Slice::CommandFailed, "Unrecognized action [#{type}]; valid values are 'set' or 'cancel'"
            end
            # if we get this far, then set a rebinding request for the specified node (or cancel
            # the rebinding request, if any, associated with the specified node)
            if action == 'set'
              response = ProjectHanlon::Engine.instance.add_rebinding_request(node)
            else
              response = ProjectHanlon::Engine.instance.cancel_rebinding_request(node)
            end
            slice_success_response(SLICE_REF, :cancel_node_rebinding, {'UUID' => response.uuid, 'Node UUID' => node.uuid, 'Action' => action}, :success_type => :generic)
          end

        end

        resource :node do

          # GET /node
          # Query registered nodes.
          #   parameters:
          #     optional:
          #       :uuid          | String   | The Hardware ID (SMBIOS UUID) of the node |
          #       :policy        | String   | The Policy UUID to use as a filter        |
          #       :filter_str    | String   | A string to use to filter the results     |
          #
          # Note, the optional 'filter_string' argument shown here must take the form of
          #   a URI-encoded string containing one or more 'name=value' pairs separated by
          #   plus (+) characters. These values will be used to filter the results so that
          #   only objects with the parameter named 'name' having a value that matches 'value'
          #   will be returned in the result.  If the named parameter does not exist in
          #   the list of parameters contained in the object, then an error is thrown.
          desc "Retrieve a list of all node instances"
          params do
            optional :uuid, type: String, desc: "The Hardware ID (SMBIOS UUID) of the node."
            optional :policy, type: String, desc: "The Policy UUID to use as a filter"
            optional :filter_str, type: String, desc: "String used to filter results"
          end
          get do
            uuid = params[:uuid].upcase if params[:uuid]
            policy_uuid = params[:policy]
            filter_str = params[:filter_str]
            raise ProjectHanlon::Error::Slice::InputError, "Usage Error: either a Hardware ID or a Policy UUID can be provided as a filter, but not both" if params[:uuid] && params[:policy]
            raise ProjectHanlon::Error::Slice::InputError, "Usage Error: a Hardware ID cannot be provided when a Filter String is specified" if params[:uuid] && params[:filter_str]
            node_selection_array = []
            if uuid
              # if a Hardware ID was supplied, then return the node with that Hardware ID
              node = ProjectHanlon::Engine.instance.lookup_node_by_hw_id({:uuid => uuid, :mac_id => []})
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with Hardware ID: [#{uuid}]" unless node
              return slice_success_object(SLICE_REF, :get_node_by_hw_id, node, :success_type => :generic)
            elsif policy_uuid
              # first find the policy with that UUID (in case the user only passed in a partial
              # UUID as an argument)
              policy = SLICE_REF.get_object("get_policy_by_uuid", :policy, policy_uuid)
              # otherwise a Policy UUID was supplied, then determine which nodes were bound to
              # active_models by that policy and use them to define a node selection array
              active_models = SLICE_REF.get_object("active_models", :active)
              active_models.each { |active_model|
                node_selection_array << active_model.node_uuid if active_model.root_policy == policy.uuid
              }
            end
            nodes = SLICE_REF.get_object("nodes", :node)
            # if a node selection array was defined, use it to filter the list of nodes returned
            nodes.select! { |node| node_selection_array.include?(node.uuid) } unless node_selection_array.empty?
            success_object = slice_success_object(SLICE_REF, :get_all_nodes, nodes, :success_type => :generic)
            # if a filter_str was provided, apply it here
            success_object['response'] = filter_hnl_response(success_object['response'], filter_str) if filter_str
            # and return the resulting success_object
            success_object
          end       # end GET /node

          resource :power do

            # GET /node/power
            # Query for the power state of a specific node.
            #   parameters:
            #     required:
            #       :hw_id         | String   | The Hardware ID (SMBIOS UUID) of the node.                      |
            #     optional:
            #       :ipmi_username | String   | The username used to access the BMC.                            |
            #       :ipmi_password | String   | The password used to access the BMC.                            |
            #       :ipmi_options  | String   | The options pass when connecting to the BMC (as a JSON string). |
            params do
              requires :hw_id, type: String, desc: "The Hardware ID (SMBIOS UUID) of the node"
              optional :ipmi_username, type: String, desc: "The IPMI username"
              optional :ipmi_password, type: String, desc: "The IPMI password"
              optional :ipmi_options, type: String, desc: "The IPMI connect options (JSON string)"
            end
            get do
              uuid = params[:hw_id].upcase
              node = ProjectHanlon::Engine.instance.lookup_node_by_hw_id({:uuid => uuid, :mac_id => []})
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with Hardware ID: [#{uuid}]" unless node
              ipmi_args = params.select { |key| ['ipmi_username', 'ipmi_password'].include?(key) }
              ipmi_option_string = params[:ipmi_options]
              begin
                options_hash = JSON.parse(ipmi_option_string, {:symbolize_names => true})
              rescue JSON::ParserError => e
                raise ProjectHanlon::Error::Slice::InputError, "IPMI Options String '#{ipmi_option_string}' is not a valid JSON String"
              end
              raise ProjectHanlon::Error::Slice::InputError, "IPMI Options String '#{ipmi_option_string}' is not a JSON Hash" unless options_hash.is_a?(Hash)
              get_power_status(ipmi_args, node, options_hash)
            end     # end GET /node/power

            # POST /node/power
            # Reset the power state of a specific node using the stated 'power_command'
            #   parameters:
            #     required:
            #       :hw_id         | String   | The Hardware ID (SMBIOS UUID) of the node.   |
            #       :power_command | String   | The BMC power command to execute.            |         | Default: unavailable
            #     optional:
            #       :ipmi_username | String   | The username used to access the BMC.         |         | Default: unavailable
            #       :ipmi_password | String   | The password used to access the BMC.         |         | Default: unavailable
            #       :ipmi_options  | String   | The options pass when connecting to the BMC. |         | Default: unavailable
            # (Note; valid values for the 'power_command' are 'on', 'off', 'reset', 'cycle' or 'softShutdown').
            params do
              requires :hw_id, type: String, desc: "The Hardware ID (SMBIOS UUID) of the node"
              requires :power_command, type: String, desc: "The BMC-related power command (on, off, reset, or cycle)"
              optional :ipmi_username, type: String, desc: "The IPMI username"
              optional :ipmi_password, type: String, desc: "The IPMI password"
              optional :ipmi_options, type: String, desc: "The IPMI connect options (JSON string)"
            end
            post do
              uuid = params[:hw_id].upcase
              node = ProjectHanlon::Engine.instance.lookup_node_by_hw_id({:uuid => uuid, :mac_id => []})
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with Hardware ID: [#{uuid}]" unless node
              ipmi_args = params.select { |key| ['power_command', 'ipmi_username', 'ipmi_password'].include?(key) }
              ipmi_option_string = params[:ipmi_options]
              begin
                options_hash = JSON.parse(ipmi_option_string, {:symbolize_names => true} )
              rescue JSON::ParserError => e
                raise ProjectHanlon::Error::Slice::InputError, "IPMI Options String '#{ipmi_option_string}' is not a valid JSON String"
              end
              raise ProjectHanlon::Error::Slice::InputError, "IPMI Options String '#{ipmi_option_string}' is not a JSON Hash" unless options_hash.is_a?(Hash)
              run_power_cmd(ipmi_args, node, options_hash)
            end     # end POST /node/power

          end     # end resource /node/power

          resource :rebind do
            # POST /node/rebind
            # Set (or cancel) a rebinding request for the specified node
            #   parameters:
            #     required:
            #       hw_id         | String   | The Hardware ID (SMBIOS UUID) of the node. |
            #       action        | String   | The rebinding action to set                |         | Default: unavailable
            # Notes:
            #        - valid values for the 'action' are 'set' or 'cancel'
            params do
              requires :hw_id, type: String, desc: "The Hardware ID (SMBIOS UUID) of the node"
              requires :action, type: String, desc: "The rebinding action to set"
            end
            post do
              uuid = params[:hw_id].upcase
              node = ProjectHanlon::Engine.instance.lookup_node_by_hw_id({:uuid => uuid, :mac_id => []})
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with Hardware ID: [#{uuid}]" unless node
              set_rebinding_action(node, params[:action])
            end     # end POST /node/rebind

          end     # end resource /node/rebind

          # the following description hides this endpoint from the swagger-ui-based documentation
          # (since the functionality provided by this endpoint is not intended to be used off of
          # the Hanlon server)
          desc 'Hide this endpoint', { :hidden => true }
          resource :checkin do

            # GET /node/checkin
            # handle a node checkin (from a Hanlon Microkernel instance)
            #   parameters:
            #         required:
            #           :last_state     | String | The "state" the node is currently in.    |     | Default: unavailable
            #         optional (although one of these two must be specified):
            #           :uuid           | String | The UUID for the node (from the BIOS).   |     | Default: unavailable
            #           :mac_id         | String | The MAC addresses for the node's NICs.   |     | Default: unavailable
            #         optional
            #           :first_checkin  | Boolean | Indicates if is first checkin (or not). |     | Default: unavailable
            #         allowed for backwards compatibility (although will throw an error if used with 'mac_id')
            #           :hw_id          | String | The MAC addresses for the node's NICs.   |     | Default: unavailable

            params do
              requires :last_state, type: String, desc: "The last state received by the Microkernel"
              optional :uuid, type: String, desc: "The UUID for the node"
              optional :mac_id, type: String, desc: "The MAC addresses of the node's NICs."
              optional :hw_id, type: String, desc: "The MAC addresses of the node's NICs."
              optional :first_checkin, type: Boolean, desc: "Used to indicate if is first checkin (or not) by MK"
            end
            desc "Handle a node checkin (by a Microkernel instance)"
            get do
              uuid = params["uuid"].upcase if params["uuid"]
              mac_id = params[:mac_id].upcase.split("_") if params[:mac_id]
              # the following parameter is only used for backwards compatibility (with
              # previous versions of Hanlon, which used a 'hw_id' field during the boot
              # process instead of the new 'mac_id' field)
              hw_id = params[:hw_id].upcase.split("_") if params[:hw_id]
              raise ProjectHanlon::Error::Slice::InvalidCommand, "The hw_id parameter is only allowed for backwards compatibility; use with the mac_id parameter is not allowed" if (hw_id && mac_id)
              mac_id = hw_id if hw_id
              # check to make sure that either the mac_id or the uuid were passed in (or that the
              # hw_id was included instead of the mac_id if it's an old Microkernel checking in, in
              # which case the mac_id will be defined here)
              raise ProjectHanlon::Error::Slice::MissingArgument, "At least one of the optional arguments (uuid or mac_id) must be specified" unless ((uuid && uuid.length > 0) || (mac_id && !(mac_id.empty?)))
              last_state = params[:last_state]
              first_checkin = params[:first_checkin]
              # Validate our args are here
              # raise ProjectHanlon::Error::Slice::MissingArgument, "Must Provide Hardware IDs[hw_id]" unless validate_param(hw_id)
              raise ProjectHanlon::Error::Slice::MissingArgument, "Must Provide Last State[last_state]" unless validate_param(last_state)
              mac_id = mac_id.split("_") if mac_id && mac_id.is_a?(String)
              # raise ProjectHanlon::Error::Slice::MissingArgument, "Must Provide At Least One Hardware ID [hw_id]" unless hw_id.count > 0
              # grab a couple of references we need
              engine = ProjectHanlon::Engine.instance
              # check to see if the node exists
              existing_node = engine.lookup_node_by_hw_id({:uuid => uuid, :mac_id => mac_id})
              if existing_node
                # if a node with this hardware id exists, process the checkin request (and return
                # the resulting command)
                command = engine.mk_checkin(existing_node.uuid, last_state)
                return slice_success_response(SLICE_REF, :checkin_node, command, :mk_response => true)
              end
              # otherwise, if we get this far, return a command telling the Microkernel to register
              # (either because no matching node already exists or because it's the first checkin
              # by the Microkernel)
              command = engine.mk_command(:register,{})
              slice_success_response(SLICE_REF, :checkin_node, command, :mk_response => true)
            end     # end GET /node/checkin

          end     # end resource /node/checkin

          desc 'Hide this endpoint', { :hidden => true }
          resource :register do

            # POST /node/register
            # register a node with Hanlon
            #   parameters:
            #     required:
            #       last_state      | String | The "state" the node is currently in.  |           | Default: unavailable
            #       attributes_hash | Hash   | The attributes_hash of the node.       |           | Default: unavailable
            #     optional (although one of these two must be specified):
            #       uuid            | String | The UUID for the node (from the BIOS). |           | Default: unavailable
            #       mac_id          | String | The MAC addresses for the node's NICs. |           | Default: unavailable
            #         allowed for backwards compatibility (although will throw an error if used with 'mac_id')
            #           :hw_id      | String | The MAC addresses for the node's NICs. |           | Default: unavailable
            desc "Handle a node registration request (by a Microkernel instance)"
            params do
              requires "last_state", type: String, desc: "The last state received by the Microkernel"
              requires "attributes_hash", type: Hash, desc: "A hash of the node's attributes (from facter, lshw, etc.)"
              optional "uuid", type: String, desc: "The UUID for the node"
              optional "mac_id", type: String, desc: "The MAC addresses of the node's NICs."
            end
            post do
              uuid = params["uuid"].upcase if params["uuid"]
              mac_id = params["mac_id"].upcase.split("_") if params[:mac_id]
              # the following parameter is only used for backwards compatibility (with
              # previous versions of Hanlon, which used a 'hw_id' field during the boot
              # process instead of the new 'mac_id' field)
              hw_id = params["hw_id"].upcase.split("_") if params[:hw_id]
              raise ProjectHanlon::Error::Slice::InvalidCommand, "The hw_id parameter is only allowed for backwards compatibility; use with the mac_id parameter is not allowed" if (hw_id && mac_id)
              mac_id = hw_id if hw_id
              # check to make sure that either the mac_id or the uuid were passed in (or that the
              # hw_id was included instead of the mac_id if it's an old Microkernel registering, in
              # which case the mac_id will be defined here)
              raise ProjectHanlon::Error::Slice::MissingArgument, "At least one of the optional arguments (uuid or mac_id) must be specified" unless ((uuid && uuid.length > 0) || (mac_id && !(mac_id.empty?)))
              last_state = params["last_state"]
              attributes_hash = params["attributes_hash"]
              # Validate our args are here
              raise ProjectHanlon::Error::Slice::MissingArgument, "Must Provide Last State[last_state]" unless validate_param(last_state)
              raise ProjectHanlon::Error::Slice::MissingArgument, "Must Provide Attributes Hash[attributes_hash]" unless attributes_hash.is_a? Hash and attributes_hash.size > 0
              # mac_id = mac_id.split("_") if mac_id && mac_id.is_a?(String)
              engine = ProjectHanlon::Engine.instance
              new_node = engine.lookup_node_by_hw_id({:uuid => uuid, :mac_id => mac_id})
              if new_node
                if uuid && !(uuid.empty?)
                  new_node.hw_id = [uuid]
                else
                  new_node.hw_id = new_node.hw_id | mac_id
                end
              else
                shell_node = ProjectHanlon::Node.new({})
                if uuid && !(uuid.empty?)
                  shell_node.hw_id = [uuid]
                else
                  shell_node.hw_id = mac_id
                end
                new_node = engine.register_new_node_with_hw_id(shell_node)
                raise ProjectHanlon::Error::Slice::CouldNotRegisterNode, "Could not register new node" unless new_node
              end
              new_node.timestamp = Time.now.to_i
              new_node.attributes_hash = attributes_hash
              new_node.last_state = last_state
              raise ProjectHanlon::Error::Slice::CouldNotRegisterNode, "Could not register node" unless new_node.update_self
              slice_success_response(SLICE_REF, :register_node, new_node.to_hash, :mk_response => true)
            end     # end POST /node/register

          end     # end resource /node/register

          resource '/:uuid' do
            # GET /node/{uuid}
            # Query for the state of a specific node.
            #   parameters:
            #         optional:
            #           :field      | String | The field to return. |                           | Default: unavailable
            desc "Get the details for a specific node (by UUID)"
            params do
              requires :uuid, type: String, desc: "The node's UUID"
              optional :field, type: String, desc: "Name of field to return ('attributes' or 'hardware_id')"
            end
            get do
              node_uuid = params[:uuid]
              node = SLICE_REF.get_object("node_with_uuid", :node, node_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with UUID: [#{node_uuid}]" unless node && (node.class != Array || node.length > 0)
              selected_option = params[:field]
              # if no params were passed in, then just return a summary for the specified node
              unless selected_option
                slice_success_object(SLICE_REF, :get_node_by_uuid, node, :success_type => :generic)
              else
                if /^(attrib|attributes)$/.match(selected_option)
                  slice_success_response(SLICE_REF, :get_node_attributes, Hash[node.attributes_hash.sort], :success_type => :generic)
                elsif /^(hardware|hardware_id|hardware_ids)$/.match(selected_option)
                  slice_success_response(SLICE_REF, :get_node_hardware_ids, {"hw_id" => node.hw_id}, :success_type => :generic)
                else
                  raise ProjectHanlon::Error::Slice::InputError, "unrecognized fieldname '#{selected_option}'"
                end
              end
            end     # end GET /node/{uuid}

            resource :power do

              # GET /node/{uuid}/power
              # Query for the power state of a specific node.
              #   parameters:
              #     required:
              #       :uuid          | String   | The uuid of the specified node.                                 |
              #     optional:
              #       :ipmi_username | String   | The username used to access the BMC.                            |
              #       :ipmi_password | String   | The password used to access the BMC.                            |
              #       :ipmi_options  | String   | The options pass when connecting to the BMC (as a JSON string). |
              params do
                requires :uuid, type: String, desc: "The node's UUID"
                optional :ipmi_username, type: String, desc: "The IPMI username"
                optional :ipmi_password, type: String, desc: "The IPMI password"
                optional :ipmi_options, type: String, desc: "The IPMI connect options (JSON string)"
              end
              get do
                node_uuid = params[:uuid]
                node = SLICE_REF.get_object("node_with_uuid", :node, node_uuid)
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with UUID: [#{node_uuid}]" unless node && (node.class != Array || node.length > 0)
                ipmi_args = params.select { |key| ['ipmi_username', 'ipmi_password'].include?(key) }
                ipmi_option_string = params[:ipmi_options]
                begin
                  options_hash = JSON.parse(ipmi_option_string, {:symbolize_names => true})
                rescue JSON::ParserError => e
                  raise ProjectHanlon::Error::Slice::InputError, "IPMI Options String '#{ipmi_option_string}' is not a valid JSON String"
                end
                raise ProjectHanlon::Error::Slice::InputError, "IPMI Options String '#{ipmi_option_string}' is not a JSON Hash" unless options_hash.is_a?(Hash)
                get_power_status(ipmi_args, node, options_hash)
              end     # end GET /node/{uuid}/power

              # POST /node/{uuid}/power
              # Reset the power state of a specific node using the stated 'power_command'
              #   parameters:
              #     required:
              #       uuid          | String   | The uuid of the specified node.              |         | Default: unavailable
              #       power_command | String   | The BMC power command to execute.            |         | Default: unavailable
              #     optional:
              #       ipmi_username | String   | The username used to access the BMC.         |         | Default: unavailable
              #       ipmi_password | String   | The password used to access the BMC.         |         | Default: unavailable
              #       ipmi_options  | String   | The options pass when connecting to the BMC. |         | Default: unavailable
              # (Note; valid values for the 'power_command' are 'on', 'off', 'reset', 'cycle' or 'softShutdown').
              params do
                requires :uuid, type: String, desc: "The node's UUID"
                requires :power_command, type: String, desc: "The BMC-related power command (on, off, reset, or cycle)"
                optional :ipmi_username, type: String, desc: "The IPMI username"
                optional :ipmi_password, type: String, desc: "The IPMI password"
                optional :ipmi_options, type: String, desc: "The IPMI connect options (JSON string)"
              end
              post do
                node_uuid = params[:uuid]
                node = SLICE_REF.get_object("node_with_uuid", :node, node_uuid)
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with UUID: [#{node_uuid}]" unless node && (node.class != Array || node.length > 0)
                ipmi_option_string = params[:ipmi_options]
                begin
                  options_hash = JSON.parse(ipmi_option_string, {:symbolize_names => true})
                rescue JSON::ParserError => e
                  raise ProjectHanlon::Error::Slice::InputError, "IPMI Options String '#{ipmi_option_string}' is not a valid JSON String"
                end
                raise ProjectHanlon::Error::Slice::InputError, "IPMI Options String '#{ipmi_option_string}' is not a JSON Hash" unless options_hash.is_a?(Hash)
                run_power_cmd(params, node, options_hash)
              end     # end POST /node/{uuid}/power

            end     # end resource /node/:uuid/power

            resource :rebind do

              # POST /node/{uuid}/rebind
              # Set (or cancel) a rebinding request for the specified node
              #   parameters:
              #     required:
              #       uuid          | String   | The uuid of the specified node.      |         | Default: unavailable
              #       action        | String   | The rebinding action to set          |         | Default: unavailable
              # Notes:
              #        - valid values for the 'action' are 'set' or 'cancel'
              params do
                requires :uuid, type: String, desc: "The node's UUID"
                requires :action, type: String, desc: "The rebinding action to set"
              end
              post do
                node_uuid = params[:uuid]
                node = SLICE_REF.get_object("node_with_uuid", :node, node_uuid)
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Node with UUID: [#{node_uuid}]" unless node && (node.class != Array || node.length > 0)
                set_rebinding_action(node, params[:action])
              end     # end POST /node/{uuid}/rebind

            end     # end resource /node/:uuid/rebind

          end     # end resource /node/:uuid

        end     # end resource :node

      end

    end

  end

end
