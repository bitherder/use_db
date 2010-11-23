require 'rubygems'
require 'test/unit'
require 'pathname'
require 'mocha'
require 'active_record'
require 'fileutils'

BASE_DIR=Pathname.new(__FILE__).dirname + '..'
$: << BASE_DIR + 'lib'

require 'use_db_plugin'


class UseDbPluginTest < Test::Unit::TestCase
  def setup
    ActiveRecord::Base.extend(UseDbPlugin)
    unless defined? Rails
      eval 'class ::Rails; end'
    end

    Rails.stubs(:root).returns(BASE_DIR+'test'+'rails_root')
    FileUtils.rm_rf(Rails.root)
    Rails.root.mkpath
    (@db_dir = Rails.root+'db').mkpath
    (@config_dir = Rails.root+'config').mkpath
    (@cake_dir = Rails.root+'cake').mkpath
    (@pie_dir = Rails.root+'cake').mkpath
  end

  def test_load_config_file
    filename = 'file.yml'
    path_to_file = Rails.root + 'config' + filename
    yaml_hash = {'attribute1' => 'value1', 'attribute2' => 'value2'}
    IO.stubs(:read).with(path_to_file).returns('yaml_text')
    erb_instance = stub(:result => 'erb')
    ERB.stubs(:new).with('yaml_text', nil, nil, '_use_db_erbout').returns(erb_instance)
    YAML.stubs(:load).with('erb').returns(yaml_hash)
    assert_equal yaml_hash, UseDbPlugin.load_config_file(filename)
  end
  
  def test_get_connection_with_use_db_paramaters_specified
    connection_spec = {
      'cake_test' => {'adapter' => 'somedb'}, 
      'cake_development' => {'adapter' => 'somedb'},
      'pie_test' => {'adapter' => 'somedb'},
    }
    
    Rails.stubs(:env).returns(:test)

    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)

    assert_equal connection_spec['cake_test'], UseDbPlugin.db_conn_spec(:prefix => 'cake_')
  end
  
  def test_get_connection_using_use_db_config_file
    database_config = {
      "cake" => {'prefix' => 'cake_'},
      "pie" => {'prefix' => 'pie_'}
    }
    connection_spec = {
      'cake_test' => {'adapter' => 'somedb'}, 
      'cake_development' => {'adapter' => 'somedb'},
      'pie_test' => {'adapter' => 'somedb'},
    }
    
    Rails.stubs(:env).returns(:test)

    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
    UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)

    assert_equal connection_spec['cake_test'], UseDbPlugin.db_conn_spec('cake')
  end
  
  def test_with_db
    Rails.stubs(:env).returns('development')
    default_name = 'Repo-men'
    cake_name = 'Raspberry Torte'
    cake_db = @cake_dir+'development.sqlite3'
    default_db = @db_dir+'development.sqlite3'
    use_db_config = @config_dir+'use_db.yml'
    database_config = @config_dir+'database.yml'
    
    File.open( use_db_config, 'w' ) do |yaml|
      YAML.dump( {'cake' => {'prefix' => 'cake_'}}, yaml )
    end
    
    File.open(database_config, 'w') do |yaml|
      YAML.dump({'cake_development' => {'adapter' => 'sqlite3', 'database' => cake_db.to_s}}, yaml)
    end

    system('sqlite3', cake_db, 'CREATE TABLE cakes (id INTEGER PRIMARY KEY, name VARCHAR(255))')
    system('sqlite3', default_db, 'CREATE TABLE defaults (id INTEGER PRIMARY KEY, name VARCHAR(255))')
    system('sqlite3', cake_db, "INSERT INTO cakes (name) VALUES ('#{cake_name}')")
    system('sqlite3', default_db, "INSERT INTO defaults (name) VALUES ('#{default_name}')")
    
    ActiveRecord::Base.establish_connection(:adapter => 'sqlite3', :database => default_db)
    
    assert_equal default_name, ActiveRecord::Base.connection.select_value('SELECT name FROM defaults')
    
    UseDbPlugin.with_db 'cake' do
      assert_equal cake_name, ActiveRecord::Base.connection.select_value('SELECT name FROM cakes')
    end
    
    assert_equal default_name, ActiveRecord::Base.connection.select_value('SELECT name FROM defaults')
  end
  
  def test_default_migration_directory_with_config_from_file
     database_config = {
       "cake" => {'prefix' => 'cake_'},
       "pie" => {'prefix' => 'pie_'}
     }
     connection_spec = {
       'cake_test' => {'adapter' => 'sqlite3'}, 
       'cake_development' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
     UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)

     ActiveRecord::Base.use_db('cake')
     assert_equal Pathname.new('db/cake/migrate'), ActiveRecord::Base.migration_dir
  end
  
  def test_migration_directory_with_explicit_db_dir_and_config_from_file
    db_dir = 'engine/cake/db'
    migration_dir = "#{db_dir}/migrate"
     database_config = {
       "cake" => {'prefix' => 'cake_', 'db_dir' => db_dir},
       "pie" => {'prefix' => 'pie_'}
     }
     connection_spec = {
       'cake_test' => {'adapter' => 'sqlite3'}, 
       'cake_development' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
     UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)

     ActiveRecord::Base.use_db('cake')
     assert_equal Pathname.new(migration_dir), ActiveRecord::Base.migration_dir
  end

  def test_migration_directory_with_explicit_migration_dir_and_config_from_file
    migration_dir = "engine/cake/db/migrate"
     database_config = {
       "cake" => {'prefix' => 'cake_', 'migration_dir' => migration_dir},
       "pie" => {'prefix' => 'pie_'}
     }
     connection_spec = {
       'cake_test' => {'adapter' => 'sqlite3'}, 
       'cake_development' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
     UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)

     ActiveRecord::Base.use_db('cake')
     assert_equal Pathname.new(migration_dir), ActiveRecord::Base.migration_dir
  end

  def test_default_migration_directory_with_ad_hoc_config_and_only_prefix
     connection_spec = {
       'cake_test' => {'adapter' => 'sqlite3'}, 
       'cake_development' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)

     ActiveRecord::Base.use_db(:prefix => 'cake_')
     assert_equal Pathname.new('db/cake/migrate'), ActiveRecord::Base.migration_dir
  end

  def test_default_migration_directory_with_ad_hoc_config_and_only_suffix
     connection_spec = {
       'test_cake' => {'adapter' => 'sqlite3'}, 
       'development_cake' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)

     ActiveRecord::Base.use_db(:suffix => '_cake')
     assert_equal Pathname.new('db/cake/migrate'), ActiveRecord::Base.migration_dir
  end
  
  def test_default_migration_directory_with_ad_hoc_config_with_prefix_and_suffix
     connection_spec = {
       'bake_test_cake' => {'adapter' => 'sqlite3'}, 
       'bake_development_cake' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)

     ActiveRecord::Base.use_db(:prefix => 'bake_', :suffix => '_cake')
     assert_equal Pathname.new('db/bake_cake/migrate'), ActiveRecord::Base.migration_dir
  end
  
  def test_default_schema_file_with_config_from_file
     database_config = {
       "cake" => {'prefix' => 'cake_'},
       "pie" => {'prefix' => 'pie_'}
     }
     connection_spec = {
       'cake_test' => {'adapter' => 'sqlite3'}, 
       'cake_development' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
     UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)

     ActiveRecord::Base.use_db('cake')
     assert_equal Pathname.new('db/cake/schema.rb'), ActiveRecord::Base.schema_filename
  end
  
  def test_schema_file_with_explicit_db_dir_and_config_from_file
    database_config = {
      "cake" => {'prefix' => 'cake_', 'db_dir' => 'engines/cake/db'},
      "pie" => {'prefix' => 'pie_'}
    }
    connection_spec = {
      'cake_test' => {'adapter' => 'sqlite3'}, 
      'cake_development' => {'adapter' => 'sqlite3'},
      'pie_test' => {'adapter' => 'sqlite3'},
    }

    Rails.stubs(:env).returns(:test)

    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
    UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)

    ActiveRecord::Base.use_db('cake')
    assert_equal Pathname.new('engines/cake/db/schema.rb'), ActiveRecord::Base.schema_filename
  end
  
  def test_schema_file_with_explicit_file_and_config_from_file
    database_config = {
      "cake" => {'prefix' => 'cake_', 'schema_file' => 'engines/cake/db/myschema.rb'},
      "pie" => {'prefix' => 'pie_'}
    }
    connection_spec = {
      'cake_test' => {'adapter' => 'sqlite3'}, 
      'cake_development' => {'adapter' => 'sqlite3'},
      'pie_test' => {'adapter' => 'sqlite3'},
    }

    Rails.stubs(:env).returns(:test)

    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
    UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)

    ActiveRecord::Base.use_db('cake')
    assert_equal Pathname.new('engines/cake/db/myschema.rb'), ActiveRecord::Base.schema_filename
  end
  
  def test_default_schema_file_with_ad_hoc_config_and_only_prefix
    connection_spec = {
      'cake_test' => {'adapter' => 'sqlite3'}, 
      'cake_development' => {'adapter' => 'sqlite3'},
      'pie_test' => {'adapter' => 'sqlite3'},
    }

    Rails.stubs(:env).returns(:test)

    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)

    ActiveRecord::Base.use_db(:prefix => 'cake_')
    assert_equal Pathname.new('db/cake/schema.rb'), ActiveRecord::Base.schema_filename
  end
  
  def test_default_schema_file_with_ad_hoc_config_and_only_suffix
    connection_spec = {
      'test_cake' => {'adapter' => 'sqlite3'}, 
      'development_cake' => {'adapter' => 'sqlite3'},
      'pie_test' => {'adapter' => 'sqlite3'},
    }

    Rails.stubs(:env).returns(:test)

    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)

    ActiveRecord::Base.use_db(:suffix => '_cake')
    assert_equal Pathname.new('db/cake/schema.rb'), ActiveRecord::Base.schema_filename
  end
  
  def test_default_schema_file_with_ad_hoc_config_with_prefix_and_suffix
     connection_spec = {
       'bake_test_cake' => {'adapter' => 'sqlite3'}, 
       'bake_development_cake' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)

     ActiveRecord::Base.use_db(:prefix => 'bake_', :suffix => '_cake')
     assert_equal Pathname.new('db/bake_cake/schema.rb'), ActiveRecord::Base.schema_filename
  end
  
  def test_default_seed_file_with_config_from_file
     database_config = {
       "cake" => {'prefix' => 'cake_'},
       "pie" => {'prefix' => 'pie_'}
     }
     connection_spec = {
       'cake_test' => {'adapter' => 'sqlite3'}, 
       'cake_development' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
     UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)

     ActiveRecord::Base.use_db('cake')
     assert_equal Pathname.new('db/cake/seeds.rb'), ActiveRecord::Base.seed_filename
  end
  
  def test_seed_file_with_explicit_seed_file_and_config_from_file
    db_dir = 'engine/cake/db'
    seed_file = "#{db_dir}/seeds.rb"
     database_config = {
       "cake" => {'prefix' => 'cake_', 'db_dir' => db_dir},
       "pie" => {'prefix' => 'pie_'}
     }
     connection_spec = {
       'cake_test' => {'adapter' => 'sqlite3'}, 
       'cake_development' => {'adapter' => 'sqlite3'},
       'pie_test' => {'adapter' => 'sqlite3'},
     }

     Rails.stubs(:env).returns(:test)

     UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
     UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)

     ActiveRecord::Base.use_db('cake')
     assert_equal Pathname.new(seed_file), ActiveRecord::Base.seed_filename
  end

  def test_seed_file_with_explicit_migration_dir_and_config_from_file
    seed_filename = "engine/cake/db/seeds.db"
    database_config = {
      "cake" => {'prefix' => 'cake_', 'seed_file' => seed_filename},
      "pie" => {'prefix' => 'pie_'}
    }
    connection_spec = {
      'cake_test' => {'adapter' => 'sqlite3'}, 
      'cake_development' => {'adapter' => 'sqlite3'},
      'pie_test' => {'adapter' => 'sqlite3'},
    }
    
    Rails.stubs(:env).returns(:test)
    
    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
    UseDbPlugin.expects(:load_config_file).with('use_db.yml').returns(database_config)
    
    ActiveRecord::Base.use_db('cake')
    assert_equal Pathname.new(seed_filename), ActiveRecord::Base.seed_filename
  end

  def test_default_seed_file_with_ad_hoc_config_and_only_prefix
    connection_spec = {
      'cake_test' => {'adapter' => 'sqlite3'}, 
      'cake_development' => {'adapter' => 'sqlite3'},
      'pie_test' => {'adapter' => 'sqlite3'},
    }
    
    Rails.stubs(:env).returns(:test)
    
    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
    
    ActiveRecord::Base.use_db(:prefix => 'cake_')
    assert_equal Pathname.new('db/cake/seeds.rb'), ActiveRecord::Base.seed_filename
  end

  def test_default_seed_file_with_ad_hoc_config_and_only_suffix
    connection_spec = {
      'test_cake' => {'adapter' => 'sqlite3'}, 
      'development_cake' => {'adapter' => 'sqlite3'},
      'pie_test' => {'adapter' => 'sqlite3'},
    }
    
    Rails.stubs(:env).returns(:test)
    
    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
    
    ActiveRecord::Base.use_db(:suffix => '_cake')
    assert_equal Pathname.new('db/cake/seeds.rb'), ActiveRecord::Base.seed_filename
  end
  
  def test_default_seed_file_with_ad_hoc_config_with_prefix_and_suffix
    connection_spec = {
      'bake_test_cake' => {'adapter' => 'sqlite3'}, 
      'bake_development_cake' => {'adapter' => 'sqlite3'},
      'pie_test' => {'adapter' => 'sqlite3'},
    }
    
    Rails.stubs(:env).returns(:test)
    
    UseDbPlugin.expects(:load_config_file).with('database.yml').returns(connection_spec)
    
    ActiveRecord::Base.use_db(:prefix => 'bake_', :suffix => '_cake')
    assert_equal Pathname.new('db/bake_cake/seeds.rb'), ActiveRecord::Base.seed_filename
  end
end
