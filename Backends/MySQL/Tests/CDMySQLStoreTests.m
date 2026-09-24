/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* Tests for the MySQL/MariaDB backend.  They need a server: set

      CD_TEST_MYSQL_URL=mysql://user:password@localhost/testdb

   and they run; leave it unset and every test returns immediately, so the
   suite is harmless on a machine without one (CD_TEST_REQUIRE_DATABASE makes
   that silence a failure instead, which is what CI wants).  Each run works
   inside a database of its own, dropped in -tearDown, so concurrent runs and
   leftovers from a crashed run cannot affect each other.

   The tests are in Backends/Common/Tests: they are the same for every SQL
   backend, and this file is what makes them MySQL's - which store to open,
   and how to cut its connection.

   Written against behavior Apple's CoreData defines, so that the same tests
   can be run on macOS against Apple's framework too. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "CDMySQLStore.h"
#import "CDSQLStoreTestCase.h"

/* One test needs a connection of its own, to pull the rug from under the
   store's. */
#import <mysql.h>

@interface CDMySQLStoreTests : CDSQLStoreTestCase
@end

@implementation CDMySQLStoreTests

- (Class)storeClass                      { return [CDMySQLStore class]; }
- (NSString *)storeType                  { return CDMySQLStoreType; }
- (NSString *)schemaNameOptionKey        { return CDMySQLSchemaNameOption; }
- (NSString *)migrateSchemaOptionKey     { return CDMySQLMigrateSchemaOption; }
- (NSString *)URLEnvironmentVariableName { return @"CD_TEST_MYSQL_URL"; }

/* Terminates every other backend on this database, which is what a server
   restart or an idle-session timeout looks like to a client.  Answers how
   many were cut off. */
- (int)terminateOtherConnections
{
    NSURL *url = self.storeURL;
    MYSQL *connection = mysql_init(NULL);
    unsigned int protocol = MYSQL_PROTOCOL_TCP;

    mysql_options(connection, MYSQL_OPT_PROTOCOL, &protocol);

    my_bool enforce = 1, verify = 0;

    mysql_options(connection, MYSQL_OPT_SSL_ENFORCE, &enforce);
    mysql_options(connection, MYSQL_OPT_SSL_VERIFY_SERVER_CERT, &verify);

    if (mysql_real_connect(connection,
                           [[url host] UTF8String],
                           [[url user] UTF8String],
                           [[url password] UTF8String],
                           NULL,
                           [url port] != nil ? [[url port] unsignedIntValue] : 3306,
                           NULL, 0) == NULL) {
        XCTFail(@"the test could not open its own connection: %s", mysql_error(connection));
        mysql_close(connection);
        return 0;
    }

    /* Every other session of ours, by the account the tests connect as. */
    unsigned long own = mysql_thread_id(connection);
    NSMutableArray *ids = [NSMutableArray array];

    if (mysql_query(connection, "SELECT id FROM information_schema.processlist WHERE user = SUBSTRING_INDEX(CURRENT_USER(), '@', 1)") == 0) {
        MYSQL_RES *result = mysql_store_result(connection);
        MYSQL_ROW row;

        while (result != NULL && (row = mysql_fetch_row(result)) != NULL)
            if (row[0] != NULL && strtoul(row[0], NULL, 10) != own)
                [ids addObject:[NSString stringWithUTF8String:row[0]]];
        if (result != NULL)
            mysql_free_result(result);
    }

    for (NSString *identifier in ids)
        mysql_query(connection, [[NSString stringWithFormat:@"KILL CONNECTION %@", identifier] UTF8String]);

    mysql_close(connection);

    return (int)[ids count];
}

/* Every test the SQL backends share.  They are included rather than
   inherited because GNUstep's XCTest runner only finds the test methods a
   class declares itself. */
#include "CDSQLStoreTestBodies.inc"

@end
