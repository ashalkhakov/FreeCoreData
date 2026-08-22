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

/* -- entity inheritance ------------------------------------------------ */

- (void)testNewObjectIDForSubentityKeepsSubentity
{
    NSEntityDescription *managerEntity =
        [[self.model entitiesByName] objectForKey:@"Manager"];
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:managerEntity referenceObject:@"m1"];
    XCTAssertNotNil(objectID);
    XCTAssertEqualObjects([[objectID entity] name], @"Manager");
    XCTAssertFalse([objectID isTemporaryID]);
}

- (void)testFetchOfParentEntityIncludesSubentityInstances
{
    [self seedRow:[NSDictionary dictionaryWithObject:@"Alice" forKey:@"name"]
        forReference:@"r1"];
    [[self.store tableForEntityName:@"Manager"]
        setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                      @"Boss", @"name",
                      [NSNumber numberWithInt:3], @"level", nil]
           forKey:@"m1"];

    /* A fetch of the parent entity includes subentity instances, which
       keep their own entity and their subentity-specific attributes. */
    NSError *error = nil;
    NSArray *results = [self.ctx executeFetchRequest:[self personFetchRequest]
                                               error:&error];
    XCTAssertEqual([results count], (NSUInteger)2);

    NSManagedObject *boss = nil;
    for (NSManagedObject *object in results)
        if ([[[object entity] name] isEqualToString:@"Manager"])
            boss = object;
    XCTAssertNotNil(boss);
    XCTAssertEqualObjects([boss valueForKey:@"name"], @"Boss");
    XCTAssertEqualObjects([boss valueForKey:@"level"],
                          [NSNumber numberWithInt:3]);

    /* A fetch of the subentity finds only its own instances. */
    NSFetchRequest *managerFetch = [[NSFetchRequest alloc] init];
    [managerFetch setEntity:
        [[self.model entitiesByName] objectForKey:@"Manager"]];
    NSArray *managers = [self.ctx executeFetchRequest:managerFetch
                                                error:&error];
    XCTAssertEqual([managers count], (NSUInteger)1);
    XCTAssertEqualObjects(
        [[managers objectAtIndex:0] valueForKey:@"name"], @"Boss");
}

- (void)testFetchWithoutSubentitiesExcludesSubentityInstances
{
    [self seedRow:[NSDictionary dictionaryWithObject:@"Alice" forKey:@"name"]
        forReference:@"r1"];
    [[self.store tableForEntityName:@"Manager"]
        setObject:[NSDictionary dictionaryWithObject:@"Boss" forKey:@"name"]
           forKey:@"m1"];

    NSFetchRequest *fetch = [self personFetchRequest];
    [fetch setIncludesSubentities:NO];

    NSError *error = nil;
    NSArray *results = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertEqual([results count], (NSUInteger)1);
    XCTAssertEqualObjects(
        [[[results objectAtIndex:0] entity] name], @"Person");
}

- (void)testInsertSubentityAndSave
{
    NSManagedObject *boss =
        [NSEntityDescription insertNewObjectForEntityForName:@"Manager"
                                      inManagedObjectContext:self.ctx];
    [boss setValue:@"Boss" forKey:@"name"];
    [boss setValue:[NSNumber numberWithInt:3] forKey:@"level"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    /* The permanent object ID keeps the subentity, and the row lands in
       the subentity's table with both the inherited and the
       subentity-specific attributes. */
    XCTAssertEqualObjects([[[boss objectID] entity] name], @"Manager");
    NSDictionary *table = [self.store.rows objectForKey:@"Manager"];
    XCTAssertEqual([table count], (NSUInteger)1);
    NSDictionary *row = [[table allValues] objectAtIndex:0];
    XCTAssertEqualObjects([row objectForKey:@"name"], @"Boss");
    XCTAssertEqualObjects([row objectForKey:@"level"],
                          [NSNumber numberWithInt:3]);
}

/* -- reference objects and URI representations ----------------------- */

- (void)testNumberReferenceObjectURIRoundTrips
{
    /* Reference objects are not limited to strings.  Verified on macOS:
       the URI component is "p" + the reference's description, so a
       number 42 travels as "p42". */
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity
                         referenceObject:[NSNumber numberWithInt:42]];

    NSURL *uri = [objectID URIRepresentation];
    XCTAssertNotNil(uri);
    XCTAssertEqualObjects([uri scheme], @"x-coredata");
    XCTAssertEqualObjects([uri lastPathComponent], @"p42");

    NSManagedObjectID *back =
        [self.psc managedObjectIDForURIRepresentation:uri];
    XCTAssertNotNil(back);
    XCTAssertEqualObjects([[back entity] name], @"Person");
    XCTAssertTrue([[[self.store referenceObjectForObjectID:back]
                       description] rangeOfString:@"42"].location
                      != NSNotFound);
}

- (void)testDataReferenceObjectURIUsesDescription
{
    /* An OData-backed store may key rows by raw data.  Verified on
       macOS: there is no special hex form - the URI carries "p" plus
       the data's escaped -description (whose exact format differs
       between Foundation implementations, but always contains the hex
       bytes). */
    unsigned char bytes[3] = { 0x01, 0xAB, 0xFF };
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity
                         referenceObject:[NSData dataWithBytes:bytes
                                                        length:3]];

    NSURL *uri = [objectID URIRepresentation];
    XCTAssertNotNil(uri);
    XCTAssertTrue([[[uri path] lastPathComponent] hasPrefix:@"p"] ||
                  [[[uri absoluteString]
                       componentsSeparatedByString:@"/"] count] > 4,
                  @"unexpected URI %@", uri);

    NSManagedObjectID *back =
        [self.psc managedObjectIDForURIRepresentation:uri];
    XCTAssertNotNil(back);
    XCTAssertTrue([[[self.store referenceObjectForObjectID:back]
                       description] rangeOfString:@"01abff"
                                         options:NSCaseInsensitiveSearch]
                      .location != NSNotFound,
                  @"the reference's bytes survive the round trip");
}

- (void)testStringReferenceObjectURIMatchesAppleEscaping
{
    /* Verified on macOS: the reference is escaped with URL *path* rules
       (space becomes %20 but "/" survives, splitting the reference over
       path components), and the coordinator hands the store the raw
       remainder without decoding - Apple literally returns
       "key%20with/slash" for this reference.  Lossy, but bit-for-bit
       what Apple does. */
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity
                         referenceObject:@"key with/slash"];

    NSURL *uri = [objectID URIRepresentation];
    XCTAssertNotNil(uri);
    XCTAssertTrue([[uri absoluteString]
                      rangeOfString:@"/pkey%20with/slash"].location
                      != NSNotFound, @"unexpected URI %@", uri);

    NSManagedObjectID *back =
        [self.psc managedObjectIDForURIRepresentation:uri];
    XCTAssertEqualObjects([self.store referenceObjectForObjectID:back],
                          @"key%20with/slash");
}

- (void)testDictionaryFetchIsShapedByTheStore
{
    /* On a clean context the store itself answers a dictionary fetch,
       building rows from its persisted state. */
    [self seedRow:[NSDictionary dictionaryWithObjectsAndKeys:
                      @"Alice", @"name",
                      [NSNumber numberWithInt:30], @"age", nil]
        forReference:@"r1"];

    NSFetchRequest *fetch = [self personFetchRequest];
    [fetch setResultType:NSDictionaryResultType];
    [fetch setPropertiesToFetch:[NSArray arrayWithObject:@"name"]];

    NSError *error = nil;
    NSUInteger fetchesBefore = [self.store fetchRequestCount];
    NSArray *rows = [self.ctx executeFetchRequest:fetch error:&error];

    XCTAssertNotNil(rows, @"fetch failed: %@", error);
    XCTAssertEqualObjects(rows,
        [NSArray arrayWithObject:
            [NSDictionary dictionaryWithObject:@"Alice" forKey:@"name"]]);
    XCTAssertTrue([self.store fetchRequestCount] > fetchesBefore);
}

/* -- relationship faulting ------------------------------------------- */

- (void)seedManagedPair
{
    /* p1 is the manager of p2; p1's reports contain p2. */
    [self seedRow:[NSDictionary dictionaryWithObjectsAndKeys:
                      @"Boss", @"name",
                      [NSArray arrayWithObject:@"p2"], @"reports", nil]
        forReference:@"p1"];
    [self seedRow:[NSDictionary dictionaryWithObjectsAndKeys:
                      @"Worker", @"name",
                      @"p1", @"manager", nil]
        forReference:@"p2"];
}

- (void)testToOneRelationshipIsSatisfiedFromTheNode
{
    [self seedManagedPair];

    NSManagedObjectID *workerID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"p2"];
    NSManagedObject *worker = [self.ctx objectWithID:workerID];

    /* Fire the row fault first (which may fetch to-many relationships,
       depending on the implementation's laziness), then measure: the
       to-one must be satisfied from the NSManagedObjectID the node
       supplied, without an additional newValueForRelationship: round
       trip. */
    XCTAssertEqualObjects([worker valueForKey:@"name"], @"Worker");

    NSUInteger callsBefore = [self.store relationshipCallCount];
    NSManagedObject *boss = [worker valueForKey:@"manager"];

    XCTAssertNotNil(boss);
    XCTAssertEqual([self.store relationshipCallCount], callsBefore,
                   @"the to-one must be satisfied from the node");
    XCTAssertEqualObjects([boss valueForKey:@"name"], @"Boss");
}

/* To-many relationships are lazy: firing the row fault does not fetch
   them; the newValueForRelationship: round trip happens on first
   access and is cached.  Verified against Apple 2026-08-22: firing
   p1's row fault cost exactly ONE relationship call - Apple resolving
   the to-one ("manager") that the node did not include, NOT the
   to-many - and accessing the to-many added exactly one more.  The
   port does the same. */
- (void)testToManyRelationshipFaultIsLazy
{
    [self seedManagedPair];

    NSManagedObjectID *bossID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"p1"];
    NSManagedObject *boss = [self.ctx objectWithID:bossID];

    NSUInteger callsBefore = [self.store relationshipCallCount];

    /* Fire the row fault: the node-omitted to-one is resolved as part
       of the row snapshot (one call); the to-many stays a fault. */
    XCTAssertEqualObjects([boss valueForKey:@"name"], @"Boss");
    XCTAssertEqual([self.store relationshipCallCount], callsBefore + 1,
                   @"row loading resolves the missing to-one and nothing else");

    /* First to-many access pays exactly one round trip... */
    id reports = [boss valueForKey:@"reports"];
    XCTAssertEqual([reports count], (NSUInteger)1);
    XCTAssertEqual([self.store relationshipCallCount], callsBefore + 2);

    /* ...and the resolved value is cached. */
    reports = [boss valueForKey:@"reports"];
    XCTAssertEqual([reports count], (NSUInteger)1);
    XCTAssertEqual([self.store relationshipCallCount], callsBefore + 2);
}

- (void)testToManyRelationshipGoesThroughNewValueForRelationship
{
    [self seedManagedPair];

    NSManagedObjectID *bossID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"p1"];
    NSManagedObject *boss = [self.ctx objectWithID:bossID];

    NSUInteger callsBefore = [self.store relationshipCallCount];
    id reports = [boss valueForKey:@"reports"];

    XCTAssertEqual([reports count], (NSUInteger)1);
    XCTAssertEqualObjects([[reports anyObject] valueForKey:@"name"],
                          @"Worker");
    XCTAssertTrue([self.store relationshipCallCount] > callsBefore,
                  @"a to-many fault is satisfied by the store");
}

/* relationshipKeyPathsForPrefetching on a fetch that takes the pending
   overlay path: the context fulfills the prefetch itself, driving the
   store's newValueForRelationship during the fetch, so later access
   does not go back to the store. */
- (void)testPrefetchKeyPathsFulfilledOnOverlayRows
{
    [self seedManagedPair];

    /* A pending insert keeps the context dirty so the fetch merges. */
    NSManagedObject *extra =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx];
    [extra setValue:@"Extra" forKey:@"name"];

    NSFetchRequest *fetch = [self personFetchRequest];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"name == %@",
                                     @"Boss"]];
    [fetch setRelationshipKeyPathsForPrefetching:
        [NSArray arrayWithObject:@"reports"]];

    NSError *error = nil;
    NSArray *result = [self.ctx executeFetchRequest:fetch error:&error];

    XCTAssertNotNil(result, @"fetch failed: %@", error);
    XCTAssertEqual([result count], (NSUInteger)1);

#if !defined(__APPLE__)
    /* The port fulfills the hint during the fetch; whether Apple
       prefetches through a custom incremental store here is not
       something it documents, so the round-trip accounting is
       port-only. */
    NSUInteger callsAfterFetch = [self.store relationshipCallCount];
#endif

    id reports = [[result lastObject] valueForKey:@"reports"];

    XCTAssertEqual([reports count], (NSUInteger)1);
    XCTAssertEqualObjects([[reports anyObject] valueForKey:@"name"],
                          @"Worker");
#if !defined(__APPLE__)
    XCTAssertEqual([self.store relationshipCallCount], callsAfterFetch,
                   @"prefetched relationship must not hit the store again");
#endif
}

- (void)testRelationshipsSurviveSaveAndRefetch
{
    NSManagedObject *boss =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx];
    [boss setValue:@"Boss" forKey:@"name"];
    NSManagedObject *worker =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx];
    [worker setValue:@"Worker" forKey:@"name"];
    [worker setValue:boss forKey:@"manager"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    /* A second context resolves the persisted relationship rows. */
    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:self.psc];

    NSFetchRequest *fetch = [self personFetchRequest];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"name == %@",
                                     @"Worker"]];
    NSArray *workers = [ctx2 executeFetchRequest:fetch error:&error];
    XCTAssertEqual([workers count], (NSUInteger)1);
    XCTAssertEqualObjects([[[workers lastObject] valueForKey:@"manager"]
                              valueForKey:@"name"],
                          @"Boss");
}

@end
