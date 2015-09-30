# Used for all event-driven commands and policy resolution

require "singleton"
require "json"
require 'rebind_request'

module ProjectHanlon
  class Engine < ProjectHanlon::Object
    include(ProjectHanlon::Logging)
    include(Singleton)

    attr_accessor :policies

    def initialize
      # create the singleton for policies
      @policies = ProjectHanlon::Policies.instance
    end



    def get_active_models
      get_data.fetch_all_objects(:active)
    end

    #####################

    #####################
    ##### Default MK ####
    #####################

    def default_mk
      mk_images = []
      get_data.fetch_all_objects(:images).each { |i|
        success, message = i.verify(ProjectHanlon.config.image_path)
        mk_images << i if i.path_prefix == "mk" && success
      }

      if mk_images.count > 0
        mk_image = nil
        mk_images.each do
        |i|
          mk_image = i if mk_image == nil
          mk_image = i if mk_image.version_weight < i.version_weight
        end

        mk_image
      else
        logger.error "Microkernel image does not exist"
        nil
      end
    end

    #####################
    ##### MK Section ####
    #####################

    def mk_checkin(uuid, last_state)
      old_timestamp = 0 # we set this early in case a timestamp field is nil
                        # We attempt to fetch the node object
      node          = get_data.fetch_object_by_uuid(:node, uuid)

      # Check to see if node is known
      if node

        # Node is known we need to update timestamp
        old_timestamp = node.timestamp unless node.timestamp == nil
        node.last_state = last_state    # We update last_state for the node
        node.timestamp  = Time.now.to_i # We update timestamp for the node
        unless node.update_self # Update node catching if it fails
          logger.error "Node #{node.uuid} checkin failed"
        end
        logger.debug "Node #{node.uuid} checkin accepted"

        # Check for a node action override
        forced_action = checkin_action_override(uuid)
        # Return the forced command if it exists
        logger.debug "Forced action for Node #{node.uuid} found (#{forced_action.to_s})" if forced_action
        return mk_command(forced_action, { }) if forced_action

        # Check to see if the time span since the last node contact
        # is greater than our register_timeout
        if (node.timestamp - old_timestamp) > ProjectHanlon.config.register_timeout
          # Our node hasn't talked to the server within an acceptable time frame
          # we will request a re-register to refresh details about the node
          logger.debug "Asking Node #{node.uuid} to re-register as we haven't talked to him in #{(node.timestamp - old_timestamp)} seconds"
          return mk_command(:register, { })
        end

        # Check to see if there is an active model
        # If there is we will call the mk_call method common to all policies
        # A active model means the node will never evaluate a policy
        # So for safety's sake - we set an extra flag (active_models_flag) which
        # prevents the policy eval below to run
        active_model = find_active_model(node)

        if active_model
          command_array = active_model.mk_call(node)
          active_model.update_self
          return mk_command(command_array[0], command_array[1])
        else
          # Evaluate node vs policy rules to see if a policy needs to be bound
          mk_eval_vs_policy_rule(node)
        end

        # If we got to this point we just need to acknowledge the checkin
        mk_command(:acknowledge, { })

      else
        # Never seen this node - we tell it to checkin
        logger.debug "Unknown Node #{uuid}, asking to register"
        mk_command(:register, { })
      end
    end

    def check_policy_match(policy, node, default_policy_uuid = nil)
      # Note; searching for a matching policy relies on the policies being evaluated
      # in the order they appear in the policy rules table; if not then the default
      # policy could be "matched" too early...
      if policy.tags.count > 0
        if check_tags(node.tags, policy) && policy.enabled.to_s == "true" && policy.is_under_maximum?
          logger.debug "Matching policy (#{policy.label}) for Node #{node.uuid} using tags#{policy.tags.inspect}"
          # We found a policy that matches
          return true
        end
      elsif default_policy_uuid && policy.uuid == default_policy_uuid
        logger.debug "Matching the default policy (#{policy.label}) for Node #{node.uuid}"
        return true
      else
        logger.error "Policy (#{policy.label}) has no tags configured"
      end
      logger.debug "No matching rules"
      false
    end

    def mk_eval_vs_policy_rule(node)
      logger.debug "Evaluating policy rules vs Node #{node.uuid}"
      begin
        # Loop through each policy checking node's tags to see if that match
        default_policy_uuid = ProjectHanlon::Policies.instance.get_default_policy
        @policies.get.each { |policy|
          # if we find a matching policy, then bind it to the node (as an
          # active_model instance) and return, otherwise continue on to the
          # next policy
          if check_policy_match(policy, node, default_policy_uuid)
            mk_bind_policy(node, policy)
            return
          end
        }
      rescue => e
        logger.error e.message
      end
    end

    def mk_bind_policy(node, policy)
      if policy.bind_me(node)
        logger.debug "Binding policy for Node (#{node.uuid}) to Policy (#{policy.label})"
        get_data.persist_object(policy)
      else
        logger.error "Cannot bind Node (#{node.uuid}) to Policy (#{policy.label})"
      end
    end

    # Used to override per-node checkin behavior for testing
    def checkin_action_override(uuid)
      checkin_file = "#{$hanlon_root}/config/checkin_action.yaml"

      return nil unless File.exist?(checkin_file) # skip is file doesn't exist'
      f               = File.open(checkin_file, "r")
      checkin_actions = YAML.load(f)
      checkin_actions[uuid] # return value for key matching uuid or nil if none
    end

    def mk_command(command_name, command_param)
      command_response                  = { }
      command_response['command_name']  = command_name
      command_response['command_param'] = command_param
      command_response
    end

    #######################
    ##### Boot Section ####
    #######################

    def boot_checkin(options = {})
      # Called by a node boot process

      logger.info "Request for boot - uuid: #{options[:uuid]}, mac_id: #{options[:mac_id]}"

      # We attempt to fetch the node object
      node = lookup_node_by_hw_id(options)

      # if a node is found in the database, then we need
      # to check for an outstanding for rebinding request
      # or a bound active_model
      if node != nil
        logger.info "Node identified - uuid: #{node.uuid}"

        # check to see if there is an outstanding "rebinding request"
        # for that node; if so use the "newly bound" active_model to
        # return the appropriate iPXE-boot script to the node
        rebind_model = get_rebinding_request(node)
        if rebind_model
          # Call the rebind model boot_call
          logger.info "Rebinding policy found (#{rebind_model.label}) for Node uuid: #{node.uuid}"
          boot_response = rebind_model.boot_call(node)
          return boot_response
        end

        # Otherwise, check to see if an active model has been bound to
        # the node
        active_model = find_active_model(node) # commented out until refactor
        # We update the dhcp_mac for the mac address that was booted
        if options[:dhcp_mac]
          node.dhcp_mac = options[:dhcp_mac]
          node.update_self
        end

        # If there is a bound active model we use it to retrieve the
        # appropriate boot response for this node, otherwise boot into
        # the Microkernel
        if active_model
          # Call the active model boot_call
          logger.info "Active policy found (#{active_model.label}) for Node uuid: #{node.uuid}"
          boot_response = active_model.boot_call(node)
          get_data.persist_object(active_model)
          return boot_response
        else
          # There is not active model so boot into the MK
          logger.info "No active policy found - uuid: #{node.uuid}"
          default_mk_boot(node.uuid)
        end
      else

        # if the node isn't in the DB, boot it into the MK
        # This is a default behavior
        logger.info "Node unknown - uuid: #{options[:uuid]}, mac_id: #{options[:mac_id]}"
        default_mk_boot("unknown", options)
      end

    end

    def find_active_model(node)
      active_models = get_data.fetch_all_objects(:active)
      active_models.each do
      |bp|
        # If we find a active model we return it
        return bp if bp.node_uuid == node.uuid
      end
      # Otherwise we return false indicating we have no policy
      false
    end

    def find_rebind_request(node)
      rebind_requests = get_data.fetch_all_objects(:rebind_request)
      return nil unless rebind_requests
      rebind_requests.select! { |request| request.node_uuid == node.uuid }
      return rebind_requests[0] if rebind_requests
      nil
    end

    def add_rebinding_request(node)
      rebind_request = find_rebind_request(node)
      if rebind_request
        logger.error "Cannot rebind Node (#{node.uuid}); rebinding request has already been made"
        raise ProjectHanlon::Error::Slice::CommandFailed, "Cannot rebind Node (#{node.uuid}); rebinding request has already been made"
      end
      rebind_request = ProjectHanlon::RebindRequest.new({ '@node_uuid' => node.uuid })
      get_data.persist_object(rebind_request)
    end

    def cancel_rebinding_request(node)
      rebind_request = find_rebind_request(node)
      unless rebind_request
        logger.error "Cannot cancel rebinding request Node (#{node.uuid}); rebinding request does not exist"
        raise ProjectHanlon::Error::Slice::CommandFailed, "Cannot cancel rebinding request Node (#{node.uuid}); rebinding request does not exist"
      end
      get_data.delete_object(rebind_request)
      rebind_request
    end

    def get_rebinding_request(node)
      rebind_request = find_rebind_request(node)
      # if we found a rebind_request, then search for a policy that matches
      # this node to an "in memory" model; if one is found then return it
      if rebind_request
        # Loop through each policy checking node's tags to see if that match
        @policies.get.each { |policy|
          if policy.model.class <= ProjectHanlon::ModelTemplate::InMemory
            # if found a match, then remove the rebinding request and return the
            # matching policy
            if check_policy_match(policy, node)
              get_data.delete_object(rebind_request)
              return policy
            end
          end
        }
      end
      # otherwise, return nil (indicating that either no matching
      # rebind_request was found or that a rebind_request was found
      # or that no policy matching this node to an "in memory" model
      # was found)
      nil
    end

    def default_mk_boot(uuid, options = {})
      logger.info "Responding with MK Boot - Node: #{uuid}"
      # obtain a reference to the BootMK policy template (we'll use that in a moment)
      default = ProjectHanlon::PolicyTemplate::BootMK.new({})
      # retrieve the SMBIOS UUID (hardware_id) for the node if the input UUID
      # is 'unknown', otherwise grab it from the referenced node itself
      if uuid == 'unknown'
        if options[:uuid]
          node_smbios_uuid = options[:uuid]
        else
          node_smbios_uuid = options[:mac_id]
        end
        # the following error condition should never occur, but just in case...
        return default.get_error_script("Neither Node UUID (SMBIOS UUID) nor Node MAC_ID were found") unless node_smbios_uuid
      else
        node = get_data.fetch_object_by_uuid(:node, uuid)
        return default.get_error_script("Node: #{uuid} not found") unless node
        hw_id_array = node.hw_id
        if hw_id_array.size == 1
          node_smbios_uuid = hw_id_array[0]
        else
          node_smbios_uuid = hw_id_array.join('_')
        end
      end
      # and determine which Microkernel reference we should use (there may be more
      # than one, if so apply some rules to pick the best one to use for a default boot)
      default_mk_ref = default_mk
      return default.get_error_script("Microkernel image not found") unless default_mk_ref
      # finally, use the policy template to retrieve the boot script to use for this node
      default.get_boot_script(default_mk_ref, node_smbios_uuid)
    end

    ########
    # Util #
    ########

    # This finds the correct node object with the provided node id's
    # If a new hw_id is sent and it not used somewhere else, it is added to the node's list
    #

    # @param [Hash] options
    # @return [Object,nil]
    def lookup_node_by_hw_id(options = { :uuid => '', :mac_id => [] })
      if (!options[:uuid] || options[:uuid].empty?) && (!options[:mac_id] || options[:mac_id].empty?)
        return nil
      end
      matching_nodes = []
      nodes          = get_data.fetch_all_objects(:node)
      nodes.each { |node|
        # if a 'uuid' was provided, then search for a match based on
        # that 'uuid' value
        if options[:uuid] && !(options[:uuid].empty?) && node.hw_id == [options[:uuid]]
          matching_nodes << node
          next
        end
        # if no 'uuid' was provided or a match was not found based on
        # the provided 'uuid' value, then look for a matching 'hw_id';
        # if a match based on 'mac_id' is found, add that node to the
        # array of matching nodes
        if options[:mac_id]
          matching_hw_id = node.hw_id & options[:mac_id]
          matching_nodes << node if matching_hw_id.count > 0
        end
      }


      if matching_nodes.count > 1
        # uh oh - we have more than one
        # This should have been fixed during reg
        # this is fatal - we raise an error
        resolve_node_hw_id_collision
        matching_nodes = [lookup_node_by_hw_id(options)]
      end

      if matching_nodes.count == 1
        matching_nodes.first
      else
        nil
      end
    end

    # This creates a new node with the provided hw_ids and returns the new object
    #
    # @param [Hash] options
    # @return [Object,nil]
    def register_new_node_with_hw_id(node_object)
      # Ensure we have at least one hw_id
      unless node_object.hw_id.count > 0
        logger.error "Cannot register node without hw_id"
        return nil
      end
      # Verify none of the hw_id's are in use
      existing_node = lookup_node_by_hw_id(:hw_id => node_object.hw_id)
      if existing_node
        logger.error "Cannot register node with duplicate HW ID to existing node #{(existing_node.hw_id & node_object.hw_id).inspect} #{existing_node.uuid} #{node_object.uuid}"
        return nil
      end
      # Create new node object with node object
      new_node = get_data.persist_object(node_object)
      # run the resolve to be sure we don't have a conflict
      resolve_node_hw_id_collision
      new_node
    end

    # This is a failsafe should a duplicate hw_id happen. It removes the conflicted hw_id from a node object with the older timestamp
    #
    # @param [Array] hw_id
    def resolve_node_hw_id_collision
      # Get all nodes
      nodes     = get_data.fetch_all_objects(:node)
      # This will hold all hw_id's (not unique)'
      all_hw_id = []
      # Take each hw_id and add to our all_hw_id array
      nodes.each { |node| all_hw_id += node.hw_id }
      # Loop through each hw_id
      all_hw_id.each do
      |hwid|
        # This will hold nodes that match
        matching_nodes = []
        # loops through each node
        nodes.each do
        |node|
          # If the hwid is in the node.hw_id array then we add to the matching ndoes array
          matching_nodes << node if (node.hw_id & [hwid]).count > 0
        end
        # If we have more than one node we have a conflict
        # We sort by timestamp ascending
        matching_nodes.sort! { |a, b| a.timestamp <=> b.timestamp }
        # We remove the first one, any that remain will be cleaned of the hwid
        matching_nodes.shift
        # We remove the hw_id from each and persist
        matching_nodes.each do
        |node|
          node.hw_id.delete(hwid)
          node.update_self
        end
      end
      nil
    end

    def check_tags(node_tags, policy)
      policy_tags = policy.tags
      logger.debug "Node Tags: #{node_tags}"
      logger.debug "Policy Tags: #{policy_tags}"
      # if we are matching using an 'or' comparison, then
      # check to see if the intersection of the two arrays
      # is empty or not; otherwise check to see if the
      # difference between the two arrays is empty or not
      if policy.match_using == 'or'
        return false if (policy_tags & node_tags).empty?
      else
        return false unless (policy_tags - node_tags).empty?
      end
      true
    end

    def uuid_sanitize(uuid)
      #uuid = uuid.gsub(/[:;,]/,"")
      #uuid.upcase
      uuid
    end

    def get_tags(node, tag_rules)
      tags = []
      tag_rules.each { |tag_rule|
        if tag_rule.check_tag_rule(node.attributes_hash)
          tags << tag_rule.get_tag(node)
        end
      }
      tags
    end

    def node_tags(node)
      tag_rules = get_data.fetch_all_objects(:tag)
      # add in tags for the declared policies
      tags = get_tags(node, tag_rules)
      # add a system tag for the hardware_id of the node
      tags = tags + node.hw_id
      # and, finally, add in any system tags that apply to this node
      tags + get_tags(node, get_system_tag_rules)
    end

    def node_status(node)
      return "rebind" if find_rebind_request(node)
      return "bound" if find_active_model(node)
      max_active_elapsed_time = ProjectHanlon.config.register_timeout
      time_since_last_checkin = Time.now.to_i - node.timestamp.to_i
      return "inactive" if time_since_last_checkin > max_active_elapsed_time
      "active"
    end

    def get_system_tag_rules
      system_tag_rules     = []
      system_tag_rules_dir = File.join(File.dirname(__FILE__), "tagging/system_rules/**/*.json")
      Dir.glob(system_tag_rules_dir).each do
      |json_file|
        begin
          system_tag_rules << JSON.parse(File.read(json_file))
        rescue => e
          logger.error "parsing error with json file: #{json_file}"
        end
      end
      system_tag_rules.map! do
      |tr|
        begin
          ProjectHanlon::Tagging::TagRule.new(tr)
        rescue => e
          logger.error "converting to object error with hash: #{tr.inspect}"
        end
      end
      system_tag_rules
    end

    # removes all nodes that have not checked in during the last
    # node_expire_timeout seconds from the database
    def remove_expired_nodes(node_expire_timeout)
      node_array = get_data.fetch_all_objects(:node)
      node_array.each { |node|
        # skip to the next one if this node is either bound or
        # set to rebind
        next if ['bound','rebind'].include?(node_status(node))
        elapsed_time = Time.now.to_i - node.timestamp.to_i
        if elapsed_time > node_expire_timeout
          node_uuid = node.uuid
          if get_data.delete_object(node)
            logger.info "expired node '#{node_uuid}' successfully removed from db"
          else
            logger.info "expired node '#{node_uuid}' could not be removed from db"
          end
        end
      }
    end

    # checks to see if an image is in use by a model (or models)
    def get_models_using_image(image_uuid)
      # check to see if the image is used by a model (or models); if it is, then return
      # the uuids of any models that use this image, else just an empty array (indicating
      # no matching models have been found)
      models = get_data.fetch_all_objects(:model)
      matching_models = models.select { |model| model.respond_to?(:image_uuid) && model.image_uuid == image_uuid }
      if matching_models.size > 0
        matching_model_uuids = matching_models.map { |model| model.uuid}
        return matching_model_uuids
      end
      []
    end

    # removes an image, but only if it's not part of a model
    def remove_image(image)
      # ensure image is not actively part of a model; if so, then raise an exception
      # (and return to the caller without removing the image)
      matching_model_uuids = get_models_using_image(image.uuid)
      unless matching_model_uuids.empty?
        logger.warn "Cannot remove image '#{image.uuid}' because it is used in the following models #{matching_model_uuids}"
        raise Exception, "Cannot remove image '#{image.uuid}' because it is used in the following models: #{matching_model_uuids}"
      end
      unless image.remove(ProjectHanlon.config.image_path)
        logger.error 'attempt to remove image from image_path failed'
        raise RuntimeError, "Attempt to remove image '#{image.uuid}' from the image_path failed"
      end
      get_data.delete_object(image)
    end

    # removes an model, but only if it's not part of a bound policy
    def remove_model(model)
      # ensure model is not actively part of a policy; if so, then raise an exception
      # (and return to the caller without removing the model)
      policies = get_data.fetch_all_objects(:policy)
      matching_policies = policies.select { |policy|
        policy.respond_to?(:model) && policy.model.uuid == model.uuid
      }
      if matching_policies.size > 0
        matching_policy_uuids = matching_policies.map { |policy| policy.uuid}
        logger.warn "Cannot remove model '#{model.uuid}' because it is used in the following policies: #{matching_policy_uuids}"
        raise Exception, "Cannot remove model '#{model.uuid}' because it is used in following policies: #{matching_policy_uuids}"
      end
      get_data.delete_object(model)
    end


    # Returns a count of active models that match the policy uuid provided
    # @param [String] policy_uuid
    # @return [Integer]
    def policy_active_model_count(policy_uuid)
      get_active_models.count { |am| am.root_policy == policy_uuid }
    end


  end
end
