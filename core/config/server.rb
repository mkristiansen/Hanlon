require 'socket'
require 'fcntl'
require 'yaml'
require 'utility'
require 'ipaddr'
require 'facter'
require 'facter/util/ip'
require 'logging/logger'
require 'mkmf'

require 'config/common'

# monkey-patch Facter::Util::IP to fix problems we are seeing under
# Tomcat (where the 'Facter.value(:kernel)' method call returns an
# empty string)
module Facter::Util::IP

  def self.get_interface_value(interface, label)
    # Linux changes the MAC address reported via ifconfig when an ethernet interface
    # becomes a slave of a bonding device to the master MAC address.
    # We have to dig a bit to get the original/real MAC address of the interface.
    bonddev = get_bonding_master(interface)
    if label == 'macaddress' and bonddev
      bondinfo = IO.readlines("/proc/net/bonding/#{bonddev}")
      hwaddrre = /^Slave Interface: #{interface}\n[^\n].+?\nPermanent HW addr: (([0-9a-fA-F]{2}:?)*)$/m
      return hwaddrre.match(bondinfo.to_s)[1].upcase
    end
    # otherwise, get the value associated with that label
    # (using either the 'ip' or 'ifconfig' command)
    get_single_interface_value(interface, label)
  end

  def self.get_interfaces
    # search for 'ifconfig'
    interface_info_cmd = find_executable0('ifconfig', nil)
    # and return the results
    if interface_info_cmd
      output = %x{#{interface_info_cmd} -a}
      # We get lots of warnings on platforms that don't get an output
      # made.
      if output
        return output.scan(/^\w+[.:]?\d+/)
      end
    end
    # if 'ifconfig' was not found, search for 'ip'
    interface_info_cmd = find_executable0('ip', nil)
    if interface_info_cmd
      return %x{ip link | grep ^[0-9] | awk '{print $2}'}.gsub(":\n","\n").split.reject { |val| val == 'lo' }
    end
    []
  end

  def self.get_single_interface_value(interface, label)
    # search for 'ifconfig'
    interface_info_cmd = find_executable0('ifconfig', nil)
    # if 'ifconfig' was found, parse the output of that command to obtain the
    # requested field
    if interface_info_cmd
      # in this case, need to parse the output of the
      # 'ifconfig' command (which varies from kernel to
      # kernel) to find the value that was requested
      REGEX_MAP.each { |kernel, map|
        regex = map[label.to_sym]
        tmp1 = []
        output = %x{#{interface_info_cmd} #{interface}}
        if interface != /^lo[0:]?\d?/
          output.split('\n').each do |s|
            if s =~ regex
              value = $1
              if label == 'netmask' && convert_from_hex?(Facter.value(:kernel).downcase.to_sym)
                value = value.scan(/../).collect do |byte| byte.to_i(16) end.join('.')
              end
              tmp1.push(value)
            end
          end
        end
        if tmp1
          value = tmp1.shift
          return value if value
        end
      }
    end
    # if 'ifconfig' was not found, search for 'ip'
    interface_info_cmd = find_executable0('ip', nil)
    # if we find the 'ip' executable, then use that to obtain
    # the value associated with the label that was passed in
    # Note; we currently only support the 'netmask', 'ipaddress'
    # 'ipaddress6', 'macaddress', and 'mtu' labels when using the 'ip'
    # command; those correspond to the labels supported in the
    # REGEX_MAP defined in Facter::Util::IP
    if interface_info_cmd
      case label
        when 'netmask'
          cidr_str = %x{#{interface_info_cmd} route show dev #{interface} | grep -v '^default' | awk '{print $1}'}.strip
          return '' unless cidr_str.size > 0
          cidr = /^[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}\.[\d]{1,3}\/([\d]{1,2})$/.match(cidr_str)[1].to_i
          output = cidr_to_netmask(cidr)
        when 'ipaddress'
          output = %x{#{interface_info_cmd} route show dev #{interface} | grep -v '^default' | awk '{print $7}'}.strip
        when 'ipaddress6'
          output = %x{#{interface_info_cmd} -6 addr show #{interface} | grep inet6 | awk '{print $2}'}.strip
        when 'macaddress'
          output = %x{#{interface_info_cmd} link show #{interface} | grep link | awk '{print $2}'}.strip
        when 'mtu'
          output = %x{#{interface_info_cmd} link show #{interface} | grep mtu | awk '{print $5}'}.strip
        else
          output = ''
      end
      return output
    end
    ''
  end

  private

  def self.unpack_ip(packed_ip)
    octets = []
    4.times do
      octet = packed_ip & 0xFF
      octets.unshift(octet.to_s)
      packed_ip = packed_ip >> 8
    end
    ip = octets.join('.')
  end

  def self.cidr_to_packed_ip(cidr)
    (("1"*cidr)+("0"*(32-cidr))).to_i(2)
  end

  def self.cidr_to_netmask(cidr)
    unpack_ip(cidr_to_packed_ip(Integer(cidr)))
  end

end

# This class represents the ProjectHanlon configuration. It is stored persistently in
# './web/config/hanlon_server.conf' file and can be edited by the user there

module ProjectHanlon
  module Config
    class Server
      include ProjectHanlon::Utility
      include ProjectHanlon::Logging
      include ProjectHanlon::Config::Common
      extend  ProjectHanlon::Logging

      attr_accessor :hanlon_server
      attr_accessor :hanlon_subnets

      attr_accessor :persist_mode
      attr_accessor :persist_options_file
      attr_accessor :persist_host
      attr_accessor :persist_port
      attr_accessor :persist_username
      attr_accessor :persist_password
      attr_accessor :persist_timeout
      attr_accessor :persist_dbname
      attr_accessor :persist_path

      attr_accessor :ipmi_username
      attr_accessor :ipmi_password
      attr_accessor :ipmi_utility

      attr_accessor :base_path
      attr_accessor :api_version
      attr_accessor :admin_port
      attr_accessor :api_port
      attr_accessor :hanlon_log_level

      attr_accessor :hanlon_cifs_share
      attr_accessor :hanlon_static_path
      attr_accessor :hanlon_cifs_share

      attr_accessor :mk_checkin_interval
      attr_accessor :mk_checkin_skew

      # mk_log_level should be 'Logger::FATAL', 'Logger::ERROR', 'Logger::WARN',
      # 'Logger::INFO', or 'Logger::DEBUG' (default is 'Logger::ERROR')
      attr_accessor :mk_log_level

      attr_accessor :image_path

      attr_accessor :register_timeout
      attr_accessor :force_mk_uuid

      attr_accessor :daemon_min_cycle_time

      attr_accessor :node_expire_timeout

      attr_accessor :hnl_mk_boot_debug_level
      attr_accessor :hnl_mk_boot_kernel_args

      attr_accessor :sui_mount_path
      attr_accessor :sui_allow_access

      attr_reader   :noun

      # Obtain our defaults
      def defaults
        #base_path = SERVICE_CONFIG[:config][:swagger_ui][:base_path]
        #api_version = SERVICE_CONFIG[:config][:swagger_ui][:api_version]
        #default_websvc_root = "#{base_path}/#{api_version}"
        default_base_path = "/hanlon/api"
        default_image_path  = "#{$hanlon_root}/image"
        default_persist_path  = "#{$hanlon_root}/data"
        defaults = {
          'hanlon_server'            => get_an_ip,
          'hanlon_subnets'           => get_initial_hanlon_subnets,
          'persist_mode'             => :mongo,
          'persist_host'             => "127.0.0.1",
          'persist_port'             => 27017,
          'persist_username'         => '',
          'persist_password'         => '',
          'persist_timeout'          => 10,
          'persist_dbname'           => "project_hanlon",
          'persist_options_file'     => '',
          'persist_path'             => default_persist_path,

          'ipmi_username'            => '',
          'ipmi_password'            => '',
          'ipmi_utility'             => '',

          'base_path'                => default_base_path,
          'api_version'              => 'v1',
          'admin_port'               => 8025,
          'api_port'                 => 8026,

          'mk_checkin_interval'      => 60,
          'mk_checkin_skew'          => 5,
          'mk_log_level'             => "Logger::ERROR",

          'image_path'               => default_image_path,

          'register_timeout'         => 120,
          'force_mk_uuid'            => "",

          'daemon_min_cycle_time'    => 30,

          # this is the default value for the amount of time (in seconds) that
          # is allowed to pass before a node is removed from the system.  If the
          # node has not checked in for this long, it'll be removed
          'node_expire_timeout'      => 300,

          # DEPRECATED: use hnl_mk_boot_kernel_args instead!
          # used to set the Microkernel boot debug level; valid values are
          # either the empty string (the default), "debug", or "quiet"
          'hnl_mk_boot_debug_level'   => "Logger::ERROR",
          'hanlon_log_level'          => "Logger::ERROR",
          'hanlon_static_path'        => "",
          'hanlon_cifs_share'         => "",

          # used to pass arguments to the Microkernel's linux kernel;
          # e.g. "console=ttyS0" or "hanlon.ip=1.2.3.4"
          'hnl_mk_boot_kernel_args'   => "",

          # config parameters for swagger_ui management (prefix::sui)
          'sui_mount_path'   => "/docs",
          'sui_allow_access'   => "true"
        }

        return defaults
      end

      def get_initial_hanlon_subnets
        interface_array = Facter::Util::IP.get_interfaces
        subnet_str_array = []
        interface_array.map { |interface_name|
          # skip to next unless looking at loopback interface or IP address is the same as the hanlon_server_ip
          next if interface_name == 'lo'
          ip_addr = Facter::Util::IP.get_interface_value(interface_name,'ipaddress')
          # skip to next if interface does not have an ip address assinged
          next if ip_addr == ""
          netmask = Facter::Util::IP.get_interface_value(interface_name,'netmask')
          # convert our IP address and netmask to a subnet string
          # in CIDR notation
          subnet_str = IPAddr.new("#{ip_addr}/#{netmask}").to_s
          subnet_str_array << "#{subnet_str}/#{netmask_to_cidr(netmask)}"
        }
        subnet_str_array.join(',')
      end

      def netmask_to_cidr(netmask_string)
        # count the number of "1's" in the binary version of the netmask
        # string to determine the CIDR representation of that netmask string
        IPAddr.new(netmask_string).to_i.to_s(2).count("1")
      end

      def mk_fact_excl_pattern
        [
            "(^facter.*$)", "(^id$)", "(^kernel.*$)", "(^memoryfree$)","(^memoryfree_mb$)",
            "(^operating.*$)", "(^osfamily$)", "(^path$)", "(^ps$)",
            "(^ruby.*$)", "(^selinux$)", "(^ssh.*$)", "(^swap.*$)",
            "(^timezone$)", "(^uniqueid$)", "(^.*uptime.*$)","(.*json_str$)"
        ].join("|")
      end

    end
  end
end
