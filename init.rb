require "use_db_plugin"
require "use_db_test"
require 'active_record/fixtures'
require "override_fixtures"
require 'active_record/migration'
require 'override_test_callbacks'
require "migration"

ActiveRecord::Base.extend(UseDbPlugin)
