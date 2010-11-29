UseDb
=====

This plugin allows you to use multiple databases in your rails application.  


Usage
-----

You can switch the database for a model in the following manner:

    class MyModel < ActiveRecord::Base
      use_db :prefix => 'secdb_', :suffix => '_cool'
    end

or, if you have a `config/use_db.yml` file with a `secdb` specification (see
description later in this file): 

    class MyModel < ActiveRecord::Base
      use_db 'secdb'
    end


`ActiveRecord::Base.use_db` can take a prefix and a suffix (only 1 of which is
required) that are prepended and appended onto the current `RAILS_ENV`. In
the above example, I would have to make the following database entries to my
database.yml:

    secdb_development_cool:
      adapter: mysql
      database: secdb_dev_db
      ...

    secdb_test_cool:
      adapater: mysql
      database: secdb_test_db
      ...

Instead of specifying the prefix and suffix directly in the `use_db` call in
your model, you can create a `config/use_db.yml` file that specifies them and
then reference entries in that file in your `use_db` call.

So, for the the databases shown above, you would have a `config/use_db.yml`
file with the following contents:

    secdb:
      prefix: secdb_
      suffix: _cool

And then your model could look like:

    class MyModel < ActiveRecord::Base
      use_db 'secdb'
    end

It's often useful to create a single abstract model which all models using a
different database extend from:

    class SecdbBase < ActiveRecord::Base
      use_db 'secdb'
      self.abstract_class = true
    end

    class MyModel < SecdbBase
      # this model will use a different database automatically now
    end


Migrations
----------

By default, the plugin expects a database specific directory to exist at
`db/<prefix><RAILS_ENV><suffix>/`, and, for migrations, a `migrate` 
subdirectory.

You can generate a new migration with:

    script/generate migration_for <db-name> <migration-name>

where `<db-name>` is the database name specified in the `config/use_db.yml`
file and `<migration-name>` can be the name of the migration as you would use
for `script/generate migration`. The migration file will be placed in your
database specific directory and you can edit it as you normally would.

To execute the migrations from your database specific migration directory, 
there is a `rake` task, `fordb:<db-name>:migrate`.

So, from our previous examples, if you wanted to create a migration to create
the widget table you would need to create a directory in your
project, 

    db/secdb/migrate

and then run 

    script/generate migration_for secdb CreateWidgets

edit your migration and then run

    rake fordb:secdb:migrate

The associated migration tasks are also available.  For example, the tasks
that would be available for our `secdb` would be:

    rake fordb:secdb:migrate
    rake fordb:secdb:migrate:down
    rake fordb:secdb:migrate:redo
    rake fordb:secdb:migrate:reset
    rake fordb:secdb:migrate:up
    rake fordb:secdb:reset
    rake fordb:secdb:rollback

The per-database directory can be changed by either specifying it directly
in the `use_db.yml` file with the `migration_dir` it will be take as the
sub directory `migrate` under the directory specified by `db_dir`.  So,
if we created a sub-project directory `secdb` under `RAILS_ROOT`, we could 
specify the database specific migration directory in the `use_db.yml` file
like:

    secdb_development_cool:
      prefix: secdb_
      suffix: _cool
      db_dir: secdb/db

Alternately, you could specify it directly with:

    secdb_development_cool:
      prefix: secdb_
      suffix: _cool
      migration_dir: secdb/db/migrate


Testing
-------

In order to test in multiple databases, you need to run database specific
setup rails tasks:

    rake fordb:<db-name>:test:load
    rake fordb:<db-name>:test:prepare

_Still to-do: integrate these tasks into the normal db:test:load and
db:test:prepare tasks so that these tasks won't normally need to be run
manually._

Note: currently, only the `:ruby` schema format is currently supported (i.e.
the `:sql` format is _not_ supported).

Fixtures
--------

The plugin expects your database specific fixtures to be in a database
specific subdirectory. By default it is in `test/<db-name>/fixtures/`,
but you can override the default using a `fixtures_dir` entry in your
`use_db.yml` file.

In order to include your fixtures for tests, you will need to run the
following rake task:

    rake fordb:<db-name>:fixtures:load

_Still to-do: integrate these tasks into the normal db:test:load and
db:test:prepare tasks so that these tasks won't normally need to be run
manually._

TODO: bitherder: figure out what will happen with fixtures with joins, etc.

_[The following may or may not be true.]_  
There is currently no other way to
force a fixture to use a specific database (sorry, no join tables yet), like
there is for migrations.


Attribution
-----------

by David Stevenson <ds@elctech.com>
updates Larry Baltz (bitherder) <larry@baltz.org>
