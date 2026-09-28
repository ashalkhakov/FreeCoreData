/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* Both SQL backends in one process.

   Each backend is a subclass of CDSQLStore, which they share.  When each
   compiled CDSQLStore and CDSQLQuery in, a process that loaded both had two
   classes of each name; the runtime kept one, and the other backend's store
   class answered with NSIncrementalStore's abstract methods ("-[CDPostgreSQLStore
   loadMetadata:] is an abstract method").  The shared part is now a library
   of its own, libCDSQLStore, which both link.

   The first test needs no server.  The second opens a store of each kind,
   side by side, when both CD_TEST_POSTGRES_URL and CD_TEST_MYSQL_URL are
   set; CD_TEST_REQUIRE_DATABASE makes their absence a failure. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "CDPostgreSQLStore.h"
#import "CDMySQLStore.h"

@interface CDSQLBackendsTogetherTests : XCTestCase
@end

@implementation CDSQLBackendsTogetherTests

- (void)testOneSQLStoreForBoth
{
    Class shared = NSClassFromString(@"CDSQLStore");
    SEL load = @selector(loadMetadata:);

    XCTAssertNotNil(shared);
    XCTAssertEqual([CDPostgreSQLStore superclass], shared);
    XCTAssertEqual([CDMySQLStore superclass], shared);
    XCTAssertNotEqual([shared instanceMethodForSelector:load],
                      [NSIncrementalStore instanceMethodForSelector:load]);
    XCTAssertEqual([CDPostgreSQLStore instanceMethodForSelector:load], [shared instanceMethodForSelector:load]);
    XCTAssertEqual([CDMySQLStore instanceMethodForSelector:load], [shared instanceMethodForSelector:load]);
}

static NSManagedObjectModel *CDTogetherModel(void)
{
    NSAttributeDescription *name = [[[NSAttributeDescription alloc] init] autorelease];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];

    NSEntityDescription *note = [[[NSEntityDescription alloc] init] autorelease];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"NSManagedObject"];
    [note setProperties:@[ name ]];

    NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] init] autorelease];
    [model setEntities:@[ note ]];
    return model;
}

/* A note saved through a store of this type, and read back through a
   coordinator of its own. */
- (void)assertStoreType:(NSString *)type class:(Class)storeClass URL:(NSURL *)url
{
    NSManagedObjectModel *model = CDTogetherModel();
    NSDictionary *options = @{ CDSQLStoreSchemaNameOption :
        [NSString stringWithFormat:@"cdtogether_%d", (int)[[NSProcessInfo processInfo] processIdentifier]] };
    NSError *error = nil;

    [NSPersistentStoreCoordinator registerStoreClass:storeClass forStoreType:type];
    for (int pass = 0; pass < 2; pass++) {
        NSPersistentStoreCoordinator *coordinator = [[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model] autorelease];
        XCTAssertNotNil([coordinator addPersistentStoreWithType:type configuration:nil URL:url options:options error:&error],
                        @"%@: %@", type, error);
        NSManagedObjectContext *context = [[[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType] autorelease];
        [context setPersistentStoreCoordinator:coordinator];
        if (pass == 0) {
            NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
            [note setValue:type forKey:@"name"];
            XCTAssertTrue([context save:&error], @"%@: %@", type, error);
        } else {
            NSArray *notes = [context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Note"] error:&error];
            XCTAssertEqualObjects([notes valueForKey:@"name"], @[ type ], @"%@: %@", type, error);
        }
    }
    if (![storeClass destroyStoreAtURL:url options:options error:&error])
        NSLog(@"could not drop the test schema: %@", error);
}

- (void)testBothStoresInOneProcess
{
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *postgres = environment[@"CD_TEST_POSTGRES_URL"];
    NSString *mysql = environment[@"CD_TEST_MYSQL_URL"];

    if ([postgres length] == 0 || [mysql length] == 0) {
        if ([environment[@"CD_TEST_REQUIRE_DATABASE"] length] > 0)
            XCTFail(@"CD_TEST_REQUIRE_DATABASE is set, but CD_TEST_POSTGRES_URL and CD_TEST_MYSQL_URL are not both");
        return;
    }
    [self assertStoreType:CDPostgreSQLStoreType class:[CDPostgreSQLStore class] URL:[NSURL URLWithString:postgres]];
    [self assertStoreType:CDMySQLStoreType class:[CDMySQLStore class] URL:[NSURL URLWithString:mysql]];
}

@end
