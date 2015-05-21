module ProjectHanlon
  # Used for binding of policy+models to a node
  # this is permanent unless a user removed the binding or deletes a node
  class Policies < ProjectHanlon::Object
    include(ProjectHanlon::Logging)
    include(Singleton)

    POLICY_PREFIX = "ProjectHanlon::PolicyTemplate::"
    MODEL_PREFIX = "ProjectHanlon::ModelTemplate::"


    # table
    # ensure unique
    # store as single object


    class PolicyTable < ProjectHanlon::Object
      attr_accessor :p_table
      def initialize(hash)
        super()
        # @todo danielp 2013-03-18: this non-UUID value is used to ensure that
        # we have a consistent value for this object, allowing us to access
        # the same object from any location that wants to modify it.
        #
        # We could, and probably should, use a real UUID hard-coded, but the
        # original authors didn't.  In migration to a real storage engine,
        # that totally should happen.
        @uuid = "policy_table"
        @_namespace = :policy_table
        @p_table = []
        from_hash(hash)
      end

      def get_line_number(policy_uuid)
        @p_table.each_with_index { |p_item_uuid, index| return index if p_item_uuid == policy_uuid }
        # if get here, the policy isn't in the policy rules table yet, so return
        # the next position
        return @p_table.size + 1
      end

      def size
        @p_table.size
      end

      def check_new_index(new_index, move_flag = false)
        # throw an error if the new_index is not within the bounds of the policy table
        # (the size of the table less one if no default policy is defined; the size of
        # the table less two if there is a default policy defined)
        default_uuid = ProjectHanlon::Policies.instance.get_default_policy
        # if we're moving (instead of inserting) then the limit is one less than
        # if we're adding a new policy to the table
        if move_flag
          default_uuid ? offset = 2 : offset = 1
        else
          default_uuid ? offset = 1 : offset = 0
        end
        max_index = @p_table.count - offset
        if new_index > max_index
          if default_uuid
            raise ProjectHanlon::Error::Slice::InputError, "Line number '#{new_index}' is not valid; should be between 0 and #{max_index}"
          else
            raise ProjectHanlon::Error::Slice::InputError, "Cannot move policies below default policy; new line number must be between 0 and #{max_index}"
          end
        elsif new_index < 0
          raise ProjectHanlon::Error::Slice::InputError, "Line number '#{new_index}' is not valid; should be between 0 and #{max_index}"
        end
      end

      def add_p_item(policy_uuid, index = nil)
        if exists_in_array?(policy_uuid)
          # if this UUID is already in the policy table, we're actually
          # moving it, not inserting it
          move_to_idx(policy_uuid, index)
        else
          # if an index was provided, insert the new policy at that
          # location, otherwise append it to the end of the array
          if index
            check_new_index(index)
            @p_table.insert(index, policy_uuid)
          else
            @p_table.push policy_uuid
          end
        end
        update_table
      end


      def resolve_duplicates
        @p_table.inject(Hash.new(0)) {|h,v| h[v] += 1; h}.reject{|k,v| v==1}.keys
      end

      def remove_missing
        policy_uuid_array = get_data.fetch_all_objects(:policy).map {|p| p.uuid}
        @p_table.map! do
        |p_item_uuid|
          p_item_uuid if policy_uuid_array.select {|uuid| uuid == p_item_uuid}.count > 0
        end
        @p_table.compact!
      end

      def exists_in_array?(policy_uuid)
        @p_table.each { |p_item_uuid|
          return true if p_item_uuid == policy_uuid }
        false
      end

      def update_table
        resolve_duplicates
        remove_missing
        self.update_self
      end

      def move_to_idx(policy_uuid, new_index)
        policy_index = find_policy_index(policy_uuid)
        # skip operation if new_index is the same as the existing index
        unless new_index == policy_index
          # check to make sure the new_index is within the bounds supported
          # by the policy table
          check_new_index(new_index, true)
          if policy_index > new_index
            # moving policy higher
            while policy_index > new_index
              @p_table[policy_index], @p_table[policy_index - 1] = @p_table[policy_index - 1], @p_table[policy_index]
              policy_index -= 1
            end
          else
            # moving policy lower
            while policy_index < new_index
              @p_table[policy_index], @p_table[policy_index + 1] = @p_table[policy_index + 1], @p_table[policy_index]
              policy_index += 1
            end
          end
          update_table
          return true
        end
        false
      end

      def find_policy_index(policy_uuid)
        @p_table.index(policy_uuid)
      end

    end

    def policy_table
      policy_table_clean

      pt = get_data.fetch_object_by_uuid(:policy_table, "policy_table")
      return pt if pt
      pt = ProjectHanlon::Policies::PolicyTable.new({})
      pt = get_data.persist_object(pt)
      raise ProjectHanlon::Error::CannotCreatePolicyTable, "Cannot create policy table" unless pt
      pt
    end

    # This method ensures that no junk entries exist in the policy table collection
    # after a period of time this will be removed by a new code push
    # nweaver - 11/6/2012
    def policy_table_clean
      # Fetch all does automatic version cleanup for us.
      get_data.fetch_all_objects(:policy_table)
    end



    # Get Array of Models that are compatible with a Policy Template
    def get_models(model_template)
      models = []
      get_data.fetch_all_objects(:model).each do
      |mc|
        models << mc if mc.template == model_template
      end
      models
    end

    # Get Array of Policy Templates available
    def get_templates
      ProjectHanlon::PolicyTemplate.class_children.map do |policy_template|
        policy_template_obj = ::Object.full_const_get(POLICY_PREFIX + policy_template[0]).new({})
        !policy_template_obj.hidden ? policy_template_obj : nil
      end.reject { |e| e.nil? }
    end

    def get_model_templates
      ProjectHanlon::ModelTemplate.class_children.map do |policy_template|
        policy_template_obj = ::Object.full_const_get(MODEL_PREFIX + policy_template[0]).new({})
        !policy_template_obj.hidden ? policy_template_obj : nil
      end.reject { |e| e.nil? }
    end

    def new_policy_from_template_name(policy_template_name)
      get_templates.each do
      |template|
        return template if template.template.to_s == policy_template_name
      end
      template
    end

    def is_policy_template?(policy_template_name)
      get_templates.each do
      |template|
        return true if template.template.to_s == policy_template_name
      end
      false
    end

    def is_model_template?(model_name)
      get_model_templates.each do
      |template|
        return template if template.name == model_name
      end
      false
    end


    def get
      # Get all the policy templates
      policies_array = get_data.fetch_all_objects(:policy)
      logger.debug "Total policies #{policies_array.count}"
      # Sort the policies based on line_number
      policies_array.sort! do
      |a,b|
        a.row_number <=> b.row_number
      end
      policies_array
    end

    # returns the UUID of the default policy in the system (or nil
    # if there is no default policy defined in the system)
    #
    # @return [String] policy_uuid
    def get_default_policy
      get.each { |policy|
        next unless policy.is_a?(ProjectHanlon::PolicyTemplate::NoOp)
        is_default = policy.is_default
        return policy.uuid if is_default
      }
      nil
    end

    # the line number is preserved for updates if no index is specified;
    # if there is no index specified and we're adding a new policy then
    # the line_number will default to the last position (unless there's
    # a default policy in the system in which case it'll default to the
    # next to the last position with the default policy kept in the last
    # position at all times)
    def add(new_policy, index = nil)
      get_data.persist_object(new_policy)
      pt = policy_table
      # check to see if a default policy exists, if so add the
      # new policy to the policy table in the next to the last
      # position (else append to the end as we've always done)
      default_policy_uuid = get_default_policy
      index = (pt.size-1) if index.nil? && default_policy_uuid && default_policy_uuid != new_policy.uuid
      begin
        pt.add_p_item(new_policy.uuid, index)
      rescue ProjectHanlon::Error::Slice::InputError => e
        # remove the object from the database if we failed to add it
        # (unless, of course, our attempt to "add" it was really an
        # attempt to move it to another position in the table)
        get_data.delete_object(new_policy) unless pt.exists_in_array?(new_policy.uuid)
        raise e
      end
    end

    alias :update :add

    def get_line_number(policy_uuid)
      pt = policy_table
      pt.get_line_number(policy_uuid)
    end

    def move_policy_to_idx(policy_uuid, new_idx)
      pt = policy_table
      # pt.add_p_item(policy_uuid, new_idx)
      pt.move_to_idx(policy_uuid, new_idx)
    end

    def policy_exists?(new_policy)
      get_data.fetch_object_by_uuid(:policy, new_policy)
    end

  end
end
