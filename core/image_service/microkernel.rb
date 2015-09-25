require "yaml"
require "digest/sha2"
require "image_service/base"

module ProjectHanlon
  module ImageService
    # Image construct for Microkernel files
    class MicroKernel < ProjectHanlon::ImageService::Base
      attr_accessor :docker_image
      attr_accessor :ssh_key
      attr_accessor :mk_version
      attr_accessor :kernel_hash
      attr_accessor :initrd_hash
      attr_accessor :image_build_time
      attr_accessor :os_version
      attr_accessor :isolinux_cfg

      def initialize(hash)
        super(hash)
        @description = "MicroKernel Image"
        @path_prefix = "mk"
        @ssh_key = nil
        @hidden = false
        from_hash(hash) unless hash == nil
      end

      def add(src_image_path, lcl_image_path, extra)
        # Add the iso to the image svc storage

        begin
          resp = super(src_image_path, lcl_image_path, extra)
          if resp[0]
            success, result_string = verify(lcl_image_path)
            unless success
              logger.error result_string
              return [false, result_string]
            end
            # save Microkernel version (passed in via the body of the RESTful POST)
            @os_version = extra[:os_version]
            # fill in the kernel and initrd hash values (if these files didn't
            # exist, would not have gotten through the 'verify' step, above)
            @kernel_hash = Digest::SHA256.hexdigest(File.read(kernel_path))
            @initrd_hash = Digest::SHA256.hexdigest(File.read(initrd_path))
            # add docker image to Microkernel image directory
            test_filename = extra[:docker_image]
            return [false, "Docker image file '#{test_filename}' does not exist"] unless File.exist?(test_filename)
            @docker_image = add_docker_to_mk_image(extra[:docker_image])
            # recalculate the verification hash now that we've added a file to the
            # Microkernel image directory
            @verification_hash = get_dir_hash(image_path)
            # extract SSH public key (if one was provided) from file
            test_filename = extra[:ssh_keyfile]
            if test_filename && !test_filename.empty?
              return [false, "SSH key file '#{test_filename}' does not exist"] unless File.exist?(test_filename)
              file_contents = File.read(test_filename).split("\n")[0]
              return [false, "File '#{test_filename}' does look like an SSH keyfile"] unless /^ssh\-\S+\s+\S+\s\S+$/.match(file_contents)
              @ssh_key = file_contents
            end
            # retrieve modification time for docker image and add it to the object
            @image_build_time = File.mtime(extra[:docker_image]).utc.to_i
          end
          resp
        rescue => e
            #logger.error e.message
            logger.log_exception e
            raise ProjectHanlon::Error::Slice::InternalError, e.message
        end
      end

      def verify(lcl_image_path)
        # check to make sure that the hashes match (of the file list
        # extracted and the file list from the ISO)
        is_valid, result = super(lcl_image_path)
        unless is_valid
          return [false, result]
        end
        # check for the iso_linux.cfg file we expect to see for
        # a RancherOS-based ISO
        isolinux_path = isolinux_cfg_path
        unless iso_includes_file?(isolinux_path)
          logger.error "missing isolinux.cfg file: #{isolinux_path}"
          return [false, "missing isolinux.cfg file: #{isolinux_path}"]
        end
        # load the parameters from the iso_linux.cfg file into
        # the @isolinux_cfg instance variable
        load_isolinux_cfg(isolinux_path)
        # then check to ensure that the kernel file shown in the
        # iso_linux.cfg file exists at the kernel_path location in
        # the unpacked ISO
        test_path = kernel_path
        unless iso_includes_file?(test_path)
          logger.error "missing kernel: #{test_path}"
          return [false, "missing kernel: #{test_path}"]
        end
        # and perform the same check for the initrd file shown in the
        # isolinux.cfg file
        test_path = initrd_path
        unless iso_includes_file?(test_path)
          logger.error "missing initrd: #{test_path}"
          return [false, "missing initrd: #{test_path}"]
        end
        # if all of those checks passed, then return success
        # (this iso looks like a RancherOS iso and the contents
        # appear to match the contents shown in the isolinux.cfg
        # file from the ISO)
        [true, '']
      end

      # Adds the docker_image (referenced as a local path to a
      # docker image file) to the directory created (above) when
      # the (RancherOS-based) Microkernel ISO was unpacked into
      # the local image path.  Throws an error if the file passed
      # in does not look like a docker image file or if it cannot
      # be copied over to the Microkernel directory under the local
      # image path
      def add_docker_to_mk_image(docker_image)
        FileUtils.cp(docker_image, image_path, { :preserve => true })
      end

      # Used to calculate a "weight" for a given ISO version.  These weights
      # are used to determine which ISO to use when multiple Hanlon-Microkernel
      # ISOS are available.  The complexity in this function results from it's
      # support for the various version numbering schemes that have been used
      # in the Hanlon-Microkernel project over time.  The following four version
      # numbering schemes are all supported:
      #
      #    v0.9.3.0
      #    v0.9.3.0+48-g104a9bc
      #    0.10.0
      #    0.10.0+4-g104a9bc
      #
      # Note that the syntax that is supported is an optional 'v' character
      # followed by a 3 or 4 part version number.  Either of these two formats
      # can be used for the "version tag" that is applied to any given
      # Hanlon-Microkernel release.  The remainder (if it exists) shows the commit
      # number and commit string for the latest commit (if that commit differs
      # from the tagged version).  These strings are converted to a floating point
      # number for comparison purposes, with later releases (in the semantic
      # versioning sense of the word "later") converting to larger floating point
      # numbers
      def version_weight
        # parse the version numbers from the @os_version value
        version_str, commit_no = /^v?(.*)$/.match(@os_version)[1].split("-")[0].split("+")
        # Limit any part of the version number to a number that is 999 or less
        version_str.split(".").map! {|v| v.to_i > 999 ? 999 : v}.join(".")
        # separate out the semantic version part (which looks like 0.10.0) from the
        # "sub_patch number" (to handle formats like v0.9.3.0, which were used in
        # older versions of the Hanlon-Microkernel project)
        version_parts = version_str.split(".").map {|x| "%03d" % x}
        sub_patch = (version_parts.length == 4 ? version_parts[3] : "000")
        # and join the parts as a single floating point number for comparison
        (version_parts[0,3].join + ".#{sub_patch}").to_f + "0.000#{commit_no}".to_f
      end

      def print_item_header
        super.push "Version", "Built Time"
      end

      def print_item
        super.push @os_version.to_s, (Time.at(@image_build_time)).to_s
      end

      def iso_includes_file?(file_path)
        # ensure the file exists and is not empty
        return File.size?(file_path)
      end

      def load_isolinux_cfg(isolinux_path)
        @isolinux_cfg = {}
        File.foreach(isolinux_path) { |line|
          # split line into two words (a key and a value) based on white space
          key, val = line.strip.split(/\s+/, 2)
          @isolinux_cfg[key] = val
        }
      end

      def cloud_config
        config_string = "#cloud-config\n"
        if @ssh_key
          config_string << "ssh_authorized_keys:\n"
          config_string << "  - #{@ssh_key}\n"
        end
        config_string << "write_files:\n"
        config_string << "  - path: /opt/rancher/bin/start.sh\n"
        config_string << "    permissions: 0755\n"
        config_string << "    owner: root\n"
        config_string << "    content: |\n"
        config_string << "      #!/bin/bash\n"
        config_string << "      echo 'Running startup script...'\n"
        config_string
      end

      def isolinux_cfg_path
        image_path + "/boot/isolinux/isolinux.cfg"
      end

      def kernel
        @isolinux_cfg['kernel']
      end

      def kernel_path
        image_path + kernel
      end

      def initrd
        @isolinux_cfg['initrd']
      end

      def initrd_path
        image_path + initrd
      end

    end
  end
end
