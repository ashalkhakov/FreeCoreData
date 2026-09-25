/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* Tests for the PostgreSQL backend.  They need a database: set

      CD_TEST_POSTGRES_URL=postgresql://user:password@localhost/testdb

   and they run; leave it unset and every test returns immediately, so the
   suite is harmless on a machine without a server (CD_TEST_REQUIRE_DATABASE
   makes that silence a failure instead, which is what CI wants).  Each run
   works inside a schema of its own, dropped in -tearDown, so concurrent runs
   and leftovers from a crashed run cannot affect each other.

   The tests are in Backends/Common/Tests: they are the same for every SQL
   backend, and this file is what makes them PostgreSQL's - which store to
   open, and how to cut its connection.

   Written against behavior Apple's CoreData defines, so that the same tests
   can be run on macOS against Apple's framework once this backend is built
   there. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "CDPostgreSQLStore.h"
#import "CDSQLStoreTestCase.h"

/* One test needs a connection of its own, to pull the rug from under the
   store's. */
#import <libpq-fe.h>

@interface CDPostgreSQLStoreTests : CDSQLStoreTestCase
@end

@implementation CDPostgreSQLStoreTests

- (Class)storeClass                      { return [CDPostgreSQLStore class]; }
- (NSString *)storeType                  { return CDPostgreSQLStoreType; }
- (NSString *)schemaNameOptionKey        { return CDPostgreSQLSchemaNameOption; }
- (NSString *)migrateSchemaOptionKey     { return CDPostgreSQLMigrateSchemaOption; }
- (NSString *)URLEnvironmentVariableName { return @"CD_TEST_POSTGRES_URL"; }

/* Terminates every other backend on this database, which is what a server
   restart or an idle-session timeout looks like to a client.  Answers how
   many were cut off. */
- (int)terminateOtherConnections
{
    PGconn *connection = PQconnectdb([[self.storeURL absoluteString] UTF8String]);

    if (PQstatus(connection) != CONNECTION_OK) {
        XCTFail(@"the test could not open its own connection: %s", PQerrorMessage(connection));
        PQfinish(connection);
        return 0;
    }

    PGresult *result = PQexec(connection,
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
        "WHERE datname = current_database() AND pid <> pg_backend_pid()");
    int terminated = (PQresultStatus(result) == PGRES_TUPLES_OK) ? PQntuples(result) : 0;

    PQclear(result);
    PQfinish(connection);

    return terminated;
}

/* Every test the SQL backends share.  They are included rather than
   inherited because GNUstep's XCTest runner only finds the test methods a
   class declares itself. */
#include "CDSQLStoreTestBodies.inc"

@end
