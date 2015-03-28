require 'config/server'

module ProjectHanlon
  module Persist
    # Json version of {ProjectHanlon::Persist::PluginInterface}
    # used by {ProjectHanlon::Persist::Controller} when ':json' is the 'persist_mode'
    # in ProjectHanlon configuration
    # persists as "#{Hanlon.config.persist_path}/#{collection_name}/#{uuid}.json"

    class JsonPlugin < PluginInterface
      include(ProjectHanlon::Logging)
      # Closes connection if it is active
      #
      # @return [Boolean] Connection status
      #
      def teardown
        @collections = nil
      end

      def persist_path
        # can't seem to reach that from here
        #Hanlon.config.persist_path
        $config.persist_path
      end

      # Establishes connection to the data store.
      #
      # @param hostname [String] DNS name or IP-address of host
      # @param port [Integer] Port number to use when connecting to the host
      # @param username [String] Username that will be used to authenticate to the host
      # @param password [String] Password that will be used to authenticate to the host
      # @param timeout [Integer] Connection timeout
      # @return [Boolean] Connection status
      #
      def connect(hostname, port, username, password, timeout)
        @collections=Hash.new
        begin
          # loop through collections:
          Dir.glob("#{persist_path}/*/").each do |collection_dir|
            collection_name=File.basename(collection_dir).to_sym
            @collections[collection_name]=Hash.new
            Dir.glob("#{persist_path}/#{collection_name}/*.json").each do |object_file|
              object_key = File.basename(object_file).sub(/.json$/,'')
              object_json = File.read(object_file)
              object_doc = JSON.parse(object_json)
              @collections[collection_name][object_key] = object_doc
            end
          end
          # if File.exists?(json_file)
          #   logger.debug "Loading from existing JSON file: (#{json_file})"
          #   json_content = File.read(json_file)
          #   logger.debug "JSON content: #{json_content}"
          #   @collections = JSON.load json_content
          #   logger.debug "@collections = #{@collections}"
          # else
          #   logger.debug "Creating empty JSON file: (#{json_file})"
          #   @collections = Hash.new do |hash, key| hash[key] = {} end
          # end
        rescue Exception => e
          puts 'WE CAUGHT IT'
          raise e
          #           if e.message.include? 'database "' + dbname + '" does not exist'
          #             @connection = create_database(hostname, port, username, password, db
          # name, timeout)
          #           else
          #             logger.error e.message
          #             raise
        end
        !!@collections.keys
      end

      def write_json(object_doc,collection_name)
        uuid=object_doc['@uuid']
        json_file="#{persist_path}/#{collection_name}/#{uuid}.json"
        logger.debug "Persisting to JSON file: (#{json_file})"
        begin
          File.open(json_file, 'w') {|f| f.write JSON.pretty_generate(object_doc)}
          #            File.write(json_file)JSON.dump(@collections)
        rescue Exception => e
          puts 'WE CAUGHT IT'
          raise e
          #           if e.message.include? 'database "' + dbname + '" does not exist'
          #             @connection = create_database(hostname, port, username, password, db
          # name, timeout)
          #           else
          #             logger.error e.message
          #             raise
        end
      end

      # Disconnects connection
      #
      # @return [Boolean] Connection status
      #
      def disconnect
        return if not @collections
        @collections = nil
      end

      # Checks whether the database is connected and active
      #
      # @return [Boolean] Connection status
      #
      def is_db_selected?
        !!@collections
      end

      # Returns all entries from the collection named 'collection_name'
      #
      # @param collection_name [Symbol]
      # @return [Array<Hash>]
      #
      def object_doc_get_all(collection_name)
        if @collections[collection_name]
          @collections[collection_name].values
        else
          []
        end
      end

      # Returns the entry keyed by the '@uuid' of the given 'object_doc' from the collection
      # named 'collection_name'
      #
      # @param object_doc [Hash]
      # @param collection_name [Symbol]
      # @return [Hash] or nil if the object cannot be found
      #
      def object_doc_get_by_uuid(object_doc, collection_name)
        if not @collections[collection_name]
          return nil 
        end
        entry = @collections[collection_name][object_doc['@uuid']]
        if entry
          entry
        else
          nil
        end
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
        raise ArgumentError.new('Document has no uuid') if uuid === nil

        # create collection in memory and create it's folder on disk
        entries = @collections[collection_name]
        if entries === nil
          @collections[collection_name] = Hash.new
        end
        unless Dir.exists? "#{persist_path}/#{collection_name}"
          FileUtils.mkdir_p "#{persist_path}/#{collection_name}"
        end

        # bump object_doc version if it already exists
        current_entry = @collections[collection_name][uuid]
        if current_entry === nil
          version = 1
        else
          old_version = current_entry['@version']
          version = (old_version > 0 ? old_version : current_entry[:version]) + 1
        end
        object_doc['@version'] = version

        # write to memory and disk
        @collections[collection_name][uuid] = object_doc
        write_json(object_doc,collection_name)
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
        object_docs.collect {|object_doc|object_doc_update(object_doc,collection_name)}
      end

      # Removes a document identified by from the '@uuid' of the given 'object_doc' from the
      # collection named 'collection_name'
      #
      # @param object_doc [Hash]
      # @param collection_name [Symbol]
      # @return [Boolean] - returns 'true' if an object was removed
      #
      def object_doc_remove(object_doc, collection_name)
        uuid = object_doc['@uuid']
        raise ArgumentError.new('Document has no uuid') if uuid === nil
        entries = @collections[collection_name]
        entries.delete(uuid) unless entries === nil
        json_file="#{Hanlon.config.persist_path}/#{collection_name}/#{uuid}.json"
        File.delete(json_file)
        true
      end

      # Removes all documents from the collection named 'collection_name'
      #
      # @param collection_name [Symbol]
      # @return [Boolean] - returns 'true' if all entries were successfully removed
      #
      def object_doc_remove_all(collection_name)
        @collections[collection_name].values.each do |object_doc|
          object_doc_remove(object_doc,collection_name)
        end
        true
      end
    end
  end
end
