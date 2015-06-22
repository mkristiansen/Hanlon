#

require 'json'
require 'socket'
require 'ipaddr'

module Hanlon
  module WebService
    module Utils

      def request_from_hanlon_subnet?(remote_addr)
        # First, retrieve the list of subnets defined in the Hanlon server
        # configuration (this array is represented by a comma-separated string
        # containing the individual subnets managed by the Hanlon server)
        hanlon_subnets = ProjectHanlon.config.hanlon_subnets.split(',')
        # then, test the subnet value for each interface to see if the subnet for
        # that interface includes the remote_addr IP address; return true if any
        # of the interfaces define a subnet that includes that IP address, false
        # if none of them do
        hanlon_subnets.map { |subnet_str|
          # construct a new IPAddr object from each of the subnet strings retrieved
          # from the Hanlon server configuration, then test to see if our remote_addr
          # is in that subnet (if so, map to true, otherwise map to false)
          internal = IPAddr.new(subnet_str)
          internal.include?(remote_addr) ? true : false
        }.include?(true)
      end
      module_function :request_from_hanlon_subnet?

      def request_from_hanlon_server?(remote_addr)
        # return whether the 'remote_addr' is the same as the 'hanlon_server' value
        # declared in the Hanlon server configuration **or** the 'remote_addr' is included
        # in the list of local IP addresses accessible through the 'Socket.ip_address_list'
        # method (if so, we consider the request to be a local request)
        remote_addr == ProjectHanlon.config.hanlon_server ||
            Socket.ip_address_list.map{|val| val.ip_address}.include?(remote_addr)
      end
      module_function :request_from_hanlon_server?

      # Checks to make sure an parameter is a format that supports a noun (uuid, etc))
      def validate_parameter(*param)
        param.each do |a|
          return false unless a && (a.to_s =~ /^\{.*\}$/) == nil && a != '' && a != {}
        end
      end
      module_function :validate_parameter

      # gets a reference to the ProjectHanlon::Data instance (and checks to make sure it
      # is working before returning the result)
      def get_data
        data = ProjectHanlon::Data.instance
        data.check_init
        data
      end
      module_function :get_data

      # used to parse the filter_string argument so that comparisons of names
      # and values can be made in the 'filter_hnl_response' method, below
      #
      # note there is no attempt made here to parse the names or values
      # further; that is left as a task that must be performed later (during
      # the comparison with the response objects being filtered); this method
      # simply transforms the '+' and '=' separated set of name-value pairs
      # in the filter_string to a hash map that can be used to filter response
      # objects, and it is that hash map that is returned from this method
      def parse_filter_string(filter_string)
        name_val_pairs = filter_string.split('+')
        comparison_hash = {}
        name_val_pairs.each { |name_val|
          comparison_pair = Hash[*name_val.split('=').flatten]
          comparison_hash.merge!(comparison_pair)
        }
        comparison_hash
      end
      module_function :parse_filter_string

      # used to obtain the value from the input response object that corresponds
      # to the input fieldname; if a matching field in the response object cannot
      # be found, then a nil will be returned (and the field will be ignored
      # for purposes of matching), otherwise the corresponding value from the
      # response object will be returned.
      #
      # note that the fieldname can take one of two forms, either a 'dot separated'
      # form or a 'string value' form
      #     - in the 'dot separated' case, the assumption is that the fieldname
      #       being used for comparison is embedded in a hash map (or in multiple,
      #       nested hash maps) in the response object; an example of this form would
      #       be a fieldname like 'attributes_hash.macaddress'
      #     - in the 'string value' case, the assumption is that the fieldname
      #       is directly accessible as a fieldname of the response object; an example
      #       of this form would be a fieldname like 'status'
      #     - in either case failing to find a corresponding field at the declared
      #       location in the response will result in an error being thrown from
      #       this method
      def get_object_value(object, fieldname)
        # first, attempt to split the fieldname based on the '.' character
        # (if it exists in the string)
        dot_split = fieldname.split('.')
        if dot_split.size > 1
          # if it's a dot-separated form, then drill down until we find the
          # value that the dot-separated form refers to and return that value
          value = object
          prev_key = dot_split[0]
          dot_split.each { |keyname|
            # throw an error if the 'value' is not a hash (before attempting to retrieve the next 'value')
            raise ProjectHanlon::Error::Slice::InputError, "Parsing of '#{fieldname}' failed; field '#{prev_key}' is not a Hash value" unless value.is_a?(Hash)
            # if get here, then just retrieve the next element from nested hash maps referred
            # to in the dot-separated form (note that for top-level fields the keys will be
            # prefixed with an '@' character but for lower-level fields that will not be the
            # case, this line will retrieve one or the other)
            value = value["@#{keyname}"] || value[keyname]
            # throw an error if a field with the key 'keyname' was not found (it's an illegal reference in that case)
            raise ProjectHanlon::Error::Slice::InputError, "Parsing of '#{fieldname}' failed; field '#{keyname}' cannot be found" unless value
            # otherwise, save this keyname for the next time through the loop and continue
            prev_key = keyname
          }
          return value
        end
        # otherwise, retrieve the field referred to by the fieldname and return
        # that value (note that for top-level fields the keys will be prefixed
        # with an '@' character but for lower-level fields that will not be the
        # case, this line will retrieve one or the other)
        object["@#{fieldname}"] || object[fieldname]
      end
      module_function :get_object_value

      # used to compare the value retrieved from the response object with the
      # input comparison_value, which can take several forms:
      #     - if the comparison value is prefixed by the 'regex:' string, then that
      #       comparison value will be converted into a regular expression and a
      #       regex comparison will be made with the object_value
      #     - if the comparison value contains a set of strings separated by either
      #       the '&' or '|' character, then that comparison value will be further
      #       broken down into an array of strings that will be used for comparison
      #           -> if the object_value is an array, it will be checked to see if
      #              all (in the the '&' case) or at least 1 (in the '|' case) of those
      #              strings are elements of the array; only string comparisons are
      #              supported in this case
      #           -> if the object_value is a string, then it can be matched against
      #              a comparison value containing one or more strings separated by
      #              the '|' character; in that case the value will be considered to
      #              match the comparison value if at least one of those strings from
      #              the comparison value matches the value
      #     - boolean object_values will be converted to strings before attempting
      #       to match against the comparison value, and the match will be made based
      #       on a simple string comparison against the values 'true' or 'false'
      def object_value_matches?(comparison_value, object_value)
        # first, test to see if the comparison value is a regular expression or
        # if it is a set of strings separated by '&' or '|' characters
        comparison_regex = Regexp.new(comparison_value.gsub(/^regex\:/,'')) if /^regex\:/.match(comparison_value)
        or_sep_substrings = comparison_value.split('|') if comparison_value.include?('|')
        and_sep_substrings = comparison_value.split('&') if comparison_value.include?('&')
        # throw an error if both '&' and '|' characters were used in the declared comparison_value string
        # (this method will match based on either a logical AND or a logical OR against the substrings in
        # the comparison_value string, but not both)
        raise ProjectHanlon::Error::Slice::InputError, "Illegal comparison_value; the declared value contains both '&' and '|' separated Strings" if and_sep_substrings && or_sep_substrings
        # throw an error if the comparison_value contains a set of '&' or '|' separated substrings
        # but also contains the string 'regex:' (we don't support logical AND or logical OR matching
        # via substrings that are, themselves, regular expressions)
        regex_in_and_substrings = and_sep_substrings.select { |val| /^regex\:/.match(val) }.size > 0 if and_sep_substrings
        regex_in_or_substrings = or_sep_substrings.select { |val| /^regex\:/.match(val) }.size > 0 if or_sep_substrings
        raise ProjectHanlon::Error::Slice::InputError, "Illegal comparison_value; the declared value contains regular expressions as substrings" if regex_in_and_substrings || regex_in_or_substrings
        # throw an error if we're using an '&' separated set of substrings for our comparison_value
        # but the object_value is not an array (the '&' separated substring construct only makes
        # sense in the case of array comparisons)
        raise ProjectHanlon::Error::Slice::InputError, "Illegal comparison_value; '&' separated strings cannot be compared to a non-Array object" if and_sep_substrings && !(object_value.is_a?(Array))
        # Ensure that the elements of the object_value are converted to a string (if the
        # object_value is an Array)
        object_value.map! { |val| val.to_s } if object_value.is_a?(Array)
        if or_sep_substrings
          # if we found a set of strings separated by '|' characters, then check for
          # a match; in this case the rules for a match depend on whether the
          # object_value is an Array or a String; if it's an Array, then check the
          # intersection between our two arrays (the 'or_sep_substrings' array and
          # the 'object_value' array) to make sure that at least one string matches
          # between the two
          return ((or_sep_substrings & object_value).size > 0) if object_value.is_a?(Array)
          # otherwise, it's a String, so just check to make sure that one of the
          # strings in the 'or_sep_substrings' Array matches
          return or_sep_substrings.include?(object_value)
        elsif and_sep_substrings
          # if we found a set of strings separated by '&' characters, then check for
          # a match; in this case the rules for a match are quite simple, just check
          # to make sure that all elements of the 'and_sep_substrings' array also
          # appear in the 'object_value' array (that the difference between them is
          # the empty set)
          return (and_sep_substrings - object_value).empty?
        elsif object_value.is_a?(Array)
          # if the object_value is an Array, then look for a match within that array;
          # first, if the comparison value was a regular expression, just check to make
          # sure that at least one of the elements in the object_value array matches
          # that regular expression
          return object_value.select { |val| comparison_regex.match(val) }.size > 0 if comparison_regex
          # otherwise, just check to see if the comparison value (assumed to be String
          # at this point) can be found in the object_value array
          return object_value.include?(comparison_value)
        end
        # if we got this far, we're looking at a simple comparison of a String or
        # Regexp against our object_value; if the comparison value passed in is a
        # regular expression, then simply return a regular expression match
        return comparison_regex.match(object_value.to_s) if comparison_regex
        # otherwise, return a simple string comparison
        comparison_value.to_s == object_value.to_s
      end
      module_function :object_value_matches?

      # determines if an input response object is a match according to the
      # rules spelled out in the comparison_hash, returning true for a match
      # and false if a match is not found
      def response_object_matches?(object, comparison_hash)
        # loop through the fieldname/comparison_value pairs in the comparison hash,
        # searching for a match between the comparison value and the corresponding
        # value for the field in the response object that corresponds to that
        # fieldname; if any of the fieldname/comparison_value pairs do not match
        # return false, else return true
        comparison_hash.each { |fieldname, comparison_value|
          object_value = get_object_value(object, fieldname)
          return false unless object_value_matches?(comparison_value, object_value)
        }
        true
      end
      module_function :response_object_matches?

      # used to filter the generic GET responses based on a 'filter_str' containing a set
      # of name/value pairs (where the names are fieldnames in the response to match against
      # and the values are comparison-values that the values from those fieldnames
      # must match for an object in the response to pass through the filter).
      #
      # The filtering done by this method supports a fairly complex syntax for the input
      # 'filter_string' argument.
      #
      # In cases where the parsing fails or a comparison cannot be made, errors will
      # be thrown.  In all cases, attempts are made to make the error as self-explanatory
      # as possible
      def filter_hnl_response(response, filter_string)
        # if response is not an array or if all of the elements in the array are not hashes,
        # then throw an error
        raise ProjectHanlon::Error::Slice::InputError, "Can only filter response arrays" unless response.is_a?(Array) && response.select { |elem| elem.is_a?(Hash) }.size > 0
        raise ProjectHanlon::Error::Slice::InputError, "Can only filter responses that are arrays of hash maps" unless response.select { |elem| elem.is_a?(Hash) }.size == response.size
        # if the response is of the right type, then parse the filter_string
        # to construct a comparison hash
        comparison_hash = parse_filter_string(filter_string)
        # then, expand the response values to construct a corresponding array
        # of objects that we can test for matches to the comparison hash
        expanded_response = response.map { |response_elem|
          if response_elem.has_key?("@uri")
            uri = URI.parse response_elem["@uri"]
            http = Net::HTTP.new(uri.host, uri.port)
            request = Net::HTTP::Get.new(uri.request_uri)
            lcl_response = http.request(request)
            JSON.parse(lcl_response.body)["response"]
          else
            # if get here, it's an error...should only be used for responses
            # that are a collection of objects (which will be a collection
            # of objects containing URIs that refer to specific instances
            # of the object in the input collection)
            raise ProjectHanlon::Error::Slice::InputError, "Can only filter response arrays that contain URIs that reference response objects"
          end
        }
        # determine which objects match based on the comparison hash constructed
        # from the filter_string (above)
        matching_indexes = response.each_index.select { |index|
          response_object_matches?(expanded_response[index], comparison_hash)
        }
        # and use the list of indexes that matched to filter the response array
        # to only include the elements that matched
        response.values_at(*matching_indexes)
      end
      module_function :filter_hnl_response

      # used to construct a response to a RESTful request that is similar to the "slice_success"
      # response used previously by Hanlon
      def hnl_slice_success_response(slice, command, response, options = {})
        mk_response = options[:mk_response] ? options[:mk_response] : false
        type = options[:success_type] ? options[:success_type] : :generic
        # Slice Success types
        # Created, Updated, Removed, Retrieved. Generic
        return_hash = {}
        return_hash["resource"] = slice.class.to_s
        return_hash["command"] = command.to_s
        return_hash["result"] = slice.success_types[type][:message]
        return_hash["http_err_code"] = slice.success_types[type][:http_code]
        return_hash["errcode"] = 0
        return_hash["response"] = response
        return_hash["client_config"] = ProjectHanlon.config.get_client_config_hash if mk_response
        return_hash
      end
      module_function :hnl_slice_success_response

      # a method similar hnl_slice_success_response method (above) that properly returns
      # a Hanlon object (or array of Hanlon objects) as part of the response
      def hnl_slice_success_object(slice, command, hnl_object, options = { })
        if hnl_object.respond_to?(:collect)
          # if here, it's a collection
          if slice.uri_root
            # if here, then we can reduce the details down and just show a URI to access
            # each element of the collection
            hnl_object = hnl_object.collect do |element|
              elem_hash = element.to_hash
              if element.respond_to?("is_template") && element.is_template
                key_field = ""
                additional_uri_str = ""
                if slice.class.to_s == 'ProjectHanlon::Slice::Broker'
                  key_field = "@plugin"
                  additional_uri_str = "plugins"
                elsif slice.class.to_s == 'ProjectHanlon::Slice::Model'
                  key_field = "@name"
                  additional_uri_str = "templates"
                elsif slice.class.to_s == 'ProjectHanlon::Slice::Policy'
                  key_field = "@template"
                  additional_uri_str = "templates"
                end
                # filter down to just the #{key_field}, @classname, and @noun fields and add a URI
                # (based on the name fo the template) to the element we're returning that can
                # be used to access the details for that element
                test_array = [key_field, "@classname", "@noun"]
                elem_hash = Hash[elem_hash.reject { |k, v| !test_array.include?(k) }]
                slice.add_uri_to_object_hash(elem_hash, key_field, additional_uri_str)
              else
                # filter down to just the @uuid, @classname, and @noun fields and add a URI
                # to the element we're returning that can be used to access the details for
                # that element
                temp_fields = %w(@uuid @classname @noun) + class_from_string(slice.class.to_s).additional_fields
                elem_hash = Hash[elem_hash.reject { |k, v| !temp_fields.include?(k) }]
                slice.add_uri_to_object_hash(elem_hash)
              end
              elem_hash
            end
          else
            # if here, then there is no way to reference each element using
            # a URI, so show the full details for each
            hnl_object = hnl_object.collect { |element| element.to_hash }
          end
        else
          # if here, then we're dealing with a single object, not a collection
          # so show the full details
          hnl_object = hnl_object.to_hash
        end
        hnl_slice_success_response(slice, command, hnl_object, options)
      end
      module_function :hnl_slice_success_object

    end
  end
end
