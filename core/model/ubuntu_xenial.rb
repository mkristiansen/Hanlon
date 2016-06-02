require "erb"

# Root ProjectHanlon namespace
module ProjectHanlon
  module ModelTemplate
    # Root Model object
    # @abstract
    class UbuntuXenial < Ubuntu
      include(ProjectHanlon::Logging)

      def initialize(hash)
        super(hash)
        # Static config
        @hidden = false
        @name = "ubuntu_Xenial"
        @description = "Ubuntu Xenial (16.04) Model"
        # Metadata vars
        @hostname_prefix = nil
        # State / must have a starting state
        @current_state = :init
        # Image UUID
        @image_uuid = true
        # Image prefix we can attach
        @image_prefix = "os"
        # Enable agent brokers for this model
        @broker_plugin = :agent
        @osversion = 'xenial'
        @final_state = :os_complete
        from_hash(hash) unless hash == nil
      end

    end
  end
end
