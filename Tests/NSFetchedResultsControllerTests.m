/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSFetchedResultsControllerTests - tests for the fetched results
   controller.  They are written against Apple's documented behavior so they
   run identically against Apple's CoreData on macOS and against the
   GNUstep port. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

/* Index paths of a fetched results controller carry the section at
   position 0 and the row inside the section at position 1. */
static NSIndexPath *IndexPathForRowInSection(NSUInteger row, NSUInteger section)
{
    NSUInteger indexes[2] = {section, row};

    return [NSIndexPath indexPathWithIndexes:indexes length:2];
}

@interface FetchedResultsRecorder : NSObject <NSFetchedResultsControllerDelegate>

@property (nonatomic, strong) NSMutableArray *objectChanges;
@property (nonatomic, strong) NSMutableArray *sectionChanges;
@property (nonatomic, assign) NSUInteger willChangeCount;
@property (nonatomic, assign) NSUInteger didChangeCount;

- (NSArray *)objectChangesOfType:(NSFetchedResultsChangeType)type;

@end

@implementation FetchedResultsRecorder

- (instancetype)init
{
    if ((self = [super init]) != nil) {
        _objectChanges = [NSMutableArray array];
        _sectionChanges = [NSMutableArray array];
    }
    return self;
}

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller
{
    self.willChangeCount++;
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    self.didChangeCount++;
}

- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath
{
    NSMutableDictionary *change = [NSMutableDictionary dictionary];

    [change setObject:anObject forKey:@"object"];
    [change setObject:[NSNumber numberWithUnsignedInteger:type] forKey:@"type"];
    if (indexPath != nil)
        [change setObject:indexPath forKey:@"indexPath"];
    if (newIndexPath != nil)
        [change setObject:newIndexPath forKey:@"newIndexPath"];

    [self.objectChanges addObject:change];
}

- (void)controller:(NSFetchedResultsController *)controller
  didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex
     forChangeType:(NSFetchedResultsChangeType)type
{
    NSMutableDictionary *change = [NSMutableDictionary dictionary];

    [change setObject:[sectionInfo name] forKey:@"name"];
    [change setObject:[NSNumber numberWithUnsignedInteger:type] forKey:@"type"];
    [change setObject:[NSNumber numberWithUnsignedInteger:sectionIndex] forKey:@"index"];

    [self.sectionChanges addObject:change];
}

- (NSArray *)objectChangesOfType:(NSFetchedResultsChangeType)type
{
    NSMutableArray *result = [NSMutableArray array];

    for (NSDictionary *change in self.objectChanges)
        if ([[change objectForKey:@"type"] unsignedIntegerValue] == type)
            [result addObject:change];

    return result;
}

@end

@interface NSFetchedResultsControllerTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@property (nonatomic, strong) FetchedResultsRecorder *recorder;

@end

@implementation NSFetchedResultsControllerTests

- (NSManagedObjectModel *)employeeModel
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];
    [name setOptional:YES];

    NSAttributeDescription *team = [[NSAttributeDescription alloc] init];
    [team setName:@"team"];
    [team setAttributeType:NSStringAttributeType];
    [team setOptional:YES];

    NSAttributeDescription *salary = [[NSAttributeDescription alloc] init];
    [salary setName:@"salary"];
    [salary setAttributeType:NSInteger32AttributeType];
    [salary setOptional:YES];

    NSEntityDescription *employee = [[NSEntityDescription alloc] init];
    [employee setName:@"Employee"];
    [employee setManagedObjectClassName:@"NSManagedObject"];
    [employee setProperties:[NSArray arrayWithObjects:name, team, salary, nil]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:employee]];

    return model;
}

- (void)setUp
{
    self.model = [self employeeModel];
    self.psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];

    NSError *error = nil;
    XCTAssertNotNil([self.psc addPersistentStoreWithType:NSInMemoryStoreType
                              configuration:nil URL:nil options:nil error:&error],
        @"unable to add the store: %@", error);

    self.ctx = [[NSManagedObjectContext alloc] init];
    [self.ctx setPersistentStoreCoordinator:self.psc];
    self.recorder = [[FetchedResultsRecorder alloc] init];
}

- (void)tearDown
{
    self.recorder = nil;
    self.ctx = nil;
    self.psc = nil;
    self.model = nil;
}

- (NSManagedObject *)insertEmployeeNamed:(NSString *)name
                                    team:(NSString *)team
                                  salary:(int)salary
{
    NSManagedObject *employee =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                             inManagedObjectContext:self.ctx];

    [employee setValue:name forKey:@"name"];
    [employee setValue:team forKey:@"team"];
    [employee setValue:[NSNumber numberWithInt:salary] forKey:@"salary"];

    return employee;
}

- (NSFetchedResultsController *)controllerWithSections:(BOOL)sections
                                             predicate:(NSPredicate *)predicate
{
/* The fixture objects have to be saved before the controller starts
   tracking them.  An object which is still pending insertion stays in the
   inserted objects of the context when it is modified, so a later change to
   it is not reported as an update and the controller does not see it. */
    NSError *saveError = nil;
    XCTAssertTrue([self.ctx save:&saveError], @"save failed: %@", saveError);

    NSFetchRequest *request = [[NSFetchRequest alloc] init];

    [request setEntity:[NSEntityDescription entityForName:@"Employee"
                                            inManagedObjectContext:self.ctx]];
    [request setPredicate:predicate];

    NSMutableArray *sortDescriptors = [NSMutableArray array];

    if (sections)
        [sortDescriptors addObject:
            [[NSSortDescriptor alloc] initWithKey:@"team" ascending:YES]];
    [sortDescriptors addObject:
        [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES]];
    [request setSortDescriptors:sortDescriptors];

    NSFetchedResultsController *controller =
        [[NSFetchedResultsController alloc] initWithFetchRequest:request
                                            managedObjectContext:self.ctx
                                            sectionNameKeyPath:sections ? @"team" : nil
                                            cacheName:nil];

    [controller setDelegate:self.recorder];

    NSError *error = nil;
    XCTAssertTrue([controller performFetch:&error], @"performFetch failed: %@", error);

    return controller;
}

- (void)testPerformFetchReturnsSortedObjects
{
    [self insertEmployeeNamed:@"Carol" team:@"Sales" salary:3];
    [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];
    [self insertEmployeeNamed:@"Bob" team:@"Engineering" salary:2];

    NSFetchedResultsController *controller = [self controllerWithSections:NO predicate:nil];

    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)3);
    XCTAssertEqualObjects([[[controller fetchedObjects] objectAtIndex:0] valueForKey:@"name"], @"Alice");
    XCTAssertEqualObjects([[[controller fetchedObjects] objectAtIndex:2] valueForKey:@"name"], @"Carol");
    XCTAssertEqual([[controller sections] count], (NSUInteger)1);
}

- (void)testSectionsAreBuiltFromTheSectionNameKeyPath
{
    [self insertEmployeeNamed:@"Carol" team:@"Sales" salary:3];
    [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];
    [self insertEmployeeNamed:@"Bob" team:@"Engineering" salary:2];

    NSFetchedResultsController *controller = [self controllerWithSections:YES predicate:nil];

    XCTAssertEqual([[controller sections] count], (NSUInteger)2);

    id <NSFetchedResultsSectionInfo> engineering = [[controller sections] objectAtIndex:0];
    id <NSFetchedResultsSectionInfo> sales = [[controller sections] objectAtIndex:1];

    XCTAssertEqualObjects([engineering name], @"Engineering");
    XCTAssertEqual([engineering numberOfObjects], (NSUInteger)2);
    XCTAssertEqualObjects([sales name], @"Sales");
    XCTAssertEqual([sales numberOfObjects], (NSUInteger)1);
}

- (void)testIndexPathRoundTrip
{
    [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];
    NSManagedObject *carol = [self insertEmployeeNamed:@"Carol" team:@"Sales" salary:3];

    NSFetchedResultsController *controller = [self controllerWithSections:YES predicate:nil];
    NSIndexPath *indexPath = [controller indexPathForObject:carol];

    XCTAssertNotNil(indexPath);
    XCTAssertEqualObjects(indexPath, IndexPathForRowInSection(0, 1));
    XCTAssertEqualObjects([controller objectAtIndexPath:indexPath], carol);
}

- (void)testInsertIsReportedToTheDelegate
{
    [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];

    NSFetchedResultsController *controller = [self controllerWithSections:YES predicate:nil];

    [self insertEmployeeNamed:@"Bob" team:@"Engineering" salary:2];
    [self.ctx processPendingChanges];

    XCTAssertEqual(self.recorder.willChangeCount, (NSUInteger)1);
    XCTAssertEqual(self.recorder.didChangeCount, (NSUInteger)1);

    NSArray *inserts = [self.recorder objectChangesOfType:NSFetchedResultsChangeInsert];
    XCTAssertEqual([inserts count], (NSUInteger)1);
    XCTAssertEqualObjects([[inserts objectAtIndex:0] objectForKey:@"newIndexPath"],
        IndexPathForRowInSection(1, 0));
    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)2);
}

- (void)testInsertOfANewSectionIsReportedToTheDelegate
{
    [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];

    NSFetchedResultsController *controller = [self controllerWithSections:YES predicate:nil];

    [self insertEmployeeNamed:@"Carol" team:@"Sales" salary:3];
    [self.ctx processPendingChanges];

    XCTAssertEqual([self.recorder.sectionChanges count], (NSUInteger)1);

    NSDictionary *change = [self.recorder.sectionChanges objectAtIndex:0];
    XCTAssertEqualObjects([change objectForKey:@"name"], @"Sales");
    XCTAssertEqual([[change objectForKey:@"type"] unsignedIntegerValue],
        (NSUInteger)NSFetchedResultsChangeInsert);
    XCTAssertEqual([[change objectForKey:@"index"] unsignedIntegerValue], (NSUInteger)1);
    XCTAssertEqual([[controller sections] count], (NSUInteger)2);
}

- (void)testDeleteIsReportedToTheDelegate
{
    [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];
    NSManagedObject *bob = [self insertEmployeeNamed:@"Bob" team:@"Engineering" salary:2];

    NSFetchedResultsController *controller = [self controllerWithSections:YES predicate:nil];

    [self.ctx deleteObject:bob];
    [self.ctx processPendingChanges];

    NSArray *deletes = [self.recorder objectChangesOfType:NSFetchedResultsChangeDelete];
    XCTAssertEqual([deletes count], (NSUInteger)1);
    XCTAssertEqualObjects([[deletes objectAtIndex:0] objectForKey:@"indexPath"],
        IndexPathForRowInSection(1, 0));
    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)1);
}

- (void)testUpdateIsReportedToTheDelegate
{
    NSManagedObject *alice = [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];

    NSFetchedResultsController *controller = [self controllerWithSections:YES predicate:nil];

    [alice setValue:[NSNumber numberWithInt:42] forKey:@"salary"];
    [self.ctx processPendingChanges];

    NSArray *updates = [self.recorder objectChangesOfType:NSFetchedResultsChangeUpdate];
    XCTAssertEqual([updates count], (NSUInteger)1);
    XCTAssertEqualObjects([[updates objectAtIndex:0] objectForKey:@"indexPath"],
        IndexPathForRowInSection(0, 0));
    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)1);
}

- (void)testChangingTheSectionMovesTheObject
{
    [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];
    NSManagedObject *bob = [self insertEmployeeNamed:@"Bob" team:@"Engineering" salary:2];

    NSFetchedResultsController *controller = [self controllerWithSections:YES predicate:nil];

    [bob setValue:@"Sales" forKey:@"team"];
    [self.ctx processPendingChanges];

    XCTAssertEqual([[controller sections] count], (NSUInteger)2);
    XCTAssertEqualObjects([controller indexPathForObject:bob], IndexPathForRowInSection(0, 1));

    NSArray *moves = [self.recorder objectChangesOfType:NSFetchedResultsChangeMove];
    XCTAssertEqual([moves count], (NSUInteger)1);
    XCTAssertEqualObjects([[moves objectAtIndex:0] objectForKey:@"indexPath"],
        IndexPathForRowInSection(1, 0));
    XCTAssertEqualObjects([[moves objectAtIndex:0] objectForKey:@"newIndexPath"],
        IndexPathForRowInSection(0, 1));
}

- (void)testObjectNoLongerMatchingThePredicateIsRemoved
{
    NSManagedObject *alice = [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:10];
    [self insertEmployeeNamed:@"Bob" team:@"Engineering" salary:20];

    NSFetchedResultsController *controller =
        [self controllerWithSections:NO
              predicate:[NSPredicate predicateWithFormat:@"salary > 5"]];

    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)2);

    [alice setValue:[NSNumber numberWithInt:1] forKey:@"salary"];
    [self.ctx processPendingChanges];

    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)1);
    XCTAssertEqual([[self.recorder objectChangesOfType:NSFetchedResultsChangeDelete] count],
        (NSUInteger)1);
    XCTAssertNil([controller indexPathForObject:alice]);
}

- (void)testObjectStartingToMatchThePredicateIsInserted
{
    NSManagedObject *alice = [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];
    [self insertEmployeeNamed:@"Bob" team:@"Engineering" salary:20];

    NSFetchedResultsController *controller =
        [self controllerWithSections:NO
              predicate:[NSPredicate predicateWithFormat:@"salary > 5"]];

    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)1);

    [alice setValue:[NSNumber numberWithInt:30] forKey:@"salary"];
    [self.ctx processPendingChanges];

    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)2);
    XCTAssertEqual([[self.recorder objectChangesOfType:NSFetchedResultsChangeInsert] count],
        (NSUInteger)1);
    XCTAssertEqualObjects([controller indexPathForObject:alice], IndexPathForRowInSection(0, 0));
}

- (void)testUnrelatedChangesDoNotNotifyTheDelegate
{
    [self insertEmployeeNamed:@"Alice" team:@"Engineering" salary:1];

    NSFetchedResultsController *controller =
        [self controllerWithSections:NO
              predicate:[NSPredicate predicateWithFormat:@"team == %@", @"Engineering"]];

    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)1);

    [self insertEmployeeNamed:@"Carol" team:@"Sales" salary:3];
    [self.ctx processPendingChanges];

    XCTAssertEqual(self.recorder.willChangeCount, (NSUInteger)0);
    XCTAssertEqual(self.recorder.didChangeCount, (NSUInteger)0);
    XCTAssertEqual([[controller fetchedObjects] count], (NSUInteger)1);
}

@end
