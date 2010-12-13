require 'pathname'
require 'rubygems'
# $: << Pathname.new[__FILE__].dirname+'lib'
require 'active_record'
require 'lib/use_db_plugin'


spec = Gem::Specification.new do |s|
  s.name             = 'bitherder-use_db'
  s.version          = UseDbPlugin::VERSION
  s.platform         = Gem::Platform::RUBY
  s.version          = '0.1'
  s.summary          = 'Rails plugin to use alternate ActiveRecord databases'
  s.rubygems_version = '1.3.7'
  s.authors          = ['David Stevenson', 'Remi Taylor', 
                        'Dave LaDelfa', 'Larry Baltz']
  s.email            = %w(ds@elctech.com remi@remitaylor.com 
                          dave@ladelfa.net larry@baltz.org)
  s.homepage         = 'https://github.com/bitherder/use_db'
  s.extra_rdoc_files = ['README.markdown']
  s.files            = `git ls-files`.split("\n")
  s.test_files       = `git ls-files -- 'test/*_test.rb'`.split("\n")
  s.require_path     = "lib"
    
  s.description = """
This is a significant augmentation of the original use_db plugin that:
  * provides for separate content/config/migration directories for each
    database
  * a full set of rake tasks for each database
  * centeralized configuration in the use_db.yml file in preference to 
    using the :prefix and :suffix attributes for the use_db directive
  * uses rake to do database test set-up instead of requiring code be
    inserted in the test helper(s)
    """
  s.add_runtime_dependency 'rails', ["~> 2"]
end
