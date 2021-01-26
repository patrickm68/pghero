require "bundler/setup"
require "combustion"
Bundler.require(:default)
require "minitest/autorun"
require "minitest/pride"
require "pg_query"
require "activerecord-import"

class Minitest::Test
  def database
    @database ||= PgHero.databases[:primary]
  end
end

logger = ActiveSupport::Logger.new(ENV["VERBOSE"] ? STDERR : nil)

Combustion.path = "test/internal"
Combustion.initialize! :active_record, :action_controller do
  config.action_controller.logger = logger
  config.active_record.logger = logger
end

class City < ActiveRecord::Base
end

class State < ActiveRecord::Base
end

class User < ActiveRecord::Base
end

states =
  50.times.map do |i|
    {
      name: "State #{i}"
    }
  end
State.import states, validate: false
ActiveRecord::Base.connection.execute("ANALYZE states")

users =
  5000.times.map do |i|
    city_id = i % 100
    {
      city_id: city_id,
      email: "person#{i}@example.org",
      login_attempts: rand(30),
      zip_code: i % 40 == 0 ? nil : "12345",
      active: true,
      country: "Test #{rand(30)}",
      tree_path: "path#{rand(30)}",
      range: (0..rand(5)),
      metadata: {favorite_color: "red"},
      created_at: Time.now - rand(50).days,
      updated_at: Time.now - rand(50).days
    }
  end
User.import users, validate: false
ActiveRecord::Base.connection.execute("ANALYZE users")
