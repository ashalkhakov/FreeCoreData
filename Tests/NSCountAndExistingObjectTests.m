/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSCountAndExistingObjectTests - tests for NSCountResultType and
   -[NSManagedObjectContext existingObjectWithID:error:].  These tests
   are written against Apple's documented behavior so they run
   identically against Apple's CoreData on macOS and against the GNUstep
   port; run them on macOS to validate assumptions about Apple's
   implementation.

   Documented behavior being verified:

   - NSCountResultType makes the fetch return "the count of the objects
     that match the request" - as an array containing a single NSNumber;
     -countForFetchRequest:error: returns "the number of objects a given
     fetch request would have returned if it had been passed to
     executeFetchRequest:", and NSNotFound on error.
   - -existingObjectWithID:error: returns the object if the context
     recognizes it, otherwise fetches a fully realized object from the
     persistent store - "unlike object(with:), this method never returns
     a fault" - and fails when the object exists in neither the context
     nor the store (community-documented error code 133000,
     NSManagedObjectReferentialIntegrityError; the exact code is
     verified by the macOS run). */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"
#import "MemoryIncrementalStore.h"

@interface NSCountAndExistingObjectTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;

@end

@implementation NSCountAndExistingObjectTests

- (void)setUp
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"store"];
    self.storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
}

- (void)tearDown
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    [fileManager removeItemAtURL:self.storeURL error:NULL];
    [fileManager removeItemAtPath:[[self.storeURL path]
                                      stringByAppendingString:@"-wal"]
                            error:NULL];
    [fileManager removeItemAtPath:[[self.storeURL path]
                                      stringByAppendingString:@"-shm"]
                            error:NULL];
    self.storeURL = nil;
}

- (NSManagedObjectContext *)contextWithStoreType:(NSString *)storeType
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV1()];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:storeType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to add %@ store: %@", storeType, error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

- (NSManagedObject *)insertEmployeeNamed:(NSString *)name
                                  salary:(int)salary
                               inContext:(NSManagedObjectContext *)ctx
{
    NSManagedObject *employee =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx];
    [employee setValue:name forKey:@"name"];
    [employee setValue:[NSNumber numberWithInt:salary] forKey:@"salary"];
    return employee;
}

- (NSFetchRequest *)employeeRequestInContext:(NSManagedObjectContext *)ctx
                                   predicate:(NSPredicate *)predicate
                                  resultType:(NSFetchRequestResultType)type
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Employee"
                                 inManagedObjectContext:ctx]];
    [fetch setPredicate:predicate];
    [fetch setResultType:type];
    return fetch;
}

/* Runs a count-type fetch and verifies the documented result shape:
   an array containing exactly one NSNumber. */
- (NSUInteger)countFromFetchInContext:(NSManagedObjectContext *)ctx
                            predicate:(NSPredicate *)predicate
{
    NSError *error = nil;
    NSArray *result = [ctx executeFetchRequest:
                              [self employeeRequestInContext:ctx
                                                   predicate:predicate
                                                  resultType:NSCountResultType]
                                         error:&error];

    XCTAssertNotNil(result, @"count fetch failed: %@", error);
    XCTAssertEqual([result count], (NSUInteger)1,
                   @"a count fetch returns an array with a single entry");
    XCTAssertTrue([[result lastObject] isKindOfClass:[NSNumber class]],
                  @"the single entry is an NSNumber, got %@",
                  [[result lastObject] class]);
    return [[result lastObject] unsignedIntegerValue];
}

/* ------------------------------------------------------------------ */
#pragma mark - NSCountResultType
/* ------------------------------------------------------------------ */

- (void)testResultTypeConstants
{
    /* Apple's header values, kept identical here. */
    XCTAssertEqual((int)NSManagedObjectResultType, 0);
    XCTAssertEqual((int)NSManagedObjectIDResultType, 1);
    XCTAssertEqual((int)NSDictionaryResultType, 2);
    XCTAssertEqual((int)NSCountResultType, 4);
}

- (void)testCountResultTypeOnSQLiteStore
{
    {
        NSManagedObjectContext *ctx =
            [self contextWithStoreType:NSSQLiteStoreType];

        [self insertEmployeeNamed:@"Alice" salary:9 inContext:ctx];
        [self insertEmployeeNamed:@"Bob" salary:5 inContext:ctx];
        [self insertEmployeeNamed:@"Carol" salary:12 inContext:ctx];

        NSError *error = nil;
        XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
    }

    /* A fresh stack, so the counts come from the store. */
    NSManagedObjectContext *ctx = [self contextWithStoreType:NSSQLiteStoreType];

    XCTAssertEqual([self countFromFetchInContext:ctx predicate:nil],
                   (NSUInteger)3);

    /* A store-evaluated predicate. */
    XCTAssertEqual([self countFromFetchInContext:ctx
                                       predicate:[NSPredicate
                                           predicateWithFormat:@"salary > 8"]],
                   (NSUInteger)2);

    /* -countForFetchRequest: agrees with the equivalent fetch. */
    NSError *error = nil;
    NSUInteger count = [ctx countForFetchRequest:
                               [self employeeRequestInContext:ctx
                                                    predicate:nil
                                                   resultType:NSManagedObjectResultType]
                                           error:&error];
    XCTAssertEqual(count, (NSUInteger)3);
}

- (void)testCountReflectsPendingChanges
{
    NSManagedObjectContext *ctx = [self contextWithStoreType:NSSQLiteStoreType];

    [self insertEmployeeNamed:@"Alice" salary:9 inContext:ctx];
    NSManagedObject *bob = [self insertEmployeeNamed:@"Bob"
                                              salary:5
                                           inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* An unsaved insert is part of what the fetch would return, so it
       is part of the count. */
    [self insertEmployeeNamed:@"Carol" salary:12 inContext:ctx];
    XCTAssertEqual([self countFromFetchInContext:ctx predicate:nil],
                   (NSUInteger)3);

    /* An unsaved delete is not. */
    [ctx deleteObject:bob];
    XCTAssertEqual([self countFromFetchInContext:ctx predicate:nil],
                   (NSUInteger)2);
}

- (void)testCountResultTypeOnXMLStore
{
    {
        NSManagedObjectContext *ctx = [self contextWithStoreType:NSXMLStoreType];

        [self insertEmployeeNamed:@"Alice" salary:9 inContext:ctx];
        [self insertEmployeeNamed:@"Bob" salary:5 inContext:ctx];

        NSError *error = nil;
        XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
    }

    NSManagedObjectContext *ctx = [self contextWithStoreType:NSXMLStoreType];

    XCTAssertEqual([self countFromFetchInContext:ctx predicate:nil],
                   (NSUInteger)2);
    XCTAssertEqual([self countFromFetchInContext:ctx
                                       predicate:[NSPredicate
                                           predicateWithFormat:@"salary > 8"]],
                   (NSUInteger)1);
}

- (void)testCountResultTypeOnInMemoryStore
{
    NSManagedObjectContext *ctx =
        [self contextWithStoreType:NSInMemoryStoreType];

    [self insertEmployeeNamed:@"Alice" salary:9 inContext:ctx];
    [self insertEmployeeNamed:@"Bob" salary:5 inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* A second context on the same coordinator. */
    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:[ctx persistentStoreCoordinator]];

    XCTAssertEqual([self countFromFetchInContext:ctx2 predicate:nil],
                   (NSUInteger)2);
    XCTAssertEqual([self countFromFetchInContext:ctx2
                                       predicate:[NSPredicate
                                           predicateWithFormat:@"salary > 8"]],
                   (NSUInteger)1);
}

- (void)testCountResultTypeIsHandledByCustomIncrementalStore
{
    /* An NSIncrementalStore receives the count request itself when the
       context has nothing to merge in. */
    [NSPersistentStoreCoordinator registerStoreClass:[MemoryIncrementalStore class]
                                        forStoreType:MemoryIncrementalStoreType];

    NSManagedObjectModel *model = IncrementalStoreTestModel();
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    MemoryIncrementalStore *store = (MemoryIncrementalStore *)
        [psc addPersistentStoreWithType:MemoryIncrementalStoreType
                          configuration:nil
                                    URL:self.storeURL
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store, @"failed to add store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    [[store tableForEntityName:@"Person"]
        setObject:[NSDictionary dictionaryWithObject:@"Alice" forKey:@"name"]
           forKey:@"p1"];
    [[store tableForEntityName:@"Person"]
        setObject:[NSDictionary dictionaryWithObject:@"Bob" forKey:@"name"]
           forKey:@"p2"];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[model entitiesByName] objectForKey:@"Person"]];
    [fetch setResultType:NSCountResultType];

    NSUInteger fetchesBefore = [store fetchRequestCount];
    NSArray *result = [ctx executeFetchRequest:fetch error:&error];

    XCTAssertNotNil(result, @"count fetch failed: %@", error);
    XCTAssertEqual([result count], (NSUInteger)1);
    XCTAssertEqual([[result lastObject] unsignedIntegerValue], (NSUInteger)2);
    XCTAssertTrue([store fetchRequestCount] > fetchesBefore,
                  @"the store itself must receive the count request");
}

/* ------------------------------------------------------------------ */
#pragma mark - existingObjectWithID:error:
/* ------------------------------------------------------------------ */

- (void)testExistingObjectWithIDReturnsRecognizedObject
{
    NSManagedObjectContext *ctx = [self contextWithStoreType:NSSQLiteStoreType];
    NSManagedObject *alice = [self insertEmployeeNamed:@"Alice"
                                                salary:9
                                             inContext:ctx];

    /* Recognized (still unsaved, temporary ID): returned directly. */
    NSError *error = nil;
    NSManagedObject *found = [ctx existingObjectWithID:[alice objectID]
                                                 error:&error];
    XCTAssertEqual(found, alice);
    XCTAssertNil(error);
}

- (void)testExistingObjectWithIDFetchesRealizedObjectFromStore
{
    NSURL *uri = nil;
    {
        NSManagedObjectContext *ctx =
            [self contextWithStoreType:NSSQLiteStoreType];
        NSManagedObject *alice = [self insertEmployeeNamed:@"Alice"
                                                    salary:9
                                                 inContext:ctx];

        NSError *error = nil;
        XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
        uri = [[alice objectID] URIRepresentation];
    }

    /* A fresh stack that has never seen the object. */
    NSManagedObjectContext *ctx = [self contextWithStoreType:NSSQLiteStoreType];
    NSManagedObjectID *objectID = [[ctx persistentStoreCoordinator]
        managedObjectIDForURIRepresentation:uri];
    XCTAssertNotNil(objectID);

    NSError *error = nil;
    NSManagedObject *found = [ctx existingObjectWithID:objectID error:&error];

    XCTAssertNotNil(found, @"existingObjectWithID failed: %@", error);
    /* "...this method never returns a fault." */
    XCTAssertFalse([found isFault]);
    XCTAssertEqualObjects([found valueForKey:@"name"], @"Alice");
}

- (void)testExistingObjectWithIDFailsForMissingObject
{
    NSURL *uri = nil;
    {
        NSManagedObjectContext *ctx =
            [self contextWithStoreType:NSSQLiteStoreType];
        NSManagedObject *alice = [self insertEmployeeNamed:@"Alice"
                                                    salary:9
                                                 inContext:ctx];

        NSError *error = nil;
        XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
        uri = [[alice objectID] URIRepresentation];

        [ctx deleteObject:alice];
        XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
    }

    NSManagedObjectContext *ctx = [self contextWithStoreType:NSSQLiteStoreType];
    NSManagedObjectID *objectID = [[ctx persistentStoreCoordinator]
        managedObjectIDForURIRepresentation:uri];
    XCTAssertNotNil(objectID);

    NSError *error = nil;
    NSManagedObject *found = [ctx existingObjectWithID:objectID error:&error];

    XCTAssertNil(found);
    XCTAssertNotNil(error, @"a missing object must produce an error");
    XCTAssertEqualObjects([error domain], NSCocoaErrorDomain);
    XCTAssertEqual([error code],
                   (NSInteger)NSManagedObjectReferentialIntegrityError);
}

- (void)testExistingObjectWithIDOnAtomicStore
{
    NSURL *aliceURI = nil, *bobURI = nil;
    {
        NSManagedObjectContext *ctx = [self contextWithStoreType:NSXMLStoreType];
        NSManagedObject *alice = [self insertEmployeeNamed:@"Alice"
                                                    salary:9
                                                 inContext:ctx];
        NSManagedObject *bob = [self insertEmployeeNamed:@"Bob"
                                                  salary:5
                                               inContext:ctx];

        NSError *error = nil;
        XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
        aliceURI = [[alice objectID] URIRepresentation];
        bobURI = [[bob objectID] URIRepresentation];

        [ctx deleteObject:bob];
        XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
    }

    NSManagedObjectContext *ctx = [self contextWithStoreType:NSXMLStoreType];
    NSPersistentStoreCoordinator *psc = [ctx persistentStoreCoordinator];

    NSError *error = nil;
    NSManagedObject *alice = [ctx existingObjectWithID:
            [psc managedObjectIDForURIRepresentation:aliceURI]
                                                 error:&error];
    XCTAssertNotNil(alice, @"existingObjectWithID failed: %@", error);
    XCTAssertFalse([alice isFault]);
    XCTAssertEqualObjects([alice valueForKey:@"name"], @"Alice");

    NSManagedObjectID *bobID =
        [psc managedObjectIDForURIRepresentation:bobURI];
    NSManagedObject *bob = (bobID != nil)
        ? [ctx existingObjectWithID:bobID error:&error] : nil;
    XCTAssertNil(bob, @"the deleted employee must not be found");
}

@end
