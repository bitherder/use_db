$: << Pathname.new(__FILE__).dirname + '../..'
$: << Pathname.new(__FILE__).dirname + '..'

require 'init'
def in_db_context(db_group)
  ActiveRecord::Base.with_db db_group do
    yield ActiveRecord::Base.connection.instance_eval{@config}
  end
end

def use_db_load_config(db_group)
  require 'active_record'
  
  @original_config = ActiveRecord::Base.configurations
  group_config = UseDbPlugin.db_config(db_group)
  all_configs = Rails::Configuration.new.database_configuration
  group_configs = all_configs.inject({}) do |configs, (name, config)|
    name = name
    if name =~ /^#{group_config[:prefix]}(.*?)#{group_config[:suffix]}$/
      configs[$1] = config
    end
    configs
  end
  
  ActiveRecord::Base.configurations = group_configs
  
  if block_given?
    yield
    restore_config
  end
end

def restore_config
  ActiveRecord::Base.configurations = @original_config
end

namespace :db do
  namespace :reset do
    desc "reset the main and all ancilliary databases"
    task :all => "db:reset"
  end
  
  namespace :migrate do
    namespace :reset do
      desc "reset the main and all ancilliary databases"
      task :all => "db:migrate:reset"
    end
  end
  
  namespace :schema do
    namespace :load do
      desc "load the schema for all the databases"
      task :all => 'db:schema:load'
    end
    
    namespace :dump do
      desc "dump the schema for all the databases"
      task :all => 'db:schema:dump'
    end
  end
end

namespace :fordb do
  db_groups = UseDbPlugin.load_config_file('use_db.yml').keys
  db_groups.each do |db_group|    
    namespace db_group do
      desc 'Raises an error if there are pending migrations'
      task :abort_if_pending_migrations => :environment do
        UseDbPlugin.with_db db_group do |conn_config|
          migration_dir = ActiveRecord::Base.migration_dir
          pending_migrations = ActiveRecord::Migrator.new(:up, migration_dir).pending_migrations

          if pending_migrations.any?
            puts "You have #{pending_migrations.size} pending migrations for #{db_group}:"
            pending_migrations.each do |pending_migration|
              puts '  %4d %s' % [pending_migration.version, pending_migration.name]
            end
            abort %{Run "rake db:migrate" to update your database then try again.}
          end
        end
      end
      
      Rake::Task['db:abort_if_pending_migrations'].enhance ["fordb:#{db_group}:abort_if_pending_migrations"]
      
      desc "Retrieves the charset for the current environment's database"
      task :charset => :environment do
        original_env = RAILS_ENV
        RAILS_ENV = UseDbPlugin.db_config_name(db_group)
        print "#{db_group}: "
        Rake::Task['db:charset'].actions.first.call
        RAILS_ENV = original_env
      end
      
      Rake::Task['db:charset'].enhance do
        Rake::Task["fordb:#{db_group}:charset"].invoke
      end
      
      desc "Retrieves the collation for the current environment's database"
      task :collation => :environment do
        original_env = RAILS_ENV
        RAILS_ENV = UseDbPlugin.db_config_name(db_group)
        print "#{db_group}: "
        Rake::Task['db:collation'].actions.first.call
        RAILS_ENV = original_env
      end
      
      Rake::Task['db:collation'].enhance do
        Rake::Task["fordb:#{db_group}:collation"].invoke
      end
      
      desc 'Create the database defined in config/database.yml for the current RAILS_ENV'
      task :create => "db:load_config" do
        original_env = RAILS_ENV
        RAILS_ENV = UseDbPlugin.db_config_name(db_group)
        Rake::Task['db:create'].actions.first.call
        RAILS_ENV = original_env
      end
      
      namespace :create do
        desc 'Create all the local databases defined in config/database.yml'
        task :all do
          use_db_load_config(db_group) do
            Rake::Task['db:create:all'].actions.first.call
          end
        end
      end

      desc 'Drops the database for the current RAILS_ENV'
      task :drop do
        use_db_load_config(db_group) do
          config = UseDbPlugin.db_conn_spec db_group
          drop_database(config)
        end
      end

      namespace :drop do
        desc 'Drops all the local databases defined in config/database.yml'
        task :all do
          use_db_load_config(db_group) do
            Rake::Task['db:drop:all'].actions.first.call
          end
        end
      end
      
      namespace :fixtures do
        desc 'Search for a fixture given a LABEL or ID.'
        task :identify => :environment do
          UseDbPlugin.with_db db_group do
            original_path = ENV['FIXTURES_PATH']
            ENV['FIXTURES_PATH'] ||= ActiveRecord::Base.fixtures_dir
            Rake::Task['db:fixtures:identify'].invoke
            ENV['FIXTURES_PATH'] = original_path
          end
        end
        
        desc "Load fixtures into the current environment's database."
        task :load => :environment do
          UseDbPlugin.with_db db_group, :set_rails_env => true do
            original_path = ENV['FIXTURES_PATH']
            ENV['FIXTURES_PATH'] ||= ActiveRecord::Base.fixtures_dir
            Rake::Task['db:fixtures:load'].actions.first.call
            ENV['FIXTURES_PATH'] = original_path
          end
        end
        
        Rake::Task['db:fixtures:load'].enhance do
          Rake::Task["fordb:#{db_group}:fixtures:load"].invoke
        end
      end
      
      
      desc "Migrate the database through scripts in db/migrate and update db/schema.rb by "\
        "invoking db:schema:dump. Target specific version with VERSION=x. Turn off output "\
        "with VERBOSE=false."
      task :migrate => :environment do
        UseDbPlugin.with_db db_group do
          ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
          migration_dir = ActiveRecord::Base.migration_dir
          ActiveRecord::Migrator.migrate(migration_dir, ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
          Rake::Task["fordb:#{db_group}:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
        end
      end
      
      Rake::Task['db:migrate'].enhance do
        Rake::Task["fordb:#{db_group}:migrate"].invoke
      end
      
      namespace :migrate do
        desc 'Runs the "down" for a given migration VERSION.'
        task :down => :environment do
          version = ENV["VERSION"] ? ENV["VERSION"].to_i : nil
          raise "VERSION is required" unless version
          ActiveRecord::Base.use_db db_group
          migration_dir = ActiveRecord::Base.migration_dir
          ActiveRecord::Migrator.run(:down, migration_dir, version)
          Rake::Task["fordb:#{db_group}:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
        end

        desc  'Rollbacks the database one migration and re migrate up. If you want to rollback more than one step, define STEP=x. Target specific version with VERSION=x.'
        task :redo => :environment do
          tasks = ENV["VERSION"] ? %w(migrate:down migrate:up) : %w(rollback migrate)
          tasks.each{|t| Rake::Task["fordb:#{db_group}:#{t}"].invoke}
        end

        desc 'Resets your database using your migrations for the current environment'
        task :reset => %w(drop create migrate).collect{|t| "fordb:#{db_group}:#{t}" }

        Rake::Task['db:migrate:reset:all'].enhance ["fordb:#{db_group}:migrate:reset"]

        desc 'Runs the "up" for a given migration VERSION.'
        task :up => :environment do
          version = ENV["VERSION"] ? ENV["VERSION"].to_i : nil
          raise "VERSION is required" unless version
          ActiveRecord::Base.use_db db_group
          migration_dir = ActiveRecord::Base.migration_dir
          ActiveRecord::Migrator.run(:up, migration_dir, version)
          Rake::Task["fordb:#{db_group}:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
        end
      end
      
      desc "Drops and recreates the database from db/schema.rb for the current environment "\
        "and loads the seeds."
      task :reset => %w(drop setup).collect{|t| "fordb:#{db_group}:#{t}"}

      Rake::Task['db:reset:all'].enhance ["fordb:#{db_group}:reset"]
      
      desc 'Rolls the schema back to the previous version. Specify the number of steps with STEP=n'
      task :rollback => :environment do
        step = ENV['STEP'] ? ENV['STEP'].to_i : 1
        UseDbPlugin.with_db db_group do
          migration_dir = ActiveRecord::Base.migration_dir
          ActiveRecord::Migrator.rollback(migration_dir, step)
          Rake::Task["fordb:#{db_group}:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
        end
      end
      
      namespace :schema do
        desc "Create a db/schema.rb file that can be portably used against any DB supported by AR"
        task :dump => :environment do
          UseDbPlugin.with_db db_group do |conn_config|
            ENV['SCHEMA'] = ActiveRecord::Base.schema_filename
            Rake::Task['db:schema:dump'].actions.first.call
          end
          Rake::Task["fordb:#{db_group}:schema:dump"].reenable
        end
        
        Rake::Task["db:schema:dump:all"].enhance ["fordb:#{db_group}:schema:dump"]
        
        desc "Load a schema.rb file into the database"
        task :load => :environment do
          UseDbPlugin.with_db db_group do |conn_config|
            ENV['SCHEMA'] = ActiveRecord::Base.schema_filename
            Rake::Task['db:schema:load'].actions.first.call
          end
          Rake::Task["fordb:#{db_group}:schema:dump"].reenable
        end
        
        Rake::Task["db:schema:load:all"].enhance ["fordb:#{db_group}:schema:load"]
      end
      
      desc 'Load the seed data from seeds.rb'
      task :seed => :environment do
        ActiveRecord::Base.use_db db_group
        seed_file = ActiveRecord::Base.seed_filename
        load(seed_file) if seed_file.exist?
      end
      
      Rake::Task["db:seed"].enhance do
        Rake::Task["fordb:#{db_group}:seed"].invoke
      end
      
      desc "Create the database, load the schema, and initialize with the seed data"
      task :setup => %w(create schema:load seed).collect{|t| "fordb:#{db_group}:#{t}"}
      
      namespace :structure do
        # can't yet "Dump the database structure to a SQL file"
        task :dump do
          raise "fordb:#{db_group}:structure:dump not yet implemented"
        end
      end
      
      namespace :test do
        # can't yet "Recreate the test database from the current environment's database schema"
        task :clone do
          raise "fordb:#{db_group}:test:clone not implemented"
        end
        
        # can't yet "Recreate the test databases from the development structure"
        task :clone_structure do
          raise "fordb:#{db_group}:test:close_structure not implemented"
        end
        
        desc "Recreate the test database from the current schema.rb"
        task :load => "fordb:#{db_group}:test:purge" do
          original_env = RAILS_ENV
          RAILS_ENV = 'test'
          Rails.instance_eval{@_env = 'test'}
          ActiveRecord::Schema.verbose = false
          Rake::Task["fordb:#{db_group}:schema:load"].invoke
          RAILS_ENV = original_env
        end
        
        desc "Check for pending migrations and load the test schema"
        task :prepare => "fordb:#{db_group}:abort_if_pending_migrations" do
          if defined?(ActiveRecord) && !ActiveRecord::Base.configurations.blank?
            Rake::Task[{ :sql  => "fordb:#{db_group}:test:clone_structure", :ruby => "fordb:#{db_group}:test:load" }[ActiveRecord::Base.schema_format]].invoke
          end
        end
        
        Rake::Task["db:test:prepare"].enhance do
          Rake::Task["fordb:#{db_group}:test:prepare"].invoke
        end
        
        desc "Empty the test database"
        task :purge do
          use_db_load_config(db_group) do
            Rake::Task['db:test:purge'].actions.first.call
          end
        end
      end
      
      desc "Retrieves the current schema version number"
      task :version => :environment do
        UseDbPlugin.with_db db_group do
          puts "Current #{db_group} version: #{ActiveRecord::Migrator.current_version}"
        end
      end
      
      Rake::Task['db:version'].enhance do
        Rake::Task["fordb:#{db_group}:version"].invoke
      end
    end
  end
end
