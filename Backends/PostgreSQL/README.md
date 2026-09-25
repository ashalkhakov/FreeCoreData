# PostgreSQL backend

An `NSIncrementalStore` that keeps a Core Data model in PostgreSQL, built on
libpq.  It is an addon: it is not part of `CoreData.framework` and nothing
else in this repository depends on it.

Status: **experimental**.  Fetching, saving, faulting, object IDs, batch
requests and persistent history all work and are covered by tests.  History is
the one feature that needs FreeCoreData rather than Apple's CoreData - see
below for why.

## Building

Requires libpq (`libpq-dev` on Debian/Ubuntu, `brew install libpq` on macOS)
and the framework built in this tree.

```sh
make                              # the framework, from the repository root
make -C Backends/PostgreSQL
```

`pg_config` is used to locate libpq when it is on PATH; otherwise the
compiler's default search paths are used.  Homebrew keeps libpq off PATH, so
on macOS point at it explicitly:

```sh
make -C Backends/PostgreSQL PG_CONFIG=/opt/homebrew/opt/libpq/bin/pg_config
```

## Using it

Link the library and open a store; the store class registers its type from
`+load`, so there is nothing to call first:

```objc
#import <CDPostgreSQLStore/CDPostgreSQLStore.h>

NSURL *url = [NSURL URLWithString:@"postgresql://user:secret@localhost/mydb"];
NSError *error = nil;

[coordinator addPersistentStoreWithType:CDPostgreSQLStoreType
                          configuration:nil
                                    URL:url
                                options:nil
                                  error:&error];
```

The URL is handed to libpq as written, so anything libpq accepts as a
connection URI works, including `?sslmode=require` and the rest of its
parameters.

`CDPostgreSQLSchemaNameOption` confines the store to a schema of its own,
which it creates if necessary:

```objc
options:@{ CDPostgreSQLSchemaNameOption : @"myapp" }
```

## Batch requests

`NSBatchInsertRequest` (both the dictionary-array and dictionary-handler
forms), `NSBatchUpdateRequest` and `NSBatchDeleteRequest` all run directly
against the database, with every result type.  As on Apple, no managed objects
are materialized, no validation or delete rules run, and loaded contexts are
not notified - though a batch delete does sweep the join-table rows of the
rows it removes.

A batch delete created with `initWithObjectIDs:` carries its list as a
`SELF IN <ids>` predicate on its fetch request, which the store translates
into a primary key list.  A predicate that does not translate to SQL is
evaluated row by row against stored values instead, exactly as the fetch path
does, so a batch request never silently applies to the wrong rows.

## Schema

The same layout the SQLite store uses, so a model behaves the same in either:
`Z_METADATA` and `Z_PRIMARYKEY` for store bookkeeping, one `Z<ENTITY>` table
per root entity (with `Z_PK`, `Z_ENT`, `Z_OPT` and a `Z<PROPERTY>` column per
attribute and to-one relationship), foreign keys on the destination table for
a to-many with a to-one inverse, and a `Z_<ENT><NAME>` join table for a
many-to-many.  All identifiers are quoted, so they keep their upper case.

Opening a store takes a PostgreSQL **advisory lock** on its schema for the
duration of one transaction, and re-checks inside the lock whether the store
already exists.  Two processes opening the same new store otherwise race to
create it - which SQLite hides behind its file lock and a server does not.
`CREATE TABLE IF NOT EXISTS` is not enough on its own: concurrent creates of
the same table fail with `duplicate key value violates unique constraint
"pg_type_typname_nsp_index"`, which is exactly what the test for this sees
when the lock is removed.

Faulting a relationship reads the destination rows' `Z_ENT` in the same query
as their keys, and object IDs are resolved without asking the database at all
when the destination entity has no subentities (its concrete entity cannot
vary, so there is nothing to look up).  Without both, faulting an N-element
relationship of an inherited entity would cost N+1 round trips.

Three differences from the SQLite store are worth knowing about:

- **Primary keys** are allocated with `UPDATE ... RETURNING`, one statement
  rather than the SQLite store's UPDATE-then-SELECT, so two connections
  cannot be handed the same key.
- **Opening is serialized** by the advisory lock described above, where the
  SQLite store relies on the file lock it gets for free.
- **Ordering is forced to the C collation.**  `NSString`'s `-compare:` orders
  by code point, which is what SQLite's default BINARY collation does; a
  PostgreSQL database created with a language collation would sort `alan`
  before `Grace`.  Every ordered comparison and `ORDER BY` on a text column
  therefore asks for `COLLATE "C"` explicitly.

Dates are stored as the `timeIntervalSinceReferenceDate` in a `double
precision` column, matching what the SQLite store persists, rather than as a
`timestamptz`.  That keeps the round trip exact and both stores readable by
the same tools, at the cost of dates being awkward to read in `psql`.

## Predicates across relationships

A key path that crosses relationships becomes an `EXISTS` subquery over the
tables it walks:

```objc
[NSPredicate predicateWithFormat:@"employer.name == %@", @"Bletchley"]
```

```sql
SELECT "Z_PK", "Z_ENT" FROM "ZCOMPANY" WHERE "Z_ENT" IN (1)
  AND (EXISTS (SELECT 1 FROM "ZPERSON" j0
                WHERE j0."ZEMPLOYER" = "ZCOMPANY"."Z_PK" AND j0."ZNAME" = $1))
```

Correlating back to the outer table by name, rather than joining it into the
outer `SELECT`, keeps the rest of the translator untouched and means no
`DISTINCT` is needed when a to-many is crossed.  Any number of hops works,
through to-one relationships, foreign-key to-many relationships and join
tables alike, and such a clause combines with local ones (and with fetch
limits and offsets, which are only pushed into SQL when the whole predicate
is).

`ANY` and `ALL` say what crossing a to-many means, and both are translated:
`ANY` as `EXISTS`, `ALL` as `NOT EXISTS` of the negation - written as
`(clause) IS NOT TRUE` so that a NULL on the far side counts as failing the
test rather than as unknown, which is what Core Data's in-memory evaluation
does.  A path through a to-many *without* `ANY` or `ALL` has no single
meaning, so it is left to the in-memory fallback rather than guessed at.

## Migration

The framework's `NSMigratePersistentStoresAutomaticallyOption` cannot serve a
store like this one: the coordinator implements it by copying the store
through `NSMigrationManager` into a second store and then **renaming files
over the original**, which a database at the far end of a socket does not
have.  The coordinator also refuses an incompatible store *before* the store
itself is opened, so it never gets the chance.

So this store migrates itself, in place.  An application asks for it with
`CDPostgreSQLMigrateSchemaOption`, and passes
`NSIgnorePersistentStoreVersioningOption` as well so that the coordinator's
file-oriented check stands aside:

```objc
options:@{ CDPostgreSQLMigrateSchemaOption        : @YES,
           NSIgnorePersistentStoreVersioningOption : @YES }
```

The store then does the version check itself - through
`-[NSManagedObjectModel isConfiguration:compatibleWithStoreMetadata:]`, the
same question the coordinator asks - and reconciles what it finds with what
the model wants:

- entities and properties **added**: new tables, new columns, a new
  `Z_PRIMARYKEY` row with the next free `Z_ENT` (existing entities keep
  theirs, because every row records the one it was written with);
- entities and properties **removed**: their columns and tables dropped, and
  only when the whole model - not merely this configuration - has no use for
  them;
- entities and properties **renamed** through `renamingIdentifier`: renamed
  in place, with their data, and a property may be renamed and retyped in
  the same version;
- attribute types **widened** where PostgreSQL can do it without losing
  anything (the integer family, `real` to `double precision`, anything to
  `text`).

Anything else - a changed inheritance chain, a type change that could lose
data - is refused by name, with the advice to use a mapping model and
`NSMigrationManager`, which work through ordinary fetches and saves and so
need nothing special from this store.

With neither option an incompatible store is refused, exactly as the
coordinator would refuse it.

Migration runs inside the same advisory-locked transaction as store
creation, so two clients that open an out-of-date store at the same moment
cannot both migrate it.

## Losing the connection

A store's connection can go away under it - the server restarts, an idle
session is timed out, a network path breaks - and libpq does not notice until
the next statement.  The store therefore finds out by trying, and then, when
it is safe, resets the connection (`PQreset`), restores the session state
that does not survive a reset (the `search_path` for a store confined to a
schema) and runs the statement once more.

Safety is the whole question, and getting it wrong is worse than never
retrying:

- A statement issued **inside a transaction** is never replayed, because the
  transaction it belonged to is gone and repeating one statement of it would
  write a fragment of a save.
- **`COMMIT` and `ROLLBACK` are never replayed.**  An empty `COMMIT` on a
  fresh connection succeeds, so replaying one would report a save that never
  happened.  The store tracks its own transaction rather than asking libpq
  after the fact: a dropped connection answers `PQTRANS_UNKNOWN`, which says
  nothing about what was open when it died.

One case stays undecidable, as it does for every client of every database: a
connection that dies after the server commits but before the reply arrives is
reported as a failure, because nothing on this side can tell it from a commit
that never happened.

The tests cover this by terminating the store's backend from a connection of
their own (`pg_terminate_backend`) and checking that the next fetch and save
succeed, that the store is still reading its own schema afterwards, and that
a save interrupted mid-flight either completes or leaves nothing behind.

## What runs in SQL, and what does not

A fetch's predicate is translated as far as it goes and the rest is
evaluated in memory, over the rows the translated part returned.  The
division matters: a predicate that does not translate at all means reading
every row of the entity and faulting each one.

Translated: comparisons against a constant on integer, floating-point,
decimal, boolean, date and string columns; `==`/`!=`/`IN` on UUID and binary
columns as well (a byte comparison is exact, even though ordering those
would mean nothing); `== nil` and `!= nil` on **any** column, whatever it
holds; `BEGINSWITH`, `ENDSWITH`, `CONTAINS`, `LIKE` and `MATCHES`-free
string matching, case-sensitive or `[c]`; `BETWEEN`, `IN`; `SELF` against
object IDs; key paths across relationships, with `ANY`/`ALL` where they
cross a to-many; and `AND`/`OR`/`NOT` of any of those.

A conjunction is translated **piece by piece**: the parts that translate go
into the `WHERE` clause and only the remainder is evaluated in memory.  So

```objc
[NSPredicate predicateWithFormat:@"age > %d AND settings == %@", 40, value]
```

fetches the rows over forty and checks the transformable attribute on those,
rather than reading the table.  `OR` and `NOT` cannot be split that way -
dropping a disjunct would narrow the result, dropping half a negation would
widen it - so they translate whole or not at all.

Counting related rows translates too.  `employees.@count > 2` becomes a
correlated count:

```sql
SELECT "Z_PK", "Z_ENT" FROM "ZCOMPANY" WHERE "Z_ENT" IN (1)
  AND ((SELECT COUNT(*) FROM "ZPERSON" c0
         WHERE c0."ZEMPLOYER" = "ZCOMPANY"."Z_PK") > 2)
```

and `SUBQUERY(employees, $e, $e.age > 40).@count > 1` adds the subquery's
own predicate to that `WHERE`.  A count, rather than a join, is what makes
`@count == 0` work: a row with nothing related still has a count.

(`SUBQUERY` is understood where the framework can express it.  gnustep-base
could not parse `SUBQUERY(...)` at all until the patch this project carries
in `patches/gnustep/`, so against an unpatched one the question cannot be
asked and the store never sees it; `@count` on a relationship works
everywhere.  The two parsers also build the same predicate differently -
Apple makes `SUBQUERY(...).@count` a `valueForKeyPath:` function
expression, gnustep-base a key path composition - and the store reads
either.)

Left to the in-memory evaluator: diacritic-insensitive and locale-sensitive
matching (`[d]`, `[cd]`); ordering comparisons on transformable values;
equality on transformable values (what is stored is whatever the value
transformer produced, and two equal objects need not archive to the same
bytes); aggregates other than `@count`; an `IN` list longer than the statement's
parameter budget (60000 on PostgreSQL, where the wire protocol counts them
in sixteen bits; MySQL escapes values into the statement instead and so
counts far higher);
sort descriptors whose key path crosses a relationship or whose selector is
neither `compare:` nor `caseInsensitiveCompare:`; and block predicates,
which nothing could translate.

Counting asks the database to count (`SELECT COUNT(*)`) when the predicate
translated and no fetch limit or offset is set; otherwise the keys are
fetched and counted here, as they must be.

When any part of the predicate or any sort descriptor is evaluated in
memory, the fetch limit and offset are applied in memory too - applying them
in SQL would take them from the wrong set of rows.

## How a statement is built

Fetches are assembled through a small query object
([`CDSQLQuery`](../Common/CDSQLQuery.h)) rather than by appending to a
string: a select list, a from-table and its alias, a join list, conditions,
grouping, ordering and a limit, written out in that order.  Parameters are
collected as each part is built, so their order matches the placeholders in
the finished statement.

It is deliberately not a relational algebra.  A fetch request can name one
entity, a predicate, sort descriptors, a limit and a result type - there is
no union or derived table to plan.  What the object provides is somewhere to
put a join list and a select list, and one place that hands out aliases, so
that a join and a correlated subquery cannot pick the same name.  The rows
of the entity being fetched are always `t0`, which is what the correlated
subqueries refer back to.

It earns its place on three shapes:

**Sorting on another table's value.**  `employer.name` joins that table in:

```sql
SELECT t0."Z_PK", t0."Z_ENT" FROM "ZPERSON" t0
  LEFT JOIN "ZCOMPANY" s0 ON s0."Z_PK" = t0."ZEMPLOYER"
 WHERE t0."Z_ENT" IN (3, 2) AND (t0."ZEMPLOYER" IS NOT NULL)
 ORDER BY s0."ZNAME" COLLATE "C" DESC, t0."Z_PK" LIMIT 1
```

The join is a LEFT one so that a row with nothing related still comes back,
as it does when the sort happens in memory.  Sorting on a *to-many* key path
has no single value to sort by, so it stays in memory.

**Dictionary results.**  When a request asks for values rather than objects
and names the properties it wants, the columns are read directly - no
managed objects are built - and `DISTINCT` and `GROUP BY` become the
database's work:

```sql
SELECT DISTINCT t0."ZAGE" FROM "ZPERSON" t0 WHERE t0."Z_ENT" IN (3, 2)
 ORDER BY t0."ZAGE" ASC
```

**Aggregates.**  An `NSExpressionDescription` over `max:`, `min:`, `sum:`,
`average:` or `count:` of a local attribute is selected as the aggregate
itself:

```sql
SELECT MAX(t0."ZAGE") FROM "ZPERSON" t0 WHERE t0."Z_ENT" IN (3, 2)
```

An aggregate whose key path crosses a relationship - `count:(employees)`,
`sum:(employees.age)` - reads a column of another table, so that table is
joined in.  The join is a `LEFT JOIN`, which is what makes a company with no
employees a row with a count of nought rather than no row at all:

```sql
SELECT t0."ZNAME", COUNT(a0."Z_PK"), SUM(a0."ZAGE") FROM "ZCOMPANY" t0
 LEFT JOIN "ZPERSON" a0 ON a0."ZEMPLOYER" = t0."Z_PK"
 WHERE t0."Z_ENT" IN (1) GROUP BY t0."ZNAME"
```

Crossing a to-many multiplies the rows, which is right for an aggregate over
those rows and wrong for anything counted alongside it - a `COUNT` of the
fetched entity would count the pairs.  So one to-many crossing is allowed per
request, and a second one, or a local aggregate mixed in with one, is
declined rather than answered with the product.  Across a to-one there is no
fan-out and no such restriction.

An aggregate is read back as the type its expression description declares,
so `max:` over a name answers a name; without a declared type the text is
read as a number.

**Grouping.**  `propertiesToGroupBy` becomes `GROUP BY`, `havingPredicate`
becomes `HAVING`, and a grouped result can be sorted by its own aggregate:

```sql
SELECT t0."ZAGE", COUNT(t0."ZNAME") FROM "ZPERSON" t0 WHERE t0."Z_ENT" IN (3, 2)
 GROUP BY t0."ZAGE" HAVING COUNT(t0."ZNAME") > 1
```

A having predicate may name a selected expression (`headcount > 1`) or write
the aggregate out (`count:(name) > 1`); both translate.

Anything the query cannot express - a second to-many join, a request whose
predicate is only partly evaluated in SQL - falls back to reading the
objects, which is what the store did for every dictionary result before.

**On FreeCoreData the store is asked first.**  Its `NSManagedObjectContext`
can build dictionary results itself, from snapshots, including grouping,
aggregates and `HAVING` - and used to do so for every store, which meant
reading every object.  It now asks the store, by `respondsToSelector:`,
whether it can shape the request (`-_canShapeDictionaryRequest:`); this one
answers by building the very query it would run and saying yes if it came
out, so it never claims more than it can express.  What it declines the
framework still shapes in memory.  Against Apple's CoreData the request
always arrives here, since Apple delegates it unconditionally.

## Optimistic locking

Every row carries `Z_OPT`, and the store remembers the version of each row it
reads.  An update is then conditional on the row still being that version, so
a row changed by another client in between is refused rather than silently
overwritten: the save fails with `NSPersistentStoreSaveConflictsError`
carrying `NSMergeConflict` objects under
`NSPersistentStoreSaveConflictsErrorKey`, each with the versions and the row
as it now stands.

Which layer notices depends on the framework.  A context that re-reads the
row at save time catches the common case before the store is ever asked -
both Apple's CoreData and FreeCoreData do - so the store's check is the
backstop for writers the framework cannot see: other processes, other
machines, and batch requests.  Neither framework routes a store-reported
conflict through the context's merge policy, so it arrives as a save error
for the application to resolve.

Two caveats.  A row this store has never read carries no expectation and is
written unconditionally.  And the version table grows with the number of rows
the store has read, since it keeps one number per row for the life of the
store.

## Persistent history (FreeCoreData only)

Pass `NSPersistentHistoryTrackingKey` in the store options and every save and
batch operation records a transaction in `Z_ATRANSACTION` with one
`Z_ACHANGE` row per object touched, including tombstones for attributes
marked `preservesValueInHistoryOnDeletion`.  Fetches and purges anchored by
token, date or transaction, the predicate-filtered
`fetchHistoryWithFetchRequest:` flavor over either history entity, and every
result type are all supported.  With
`NSPersistentStoreRemoteChangeNotificationPostOptionKey` the store also posts
`NSPersistentStoreRemoteChangeNotification` carrying its new token.

Nothing extra is needed to make the coordinator aware of the store's history
position: `-currentPersistentHistoryTokenFromStores:` asks each store through
`respondsToSelector:`, so implementing `_historyTrackingEnabled` and
`_lastHistoryTransactionNumber` is the whole of it.

**This works against FreeCoreData only**, through public API of its own that
Apple's CoreData has no equivalent of.  A store implementing history has to
do two things neither framework used to allow from outside:

*Read the request* - is it a fetch or a purge, and what is it anchored to?
FreeCoreData publishes `-isPurgeRequest`, `-anchorDate` and
`-anchorTransactionNumber`.

*Build what it answers with* - the transactions, changes and tokens.
FreeCoreData publishes `+[NSPersistentHistoryTransaction
transactionWithNumber:timestamp:author:contextName:processID:bundleID:storeIdentifier:changes:]`,
`+[NSPersistentHistoryChange changeWithID:type:objectID:updatedProperties:tombstone:]`,
`+[NSPersistentHistoryToken tokenWithTransactionNumbersByStoreIdentifier:]`
and `-[NSPersistentHistoryToken transactionNumberForStoreIdentifier:]`.  A
transaction adopts its changes when it is made, which is what wires up each
change's `-transaction` back-pointer.

Why Apple's cannot serve:

- Apple publishes `token`, `fetchRequest` and `resultType` on
  `NSPersistentHistoryChangeRequest`, and nothing else; this framework
  publishes exactly the same three and keeps `_isPurge`, `_anchorDate` and
  `_anchorTransactionNumber` to itself.
- The class does not carry the distinction: `fetchHistoryAfterDate:` and
  `deleteHistoryBeforeDate:` both return a plain
  `NSPersistentHistoryChangeRequest` (verified against Apple's runtime), so
  `isKindOfClass:` cannot separate them.
- The default `resultType` only hints.  Apple pins a purge to
  `NSPersistentHistoryResultTypeStatusOnly` and silently refuses to raise it,
  but a fetch may be set to `StatusOnly` too, so the common case stays
  ambiguous - and running a purge as a fetch would delete history someone
  asked to read.

So the store reaches into nothing.  It declares those methods in its own
source rather than importing a header - which is what lets the same file
still compile against Apple's CoreData - and guards every call with a
runtime check.  Built against Apple's CoreData that check is
false, and history requests are reported as an unsupported request type.  The
test suite checks both halves: the behavior on FreeCoreData, and the refusal
on Apple.

## Not implemented

- **Key paths crossing relationships in *sort descriptors*** (predicates do
  translate - see below).  Those fetches are ordered in memory instead, as
  they are in the SQLite store.
- **Derived attributes** other than the plain copy form, which becomes a
  stored generated column.  Other derivations are written as whatever the
  object holds at save time.
- **Connection pooling.**  One connection per store, which is the shape Core
  Data expects (a coordinator per thread brings its own store, and so its own
  connection).

## On macOS

`CDPostgreSQLStore.xcodeproj` builds the same sources against **Apple's**
CoreData, which is the point: a store written to the public API can be
checked against the implementation this project is a port of.  (Persistent
history is the exception and is skipped there; see above.)  It has two
targets - `CDPostgreSQLStore` (a static library) and `CDPostgreSQLStoreTests`
(the same test suite) - and needs Homebrew's libpq:

```sh
brew install libpq

xcodebuild -project Backends/PostgreSQL/CDPostgreSQLStore.xcodeproj \
    -scheme CDPostgreSQLStoreTests -destination 'platform=macOS' \
    TEST_RUNNER_CD_TEST_POSTGRES_URL=postgresql://postgres:test@localhost:5432/coredata_test \
    test
```

The `TEST_RUNNER_` prefix matters: **xcodebuild does not pass the shell's
environment to the test process**, and it strips that prefix when handing the
variable over.  Setting plain `CD_TEST_POSTGRES_URL` in the shell leaves the
suite skipping every test while still reporting success - which is exactly
what it did the first time this was run.  Running from the Xcode UI instead,
put `CD_TEST_POSTGRES_URL` in the scheme's Test action environment.

Debug builds set `ONLY_ACTIVE_ARCH`, because Homebrew's libpq is built for
the host architecture alone and a universal build cannot link the other
slice.

## Tests

The tests need a database:

```sh
docker run -d --name pg -e POSTGRES_PASSWORD=test -e POSTGRES_DB=coredata_test \
    -p 5432:5432 postgres:16

CD_TEST_POSTGRES_URL=postgresql://postgres:test@localhost/coredata_test \
    make -C Backends/PostgreSQL/Tests run-tests
```

Each test runs in a schema of its own, which is dropped afterwards, so runs
cannot collide.  With `CD_TEST_POSTGRES_URL` unset every test returns
immediately, which is why `run-tests` is safe to run anywhere.  That silence
is wrong where a server was meant to be there - a database that failed to
start would leave a green run that tested nothing - so setting
`CD_TEST_REQUIRE_DATABASE` turns the skip into a failure.  CI sets it.

The suite is written against behavior Apple's CoreData defines, so it runs on
macOS against Apple's framework as well (see above) - which is how it was
first verified.  Where the two disagree, Apple arbitrates: batch updating a
relationship, for instance, is rejected by Apple with an exception before the
request reaches any store, so the test accepts a raise as well as a returned
error.
