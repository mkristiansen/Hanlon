require './application'
require 'yaml'

Encoding.default_external = Encoding::UTF_8

hanlon_config = YAML::load(File.open('config/hanlon_server.conf'))

use Rack::Static,
    :urls => ["/images", "/js", "/css"],
    :root => "public",
    :index => "index.html",
    :header_rules => [
      [:all, {'Cache-Control' => 'public, max-age=86400'}]
    ]

run Rack::URLMap.new(
    hanlon_config['base_path'] => Hanlon::WebService::App.new
)