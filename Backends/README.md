# Backends

Optional persistent-store backends for the CoreData framework, each in its own
subdirectory.  Nothing here is built by the top-level `make`, nothing here is
linked into `CoreData.framework`, and none of it adds a dependency for people
who only want the framework: a backend is an addon that an application opts
into by linking it.

| Directory    | Store type            | Requires                          | Status       |
| ------------ | --------------------- | --------------------------------- | ------------ |
| `PostgreSQL` | `CDPostgreSQLStore`   | libpq                             | experimental |
| `MySQL`      | `CDMySQLStore`        | MariaDB Connector/C or libmysqlclient | experimental |

The two SQL backends keep the same schema and behave the same way; `MySQL`'s
README lists only where its dialect differs.

## How a backend plugs in

Each backend is an `NSIncrementalStore` subclass that registers itself with
`+[NSPersistentStoreCoordinator registerStoreClass:forStoreType:]` from its
`+load`, so linking the library is all an application has to do:

```objc
#import <CDPostgreSQLStore/CDPostgreSQLStore.h>

[coordinator addPersistentStoreWithType:CDPostgreSQLStoreType
                          configuration:nil
                                    URL:[NSURL URLWithString:@"postgresql://localhost/mydb"]
                                options:nil
                                  error:&error];
```

## Public API only

A backend uses only the framework's **public** headers - the same API Apple
publishes for third-party incremental stores.  It never imports a `-Private.h`
header, even though it sits in the same repository and could.

The reason is that a store written this way also compiles and runs against
Apple's CoreData on macOS, which means its test suite can be arbitrated by the
implementation this project is a port of, exactly as the framework's own suite
is.  That is the single most useful debugging tool this project has, and it is
worth the small amount of code that has to be reimplemented publicly (value
transformers, entity-inheritance checks) to keep it.

This costs less than it sounds.  The result objects a store has to hand back -
`NSBatchUpdateResult` and its siblings - are built inside the framework with
an initializer that is private, but nothing stops a backend from producing one
publicly: those classes declare no designated initializer, do not mark `init`
unavailable, and expose `result`/`resultType` as readonly properties, so a
subclass carrying its own values answers both messages perfectly well.  The
persistent store coordinator returns whatever the store gives it, unchanged.

What public API genuinely does not offer is a way to read a persistent history
request: whether it is a fetch or a purge, and what it is anchored to, are
private to the framework - and to Apple's, which publishes exactly the same
three accessors (`token`, `fetchRequest`, `resultType`) and no more.  The
distinction is not a class either: `+fetchHistoryAfterDate:` and
`+deleteHistoryBeforeDate:` both return a plain `NSPersistentHistoryChangeRequest`,
on Apple as here, so `isKindOfClass:` cannot separate them.

This framework therefore publishes what a store needs, as additions of its
own: `-isPurgeRequest`, `-anchorDate` and `-anchorTransactionNumber` for
reading a request, and factory methods on `NSPersistentHistoryTransaction`,
`NSPersistentHistoryChange` and `NSPersistentHistoryToken` for building what
a store answers with.  A backend that uses them declares them in its own
source rather than importing a header, so the same file still compiles
against Apple's CoreData, and guards every call with a runtime check that is
false there.  `PostgreSQL` does exactly this, and reports history as an
unsupported request type when built against Apple's framework.  See the individual backend's
README for what it does and does not implement.

Grouped and aggregated fetches
------------------------------

A `NSDictionaryResultType` request that groups rows, or computes an aggregate
over them, is one statement to a SQL database and a full table scan to anyone
who shapes the rows after fetching the objects.  Apple's CoreData hands the
whole request - grouping, `havingPredicate`, sort descriptors and all - to the
store.  This framework used to shape those rows itself for every store, which
was correct but read the whole table, and could not sort by an aggregate's
name at all: the name belongs to the row, not to any object.

A store may now say it will do the work, by answering
`-_canShapeDictionaryRequest:`.  The framework asks with
`respondsToSelector:`, so no store has to know about it, and a store that
answers `NO` - or is not asked, because several stores are affected - gets the
in-memory shaping as before, now ordered after the rows are built rather than
before.  `CDSQLStore` answers by building the very query the fetch would run
and saying yes if it came out, so it never claims more than it can express;
what it cannot express (an aggregate across a relationship, a predicate that
does not translate exactly) it leaves to the framework.

Nothing here is needed on Apple's CoreData, which never sends the message.

Continuous integration
----------------------

`.github/workflows/backends.yml` is these backends' own workflow - the
framework's CI does not build them, since they are an addon and need servers
to say anything.  It runs when anything under `Backends/` changes, and when
`CoreData/` does: a store is a client of the framework's public API, so a
change there can break a backend without touching a file here.

On Linux it builds the framework and both backends against a restored GNUstep
stack (the same cache the framework's CI fills) and runs each suite against a
service container: PostgreSQL 16, MySQL 8, and MariaDB 11 through the MySQL
backend, which is written for both and cannot be assumed correct on one from a
run on the other.

On macOS it builds both backends and their test bundles against Apple's
CoreData.  That is the check the public-API-only rule needs - one private
method and it stops compiling - while running the suites there would need
servers on the runner, which is left to whoever wants it locally.

The suites skip themselves when no URL is configured, which is right on a
machine with no server and wrong in CI, where a database that failed to start
would leave a green run that tested nothing.  CI therefore sets
`CD_TEST_REQUIRE_DATABASE`, which turns the skip into a failure.
