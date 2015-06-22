#

require 'json'
require 'api_utils'
require 'slice'
require 'slice/tag'
require 'error'

module Hanlon
  module WebService
    module Tag

      class APIv1 < Grape::API

        version :v1, :using => :path, :vendor => "hanlon"
        format :json
        default_format :json
        SLICE_REF = ProjectHanlon::Slice::Tag.new([])

        rescue_from ProjectHanlon::Error::Slice::InvalidUUID,
                    ProjectHanlon::Error::Slice::MissingArgument,
                    Grape::Exceptions::Validation do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from ProjectHanlon::Error::Slice::CouldNotCreate,
                    ProjectHanlon::Error::Slice::CouldNotUpdate,
                    ProjectHanlon::Error::Slice::CouldNotRemove do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(403, e.class.name, e.message).to_json,
              403,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from :all do |e|
          #raise e
          Rack::Response.new(
              Hanlon::WebService::Response.new(500, e.class.name, e.message).to_json,
              500,
              { "Content-type" => "application/json" }
          )
        end

        helpers do

          def content_type_header
            settings[:content_types][env['api.format']]
          end

          def api_format
            env['api.format']
          end

          def is_uuid?(string_)
            string_ =~ /^[A-Za-z0-9]{1,22}$/
          end

          def get_data_ref
            Hanlon::WebService::Utils::get_data
          end

          def slice_success_response(slice, command, response, options = {})
            Hanlon::WebService::Utils::hnl_slice_success_response(slice, command, response, options)
          end

          def slice_success_object(slice, command, response, options = {})
            Hanlon::WebService::Utils::hnl_slice_success_object(slice, command, response, options)
          end

          def filter_hnl_response(response, filter_str)
            Hanlon::WebService::Utils::filter_hnl_response(response, filter_str)
          end

          def find_matcher_for_tag(tag_uuid, matcher_uuid)
            found_matcher = []
            tag = SLICE_REF.get_object("tag_with_uuid", :tag, tag_uuid)
            raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot find Tag with UUID [#{tag_uuid}]" unless tag && (tag.class != Array || tag.length > 0)
            tag.tag_matchers.each { |matcher|
              found_matcher << [matcher, tag] if matcher.uuid.scan(matcher_uuid).count > 0
            }
            # if it's still an empty array, fill it with something
            found_matcher << [nil, tag] if found_matcher.empty?
            found_matcher.count == 1 ? found_matcher.first : nil
          end

          def get_matchers(tag_uuid)
            matchers = []
            tag = SLICE_REF.get_object("tag_with_uuid", :tag, tag_uuid)
            raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot find Tag with UUID [#{tag_uuid}]" unless tag && (tag.class != Array || tag.length > 0)
            tag.tag_matchers.each { |matcher|
              matchers << matcher
            }
            [matchers, tag]
          end

        end

        resource :tag do

          # GET /tag
          # Query for defined tags.
          #   parameters:
          #     optional:
          #       :filter_str    | String   | A string to use to filter the results  |
          desc "Retrieve a list of all tags"
          params do
            optional :filter_str, type: String, desc: "String used to filter results"
          end
          get do
            filter_str = params[:filter_str]
            tagrules = SLICE_REF.get_object("tagrules", :tag)
            success_object = slice_success_object(SLICE_REF, :get_all_tagrules, tagrules, :success_type => :generic)
            # if a filter_str was provided, apply it here
            success_object['response'] = filter_hnl_response(success_object['response'], filter_str) if filter_str
            # and return the resulting success_object
            success_object
          end     # end GET /tag

          # POST /tag
          # Create a Hanlon tag; note that one of the two 'optional' parameters (the 'tag' or the 'field')
          # must be specified, otherwise an error will be thrown
          #   parameters:
          #     name            | String | The "name" to use for the new tag   |         | Default: unavailable
          #   optional:
          #     tag             | String | The "tag" value                     |         | Default: unavailable
          #     field           | String | The "field" to based a tag on       |         | Default: unavailable
          desc "Create a new tag"
          params do
            requires "name", type: String, desc: "The new tag's name"
            optional "tag", type: String, desc: "The new tag's 'tag' value"
            optional "field", type: String, desc: "Field to base tag on (for value tags)"
          end
          post do
            # check to ensure one of the two optional parameters were included, throw an error
            # if both are missing; also check to ensure that both were not specified, if that is the
            # case then throw an error as well (since the type of tag you're creating is ambiguous)
            raise ProjectHanlon::Error::Slice::InputError, "Usage Error: either a 'tag' or a 'field' must be defined to create a tag" unless params["tag"] || params["field"]
            raise ProjectHanlon::Error::Slice::InputError, "Usage Error: only one of the 'tag' or 'field' parameters can be specified when creating a tag" if params["tag"] && params["field"]
            # create a new tag using the options that were passed into this subcommand,
            # then persist the tag
            tag_params = { "@name" => params["name"] }
            tag_params["@tag"] = params["tag"] if params["tag"]
            tag_params["@field"] = params["field"] if params["field"]
            tagrule = ProjectHanlon::Tagging::TagRule.new(tag_params)
            raise(ProjectHanlon::Error::Slice::CouldNotCreate, "Could not create Tag Rule") unless tagrule
            get_data_ref.persist_object(tagrule)
            slice_success_object(SLICE_REF, :create_tag, tagrule, :success_type => :created)
          end     # end POST /tag

          resource '/:uuid' do

            # GET /tag/{uuid}
            # Query for the state of a specific tag.
            desc "Retrieve details for a specific tag (by UUID)"
            params do
              requires :uuid, type: String, desc: "The tag's UUID"
            end
            get do
              tag_uuid = params[:uuid]
              tagrule = SLICE_REF.get_object("tagrule_by_uuid", :tag, tag_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot find Tag with UUID [#{tag_uuid}]" unless tagrule && (tagrule.class != Array || tagrule.length > 0)
              slice_success_object(SLICE_REF, :get_tagrule_by_uuid, tagrule, :success_type => :generic)
            end     # end GET /tag/{uuid}

            # PUT /tag/{uuid}
            # Update a Hanlon tag (either the name or tag, or boht, can be updated using
            # this endpoint)
            #   parameters:
            #     name            | String | The new "name" to assign to the tag        |         | Default: unavailable
            #     tag             | String | The new "tag" value to assign to the tag   |         | Default: unavailable
            #     field           | String | The new "field" value to assign to the tag |         | Default: unavailable
            desc "Update a specific tag (by UUID)"
            params do
              requires :uuid, type: String, desc: "The tag's UUID"
              optional "name", type: String, desc: "The tag's new name"
              optional "tag", type: String, desc: "The tag's new 'tag' value"
              optional "field", type: String, desc: "The value tag's new 'field' value"
            end
            put do
              # get the input parameters that were passed in as part of the request
              # (at least one of these should be a non-nil value)
              tag_uuid = params[:uuid]
              name = params["name"]
              tag = params["tag"]
              field = params["field"]
              # check the values that were passed in (and gather new meta-data if
              # the --change-metadata flag was included in the update command and the
              # command was invoked via the CLI...it's an error to use this flag via
              # the RESTful API, the req_metadata_hash should be used instead)
              # get the tag to update
              tagrule = SLICE_REF.get_object("tagrule_with_uuid", :tag, tag_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Tag Rule with UUID: [#{tag_uuid}]" unless tagrule && (tagrule.class != Array || tagrule.length > 0)
              # ensure that we don't attempt to update the 'tag' associated with a value tag or the 'field' associated with a tag
              raise ProjectHanlon::Error::Slice::InputError, "Usage Error: cannot update a value tag's 'tag' parameter" if (tagrule.field && !(tagrule.field.empty?) && params["tag"])
              raise ProjectHanlon::Error::Slice::InputError, "Usage Error: cannot update a tag's 'field' parameter" if (tagrule.tag && !(tagrule.tag.empty?) && params["field"])
              tagrule.name = name if name
              tagrule.tag = tag if tag
              tagrule.field = field if field
              raise ProjectHanlon::Error::Slice::CouldNotUpdate, "Could not update Tag Rule [#{tagrule.uuid}]" unless tagrule.update_self
              slice_success_object(SLICE_REF, :update_tag, tagrule, :success_type => :updated)
            end     # end PUT /tag/{uuid}

            # DELETE /tag/{uuid}
            # Remove a Hanlon tag (by UUID)
            desc "Remove a specific tag (by UUID)"
            params do
              requires :uuid, type: String, desc: "The tag's UUID"
            end
            delete do
              tag_uuid = params[:uuid]
              tagrule = SLICE_REF.get_object("tag_with_uuid", :tag, tag_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Tag with UUID: [#{tag_uuid}]" unless tagrule && (tagrule.class != Array || tagrule.length > 0)
              raise ProjectHanlon::Error::Slice::CouldNotRemove, "Could not remove Tag [#{tag.uuid}]" unless get_data_ref.delete_object(tagrule)
              slice_success_response(SLICE_REF, :remove_tag_by_uuid, "Tag [#{tagrule.uuid}] removed", :success_type => :removed)
            end     # end DELETE /tag/{uuid}

            resource :matcher do

              # GET /tag/{uuid}/matcher
              # Query for defined tag matchers (for a given tag).
              #   parameters:
              #     required:
              #       :uuid          | String   | The UUID of the tag to retrieve the matchers for  |
              #     optional:
              #       :filter_str    | String   | A string to use to filter the results             |
              desc "Retrieve a list of all tag matchers (for a given tag)"
              params do
                requires :uuid, type: String, desc: "The tag's UUID"
                optional :filter_str, type: String, desc: "String used to filter results"
              end
              get do
                tag_uuid = params[:uuid]
                filter_str = params[:filter_str]
                matchers, tagrule = get_matchers(tag_uuid)
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Tag with UUID: [#{tag_uuid}]" unless tagrule && (tagrule.class != Array || tagrule.length > 0)
                success_object = slice_success_object(SLICE_REF, :get_all_matchers, matchers, :success_type => :generic)
                # if a filter_str was provided, apply it here
                success_object['response'] = filter_hnl_response(success_object['response'], filter_str) if filter_str
                # and return the resulting success_object
                success_object
              end     # end GET /tag/{uuid}/matcher

              # POST /tag/{uuid}/matcher
              # Create a Hanlon tag matcher (and add to the given tag)
              #   parameters:
              #     key             | String | The "key" to use for the new tag matcher     |    | Default: unavailable
              #     compare         | String | The comparison method to use (like or equal) |    | Default: unavailable
              #     value           | String | The value to compare against                 |    | Default: unavailable
              #     inverse         | String | Should the matcher invert the rule?          |    | Default: unavailable
              desc "Create a new tag matcher (and add to the specified tag)"
              params do
                requires :uuid, desc: "The tag's UUID"
                requires "key", type: String, desc: "The 'key' to use"
                requires "compare", type: String, desc: "The comparison method"
                requires "value", type: String, desc: "The 'value' to match"
                optional "inverse", type: String, desc: "Invert the match?"
              end
              post do
                tag_uuid = params[:uuid]
                tagrule = SLICE_REF.get_object("tagrule_with_uuid", :tag, tag_uuid)
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Tag Rule with UUID: [#{tag_uuid}]" unless tagrule && (tagrule.class != Array || tagrule.length > 0)
                raise ProjectHanlon::Error::Slice::InvalidCommand, "Tag [#{tag_uuid}] is a value tag (based on #{tagrule.field}); cannot add a tag matcher" if tagrule.field
                key = params["key"]
                compare = params["compare"]
                value = params["value"]
                inverse = params["inverse"]
                # if the user is creating a 'like' tag matcher, but the value passed in is
                # not a valid regular expression, then throw an error
                if compare == 'like'
                  begin
                    regex_value = Regexp.new(value)
                  rescue SyntaxError, RegexpError => e
                    raise ProjectHanlon::Error::Slice::CouldNotCreate, "Invalid regexp value; #{e.message}"
                  end
                end
                # if an inverse value was not provided, default to false
                inverse = "false" unless inverse
                raise ProjectHanlon::Error::Slice::MissingArgument, "Value for 'compare' must be [equal|like]" unless compare == "equal" || compare == "like"
                raise ProjectHanlon::Error::Slice::MissingArgument, "Value for 'inverse' must be [true|false]" unless inverse == "true" || inverse == "false"
                matcher = tagrule.add_tag_matcher(:key => key, :compare => compare, :value => value, :inverse => inverse)
                raise ProjectHanlon::Error::Slice::CouldNotCreate, "Could not create tag matcher" unless matcher
                raise(ProjectHanlon::Error::Slice::CouldNotCreate, "Could not create Tag Matcher") unless tagrule.update_self
                slice_success_object(SLICE_REF, :create_matcher, matcher, :success_type => :created)
              end     # end POST /tag/{uuid}/matcher

              resource '/:matcher_uuid' do

                # GET /tag/{uuid}/matcher/{matcher_uuid}
                # Query for the state of a specific tag matcher (for a specific tag).
                desc "Retrieve the details for a tag matcher (for the specified tag)"
                params do
                  requires :uuid, type: String, desc: "The tag's UUID"
                  requires :matcher_uuid, type: String, desc: "The tag matcher's UUID"
                end
                get do
                  tag_uuid = params[:uuid]
                  matcher_uuid = params[:matcher_uuid]
                  matcher, tagrule = find_matcher_for_tag(tag_uuid, matcher_uuid)
                  raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot find Tag Matcher with UUID [#{matcher_uuid}] in Tag with UUID [#{tagrule.uuid}]" unless matcher
                  slice_success_object(SLICE_REF, :get_matcher_by_uuid, matcher, :success_type => :generic)
                end     # end GET /tag/{uuid}/matcher/{matcher_uuid}

                # PUT /tag/{uuid}/matcher/{matcher_uuid}
                # Update a Hanlon tag matcher (values for any of the the key, compare, value, or inverse
                # fields can be updated using this endpoint)
                #   parameters:
                #     key             | String | The "name" to use for the new tag   |         | Default: unavailable
                #     compare         | String | The "tag" value                     |         | Default: unavailable
                #     value           | String | The "tag" value                     |         | Default: unavailable
                #     inverse         | String | The "tag" value                     |         | Default: unavailable
                desc "Update a tag matcher instance (for the specified tag)"
                params do
                  requires :uuid, type: String, desc: "The tag's UUID"
                  requires :matcher_uuid, type: String, desc: "The tag matcher's UUID"
                  optional "key", type: String, desc: "The new 'key'"
                  optional "compare", type: String, desc: "The new comparison method"
                  optional "value", type: String, desc: "The new value to match against"
                  optional "inverse", type: String, desc: "Should the match be inverted?"
                end
                put do
                  # get the input parameters that were passed in as part of the request
                  # (at least one of these should be a non-nil value)
                  tag_uuid = params[:uuid]
                  matcher_uuid = params[:matcher_uuid]
                  key = params["key"]
                  compare = params["compare"]
                  value = params["value"]
                  inverse = params["inverse"]
                  # find the matcher to update
                  matcher, tag = find_matcher_for_tag(tag_uuid, matcher_uuid)
                  # check the parameters received in the request
                  raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot find Tag with UUID [#{tag_uuid}]" unless tag && (tag.class != Array || tag.length > 0)
                  raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot find Tag Matcher with UUID [#{matcher_uuid}] in Tag with UUID [#{tag_uuid}]" unless matcher
                  raise ProjectHanlon::Error::Slice::MissingArgument, "Value for 'compare' must be [equal|like]" unless !compare || compare == "equal" || compare == "like"
                  raise ProjectHanlon::Error::Slice::MissingArgument, "Value for 'inverse' must be [true|false]" unless !inverse || inverse == "true" || inverse == "false"
                  # and update the fields in this matcher
                  matcher.key = key if key
                  matcher.compare = compare if compare
                  matcher.value = value if value
                  matcher.inverse = inverse if inverse
                  # throw an error if cannot update the tag with the new matcher
                  raise ProjectHanlon::Error::Slice::CouldNotUpdate, "Could not update Tag Matcher [#{matcher.uuid}]" unless tag.update_self
                  slice_success_object(SLICE_REF, :update_matcher, matcher, :success_type => :updated)
                end     # end PUT /tag/{uuid}/matcher/{matcher_uuid}

                # DELETE /tag/{uuid}/matcher/{matcher_uuid}
                # Remove a Hanlon tag matcher (by UUID) from the specified Hanlon tag instance
                desc "Remove a tag matcher instance (from the specified tag)"
                params do
                  requires :uuid, type: String, desc: "The tag's UUID"
                  requires :matcher_uuid, type: String, desc: "The tag matcher's UUID"
                end
                delete do
                  tag_uuid = params[:uuid]
                  matcher_uuid = params[:matcher_uuid]
                  matcher, tagrule = find_matcher_for_tag(tag_uuid, matcher_uuid)
                  raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot find Tag with UUID [#{tag_uuid}]" unless tagrule && (tagrule.class != Array || tagrule.length > 0)
                  raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot find Tag Matcher with UUID [#{matcher_uuid}] in Tag with UUID [#{tag_uuid}]" unless matcher && (matcher.class != Array || matcher.length > 0)
                  raise ProjectHanlon::Error::Slice::CouldNotRemove, "Could not remove Tag Matcher [#{matcher.uuid}]" unless tagrule.remove_tag_matcher(matcher.uuid)
                  raise(ProjectHanlon::Error::Slice::CouldNotCreate, "Could not remove Tag Matcher from Tag [#{tagrule.uuid}]") unless tagrule.update_self
                  slice_success_response(SLICE_REF, :remove_matcher, "Tag Matcher [#{matcher.uuid}] removed", :success_type => :removed)
                end     # end DELETE /tag/{uuid}/matcher/{matcher_uuid}

              end     # end resource /tag/:uuid/matcher/:matcher_uuid

            end     # end resource /tag/:uuid/matcher

          end     # end resource /tag/:uuid

        end     # end resource /tag

      end

    end

  end

end
