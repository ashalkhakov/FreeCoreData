/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSManagedObjectLifecycleTests - managed object life cycle tests:
   awakeFromInsert/awakeFromFetch, willSave/didSave, prepareForDeletion,
   faulting callbacks, state flags, changed/committed values, and
   delete-rule propagation. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

static NSUInteger awakeFromInsertCount;
static NSUInteger awakeFromFetchCount;
static NSUInteger willSaveCount;
static NSUInteger didSaveCount;
static NSUInteger prepareForDeletionCount;
static NSUInteger willTurnIntoFaultCount;
static NSUInteger didTurnIntoFaultCount;

@interface LifecyclePerson : NSManagedObject
- (NSString *)displayName;
@end

@implementation LifecyclePerson

/* Custom accessor for the transient displayName attribute; -valueForKey:
   must dispatch to it instead of reading the (empty) modeled storage. */
- (NSString *)displayName
{
    return [NSString stringWithFormat:@"%@ \"%@\"",
        [self valueForKey:@"name"], [self valueForKey:@"nickname"]];
}

- (void)awakeFromInsert
{
    [super awakeFromInsert];
    awakeFromInsertCount++;
}

- (void)awakeFromFetch
{
    [super awakeFromFetch];
    awakeFromFetchCount++;
}

- (void)willSave
{
    [super willSave];
    willSaveCount++;
}

- (void)didSave
{
    [super didSave];
    didSaveCount++;
}

- (void)prepareForDeletion
{
    [super prepareForDeletion];
    prepareForDeletionCount++;
}

- (void)willTurnIntoFault
{
    [super willTurnIntoFault];
    willTurnIntoFaultCount++;
}

- (void)didTurnIntoFault
{
    [super didTurnIntoFault];
    didTurnIntoFaultCount++;
}

@end

/* Model: Person(name, nickname[default "buddy"]) <->> Pet(name),
   Person.pets uses the Cascade delete rule. */
static NSManagedObjectModel *LifecycleTestModel(void)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];

    NSAttributeDescription *nickname = [[NSAttributeDescription alloc] init];
    [nickname setName:@"nickname"];
    [nickname setAttributeType:NSStringAttributeType];
    [nickname setDefaultValue:@"buddy"];

    NSAttributeDescription *displayName = [[NSAttributeDescription alloc] init];
    [displayName setName:@"displayName"];
    [displayName setAttributeType:NSStringAttributeType];
    [displayName setTransient:YES];
    [displayName setOptional:YES];

    NSAttributeDescription *petName = [[NSAttributeDescription alloc] init];
    [petName setName:@"name"];
    [petName setAttributeType:NSStringAttributeType];

    NSRelationshipDescription *pets =
        [[NSRelationshipDescription alloc] init];
    [pets setName:@"pets"];
    [pets setMinCount:0];
    [pets setMaxCount:0];
    [pets setDeleteRule:NSCascadeDeleteRule];

    NSRelationshipDescription *owner =
        [[NSRelationshipDescription alloc] init];
    [owner setName:@"owner"];
    [owner setMinCount:1];
    [owner setMaxCount:1];

    NSEntityDescription *personEntity = [[NSEntityDescription alloc] init];
    [personEntity setName:@"Person"];
    [personEntity setManagedObjectClassName:@"LifecyclePerson"];
    [personEntity setProperties:
        [NSArray arrayWithObjects:name, nickname, displayName, pets, nil]];

    NSEntityDescription *petEntity = [[NSEntityDescription alloc] init];
    [petEntity setName:@"Pet"];
    [petEntity setManagedObjectClassName:@"NSManagedObject"];
    [petEntity setProperties:[NSArray arrayWithObjects:petName, owner, nil]];

    [pets setDestinationEntity:petEntity];
    [owner setDestinationEntity:personEntity];
    [pets setInverseRelationship:owner];
    [owner setInverseRelationship:pets];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:
        [NSArray arrayWithObjects:personEntity, petEntity, nil]];
    return model;
}

@interface NSManagedObjectLifecycleTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSManagedObjectContext *ctx;

@end

@implementation NSManagedObjectLifecycleTests

- (void)setUp
{
    awakeFromInsertCount = 0;
    awakeFromFetchCount = 0;
    willSaveCount = 0;
    didSaveCount = 0;
    prepareForDeletionCount = 0;
    willTurnIntoFaultCount = 0;
    didTurnIntoFaultCount = 0;

    self.model = LifecycleTestModel();
    self.psc = [[NSPersistentStoreCoordinator alloc]
                   initWithManagedObjectModel:self.model];
    NSError *error = nil;
    [self.psc addPersistentStoreWithType:NSInMemoryStoreType
                           configuration:nil URL:nil options:nil
                                   error:&error];
    self.ctx = [[NSManagedObjectContext alloc] init];
    [self.ctx setPersistentStoreCoordinator:self.psc];
}

- (void)tearDown
{
    self.ctx = nil;
    self.psc = nil;
    self.model = nil;
}

- (NSManagedObject *)insertPersonNamed:(NSString *)name
{
    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:self.ctx];
    [person setValue:name forKey:@"name"];
    return person;
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

/* -- insertion ----------------------------------------------------------- */

- (void)testAwakeFromInsertCalledOnceOnInsertion
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];

    XCTAssertNotNil(person);
    XCTAssertEqual(awakeFromInsertCount, (NSUInteger)1);
    XCTAssertEqual(awakeFromFetchCount, (NSUInteger)0);
}

- (void)testDefaultValuesAreAppliedBeforeAwakeFromInsert
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];

    XCTAssertEqualObjects([person valueForKey:@"nickname"], @"buddy");
}

- (void)testNewlyInsertedObjectStateFlags
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];

    XCTAssertTrue([person isInserted]);
    XCTAssertFalse([person isDeleted]);
    XCTAssertFalse([person isFault]);
    XCTAssertNotNil([person managedObjectContext]);
    XCTAssertTrue([[person objectID] isTemporaryID]);
}

/* -- saving -------------------------------------------------------------- */

- (void)testWillSaveAndDidSaveCalledOnSave
{
    [self insertPersonNamed:@"Alice"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);
    XCTAssertEqual(willSaveCount, (NSUInteger)1);
    XCTAssertEqual(didSaveCount, (NSUInteger)1);
}

- (void)testStateFlagsAfterSave
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    XCTAssertFalse([person isInserted]);
    XCTAssertFalse([person isUpdated]);
    XCTAssertFalse([person isDeleted]);
    XCTAssertFalse([[person objectID] isTemporaryID]);
}

- (void)testIsUpdatedAfterModification
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [person setValue:@"Alicia" forKey:@"name"];
    XCTAssertTrue([person isUpdated]);
    XCTAssertFalse([person isInserted]);

    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);
    XCTAssertFalse([person isUpdated]);
}

- (void)testChangedValuesTracksModificationsAndResetsOnSave
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [person setValue:@"Alicia" forKey:@"name"];
    NSDictionary *changed = [person changedValues];
    XCTAssertEqualObjects([changed objectForKey:@"name"], @"Alicia");

    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);
    XCTAssertEqual([[person changedValues] count], (NSUInteger)0);
    XCTAssertEqualObjects([person valueForKey:@"name"], @"Alicia");
}

- (void)testCommittedValuesForKeysReflectsPersistedState
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [person setValue:@"Alicia" forKey:@"name"];

    /* Committed values reflect the store, not the pending change. */
    NSDictionary *committed = [person committedValuesForKeys:
        [NSArray arrayWithObject:@"name"]];
    XCTAssertEqualObjects([committed objectForKey:@"name"], @"Alice");

    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);
    committed = [person committedValuesForKeys:
        [NSArray arrayWithObject:@"name"]];
    XCTAssertEqualObjects([committed objectForKey:@"name"], @"Alicia");
}

/* -- fetching / faulting -------------------------------------------------- */

- (void)testAwakeFromFetchCalledWhenObjectIsUnfaulted
{
    [self insertPersonNamed:@"Alice"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    /* A second context on the same coordinator faults the object in. */
    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:self.psc];

    awakeFromFetchCount = 0;
    NSArray *people = [self fetchAllPeopleInContext:ctx2];
    XCTAssertEqual([people count], (NSUInteger)1);

    NSManagedObject *fetched = [people objectAtIndex:0];
    XCTAssertEqualObjects([fetched valueForKey:@"name"], @"Alice");
    XCTAssertEqual(awakeFromFetchCount, (NSUInteger)1);
    XCTAssertFalse([fetched isFault]);
}

- (void)testRefreshObjectTurnsObjectBackIntoFault
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [person setValue:@"Alicia" forKey:@"name"];

    willTurnIntoFaultCount = 0;
    didTurnIntoFaultCount = 0;
    [self.ctx refreshObject:person mergeChanges:NO];

    XCTAssertTrue([person isFault]);
    XCTAssertEqual(willTurnIntoFaultCount, (NSUInteger)1);
    XCTAssertEqual(didTurnIntoFaultCount, (NSUInteger)1);

    /* The pending change was discarded; unfaulting reloads store data. */
    XCTAssertEqualObjects([person valueForKey:@"name"], @"Alice");
    XCTAssertFalse([person isFault]);
}

- (void)testRefreshObjectMergingChangesKeepsPendingEdits
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [person setValue:@"Alicia" forKey:@"name"];
    [self.ctx refreshObject:person mergeChanges:YES];

    XCTAssertEqualObjects([person valueForKey:@"name"], @"Alicia");
}

/* -- deletion ------------------------------------------------------------ */

- (void)testPrepareForDeletionCalledOnDelete
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [self.ctx deleteObject:person];
    XCTAssertEqual(prepareForDeletionCount, (NSUInteger)1);
    XCTAssertTrue([person isDeleted]);

    /* Apple re-invokes the callback on a repeated delete. */
    [self.ctx deleteObject:person];
    XCTAssertEqual(prepareForDeletionCount, (NSUInteger)2);
}

- (void)testDeleteAndSaveRemovesObjectFromStore
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [self.ctx deleteObject:person];
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);
    XCTAssertFalse([person isDeleted]);

    XCTAssertEqual([[self fetchAllPeopleInContext:self.ctx] count],
                   (NSUInteger)0);
}

- (void)testCascadeDeleteRulePropagatesToRelatedObjects
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];
    NSManagedObject *pet =
        [NSEntityDescription insertNewObjectForEntityForName:@"Pet"
                                      inManagedObjectContext:self.ctx];
    [pet setValue:@"Rex" forKey:@"name"];
    [pet setValue:person forKey:@"owner"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [self.ctx deleteObject:person];
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Pet"]];
    NSArray *pets = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertEqual([pets count], (NSUInteger)0);
}

/* -- rollback ------------------------------------------------------------ */

- (void)testRollbackDiscardsPendingChanges
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [person setValue:@"Alicia" forKey:@"name"];
    NSManagedObject *doomed = [self insertPersonNamed:@"Bob"];
    [self.ctx deleteObject:person];

    [self.ctx rollback];

    XCTAssertEqual([[self.ctx insertedObjects] count], (NSUInteger)0);
    XCTAssertEqual([[self.ctx updatedObjects] count], (NSUInteger)0);
    XCTAssertEqual([[self.ctx deletedObjects] count], (NSUInteger)0);
    XCTAssertEqualObjects([person valueForKey:@"name"], @"Alice");
    XCTAssertNil([self.ctx objectRegisteredForID:[doomed objectID]]);
}

/* -- custom accessors ----------------------------------------------------- */

- (void)testValueForKeyDispatchesToCustomAccessor
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];

    /* The transient displayName attribute is computed by the accessor
       implemented on LifecyclePerson. */
    XCTAssertEqualObjects([person valueForKey:@"displayName"],
                          @"Alice \"buddy\"");
    /* Attributes without a custom accessor still read modeled storage. */
    XCTAssertEqualObjects([person valueForKey:@"name"], @"Alice");
}

@end
