require_relative "boot"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module PnpmMultiBuildpack
  class Application < Rails::Application
    config.load_defaults 8.1
  end
end
