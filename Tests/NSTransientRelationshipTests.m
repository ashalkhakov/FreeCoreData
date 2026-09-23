/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSTransientRelationshipTests - relationships marked transient: kept
   and tracked in memory (inverse maintenance, change tracking,
   surviving a save), never written to or read from the store, and
   invisible to store compatibility.  These compile on macOS against
   Apple CoreData, so every semantic asserted here is arbitrated by
   Apple's implementation. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

@interface NSTransientRelationshipTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSString *storePath;
@property (nonatomic, strong) NSManagedObjectContext *ctx;

@end

@implementation NSTransientRelationshipTests

/* Note{text, cachedSummary(TRANSIENT)} <-tags(TRANSIENT, to-many)->
   Tag{label, owner(TRANSIENT, to-one)}.  When includeTransients is NO
   the same entities carry only the persistent attributes, for the
   compatibility test. */
- (NSManagedObjectModel *)makeModelIncludingTransients:(BOOL)includeTransients
{
    NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
    [text setName:@"text"];
    [text setAttributeType:NSStringAttributeType];
    [text setOptional:YES];

    NSAttributeDescription *label = [[NSAttributeDescription alloc] init];
    [label setName:@"label"];
    [label setAttributeType:NSStringAttributeType];
    [label setOptional:YES];

    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"NSManagedObject"];

    NSEntityDescription *tag = [[NSEntityDescription alloc] init];
    [tag setName:@"Tag"];
    [tag setManagedObjectClassName:@"NSManagedObject"];

    NSMutableArray *noteProperties = [NSMutableArray arrayWithObject:text];
    NSMutableArray *tagProperties = [NSMutableArray arrayWithObject:label];

    if (includeTransients) {
        NSAttributeDescription *summary = [[NSAttributeDescription alloc] init];
        [summary setName:@"cachedSummary"];
        [summary setAttributeType:NSStringAttributeType];
        [summary setOptional:YES];
        [summary setTransient:YES];
        [noteProperties addObject:summary];

        NSRelationshipDescription *tags = [[NSRelationshipDescription alloc] init];
        [tags setName:@"tags"];
        [tags setDestinationEntity:tag];
        [tags setMaxCount:0];
        [tags setOptional:YES];
        [tags setDeleteRule:NSNullifyDeleteRule];
        [tags setTransient:YES];

        NSRelationshipDescription *owner = [[NSRelationshipDescription alloc] init];
        [owner setName:@"owner"];
        [owner setDestinationEntity:note];
        [owner setMaxCount:1];
        [owner setOptional:YES];
        [owner setDeleteRule:NSNullifyDeleteRule];
        [owner setTransient:YES];

        [tags setInverseRelationship:owner];
        [owner setInverseRelationship:tags];
        [noteProperties addObject:tags];
        [tagProperties addObject:owner];
    }

    [note setProperties:noteProperties];
    [tag setProperties:tagProperties];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObjects:note, tag, nil]];
    return model;
}

- (void)setUp
{
    self.model = [self makeModelIncludingTransients:YES];
    self.psc = [[NSPersistentStoreCoordinator alloc]
                   initWithManagedObjectModel:self.model];
    self.storePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"transient-%@.sqlite",
         [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSError *err = nil;
    XCTAssertNotNil([self.psc
        addPersistentStoreWithType:NSSQLiteStoreType
                     configuration:nil
                               URL:[NSURL fileURLWithPath:self.storePath]
                           options:nil
                             error:&err], @"add store: %@", err);

    self.ctx = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [self.ctx setPersistentStoreCoordinator:self.psc];
}

- (void)tearDown
{
    self.ctx = nil;
    for (NSPersistentStore *store in [[self.psc persistentStores] copy])
        [self.psc removePersistentStore:store error:NULL];
    self.psc = nil;
    self.model = nil;
    if (self.storePath) {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:self.storePath error:NULL];
        [fm removeItemAtPath:[self.storePath stringByAppendingString:@"-wal"] error:NULL];
        [fm removeItemAtPath:[self.storePath stringByAppendingString:@"-shm"] error:NULL];
    }
}

/* One note with two tags wired through the transient relationship. */
- (NSManagedObject *)makeTaggedNote
{
    NSManagedObject *note = [NSEntityDescription
        insertNewObjectForEntityForName:@"Note" inManagedObjectContext:self.ctx];
    [note setValue:@"body" forKey:@"text"];

    for (NSString *label in @[ @"red", @"blue" ]) {
        NSManagedObject *tag = [NSEntityDescription
            insertNewObjectForEntityForName:@"Tag" inManagedObjectContext:self.ctx];
        [tag setValue:label forKey:@"label"];
        [[note mutableSetValueForKey:@"tags"] addObject:tag];
    }
    return note;
}

/* ---------------------------------------------------------------- */

- (void)testInverseMaintenanceWorksInMemory
{
    NSManagedObject *note = [self makeTaggedNote];
    NSSet *tags = [note valueForKey:@"tags"];

    XCTAssertEqual([tags count], (NSUInteger)2);
    for (NSManagedObject *tag in tags)
        XCTAssertEqual([tag valueForKey:@"owner"], note,
            @"the transient inverse is maintained like any other");

    NSManagedObject *red = nil;
    for (NSManagedObject *tag in tags)
        if ([[tag valueForKey:@"label"] isEqual:@"red"])
            red = tag;
    [[note mutableSetValueForKey:@"tags"] removeObject:red];
    XCTAssertNil([red valueForKey:@"owner"],
        @"removal clears the transient inverse");
    XCTAssertEqual([[note valueForKey:@"tags"] count], (NSUInteger)1);
}

- (void)testTransientValuesSurviveASave
{
    NSManagedObject *note = [self makeTaggedNote];
    [note setValue:@"two colors" forKey:@"cachedSummary"];

    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);

    XCTAssertEqual([[note valueForKey:@"tags"] count], (NSUInteger)2,
        @"a transient relationship keeps its value across a save");
    XCTAssertEqualObjects([note valueForKey:@"cachedSummary"], @"two colors",
        @"a transient attribute keeps its value across a save");
    XCTAssertFalse([note hasChanges], @"the save cleaned the object");

    /* And across a second save touching something persistent. */
    [note setValue:@"edited" forKey:@"text"];
    XCTAssertTrue([self.ctx save:&err], @"second save: %@", err);
    XCTAssertEqual([[note valueForKey:@"tags"] count], (NSUInteger)2);
    XCTAssertEqualObjects([note valueForKey:@"cachedSummary"], @"two colors");
}

- (void)testTransientChangesCountAsChanges
{
    NSManagedObject *note = [self makeTaggedNote];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);
    XCTAssertFalse([self.ctx hasChanges]);

    [note setValue:@"a summary" forKey:@"cachedSummary"];
    XCTAssertTrue([note hasChanges],
        @"changing a transient property dirties the object");
    /* Arbitrated on macOS: -changedValues reports PERSISTENT
       properties only (as its documentation says) - the transient
       change dirties the object without ever appearing there. */
    XCTAssertNil([[note changedValues] objectForKey:@"cachedSummary"]);
    XCTAssertTrue([self.ctx save:&err], @"save of a transient-only change: %@", err);
    XCTAssertFalse([note hasChanges]);
}

- (void)testTransientRelationshipsAreNotPersisted
{
    [self makeTaggedNote];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);

    /* A separate stack over the same file: the rows are there, the
       transient wiring is not. */
    NSPersistentStoreCoordinator *psc2 = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:self.model];
    XCTAssertNotNil([psc2 addPersistentStoreWithType:NSSQLiteStoreType
                                       configuration:nil
                                                 URL:[NSURL fileURLWithPath:self.storePath]
                                             options:nil
                                               error:&err], @"reopen: %@", err);
    NSManagedObjectContext *fresh = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [fresh setPersistentStoreCoordinator:psc2];

    NSArray *notes = [fresh executeFetchRequest:
        [NSFetchRequest fetchRequestWithEntityName:@"Note"] error:&err];
    NSArray *tags = [fresh executeFetchRequest:
        [NSFetchRequest fetchRequestWithEntityName:@"Tag"] error:&err];
    XCTAssertEqual([notes count], (NSUInteger)1);
    XCTAssertEqual([tags count], (NSUInteger)2,
        @"the tag OBJECTS are persistent; only the relationship is transient");

    XCTAssertEqual([[[notes objectAtIndex:0] valueForKey:@"tags"] count], (NSUInteger)0,
        @"the transient relationship does not come back from the store");
    XCTAssertNil([[tags objectAtIndex:0] valueForKey:@"owner"]);
    XCTAssertNil([[notes objectAtIndex:0] valueForKey:@"cachedSummary"]);

    for (NSPersistentStore *store in [[psc2 persistentStores] copy])
        [psc2 removePersistentStore:store error:NULL];
}

- (void)testRefreshResetsTransientValues
{
    NSManagedObject *note = [self makeTaggedNote];
    [note setValue:@"summary" forKey:@"cachedSummary"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);

    [self.ctx refreshObject:note mergeChanges:NO];

    XCTAssertEqual([[note valueForKey:@"tags"] count], (NSUInteger)0,
        @"a refresh re-faults from the store, which has no transient values");
    XCTAssertNil([note valueForKey:@"cachedSummary"]);
    XCTAssertEqualObjects([note valueForKey:@"text"], @"body",
        @"persistent values come back");
}

- (void)testTransientValuesRideAChildSave
{
    NSManagedObjectContext *child = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [child setParentContext:self.ctx];

    NSManagedObject *note = [NSEntityDescription
        insertNewObjectForEntityForName:@"Note" inManagedObjectContext:child];
    [note setValue:@"from child" forKey:@"text"];
    NSManagedObject *tag = [NSEntityDescription
        insertNewObjectForEntityForName:@"Tag" inManagedObjectContext:child];
    [tag setValue:@"green" forKey:@"label"];
    [[note mutableSetValueForKey:@"tags"] addObject:tag];

    NSError *err = nil;
    XCTAssertTrue([child save:&err], @"child save: %@", err);

    NSArray *parentNotes = [self.ctx executeFetchRequest:
        [NSFetchRequest fetchRequestWithEntityName:@"Note"] error:&err];
    XCTAssertEqual([parentNotes count], (NSUInteger)1, @"%@", err);

    NSSet *parentTags = [[parentNotes objectAtIndex:0] valueForKey:@"tags"];
    XCTAssertEqual([parentTags count], (NSUInteger)1,
        @"the transient relationship rides the child save into the parent");
    XCTAssertEqualObjects([[parentTags anyObject] valueForKey:@"label"], @"green");

    XCTAssertTrue([self.ctx save:&err], @"root save: %@", err);
    XCTAssertEqual([[[parentNotes objectAtIndex:0] valueForKey:@"tags"] count],
                   (NSUInteger)1,
        @"and survives the root save too");
}

- (void)testTransientPropertiesDoNotAffectStoreCompatibility
{
    /* The same two entities without any transient properties hash and
       open identically: adding transients never demands a migration. */
    NSManagedObjectModel *bare = [self makeModelIncludingTransients:NO];

    XCTAssertEqualObjects(
        [[[[self.model entitiesByName] objectForKey:@"Note"] versionHash] description],
        [[[[bare entitiesByName] objectForKey:@"Note"] versionHash] description],
        @"transient properties are not part of the entity version hash");

    /* A store written by the transient-free model opens under the
       transient-bearing one with migration disabled. */
    NSString *barePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"transient-bare-%@.sqlite",
         [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSPersistentStoreCoordinator *writer = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:bare];
    NSError *err = nil;
    XCTAssertNotNil([writer addPersistentStoreWithType:NSSQLiteStoreType
                                         configuration:nil
                                                   URL:[NSURL fileURLWithPath:barePath]
                                               options:nil
                                                 error:&err], @"%@", err);
    for (NSPersistentStore *store in [[writer persistentStores] copy])
        [writer removePersistentStore:store error:NULL];

    NSPersistentStoreCoordinator *reader = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:self.model];
    NSDictionary *noMigration = [NSDictionary
        dictionaryWithObject:[NSNumber numberWithBool:NO]
                      forKey:NSMigratePersistentStoresAutomaticallyOption];
    XCTAssertNotNil([reader addPersistentStoreWithType:NSSQLiteStoreType
                                         configuration:nil
                                                   URL:[NSURL fileURLWithPath:barePath]
                                               options:noMigration
                                                 error:&err],
        @"a store from the transient-free model opens without migration: %@", err);

    for (NSPersistentStore *store in [[reader persistentStores] copy])
        [reader removePersistentStore:store error:NULL];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:barePath error:NULL];
    [fm removeItemAtPath:[barePath stringByAppendingString:@"-wal"] error:NULL];
    [fm removeItemAtPath:[barePath stringByAppendingString:@"-shm"] error:NULL];
}

@end
