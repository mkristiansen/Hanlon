require "cassandra"
require "set"
require "persist/plugin_interface"

module ProjectHanlon
  module Persist
    # Cassandra database version of {ProjectHanlon::Persist::PluginInterface}
    # used by {ProjectHanlon::Persist::Controller} when ':cassandra' is the 'persist_mode' in
    # ProjectHanlon configuration
    class CassandraPlugin < PluginInterface
      include(ProjectHanlon::Logging)

      # Closes connection if it is active
      #
      # @return [Boolean] Connection status
      #
      def teardown
        logger.debug "Connection teardown"
        @connected_to_db && disconnect
        @connected_to_db
      end

      # Establishes connection to a keyspace in the Cassandra DB cluster
      #
      # @param hostname [String]
      # @param port [Integer]
      # @param username [String] Username that will be used to authenticate to the host
      # @param password [String] Password that will be used to authenticate to the host
      # @param timeout [Integer] Connection timeout
      # @return [Boolean] Connection status
      #
      def connect(hostname, port, username, password, timeout)
        logger.debug "Connecting to Cassandra (#{hostname}:#{port}) with timeout (#{timeout})"
        begin
          hosts = [hostname]
          # @cluster = Cassandra.cluster(username: username, password: password, hosts: hosts, idle_timeout: nil)
          @cluster = Cassandra.cluster(hosts: hosts, idle_timeout: nil)
          @session = start_session
          @connected_to_db = true
        rescue Errors::NoHostsAvailable
          logger.error "Errors::NoHostsAvailable"
          return false
        rescue Errors::AuthenticationError
          logger.error "Errors::AuthenticationError"
          return false
        rescue Errors::ProtocolError
          logger.error "Errors::ProtocolError"
          return false
        rescue Error
          logger.error "Error"
          return false
        end
        @connected_to_db
      end

      # Disconnects connection
      #
      # @return [Boolean] Connection status
      #
      def disconnect
        logger.debug "Disconnecting from Cassandra DB"
        @session.close
        @cluster.close
        @connected_to_db = false
      end

      # Checks whether DB 'ProjectHanlon' is selected in Cassandra DB
      #
      # @return [Boolean] Connection status
      #
      def is_db_selected?
        #logger.debug "Is ProjectHanlon DB selected?(#{(@session != nil and @cluster.active?)})"
        (@connected_to_db && @session.keyspace == $config.persist_dbname)
      end


      # Returns the documents from the collection named 'collection_name'
      #
      # @param collection_name [Symbol]
      # @return [Array<Hash>]
      #
      def object_doc_get_all(collection_name)
        logger.debug "Get all objects from collection (#{collection_name})"
        ensure_table_exists(collection_name)
        collection_by_name(collection_name)
      end

      # Returns the entry keyed by the '@uuid' of the given 'object_doc' from the collection
      # named 'collection_name'
      #
      # @param object_doc [Hash]
      # @param collection_name [Symbol]
      # @return [Hash] or nil if the object cannot be found
      #
      def object_doc_get_by_uuid(object_doc, collection_name)
        uuid = object_doc['@uuid']
        logger.debug "Get document from collection (#{collection_name}) with uuid (#{uuid})"
        ensure_table_exists(collection_name)
        return_doc_array = objects_from_collection(collection_name, uuid)
        return_doc_array.empty? ? nil : return_doc_array[0]
      end

      # Adds or updates 'obj_document' in the collection named 'collection_name' with an incremented
      # '@version' value
      #
      # @param object_doc [Hash]
      # @param collection_name [Symbol]
      # @return [Hash] The updated doc
      #
      def object_doc_update(object_doc, collection_name)
        uuid = object_doc['@uuid']
        logger.debug "Check for document in collection (#{collection_name}) with uuid (#{uuid})"
        ensure_table_exists(collection_name)
        result = @session.execute("SELECT * from #{collection_name} where uuid = '#{uuid}'")
        encoded_object_doc = Utility.encode_symbols_in_hash(object_doc)
        if result.empty?
          logger.debug "Add new document to collection (#{collection_name}) with uuid (#{uuid})"
          @session.execute("INSERT INTO #{collection_name} ( uuid, json_obj_str ) VALUES ( '#{uuid}', '#{JSON.generate(encoded_object_doc)}' )")
        else
          logger.debug "Update document in collection (#{collection_name}) with uuid (#{uuid})"
          @session.execute("UPDATE #{collection_name} set json_obj_str = '#{JSON.generate(encoded_object_doc)}' where uuid = '#{uuid}'")
        end
        object_doc
      end

      # Adds or updates multiple object documents in the collection named 'collection_name'. This will
      # increase the '@version' value of all the documents
      #
      # @param object_docs [Array<Hash>]
      # @param collection_name [Symbol]
      # @return [Array<Hash>] The updated documents
      #
      def object_doc_update_multi(object_docs, collection_name)
        logger.debug "Update documents in collection (#{collection_name})"
        ensure_table_exists(collection_name)
        # We use this to always pull newest
        object_docs.each { |object_doc|
          uuid = object_doc['@uuid']
          encoded_object_doc = Utility.encode_symbols_in_hash(object_doc)
          @session.execute("UPDATE #{collection_name} set json_obj_str = #{JSON.generate(encoded_object_doc)} where uuid = '#{uuid}'")
        }
        object_docs
      end

      # Removes a document identified by from the '@uuid' of the given 'object_doc' from the
      # collection named 'collection_name'
      #
      # @param object_doc [Hash]
      # @param collection_name [Symbol]
      # @return [true] - returns 'true' if an object was removed
      #
      def object_doc_remove(object_doc, collection_name)
        uuid = object_doc['@uuid']
        logger.debug "Remove document in collection (#{collection_name}) with uuid (#{uuid})"
        ensure_table_exists(collection_name)
        @session.execute("DELETE from #{collection_name} where uuid = '#{uuid}'")
        true
      end

      # Removes all documents from the collection named 'collection_name'
      #
      # @param collection_name [Symbol]
      # @return [Boolean] - returns 'true' if all entries were successfully removed
      #
      def object_doc_remove_all(collection_name)
        logger.debug "Remove all documents in collection (#{collection_name})"
        ensure_table_exists(collection_name)
        @session.execute("DELETE from #{collection_name}")
        true
      end


      private # Cassandra internal stuff we don't want exposed'

      # Starts a session connected to the keyspace corresponding to the 'persist_dbname'
      # stated in the Hanlon server configuration; note that if there is no corresponding
      # keyspace in the cluster, then the requested keyspace will be created by this method
      # TODO: sort out how best to handle replication_factor of this keyspace, currently defaults to '1'
      def start_session
        keyspace = $config.persist_dbname
        # if there is no keyspace by this name already in the cluster, then
        # create it (and setup a session that uses it)
        unless @cluster.has_keyspace?(keyspace)
          keyspace_definition = "CREATE KEYSPACE #{keyspace} WITH replication = { 'class': 'SimpleStrategy', 'replication_factor': 1 }"
          session = @cluster.connect
          session.execute(keyspace_definition)
          session.execute("USE #{keyspace}")
          return session
        end
        # else just connect to the existing keyspace
        @cluster.connect(keyspace)
      end

      # checks to ensure that the named table exists; if not it is created
      def ensure_table_exists(collection_name)
        # set a flag to false, will set it to true if we have
        # to create the table
        create_table = false
        # search the keyspace for the collection_name in question
        keyspace = $config.persist_dbname
        result = @session.execute("SELECT columnfamily_name from system.schema_columnfamilies where keyspace_name = '#{keyspace}'")
        if result.empty?
          create_table = true
        else
          matching_records = []
          result.rows.each { |row|
            matching_records << row if row['columnfamily_name'] == collection_name.to_s
          }
          create_table = true if matching_records.empty?
        end
        # if table wasn't found, then create it
        if create_table
          table_definition = "CREATE TABLE #{collection_name} ( uuid TEXT, json_obj_str TEXT, PRIMARY KEY (uuid) )"
          @session.execute(table_definition)
        end
      end

      # Returns the array of matching records (by UUID value) from the the
      # Cassandra DB collection corresponding to the input 'collection_name'
      # as an array of HashMaps (there should be zero or one matching record,
      # since the UUID field is a primary key, but we'll return it as an array
      # for simplicity)
      # @param collection_name [String]
      # @param uuid [String]
      # @return [Hash]
      def objects_from_collection(collection_name, uuid)
        if is_db_selected?
          ensure_table_exists(collection_name)
          result = @session.execute("SELECT * from #{collection_name} where uuid = '#{uuid}'").rows
          return_array = []
          result.each { |row|
            return_array << Utility.decode_symbols_in_hash(JSON.parse!(row['json_obj_str']))
          }
          return_array
        else
          raise "DB appears to be down"
        end
      end

      # Returns contents of the Cassandra DB Collection corresponding to
      # the input 'collection_name' as an array of HashMaps (one per object
      # in the collection)
      # @param collection_name [String]
      # @return [Array<Hash>]
      def collection_by_name(collection_name)
        if is_db_selected?
          result = @session.execute("SELECT * from #{collection_name}").rows
          return_array = []
          result.each { |row|
            return_array << Utility.decode_symbols_in_hash(JSON.parse!(row['json_obj_str']))
          }
          return_array
        else
          raise "DB appears to be down"
        end
      end

    end
  end
end


