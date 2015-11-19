module ProjectHanlon
  module ImageService
    # Image construct for generic Operating System install ISOs
    class VMwareHypervisor < ProjectHanlon::ImageService::Base

      attr_accessor :esxi_version
      attr_accessor :boot_cfg

      def initialize(hash)
        super(hash)
        @description = "VMware Hypervisor Install"
        @path_prefix = "esxi"
        @hidden = false
        from_hash(hash) unless hash == nil
      end

      def add(src_image_path, lcl_image_path)
        begin
          resp = super(src_image_path, lcl_image_path)
          if resp[0]
            success, result_string = verify(lcl_image_path)
            unless success
              logger.error result_string
              return [false, result_string]
            end
          end
          resp
        rescue => e
          logger.error e.message
          return [false, e.message]
        end
      end

      def verify(lcl_image_path)
        # check to make sure that the hashes match (of the file list
        # extracted and the file list from the ISO)
        is_valid, result = super(lcl_image_path)
        unless is_valid
          return [false, result]
        end
        # and check some parameters from the files extracted from the ISO
        if File.exist?("#{image_path}/vmware-esx-base-osl.txt") && File.exist?("#{image_path}/boot.cfg")
          begin
            @esxi_version = File.read("#{image_path}/vmware-esx-base-osl.txt", :encoding => 'ISO-8859-1').split("\n")[2].gsub("\r","")
            @boot_cfg =  File.read("#{image_path}/boot.cfg", :encoding => 'ISO-8859-1')
            if @esxi_version && @boot_cfg
              return [true, '']
            end
            # if we got here, could read the files but there wasn't anything in one or
            # the other or both (so return the correct error)
            return [false, "Missing 'esxi_version' and 'boot_cfg' in ISO"] unless @esxi_version || @boot_cfg
            return [false, "Missing 'esxi_version' in ISO"] unless @esxi_version
            [false, "Missing 'boot_cfg' in ISO"]
          rescue => e
            logger.debug e
            [false, e.message]
          end
        else
          logger.error "Does not look like an ESXi ISO"
          [false, "Does not look like an ESXi ISO"]
        end
      end

      def print_image_info(lcl_image_path)
        super(lcl_image_path)
        print "\tVersion: "
        print "#{@esxi_version}  \n".green
      end

      def print_item_header
        super.push "Version"
      end

      def print_item
        super.push @esxi_version
      end

    end
  end
end
