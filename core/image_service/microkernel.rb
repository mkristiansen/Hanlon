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

      def initialize(hash)
        super(hash)
        @description = "MicroKernel Image"
        @path_prefix = "mk"
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
            # add docker image to Microkernel image and extract SSH public key from file
            @docker_image = add_docker_to_mk_image(extra[:docker_image])
            @ssh_key = extract_pub_key(extra[:ssh_keyfile]) if extra[:ssh_keyfile] && !extra[:ssh_keyfile].empty?
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
        # check the kernel_path parameter value
        test_path = kernel_path
        unless File.exists?(test_path)
          logger.error "missing kernel: #{test_path}"
          return [false, "missing kernel: #{test_path}"]
        end
        # check the initrd_path parameter value
        test_path = initrd_path
        unless File.exists?(test_path)
          logger.error "missing initrd: #{test_path}"
          return [false, "missing initrd: #{test_path}"]
        end
        # if all of those checks passed, then return success
        [true, '']
      end

      def add_docker_to_mk_image(docker_image)

      end

      def extract_pub_key(ssh_keyfile)
        # extract SSH public key from the public key file (if that file exists,
        # if it's readable, and if that file is indeed an SSH public key file)

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

      def kernel_path
        image_path + "/boot/vmlinuz"
      end

      def initrd_path
        image_path + "/boot/initrd"
      end

    end
  end
end
