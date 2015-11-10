
hnl_uri = ProjectHanlon.config.hanlon_uri + ProjectHanlon.config.websvc_root

describe 'Hanlon::WebService::Node' do

  include ProjectHanlon::HttpHelper

  before(:all) do
    $hw_id = UUID.generate
  end

  describe 'resource :node' do

    # Moved this endpoint to the top of the test order to have a node for testing
    describe 'resource :register' do
      describe 'POST /node/register' do
        it 'Handles a node registration request (by a Microkernel instance)' do
          uri = URI.parse(hnl_uri + '/node/register')

          uuid = $hw_id
          last_state = 'idle'
          attributes_hash = {
              :hostname => 'hanlon.example.com',
              :ip_address => '1.1.1.1'
          }

          body_hash = {
              :uuid => uuid,
              :last_state => last_state,
              :attributes_hash => attributes_hash,
          }
          json_data = body_hash.to_json

          # make the request
          hnl_response, http_response = hnl_http_post_json_data(uri, json_data, true)
          # parse the output and validate
          parsed = JSON.parse(http_response.body)
          expect(parsed['resource']).to eq('ProjectHanlon::Slice::Node')
          expect(parsed['command']).to eq('register_node')
          expect(parsed['result']).to eq('Ok')
          expect(parsed['http_err_code']).to eq(200)
          expect(parsed['errcode']).to eq(0)
          # make sure we are getting the same hw_id in return
          expect(hnl_response['@hw_id']).to include($hw_id.upcase)
          # save the created UUID for later use
          $node_uuid = hnl_response['@uuid']
        end
      end   # end POST /node/register
    end   # end resource :register

    describe 'GET /node' do
      it 'Returns a list of all node instances' do
        uri = URI.parse(hnl_uri + '/node')
        # make the request
        hnl_response, http_response = hnl_http_get(uri, true)
        # parse the output and validate
        parsed = JSON.parse(http_response.body)
        expect(parsed['resource']).to eq('ProjectHanlon::Slice::Node')
        expect(parsed['command']).to eq('get_all_nodes')
        expect(parsed['result']).to eq('Ok')
        expect(parsed['http_err_code']).to eq(200)
        expect(parsed['errcode']).to eq(0)
        expect(hnl_response).to_not be(nil)
      end

    end   # end GET /node

    describe 'GET /node?uuid={smbiosuuid}' do
      it 'Returns the details for a specific node (by SMBIOS UUID)' do
        uri = URI.parse(hnl_uri + '/node?uuid=' + $hw_id)
        # make the request
        hnl_response, http_response = hnl_http_get(uri, true)
        # parse the output and validate
        parsed = JSON.parse(http_response.body)
        expect(parsed['resource']).to eq('ProjectHanlon::Slice::Node')
        expect(parsed['command']).to eq('get_node_by_hw_id')
        expect(parsed['result']).to eq('Ok')
        expect(parsed['http_err_code']).to eq(200)
        expect(parsed['errcode']).to eq(0)
        # make sure we are getting the same hw_id in return
        expect(hnl_response['@hw_id']).to include($hw_id.upcase)
        # make sure we are getting the same node
        expect(hnl_response['@uuid']).to eq($node_uuid)
      end
    end   # end GET /node/{uuid}

    describe 'resource :power' do

      describe 'GET /node/power' do
        # it 'Returns the power state of a node (by hw_id)' do
        #   # TODO - 'resource :power' not yet implemented
        #
        # end
      end   # end GET /node/power

      describe 'POST /node/power' do
        # it 'Resets the power state of a node (by hw_id)' do
        #   # TODO - 'resource :power' not yet implemented
        #
        # end
      end   # end POST /node/power

    end   # end resource :power

    describe 'resource :checkin' do
      describe 'GET /node/checkin' do
        it 'Handles a node checkin (by a Microkernel instance)' do
          uri = URI.parse(hnl_uri + "/node/checkin?hw_id=#{$hw_id}&last_state=idle_test")
          # make the request
          hnl_response, http_response = hnl_http_get(uri, true)
          # parse the output and validate
          parsed = JSON.parse(http_response.body)
          expect(parsed['resource']).to eq('ProjectHanlon::Slice::Node')
          expect(parsed['command']).to eq('checkin_node')
          expect(parsed['result']).to eq('Ok')
          expect(parsed['http_err_code']).to eq(200)
          expect(parsed['errcode']).to eq(0)
          expect(hnl_response['command_name']).to eq('acknowledge')
        end
      end   # end GET /node/checkin
    end   # end resource :checkin

    # resource :register goes here in hierarchy but was moved to the top to create a node for testing

    describe 'resource /:uuid' do

      describe 'GET /node/{uuid}' do
        it 'Returns the details for a specific node (by uuid)' do
          uri = URI.parse(hnl_uri + '/node/' + $node_uuid)
          # make the request
          hnl_response, http_response = hnl_http_get(uri, true)
          # parse the output and validate
          parsed = JSON.parse(http_response.body)
          expect(parsed['resource']).to eq('ProjectHanlon::Slice::Node')
          expect(parsed['command']).to eq('get_node_by_uuid')
          expect(parsed['result']).to eq('Ok')
          expect(parsed['http_err_code']).to eq(200)
          expect(parsed['errcode']).to eq(0)
          # make sure we are getting the same hw_id in return
          expect(hnl_response['@hw_id']).to include($hw_id.upcase)
          # make sure we are getting the same node
          expect(hnl_response['@uuid']).to eq($node_uuid)
        end
      end   # end GET /node/{uuid}

      describe 'resource :power' do

        describe 'GET /node/{uuid}/power' do
          # it 'Returns the power state of a specific node (by uuid)' do
          #   # TODO - 'resource :power' not yet implemented
          #
          # end
        end   # end GET /node/{uuid}/power

        describe 'POST /node/{uuid}/power' do
          # it 'Resets the power state of a specific node (by uuid)' do
          #   # TODO - 'resource :power' not yet implemented
          #
          # end
        end   # end POST /node/{uuid}/power

      end   # end resource :power

    end   # end resource /:uuid

  end   # end resource :node

end
