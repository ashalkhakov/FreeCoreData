/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDSQLStore.h"

/* PostgreSQL-backed incremental store: the libpq driver and PostgreSQL's
   dialect on top of CDSQLStore, which holds everything the SQL backends
   have in common.  Read CDSQLStore.h for what the store does; this header
   is what an application needs to open one.

   The schema is the one the in-tree SQLite store keeps, so a model behaves
   the same way whichever it is stored in. */

/* The store type to pass to -addPersistentStoreWithType:...  */
extern NSString * const CDPostgreSQLStoreType;

/* The schema to confine the store to; created if it does not exist, which
   keeps several stores (or several test runs) out of each other's way
   inside one database.  The value is an NSString. */
extern NSString * const CDPostgreSQLSchemaNameOption;

/* Bring the schema into line with the model when the two have drifted
   apart - columns and tables added, removed or renamed, attribute types
   widened.  An application asking for this also passes
   NSIgnorePersistentStoreVersioningOption, because the coordinator's own
   check is file-oriented and would refuse the store first.  The value is an
   NSNumber.  See the README. */
extern NSString * const CDPostgreSQLMigrateSchemaOption;

@interface CDPostgreSQLStore : CDSQLStore {
    void *_connection;        /* PGconn * */
    long long _rowsAffected;  /* of the statement just run */
}

@end
