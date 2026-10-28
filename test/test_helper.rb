ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module UserFactory
  DEFAULT_PASSWORD = "x".freeze

  def create_user(name:, email:, **attributes)
    User.create!(name: name, email: email, password: DEFAULT_PASSWORD, **attributes)
  end
end

ActiveSupport::TestCase.include(UserFactory)
