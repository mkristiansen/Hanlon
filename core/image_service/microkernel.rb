require "yaml"
require "digest/sha2"
require "image_service/base"

module ProjectHanlon
  module ImageService
    # Image construct for Microkernel files
    class MicroKernel < ProjectHanlon::ImageService::Base
      attr_accessor :docker_image
      attr_accessor :ssh_key
      attr_accessor :mk_password
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
        @mk_password = nil
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
            # and set the mk_password using the 'mk_password' parameter (if one was provided)
            password = extra[:mk_password]
            @mk_password = password if password && !password.empty?
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
        File.basename(docker_image)
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
        version_str, commit_no = /^v?(.*)$/.match(@os_version)[1].split("-")[0].split("_")
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
        config = ProjectHanlon.config
        host_tmp_dir = '/container-tmp-files'
        image_svc_uri = "http://#{config.hanlon_server}:#{config.api_port}#{config.websvc_root}/image/mk/#{uuid}"
        config_string = "#cloud-config\n"
        if @ssh_key
          config_string << "ssh_authorized_keys:\n"
          config_string << "  - #{@ssh_key}\n"
        end
        config_string << "write_files:\n"
        config_string << "  - path: #{host_tmp_dir}/first_checkin.yaml\n"
        config_string << "    permissions: 644\n"
        config_string << "    owner: root\n"
        config_string << "    content: |\n"
        config_string << "      --- true\n"
        config_string << "  - path: #{host_tmp_dir}/mk_conf.yaml\n"
        config_string << "    permissions: 644\n"
        config_string << "    owner: root\n"
        config_string << "    content: |\n"
        config_string << "      mk_register_path: #{config.websvc_root}/node/register\n"
        config_string << "      mk_uri: http://#{config.hanlon_server}:#{config.api_port}\n"
        config_string << "      mk_checkin_interval: #{config.mk_checkin_interval}\n"
        config_string << "      mk_checkin_path: #{config.websvc_root}/node/checkin\n"
        config_string << "      mk_checkin_skew: #{config.mk_checkin_skew}\n"
        config_string << "      mk_fact_excl_pattern: #{config.mk_fact_excl_pattern}\n"
        config_string << "      mk_log_level: #{config.mk_log_level}\n"
        config_string << "  - path: #{host_tmp_dir}/mk-version.yaml\n"
        config_string << "    permissions: 644\n"
        config_string << "    owner: root\n"
        config_string << "    content: |\n"
        config_string << "      --- \n"
        config_string << "      mk_version: #{os_version}\n"
        config_string << "  - path: /opt/rancher/bin/listen-cmd-channel.sh\n"
        config_string << "    permissions: 755\n"
        config_string << "    owner: root\n"
        config_string << "    content: |\n"
        config_string << "      #!/bin/bash\n"
        config_string << "      [ -d #{host_tmp_dir}/cmd-channels ] || mkdir #{host_tmp_dir}/cmd-channels\n"
        config_string << "      [ -e #{host_tmp_dir}/cmd-channels/node-state-channel ] || mkfifo #{host_tmp_dir}/cmd-channels/node-state-channel\n"
        config_string << "      while read msg < #{host_tmp_dir}/cmd-channels/node-state-channel; do\n"
        config_string << "        if [ \"$msg\" = \"reboot\" ]; then\n"
        config_string << "          reboot\n"
        config_string << "        elif [ \"$msg\" = \"poweroff\" ]; then\n"
        config_string << "          poweroff\n"
        config_string << "        else\n"
        config_string << "          echo \"message '$msg' unrecognized\"\n"
        config_string << "        fi\n"
        config_string << "      done\n"
        config_string << "  - path: /opt/rancher/bin/start-mk.sh\n"
        config_string << "    permissions: 755\n"
        config_string << "    owner: root\n"
        config_string << "    content: |\n"
        config_string << "      #!/bin/bash\n"
        config_string << "      \n"
        config_string << "      # download Microkernel image from Hanlon server\n"
        config_string << "      cd /tmp\n"
        config_string << "      wget #{image_svc_uri}/#{docker_image}\n"
        config_string << "      # wait until docker daemon is running\n"
        config_string << "      prev_time=0\n"
        config_string << "      sleep_time=1\n"
        config_string << "      while true; do\n"
        config_string << "        # break out of loop if docker daemon is in process table\n"
        config_string << "        ps aux | grep `cat /var/run/docker.pid` | grep -v grep 2>&1 > /dev/null && break\n"
        config_string << "        tmp_val=$((prev_time+sleep_time))\n"
        config_string << "        prev_time=$sleep_time\n"
        config_string << "        sleep_time=$tmp_val\n"
        config_string << "        sleep $sleep_time\n"
        config_string << "      done\n"
        config_string << "      # load Microkernel image and start the Microkernel\n"
        config_string << "      docker load -i #{docker_image}\n"
        config_string << "      docker run --privileged=true --name=hnl_mk -v /proc:/host-proc:ro -v /dev:/host-dev:ro -v /sys:/host-sys:ro -v #{host_tmp_dir}:/tmp -d --net host -t `docker images -q` /bin/bash -c '/usr/local/bin/hnl_mk_init.rb && read -p \"waiting...\"'\n"
        config_string << "  - path: /opt/rancher/bin/start.sh\n"
        config_string << "    permissions: 755\n"
        config_string << "    owner: root\n"
        config_string << "    content: |\n"
        config_string << "      #!/bin/bash\n"
        config_string << "      /opt/rancher/bin/listen-cmd-channel.sh &\n"
        config_string << "      /opt/rancher/bin/start-mk.sh &\n"
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
