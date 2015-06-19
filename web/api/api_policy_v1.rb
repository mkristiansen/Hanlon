#

require 'json'
require 'api_utils'

module Hanlon
  module WebService
    module Policy

      class APIv1 < Grape::API

        String.class_eval do
          def to_boolean
            self == 'true'
          end
        end

        version :v1, :using => :path, :vendor => "hanlon"
        format :json
        default_format :json
        SLICE_REF = ProjectHanlon::Slice::Policy.new([])

        rescue_from ProjectHanlon::Error::Slice::InvalidUUID,
                    ProjectHanlon::Error::Slice::NoCallbackFound,
                    ProjectHanlon::Error::Slice::InvalidPolicyTemplate,
                    ProjectHanlon::Error::Slice::InvalidModel,
                    ProjectHanlon::Error::Slice::MissingTags,
                    ProjectHanlon::Error::Slice::InvalidMaximumCount,
                    ProjectHanlon::Error::Slice::MissingActiveModelUUID,
                    ProjectHanlon::Error::Slice::MissingCallbackNamespace,
                    ProjectHanlon::Error::Slice::MissingArgument,
                    ProjectHanlon::Error::Slice::InputError,
                    Grape::Exceptions::Validation do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from ProjectHanlon::Error::Slice::CouldNotCreate,
                    ProjectHanlon::Error::Slice::CouldNotUpdate,
                    ProjectHanlon::Error::Slice::CouldNotRemove do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(403, e.class.name, e.message).to_json,
              403,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from ProjectHanlon::Error::Slice::MethodNotAllowed do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(405, e.class.name, e.message).to_json,
              405,
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

          def request_is_from_hanlon_subnet(ip_addr)
            Hanlon::WebService::Utils::request_from_hanlon_subnet?(ip_addr)
          end

          def get_data_ref
            Hanlon::WebService::Utils::get_data
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

          def make_callback(active_model, callback_namespace, command_array)
            callback = active_model.model.callback[callback_namespace]
            raise ProjectHanlon::Error::Slice::NoCallbackFound, "Missing callback" unless callback
            node = get_data_ref.fetch_object_by_uuid(:node, active_model.node_uuid)
            callback_return = active_model.model.callback_init(callback, command_array, node, active_model.uuid, active_model.broker)
            active_model.update_self
            callback_return
          end

          def split_tags(tags)
            # set a default to use when returning the input 'tags'
            # argument without change (can use this value to test if
            # changes should be made to existing 'match_using' values
            # in the calling routine)
            match_using = nil
            # if input argument is not a string, return it unchanged
            if tags.is_a? String
              # first, use both possible separators to split the input string and
              # determine if the string we're splitting by actually exists in the
              # input string in each case
              comma_split = tags.split(',')
              includes_comma = (comma_split.size > 1)
              or_split = tags.split('|')
              includes_or = (or_split.size > 1)
              # if found both separator strings, return an error
              raise ProjectHanlon::Error::Slice::InputError, "Usage Error: mixed-use of ',' and '| as separators in policy tag strings is not supported)" if includes_comma && includes_or
              # if the input string is an '|' separated string, then return the
              # or_split values as the policy tags tags and an 'or' as the string
              # for how those policy tags should be matched to a node
              # it must be a ',' separated string or a single tag as a string
              # (in which case it'll contain neither a ',' nor an '|')
              if includes_or
                return [or_split, 'or']
              end
              # otherwise, return the comma_split values as the policy tag(s)
              # and an 'and' as the string for how to match the policy tag(s)
              # to a node
              return [comma_split, 'and']
            end
            # return the result and how those tags should be matched
            [tags, match_using]
          end

        end

        resource :policy do

          # GET /policy
          # Query for defined policies.
          #   parameters:
          #     optional:
          #       :filter_str    | String   | A string to use to filter the results  |
          desc "Retrieve a list of all policy instances"
          params do
            optional :filter_str, type: String, desc: "String used to filter results"
          end
          get do
            filter_str = params[:filter_str]
            policies = SLICE_REF.get_object("policies", :policy)
            # Issue 125 Fix - add policy serial number & bind_counter to rest api
            policies.each do |policy|
              policy.line_number = policy.row_number
              policy.bind_counter = policy.current_count
            end
            success_object = slice_success_object(SLICE_REF, :get_all_policies, policies, :success_type => :generic)
            # if a filter_str was provided, apply it here
            success_object['response'] = filter_hnl_response(success_object['response'], filter_str) if filter_str
            # and return the resulting success_object
            success_object
          end     # end GET /policy

          # POST /policy
          # Create a Hanlon policy
          #   parameters:
          #     template          | String | The "template" to use for the new policy |         | Default: unavailable
          #     label             | String | The "label" to use for the new policy    |         | Default: unavailable
          #     model_uuid        | String | The UUID of the model to use             |         | Default: unavailable
          #     tags              | String | The (comma-separated) list of tags       |         | Default: unavailable
          #     broker_uuid       | String | The UUID of the broker to use            |         | Default: "none"
          #     line_number       | String | The line number in the policy table      |         | Default: nil
          #     enabled           | String | A flag indicating if policy is enabled   |         | Default: "false"
          #     maximum           | String | The maximum_count for the policy         |         | Default: "0"
          #     is_default        | String | A flag indicating if policy is default   |         | Default: "false"
          #
          # Note: if the 'is_default' flag is set to true, then the policy that is created will be
          #       set up as the 'default policy' in the policy rules table (i.e. as a policy that matches
          #       any node not matched by another policy). That means that the following conditions
          #       must be met to successfully create this policy:
          #         - there cannot already be a default policy defined in the policy rules table
          #         - the request to create this policy cannot specify any of the following parameters:
          #             * a 'tags' string (defining the tags to match against makes no sense
          #               for a default policy)
          #             * a 'broker_uuid' parameter (the default policy can only be declared
          #               for policies that follow the 'discover_only' or 'boot_local' policy
          #               templates, and policies that follow these templates do not hand off
          #               the system to a broker (by design)
          #             * a value for the 'enabled' flag (the default policy is assumed to
          #               be enabled at all times)
          #             * a maximum count via the 'maximum' parameter (the default policy is
          #               assumed to match any nodes that don't match another policy in the
          #               policy rules table, not just a limited number)
          desc "Create a new policy instance"
          params do
            requires "template", type: String, desc: "The policy template to use"
            requires "label", type: String, desc: "The new policy's name"
            requires "model_uuid", type: String, desc: "The model to use (by UUID)"
            optional "tags", type: String, default: nil, desc: "The tags to match against"
            optional "broker_uuid", type: String, default: "none", desc: "The broker to use (by UUID)"
            optional "line_number", type: String, default: nil, desc: "Line number in the policy table for new policy"
            optional "enabled", type: String, default: "false", desc: "Enabled when created?"
            optional "maximum", type: String, default: "0", desc: "Max. number to match against"
            optional "is_default", type: String, default: "false", desc: "Should policy be set as the default policy?"
          end
          post do
            # grab values for required parameters
            policy_template = params["template"]
            label = params["label"]
            model_uuid = params["model_uuid"]
            broker_uuid = params["broker_uuid"] unless params["broker_uuid"] == "none"
            tags = params["tags"]
            line_number = params["line_number"]
            # convert enabled parameter to a boolean (true or false) value
            enabled = params["enabled"]
            raise ProjectHanlon::Error::Slice::InputError, "Value for enabled (#{enabled}) is not an Boolean" unless ['true','false'].include?(enabled)
            enabled = enabled.to_boolean
            # convert maximum parameter to an integer
            maximum = params["maximum"]
            raise ProjectHanlon::Error::Slice::InvalidMaximumCount, "Policy maximum count must be a valid integer" unless maximum.to_i.to_s == maximum
            maximum = maximum.to_i
            raise ProjectHanlon::Error::Slice::InvalidMaximumCount, "Policy maximum count must be > 0" unless maximum >= 0
            # convert is_default parameter to a boolean (true or false) value
            is_default = params["is_default"]
            raise ProjectHanlon::Error::Slice::InputError, "Value for is_default (#{is_default}) is not an Boolean" unless ['true','false'].include?(is_default)
            is_default = is_default.to_boolean
            # check for errors in the required inputs
            policy = SLICE_REF.new_object_from_template_name(POLICY_PREFIX, policy_template)
            raise ProjectHanlon::Error::Slice::InvalidPolicyTemplate, "Policy Template is not valid [#{policy_template}]" unless policy
            model = SLICE_REF.get_object("model_by_uuid", :model, model_uuid)
            raise ProjectHanlon::Error::Slice::InvalidUUID, "Invalid Model UUID [#{model_uuid}]" unless model && (model.class != Array || model.length > 0)
            raise ProjectHanlon::Error::Slice::InvalidModel, "Invalid Model Type [#{model.template}] != [#{policy.template}]" unless policy.template.to_s == model.template.to_s
            # grab the list of policies (we'll use it later)
            policy_rules = ProjectHanlon::Policies.instance
            # then check for errors in the optional inputs; first to see if the policy
            # we are creating is intended to be a new 'default policy' for the system
            if is_default
              # if get here, ensure that there is not already default policy already defined in the system
              default_policy_uuid = policy_rules.get_default_policy
              raise ProjectHanlon::Error::Slice::InputError, "Cannot create a new default policy, a default policy is already defined (#{default_policy_uuid})" if default_policy_uuid
              # and that the policy being created here can be used as a default policy (i.e. that it is a
              # 'boot_local' or 'discover_only' policy)
              raise ProjectHanlon::Error::Slice::InputError, "Only no-op ('boot_local' or 'discover_only') policies can be used as default policies)" unless ['boot_local', 'discover_only'].include?(policy_template)
              # if no default policy was found in the system, then check for input errors in the request
              raise ProjectHanlon::Error::Slice::InputError, "Cannot define a broker instance when creating a default policy (only 'boot_local' and 'discover_only' policies can be default policies)" if broker_uuid
              raise ProjectHanlon::Error::Slice::InputError, "Cannot define a line number when creating a default policy (assumed to always be last)" if line_number
              raise ProjectHanlon::Error::Slice::InputError, "Cannot create a disabled default policy (is_default: #{is_default}, enabled: #{enabled})" unless enabled
              raise ProjectHanlon::Error::Slice::InputError, "Cannot define a maximum number of bindings for a default policy (assumed to match any node not matched by another policy)" if maximum > 0
            end
            if broker_uuid
              raise ProjectHanlon::Error::Slice::InputError, "Cannot add a broker to a no-op policy" if ['boot_local', 'discover_only'].include?(policy_template)
              broker = SLICE_REF.get_object("broker_by_uuid", :broker, broker_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Invalid Broker UUID [#{broker_uuid}]" unless (broker && (broker.class != Array || broker.length > 0)) || broker_uuid == "none"
            end
            line_number = line_number.strip if line_number
            raise ProjectHanlon::Error::Slice::InputError, "Index '#{line_number}' is not an integer" if line_number && !/^[+-]?\d+$/.match(line_number)
            line_number = line_number.to_i if line_number
            # split the tags that were passed in and determine how they should be matched to a node for this policy (either an 'and' or an 'or')
            tags, match_using = split_tags(tags) if tags
            raise ProjectHanlon::Error::Slice::MissingTags, "Must provide at least one tag ['tag(,tag)']" unless is_default || (tags && tags.count > 0)
            # Flesh out the policy
            policy.label         = label
            policy.model         = model
            policy.broker        = broker
            policy.tags          = tags if tags
            policy.match_using   = match_using if match_using
            policy.enabled       = enabled
            policy.is_template   = false
            policy.maximum_count = maximum
            policy.is_default    = is_default if policy.is_a?(ProjectHanlon::PolicyTemplate::NoOp)
            # Add policy
            raise(ProjectHanlon::Error::Slice::CouldNotCreate, "Could not create Policy") unless policy_rules.add(policy, line_number)
            # Issue 125 Fix - add policy serial number & bind_counter to rest api
            policy.line_number = policy.row_number
            policy.bind_counter = policy.current_count
            slice_success_object(SLICE_REF, :create_policy, policy, :success_type => :created)
          end     # end POST /policy

          resource :templates do

            # GET /policy/templates
            # Query for available policy templates
            desc "Retrieve a list of available policy templates"
            get do
              # get the policy templates (as an array)
              policy_templates = SLICE_REF.get_child_templates(ProjectHanlon::PolicyTemplate)
              # then, construct the response
              slice_success_object(SLICE_REF, :get_policy_templates, policy_templates, :success_type => :generic)
            end     # end GET /policy/templates

            resource '/:name' do

              # GET /policy/templates/{name}
              # Query for a specific policy template (by UUID)
              desc "Retrieve details for a specific policy template (by name)"
              params do
                requires :name, type: String, desc: "The name of the template"
              end
              get do
                # get the matching policy template
                policy_template_name = params[:name]
                policy_templates = SLICE_REF.get_child_templates(ProjectHanlon::PolicyTemplate)
                policy_template = policy_templates.select { |template| template.template.to_s == policy_template_name }
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Policy Template Named: [#{policy_template_name}]" unless policy_template && (policy_template.class != Array || policy_template.length > 0)
                # then, construct the response
                slice_success_object(SLICE_REF, :get_policy_template_by_name, policy_template[0], :success_type => :generic)
              end     # end GET /policy/templates/{name}

            end     # end resource /policy/templates/:name

          end     # end resource /policy/templates

          # the following description hides this endpoint from the swagger-ui-based documentation
          # (since the functionality provided by this endpoint is not intended to be used off of
          # the Hanlon server)
          desc 'Hide this endpoint', {
              :hidden => true
          }
          resource :callback do

            resource '/:uuid' do

              resource '/:namespace_and_args', requirements: { namespace_and_args: /.*/ } do

                # GET /policy/callback/{uuid}/{namespace_and_args}
                # Make a callback "call" (used during the install/broker-handoff process to track progress)
                desc "Used to handle callbacks (to active_model instances)"
                before do
                  # only allow access to this resource from the Hanlon subnet
                  unless request_is_from_hanlon_subnet(env['REMOTE_ADDR'])
                    env['api.format'] = :text
                    raise ProjectHanlon::Error::Slice::MethodNotAllowed, "Remote Access Forbidden; access to /policy/callback resource is not allowed from outside of the Hanlon subnet"
                  end
                end
                params do
                  requires :uuid, type: String, desc: "The active_model's UUID"
                  requires :namespace_and_args, type: String, desc: "The namespace and arguments for the callback"
                end
                get do
                  # get (and check) the required parameters
                  active_model_uuid  = params[:uuid]
                  raise ProjectHanlon::Error::Slice::MissingActiveModelUUID, "Missing active model uuid" unless SLICE_REF.validate_arg(active_model_uuid)
                  namespace_and_args = params[:namespace_and_args].split('/')
                  callback_namespace = namespace_and_args.shift
                  raise ProjectHanlon::Error::Slice::MissingCallbackNamespace, "Missing callback namespace" unless SLICE_REF.validate_arg(callback_namespace)
                  engine       = ProjectHanlon::Engine.instance
                  active_model = nil
                  engine.get_active_models.each { |am| active_model = am if am.uuid == active_model_uuid }
                  raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Active Model with UUID: [#{active_model_uuid}]" unless active_model
                  env['api.format'] = :text
                  make_callback(active_model, callback_namespace, namespace_and_args)
                end     # end GET /policy/callback/{uuid}/{namespace_and_args}

              end     # end resource /policy/callback/:uuid/:namespace_and_args

            end     # end resource /policy/callback/:uuid

          end     # end resource /policy/callback

          resource '/:uuid' do

            # GET /policy/{uuid}
            # Query for the state of a specific policy.
            desc "Retrieve details for a specific policy instance (by UUID)"
            params do
              requires :uuid, type: String, desc: "The policy's UUID"
            end
            get do
              policy_uuid = params[:uuid]
              policy = SLICE_REF.get_object("get_policy_by_uuid", :policy, policy_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Policy with UUID: [#{policy_uuid}]" unless policy
              # Issue 125 Fix - add policy serial number & bind_counter to rest api
              policy.line_number = policy.row_number
              policy.bind_counter = policy.current_count
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Policy with UUID: [#{policy_uuid}]" unless policy && (policy.class != Array || policy.length > 0)
              slice_success_object(SLICE_REF, :get_policy_by_uuid, policy, :success_type => :generic)
            end     # end GET /policy/{uuid}

            # PUT /policy/{uuid}
            # Update a Hanlon policy (any of the the label, image UUID, or req_metadata_hash
            # can be updated using this endpoint; note that the policy template cannot be updated
            # once a policy is created
            #   parameters:
            #     label             | String | The new "label" value                    |         | Default: unavailable
            #     model_uuid        | String | The new model UUID value                 |         | Default: unavailable
            #     tags              | String | The new (comma-separated) list of tags   |         | Default: unavailable
            #     broker_uuid       | String | The new broker UUID value                |         | Default: unavailable
            #     new_line_number   | String | The new line number in the policy table  |         | Default: unavailable
            #     enabled           | String | A new "enabled flag" value               |         | Default: unavailable
            #     maximum           | String | The new maximum_count value              |         | Default: unavailable
            desc "Update a policy instance (by UUID)"
            params do
              requires :uuid, type: String, desc: "The policy's UUID"
              optional "label", type: String, default: nil, desc: "The policy's new label"
              optional "model_uuid", type: String, default: nil, desc: "The new model (by UUID)"
              optional "tags", type: String, default: nil, desc: "The new tags"
              optional "broker_uuid", type: String, default: nil, desc: "The new broker (by UUID)"
              optional "new_line_number", type: String, default: nil, desc: "Line number (in policy table)"
              optional "enabled", type: String, default: nil, desc: "The new 'enabled' flag value"
              optional "maximum", type: String, default: nil, desc: "Max. number to match against"
            end
            put do
              # get optional parameters
              label = params["label"]
              model_uuid = params["model_uuid"]
              tags = params["tags"]
              broker_uuid = params["broker_uuid"]
              new_line_number = params["new_line_number"]
              enabled = params["enabled"]
              maximum = params["maximum"]

              # and check the values that were passed in (skipping those that were not)
              policy_uuid = params[:uuid]
              policy = SLICE_REF.get_object("policy_with_uuid", :policy, policy_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Invalid Policy UUID [#{policy_uuid}]" unless policy && (policy.class != Array || policy.length > 0)
              # check to ensure we aren't trying to update the default policy
              is_default = policy.is_default if policy.is_a?(ProjectHanlon::PolicyTemplate::NoOp)
              raise ProjectHanlon::Error::Slice::InputError, "Policy UUID [#{policy_uuid}] is the 'default policy' for the system, which cannot be updated" if is_default

              if tags
                tags, match_using = split_tags(tags)
                raise ProjectHanlon::Error::Slice::MissingArgument, "Policy Tags ['tag(,tag)']" unless tags.count > 0
              end
              model = nil
              if model_uuid
                model = SLICE_REF.get_object("model_by_uuid", :model, model_uuid)
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Invalid Model UUID [#{model_uuid}]" unless model && (model.class != Array || model.length > 0)
                raise ProjectHanlon::Error::Slice::InvalidModel, "Invalid Model Type [#{model.label}]" unless policy.template == model.template
              end
              broker = nil
              if broker_uuid
                raise ProjectHanlon::Error::Slice::InputError, "Cannot add a broker to a no-op policy" if [:boot_local, :discover_only].include?(policy.template)
                broker = SLICE_REF.get_object("broker_by_uuid", :broker, broker_uuid)
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Invalid Broker UUID [#{broker_uuid}]" unless (broker && (broker.class != Array || broker.length > 0)) || broker_uuid == "none"
              end
              new_line_number = new_line_number.strip if new_line_number
              raise ProjectHanlon::Error::Slice::InputError, "New index '#{new_line_number}' is not an integer" if new_line_number && !/^[+-]?\d+$/.match(new_line_number)
              if enabled
                raise ProjectHanlon::Error::Slice::InputError, "Enabled flag must have a value of 'true' or 'false'" if enabled != "true" && enabled != "false"
              end
              if maximum
                raise ProjectHanlon::Error::Slice::InvalidMaximumCount, "Policy maximum count must be a valid integer" unless maximum.to_i.to_s == maximum
                raise ProjectHanlon::Error::Slice::InvalidMaximumCount, "Policy maximum count must be > 0" unless maximum.to_i >= 0
              end
              # Update object properties
              policy.label = label if label
              policy.model = model if model
              policy.broker = broker if broker
              policy.tags = tags if tags
              policy.match_using = match_using if match_using
              policy.enabled = enabled if enabled
              policy.maximum_count = maximum if maximum
              if new_line_number
                policy_rules = ProjectHanlon::Policies.instance
                policy_rules.move_policy_to_idx(policy.uuid, new_line_number.to_i)
              end
              # Update object
              raise ProjectHanlon::Error::Slice::CouldNotUpdate, "Could not update Broker Target [#{broker.uuid}]" unless policy.update_self
              # Issue 125 Fix - add policy serial number & bind_counter to rest api
              policy.line_number = policy.row_number
              policy.bind_counter = policy.current_count
              slice_success_object(SLICE_REF, :update_policy, policy, :success_type => :updated)
            end     # end PUT /policy/{uuid}

            # DELETE /policy/{uuid}
            # Remove a Hanlon policy (by UUID)
            desc "Remove a model instance (by UUID)"
            params do
              requires :uuid, type: String, desc: "The policy's UUID"
            end
            delete do
              policy_uuid = params[:uuid]
              policy = SLICE_REF.get_object("policy_with_uuid", :policy, policy_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Policy with UUID: [#{policy_uuid}]" unless policy && (policy.class != Array || policy.length > 0)
              raise ProjectHanlon::Error::Slice::CouldNotRemove, "Could not remove Policy [#{policy.uuid}]" unless get_data_ref.delete_object(policy)
              # ensure policy rules table is updated to reflect removed policy
              policy_rules = ProjectHanlon::Policies.instance
              policy_rules.policy_table.update_table
              slice_success_response(SLICE_REF, :remove_policy_by_uuid, "Policy [#{policy.uuid}] removed", :success_type => :removed)
            end     # end DELETE /policy/{uuid}

          end     # end resource /policy/:uuid

        end     # end resource /policy

      end

    end

  end

end
