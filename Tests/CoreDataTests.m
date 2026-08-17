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

/* Apple's -[NSPersistentStoreCoordinator addPersistentStoreWithType:...]
   verifies that the store's `type` matches the requested store type after
   -loadMetadata: returns; without these overrides it fails with
   NSPersistentStoreTypeMismatchError (134010) on macOS.  Apple's instance
   -type delegates to the +type class method, so both are provided. */
+ (NSString *)type
{
    return MemoryIncrementalStoreType;
}

- (NSString *)type
{
    return MemoryIncrementalStoreType;
}

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

/* An incremental store registered under one type whose -type reports
   another; adding it must fail with NSPersistentStoreTypeMismatchError
   (134010), mirroring Apple. */
static NSString * const MismatchIncrementalStoreType = @"MismatchIncrementalStoreType";

@interface MismatchIncrementalStore : MemoryIncrementalStore
@end

@implementation MismatchIncrementalStore
@end

/* ------------------------------------------------------------------ */
#pragma mark - NSPersistentStoreCoordinatorTypeMismatchTests
/* ------------------------------------------------------------------ */

@interface NSPersistentStoreCoordinatorTypeMismatchTests : XCTestCase
@end

@implementation NSPersistentStoreCoordinatorTypeMismatchTests

- (void)testAddStoreWithMismatchedTypeFails
{
    [NSPersistentStoreCoordinator registerStoreClass:[MismatchIncrementalStore class]
                                        forStoreType:MismatchIncrementalStoreType];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:IncrementalStoreTestModel()];
    NSURL *url = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [[NSProcessInfo processInfo] globallyUniqueString]]];

    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:MismatchIncrementalStoreType
                          configuration:nil
                                    URL:url
                                options:nil
                                  error:&error];
    XCTAssertNil(store);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([error domain], NSCocoaErrorDomain);
    XCTAssertEqual([error code], (NSInteger)NSPersistentStoreTypeMismatchError);
    XCTAssertEqual([[psc persistentStores] count], (NSUInteger)0);
}

@end

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

/* ------------------------------------------------------------------ */
#pragma mark - NSXMLPersistentStore roundtrip test helpers
/* ------------------------------------------------------------------ */

/* Employee <->> Department model built in code so the tests run
   identically against Apple's CoreData on macOS and the GNUstep port. */
static NSManagedObjectModel *XMLStoreTestModel(void)
{
    NSAttributeDescription *employeeName = [[NSAttributeDescription alloc] init];
    [employeeName setName:@"name"];
    [employeeName setAttributeType:NSStringAttributeType];
    [employeeName setOptional:YES];

    NSAttributeDescription *salary = [[NSAttributeDescription alloc] init];
    [salary setName:@"salary"];
    [salary setAttributeType:NSInteger32AttributeType];
    [salary setOptional:YES];

    NSAttributeDescription *hireDate = [[NSAttributeDescription alloc] init];
    [hireDate setName:@"hireDate"];
    [hireDate setAttributeType:NSDateAttributeType];
    [hireDate setOptional:YES];

    NSAttributeDescription *departmentName = [[NSAttributeDescription alloc] init];
    [departmentName setName:@"name"];
    [departmentName setAttributeType:NSStringAttributeType];
    [departmentName setOptional:YES];

    NSRelationshipDescription *department = [[NSRelationshipDescription alloc] init];
    [department setName:@"department"];
    [department setMinCount:1];
    [department setMaxCount:1];
    [department setOptional:YES];

    NSRelationshipDescription *employees = [[NSRelationshipDescription alloc] init];
    [employees setName:@"employees"];
    [employees setMinCount:0];
    [employees setMaxCount:0];
    [employees setOptional:YES];

    NSEntityDescription *employeeEntity = [[NSEntityDescription alloc] init];
    [employeeEntity setName:@"Employee"];
    [employeeEntity setManagedObjectClassName:@"NSManagedObject"];
    [employeeEntity setProperties:
        [NSArray arrayWithObjects:employeeName, salary, hireDate, department, nil]];

    NSEntityDescription *departmentEntity = [[NSEntityDescription alloc] init];
    [departmentEntity setName:@"Department"];
    [departmentEntity setManagedObjectClassName:@"NSManagedObject"];
    [departmentEntity setProperties:
        [NSArray arrayWithObjects:departmentName, employees, nil]];

    [department setDestinationEntity:departmentEntity];
    [employees setDestinationEntity:employeeEntity];
    [department setInverseRelationship:employees];
    [employees setInverseRelationship:department];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:
        [NSArray arrayWithObjects:employeeEntity, departmentEntity, nil]];
    return model;
}

/* ------------------------------------------------------------------ */
#pragma mark - NSXMLPersistentStoreTests
/* ------------------------------------------------------------------ */

@interface NSXMLPersistentStoreTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;

@end

@implementation NSXMLPersistentStoreTests

- (void)setUp
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"xml"];
    self.storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.storeURL error:NULL];
    self.storeURL = nil;
}

/* Builds a fresh coordinator + context stack on top of the XML store at
   `storeURL`, simulating an independent application run. */
- (NSManagedObjectContext *)contextWithModel:(NSManagedObjectModel *)model
                                     options:(NSDictionary *)options
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSXMLStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:options
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to open XML store: %@", error);
    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

- (NSManagedObjectContext *)contextWithModel:(NSManagedObjectModel *)model
{
    return [self contextWithModel:model options:nil];
}

- (NSArray *)fetchEntityNamed:(NSString *)entityName
                    inContext:(NSManagedObjectContext *)ctx
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[[[ctx persistentStoreCoordinator] managedObjectModel]
                          entitiesByName] objectForKey:entityName]];
    NSError *error = nil;
    NSArray *results = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(results, @"fetch failed: %@", error);
    return results;
}

/* -- attribute roundtrip --------------------------------------------- */

- (void)testAttributeRoundtrip
{
    NSDate *hireDate = [NSDate dateWithTimeIntervalSinceReferenceDate:445103622.25];

    /* First run: create the store and save one Employee. */
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    [alice setValue:[NSNumber numberWithInt:42] forKey:@"salary"];
    [alice setValue:hireDate forKey:@"hireDate"];

    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);
    XCTAssertTrue([[NSFileManager defaultManager]
                      fileExistsAtPath:[self.storeURL path]]);

    /* Second run: reopen the file with a completely fresh stack. */
    NSManagedObjectContext *ctx2 = [self contextWithModel:XMLStoreTestModel()];
    NSArray *employees = [self fetchEntityNamed:@"Employee" inContext:ctx2];
    XCTAssertEqual([employees count], (NSUInteger)1);

    NSManagedObject *reloaded = [employees objectAtIndex:0];
    XCTAssertEqualObjects([reloaded valueForKey:@"name"], @"Alice");
    XCTAssertEqual([[reloaded valueForKey:@"salary"] intValue], 42);

    NSDate *reloadedDate = [reloaded valueForKey:@"hireDate"];
    XCTAssertNotNil(reloadedDate);
    XCTAssertEqualWithAccuracy([reloadedDate timeIntervalSinceReferenceDate],
                               [hireDate timeIntervalSinceReferenceDate],
                               0.001);
}

- (void)testNilAttributeRoundtrip
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *bob =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [bob setValue:@"Bob" forKey:@"name"];
    /* salary and hireDate deliberately left nil. */

    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:XMLStoreTestModel()];
    NSArray *employees = [self fetchEntityNamed:@"Employee" inContext:ctx2];
    XCTAssertEqual([employees count], (NSUInteger)1);
    NSManagedObject *reloaded = [employees objectAtIndex:0];
    XCTAssertEqualObjects([reloaded valueForKey:@"name"], @"Bob");
    XCTAssertNil([reloaded valueForKey:@"hireDate"]);
}

/* -- relationship roundtrip ------------------------------------------ */

- (void)testRelationshipRoundtrip
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *engineering =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:ctx1];
    [engineering setValue:@"Engineering" forKey:@"name"];

    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    NSManagedObject *bob =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [bob setValue:@"Bob" forKey:@"name"];

    /* Set both sides of the relationship explicitly so the test does not
       depend on automatic inverse maintenance. */
    [alice setValue:engineering forKey:@"department"];
    [bob setValue:engineering forKey:@"department"];
    [engineering setValue:[NSSet setWithObjects:alice, bob, nil]
                   forKey:@"employees"];

    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:XMLStoreTestModel()];
    NSArray *departments = [self fetchEntityNamed:@"Department" inContext:ctx2];
    XCTAssertEqual([departments count], (NSUInteger)1);

    NSManagedObject *reloadedDept = [departments objectAtIndex:0];
    XCTAssertEqualObjects([reloadedDept valueForKey:@"name"], @"Engineering");

    NSSet *reloadedEmployees = [reloadedDept valueForKey:@"employees"];
    XCTAssertEqual([reloadedEmployees count], (NSUInteger)2);
    NSSet *names = [NSSet setWithArray:
        [[reloadedEmployees allObjects] valueForKey:@"name"]];
    XCTAssertEqualObjects(names,
        ([NSSet setWithObjects:@"Alice", @"Bob", nil]));

    for (NSManagedObject *employee in reloadedEmployees) {
        NSManagedObject *dept = [employee valueForKey:@"department"];
        XCTAssertEqualObjects([dept valueForKey:@"name"], @"Engineering");
    }
}

/* -- update and delete roundtrip -------------------------------------- */

- (void)testUpdateAndDeleteRoundtrip
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    [alice setValue:[NSNumber numberWithInt:42] forKey:@"salary"];
    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    /* Update in a second run. */
    NSManagedObjectContext *ctx2 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *reloaded =
        [[self fetchEntityNamed:@"Employee" inContext:ctx2] objectAtIndex:0];
    [reloaded setValue:[NSNumber numberWithInt:100] forKey:@"salary"];
    XCTAssertTrue([ctx2 save:&error], @"save failed: %@", error);

    /* Verify the update, then delete, in a third run. */
    NSManagedObjectContext *ctx3 = [self contextWithModel:XMLStoreTestModel()];
    NSArray *employees = [self fetchEntityNamed:@"Employee" inContext:ctx3];
    XCTAssertEqual([employees count], (NSUInteger)1);
    XCTAssertEqual(
        [[[employees objectAtIndex:0] valueForKey:@"salary"] intValue], 100);
    [ctx3 deleteObject:[employees objectAtIndex:0]];
    XCTAssertTrue([ctx3 save:&error], @"save failed: %@", error);

    /* Fourth run: the store is empty. */
    NSManagedObjectContext *ctx4 = [self contextWithModel:XMLStoreTestModel()];
    XCTAssertEqual([[self fetchEntityNamed:@"Employee" inContext:ctx4] count],
                   (NSUInteger)0);
}

/* -- store metadata ---------------------------------------------------- */

- (void)testMetadataRoundtrip
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    NSPersistentStore *store = [[[[ctx1 persistentStoreCoordinator]
        persistentStores] objectAtIndex:0] self];

    NSDictionary *metadata = [NSPersistentStoreCoordinator
        metadataForPersistentStoreOfType:NSXMLStoreType
                                     URL:self.storeURL
                                   error:&error];
    XCTAssertNotNil(metadata, @"metadata read failed: %@", error);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreTypeKey],
                          NSXMLStoreType);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreUUIDKey],
                          [store identifier]);
}

/* -- Apple interoperability -------------------------------------------- */

/* The on-disk format written by this store must match the format Apple's
   NSXMLStoreType writes: a <database> root, a <databaseInfo> header with
   UUID and nextObjectID, one <object> element per instance whose `type'
   attribute is the uppercased entity name, and <relationship> elements
   whose `idrefs' point at other object ids. */
- (void)testWrittenFileFormatMatchesApple
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *engineering =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:ctx1];
    [engineering setValue:@"Engineering" forKey:@"name"];
    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    [alice setValue:engineering forKey:@"department"];
    [engineering setValue:[NSSet setWithObject:alice] forKey:@"employees"];

    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    NSXMLDocument *doc = [[NSXMLDocument alloc]
        initWithContentsOfURL:self.storeURL options:0 error:&error];
    XCTAssertNotNil(doc, @"store file is not parseable XML: %@", error);

    NSXMLElement *database = [doc rootElement];
    XCTAssertEqualObjects([database name], @"database");

    NSXMLElement *databaseInfo =
        [[database elementsForName:@"databaseInfo"] lastObject];
    XCTAssertNotNil(databaseInfo);
    XCTAssertTrue([[[[databaseInfo elementsForName:@"UUID"] lastObject]
                       stringValue] length] > 0);
    XCTAssertTrue([[[[databaseInfo elementsForName:@"nextObjectID"] lastObject]
                       stringValue] integerValue] > 0);

    NSArray *objects = [database elementsForName:@"object"];
    XCTAssertEqual([objects count], (NSUInteger)2);

    NSMutableSet *objectIDs = [NSMutableSet set];
    NSMutableSet *typeNames = [NSMutableSet set];
    for (NSXMLElement *object in objects) {
        NSString *type = [[object attributeForName:@"type"] stringValue];
        NSString *objectID = [[object attributeForName:@"id"] stringValue];
        /* Apple writes entity names in uppercase. */
        XCTAssertEqualObjects(type, [type uppercaseString]);
        XCTAssertTrue([objectID length] > 0);
        [typeNames addObject:type];
        [objectIDs addObject:objectID];
    }
    XCTAssertEqualObjects(typeNames,
        ([NSSet setWithObjects:@"EMPLOYEE", @"DEPARTMENT", nil]));

    /* Attribute elements carry the value as element content. */
    NSXMLElement *aliceElement = nil;
    for (NSXMLElement *object in objects)
        if ([[[object attributeForName:@"type"] stringValue]
                isEqualToString:@"EMPLOYEE"])
            aliceElement = object;
    XCTAssertNotNil(aliceElement);

    BOOL foundName = NO;
    for (NSXMLElement *attribute in [aliceElement elementsForName:@"attribute"]) {
        if ([[[attribute attributeForName:@"name"] stringValue]
                isEqualToString:@"name"]) {
            foundName = YES;
            XCTAssertEqualObjects([attribute stringValue], @"Alice");
        }
    }
    XCTAssertTrue(foundName);

    /* Relationship idrefs reference object ids present in the file, and the
       destination is the uppercased entity name. */
    for (NSXMLElement *object in objects) {
        for (NSXMLElement *relationship in
                 [object elementsForName:@"relationship"]) {
            NSString *destination =
                [[relationship attributeForName:@"destination"] stringValue];
            XCTAssertEqualObjects(destination, [destination uppercaseString]);
            NSString *idrefs =
                [[relationship attributeForName:@"idrefs"] stringValue];
            for (NSString *ref in
                     [idrefs componentsSeparatedByString:@" "]) {
                if ([ref length] == 0)
                    continue;
                XCTAssertTrue([objectIDs containsObject:ref],
                              @"idref %@ does not match any object id", ref);
            }
        }
    }
}

/* Loads a fixture file written in the format Apple's NSXMLStoreType
   produces (uppercase entity names, z-prefixed object ids, dates as
   seconds since the reference date) and verifies the object graph. */
- (void)testLoadsAppleGeneratedStore
{
    NSString *fixture =
        @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\" ?>\n"
        @"<database>\n"
        @"    <databaseInfo>\n"
        @"        <version>134481920</version>\n"
        @"        <UUID>7DFA6DAB-A071-4B34-8DFB-BAC65DD66FDE</UUID>\n"
        @"        <nextObjectID>105</nextObjectID>\n"
        @"        <metadata></metadata>\n"
        @"    </databaseInfo>\n"
        @"    <object type=\"DEPARTMENT\" id=\"z104\">\n"
        @"        <attribute name=\"name\" type=\"string\">Engineering</attribute>\n"
        @"        <relationship name=\"employees\" type=\"0/0\" destination=\"EMPLOYEE\" idrefs=\"z102 z103\"></relationship>\n"
        @"    </object>\n"
        @"    <object type=\"EMPLOYEE\" id=\"z102\">\n"
        @"        <attribute name=\"name\" type=\"string\">Alice</attribute>\n"
        @"        <attribute name=\"salary\" type=\"int32\">100</attribute>\n"
        @"        <attribute name=\"hireDate\" type=\"date\">445103622.00000000</attribute>\n"
        @"        <relationship name=\"department\" type=\"1/1\" destination=\"DEPARTMENT\" idrefs=\"z104\"></relationship>\n"
        @"    </object>\n"
        @"    <object type=\"EMPLOYEE\" id=\"z103\">\n"
        @"        <attribute name=\"name\" type=\"string\">Bob</attribute>\n"
        @"        <attribute name=\"salary\" type=\"int32\">90</attribute>\n"
        @"        <relationship name=\"department\" type=\"1/1\" destination=\"DEPARTMENT\" idrefs=\"z104\"></relationship>\n"
        @"    </object>\n"
        @"</database>\n";

    NSError *error = nil;
    XCTAssertTrue([fixture writeToURL:self.storeURL
                           atomically:YES
                             encoding:NSUTF8StringEncoding
                                error:&error],
                  @"failed to write fixture: %@", error);

    /* The fixture has no model version hashes in its metadata, so ask
       CoreData to skip the model compatibility check (a no-op on the
       GNUstep port, required by Apple's CoreData). */
    NSDictionary *options = nil;
#ifdef __APPLE__
    options = [NSDictionary
        dictionaryWithObject:[NSNumber numberWithBool:YES]
                      forKey:NSIgnorePersistentStoreVersioningOption];
#endif
    NSManagedObjectContext *ctx = [self contextWithModel:XMLStoreTestModel()
                                                 options:options];

    NSArray *employees = [self fetchEntityNamed:@"Employee" inContext:ctx];
    XCTAssertEqual([employees count], (NSUInteger)2);
    NSSet *names =
        [NSSet setWithArray:[employees valueForKey:@"name"]];
    XCTAssertEqualObjects(names,
        ([NSSet setWithObjects:@"Alice", @"Bob", nil]));

    NSManagedObject *aliceObject = nil;
    for (NSManagedObject *employee in employees)
        if ([[employee valueForKey:@"name"] isEqualToString:@"Alice"])
            aliceObject = employee;
    XCTAssertNotNil(aliceObject);
    XCTAssertEqual([[aliceObject valueForKey:@"salary"] intValue], 100);
    NSDate *hireDate = [aliceObject valueForKey:@"hireDate"];
    XCTAssertNotNil(hireDate);
    XCTAssertEqualWithAccuracy([hireDate timeIntervalSinceReferenceDate],
                               445103622.0, 0.001);

    NSManagedObject *department = [aliceObject valueForKey:@"department"];
    XCTAssertNotNil(department);
    XCTAssertEqualObjects([department valueForKey:@"name"], @"Engineering");

    NSArray *departments = [self fetchEntityNamed:@"Department" inContext:ctx];
    XCTAssertEqual([departments count], (NSUInteger)1);
    NSSet *reloadedEmployees =
        [[departments objectAtIndex:0] valueForKey:@"employees"];
    XCTAssertEqual([reloadedEmployees count], (NSUInteger)2);
}

@end
