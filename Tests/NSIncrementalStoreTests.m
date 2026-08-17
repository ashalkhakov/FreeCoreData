/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSIncrementalStoreTests - NSIncrementalStore contract tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "MemoryIncrementalStore.h"

@interface NSIncrementalStoreTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@property (nonatomic, strong) MemoryIncrementalStore *store;
@property (nonatomic, strong) NSEntityDescription *entity;

@end

@implementation NSIncrementalStoreTests

- (void)setUp
{
    [NSPersistentStoreCoordinator registerStoreClass:[MemoryIncrementalStore class]
                                        forStoreType:MemoryIncrementalStoreType];
    self.model = IncrementalStoreTestModel();
    self.psc = [[NSPersistentStoreCoordinator alloc]
                   initWithManagedObjectModel:self.model];
    NSURL *url = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSError *error = nil;
    self.store = (MemoryIncrementalStore *)
        [self.psc addPersistentStoreWithType:MemoryIncrementalStoreType
                               configuration:nil
                                         URL:url
                                     options:nil
                                       error:&error];
    self.ctx = [[NSManagedObjectContext alloc] init];
    [self.ctx setPersistentStoreCoordinator:self.psc];
    self.entity = [[self.model entitiesByName] objectForKey:@"Person"];
}

- (void)tearDown
{
    self.ctx = nil;
    self.store = nil;
    self.psc = nil;
    self.model = nil;
    self.entity = nil;
}

- (void)seedRow:(NSDictionary *)row forReference:(id)ref
{
    NSMutableDictionary *table = [self.store tableForEntityName:@"Person"];
    [table setObject:row forKey:ref];
}

- (NSFetchRequest *)personFetchRequest
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:self.entity];
    return fetch;
}

/* -- store setup / metadata ------------------------------------------ */

- (void)testAddPersistentStoreCallsLoadMetadata
{
    XCTAssertNotNil(self.store);
    XCTAssertTrue([self.store isKindOfClass:[MemoryIncrementalStore class]]);
    XCTAssertTrue([self.store isKindOfClass:[NSIncrementalStore class]]);
    XCTAssertEqual(self.store.loadMetadataCallCount, (NSUInteger)1);
    XCTAssertEqual([[self.psc persistentStores] count], (NSUInteger)1);
}

- (void)testStoreMetadataContainsTypeAndUUID
{
    NSDictionary *metadata = [self.psc metadataForPersistentStore:self.store];
    XCTAssertEqualObjects([metadata objectForKey:NSStoreTypeKey],
                          MemoryIncrementalStoreType);
    XCTAssertNotNil([metadata objectForKey:NSStoreUUIDKey]);
}

- (void)testStoreIdentifierMatchesMetadataUUID
{
    NSDictionary *metadata = [self.psc metadataForPersistentStore:self.store];
    XCTAssertEqualObjects([self.store identifier],
                          [metadata objectForKey:NSStoreUUIDKey]);
}

/* -- object IDs and reference objects -------------------------------- */

- (void)testNewObjectIDIsPermanent
{
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"r1"];
    XCTAssertNotNil(objectID);
    XCTAssertFalse([objectID isTemporaryID]);
    XCTAssertEqualObjects([[objectID entity] name], @"Person");
    XCTAssertEqualObjects([objectID persistentStore], self.store);
}

- (void)testReferenceObjectRoundTripString
{
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"r1"];
    XCTAssertEqualObjects([self.store referenceObjectForObjectID:objectID], @"r1");
}

- (void)testReferenceObjectRoundTripNumber
{
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity
                         referenceObject:[NSNumber numberWithInt:42]];
    id ref = [self.store referenceObjectForObjectID:objectID];
    XCTAssertEqualObjects([ref description],
                          [[NSNumber numberWithInt:42] description]);
}

- (void)testObjectIDsAreUniquedPerReferenceObject
{
    NSManagedObjectID *first =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"r1"];
    NSManagedObjectID *second =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"r1"];
    NSManagedObjectID *other =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"r2"];
    XCTAssertEqualObjects(first, second);
    XCTAssertFalse([first isEqual:other]);
}

- (void)testObjectIDURIRepresentationRoundTrip
{
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"r1"];
    NSURL *uri = [objectID URIRepresentation];
    XCTAssertNotNil(uri);
    XCTAssertEqualObjects([uri scheme], @"x-coredata");
    NSManagedObjectID *roundTrip =
        [self.psc managedObjectIDForURIRepresentation:uri];
    XCTAssertEqualObjects(roundTrip, objectID);
}

/* -- fetching --------------------------------------------------------- */

- (void)testFetchRoutesToExecuteRequest
{
    [self seedRow:[NSDictionary dictionaryWithObjectsAndKeys:
                      @"Alice", @"name",
                      [NSNumber numberWithInt:30], @"age", nil]
        forReference:@"r1"];
    [self seedRow:[NSDictionary dictionaryWithObjectsAndKeys:
                      @"Bob", @"name",
                      [NSNumber numberWithInt:40], @"age", nil]
        forReference:@"r2"];

    NSError *error = nil;
    NSArray *results = [self.ctx executeFetchRequest:[self personFetchRequest]
                                               error:&error];
    XCTAssertEqual([results count], (NSUInteger)2);
    XCTAssertTrue(self.store.fetchRequestCount >= (NSUInteger)1);

    NSMutableSet *names = [NSMutableSet set];
    for (NSManagedObject *object in results) {
        XCTAssertEqualObjects([[object entity] name], @"Person");
        [names addObject:[object valueForKey:@"name"]];
    }
    XCTAssertEqualObjects(names,
        ([NSSet setWithObjects:@"Alice", @"Bob", nil]));
}

- (void)testFetchWithPredicate
{
    [self seedRow:[NSDictionary dictionaryWithObjectsAndKeys:
                      @"Alice", @"name",
                      [NSNumber numberWithInt:30], @"age", nil]
        forReference:@"r1"];
    [self seedRow:[NSDictionary dictionaryWithObjectsAndKeys:
                      @"Bob", @"name",
                      [NSNumber numberWithInt:40], @"age", nil]
        forReference:@"r2"];

    NSFetchRequest *fetch = [self personFetchRequest];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"name == %@", @"Alice"]];

    NSError *error = nil;
    NSArray *results = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertEqual([results count], (NSUInteger)1);
    XCTAssertEqualObjects([[results objectAtIndex:0] valueForKey:@"name"],
                          @"Alice");
}

- (void)testFetchWithSortDescriptors
{
    [self seedRow:[NSDictionary dictionaryWithObject:@"Bob" forKey:@"name"]
        forReference:@"r1"];
    [self seedRow:[NSDictionary dictionaryWithObject:@"Alice" forKey:@"name"]
        forReference:@"r2"];

    NSFetchRequest *fetch = [self personFetchRequest];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];

    NSError *error = nil;
    NSArray *results = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertEqual([results count], (NSUInteger)2);
    XCTAssertEqualObjects([[results objectAtIndex:0] valueForKey:@"name"],
                          @"Alice");
    XCTAssertEqualObjects([[results objectAtIndex:1] valueForKey:@"name"],
                          @"Bob");
}

- (void)testFaultingCallsNewValuesForObject
{
    [self seedRow:[NSDictionary dictionaryWithObjectsAndKeys:
                      @"Alice", @"name",
                      [NSNumber numberWithInt:30], @"age", nil]
        forReference:@"r1"];

    NSError *error = nil;
    NSArray *results = [self.ctx executeFetchRequest:[self personFetchRequest]
                                               error:&error];
    XCTAssertEqual([results count], (NSUInteger)1);

    NSManagedObject *person = [results objectAtIndex:0];
    XCTAssertEqualObjects([person valueForKey:@"name"], @"Alice");
    XCTAssertEqualObjects([person valueForKey:@"age"],
                          [NSNumber numberWithInt:30]);
    XCTAssertTrue(self.store.newValuesCallCount >= (NSUInteger)1);
}

/* -- saving ------------------------------------------------------------ */

- (void)testInsertAndSaveRoutesSaveChangesRequest
{
    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx];
    [person setValue:@"Alice" forKey:@"name"];
    [person setValue:[NSNumber numberWithInt:30] forKey:@"age"];
    XCTAssertTrue([[person objectID] isTemporaryID]);

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error]);

    XCTAssertEqual(self.store.saveRequestCount, (NSUInteger)1);
    XCTAssertEqual(self.store.lastInsertedCount, (NSUInteger)1);
    XCTAssertEqual(self.store.lastUpdatedCount, (NSUInteger)0);
    XCTAssertEqual(self.store.lastDeletedCount, (NSUInteger)0);
    XCTAssertTrue(self.store.obtainPermanentIDsCallCount >= (NSUInteger)1);
    XCTAssertFalse([[person objectID] isTemporaryID]);

    NSDictionary *table = [self.store.rows objectForKey:@"Person"];
    XCTAssertEqual([table count], (NSUInteger)1);
    NSDictionary *row = [[table allValues] objectAtIndex:0];
    XCTAssertEqualObjects([row objectForKey:@"name"], @"Alice");
}

- (void)testInsertedObjectCanBeFetchedBack
{
    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx];
    [person setValue:@"Alice" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error]);

    NSArray *results = [self.ctx executeFetchRequest:[self personFetchRequest]
                                               error:&error];
    XCTAssertEqual([results count], (NSUInteger)1);
    NSManagedObject *fetched = [results objectAtIndex:0];
    XCTAssertEqualObjects([fetched objectID], [person objectID]);
    XCTAssertEqualObjects([fetched valueForKey:@"name"], @"Alice");
}

- (void)testUpdateAndSave
{
    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx];
    [person setValue:@"Alice" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error]);

    [person setValue:@"Carol" forKey:@"name"];
    XCTAssertTrue([self.ctx save:&error]);

    XCTAssertEqual(self.store.saveRequestCount, (NSUInteger)2);
    XCTAssertEqual(self.store.lastUpdatedCount, (NSUInteger)1);
    XCTAssertEqual(self.store.lastInsertedCount, (NSUInteger)0);

    NSDictionary *table = [self.store.rows objectForKey:@"Person"];
    XCTAssertEqual([table count], (NSUInteger)1);
    NSDictionary *row = [[table allValues] objectAtIndex:0];
    XCTAssertEqualObjects([row objectForKey:@"name"], @"Carol");
}

- (void)testDeleteAndSave
{
    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx];
    [person setValue:@"Alice" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error]);

    [self.ctx deleteObject:person];
    XCTAssertTrue([self.ctx save:&error]);

    XCTAssertEqual(self.store.lastDeletedCount, (NSUInteger)1);
    XCTAssertEqual([[self.store.rows objectForKey:@"Person"] count],
                   (NSUInteger)0);

    NSArray *results = [self.ctx executeFetchRequest:[self personFetchRequest]
                                               error:&error];
    XCTAssertEqual([results count], (NSUInteger)0);
}

- (void)testSaveWithoutChangesSendsEmptySaveRequest
{
    /* Apple sends a save changes request to the store even when the
       context has no changes; the request's change sets are empty. */
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error]);
    XCTAssertEqual(self.store.saveRequestCount, (NSUInteger)1);
    XCTAssertEqual(self.store.lastInsertedCount, (NSUInteger)0);
    XCTAssertEqual(self.store.lastUpdatedCount, (NSUInteger)0);
    XCTAssertEqual(self.store.lastDeletedCount, (NSUInteger)0);
}

@end
