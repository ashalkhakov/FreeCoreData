/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* The fixture the SQL backend suites share.

   The two suites - PostgreSQL's and MySQL's - are the same tests: a store
   that speaks SQL over a network has the same job whichever server is at
   the other end, and a test that passes against one and was never run
   against the other is worth little.  They are therefore written once,
   here, and each backend supplies what genuinely differs: which store class
   and store type to open, which environment variable carries the URL, the
   names of its option keys, and how to cut the store's connection out from
   under it.

   The tests themselves live in CDSQLStoreTestBodies.inc, which each
   backend's suite includes inside its own @implementation rather than
   inheriting.  That is not a style preference: GNUstep's XCTest runner
   discovers only the test methods a class declares itself, so a concrete
   subclass of a base class full of tests runs nothing at all.  Including
   the bodies gives each backend's class its own copy of every test method,
   which both runners find.  This file holds everything that inheritance
   does handle - the fixture, the helpers and the hooks. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

/* Declared so the tests can ask, at runtime, whether they are running
   against a CoreData a store can implement history against.  This is
   FreeCoreData's own API; Apple's CoreData has no equivalent. */
@interface NSPersistentHistoryChangeRequest (CDFreeCoreDataAPI)
- (BOOL)isPurgeRequest;
@end

/* A model with the shapes the store has to get right: every attribute type,
   a to-one/to-many pair backed by a foreign key, an ordered to-many, and a
   many-to-many backed by a join table. */
NSManagedObjectModel *CDSQLTestModel(void);

@interface CDSQLStoreTestCase : XCTestCase
@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSURL *storeURL;
@property (nonatomic, strong) NSDictionary *storeOptions;
@property (nonatomic, strong) NSManagedObjectContext *context;
@end

/* What a backend supplies.  Every one of these is abstract here: the class
   carries no tests of its own, so nothing calls them until a backend's
   suite does. */
@interface CDSQLStoreTestCase (CDSQLStoreTestBackend)

- (Class)storeClass;
- (NSString *)storeType;
- (NSString *)schemaNameOptionKey;
- (NSString *)migrateSchemaOptionKey;

/* The variable that carries the server URL, named in the failure message
   when CD_TEST_REQUIRE_DATABASE says there has to be one. */
- (NSString *)URLEnvironmentVariableName;

/* Cuts off every connection to this database except the one doing the
   cutting, which is what a server restart or an idle-session timeout looks
   like to a client.  Answers how many were cut off.  It needs the client
   library, which is why it belongs to the backend and not here. */
- (int)terminateOtherConnections;

@end

/* The fixture and the helpers the tests are written against. */
@interface CDSQLStoreTestCase (CDSQLStoreTestFixture)

- (BOOL)databaseAvailable;
- (NSManagedObjectContext *)newContext;
- (NSManagedObject *)insertPersonNamed:(NSString *)name age:(int)age;
- (NSArray *)fetchPeopleWithPredicate:(NSPredicate *)predicate
                      sortDescriptors:(NSArray *)sortDescriptors
                              context:(NSManagedObjectContext *)context;
- (NSManagedObject *)personNamed:(NSString *)name inContext:(NSManagedObjectContext *)context;
- (NSPredicate *)namedPredicate:(NSString *)name;
- (BOOL)save;

@end
