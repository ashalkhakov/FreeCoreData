# MySQL / MariaDB backend

An `NSIncrementalStore` that keeps a Core Data model in MySQL or MariaDB.
Like the PostgreSQL backend it is an addon: it lives outside
`CoreData.framework` and nothing else in this repository depends on it.

Status: **experimental**, and feature-for-feature with the PostgreSQL
backend - fetching, saving, faulting, batch requests, optimistic locking,
predicates across relationships, connection recovery, in-place migration,
and (against FreeCoreData) persistent history.  The same 54 tests run
against it, and pass on MySQL 8 and MariaDB 11 alike.

For what the store *does* - the schema it keeps, how history and locking
work, what migration reconciles - read
[the PostgreSQL backend's README](../PostgreSQL/README.md): the two agree on
all of it.  What follows is only where MySQL differs.

## Building

Needs a MySQL client library.  MariaDB Connector/C speaks to both servers
and is the one this was developed against (`brew install
mariadb-connector-c`, `apt install libmariadb-dev`); `libmysqlclient-dev`
serves as well.

```sh
make                          # the framework, from the repository root
make -C Backends/MySQL
```

The makefile finds the library through `mariadb_config` or `mysql_config`.

## Using it

```objc
#import <CDMySQLStore/CDMySQLStore.h>

NSURL *url = [NSURL URLWithString:@"mysql://user:secret@localhost:3306/mydb"];

[coordinator addPersistentStoreWithType:CDMySQLStoreType
                          configuration:nil
                                    URL:url
                                options:nil
                                  error:&error];
```

The URL is taken apart by the store (MySQL has no URI parser of libpq's
kind): user, password, host, port - 3306 by default - and database.  Two
query parameters are understood:

- `sslmode` - `disable`, `require` (the default), `verify-ca` or
  `verify-full`.  The default deliberately does not verify: a server that
  was never given a certificate answers with a self-signed one, and
  refusing to speak to it would make the common case unusable.  A
  deployment that cares says so in the URL.
- `sslrootcert` - the CA to verify against.

`CDMySQLSchemaNameOption` names the **database** to use instead of the URL's
- in MySQL a schema is a database - and it is created if it does not exist.

The store always connects over TCP.  A MySQL client otherwise reads the host
name `localhost` as an instruction to use a local socket, whatever port was
asked for, which is not what a URL naming a server means.

## Where MySQL differs

| | PostgreSQL | MySQL |
| --- | --- | --- |
| Identifier quoting | `"name"` | `` `name` ``, backtick doubled |
| Identifier limit | 63 bytes | 64 characters |
| Schema | a namespace inside a database | *is* a database |
| Text ordering | `COLLATE "C"` per comparison | `COLLATE utf8mb4_bin` on the column |
| Case-insensitive match | `ILIKE` | `LOWER(x) LIKE LOWER(y)` |
| Upsert | `ON CONFLICT … DO UPDATE` | `ON DUPLICATE KEY UPDATE` |
| Reading a new key back | `UPDATE … RETURNING` | `UPDATE … SET x = LAST_INSERT_ID(x + 1)` |
| Creation lock | `pg_advisory_xact_lock`, released by the transaction | `GET_LOCK`, held by the session and released by hand |
| Reconnecting | `PQreset`, same handle | a new handle, swapped in |
| `ESCAPE` clause | `ESCAPE '\'` | `ESCAPE '\\'` - a backslash escapes in a MySQL literal |
| Booleans | `true` / `false` | `1` / `0` |

Types follow: `smallint`, `int`, `bigint`, `tinyint(1)` for booleans,
`double`, `float`, `decimal(65,20)` (MySQL needs a precision where
PostgreSQL's `numeric` takes none), `text collate utf8mb4_bin`, `char(36)`
for UUIDs, `longblob` for binary and transformable values.

## The one behavioural difference worth knowing

**MySQL commits DDL as it goes.**  A `CREATE TABLE` or `ALTER TABLE` ends the
transaction it is in, which PostgreSQL does not do.  Two consequences:

- Creating a store is not one atomic step.  The creation lock is what makes
  it safe against another client doing the same thing at the same moment,
  and the store re-checks inside the lock rather than trusting a rollback.
- **A migration that fails partway leaves the schema partly migrated.**  On
  PostgreSQL the whole reconciliation rolls back; here it cannot.  Take a
  backup before migrating a database you care about - which is good advice
  anyway, and necessary here.

## Tests

```sh
docker run -d --name mysql -e MYSQL_ROOT_PASSWORD=test \
    -e MYSQL_DATABASE=coredata_test -p 3306:3306 mysql:8

CD_TEST_MYSQL_URL=mysql://root:test@localhost:3306/coredata_test \
    make -C Backends/MySQL/Tests run-tests
```

On macOS, against Apple's CoreData, through the Xcode project - note the
`TEST_RUNNER_` prefix, which is how xcodebuild passes a variable to the test
process:

```sh
xcodebuild -project Backends/MySQL/CDMySQLStore.xcodeproj \
    -scheme CDMySQLStoreTests -destination 'platform=macOS' \
    TEST_RUNNER_CD_TEST_MYSQL_URL=mysql://root:test@localhost:3306/coredata_test \
    test
```

Each test works in a database of its own, dropped afterwards.  With
`CD_TEST_MYSQL_URL` unset every test returns immediately.
