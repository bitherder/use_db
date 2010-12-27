require "use_db_plugin"
if RAILS_ENV=="test"
  require "use_db_test"
  require 'active_record/fixtures'
  require "override_fixtures"
  require 'override_test_callbacks'
end
require 'active_record/migration'
require "migration"

ActiveRecord::Base.extend(UseDbPlugin)
