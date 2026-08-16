/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* CoreDataTests.m - Basic CoreData runtime tests.
   Compiled with ARC (-fobjc-arc).
   Runs via GNUstep's xctest(1) runner on Linux and via Xcode on macOS.
   On both platforms the real XCTest framework is used — no custom shim. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

/* ------------------------------------------------------------------ */
#pragma mark - NSManagedObjectModelTests
/* ------------------------------------------------------------------ */

@interface NSManagedObjectModelTests : XCTestCase
@end

@implementation NSManagedObjectModelTests

- (void)testModelCreation
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    XCTAssertNotNil(model);
    XCTAssertNotNil([model entities]);
}

- (void)testModelMergeEmpty
{
    NSManagedObjectModel *model =
        [NSManagedObjectModel modelByMergingModels:[NSArray array]];
    XCTAssertNotNil(model);
    XCTAssertEqual([[model entities] count], (NSUInteger)0);
}

- (void)testFetchRequestTemplate
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:@"MyEntity"];
    [model setEntities:[NSArray arrayWithObject:entity]];
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setEntity:entity];
    [model setFetchRequestTemplate:req forName:@"myTemplate"];
    XCTAssertEqualObjects([model fetchRequestTemplateForName:@"myTemplate"], req);
}

- (void)testConfigurations
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    XCTAssertNotNil([model configurations]);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSFetchRequestTests
/* ------------------------------------------------------------------ */

@interface NSFetchRequestTests : XCTestCase
@end

@implementation NSFetchRequestTests

- (void)testDefaults
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    XCTAssertNil([req entity]);
    XCTAssertNil([req predicate]);
    XCTAssertEqual([req fetchLimit], (NSUInteger)0);
}

- (void)testSettersGetters
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setFetchLimit:42];
    XCTAssertEqual([req fetchLimit], (NSUInteger)42);
    [req setFetchOffset:10];
    XCTAssertEqual([req fetchOffset], (NSUInteger)10);
}

- (void)testCopy
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setFetchLimit:7];
    NSFetchRequest *copy = [req copy];
    XCTAssertNotNil(copy);
    XCTAssertEqual([copy fetchLimit], (NSUInteger)7);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSPersistentStoreCoordinatorTests
/* ------------------------------------------------------------------ */

@interface NSPersistentStoreCoordinatorTests : XCTestCase
@end

@implementation NSPersistentStoreCoordinatorTests

- (void)testRegisteredStoreTypes
{
    NSDictionary *types = [NSPersistentStoreCoordinator registeredStoreTypes];
    XCTAssertNotNil(types);
    XCTAssertNotNil([types objectForKey:NSInMemoryStoreType]);
    XCTAssertNotNil([types objectForKey:NSXMLStoreType]);
}

- (void)testInMemoryStore
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    NSPersistentStoreCoordinator *psc =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    XCTAssertNotNil(psc);

    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store);
    XCTAssertNil(error);
    XCTAssertEqual([[psc persistentStores] count], (NSUInteger)1);
}

- (void)testRemoveStore
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    NSPersistentStoreCoordinator *psc =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];

    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store);
    BOOL removed = [psc removePersistentStore:store error:&error];
    XCTAssertTrue(removed);
    XCTAssertEqual([[psc persistentStores] count], (NSUInteger)0);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSManagedObjectContextTests
/* ------------------------------------------------------------------ */

@interface NSManagedObjectContextTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSManagedObjectContext *ctx;

@end

@implementation NSManagedObjectContextTests

- (void)setUp
{
    self.model = [[NSManagedObjectModel alloc] init];
    self.psc   = [[NSPersistentStoreCoordinator alloc]
                     initWithManagedObjectModel:self.model];
    NSError *err = nil;
    [self.psc addPersistentStoreWithType:NSInMemoryStoreType
                           configuration:nil URL:nil options:nil error:&err];
    self.ctx = [[NSManagedObjectContext alloc] init];
    [self.ctx setPersistentStoreCoordinator:self.psc];
}

- (void)tearDown
{
    self.ctx   = nil;
    self.psc   = nil;
    self.model = nil;
}

- (void)testContextCreation
{
    XCTAssertNotNil(self.ctx);
    XCTAssertNotNil([self.ctx persistentStoreCoordinator]);
    XCTAssertFalse([self.ctx hasChanges]);
}

- (void)testRegisteredObjects
{
    XCTAssertNotNil([self.ctx registeredObjects]);
    XCTAssertEqual([[self.ctx registeredObjects] count], (NSUInteger)0);
}

- (void)testSaveWithNoChanges
{
    NSError *err = nil;
    BOOL ok = [self.ctx save:&err];
    XCTAssertTrue(ok);
    XCTAssertNil(err);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - MemoryIncrementalStore (NSIncrementalStore test subclass)
/* ------------------------------------------------------------------ */

/* A minimal in-memory NSIncrementalStore subclass implementing the
   documented NSIncrementalStore contract.  It is deliberately written
   against Apple's official documentation so that the test cases below run
   identically against Apple's CoreData on macOS and against the GNUstep
   port.  Rows are kept as: entity name -> (reference object -> attribute
   values dictionary). */

static NSString * const MemoryIncrementalStoreType = @"MemoryIncrementalStoreType";

@interface MemoryIncrementalStore : NSIncrementalStore

@property (nonatomic, strong) NSMutableDictionary *rows;

@property (nonatomic) NSUInteger loadMetadataCallCount;
@property (nonatomic) NSUInteger fetchRequestCount;
@property (nonatomic) NSUInteger saveRequestCount;
@property (nonatomic) NSUInteger newValuesCallCount;
@property (nonatomic) NSUInteger obtainPermanentIDsCallCount;
@property (nonatomic) NSUInteger lastInsertedCount;
@property (nonatomic) NSUInteger lastUpdatedCount;
@property (nonatomic) NSUInteger lastDeletedCount;
@property (nonatomic) long long nextReferenceNumber;

- (NSMutableDictionary *)tableForEntityName:(NSString *)entityName;

@end

@implementation MemoryIncrementalStore

- (NSMutableDictionary *)tableForEntityName:(NSString *)entityName
{
    NSMutableDictionary *table = [self.rows objectForKey:entityName];
    if (table == nil) {
        table = [NSMutableDictionary dictionary];
        [self.rows setObject:table forKey:entityName];
    }
    return table;
}

- (BOOL)loadMetadata:(NSError **)error
{
    self.loadMetadataCallCount++;
    if (self.rows == nil)
        self.rows = [NSMutableDictionary dictionary];
    NSString *uuid = [[NSProcessInfo processInfo] globallyUniqueString];
    [self setMetadata:[NSDictionary dictionaryWithObjectsAndKeys:
                          MemoryIncrementalStoreType, NSStoreTypeKey,
                          uuid, NSStoreUUIDKey, nil]];
    return YES;
}

- (void)writeRowForObject:(NSManagedObject *)object
{
    id ref = [self referenceObjectForObjectID:[object objectID]];
    NSMutableDictionary *table = [self tableForEntityName:[[object entity] name]];
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    for (NSString *key in [[object entity] attributesByName]) {
        id value = [object valueForKey:key];
        if (value != nil)
            [row setObject:value forKey:key];
    }
    [table setObject:row forKey:ref];
}

- (id)executeRequest:(NSPersistentStoreRequest *)request
         withContext:(NSManagedObjectContext *)context
               error:(NSError **)error
{
    if ([request requestType] == NSFetchRequestType) {
        self.fetchRequestCount++;
        NSFetchRequest *fetch = (NSFetchRequest *)request;
        NSEntityDescription *entity = [fetch entity];
        NSMutableArray *results = [NSMutableArray array];
        NSDictionary *table = [self.rows objectForKey:[entity name]];
        for (id ref in table) {
            NSManagedObjectID *objectID =
                [self newObjectIDForEntity:entity referenceObject:ref];
            [results addObject:[context objectWithID:objectID]];
        }
        if ([fetch predicate] != nil)
            [results filterUsingPredicate:[fetch predicate]];
        if ([[fetch sortDescriptors] count] > 0)
            [results sortUsingDescriptors:[fetch sortDescriptors]];
        return results;
    }

    if ([request requestType] == NSSaveRequestType) {
        self.saveRequestCount++;
        NSSaveChangesRequest *save = (NSSaveChangesRequest *)request;
        self.lastInsertedCount = [[save insertedObjects] count];
        self.lastUpdatedCount = [[save updatedObjects] count];
        self.lastDeletedCount = [[save deletedObjects] count];
        for (NSManagedObject *object in [save insertedObjects])
            [self writeRowForObject:object];
        for (NSManagedObject *object in [save updatedObjects])
            [self writeRowForObject:object];
        for (NSManagedObject *object in [save deletedObjects]) {
            id ref = [self referenceObjectForObjectID:[object objectID]];
            [[self tableForEntityName:[[object entity] name]] removeObjectForKey:ref];
        }
        return [NSArray array];
    }

    return nil;
}

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                         withContext:(NSManagedObjectContext *)context
                                               error:(NSError **)error
{
    self.newValuesCallCount++;
    id ref = [self referenceObjectForObjectID:objectID];
    NSDictionary *row = [[self.rows objectForKey:[[objectID entity] name]] objectForKey:ref];
    if (row == nil) {
        if (error != NULL)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:133000
                                     userInfo:nil];
        return nil;
    }
    return [[NSIncrementalStoreNode alloc] initWithObjectID:objectID
                                                 withValues:row
                                                    version:1];
}

- (id)newValueForRelationship:(NSRelationshipDescription *)relationship
              forObjectWithID:(NSManagedObjectID *)objectID
                  withContext:(NSManagedObjectContext *)context
                        error:(NSError **)error
{
    return [NSArray array];
}

- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)error
{
    self.obtainPermanentIDsCallCount++;
    NSMutableArray *result = [NSMutableArray array];
    for (NSManagedObject *object in array) {
        self.nextReferenceNumber++;
        NSString *ref =
            [NSString stringWithFormat:@"ref-%lld", self.nextReferenceNumber];
        [result addObject:[self newObjectIDForEntity:[object entity]
                                     referenceObject:ref]];
    }
    return result;
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - Incremental store test helpers
/* ------------------------------------------------------------------ */

static NSManagedObjectModel *IncrementalStoreTestModel(void)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];

    NSAttributeDescription *age = [[NSAttributeDescription alloc] init];
    [age setName:@"age"];
    [age setAttributeType:NSInteger32AttributeType];

    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:@"Person"];
    [entity setManagedObjectClassName:@"NSManagedObject"];
    [entity setProperties:[NSArray arrayWithObjects:name, age, nil]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:entity]];
    return model;
}

/* ------------------------------------------------------------------ */
#pragma mark - NSPersistentStoreRequestTests
/* ------------------------------------------------------------------ */

@interface NSPersistentStoreRequestTests : XCTestCase
@end

@implementation NSPersistentStoreRequestTests

- (void)testFetchRequestIsAPersistentStoreRequest
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    XCTAssertTrue([fetch isKindOfClass:[NSPersistentStoreRequest class]]);
    XCTAssertEqual([fetch requestType],
                   (NSPersistentStoreRequestType)NSFetchRequestType);
}

- (void)testSaveChangesRequestType
{
    NSSaveChangesRequest *save =
        [[NSSaveChangesRequest alloc] initWithInsertedObjects:nil
                                               updatedObjects:nil
                                               deletedObjects:nil
                                                lockedObjects:nil];
    XCTAssertTrue([save isKindOfClass:[NSPersistentStoreRequest class]]);
    XCTAssertEqual([save requestType],
                   (NSPersistentStoreRequestType)NSSaveRequestType);
}

- (void)testSaveChangesRequestAccessors
{
    NSManagedObjectModel *model = IncrementalStoreTestModel();
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    [psc addPersistentStoreWithType:NSInMemoryStoreType
                      configuration:nil URL:nil options:nil error:&error];
    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:ctx];
    NSSet *inserted = [NSSet setWithObject:person];

    NSSaveChangesRequest *save =
        [[NSSaveChangesRequest alloc] initWithInsertedObjects:inserted
                                               updatedObjects:[NSSet set]
                                               deletedObjects:[NSSet set]
                                                lockedObjects:nil];
    XCTAssertEqualObjects([save insertedObjects], inserted);
    XCTAssertEqual([[save updatedObjects] count], (NSUInteger)0);
    XCTAssertEqual([[save deletedObjects] count], (NSUInteger)0);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSIncrementalStoreNodeTests
/* ------------------------------------------------------------------ */

@interface NSIncrementalStoreNodeTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) MemoryIncrementalStore *store;
@property (nonatomic, strong) NSEntityDescription *entity;

@end

@implementation NSIncrementalStoreNodeTests

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
    self.entity = [[self.model entitiesByName] objectForKey:@"Person"];
}

- (void)tearDown
{
    self.store = nil;
    self.psc = nil;
    self.model = nil;
    self.entity = nil;
}

- (NSIncrementalStoreNode *)nodeWithValues:(NSDictionary *)values version:(uint64_t)version
{
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"node-ref"];
    return [[NSIncrementalStoreNode alloc] initWithObjectID:objectID
                                                 withValues:values
                                                    version:version];
}

- (void)testNodeStoresObjectIDAndVersion
{
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"node-ref"];
    NSIncrementalStoreNode *node = [[NSIncrementalStoreNode alloc]
        initWithObjectID:objectID
              withValues:[NSDictionary dictionaryWithObject:@"Bob" forKey:@"name"]
                 version:7];
    XCTAssertEqualObjects([node objectID], objectID);
    XCTAssertEqual([node version], (uint64_t)7);
}

- (void)testNodeValueForPropertyDescription
{
    NSIncrementalStoreNode *node =
        [self nodeWithValues:[NSDictionary dictionaryWithObjectsAndKeys:
                                 @"Bob", @"name",
                                 [NSNumber numberWithInt:30], @"age", nil]
                     version:1];
    NSPropertyDescription *nameProperty =
        [[self.entity attributesByName] objectForKey:@"name"];
    NSPropertyDescription *ageProperty =
        [[self.entity attributesByName] objectForKey:@"age"];
    XCTAssertEqualObjects([node valueForPropertyDescription:nameProperty], @"Bob");
    XCTAssertEqualObjects([node valueForPropertyDescription:ageProperty],
                          [NSNumber numberWithInt:30]);
}

- (void)testNodeUpdateWithValues
{
    NSIncrementalStoreNode *node =
        [self nodeWithValues:[NSDictionary dictionaryWithObjectsAndKeys:
                                 @"Bob", @"name",
                                 [NSNumber numberWithInt:30], @"age", nil]
                     version:1];
    [node updateWithValues:[NSDictionary dictionaryWithObjectsAndKeys:
                               @"Carol", @"name",
                               [NSNumber numberWithInt:31], @"age", nil]
                   version:2];
    NSPropertyDescription *nameProperty =
        [[self.entity attributesByName] objectForKey:@"name"];
    XCTAssertEqualObjects([node valueForPropertyDescription:nameProperty], @"Carol");
    XCTAssertEqual([node version], (uint64_t)2);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSIncrementalStoreTests
/* ------------------------------------------------------------------ */

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

- (void)testSaveWithoutChangesDoesNotCallStore
{
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error]);
    XCTAssertEqual(self.store.saveRequestCount, (NSUInteger)0);
}

@end
