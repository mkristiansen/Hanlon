module ProjectHanlon
  module ImageService
    # Image construct for generic Operating System install ISOs
    class XenServerHypervisor < ProjectHanlon::ImageService::Base

      attr_accessor :xenserver_version

      def initialize(hash)
        super(hash)
        @description = "XenServer Hypervisor Install"
        @path_prefix = "xenserver"
        @hidden = false
        from_hash(hash) unless hash == nil
      end

      def add(src_image_path, lcl_image_path)
        begin
          resp = super(src_image_path, lcl_image_path)
          if resp[0]
            unless verify(lcl_image_path)
              logger.error "Missing metadata"
              return [false, "Missing metadata"]
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
        if File.exist?("#{image_path}/packages.xenserver/XS-REPOSITORY") &&
            File.exist?("#{image_path}/boot/pxelinux/mboot.c32") &&
            File.exist?("#{image_path}/boot/pxelinux/pxelinux.0")
          begin
            line = File.read("#{image_path}/packages.xenserver/XS-REPOSITORY").split("\n")[0]
            @xenserver_version = line[line.index("version=")+9,5]
            if @xenserver_version
              return [true, '']
            end
            [false, "Missing 'xenserver_version' in ISO"]
          rescue => e
            logger.debug e
            [false, e.message]
          end
        else
          logger.error "Does not look like an XenServer ISO"
          [false, "Does not look like an XenServer ISO"]
        end
      end

      def print_image_info(lcl_image_path)
        super(lcl_image_path)
        print "\tVersion: "
        print "#{@xenserver_version}  \n".green
      end

      def print_item_header
        super.push "Version"
      end

      def print_item
        super.push @xenserver_version
      end

    end
  end
end

