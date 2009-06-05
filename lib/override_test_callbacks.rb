# puts "Overriding test fixture setup and teardown callbacks"

module ActiveRecord #:nodoc:
  module TestFixtures #:nodoc:
      
    def setup_fixtures
      return unless defined?(ActiveRecord) && !ActiveRecord::Base.configurations.blank?

      if pre_loaded_fixtures && !use_transactional_fixtures
        raise RuntimeError, 'pre_loaded_fixtures requires use_transactional_fixtures'
      end

      @fixture_cache = {}
      @@already_loaded_fixtures ||= {}

      # Load fixtures once and begin transaction.
      if run_in_transaction?
        if @@already_loaded_fixtures[self.class]
          @loaded_fixtures = @@already_loaded_fixtures[self.class]
        else
          load_fixtures
          @@already_loaded_fixtures[self.class] = @loaded_fixtures
        end

        # Use_DB: Original version does this once for a single connection, but we'll do it in a loop.
        # puts "Establishing TRANSACTION for #{UseDbPlugin.all_connections.length} open connections"

        UseDbPlugin.all_connections.each do |conn|
          conn.increment_open_transactions
          conn.transaction_joinable = false
          conn.begin_db_transaction
        end
        
      # Load fixtures for every test.
      else
        Fixtures.reset_cache
        @@already_loaded_fixtures[self.class] = nil
        load_fixtures
      end

      # Instantiate fixtures for every test if requested.
      instantiate_fixtures if use_instantiated_fixtures
    end

    def teardown_fixtures
      return unless defined?(ActiveRecord) && !ActiveRecord::Base.configurations.blank?

      unless run_in_transaction?
        Fixtures.reset_cache
      end

      # Use_DB: Original version does this once for a single connection, but we'll do it in a loop.
      # puts "Finishing (rolling back) TRANSACTION for #{UseDbPlugin.all_connections.length} open connections"
      UseDbPlugin.all_connections.each do |conn|

        # Rollback changes if a transaction is active.
        if run_in_transaction? && conn.open_transactions != 0
          conn.rollback_db_transaction
          conn.decrement_open_transactions
        end
      
      end
      ActiveRecord::Base.clear_active_connections!
    end

  end
end