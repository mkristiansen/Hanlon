# ProjectHanlon Policy Base class
# Root abstract
require 'policy/no_op'

module ProjectHanlon
  module PolicyTemplate
    class DiscoverOnly < ProjectHanlon::PolicyTemplate::NoOp
      include(ProjectHanlon::Logging)

      # @param hash [Hash]
      def initialize(hash)
        super(hash)
        @hidden = false
        @template = :discover_only
        @description = "Policy used to discover new nodes."

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
