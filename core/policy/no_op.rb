# ProjectHanlon NoOp Policy Base class
# Root abstract
require 'policy/base'

module ProjectHanlon
  module PolicyTemplate
    class NoOp < ProjectHanlon::PolicyTemplate::Base
      include(ProjectHanlon::Logging)

      attr_accessor :is_default

      # @param hash [Hash]
      def initialize(hash)
        super(hash)
        @hidden = true
        @template = :no_op
        @description = "Base class for 'no-op' models in Hanlon."
        @is_default = false

        from_hash(hash) unless hash == nil
      end

      def print_header
        if @bound
          return "Label", "State", "Node UUID", "Broker", "Bind #", "UUID"
        else
          if @is_template
            return "Template", "Description"
          else
            return "#", "Enabled", "Label", "Tags", "Model Label", "#/Max", "Counter", "UUID"
          end
        end
      end

      def print_items
        if @bound
          broker_name = @broker ? @broker.name : "none"
          return @label, @model.current_state.to_s, @node_uuid, broker_name, @model.counter.to_s, @uuid
        else
          tag_string = (is_default ? '**default**' : "[#{get_tag_string}]")
          if @is_template
            return @template.to_s, @description.to_s
          else
            max_num = @maximum_count.to_i == 0 ? '-' : @maximum_count
            return @line_number.to_s, @enabled.to_s, @label, tag_string, @model.label.to_s, "#{@bind_counter}/#{max_num}", @model.counter.to_s, @uuid
          end
        end
      end

      def print_item
        if @bound
          broker_name = @broker ? @broker.name : "none"
          [@uuid,
           @label,
           @template.to_s,
           @node_uuid,
           @model.label.to_s,
           @model.name.to_s,
           @model.current_state.to_s,
           broker_name,
           @model.counter.to_s,
           Time.at(@bind_timestamp).strftime("%H:%M:%S %m-%d-%Y")]
        else
          broker_name = @broker ? @broker.name : "none"
          tag_string = (is_default ? '**default**' : "[#{get_tag_string}]")
          [@uuid,
           #line_number.to_s,
           @line_number.to_s,
           @label,
           @enabled.to_s,
           @template.to_s,
           @description,
           tag_string,
           @match_using,
           @model.label.to_s,
           broker_name,
           #current_count.to_s,
           @bind_counter.to_s,
           @maximum_count.to_s,
           @model.counter.to_s]
        end
      end

    end
  end
end