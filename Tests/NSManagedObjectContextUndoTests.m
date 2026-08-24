/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSManagedObjectContextUndoTests - NSUndoManager integration.

   CoreData registers undo at CHANGE-EVENT granularity: everything that
   happened since the last processPendingChanges undoes as one step -
   attribute changes coalesced to their event-start values, insertions
   removed, deletions resurrected, relationship changes reverted on both
   sides.  Contexts have no undo manager unless one is assigned (Apple
   default since macOS 10.12).  Fault realization (awakeFromFetch)
   registers nothing.  -rollback and -reset clear the undo stack.

   Tests run without a run loop, so NSUndoManager's by-event group
   closing never fires; each test either lets -undo close the one open
   group, or brackets events in explicit begin/endUndoGrouping. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

static NSManagedObjectModel *UndoTestModel(void)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];
    [name setOptional:YES];

    NSAttributeDescription *salary = [[NSAttributeDescription alloc] init];
    [salary setName:@"salary"];
    [salary setAttributeType:NSInteger32AttributeType];
    [salary setOptional:YES];

    NSAttributeDescription *deptName = [[NSAttributeDescription alloc] init];
    [deptName setName:@"name"];
    [deptName setAttributeType:NSStringAttributeType];
    [deptName setOptional:YES];

    NSRelationshipDescription *employees =
        [[NSRelationshipDescription alloc] init];
    [employees setName:@"employees"];
    [employees setMinCount:0];
    [employees setMaxCount:0];
    [employees setOptional:YES];
    [employees setDeleteRule:NSNullifyDeleteRule];

    NSRelationshipDescription *department =
        [[NSRelationshipDescription alloc] init];
    [department setName:@"department"];
    [department setMinCount:0];
    [department setMaxCount:1];
    [department setOptional:YES];
    [department setDeleteRule:NSNullifyDeleteRule];

    NSEntityDescription *employee = [[NSEntityDescription alloc] init];
    [employee setName:@"Employee"];
    [employee setManagedObjectClassName:@"NSManagedObject"];
    [employee setProperties:
        [NSArray arrayWithObjects:name, salary, department, nil]];

    NSEntityDescription *dept = [[NSEntityDescription alloc] init];
    [dept setName:@"Department"];
    [dept setManagedObjectClassName:@"NSManagedObject"];
    [dept setProperties:[NSArray arrayWithObjects:deptName, employees, nil]];

    [employees setDestinationEntity:employee];
    [department setDestinationEntity:dept];
    [employees setInverseRelationship:department];
    [department setInverseRelationship:employees];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObjects:employee, dept, nil]];
    return model;
}

@interface NSManagedObjectContextUndoTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@property (nonatomic, strong) NSUndoManager *um;

@end

@implementation NSManagedObjectContextUndoTests

- (void)setUp
{
    self.model = UndoTestModel();
    self.psc = [[NSPersistentStoreCoordinator alloc]
                   initWithManagedObjectModel:self.model];
    NSError *error = nil;
    [self.psc addPersistentStoreWithType:NSInMemoryStoreType
                           configuration:nil URL:nil options:nil
                                   error:&error];
    XCTAssertNotNil([[self.psc persistentStores] firstObject],
                    @"store add failed: %@", error);
    self.ctx = [[NSManagedObjectContext alloc] init];
    [self.ctx setPersistentStoreCoordinator:self.psc];
    self.um = [[NSUndoManager alloc] init];
}

- (void)tearDown
{
    /* Break the undo stack's references before the context goes away. */
    [self.ctx setUndoManager:nil];
    self.um = nil;
    self.ctx = nil;
    self.psc = nil;
    self.model = nil;
}

- (NSManagedObject *)insertEmployeeNamed:(NSString *)name
{
    NSManagedObject *employee =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:self.ctx];
    [employee setValue:name forKey:@"name"];
    return employee;
}

- (NSManagedObject *)insertDepartmentNamed:(NSString *)name
{
    NSManagedObject *dept =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:self.ctx];
    [dept setValue:name forKey:@"name"];
    return dept;
}

- (void)saveContext
{
    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);
}

- (NSUInteger)countOfEntity:(NSString *)entityName
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:entityName]];
    NSError *error = nil;
    NSArray *result = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    return [result count];
}

/* Contexts have no undo manager unless assigned one (Apple default
   since macOS 10.12 / all of iOS). */
- (void)testUndoManagerIsNilByDefault
{
    XCTAssertNil([self.ctx undoManager]);
}

- (void)testUndoWithoutUndoManagerIsANoOp
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [self.ctx processPendingChanges];
    [self.ctx undo];
    [self.ctx redo];
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Alice");
}

- (void)testAttributeChangeUndoAndRedo
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [self saveContext];

    [self.ctx setUndoManager:self.um];

    [employee setValue:@"Bob" forKey:@"name"];
    [self.ctx processPendingChanges];

    [self.ctx undo];
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Alice");

    [self.ctx redo];
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Bob");
}

/* All changes between two processPendingChanges undo as one step, and a
   key changed twice restores its event-start value. */
- (void)testEventCoalescesToOneUndoStep
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [employee setValue:[NSNumber numberWithInt:100] forKey:@"salary"];
    [self saveContext];

    [self.ctx setUndoManager:self.um];

    [employee setValue:@"Bob" forKey:@"name"];
    [employee setValue:@"Carol" forKey:@"name"];
    [employee setValue:[NSNumber numberWithInt:200] forKey:@"salary"];
    [self.ctx processPendingChanges];

    [self.ctx undo];
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Alice");
    XCTAssertEqualObjects([employee valueForKey:@"salary"],
                          [NSNumber numberWithInt:100]);
}

- (void)testSeparateEventsUndoSeparately
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [self saveContext];

    /* With groupsByEvent (the default), an explicit beginUndoGrouping
       at level 0 first opens the automatic event group and nests inside
       it - and without a run loop that outer group never closes, so
       every "event" would coalesce into one undo step.  Discrete steps
       without a run loop require explicit grouping only. */
    [self.um setGroupsByEvent:NO];
    [self.ctx setUndoManager:self.um];

    [self.um beginUndoGrouping];
    [employee setValue:@"Bob" forKey:@"name"];
    [self.ctx processPendingChanges];
    [self.um endUndoGrouping];

    [self.um beginUndoGrouping];
    [employee setValue:@"Carol" forKey:@"name"];
    [self.ctx processPendingChanges];
    [self.um endUndoGrouping];

    [self.ctx undo];
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Bob");

    [self.ctx undo];
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Alice");
}

- (void)testInsertUndoRemovesObjectAndRedoRestoresIt
{
    [self.ctx setUndoManager:self.um];

    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [self.ctx processPendingChanges];
    XCTAssertEqual([[self.ctx insertedObjects] count], (NSUInteger)1);

    [self.ctx undo];
    XCTAssertEqual([[self.ctx insertedObjects] count], (NSUInteger)0);
    XCTAssertEqual([self countOfEntity:@"Employee"], (NSUInteger)0);

    [self.ctx redo];
    XCTAssertEqual([self countOfEntity:@"Employee"], (NSUInteger)1);
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Alice");
    [self saveContext];
}

- (void)testDeleteUndoBeforeSaveRestoresObject
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [self saveContext];

    [self.ctx setUndoManager:self.um];

    [self.ctx deleteObject:employee];
    [self.ctx processPendingChanges];
    XCTAssertTrue([employee isDeleted]);

    [self.ctx undo];
    XCTAssertFalse([employee isDeleted]);
    XCTAssertEqual([[self.ctx deletedObjects] count], (NSUInteger)0);
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Alice");
    XCTAssertEqual([self countOfEntity:@"Employee"], (NSUInteger)1);

    [self.ctx redo];
    XCTAssertTrue([employee isDeleted]);
    [self saveContext];
    XCTAssertEqual([self countOfEntity:@"Employee"], (NSUInteger)0);
}

/* Undoing past a save: the deletion has hit the store, so undo brings
   the object back as a new insertion carrying its old values, and the
   next save persists it again. */
- (void)testDeleteUndoAfterSaveResurrectsObject
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [employee setValue:[NSNumber numberWithInt:100] forKey:@"salary"];
    [self saveContext];

    [self.ctx setUndoManager:self.um];

    [self.ctx deleteObject:employee];
    [self.ctx processPendingChanges];
    [self saveContext];
    XCTAssertEqual([self countOfEntity:@"Employee"], (NSUInteger)0);

    [self.ctx undo];
    [self saveContext];
    XCTAssertEqual([self countOfEntity:@"Employee"], (NSUInteger)1);

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Employee"]];
    NSError *error = nil;
    NSManagedObject *fetched =
        [[self.ctx executeFetchRequest:fetch error:&error] firstObject];
    XCTAssertEqualObjects([fetched valueForKey:@"name"], @"Alice");
    XCTAssertEqualObjects([fetched valueForKey:@"salary"],
                          [NSNumber numberWithInt:100]);
}

- (void)testToOneRelationshipUndoRestoresBothSides
{
    NSManagedObject *sales = [self insertDepartmentNamed:@"Sales"];
    NSManagedObject *hr = [self insertDepartmentNamed:@"HR"];
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [employee setValue:sales forKey:@"department"];
    [self saveContext];

    [self.ctx setUndoManager:self.um];

    [employee setValue:hr forKey:@"department"];
    [self.ctx processPendingChanges];
    XCTAssertEqualObjects([employee valueForKey:@"department"], hr);

    [self.ctx undo];
    XCTAssertEqualObjects([employee valueForKey:@"department"], sales);
    XCTAssertTrue([[sales valueForKey:@"employees"] containsObject:employee]);
    XCTAssertFalse([[hr valueForKey:@"employees"] containsObject:employee]);

    [self.ctx redo];
    XCTAssertEqualObjects([employee valueForKey:@"department"], hr);
    XCTAssertTrue([[hr valueForKey:@"employees"] containsObject:employee]);
    XCTAssertFalse([[sales valueForKey:@"employees"] containsObject:employee]);
}

/* Mutations through the mutable-collection proxy funnel through the
   same change paths and must be equally undoable. */
- (void)testToManyProxyMutationUndo
{
    NSManagedObject *sales = [self insertDepartmentNamed:@"Sales"];
    NSManagedObject *alice = [self insertEmployeeNamed:@"Alice"];
    NSManagedObject *bob = [self insertEmployeeNamed:@"Bob"];
    [alice setValue:sales forKey:@"department"];
    [self saveContext];

    [self.ctx setUndoManager:self.um];

    [[sales mutableSetValueForKey:@"employees"] addObject:bob];
    [self.ctx processPendingChanges];
    XCTAssertEqual([[sales valueForKey:@"employees"] count], (NSUInteger)2);

    [self.ctx undo];
    XCTAssertEqual([[sales valueForKey:@"employees"] count], (NSUInteger)1);
    XCTAssertTrue([[sales valueForKey:@"employees"] containsObject:alice]);
    XCTAssertNil([bob valueForKey:@"department"]);

    [self.ctx redo];
    XCTAssertEqual([[sales valueForKey:@"employees"] count], (NSUInteger)2);
    XCTAssertEqualObjects([bob valueForKey:@"department"], sales);
}

/* Firing a fault realizes stored values; nothing about that is a
   user-visible change, so it must not create undo work. */
- (void)testFaultFiringRegistersNoUndo
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [self saveContext];
    NSManagedObjectID *objectID = [employee objectID];

    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:self.psc];
    NSUndoManager *um2 = [[NSUndoManager alloc] init];
    [ctx2 setUndoManager:um2];

    NSManagedObject *fault = [ctx2 objectWithID:objectID];
    XCTAssertEqualObjects([fault valueForKey:@"name"], @"Alice");
    [ctx2 processPendingChanges];

    XCTAssertFalse([um2 canUndo]);
    [ctx2 setUndoManager:nil];
}

- (void)testRollbackClearsUndoStack
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [self saveContext];

    [self.ctx setUndoManager:self.um];

    [employee setValue:@"Bob" forKey:@"name"];
    [self.ctx processPendingChanges];
    XCTAssertTrue([self.um canUndo]);

    [self.ctx rollback];
    XCTAssertFalse([self.um canUndo]);
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Alice");
}

- (void)testResetClearsUndoStack
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [self saveContext];

    [self.ctx setUndoManager:self.um];

    [employee setValue:@"Bob" forKey:@"name"];
    [self.ctx processPendingChanges];
    XCTAssertTrue([self.um canUndo]);

    [self.ctx reset];
    XCTAssertFalse([self.um canUndo]);
}

/* Undo works across a save of UPDATES: undoing restores the pre-save
   values as pending changes, and saving again persists them. */
- (void)testUndoAcrossSaveOfUpdates
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [self saveContext];

    [self.ctx setUndoManager:self.um];

    [employee setValue:@"Bob" forKey:@"name"];
    [self.ctx processPendingChanges];
    [self saveContext];

    [self.ctx undo];
    XCTAssertEqualObjects([employee valueForKey:@"name"], @"Alice");
    XCTAssertTrue([[self.ctx updatedObjects] containsObject:employee]);
    [self saveContext];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Employee"]];
    NSError *error = nil;
    NSManagedObject *fetched =
        [[self.ctx executeFetchRequest:fetch error:&error] firstObject];
    XCTAssertEqualObjects([fetched valueForKey:@"name"], @"Alice");
}

@end
