require 'pathname'

module UseDbPlugin
  # options can have one or the other of the following options:
  #   :prefix - Specify the prefix to append to the RAILS_ENV when finding the adapter secification in database.yml
  #   :suffix - Just like :prefix, only contactentated
  # OR
  #   :adapter
  #   :host
  #   :username
  #   :password
  #     ... etc ... same as the options in establish_connection
  #  
  # Set the following to true in your test environment 
  # to enable extended debugging printing during testing ...
  # UseDbPlugin.debug_print = true   
  #
  
  @@use_dbs = [ActiveRecord::Base]
  @@debug_print = false
  
  def self.all_use_dbs
    @@use_dbs
  end
  
  def self.all_connections
    @@use_dbs.map(&:connection).uniq
  end
  
  def self.debug_print
    @@debug_print
  end
  
  def self.debug_print=(newval)
    @@debug_print = newval
  end
  
  def self.log(msg)
    if @@debug_print or ENV['DEBUG'] or ENV['USE_DB_DEBUG']
      puts msg
    end
    
    Rails.logger.debug msg
  end
  
  module ClassMixin
    def uses_db?
      true
    end
  end  
  
  def self.load_config_file(filename)
    YAML.load(ERB.new(IO.read(Rails.root+'config'+filename), nil, nil, '_use_db_erbout').result)
  end
  
  def self.db_spec(db_group)
    option_sets = load_config_file('use_db.yml')
    options = option_sets[db_group.to_s]
    
    raise ArgumentError, "#{db_group.inspect} does not exist in use_db.yml" unless options
    
    options[:db_group] = db_group
    options
  end
  
  def self.db_config(*args)
    config = 
      case args.first
      when String, Symbol
        db_group = args.shift
        options = db_spec db_group
        if args.first.kind_of? Hash
          args.first.merge options
        else
          options
        end
      else
        args.first || {}
      end

    config.symbolize_keys!
    config[:rails_env] = (config[:rails_env] || Rails.env)
    config
  end

  def self.db_config_name(*args)
    config = db_config(*args)
    "#{config[:prefix]}#{config[:rails_env]}#{config[:suffix]}"
  end

  def self.db_conn_spec(*args)
    config = db_config(*args)

    if (config[:adapter])
      config.delete(:suffix)
      config.delete(:prefix)
      config.delete(:rails_env)
      config
    else
      database_config_name = db_config_name(config)
      connections = load_config_file 'database.yml'
      if (connections[database_config_name].nil?)
        raise("Cannot find database specification.  Configuration "\
          "'#{database_config_name}' expected in config/database.yml")
      end
      
      connections[database_config_name].symbolize_keys
    end
  end
  
  def self.with_db(*db_spec_args)
    config = UseDbPlugin.db_config(*db_spec_args)
    original_connection_config = ActiveRecord::Base.connection.instance_eval{@config}
    begin
      ActiveRecord::Base.use_db(*db_spec_args)
      if(set_rails_env = config[:set_rails_env])
        config.delete(:set_rails_env)
        original_rails_env_const = RAILS_ENV
        original_rails_env_method_value = Rails.env
        Object.const_set 'RAILS_ENV', UseDbPlugin.db_config_name(config)
        Rails.instance_eval{@_env = RAILS_ENV}
      end
      yield
    ensure
      if(set_rails_env)
        Object.const_set 'RAILS_ENV', original_rails_env_const
        Rails.instance_eval "@_env = '#{original_rails_env_method_value}'"
      end
      ActiveRecord::Base.establish_connection original_connection_config
    end
  end
  
  def use_db(*args)
    @use_db_config = config = UseDbPlugin.db_config(*args)
    conn_spec = UseDbPlugin.db_conn_spec(config)
    if ActiveRecord::Base.connected? && conn_spec == ActiveRecord::Base.connection.instance_eval{@config}
      unless self == ActiveRecord::Base
        UseDbPlugin.log "#{self} using same connection as ActiveRecord::Base"
      end
      ActiveRecord::Base.connection.reconnect!
      return
    end
    
    UseDbPlugin.log "Establishing connecting on behalf of #{self} to #{conn_spec.inspect}"
    
    establish_connection(conn_spec)
    extend ClassMixin
    @@use_dbs << self unless @@use_dbs.include?(self) || self.to_s.starts_with?("TestModel")
  end
  
  def use_db_config
    @use_db_config
  end
  
  def self.db_path(*args)
    config = db_config(*args)
    
    config_option_name = config[:option_name] && config[:option_name].to_sym
    path_base = config[:base] || ''
    
    if path = config[config_option_name]
      Pathname.new(path)
    elsif dir = config[:db_dir]
      Pathname.new(dir)+path_base
    elsif config[:db_group]
      Pathname.new('db')+config[:db_group]+path_base
    elsif !(elements = [config[:prefix], config[:suffix]].compact).empty?
      Pathname.new('db')+elements.map{|e| e.sub(/^_+(.*)$/, '\1').sub(/(.*)_+$/, '\1')}.join('_')+path_base
    else
      raise "can't determine where to find '#{path_base}' for #{args.inspect}"
    end
    
  end
  
  def self.fixtures_dir(*args)
    config = db_config(*args)
    
    if path = config[:fixtures_dir]
      Pathname.new(path)
    elsif config[:db_group]
      Pathname.new('test')+'fixtures'+config[:db_group]
    elsif !(elements = [config[:prefix], config[:suffix]].compact).empty?
      Pathname.new('test')+'fixtures'+elements.map{|e| e.sub(/^_+(.*)$/, '\1').sub(/(.*)_+$/, '\1')}.join('_')
    else
      raise "can't determine where to find fixtures for #{args.inspect}"
    end
  end
  
  def self.migration_dir(*args)
    db_path(db_config(*args).merge(:option_name => :migration_dir, :base => 'migrate'))
  end
  
  def self.schema_filename(*args)
    db_path(db_config(*args).merge(:option_name => :schema_file, :base => 'schema.rb'))
  end
  
  def self.seed_filename(*args)
    db_path(db_config(*args).merge(:option_name => :seed_file, :base => 'seeds.rb'))
  end
  
  def self.schema_format(*args)
    config = db_config(*args)
    (config[:schema_format] || :ruby).to_sym
  end

  def migration_dir
    UseDbPlugin.migration_dir(@use_db_config)
  end
  
  
  def schema_filename
    UseDbPlugin.schema_filename(@use_db_config)
  end
  
  def seed_filename
    UseDbPlugin.seed_filename(@use_db_config)
  end
  
  def fixtures_dir
    UseDbPlugin.fixtures_dir(@use_db_config)
  end
end

class UseDbPluginClass
  extend UseDbPlugin
end
