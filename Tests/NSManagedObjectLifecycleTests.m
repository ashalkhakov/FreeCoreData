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

/* A plain @dynamic subclass over a PROGRAMMATICALLY built model - the
   framework must synthesize these accessors no matter how the model
   was constructed (they historically existed only for models decoded
   from a compiled file, so pda.sourceText raised
   doesNotRecognizeSelector; found by the Doom3 PDA editor project). */
@interface DynamicPDA : NSManagedObject

@property (nonatomic, strong) NSString *sourceText;
@property (nonatomic, strong) DynamicPDA *linked;

@end

@implementation DynamicPDA

@dynamic sourceText, linked;

@end

/* Scalar-typed @dynamic properties - the synthesized accessors must
   match the DECLARED ABI instead of boxing through object-typed IMPs: a
   float getter returning an NSNumber pointer in the integer register
   leaves the caller reading garbage from the FP register, and a BOOL
   getter reading the pointer's low byte is almost always YES.  KVC was
   unaffected, which masked the bug (reported by UDQuakeTools). */
@interface ScalarSettings : NSManagedObject

@property (nonatomic) float depthHack;
@property (nonatomic) double ratio;
@property (nonatomic) BOOL enabled;
@property (nonatomic) int32_t hitCount;
@property (nonatomic) int64_t bigCount;
@property (nonatomic, strong) NSString *label;

@end

@implementation ScalarSettings

@dynamic depthHack, ratio, enabled, hitCount, bigCount, label;

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

/* Direct property messages on a @dynamic subclass, model built in
   code (never through initWithCoder:). */
- (void)testDynamicAccessorsOnProgrammaticModel
{
    NSAttributeDescription *sourceText =
        [[NSAttributeDescription alloc] init];
    [sourceText setName:@"sourceText"];
    [sourceText setAttributeType:NSStringAttributeType];
    [sourceText setOptional:YES];

    NSRelationshipDescription *linked =
        [[NSRelationshipDescription alloc] init];
    [linked setName:@"linked"];
    [linked setMinCount:0];
    [linked setMaxCount:1];
    [linked setOptional:YES];
    [linked setDeleteRule:NSNullifyDeleteRule];

    NSEntityDescription *pdaEntity = [[NSEntityDescription alloc] init];
    [pdaEntity setName:@"PDA"];
    [pdaEntity setManagedObjectClassName:@"DynamicPDA"];
    [pdaEntity setProperties:
        [NSArray arrayWithObjects:sourceText, linked, nil]];
    [linked setDestinationEntity:pdaEntity];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:pdaEntity]];

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store, @"failed to add store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    DynamicPDA *pda = (DynamicPDA *)
        [NSEntityDescription insertNewObjectForEntityForName:@"PDA"
                                      inManagedObjectContext:ctx];
    DynamicPDA *other = (DynamicPDA *)
        [NSEntityDescription insertNewObjectForEntityForName:@"PDA"
                                      inManagedObjectContext:ctx];

    /* The direct sends that used to raise doesNotRecognizeSelector. */
    pda.sourceText = @"personal data assistant";
    other.sourceText = @"other";
    pda.linked = other;

    XCTAssertEqualObjects(pda.sourceText, @"personal data assistant");
    XCTAssertEqualObjects(pda.linked, other);

    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* And they read persisted state through a fresh context. */
    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"PDA"
                                 inManagedObjectContext:ctx2]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:
        @"sourceText == %@", @"personal data assistant"]];

    NSArray *fetched = [ctx2 executeFetchRequest:fetch error:&error];
    XCTAssertEqual([fetched count], (NSUInteger)1);

    DynamicPDA *reloaded = [fetched lastObject];
    XCTAssertEqualObjects(reloaded.sourceText, @"personal data assistant");
    XCTAssertEqualObjects(reloaded.linked.sourceText, @"other");
}

/* Scalar-typed @dynamic properties read and write correctly through
   direct property syntax - the synthesized IMPs must match the
   declared ABI (float returned in the FP register, etc.), not box
   everything as objects.  The UDQuakeTools repro: a Float attribute
   defaulting to 1.5 read 1.5 via KVC but garbage via the property. */
- (void)testScalarDynamicAccessors
{
    NSAttributeDescription *depthHack = [[NSAttributeDescription alloc] init];
    [depthHack setName:@"depthHack"];
    [depthHack setAttributeType:NSFloatAttributeType];
    [depthHack setDefaultValue:[NSNumber numberWithFloat:1.5f]];
    [depthHack setOptional:YES];

    NSAttributeDescription *ratio = [[NSAttributeDescription alloc] init];
    [ratio setName:@"ratio"];
    [ratio setAttributeType:NSDoubleAttributeType];
    [ratio setOptional:YES];

    NSAttributeDescription *enabled = [[NSAttributeDescription alloc] init];
    [enabled setName:@"enabled"];
    [enabled setAttributeType:NSBooleanAttributeType];
    [enabled setOptional:YES];

    NSAttributeDescription *hitCount = [[NSAttributeDescription alloc] init];
    [hitCount setName:@"hitCount"];
    [hitCount setAttributeType:NSInteger32AttributeType];
    [hitCount setOptional:YES];

    NSAttributeDescription *bigCount = [[NSAttributeDescription alloc] init];
    [bigCount setName:@"bigCount"];
    [bigCount setAttributeType:NSInteger64AttributeType];
    [bigCount setOptional:YES];

    NSAttributeDescription *label = [[NSAttributeDescription alloc] init];
    [label setName:@"label"];
    [label setAttributeType:NSStringAttributeType];
    [label setOptional:YES];

    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:@"Settings"];
    [entity setManagedObjectClassName:@"ScalarSettings"];
    [entity setProperties:[NSArray arrayWithObjects:
        depthHack, ratio, enabled, hitCount, bigCount, label, nil]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:entity]];

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store, @"failed to add store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    ScalarSettings *settings = (ScalarSettings *)
        [NSEntityDescription insertNewObjectForEntityForName:@"Settings"
                                      inManagedObjectContext:ctx];

    /* The repro itself: the modeled default must come back through the
       property exactly as it does through KVC. */
    XCTAssertEqual(settings.depthHack, 1.5f);
    XCTAssertEqual([[settings valueForKey:@"depthHack"] floatValue], 1.5f);

    /* Unset scalar properties read as zero/NO, not as the low bits of
       an NSNumber pointer (the old BOOL bug: almost always YES). */
    XCTAssertFalse(settings.enabled);
    XCTAssertEqual(settings.ratio, 0.0);
    XCTAssertEqual(settings.hitCount, (int32_t)0);

    settings.depthHack = 0.25f;
    settings.ratio = 2.75;
    settings.enabled = YES;
    settings.hitCount = -42;
    settings.bigCount = 1LL << 40;
    settings.label = @"pda";

    XCTAssertEqual(settings.depthHack, 0.25f);
    XCTAssertEqual(settings.ratio, 2.75);
    XCTAssertTrue(settings.enabled);
    XCTAssertEqual(settings.hitCount, (int32_t)-42);
    XCTAssertEqual(settings.bigCount, (int64_t)(1LL << 40));
    XCTAssertEqualObjects(settings.label, @"pda");

    /* Property writes and KVC reads agree (and vice versa). */
    XCTAssertEqualObjects([settings valueForKey:@"ratio"],
                          [NSNumber numberWithDouble:2.75]);
    [settings setValue:[NSNumber numberWithInt:7] forKey:@"hitCount"];
    XCTAssertEqual(settings.hitCount, (int32_t)7);

    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* Persisted values come back through the typed accessors in a
       fresh context. */
    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Settings"
                                 inManagedObjectContext:ctx2]];

    ScalarSettings *reloadedSettings =
        [[ctx2 executeFetchRequest:fetch error:&error] lastObject];
    XCTAssertNotNil(reloadedSettings, @"fetch failed: %@", error);
    XCTAssertEqual(reloadedSettings.depthHack, 0.25f);
    XCTAssertEqual(reloadedSettings.ratio, 2.75);
    XCTAssertTrue(reloadedSettings.enabled);
    XCTAssertEqual(reloadedSettings.hitCount, (int32_t)7);
    XCTAssertEqual(reloadedSettings.bigCount, (int64_t)(1LL << 40));
    XCTAssertEqualObjects(reloadedSettings.label, @"pda");
}

/* The to-many set returned by -valueForKey: is mutable, and mutating
   it edits the relationship through the model - change tracking and
   inverse maintenance included.  This is the NSArrayController
   contentSet-binding scenario from UDQuakeTools: GNUstep's
   -[NSArrayController remove:] mutates the bound collection in place,
   which used to raise doesNotRecognizeSelector on the immutable
   relationship set and wedge the app mid-event.  Apple's relationship
   set (_NSFaultingMutableSet) accepts the same mutations. */
- (void)testToManyRelationshipSetIsMutable
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];
    NSManagedObject *pet1 =
        [NSEntityDescription insertNewObjectForEntityForName:@"Pet"
                                      inManagedObjectContext:self.ctx];
    [pet1 setValue:@"Rex" forKey:@"name"];
    [pet1 setValue:person forKey:@"owner"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    NSMutableSet *pets = (NSMutableSet *)[person valueForKey:@"pets"];
    XCTAssertTrue([pets isKindOfClass:[NSMutableSet class]]);
    XCTAssertEqual([pets count], (NSUInteger)1);

    /* -member: answers with the managed object itself. */
    XCTAssertEqualObjects([pets member:pet1], pet1);
    XCTAssertTrue([pets containsObject:pet1]);

    /* The "+" flow: add through the collection. */
    NSManagedObject *pet2 =
        [NSEntityDescription insertNewObjectForEntityForName:@"Pet"
                                      inManagedObjectContext:self.ctx];
    [pet2 setValue:@"Fido" forKey:@"name"];
    [pets addObject:pet2];

    XCTAssertEqual([pets count], (NSUInteger)2);
    XCTAssertTrue([pets containsObject:pet2]);

#if defined(__APPLE__)
    /* Mac-verified: Apple's faulting set ACCEPTS in-place mutation but
       silently bypasses change processing - the inverse is not
       maintained and the owner is not marked updated (the footgun the
       docs warn about; mutableSetValueForKey: is the tracked channel).
       The port deliberately diverges by routing in-place mutations
       through the model: GNUstep's NSArrayController mutates a bound
       contentSet in place, and Apple's untracked semantics there would
       mean edits that never save. */
    XCTAssertNil([pet2 valueForKey:@"owner"]);
    XCTAssertFalse([person isUpdated]);

    [pets removeObject:pet2];
    XCTAssertEqual([pets count], (NSUInteger)1);
    XCTAssertTrue([pets containsObject:pet1]);
#else
    /* The port routes the mutation through -setValue:forKey:, so the
       inverse is wired and the change is tracked. */
    XCTAssertEqualObjects([pet2 valueForKey:@"owner"], person);
    XCTAssertTrue([person isUpdated]);

    /* The "-" flow that used to hang: remove the selected row through
       the same collection. */
    [pets removeObject:pet2];

    XCTAssertEqual([pets count], (NSUInteger)1);
    XCTAssertTrue([pets containsObject:pet1]);
    XCTAssertNil([pet2 valueForKey:@"owner"]);

    /* Removing a non-member is a no-op, not an error. */
    [pets removeObject:pet2];
    XCTAssertEqual([pets count], (NSUInteger)1);
#endif

    /* pet2 is detached but still inserted; discard it so the save does
       not trip owner's minCount validation. */
    [self.ctx deleteObject:pet2];

    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:self.psc];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    NSManagedObject *reloaded =
        [[ctx2 executeFetchRequest:fetch error:&error] lastObject];
    NSSet *reloadedPets = [reloaded valueForKey:@"pets"];
    XCTAssertEqual([reloadedPets count], (NSUInteger)1);
    XCTAssertEqualObjects(
        [[reloadedPets anyObject] valueForKey:@"name"], @"Rex");
}

/* Pending changes process on an ordinary run loop turn - the
   objects-did-change notification must not wait for an explicit
   -processPendingChanges or a save.  (The port's deferred processing
   was filed under NSRunLoopCommonModes, which GNUstep's run loop
   matches literally, so the performer never fired; reported by
   UDQuakeTools.) */
- (void)testPendingChangesProcessOnRunLoopTurn
{
    NSManagedObject *person = [self insertPersonNamed:@"Alice"];
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    __block BOOL notified = NO;
    __block BOOL personListed = NO;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                    object:self.ctx
                     queue:nil
                usingBlock:^(NSNotification *note) {
        notified = YES;
        personListed = [[[note userInfo]
            objectForKey:NSUpdatedObjectsKey] containsObject:person];
    }];

    [person setValue:@"Bob" forKey:@"name"];

    /* No explicit processPendingChanges - just turn the run loop. */
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (!notified && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop mainRunLoop]
            runMode:NSDefaultRunLoopMode
         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];

    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    XCTAssertTrue(notified,
        @"objects-did-change never fired on a run loop turn");
    XCTAssertTrue(personListed);
}

@end
