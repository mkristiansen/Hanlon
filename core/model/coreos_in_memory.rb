module ProjectHanlon
  module ModelTemplate

    class CoreosInMemory < InMemory
      include(ProjectHanlon::Logging)

      # setup an accessor for the ssh_key instance var
      attr_accessor :ssh_key

      def initialize(hash)
        super(hash)
        # Static config
        @hidden      = false
        @name        = "coreos_in_memory"
        @description = "CoreOS In-Memory"
        # initialize SSH key to nil
        @ssh_key     = nil

        @req_metadata_hash = {
          "@hostname_prefix" => {
            :default     => "node",
            :example     => "node",
            :validation  => '^[a-zA-Z0-9][a-zA-Z0-9\-]*$',
            :required    => true,
            :description => "node hostname prefix (will append node number)"
          },
          "@domainname" => {
            :default     => "localdomain",
            :example     => "example.com",
            :validation  => '^[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9](\.[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])*$',
            :required    => true,
            :description => "local domain name (will be used in /etc/hosts file)"
          },
          "@ssh_key" => {
            :default      => "",
            :example      => "",
            :validation   => '',
            :required     => true,
            :description  => "the (public) SSH key to use when connecting to the CoreOS instance"
          }
        }
        from_hash(hash) unless hash == nil
      end

      def callback
        {
            "ssh-key" => :ssh_key,
        }
      end

      def ssh_key
        return @ssh_key
      end

      def boot_call(node, policy_uuid)
        super(node, policy_uuid)
        case @current_state
          when :init, :preinstall
            @result = "Starting CoreOS In-Memory model boot"
            ret = start_install(node, policy_uuid)
          when :timeout_error, :error_catch
            engine = ProjectHanlon::Engine.instance
            ret = engine.default_mk_boot(node.uuid)
          else
            engine = ProjectHanlon::Engine.instance
            ret = engine.default_mk_boot(node.uuid)
        end
        fsm_action(:boot_call, :boot_call)
        ret
      end


      # will perform an "install" of CoreOS by booting
      # into an in-memory image
      def start_install(node, policy_uuid)
        filepath = template_filepath('boot_install')
        ERB.new(File.read(filepath)).result(binding)
      end

      # ERB.result(binding) is failing in Ruby 1.9.2 and 1.9.3 so template is processed in the def block.
      def template_filepath(filename)
        filepath = File.join(File.dirname(__FILE__), "coreos/#{filename}.erb")
      end

      def kernel_args(policy_uuid)
        filepath = template_filepath('kernel_args_in_memory')
        ERB.new(File.read(filepath)).result(binding)
      end

      def hostname
        "#{@hostname_prefix}#{@counter.to_s}"
      end

      def kernel_path
        "coreos/vmlinuz"
      end

      def initrd_path
        "coreos/cpio.gz"
      end

      # TODO: make optional
      # This will only affect the boot for install. It is helpful to debug errors
      def autologin_kernel_args
        "coreos pxe demo"
      end

      def config
        ProjectHanlon.config
      end

    end
  end
end
