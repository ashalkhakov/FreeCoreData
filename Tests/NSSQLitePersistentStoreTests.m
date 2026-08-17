/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSSQLitePersistentStoreTests - tests for the SQLite store
   (NSSQLiteStoreType).  These tests are written against Apple's documented
   behavior so they run identically against Apple's CoreData on macOS and
   against the GNUstep port; run them on macOS to validate assumptions
   about Apple's SQLite store implementation. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"

@interface NSSQLitePersistentStoreTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;

@end

@implementation NSSQLitePersistentStoreTests

- (void)setUp
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"sqlite"];
    self.storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
}

- (void)removeStoreFilesAtURL:(NSURL *)url
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    [fileManager removeItemAtURL:url error:NULL];
    /* Apple's SQLite store may leave WAL/SHM journal files behind. */
    [fileManager removeItemAtPath:[[url path] stringByAppendingString:@"-wal"]
                            error:NULL];
    [fileManager removeItemAtPath:[[url path] stringByAppendingString:@"-shm"]
                            error:NULL];
}

- (void)tearDown
{
    [self removeStoreFilesAtURL:self.storeURL];
    self.storeURL = nil;
}

/* Builds a fresh coordinator + context stack on top of the SQLite store at
   `storeURL`, simulating an independent application run. */
- (NSManagedObjectContext *)contextWithModel:(NSManagedObjectModel *)model
                                     options:(NSDictionary *)options
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:options
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to add SQLite store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

- (NSArray *)fetchEntityNamed:(NSString *)entityName
                    inContext:(NSManagedObjectContext *)ctx
                    predicate:(NSPredicate *)predicate
              sortDescriptors:(NSArray *)sortDescriptors
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:entityName
                                 inManagedObjectContext:ctx]];
    [fetch setPredicate:predicate];
    [fetch setSortDescriptors:sortDescriptors];

    NSError *error = nil;
    NSArray *result = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    return result;
}

/* Inserts Alice (Engineering) and Bob (no department) and saves. */
- (void)populateStore
{
    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];

    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx];
    [alice setValue:@"Alice" forKey:@"name"];
    [alice setValue:[NSNumber numberWithInt:9] forKey:@"salary"];
    [alice setValue:[NSDate dateWithTimeIntervalSinceReferenceDate:1000]
             forKey:@"hireDate"];

    NSManagedObject *bob =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx];
    [bob setValue:@"Bob" forKey:@"name"];
    [bob setValue:[NSNumber numberWithInt:5] forKey:@"salary"];

    NSManagedObject *department =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:ctx];
    [department setValue:@"Engineering" forKey:@"name"];
    [alice setValue:department forKey:@"department"];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
}

- (void)testAddingStoreCreatesFileAndReportsType
{
    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSPersistentStore *store =
        [[[ctx persistentStoreCoordinator] persistentStores] firstObject];

    XCTAssertEqualObjects([store type], NSSQLiteStoreType);
    XCTAssertTrue([[NSFileManager defaultManager]
        fileExistsAtPath:[self.storeURL path]]);
}

- (void)testSaveAndFetchAcrossReopen
{
    [self populateStore];

    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSArray *employees =
        [self fetchEntityNamed:@"Employee"
                     inContext:ctx
                     predicate:nil
               sortDescriptors:[NSArray arrayWithObject:
                   [NSSortDescriptor sortDescriptorWithKey:@"name"
                                                 ascending:YES]]];
    XCTAssertEqual([employees count], (NSUInteger)2);

    NSManagedObject *alice = [employees objectAtIndex:0];
    XCTAssertEqualObjects([alice valueForKey:@"name"], @"Alice");
    XCTAssertEqual([[alice valueForKey:@"salary"] intValue], 9);
    XCTAssertEqualWithAccuracy(
        [[alice valueForKey:@"hireDate"] timeIntervalSinceReferenceDate],
        1000.0, 0.001);

    NSManagedObject *bob = [employees objectAtIndex:1];
    XCTAssertEqualObjects([bob valueForKey:@"name"], @"Bob");
    XCTAssertNil([bob valueForKey:@"hireDate"]);
    XCTAssertNil([bob valueForKey:@"department"]);
}

- (void)testRelationshipsAcrossReopen
{
    [self populateStore];

    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSArray *employees =
        [self fetchEntityNamed:@"Employee"
                     inContext:ctx
                     predicate:[NSPredicate predicateWithFormat:@"name == %@",
                                            @"Alice"]
               sortDescriptors:nil];
    XCTAssertEqual([employees count], (NSUInteger)1);

    NSManagedObject *alice = [employees objectAtIndex:0];
    NSManagedObject *department = [alice valueForKey:@"department"];
    XCTAssertNotNil(department);
    XCTAssertEqualObjects([department valueForKey:@"name"], @"Engineering");

    /* The inverse to-many relationship resolves through the store. */
    id members = [department valueForKey:@"employees"];
    XCTAssertEqual([members count], (NSUInteger)1);
    XCTAssertEqualObjects([[members anyObject] valueForKey:@"name"], @"Alice");
}

- (void)testUpdateAndDeletePersistAcrossReopen
{
    [self populateStore];

    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSArray *employees = [self fetchEntityNamed:@"Employee"
                                      inContext:ctx
                                      predicate:nil
                                sortDescriptors:[NSArray arrayWithObject:
                   [NSSortDescriptor sortDescriptorWithKey:@"name"
                                                 ascending:YES]]];
    NSManagedObject *alice = [employees objectAtIndex:0];
    NSManagedObject *bob = [employees objectAtIndex:1];

    [alice setValue:[NSNumber numberWithInt:12] forKey:@"salary"];
    [ctx deleteObject:bob];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:VersioningTestModelV1()
                                                  options:nil];
    NSArray *remaining = [self fetchEntityNamed:@"Employee"
                                      inContext:ctx2
                                      predicate:nil
                                sortDescriptors:nil];
    XCTAssertEqual([remaining count], (NSUInteger)1);
    XCTAssertEqualObjects([[remaining lastObject] valueForKey:@"name"],
                          @"Alice");
    XCTAssertEqual([[[remaining lastObject] valueForKey:@"salary"] intValue],
                   12);
}

- (void)testObjectIDURIUsesApplePrimaryKeyFormat
{
    [self populateStore];

    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSArray *employees = [self fetchEntityNamed:@"Employee"
                                      inContext:ctx
                                      predicate:nil
                                sortDescriptors:nil];
    NSURL *uri = [[[employees lastObject] objectID] URIRepresentation];

    /* Apple's SQLite store object IDs look like
       x-coredata://<store-UUID>/<Entity>/p<primary key>. */
    XCTAssertEqualObjects([uri scheme], @"x-coredata");
    XCTAssertTrue([[uri lastPathComponent] hasPrefix:@"p"],
                  @"unexpected URI %@", uri);

    /* The URI round-trips back to the same object ID. */
    NSManagedObjectID *objectID = [[ctx persistentStoreCoordinator]
        managedObjectIDForURIRepresentation:uri];
    XCTAssertEqualObjects(objectID, [[employees lastObject] objectID]);
}

- (void)testMetadataContainsTypeUUIDAndVersionHashes
{
    [self populateStore];

    NSError *error = nil;
    NSDictionary *metadata = [NSPersistentStoreCoordinator
        metadataForPersistentStoreOfType:NSSQLiteStoreType
                                     URL:self.storeURL
                                   error:&error];
    XCTAssertNotNil(metadata, @"failed to read metadata: %@", error);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreTypeKey],
                          NSSQLiteStoreType);
    XCTAssertNotNil([metadata objectForKey:NSStoreUUIDKey]);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreModelVersionHashesKey],
                          [VersioningTestModelV1() entityVersionHashesByName]);
}

- (void)testReopeningWithIncompatibleModelFails
{
    [self populateStore];

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV2()];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNil(store);
    XCTAssertNotNil(error);
    XCTAssertEqual([error code],
                   (NSInteger)NSPersistentStoreIncompatibleVersionHashError);
}

- (void)testIgnoreVersioningOptionSkipsCompatibilityCheck
{
    [self populateStore];

    NSError *error = nil;
    NSDictionary *options = [NSDictionary
        dictionaryWithObject:[NSNumber numberWithBool:YES]
                      forKey:NSIgnorePersistentStoreVersioningOption];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV2()];
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:options
                                                         error:&error];
    XCTAssertNotNil(store, @"open with ignore option failed: %@", error);
}

- (void)testMigrationManagerMigratesStore
{
    [self populateStore];

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
                                      type:NSSQLiteStoreType
                                   options:nil
                          withMappingModel:mapping
                          toDestinationURL:destinationURL
                           destinationType:NSSQLiteStoreType
                        destinationOptions:nil
                                     error:&error];
    XCTAssertTrue(ok, @"migration failed: %@", error);

    /* The migrated store opens with the destination model and preserves
       the data and relationships. */
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:destinationModel];
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:destinationURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to open migrated store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[destinationModel entitiesByName] objectForKey:@"Employee"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"name == %@",
                                     @"Alice"]];
    NSArray *employees = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertEqual([employees count], (NSUInteger)1);

    NSManagedObject *alice = [employees objectAtIndex:0];
    XCTAssertEqual([[alice valueForKey:@"salary"] intValue], 9);
    XCTAssertNil([alice valueForKey:@"title"]);

    NSManagedObject *department = [alice valueForKey:@"department"];
    XCTAssertNotNil(department);
    XCTAssertEqualObjects([department valueForKey:@"name"], @"Engineering");

    [self removeStoreFilesAtURL:destinationURL];
}

/* Item <<->> Tag (many-to-many) plus Manager, a subentity of Person. */
static NSManagedObjectModel *manyToManyAndInheritanceModel(void)
{
    NSAttributeDescription *itemName = [[NSAttributeDescription alloc] init];
    [itemName setName:@"name"];
    [itemName setAttributeType:NSStringAttributeType];
    [itemName setOptional:YES];

    NSAttributeDescription *tagLabel = [[NSAttributeDescription alloc] init];
    [tagLabel setName:@"label"];
    [tagLabel setAttributeType:NSStringAttributeType];
    [tagLabel setOptional:YES];

    NSRelationshipDescription *tags = [[NSRelationshipDescription alloc] init];
    [tags setName:@"tags"];
    [tags setMinCount:0];
    [tags setMaxCount:0];
    [tags setOptional:YES];

    NSRelationshipDescription *items = [[NSRelationshipDescription alloc] init];
    [items setName:@"items"];
    [items setMinCount:0];
    [items setMaxCount:0];
    [items setOptional:YES];

    NSEntityDescription *item = [[NSEntityDescription alloc] init];
    [item setName:@"Item"];
    [item setManagedObjectClassName:@"NSManagedObject"];

    NSEntityDescription *tag = [[NSEntityDescription alloc] init];
    [tag setName:@"Tag"];
    [tag setManagedObjectClassName:@"NSManagedObject"];

    [tags setDestinationEntity:tag];
    [tags setInverseRelationship:items];
    [items setDestinationEntity:item];
    [items setInverseRelationship:tags];

    [item setProperties:[NSArray arrayWithObjects:itemName, tags, nil]];
    [tag setProperties:[NSArray arrayWithObjects:tagLabel, items, nil]];

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

    NSEntityDescription *manager = [[NSEntityDescription alloc] init];
    [manager setName:@"Manager"];
    [manager setManagedObjectClassName:@"NSManagedObject"];
    [manager setProperties:[NSArray arrayWithObject:reports]];

    [person setSubentities:[NSArray arrayWithObject:manager]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:
        [NSArray arrayWithObjects:item, tag, person, manager, nil]];
    return model;
}

- (void)testManyToManyAndSubentitiesPersistAcrossReopen
{
    NSManagedObjectContext *ctx =
        [self contextWithModel:manyToManyAndInheritanceModel() options:nil];

    NSManagedObject *pen =
        [NSEntityDescription insertNewObjectForEntityForName:@"Item"
                                      inManagedObjectContext:ctx];
    [pen setValue:@"Pen" forKey:@"name"];
    NSManagedObject *book =
        [NSEntityDescription insertNewObjectForEntityForName:@"Item"
                                      inManagedObjectContext:ctx];
    [book setValue:@"Book" forKey:@"name"];

    NSManagedObject *red =
        [NSEntityDescription insertNewObjectForEntityForName:@"Tag"
                                      inManagedObjectContext:ctx];
    [red setValue:@"red" forKey:@"label"];
    NSManagedObject *blue =
        [NSEntityDescription insertNewObjectForEntityForName:@"Tag"
                                      inManagedObjectContext:ctx];
    [blue setValue:@"blue" forKey:@"label"];

    [[pen mutableSetValueForKey:@"tags"] addObject:red];
    [[pen mutableSetValueForKey:@"tags"] addObject:blue];
    [[book mutableSetValueForKey:@"tags"] addObject:red];

    NSManagedObject *boss =
        [NSEntityDescription insertNewObjectForEntityForName:@"Manager"
                                      inManagedObjectContext:ctx];
    [boss setValue:@"Boss" forKey:@"name"];
    [boss setValue:[NSNumber numberWithInt:7] forKey:@"reports"];
    NSManagedObject *worker =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:ctx];
    [worker setValue:@"Worker" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* Reopen and verify the many-to-many relationship from both sides. */
    ctx = [self contextWithModel:manyToManyAndInheritanceModel() options:nil];

    NSArray *pens = [self fetchEntityNamed:@"Item"
                                 inContext:ctx
                                 predicate:[NSPredicate predicateWithFormat:
                                               @"name == %@", @"Pen"]
                           sortDescriptors:nil];
    XCTAssertEqual([pens count], (NSUInteger)1);
    pen = [pens objectAtIndex:0];
    XCTAssertEqual([[pen valueForKey:@"tags"] count], (NSUInteger)2);

    NSArray *reds = [self fetchEntityNamed:@"Tag"
                                 inContext:ctx
                                 predicate:[NSPredicate predicateWithFormat:
                                               @"label == %@", @"red"]
                           sortDescriptors:nil];
    XCTAssertEqual([reds count], (NSUInteger)1);
    red = [reds objectAtIndex:0];
    XCTAssertEqual([[red valueForKey:@"items"] count], (NSUInteger)2);

    /* A fetch of the parent entity includes subentity instances... */
    NSArray *people = [self fetchEntityNamed:@"Person"
                                   inContext:ctx
                                   predicate:nil
                             sortDescriptors:nil];
    XCTAssertEqual([people count], (NSUInteger)2);

    NSUInteger managerCount = 0;
    for (NSManagedObject *person in people)
        if ([[[person entity] name] isEqualToString:@"Manager"]) {
            managerCount++;
            XCTAssertEqual([[person valueForKey:@"reports"] intValue], 7);
        }
    XCTAssertEqual(managerCount, (NSUInteger)1);

    /* ...while a fetch of the subentity finds only its own instances. */
    NSArray *managers = [self fetchEntityNamed:@"Manager"
                                     inContext:ctx
                                     predicate:nil
                               sortDescriptors:nil];
    XCTAssertEqual([managers count], (NSUInteger)1);

    /* Removing from one side of a many-to-many persists. */
    [[pen mutableSetValueForKey:@"tags"] removeObject:
        [[pen valueForKey:@"tags"] anyObject]];
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    ctx = [self contextWithModel:manyToManyAndInheritanceModel() options:nil];
    pens = [self fetchEntityNamed:@"Item"
                        inContext:ctx
                        predicate:[NSPredicate predicateWithFormat:
                                      @"name == %@", @"Pen"]
                  sortDescriptors:nil];
    XCTAssertEqual([[[pens objectAtIndex:0] valueForKey:@"tags"] count],
                   (NSUInteger)1);
}

@end
