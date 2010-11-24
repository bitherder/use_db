#TODO: @larry.baltz: figure out how to get the destroy script to work

class MigrationForGenerator < MigrationGenerator
  attr_reader :db_group
  
  def initialize(runtime_args, runtime_options = {})
    super
    @args = runtime_args.dup
    @db_group = @args.shift
    base_name = @args.shift
    assign_db_config!(@db_group)
    assign_names!(base_name)
  end
  
  def manifest
    record do |m|
      m.migration_template 'migration.rb', @migration_dir, :assigns => get_local_assigns
    end
  end
  
  private
  
  def assign_db_config!(db_group)
    @db_config = UseDbPlugin.db_spec db_group
    @db_conn_spec = UseDbPlugin.db_conn_spec @db_config
    @migration_dir = UseDbPlugin.migration_dir @db_config
  end
end