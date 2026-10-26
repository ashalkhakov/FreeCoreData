/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSManagedObjectContextTests - basic context tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

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

/* A context with a one entity model, used by the change notification
   tests below. */
- (NSManagedObjectContext *)contextWithNoteEntity
{
    NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
    [text setName:@"text"];
    [text setAttributeType:NSStringAttributeType];
    [text setOptional:YES];

    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"NSManagedObject"];
    [note setProperties:[NSArray arrayWithObject:text]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:note]];

    NSPersistentStoreCoordinator *psc =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *err = nil;
    XCTAssertNotNil([psc addPersistentStoreWithType:NSInMemoryStoreType
                         configuration:nil URL:nil options:nil error:&err],
        @"unable to add the store: %@", err);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    /* The receiver keeps the whole stack alive for the test. */
    self.model = model;
    self.psc = psc;

    return ctx;
}

/* -reset tells its observers, before it returns, that every object it had
   is gone: the IDs of them all - temporary ones for objects never saved -
   under NSInvalidatedAllObjectsKey, and nothing of the changes still
   pending.  An empty context tells them too. */
- (void)testResetPostsTheIDsOfEveryObjectItHad
{
    NSManagedObjectContext *ctx = [self contextWithNoteEntity];
    NSMutableArray *notes = [NSMutableArray array];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
        object:ctx queue:nil usingBlock:^(NSNotification *note) {
            [notes addObject:[note userInfo]];
        }];

    [ctx reset];
    XCTAssertEqual([notes count], (NSUInteger)1);
    XCTAssertEqualObjects([[notes lastObject] objectForKey:NSInvalidatedAllObjectsKey], @[]);

    NSManagedObject *saved = [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                                           inManagedObjectContext:ctx];
    [saved setValue:@"saved" forKey:@"text"];
    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"%@", error);
    [ctx processPendingChanges];

    NSManagedObject *fetched = [[ctx executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Note"] error:NULL] firstObject];
    [fetched setValue:@"changed" forKey:@"text"];
    NSManagedObject *inserted = [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                                              inManagedObjectContext:ctx];
    NSSet *expected = [NSSet setWithObjects:[fetched objectID], [inserted objectID], nil];

    [notes removeAllObjects];
    [ctx reset];
    XCTAssertEqual([notes count], (NSUInteger)1);
    NSDictionary *userInfo = [notes lastObject];
    XCTAssertNil([userInfo objectForKey:NSInsertedObjectsKey]);
    XCTAssertNil([userInfo objectForKey:NSUpdatedObjectsKey]);
    NSArray *invalidated = [userInfo objectForKey:NSInvalidatedAllObjectsKey];
    XCTAssertTrue([invalidated isKindOfClass:[NSArray class]]);
    XCTAssertEqualObjects([NSSet setWithArray:invalidated], expected);
    XCTAssertEqual([[ctx registeredObjects] count], (NSUInteger)0);

    /* Nothing more comes once the changes it had would have been processed. */
    [ctx processPendingChanges];
    XCTAssertEqual([notes count], (NSUInteger)1);

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

/* A merge is told of at once, as on Apple: one objects-did-change
   notification posted before the merge returns, with the merge's
   insertions, deletions and refreshes and whatever the context had
   pending of its own - an object edited here and refreshed by the merge
   is both updated and refreshed.  Nothing is left for the event's end.
   The same for a merge of a save's object IDs into several contexts. */
- (void)testAMergeIsToldOfAtOnce
{
    for (NSString *how in @[ @"notification", @"remote" ]) {
        NSManagedObjectContext *saving = [self contextWithNoteEntity];
        NSManagedObjectContext *merging = [[NSManagedObjectContext alloc] init];
        [merging setPersistentStoreCoordinator:[saving persistentStoreCoordinator]];

        NSManagedObject *edited = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:saving];
        NSManagedObject *gone = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:saving];
        [edited setValue:@"edited" forKey:@"text"];
        [gone setValue:@"gone" forKey:@"text"];
        NSError *error = nil;
        XCTAssertTrue([saving save:&error], @"%@", error);

        NSManagedObject *mergingEdited = [merging existingObjectWithID:[edited objectID] error:NULL];
        NSManagedObject *mergingGone = [merging existingObjectWithID:[gone objectID] error:NULL];
        [merging processPendingChanges];

        NSMutableArray *notes = [NSMutableArray array];
        id observer = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
            object:merging queue:nil usingBlock:^(NSNotification *note) {
                [notes addObject:[note userInfo]];
            }];

        NSManagedObject *local = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:merging];
        [local setValue:@"local" forKey:@"text"];
        [mergingEdited setValue:@"edited here" forKey:@"text"];

        NSManagedObject *added = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:saving];
        [added setValue:@"added" forKey:@"text"];
        [edited setValue:@"edited there" forKey:@"text"];
        [saving deleteObject:gone];
        __block NSDictionary *saved = nil;
        id saveObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:NSManagedObjectContextDidSaveNotification
            object:saving queue:nil usingBlock:^(NSNotification *note) {
                saved = [note userInfo];
            }];
        XCTAssertTrue([saving save:&error], @"%@", error);
        [[NSNotificationCenter defaultCenter] removeObserver:saveObserver];

        if ([how isEqualToString:@"notification"])
            [merging mergeChangesFromContextDidSaveNotification:
                [NSNotification notificationWithName:NSManagedObjectContextDidSaveNotification object:saving userInfo:saved]];
        else {
            NSMutableDictionary *ids = [NSMutableDictionary dictionary];
            for (NSString *key in @[ NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey ])
                ids[key] = [[saved[key] allObjects] valueForKey:@"objectID"];
            [NSManagedObjectContext mergeChangesFromRemoteContextSave:ids intoContexts:@[ merging ]];
        }

        XCTAssertEqual([notes count], (NSUInteger)1, @"%@: told before the merge returns", how);
        NSDictionary *userInfo = [notes lastObject];
        NSSet *inserted = userInfo[NSInsertedObjectsKey];
        XCTAssertEqual([inserted count], (NSUInteger)2, @"%@", how);
        XCTAssertTrue([inserted containsObject:local], @"%@", how);
        XCTAssertTrue([userInfo[NSUpdatedObjectsKey] containsObject:mergingEdited], @"%@", how);
        XCTAssertTrue([userInfo[NSRefreshedObjectsKey] containsObject:mergingEdited], @"%@", how);
        XCTAssertTrue([userInfo[NSDeletedObjectsKey] containsObject:mergingGone], @"%@", how);

        [merging processPendingChanges];
        XCTAssertEqual([notes count], (NSUInteger)1, @"%@: nothing left for the event's end", how);
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }
}

- (void)testProcessPendingChangesPostsObjectsDidChangeNotification
{
    NSManagedObjectContext *ctx = [self contextWithNoteEntity];
    __block NSDictionary *userInfo = nil;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
        object:ctx queue:nil usingBlock:^(NSNotification *note) {
            userInfo = [note userInfo];
        }];

    NSManagedObject *inserted =
        [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                             inManagedObjectContext:ctx];
    [inserted setValue:@"hello" forKey:@"text"];

    [ctx processPendingChanges];

    XCTAssertNotNil(userInfo);
    XCTAssertTrue([[userInfo objectForKey:NSInsertedObjectsKey] containsObject:inserted]);

    /* Changes are reported only once. */
    userInfo = nil;
    [ctx processPendingChanges];
    XCTAssertNil(userInfo);

    /* Updating a registered object reports it as updated. */
    [inserted setValue:@"goodbye" forKey:@"text"];
    [ctx processPendingChanges];
    XCTAssertNotNil(userInfo);
    XCTAssertTrue([[userInfo objectForKey:NSUpdatedObjectsKey] containsObject:inserted]);

    /* Deleting it reports it as deleted. */
    userInfo = nil;
    [ctx deleteObject:inserted];
    [ctx processPendingChanges];
    XCTAssertNotNil(userInfo);
    XCTAssertTrue([[userInfo objectForKey:NSDeletedObjectsKey] containsObject:inserted]);

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

/* Category <-> products (one-to-many), person <-> partner (one-to-one). */
static NSManagedObjectContext *InverseTestContext(void)
{
    NSEntityDescription *category = [[NSEntityDescription alloc] init];
    [category setName:@"InverseCategory"];
    [category setManagedObjectClassName:@"NSManagedObject"];
    NSEntityDescription *product = [[NSEntityDescription alloc] init];
    [product setName:@"InverseProduct"];
    [product setManagedObjectClassName:@"NSManagedObject"];
    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    [person setName:@"InversePerson"];
    [person setManagedObjectClassName:@"NSManagedObject"];
    NSMutableArray *names = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
        [name setName:@"name"];
        [name setAttributeType:NSStringAttributeType];
        [name setOptional:YES];
        [names addObject:name];
    }
    NSRelationshipDescription *products = [[NSRelationshipDescription alloc] init];
    [products setName:@"products"];
    [products setDestinationEntity:product];
    [products setMaxCount:0];
    [products setOptional:YES];
    NSRelationshipDescription *owner = [[NSRelationshipDescription alloc] init];
    [owner setName:@"category"];
    [owner setDestinationEntity:category];
    [owner setMaxCount:1];
    [owner setOptional:YES];
    [products setInverseRelationship:owner];
    [owner setInverseRelationship:products];
    NSRelationshipDescription *partner = [[NSRelationshipDescription alloc] init];
    [partner setName:@"partner"];
    [partner setDestinationEntity:person];
    [partner setMaxCount:1];
    [partner setOptional:YES];
    [partner setInverseRelationship:partner];
    [category setProperties:@[ names[0], products ]];
    [product setProperties:@[ names[1], owner ]];
    [person setProperties:@[ names[2], partner ]];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ category, product, person ]];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL];
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [context setPersistentStoreCoordinator:psc];
    return context;
}

static NSManagedObject *InverseTestObject(NSManagedObjectContext *context, NSString *entity, NSString *name)
{
    NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:context];
    [object setValue:name forKey:@"name"];
    return object;
}

static NSArray *InverseTestNames(id objects)
{
    return [[[objects valueForKey:@"name"] allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

- (void)testAnObjectAddedToAToManyLeavesItsOldOwner
{
    /* Apple: a product added to a category's products, by setting the set
       or through -mutableSetValueForKey:, is no longer among the products
       of the category it had, before a save and after it. */
    for (NSString *how in @[ @"set", @"mutable" ]) {
        NSManagedObjectContext *context = InverseTestContext();
        NSManagedObject *drinks = InverseTestObject(context, @"InverseCategory", @"drinks");
        NSManagedObject *sauces = InverseTestObject(context, @"InverseCategory", @"sauces");
        NSManagedObject *chai = InverseTestObject(context, @"InverseProduct", @"chai");
        NSManagedObject *syrup = InverseTestObject(context, @"InverseProduct", @"syrup");
        [chai setValue:drinks forKey:@"category"];
        [syrup setValue:sauces forKey:@"category"];
        NSError *error = nil;
        XCTAssertTrue([context save:&error], @"%@", error);

        if ([how isEqualToString:@"set"])
            [drinks setValue:[NSSet setWithObjects:chai, syrup, nil] forKey:@"products"];
        else
            [[drinks mutableSetValueForKey:@"products"] addObject:syrup];
        XCTAssertEqualObjects([syrup valueForKey:@"category"], drinks, @"%@", how);
        XCTAssertEqualObjects(InverseTestNames([sauces valueForKey:@"products"]), @[], @"%@", how);
        XCTAssertTrue([[context updatedObjects] containsObject:sauces], @"%@: the old owner changed", how);

        XCTAssertTrue([context save:&error], @"%@", error);
        [context reset];
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"InverseCategory"];
        [request setPredicate:[NSPredicate predicateWithFormat:@"name == 'sauces'"]];
        NSManagedObject *saved = [[context executeFetchRequest:request error:NULL] firstObject];
        XCTAssertEqualObjects(InverseTestNames([saved valueForKey:@"products"]), @[], @"%@: after a save", how);
    }
}

- (void)testAOneToOnePartnersOldPartnerHasNone
{
    NSManagedObjectContext *context = InverseTestContext();
    NSManagedObject *ann = InverseTestObject(context, @"InversePerson", @"ann");
    NSManagedObject *bob = InverseTestObject(context, @"InversePerson", @"bob");
    NSManagedObject *cy = InverseTestObject(context, @"InversePerson", @"cy");
    [ann setValue:bob forKey:@"partner"];
    [cy setValue:bob forKey:@"partner"];
    XCTAssertEqualObjects([bob valueForKey:@"partner"], cy);
    XCTAssertNil([ann valueForKey:@"partner"]);
}

/* Every string constant has the value Apple's Core Data gives it (as
   printed on macOS 15), not its own name: code that matches a notification
   or a key by string, such as gnustep-gui's controllers, which cannot link
   Core Data, then works with both. */
- (void)testStringConstantsHaveCoreDataValues
{
    NSDictionary *expected = @{
        @"NSAddedPersistentStoresKey": @"added",
        @"NSAffectedStoresErrorKey": @"NSAffectedStoresErrorKey",
        @"NSDeletedObjectIDsKey": @"deleted_objectIDs",
        @"NSDeletedObjectsKey": @"deleted",
        @"NSDetailedErrorsKey": @"NSDetailedErrors",
        @"NSIgnorePersistentStoreVersioningOption": @"NSIgnorePersistentStoreVersioningOption",
        @"NSInMemoryStoreType": @"InMemory",
        @"NSInferMappingModelAutomaticallyOption": @"NSInferMappingModelAutomaticallyOption",
        @"NSInsertedObjectIDsKey": @"inserted_objectIDs",
        @"NSInsertedObjectsKey": @"inserted",
        @"NSInvalidatedAllObjectsKey": @"invalidatedAll",
        @"NSInvalidatedObjectsKey": @"invalidated",
        @"NSManagedObjectContextDidSaveNotification": @"NSManagingContextDidSaveChangesNotification",
        @"NSManagedObjectContextDidSaveObjectIDsNotification": @"NSManagedObjectContextDidSaveObjectIDsNotification",
        @"NSManagedObjectContextObjectsDidChangeNotification": @"NSObjectsChangedInManagingContextNotification",
        @"NSManagedObjectContextWillSaveNotification": @"NSManagingContextWillSaveChangesNotification",
        @"NSMigratePersistentStoresAutomaticallyOption": @"NSMigratePersistentStoresAutomaticallyOption",
        @"NSMigrationDestinationObjectKey": @"destination",
        @"NSMigrationEntityMappingKey": @"entityMapping",
        @"NSMigrationEntityPolicyKey": @"entityPolicy",
        @"NSMigrationManagerKey": @"manager",
        @"NSMigrationPropertyMappingKey": @"propertyMapping",
        @"NSMigrationSourceObjectKey": @"source",
        @"NSPersistentHistoryTokenKey": @"historyToken",
        @"NSPersistentHistoryTrackingKey": @"NSPersistentHistoryTrackingKey",
        @"NSPersistentStoreCoordinatorStoresDidChangeNotification": @"NSPersistentStoreCoordinatorStoresDidChangeNotification",
        @"NSPersistentStoreRemoteChangeNotification": @"NSPersistentStoreRemoteChangeNotification",
        @"NSPersistentStoreRemoteChangeNotificationPostOptionKey": @"NSPersistentStoreRemoteChangeNotificationOptionKey",
        @"NSPersistentStoreSaveConflictsErrorKey": @"conflictList",
        @"NSReadOnlyPersistentStoreOption": @"NSReadOnlyPersistentStoreOption",
        @"NSRefreshedObjectsKey": @"refreshed",
        @"NSRemovedPersistentStoresKey": @"removed",
        @"NSSQLiteErrorDomain": @"NSSQLiteErrorDomain",
        @"NSSQLiteManualVacuumOption": @"NSSQLiteManualVacuumOption",
        @"NSSQLiteStoreType": @"SQLite",
        @"NSStoreModelVersionHashesKey": @"NSStoreModelVersionHashes",
        @"NSStoreModelVersionIdentifiersKey": @"NSStoreModelVersionIdentifiers",
        @"NSStoreTypeKey": @"NSStoreType",
        @"NSStoreUUIDKey": @"NSStoreUUID",
        @"NSUUIDChangedPersistentStoresKey": @"changedUUID",
        @"NSUpdatedObjectIDsKey": @"updated_objectIDs",
        @"NSUpdatedObjectsKey": @"updated",
        @"NSValidationKeyErrorKey": @"NSValidationErrorKey",
        @"NSValidationObjectErrorKey": @"NSValidationErrorObject",
        @"NSValidationPredicateErrorKey": @"NSValidationErrorPredicate",
        @"NSValidationValueErrorKey": @"NSValidationErrorValue",
        @"NSXMLStoreType": @"XML",
    };
    NSDictionary *actual = @{
        @"NSAddedPersistentStoresKey": NSAddedPersistentStoresKey,
        @"NSAffectedStoresErrorKey": NSAffectedStoresErrorKey,
        @"NSDeletedObjectIDsKey": NSDeletedObjectIDsKey,
        @"NSDeletedObjectsKey": NSDeletedObjectsKey,
        @"NSDetailedErrorsKey": NSDetailedErrorsKey,
        @"NSIgnorePersistentStoreVersioningOption": NSIgnorePersistentStoreVersioningOption,
        @"NSInMemoryStoreType": NSInMemoryStoreType,
        @"NSInferMappingModelAutomaticallyOption": NSInferMappingModelAutomaticallyOption,
        @"NSInsertedObjectIDsKey": NSInsertedObjectIDsKey,
        @"NSInsertedObjectsKey": NSInsertedObjectsKey,
        @"NSInvalidatedAllObjectsKey": NSInvalidatedAllObjectsKey,
        @"NSInvalidatedObjectsKey": NSInvalidatedObjectsKey,
        @"NSManagedObjectContextDidSaveNotification": NSManagedObjectContextDidSaveNotification,
        @"NSManagedObjectContextDidSaveObjectIDsNotification": NSManagedObjectContextDidSaveObjectIDsNotification,
        @"NSManagedObjectContextObjectsDidChangeNotification": NSManagedObjectContextObjectsDidChangeNotification,
        @"NSManagedObjectContextWillSaveNotification": NSManagedObjectContextWillSaveNotification,
        @"NSMigratePersistentStoresAutomaticallyOption": NSMigratePersistentStoresAutomaticallyOption,
        @"NSMigrationDestinationObjectKey": NSMigrationDestinationObjectKey,
        @"NSMigrationEntityMappingKey": NSMigrationEntityMappingKey,
        @"NSMigrationEntityPolicyKey": NSMigrationEntityPolicyKey,
        @"NSMigrationManagerKey": NSMigrationManagerKey,
        @"NSMigrationPropertyMappingKey": NSMigrationPropertyMappingKey,
        @"NSMigrationSourceObjectKey": NSMigrationSourceObjectKey,
        @"NSPersistentHistoryTokenKey": NSPersistentHistoryTokenKey,
        @"NSPersistentHistoryTrackingKey": NSPersistentHistoryTrackingKey,
        @"NSPersistentStoreCoordinatorStoresDidChangeNotification": NSPersistentStoreCoordinatorStoresDidChangeNotification,
        @"NSPersistentStoreRemoteChangeNotification": NSPersistentStoreRemoteChangeNotification,
        @"NSPersistentStoreRemoteChangeNotificationPostOptionKey": NSPersistentStoreRemoteChangeNotificationPostOptionKey,
        @"NSPersistentStoreSaveConflictsErrorKey": NSPersistentStoreSaveConflictsErrorKey,
        @"NSReadOnlyPersistentStoreOption": NSReadOnlyPersistentStoreOption,
        @"NSRefreshedObjectsKey": NSRefreshedObjectsKey,
        @"NSRemovedPersistentStoresKey": NSRemovedPersistentStoresKey,
        @"NSSQLiteErrorDomain": NSSQLiteErrorDomain,
        @"NSSQLiteManualVacuumOption": NSSQLiteManualVacuumOption,
        @"NSSQLiteStoreType": NSSQLiteStoreType,
        @"NSStoreModelVersionHashesKey": NSStoreModelVersionHashesKey,
        @"NSStoreModelVersionIdentifiersKey": NSStoreModelVersionIdentifiersKey,
        @"NSStoreTypeKey": NSStoreTypeKey,
        @"NSStoreUUIDKey": NSStoreUUIDKey,
        @"NSUUIDChangedPersistentStoresKey": NSUUIDChangedPersistentStoresKey,
        @"NSUpdatedObjectIDsKey": NSUpdatedObjectIDsKey,
        @"NSUpdatedObjectsKey": NSUpdatedObjectsKey,
        @"NSValidationKeyErrorKey": NSValidationKeyErrorKey,
        @"NSValidationObjectErrorKey": NSValidationObjectErrorKey,
        @"NSValidationPredicateErrorKey": NSValidationPredicateErrorKey,
        @"NSValidationValueErrorKey": NSValidationValueErrorKey,
        @"NSXMLStoreType": NSXMLStoreType,
    };
    for (NSString *name in expected)
        XCTAssertEqualObjects([actual objectForKey:name],
                              [expected objectForKey:name], @"%@", name);
}

@end
