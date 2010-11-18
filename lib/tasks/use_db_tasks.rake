# desc "Explaining what the task does"
# task :use_db do
#   # Task goes here
# end
$: << Pathname.new(__FILE__).dirname + '../..'
$: << Pathname.new(__FILE__).dirname + '..'

# , :rails_env => Rails.env || 'development'

require 'init'
def in_db_context(db_group)
  ActiveRecord::Base.with_db db_group do
    yield ActiveRecord::Base.connection.instance_eval{@config}
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
          puts "migration_dir: #{migration_dir}"
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
      
      desc "Retrieves the charset for the current environment's database"
      task :charset => :environment do
        RAILS_ENV = UseDbPlugin.db_config_name(db_group)
        Rake::Task['db:charset'].actions.first.call
      end
      
      desc "Retrieves the collation for the current environment's database"
      task :collation => :environment do
        RAILS_ENV = UseDbPlugin.db_config_name(db_group)
        Rake::Task['db:collation'].actions.first.call
      end
      
      # TODO: @larry.baltz - implement per-databse create and drop tasks
      # per-database create and drop tasks are not critical since they can be handled
      # (at a gross level) by the system-wide db:create:all and db:drop:all tasks
      #
      # desc 'Create the database defined in config/database.yml for the current RAILS_ENV'
      # task :create => ":db:load_config" do
      #   create_database(ActiveRecord::Base.get_use_db_conn_spec(db_group))
      # end
      # 
      # namespace :create do
      #   desc 'Create all the local databases defined in config/database.yml'
      #   task :all
      # end
      # 
      # desc 'Drops the database for the current RAILS_ENV'
      # task :drop
      # 
      # namespace :drop do
      #   desc 'Drops all the local databases defined in config/database.yml'
      #   task :all
      # end
      
      namespace :fixtures do
        desc 'Search for a fixture given a LABEL or ID.'
        task :identify
        desc "Load fixtures into the current environment's database."
        task :load
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
      
      namespace :migrate do
        desc "Runs the 'down' for a given migration VERSION."
        task :down
        
        desc "Rollbacks the database one migration and re migrate up."
        task :redo
        
        desc "Resets your database using your migrations for the current environment"
        task :reset
        
        desc "Runs the 'up' for a given migration VERSION."
        task :up
      end
      
      desc "Drops and recreates the database from db/schema.rb for the current environment "\
        "and loads the seeds."
      task :reset
      
      desc "Rolls the schema back to the previous version."
      task :rollback
      
      namespace :schema do
        desc "Create a db/schema.rb file that can be portably used against any DB supported by AR"
        task :dump => :environment do
          UseDbPlugin.with_db db_group do |conn_config|
            ENV['SCHEMA'] = ActiveRecord::Base.schema_filename
            Rake::Task['db:schema:dump'].actions.first.call
          end
          Rake::Task["fordb:#{db_group}:schema:dump"].reenable
        end
        
        desc "Load a schema.rb file into the database"
        task :load => :environment do
          UseDbPlugin.with_db db_group do |conn_config|
            ENV['SCHEMA'] = ActiveRecord::Base.schema_filename
            Rake::Task['db:schema:load'].actions.first.call
          end
          Rake::Task["fordb:#{db_group}:schema:dump"].reenable
          
        end
      end
      desc "Load the seed data from db/seeds.rb"
      task :seed
      
      namespace :sessions do
        desc "Clear the sessions table"
        task :clear
        
        desc "Creates a sessions migration for use with ActiveRecord::SessionStore"
        task :create
      end
      desc "Create the database, load the schema, and initialize with the seed data"
      task :setup
      
      namespace :structure do
        desc "Dump the database structure to a SQL file"
        task :dump
      end
      
      namespace :test do
        desc "Recreate the test database from the current environment's database schema"
        task :clone
        
        desc "Recreate the test databases from the development structure"
        task :clone_structure
        
        desc "Recreate the test database from the current schema.rb"
        task :load
        
        desc "Check for pending migrations and load the test schema"
        task :prepare
        
        desc "Empty the test database"
        task :purge
      end
      
      desc "Retrieves the current schema version number"
      task :version => :environment do
        UseDbPlugin.with_db db_group do
          puts "Current version: #{ActiveRecord::Migrator.current_version}"
        end
      end
    end
  end
end

namespace :db do
  namespace :structure do
    desc "dump the database structure of the database specified by use_db"
    task :dump_use_db do            
      require 'init'
      require 'lib/test_model'
      
      UseDbTest.other_databases.each do |options| 
        puts "DUMPING TEST DB: #{options.inspect}" if UseDbPlugin.debug_print
             
        options_dup = options.dup
        options_dup[:rails_env] = "development"    
        conn_spec = UseDbPluginClass.get_use_db_conn_spec(options_dup)
        #establish_connection(conn_spec)

        test_class = UseDbTest.setup_test_model(options[:prefix], options[:suffix], "ForDumpStructure")

        # puts "Dumping DB structure #{test_class.inspect}..."

        case conn_spec["adapter"]
          when "mysql", "oci", "oracle"
            test_class.establish_connection(conn_spec)
            File.open("#{RAILS_ROOT}/db/#{RAILS_ENV}_#{options[:prefix]}_#{options[:suffix]}_structure.sql", "w+") { |f| f << test_class.connection.structure_dump }
=begin      when "postgresql"
            ENV['PGHOST']     = abcs[RAILS_ENV]["host"] if abcs[RAILS_ENV]["host"]
            ENV['PGPORT']     = abcs[RAILS_ENV]["port"].to_s if abcs[RAILS_ENV]["port"]
            ENV['PGPASSWORD'] = abcs[RAILS_ENV]["password"].to_s if abcs[RAILS_ENV]["password"]
            search_path = abcs[RAILS_ENV]["schema_search_path"]
            search_path = "--schema=#{search_path}" if search_path
            `pg_dump -i -U "#{abcs[RAILS_ENV]["username"]}" -s -x -O -f db/#{RAILS_ENV}_structure.sql #{search_path} #{abcs[RAILS_ENV]["database"]}`
            raise "Error dumping database" if $?.exitstatus == 1
          when "sqlite", "sqlite3"
            dbfile = abcs[RAILS_ENV]["database"] || abcs[RAILS_ENV]["dbfile"]
            `#{abcs[RAILS_ENV]["adapter"]} #{dbfile} .schema > db/#{RAILS_ENV}_structure.sql`
          when "sqlserver"
            `scptxfr /s #{abcs[RAILS_ENV]["host"]} /d #{abcs[RAILS_ENV]["database"]} /I /f db\\#{RAILS_ENV}_structure.sql /q /A /r`
            `scptxfr /s #{abcs[RAILS_ENV]["host"]} /d #{abcs[RAILS_ENV]["database"]} /I /F db\ /q /A /r`
          when "firebird"
            set_firebird_env(abcs[RAILS_ENV])
            db_string = firebird_db_string(abcs[RAILS_ENV])
            sh "isql -a #{db_string} > db/#{RAILS_ENV}_structure.sql"
=end        
          else
            raise "Task not supported by '#{conn_spec["adapter"]}'"
        end

        #if test_class.connection.supports_migrations?
        #  File.open("db/#{RAILS_ENV}_structure.sql", "a") { |f| f << ActiveRecord::Base.connection.dump_schema_information }
        #end

        test_class.connection.disconnect!
      end
    end
  end
  
  namespace :test do
    task :clone_structure => "db:test:clone_structure_use_db"
    
    task :clone_structure_use_db => ["db:structure:dump_use_db","db:test:purge_use_db"] do
      require 'init'
      require 'lib/test_model'
      
      UseDbTest.other_databases.each do |options|   
        
        puts "CLONING TEST DB: #{options.inspect}" if UseDbPlugin.debug_print
           
        options_dup = options.dup
        conn_spec = UseDbPluginClass.get_use_db_conn_spec(options_dup)
        #establish_connection(conn_spec)

        test_class = UseDbTest.setup_test_model(options[:prefix], options[:suffix], "ForClone", "test")

       # puts "Cloning DB structure #{test_class.inspect}..."

        case conn_spec["adapter"]
          when "mysql"
            test_class.connection.execute('SET foreign_key_checks = 0')
            IO.readlines("#{RAILS_ROOT}/db/#{RAILS_ENV}_#{options[:prefix]}_#{options[:suffix]}_structure.sql").join.split("\n\n").each do |table|
              test_class.connection.execute(table)
            end
          when "oci", "oracle"
            IO.readlines("#{RAILS_ROOT}/db/#{RAILS_ENV}_#{options[:prefix]}_#{options[:suffix]}_structure.sql").join.split(";\n\n").each do |ddl|
              test_class.connection.execute(ddl)
            end
=begin      when "postgresql"
            ENV['PGHOST']     = abcs["test"]["host"] if abcs["test"]["host"]
            ENV['PGPORT']     = abcs["test"]["port"].to_s if abcs["test"]["port"]
            ENV['PGPASSWORD'] = abcs["test"]["password"].to_s if abcs["test"]["password"]
            `psql -U "#{abcs["test"]["username"]}" -f db/#{RAILS_ENV}_structure.sql #{abcs["test"]["database"]}`
          when "sqlite", "sqlite3"
            dbfile = abcs["test"]["database"] || abcs["test"]["dbfile"]
            `#{abcs["test"]["adapter"]} #{dbfile} < db/#{RAILS_ENV}_structure.sql`
          when "sqlserver"
            `osql -E -S #{abcs["test"]["host"]} -d #{abcs["test"]["database"]} -i db\\#{RAILS_ENV}_structure.sql`
          when "firebird"
            set_firebird_env(abcs["test"])
            db_string = firebird_db_string(abcs["test"])
            sh "isql -i db/#{RAILS_ENV}_structure.sql #{db_string}"
=end
          else
            raise "Task not supported by '#{conn_spec["adapter"]}'"
        end

        test_class.connection.disconnect!
      end
    end
    
    task :purge_use_db => "db:test:purge" do
      require 'init'
      require 'lib/test_model'

      UseDbTest.other_databases.each do |options|
        puts "PURGING TEST DB: #{options.inspect}" if UseDbPlugin.debug_print
        options_dup = options.dup
        options_dup[:rails_env] = "test"
        conn_spec = UseDbPluginClass.get_use_db_conn_spec(options_dup)
        puts "GOT CONN_SPEC: #{conn_spec.inspect}"
        test_class = UseDbTest.setup_test_model(options[:prefix], options[:suffix], "ForPurge", "test")
        puts "GOT TEST_CLASS: #{test_class.inspect}"
        #test_class.establish_connection        

        case conn_spec["adapter"]
          when "mysql"
            test_class.connection.recreate_database(conn_spec["database"])
          when "oci", "oracle"
            test_class.connection.structure_drop.split(";\n\n").each do |ddl|
              test_class.connection.execute(ddl)
            end
          when "firebird"
            test_class.connection.recreate_database!
=begin
          when "postgresql"
            ENV['PGHOST']     = abcs["test"]["host"] if abcs["test"]["host"]
            ENV['PGPORT']     = abcs["test"]["port"].to_s if abcs["test"]["port"]
            ENV['PGPASSWORD'] = abcs["test"]["password"].to_s if abcs["test"]["password"]
            enc_option = "-E #{abcs["test"]["encoding"]}" if abcs["test"]["encoding"]

            ActiveRecord::Base.clear_active_connections!
            `dropdb -U "#{abcs["test"]["username"]}" #{abcs["test"]["database"]}`
            `createdb #{enc_option} -U "#{abcs["test"]["username"]}" #{abcs["test"]["database"]}`
          when "sqlite","sqlite3"
            dbfile = abcs["test"]["database"] || abcs["test"]["dbfile"]
            File.delete(dbfile) if File.exist?(dbfile)
          when "sqlserver"
            dropfkscript = "#{abcs["test"]["host"]}.#{abcs["test"]["database"]}.DP1".gsub(/\\/,'-')
            `osql -E -S #{abcs["test"]["host"]} -d #{abcs["test"]["database"]} -i db\\#{dropfkscript}`
            `osql -E -S #{abcs["test"]["host"]} -d #{abcs["test"]["database"]} -i db\\#{RAILS_ENV}_structure.sql`
=end
          else
            raise "Task not supported by '#{conn_spec["adapter"]}'"
        end

        test_class.connection.disconnect!    
      end
    end  
  end
end

namespace :test do
  task :units => "db:test:clone_structure_use_db"
  task :functionals => "db:test:clone_structure_use_db"
  task :integrations => "db:test:clone_structure_use_db"
end