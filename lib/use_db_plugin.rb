# UseDb

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
    return @@use_dbs
  end
  
  def self.all_connections
    return @@use_dbs.map(&:connection).uniq
  end
  
  def self.debug_print
    return @@debug_print
  end
  
  def self.debug_print=(newval)
    @@debug_print = newval
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
          (args.first || {}).merge options
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
      
      connections[database_config_name]
    end
  end
  
  def self.with_db(*db_spec_args)
    original_connection_config = ActiveRecord::Base.connection.instance_eval{@config}
    begin
      ActiveRecord::Base.use_db(*db_spec_args)
      yield
    ensure
      ActiveRecord::Base.establish_connection original_connection_config
    end
  end
  
  def use_db(*args)
    @use_db_config = config = UseDbPlugin.db_config(*args)
    conn_spec = UseDbPlugin.db_conn_spec(config)
    puts "Establishing connecting on behalf of #{self.to_s} to #{conn_spec.inspect}" if UseDbPlugin.debug_print
    establish_connection(conn_spec)
    extend ClassMixin
    @@use_dbs << self unless @@use_dbs.include?(self) || self.to_s.starts_with?("TestModel")
  end
  
  def use_db_config
    @use_db_config
  end
  
  def migration_dir
    if dir = @use_db_config[:migration_dir]
      dir
    elsif dir = @use_db_config[:db_dir]
      (Pathname.new(dir)+'migrate').to_s
    elsif @use_db_config[:db_group]
      "db/#{@use_db_config[:db_group]}/migrate"
    elsif !(elements = [@use_db_config[:prefix], @use_db_config[:suffix]].compact).empty?
      "db/#{elements.map{|e| e.sub(/^_+(.*)$/, '\1').sub(/(.*)_+$/, '\1')}.join('_')}/migrate"
    else
      raise "can't determine where to find migrations for #{self.name}"
    end
  end
  
  def schema_filename
    if file_name = @use_db_config[:schema_file]
      file_name
    elsif dir = @use_db_config[:db_dir]
      (Pathname.new(dir)+'schema.rb').to_s
    elsif !(elements = [@use_db_config[:prefix], @use_db_config[:suffix]].compact).empty?
      "db/#{elements.map{|e| e.sub(/^_+(.*)$/, '\1').sub(/(.*)_+$/, '\1')}.join('_')}/schema.rb"
    else
      raise "can't determine location for schema.rb for #{self.name}"
    end
  end
end

class UseDbPluginClass
  extend UseDbPlugin
end
