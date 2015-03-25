require "erb"

# Root ProjectHanlon namespace
module ProjectHanlon
  module ModelTemplate
    # Root Model object
    # @abstract
    class VMwareESXi5Dhcp < ProjectHanlon::ModelTemplate::VMwareESXi
      include(ProjectHanlon::Logging)

      # # Assigned image
      # attr_accessor :image_uuid
      #
      # # Metadata
      # attr_accessor :hostname
      #
      # # Compatible Image Prefix
      # attr_accessor :image_prefix

      def initialize(hash)
        super(hash)
        # Static config
        @hidden                  = false
        @template                = :vmware_hypervisor
        @name                    = "vmware_esxi_5_dhcp"
        @description             = "VMware ESXi 5 DHCP Deployment"
        @osversion               = "5_dhcp"
        # Metadata vars
        @hostname_prefix         = nil
        # State / must have a starting state
        @current_state           = :init
        # Image UUID
        @image_uuid              = true
        # Image prefix we can attach
        @image_prefix            = "esxi"
        # Enable agent brokers for this model
        @broker_plugin           = :proxy
        @final_state             = :os_complete
        # Metadata vars
        @esx_license             = nil
        @hostname_prefix         = nil
        @vcenter_name            = nil
        @vcenter_datacenter_path = nil
        @vcenter_cluster_path    = nil
        @enable_vsan             = "False"
        @vsan_uuid               = UUID.generate
        @packages                = []
	      @configure_disk_to_local = "False"
        # Metadata
        @req_metadata_hash       = {
            "@esx_license"             => { :default     => "",
                                            :example     => "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE",
                                            :validation  => '^[A-Z\d]{5}-[A-Z\d]{5}-[A-Z\d]{5}-[A-Z\d]{5}-[A-Z\d]{5}$',
                                            :required    => true,
                                            :description => "ESX License Key" },
            "@root_password"           => { :default     => "test1234",
                                            :example     => "P@ssword!",
                                            :validation  => '^[\S]{8,}',
                                            :required    => true,
                                            :description => "root password (> 8 characters)"
            },
            "@hostname_prefix"         => { :default     => "",
                                            :example     => "esxi-node",
                                            :validation  => '^[A-Za-z\d-]{3,}$',
                                            :required    => true,
                                            :description => "Prefix for naming node" }
        }
        @opt_metadata_hash = {
            "@vcenter_name"            => { :default     => "",
                                            :example     => "vcenter01",
                                            :validation  => '^[\w.-]{3,}$',
                                            :required    => false,
                                            :description => "Optional for broker use: the vCenter to attach ESXi node to" },
            "@vcenter_datacenter_path" => { :default     => "",
                                            :example     => "Datacenter01",
                                            :validation  => '^[a-zA-Z\d-]{3,}$',
                                            :required    => false,
                                            :description => "Optional for broker use: the vCenter Datacenter path to place ESXi host in" },
            "@vcenter_cluster_path"    => { :default     => "",
                                            :example     => "Cluster01",
                                            :validation  => '^[a-zA-Z\d-]{3,}$',
                                            :required    => false,
                                            :description => "Optional for broker use: the vCenter Cluster to place ESXi node in" },
            "@enable_vsan"       => { :default     => "False",
                                           :example     => "",
                                           :validation  => '',
                                           :required    => false,
                                           :description => "Join vSAN cluster and create vSAN disk groups" },
            "@vsan_uuid"               => { :default     => "",
                                            :example     => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                                            :validation  => '^[a-z\d]{8}-[a-z\d]{4}-[a-z\d]{4}-[a-z\d]{4}-[a-z\d]{12}$',
                                            :required    => false,
                                            :description => "VMware vSAN UUID.  Use the default or type in" },
            "@packages"                => { :default     => "",
                                            :example     => "",
                                            :validation  => '',
                                            :required    => false,
                                            :description => "Optional for broker use: the vCenter Cluster to place ESXi node in" },
	    "@configure_disk_to_local" => { :default     => "False",
                                            :example     => "",
                                            :validation  => '',
                                            :required    => false,
                                            :description => "Optional for vSAN, should we use non-local disks in vSAN disk group." }
        }

        from_hash(hash) unless hash == nil
      end


      def postinstall
        @arg = @args_array.shift
        case @arg
          when "send_ips"
            # Grab IP string
            @ip_string = @args_array.shift
            logger.debug "Node IP String: #{@ip_string}"
            @node_ip = @ip_string if @ip_string =~ /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/
            return
          when "end"
            fsm_action(:postinstall_end, :postinstall)
            return "ok"
          when "debug"
            ret = ""
            ret << "vcenter: #{@vcenter_name}\n"
            ret << "vcenter: #{@vcenter_datacenter_path}\n"
            ret << "vcenter: #{@vcenter_cluster_path}\n"
            return ret
          else
            return "error"
        end
      end
    end
  end
end
