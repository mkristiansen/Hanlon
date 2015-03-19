require "erb"

# Root ProjectHanlon namespace
module ProjectHanlon
  module ModelTemplate
    # Root Model object
    # @abstract
    class InMemory < ProjectHanlon::ModelTemplate::Base
      include(ProjectHanlon::Logging)

      # Assigned image
      attr_accessor :image_uuid
      # Metadata
      attr_accessor :hostname
      attr_accessor :domainname
      # Compatible Image Prefix
      attr_accessor :image_prefix

      def initialize(hash)
        super(hash)
        # Static config
        @hidden      = true
        @template = :linux_deploy
        @name = "in_memory"
        @description = "Generic In-Memory Model"
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
        @final_state = :os_complete
        from_hash(hash) unless hash == nil
      end

      # Defines our FSM for this model
      #  For state => {action => state, ..}
      def fsm_tree
        {
          :init => {
            :mk_call       => :init,
            :boot_call     => :init,
            :timeout       => :timeout_error,
            :error         => :error_catch,
            :else          => :init,
          },
          :timeout_error => {
            :mk_call   => :timeout_error,
            :boot_call => :timeout_error,
            :else      => :timeout_error,
            :reset     => :init
          },
          :error_catch => {
            :mk_call   => :error_catch,
            :boot_call => :error_catch,
            :else      => :error_catch,
            :reset     => :init
          },
        }
      end

      def mk_call(node, policy_uuid)
        super(node, policy_uuid)
        case @current_state
          # We need to reboot
          when :init, :preinstall
            ret = [:reboot, {}]
          when :timeout_error, :error_catch
            ret = [:acknowledge, {}]
          else
            ret = [:acknowledge, {}]
        end
        fsm_action(:mk_call, :mk_call)
        ret
      end

      def hostname
        "#{@hostname_prefix}#{@counter.to_s}"
      end

      def config
        ProjectHanlon.config
      end

    end
  end
end
