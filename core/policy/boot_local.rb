# ProjectHanlon Policy Base class
# Root abstract
require 'policy/no_op'

module ProjectHanlon
  module PolicyTemplate
    class BootLocal < ProjectHanlon::PolicyTemplate::NoOp
      include(ProjectHanlon::Logging)

      # @param hash [Hash]
      def initialize(hash)
        super(hash)
        @hidden = false
        @template = :boot_local
        @description = "Policy used to adding existing nodes to Hanlon."

        from_hash(hash) unless hash == nil
      end


      def mk_call(node)
        model.mk_call(node, @uuid)
      end

      def boot_call(node)
        model.boot_call(node, @uuid)
      end

    end
  end
end
