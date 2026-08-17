/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* StoreVersioningTests - store metadata stamping, compatibility and migration tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"

@interface StoreVersioningTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;

@end

@implementation StoreVersioningTests

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

- (NSPersistentStore *)openStoreWithModel:(NSManagedObjectModel *)model
                                  options:(NSDictionary *)options
                                    error:(NSError **)error
                                  context:(NSManagedObjectContext **)outContext
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSXMLStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:options
                                                         error:error];
    if (store != nil && outContext != NULL) {
        NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
        [ctx setPersistentStoreCoordinator:psc];
        *outContext = ctx;
    }
    return store;
}

- (void)createV1StoreWithEmployeeNamed:(NSString *)name
{
    NSError *error = nil;
    NSManagedObjectContext *ctx = nil;
    NSPersistentStore *store = [self openStoreWithModel:VersioningTestModelV1()
                                                options:nil
                                                  error:&error
                                                context:&ctx];
    XCTAssertNotNil(store, @"failed to open store: %@", error);

    NSManagedObject *employee =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx];
    [employee setValue:name forKey:@"name"];
    [employee setValue:[NSNumber numberWithInt:9] forKey:@"salary"];

    NSManagedObject *department =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:ctx];
    [department setValue:@"Engineering" forKey:@"name"];
    [employee setValue:department forKey:@"department"];

    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
}

- (void)testStoreIsStampedWithVersionHashes
{
    [self createV1StoreWithEmployeeNamed:@"Alice"];

    NSError *error = nil;
    NSDictionary *metadata = [NSPersistentStoreCoordinator
        metadataForPersistentStoreOfType:NSXMLStoreType
                                     URL:self.storeURL
                                   error:&error];
    XCTAssertNotNil(metadata);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreModelVersionHashesKey],
                          [VersioningTestModelV1() entityVersionHashesByName]);
}

- (void)testReopeningWithCompatibleModelSucceeds
{
    [self createV1StoreWithEmployeeNamed:@"Alice"];

    NSError *error = nil;
    NSPersistentStore *store = [self openStoreWithModel:VersioningTestModelV1()
                                                options:nil
                                                  error:&error
                                                context:NULL];
    XCTAssertNotNil(store, @"reopen failed: %@", error);
}

- (void)testReopeningWithIncompatibleModelFails
{
    [self createV1StoreWithEmployeeNamed:@"Alice"];

    NSError *error = nil;
    NSPersistentStore *store = [self openStoreWithModel:VersioningTestModelV2()
                                                options:nil
                                                  error:&error
                                                context:NULL];
    XCTAssertNil(store);
    XCTAssertNotNil(error);
    XCTAssertEqual([error code],
                   (NSInteger)NSPersistentStoreIncompatibleVersionHashError);
}

- (void)testIgnoreVersioningOptionSkipsCompatibilityCheck
{
    [self createV1StoreWithEmployeeNamed:@"Alice"];

    NSError *error = nil;
    NSDictionary *options = [NSDictionary
        dictionaryWithObject:[NSNumber numberWithBool:YES]
                      forKey:NSIgnorePersistentStoreVersioningOption];
    NSPersistentStore *store = [self openStoreWithModel:VersioningTestModelV2()
                                                options:options
                                                  error:&error
                                                context:NULL];
    XCTAssertNotNil(store, @"open with ignore option failed: %@", error);
}

- (void)testModelCompatibilityWithStoreMetadata
{
    [self createV1StoreWithEmployeeNamed:@"Alice"];

    NSError *error = nil;
    NSDictionary *metadata = [NSPersistentStoreCoordinator
        metadataForPersistentStoreOfType:NSXMLStoreType
                                     URL:self.storeURL
                                   error:&error];
    XCTAssertNotNil(metadata, @"failed to read metadata: %@", error);

    XCTAssertTrue([VersioningTestModelV1() isConfiguration:nil
                              compatibleWithStoreMetadata:metadata]);
    XCTAssertFalse([VersioningTestModelV2() isConfiguration:nil
                               compatibleWithStoreMetadata:metadata]);
    XCTAssertFalse([VersioningTestModelV1() isConfiguration:nil
               compatibleWithStoreMetadata:[NSDictionary dictionary]]);
}

- (void)testMigrationManagerMigratesStore
{
    [self createV1StoreWithEmployeeNamed:@"Alice"];

    NSManagedObjectModel *sourceModel = VersioningTestModelV1();
    NSManagedObjectModel *destinationModel = VersioningTestModelV2();

    NSError *error = nil;
    NSMappingModel *mapping = [NSMappingModel
        inferredMappingModelForSourceModel:sourceModel
                          destinationModel:destinationModel
                                     error:&error];
    XCTAssertNotNil(mapping);

    NSURL *destinationURL = [NSURL fileURLWithPath:
        [[self.storeURL path] stringByAppendingString:@"-v2"]];

    NSMigrationManager *manager = [[NSMigrationManager alloc]
        initWithSourceModel:sourceModel destinationModel:destinationModel];
    BOOL ok = [manager migrateStoreFromURL:self.storeURL
                                      type:NSXMLStoreType
                                   options:nil
                          withMappingModel:mapping
                          toDestinationURL:destinationURL
                           destinationType:NSXMLStoreType
                        destinationOptions:nil
                                     error:&error];
    XCTAssertTrue(ok, @"migration failed: %@", error);
    /* Apple resets the migration progress once the migration completes. */
    XCTAssertEqualWithAccuracy([manager migrationProgress], 0.0f, 0.001f);

    /* The migrated store opens with the destination model and preserves
       the data and relationships. */
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:destinationModel];
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSXMLStoreType
                                                 configuration:nil
                                                           URL:destinationURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to open migrated store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[destinationModel entitiesByName] objectForKey:@"Employee"]];
    NSArray *employees = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertEqual([employees count], (NSUInteger)1);

    NSManagedObject *alice = [employees objectAtIndex:0];
    XCTAssertEqualObjects([alice valueForKey:@"name"], @"Alice");
    XCTAssertEqual([[alice valueForKey:@"salary"] intValue], 9);
    XCTAssertNil([alice valueForKey:@"title"]);

    NSManagedObject *department = [alice valueForKey:@"department"];
    XCTAssertNotNil(department);
    XCTAssertEqualObjects([department valueForKey:@"name"], @"Engineering");

    [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:NULL];
}

/* -- entity inheritance ------------------------------------------------ */

/* Person(name) with subentity Manager.  When `withBudget` is YES the
   Manager subentity carries an extra attribute, producing a different
   version hash for Manager (but not for Person). */
static NSManagedObjectModel *InheritanceVersioningModel(BOOL withBudget)
{
    NSAttributeDescription *personName = [[NSAttributeDescription alloc] init];
    [personName setName:@"name"];
    [personName setAttributeType:NSStringAttributeType];
    [personName setOptional:YES];

    NSAttributeDescription *reports = [[NSAttributeDescription alloc] init];
    [reports setName:@"reports"];
    [reports setAttributeType:NSInteger32AttributeType];
    [reports setOptional:YES];

    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    [person setName:@"Person"];
    [person setManagedObjectClassName:@"NSManagedObject"];
    [person setProperties:[NSArray arrayWithObject:personName]];

    NSMutableArray *managerProperties =
        [NSMutableArray arrayWithObject:reports];
    if (withBudget) {
        NSAttributeDescription *budget =
            [[NSAttributeDescription alloc] init];
        [budget setName:@"budget"];
        [budget setAttributeType:NSInteger32AttributeType];
        [budget setOptional:YES];
        [managerProperties addObject:budget];
    }

    NSEntityDescription *manager = [[NSEntityDescription alloc] init];
    [manager setName:@"Manager"];
    [manager setManagedObjectClassName:@"NSManagedObject"];
    [manager setProperties:managerProperties];

    [person setSubentities:[NSArray arrayWithObject:manager]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObjects:person, manager, nil]];
    return model;
}

- (void)createInheritanceStore
{
    NSError *error = nil;
    NSManagedObjectContext *ctx = nil;
    NSPersistentStore *store =
        [self openStoreWithModel:InheritanceVersioningModel(NO)
                         options:nil
                           error:&error
                         context:&ctx];
    XCTAssertNotNil(store, @"failed to open store: %@", error);

    NSManagedObject *boss =
        [NSEntityDescription insertNewObjectForEntityForName:@"Manager"
                                      inManagedObjectContext:ctx];
    [boss setValue:@"Boss" forKey:@"name"];
    [boss setValue:[NSNumber numberWithInt:7] forKey:@"reports"];

    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
}

- (void)testInheritanceStoreIsStampedWithSubentityHashes
{
    [self createInheritanceStore];

    NSError *error = nil;
    NSDictionary *metadata = [NSPersistentStoreCoordinator
        metadataForPersistentStoreOfType:NSXMLStoreType
                                     URL:self.storeURL
                                   error:&error];
    XCTAssertNotNil(metadata, @"failed to read metadata: %@", error);

    /* The version hashes cover the parent and the subentity, and match
       the model's own per-entity hashes. */
    NSDictionary *hashes =
        [metadata objectForKey:NSStoreModelVersionHashesKey];
    XCTAssertNotNil([hashes objectForKey:@"Person"]);
    XCTAssertNotNil([hashes objectForKey:@"Manager"]);
    XCTAssertEqualObjects(hashes,
        [InheritanceVersioningModel(NO) entityVersionHashesByName]);
}

- (void)testReopeningWithModifiedSubentityFails
{
    [self createInheritanceStore];

    /* Reopening with an identical model (parent and subentity unchanged)
       succeeds... */
    NSError *error = nil;
    NSPersistentStore *store =
        [self openStoreWithModel:InheritanceVersioningModel(NO)
                         options:nil
                           error:&error
                         context:NULL];
    XCTAssertNotNil(store, @"reopen failed: %@", error);

    /* ...while a model whose subentity gained an attribute is rejected,
       even though the parent entity is unchanged. */
    error = nil;
    store = [self openStoreWithModel:InheritanceVersioningModel(YES)
                             options:nil
                               error:&error
                             context:NULL];
    XCTAssertNil(store);
    XCTAssertNotNil(error);
    XCTAssertEqual([error code],
                   (NSInteger)NSPersistentStoreIncompatibleVersionHashError);
}

- (void)testModifiedSubentityChangesOnlyItsOwnVersionHash
{
    NSDictionary *v1Hashes =
        [InheritanceVersioningModel(NO) entityVersionHashesByName];
    NSDictionary *v2Hashes =
        [InheritanceVersioningModel(YES) entityVersionHashesByName];

    XCTAssertEqualObjects([v1Hashes objectForKey:@"Person"],
                          [v2Hashes objectForKey:@"Person"]);
    XCTAssertNotEqualObjects([v1Hashes objectForKey:@"Manager"],
                             [v2Hashes objectForKey:@"Manager"]);
}

@end
