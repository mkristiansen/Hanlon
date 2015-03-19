module ProjectHanlon
  module ModelTemplate

    class CoreosStable < Coreos
      include(ProjectHanlon::Logging)

      def initialize(hash)
        super(hash)
        # Static config
        @hidden      = false
        @name        = "coreos_stable"
        @description = "CoreOS Stable"

        from_hash(hash) unless hash == nil
      end
    end
  end
end
