/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSMergePolicyTests - merging and conflict resolution tests, mirroring
   Apple's "Conflict resolution" Core Data documentation: merge policy
   constants, cross-context change merging, and optimistic-locking
   conflicts resolved per merge policy during -save:. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

/* Model: Person(name, salary). */
static NSManagedObjectModel *MergeTestModel(void)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];

    NSAttributeDescription *salary = [[NSAttributeDescription alloc] init];
    [salary setName:@"salary"];
    [salary setAttributeType:NSInteger32AttributeType];

    NSEntityDescription *personEntity = [[NSEntityDescription alloc] init];
    [personEntity setName:@"Person"];
    [personEntity setManagedObjectClassName:@"NSManagedObject"];
    [personEntity setProperties:[NSArray arrayWithObjects:name, salary, nil]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:personEntity]];
    return model;
}

@interface NSMergePolicyTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSManagedObjectContext *ctx1;
@property (nonatomic, strong) NSManagedObjectContext *ctx2;

@end

@implementation NSMergePolicyTests

- (void)setUp
{
    self.model = MergeTestModel();
    self.psc = [[NSPersistentStoreCoordinator alloc]
                   initWithManagedObjectModel:self.model];
    NSError *error = nil;
    [self.psc addPersistentStoreWithType:NSInMemoryStoreType
                           configuration:nil URL:nil options:nil
                                   error:&error];
    self.ctx1 = [[NSManagedObjectContext alloc] init];
    [self.ctx1 setPersistentStoreCoordinator:self.psc];
    self.ctx2 = [[NSManagedObjectContext alloc] init];
    [self.ctx2 setPersistentStoreCoordinator:self.psc];
}

- (void)tearDown
{
    self.ctx1 = nil;
    self.ctx2 = nil;
    self.psc = nil;
    self.model = nil;
}

- (NSArray *)fetchAllPeopleInContext:(NSManagedObjectContext *)ctx
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    NSError *error = nil;
    NSArray *result = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    return result;
}

/* Inserts a person via ctx1, saves, and returns ctx2's fully materialized
   copy so both contexts hold a snapshot of the same row. */
- (NSManagedObject *)makeSharedPersonNamed:(NSString *)name
                                    salary:(int)salary
{
    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx1];
    [person setValue:name forKey:@"name"];
    [person setValue:[NSNumber numberWithInt:salary] forKey:@"salary"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    NSArray *people = [self fetchAllPeopleInContext:self.ctx2];
    XCTAssertEqual([people count], (NSUInteger)1);
    NSManagedObject *other = [people objectAtIndex:0];

    /* Materialize ctx2's snapshot before ctx1 makes conflicting changes. */
    XCTAssertEqualObjects([other valueForKey:@"name"], name);
    return other;
}

/* -- merge policy API ----------------------------------------------------- */

- (void)testMergePolicyConstantsExist
{
    XCTAssertNotNil(NSErrorMergePolicy);
    XCTAssertNotNil(NSMergeByPropertyStoreTrumpMergePolicy);
    XCTAssertNotNil(NSMergeByPropertyObjectTrumpMergePolicy);
    XCTAssertNotNil(NSOverwriteMergePolicy);
    XCTAssertNotNil(NSRollbackMergePolicy);

    XCTAssertEqual([NSErrorMergePolicy mergeType],
                   NSErrorMergePolicyType);
    XCTAssertEqual([NSMergeByPropertyStoreTrumpMergePolicy mergeType],
                   NSMergeByPropertyStoreTrumpMergePolicyType);
    XCTAssertEqual([NSMergeByPropertyObjectTrumpMergePolicy mergeType],
                   NSMergeByPropertyObjectTrumpMergePolicyType);
    XCTAssertEqual([NSOverwriteMergePolicy mergeType],
                   NSOverwriteMergePolicyType);
    XCTAssertEqual([NSRollbackMergePolicy mergeType],
                   NSRollbackMergePolicyType);
}

- (void)testDefaultMergePolicyIsErrorPolicy
{
    XCTAssertEqual([self.ctx1 mergePolicy], NSErrorMergePolicy);
}

- (void)testSetMergePolicy
{
    [self.ctx1 setMergePolicy:NSOverwriteMergePolicy];
    XCTAssertEqual([self.ctx1 mergePolicy], NSOverwriteMergePolicy);
}

/* -- did-save notification and cross-context merging ---------------------- */

- (void)testDidSaveNotificationContainsChangeSets
{
    __block NSNotification *received = nil;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextDidSaveNotification
                    object:self.ctx1
                     queue:nil
                usingBlock:^(NSNotification *note) { received = note; }];

    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx1];
    [person setValue:@"Alice" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    XCTAssertNotNil(received);
    NSSet *inserted =
        [[received userInfo] objectForKey:NSInsertedObjectsKey];
    XCTAssertEqual([inserted count], (NSUInteger)1);
    XCTAssertTrue([inserted containsObject:person]);

    [person setValue:@"Alicia" forKey:@"name"];
    received = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    NSSet *updated = [[received userInfo] objectForKey:NSUpdatedObjectsKey];
    XCTAssertEqual([updated count], (NSUInteger)1);
    XCTAssertTrue([updated containsObject:person]);

    [self.ctx1 deleteObject:person];
    received = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    NSSet *deleted = [[received userInfo] objectForKey:NSDeletedObjectsKey];
    XCTAssertEqual([deleted count], (NSUInteger)1);

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testMergeChangesPropagatesUpdatesToOtherContext
{
    NSManagedObject *other = [self makeSharedPersonNamed:@"Alice" salary:10];

    __block NSNotification *received = nil;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextDidSaveNotification
                    object:self.ctx1
                     queue:nil
                usingBlock:^(NSNotification *note) { received = note; }];

    NSManagedObject *person =
        [[self fetchAllPeopleInContext:self.ctx1] objectAtIndex:0];
    [person setValue:@"Alicia" forKey:@"name"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    XCTAssertNotNil(received);
    [self.ctx2 mergeChangesFromContextDidSaveNotification:received];

    XCTAssertEqualObjects([other valueForKey:@"name"], @"Alicia");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testMergeChangesRemovesDeletedObjectsFromOtherContext
{
    NSManagedObject *other = [self makeSharedPersonNamed:@"Alice" salary:10];
    NSManagedObjectID *objectID = [other objectID];

    __block NSNotification *received = nil;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextDidSaveNotification
                    object:self.ctx1
                     queue:nil
                usingBlock:^(NSNotification *note) { received = note; }];

    NSManagedObject *person =
        [[self fetchAllPeopleInContext:self.ctx1] objectAtIndex:0];
    [self.ctx1 deleteObject:person];
    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    XCTAssertNotNil(received);
    [self.ctx2 mergeChangesFromContextDidSaveNotification:received];

    /* Apple keeps the (still referenced) local instance registered as a
       fault; the row is gone, so fetches no longer return it. */
    NSManagedObject *local = [self.ctx2 objectRegisteredForID:objectID];
    XCTAssertNotNil(local);
    XCTAssertTrue([local isFault]);
    XCTAssertEqual([[self fetchAllPeopleInContext:self.ctx2] count],
                   (NSUInteger)0);

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testMergeChangesRegistersInsertedObjectsInOtherContext
{
    __block NSNotification *received = nil;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextDidSaveNotification
                    object:self.ctx1
                     queue:nil
                usingBlock:^(NSNotification *note) { received = note; }];

    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx1];
    [person setValue:@"Alice" forKey:@"name"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    [self.ctx2 mergeChangesFromContextDidSaveNotification:received];

    NSManagedObject *other =
        [self.ctx2 objectRegisteredForID:[person objectID]];
    XCTAssertNotNil(other);
    XCTAssertEqualObjects([other valueForKey:@"name"], @"Alice");

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

/* -- optimistic locking conflicts during -save: ---------------------------- */

- (void)testErrorMergePolicyFailsSaveOnConflict
{
    NSManagedObject *other = [self makeSharedPersonNamed:@"Alice" salary:10];

    NSManagedObject *person =
        [[self fetchAllPeopleInContext:self.ctx1] objectAtIndex:0];
    [person setValue:@"FromCtx1" forKey:@"name"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    [other setValue:@"FromCtx2" forKey:@"name"];
    error = nil;
    XCTAssertFalse([self.ctx2 save:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([error domain], NSCocoaErrorDomain);
    XCTAssertEqual([error code], (NSInteger)NSManagedObjectMergeError);

    NSArray *conflicts =
        [[error userInfo] objectForKey:NSPersistentStoreSaveConflictsErrorKey];
    XCTAssertEqual([conflicts count], (NSUInteger)1);

    NSMergeConflict *conflict = [conflicts objectAtIndex:0];
    XCTAssertEqual([conflict sourceObject], other);
    XCTAssertEqualObjects(
        [[conflict cachedSnapshot] objectForKey:@"name"], @"Alice");
    XCTAssertEqualObjects(
        [[conflict persistedSnapshot] objectForKey:@"name"], @"FromCtx1");
    XCTAssertEqualObjects(
        [[conflict objectSnapshot] objectForKey:@"name"], @"FromCtx2");
}

- (void)testStoreTrumpMergePolicyKeepsPersistedConflictingValues
{
    NSManagedObject *other = [self makeSharedPersonNamed:@"Alice" salary:10];

    NSManagedObject *person =
        [[self fetchAllPeopleInContext:self.ctx1] objectAtIndex:0];
    [person setValue:@"FromCtx1" forKey:@"name"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    [self.ctx2 setMergePolicy:NSMergeByPropertyStoreTrumpMergePolicy];
    [other setValue:@"FromCtx2" forKey:@"name"];
    [other setValue:[NSNumber numberWithInt:99] forKey:@"salary"];
    error = nil;
    XCTAssertTrue([self.ctx2 save:&error], @"save failed: %@", error);

    /* The store's change to `name' trumps; the non-conflicting local
       change to `salary' is preserved. */
    XCTAssertEqualObjects([other valueForKey:@"name"], @"FromCtx1");
    XCTAssertEqual([[other valueForKey:@"salary"] intValue], 99);

    [self.ctx1 refreshObject:person mergeChanges:NO];
    XCTAssertEqualObjects([person valueForKey:@"name"], @"FromCtx1");
    XCTAssertEqual([[person valueForKey:@"salary"] intValue], 99);
}

- (void)testObjectTrumpMergePolicyKeepsInMemoryConflictingValues
{
    NSManagedObject *other = [self makeSharedPersonNamed:@"Alice" salary:10];

    NSManagedObject *person =
        [[self fetchAllPeopleInContext:self.ctx1] objectAtIndex:0];
    [person setValue:@"FromCtx1" forKey:@"name"];
    [person setValue:[NSNumber numberWithInt:50] forKey:@"salary"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    [self.ctx2 setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    [other setValue:@"FromCtx2" forKey:@"name"];
    error = nil;
    XCTAssertTrue([self.ctx2 save:&error], @"save failed: %@", error);

    /* The in-memory change to `name' trumps; the store's change to
       `salary' is preserved. */
    XCTAssertEqualObjects([other valueForKey:@"name"], @"FromCtx2");
    XCTAssertEqual([[other valueForKey:@"salary"] intValue], 50);
}

- (void)testOverwriteMergePolicySavesEntireObject
{
    NSManagedObject *other = [self makeSharedPersonNamed:@"Alice" salary:10];

    NSManagedObject *person =
        [[self fetchAllPeopleInContext:self.ctx1] objectAtIndex:0];
    [person setValue:[NSNumber numberWithInt:77] forKey:@"salary"];
    [person setValue:@"FromCtx1" forKey:@"name"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    [self.ctx2 setMergePolicy:NSOverwriteMergePolicy];
    [other setValue:@"FromCtx2" forKey:@"name"];
    error = nil;
    XCTAssertTrue([self.ctx2 save:&error], @"save failed: %@", error);

    /* The whole in-memory object is written over the persisted version,
       reverting ctx1's salary change too. */
    [self.ctx1 refreshObject:person mergeChanges:NO];
    XCTAssertEqualObjects([person valueForKey:@"name"], @"FromCtx2");
    XCTAssertEqual([[person valueForKey:@"salary"] intValue], 10);
}

- (void)testRollbackMergePolicyDiscardsInMemoryChanges
{
    NSManagedObject *other = [self makeSharedPersonNamed:@"Alice" salary:10];

    NSManagedObject *person =
        [[self fetchAllPeopleInContext:self.ctx1] objectAtIndex:0];
    [person setValue:@"FromCtx1" forKey:@"name"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx1 save:&error], @"save failed: %@", error);

    [self.ctx2 setMergePolicy:NSRollbackMergePolicy];
    [other setValue:@"FromCtx2" forKey:@"name"];
    error = nil;
    XCTAssertTrue([self.ctx2 save:&error], @"save failed: %@", error);

    /* The in-memory change was discarded; the persisted version wins. */
    XCTAssertEqualObjects([other valueForKey:@"name"], @"FromCtx1");
    XCTAssertEqual([[other changedValues] count], (NSUInteger)0);

    [self.ctx1 refreshObject:person mergeChanges:NO];
    XCTAssertEqualObjects([person valueForKey:@"name"], @"FromCtx1");
}

- (void)testNoConflictWhenDifferentObjectsAreChanged
{
    [self makeSharedPersonNamed:@"Alice" salary:10];

    NSManagedObject *bob =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx2];
    [bob setValue:@"Bob" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx2 save:&error], @"save failed: %@", error);
    XCTAssertEqual([[self fetchAllPeopleInContext:self.ctx1] count],
                   (NSUInteger)2);
}

@end
