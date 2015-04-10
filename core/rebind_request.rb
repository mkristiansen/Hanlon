# Root ProjectHanlon::Node namespace
class ProjectHanlon::RebindRequest < ProjectHanlon::Object
  attr_accessor :node_uuid
  attr_accessor :timestamp

  # init
  # @param hash [Hash]
  def initialize(hash)
    super()
    @_namespace = :rebind_request
    @noun = "rebind_request"
    @node_uuid = ""
    @timestamp = Time.now.to_i
    from_hash(hash)
  end

  def uuid=(new_uuid)
    @uuid = new_uuid.upcase
  end

  def print_header
    return "UUID", "Node UUID", "Request Time"
  end

  def print_items
    return @uuid, @node_uuid, Time.at(@timestamp.to_i).strftime("%m-%d-%y %H:%M:%S")
  end

  def print_item_header
    return "UUID", "Node UUID", "Request Time"
  end

  def print_item
    return @uuid, @node_uuid, Time.at(@timestamp.to_i).strftime("%m-%d-%y %H:%M:%S"), @node_uuid
  end

  def line_color
    :white_on_black
  end

  def header_color
    :red_on_black
  end

end
