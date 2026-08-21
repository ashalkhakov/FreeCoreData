/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSPendingChangesFetchTests - the result-type-aware pending-change
   overlay: the store answers with the last saved state, then the
   context patches membership with this context's unsaved inserts,
   updates and deletes, and emits the answer in the shape resultType
   asked for.  These tests are written against Apple's documented
   behavior so they run identically against Apple's CoreData on macOS
   and against the GNUstep port.

   The fixture mirrors an "unsaved edits vs a filtered fetch" scenario:
   saved rows alpha(22), bravo(25), charlie(10); pending: alpha updated
   to 5 (falls out of `salary > 20`), charlie updated to 21 (falls IN),
   bravo deleted, delta(30) and echo(40) inserted.  The merged
   membership for `salary > 20` is {charlie, delta, echo}; the saved
   membership is {alpha, bravo}.

   Documented Apple behavior encoded here:
   - includesPendingChanges defaults to YES and controls the overlay;
     NO returns only what "matched the predicate in the persistent
     store" (values shown by returned managed objects are still the
     context's in-memory ones - membership and values are separate).
   - NSDictionaryResultType never reflects pending changes: "the array
     returned from the fetch reflects the current state in the
     persistent store" (includesPendingChanges YES is documented as
     unsupported for dictionaries).
   - Counts reflect the same membership the equivalent object fetch
     would return.
   - Sorting and fetchLimit/fetchOffset apply to the merged result. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"

@interface NSPendingChangesFetchTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;
@property (nonatomic, strong) NSManagedObjectContext *ctx;
@property (nonatomic, strong) NSManagedObject *alpha;
@property (nonatomic, strong) NSManagedObject *bravo;
@property (nonatomic, strong) NSManagedObject *charlie;

@end

@implementation NSPendingChangesFetchTests

- (void)setUp
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"store"];
    self.storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
}

- (void)tearDown
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    [fileManager removeItemAtURL:self.storeURL error:NULL];
    [fileManager removeItemAtPath:[[self.storeURL path]
                                      stringByAppendingString:@"-wal"]
                            error:NULL];
    [fileManager removeItemAtPath:[[self.storeURL path]
                                      stringByAppendingString:@"-shm"]
                            error:NULL];
    self.storeURL = nil;
    self.ctx = nil;
    self.alpha = nil;
    self.bravo = nil;
    self.charlie = nil;
}

- (NSManagedObjectContext *)contextWithStoreType:(NSString *)storeType
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV1()];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:storeType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to add %@ store: %@", storeType, error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

- (NSManagedObject *)insertEmployeeNamed:(NSString *)name
                                  salary:(int)salary
                               inContext:(NSManagedObjectContext *)ctx
{
    NSManagedObject *employee =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx];
    [employee setValue:name forKey:@"name"];
    [employee setValue:[NSNumber numberWithInt:salary] forKey:@"salary"];
    return employee;
}

/* Saves alpha/bravo/charlie, then applies the unsaved edits described
   in the header comment, leaving the context dirty. */
- (void)buildDirtyFixture
{
    self.ctx = [self contextWithStoreType:NSSQLiteStoreType];

    self.alpha = [self insertEmployeeNamed:@"alpha" salary:22
                                 inContext:self.ctx];
    self.bravo = [self insertEmployeeNamed:@"bravo" salary:25
                                 inContext:self.ctx];
    self.charlie = [self insertEmployeeNamed:@"charlie" salary:10
                                   inContext:self.ctx];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [self.alpha setValue:[NSNumber numberWithInt:5] forKey:@"salary"];
    [self.charlie setValue:[NSNumber numberWithInt:21] forKey:@"salary"];
    [self.ctx deleteObject:self.bravo];
    [self insertEmployeeNamed:@"delta" salary:30 inContext:self.ctx];
    [self insertEmployeeNamed:@"echo" salary:40 inContext:self.ctx];
}

- (NSFetchRequest *)matchingRequestWithResultType:(NSFetchRequestResultType)type
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Employee"
                                 inManagedObjectContext:self.ctx]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"salary > 20"]];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
    [fetch setResultType:type];
    return fetch;
}

- (NSArray *)namesOfObjects:(NSArray *)objects
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSManagedObject *object in objects)
        [names addObject:[object valueForKey:@"name"]];
    return names;
}

/* ------------------------------------------------------------------ */
#pragma mark - Objects
/* ------------------------------------------------------------------ */

- (void)testObjectFetchAppliesPendingOverlay
{
    [self buildDirtyFixture];

    NSError *error = nil;
    NSArray *result = [self.ctx executeFetchRequest:
        [self matchingRequestWithResultType:NSManagedObjectResultType]
                                              error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);

    /* bravo dropped (deleted), alpha dropped (updated out of the
       predicate), charlie added (updated INTO the predicate), delta and
       echo added (unsaved inserts). */
    XCTAssertEqualObjects([self namesOfObjects:result],
        ([NSArray arrayWithObjects:@"charlie", @"delta", @"echo", nil]));

    /* Values are the in-memory ones. */
    XCTAssertEqual([[[result objectAtIndex:0] valueForKey:@"salary"]
                       intValue], 21);
}

- (void)testIncludesPendingChangesNOReturnsSavedMembership
{
    [self buildDirtyFixture];

    NSFetchRequest *fetch =
        [self matchingRequestWithResultType:NSManagedObjectResultType];
    [fetch setIncludesPendingChanges:NO];

    NSError *error = nil;
    NSArray *result = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);

    /* Membership is the store's saved answer... */
    XCTAssertEqualObjects([self namesOfObjects:result],
        ([NSArray arrayWithObjects:@"alpha", @"bravo", nil]));

    /* ...while the returned objects still show this context's unsaved
       values - membership and values are separate questions. */
    XCTAssertEqual([[[result objectAtIndex:0] valueForKey:@"salary"]
                       intValue], 5);
}

/* ------------------------------------------------------------------ */
#pragma mark - Object IDs
/* ------------------------------------------------------------------ */

- (void)testObjectIDFetchAppliesPendingOverlay
{
    [self buildDirtyFixture];

    NSError *error = nil;
    NSArray *result = [self.ctx executeFetchRequest:
        [self matchingRequestWithResultType:NSManagedObjectIDResultType]
                                              error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    XCTAssertEqual([result count], (NSUInteger)3);

    for (id entry in result)
        XCTAssertTrue([entry isKindOfClass:[NSManagedObjectID class]],
                      @"got %@", [entry class]);

    /* Same membership as the object fetch: charlie's saved ID plus the
       two unsaved inserts, whose IDs are still temporary.  Ordering is
       deliberately not asserted: verified on macOS, Apple does not
       apply the sort descriptors to the overlay-only portion of an ID
       fetch (the saved row's ID came last despite the name sort). */
    XCTAssertTrue([result containsObject:[self.charlie objectID]]);
    XCTAssertFalse([result containsObject:[self.alpha objectID]]);
    XCTAssertFalse([result containsObject:[self.bravo objectID]]);

    NSUInteger temporary = 0;
    for (NSManagedObjectID *entry in result)
        if ([entry isTemporaryID])
            temporary++;
    XCTAssertEqual(temporary, (NSUInteger)2,
                   @"the two unsaved inserts carry temporary IDs");
}

/* ------------------------------------------------------------------ */
#pragma mark - Counts
/* ------------------------------------------------------------------ */

- (void)testCountFetchAppliesPendingOverlay
{
    [self buildDirtyFixture];

    NSError *error = nil;
    NSArray *result = [self.ctx executeFetchRequest:
        [self matchingRequestWithResultType:NSCountResultType]
                                              error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    XCTAssertEqual([result count], (NSUInteger)1);
    XCTAssertEqual([[result lastObject] unsignedIntegerValue],
                   (NSUInteger)3);

    XCTAssertEqual([self.ctx countForFetchRequest:
        [self matchingRequestWithResultType:NSManagedObjectResultType]
                                            error:&error],
                   (NSUInteger)3);

    /* The saved picture is still one flag away. */
    NSFetchRequest *savedCount =
        [self matchingRequestWithResultType:NSCountResultType];
    [savedCount setIncludesPendingChanges:NO];
    result = [self.ctx executeFetchRequest:savedCount error:&error];
    XCTAssertEqual([[result lastObject] unsignedIntegerValue],
                   (NSUInteger)2);
}

/* ------------------------------------------------------------------ */
#pragma mark - Dictionaries
/* ------------------------------------------------------------------ */

- (void)testDictionaryFetchReflectsStoreOnly
{
    [self buildDirtyFixture];

    /* Documented Apple behavior: dictionary results always reflect the
       persistent store; pending changes are never merged in. */
    NSFetchRequest *fetch =
        [self matchingRequestWithResultType:NSDictionaryResultType];
    [fetch setPropertiesToFetch:
        [NSArray arrayWithObjects:@"name", @"salary", nil]];

    NSError *error = nil;
    NSArray *rows = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(rows, @"fetch failed: %@", error);

    NSArray *expected = [NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"alpha", @"name", [NSNumber numberWithInt:22], @"salary", nil],
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"bravo", @"name", [NSNumber numberWithInt:25], @"salary", nil],
        nil];
    XCTAssertEqualObjects(rows, expected);
}

- (void)testDictionaryFetchDefaultKeysAreAllAttributes
{
    /* With no propertiesToFetch, dictionary rows carry every attribute
       of the entity (relationships never appear). */
    self.ctx = [self contextWithStoreType:NSSQLiteStoreType];
    NSManagedObject *employee = [self insertEmployeeNamed:@"alice"
                                                   salary:9
                                                inContext:self.ctx];
    [employee setValue:[NSDate dateWithTimeIntervalSinceReferenceDate:1000]
                forKey:@"hireDate"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Employee"
                                 inManagedObjectContext:self.ctx]];
    [fetch setResultType:NSDictionaryResultType];

    NSArray *rows = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(rows, @"fetch failed: %@", error);
    XCTAssertEqual([rows count], (NSUInteger)1);

    NSDictionary *row = [rows lastObject];
    XCTAssertEqualObjects([row objectForKey:@"name"], @"alice");
    XCTAssertEqual([[row objectForKey:@"salary"] intValue], 9);
    XCTAssertEqualWithAccuracy(
        [[row objectForKey:@"hireDate"] timeIntervalSinceReferenceDate],
        1000.0, 0.001);
    /* The department relationship must not appear as a key. */
    XCTAssertNil([row objectForKey:@"department"]);
}

- (void)testDictionaryFetchOnAtomicStore
{
    /* Atomic stores have no shaping of their own; the context builds
       the rows from the cache-node snapshots. */
    self.ctx = [self contextWithStoreType:NSInMemoryStoreType];
    [self insertEmployeeNamed:@"xray" salary:22 inContext:self.ctx];
    [self insertEmployeeNamed:@"yankee" salary:10 inContext:self.ctx];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Employee"
                                 inManagedObjectContext:self.ctx]];
    [fetch setResultType:NSDictionaryResultType];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"salary > 20"]];
    [fetch setPropertiesToFetch:[NSArray arrayWithObject:@"name"]];

    NSArray *rows = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(rows, @"fetch failed: %@", error);
    XCTAssertEqualObjects(rows,
        [NSArray arrayWithObject:
            [NSDictionary dictionaryWithObject:@"xray" forKey:@"name"]]);
}

- (void)testDistinctDictionaryRows
{
    self.ctx = [self contextWithStoreType:NSSQLiteStoreType];
    [self insertEmployeeNamed:@"dup" salary:1 inContext:self.ctx];
    [self insertEmployeeNamed:@"dup" salary:2 inContext:self.ctx];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Employee"
                                 inManagedObjectContext:self.ctx]];
    [fetch setResultType:NSDictionaryResultType];
    [fetch setPropertiesToFetch:[NSArray arrayWithObject:@"name"]];
    [fetch setReturnsDistinctResults:YES];

    NSArray *rows = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(rows, @"fetch failed: %@", error);
    XCTAssertEqual([rows count], (NSUInteger)1);
    XCTAssertEqualObjects([[rows lastObject] objectForKey:@"name"], @"dup");
}

/* ------------------------------------------------------------------ */
#pragma mark - Ordering and windowing
/* ------------------------------------------------------------------ */

- (void)testSortAndWindowOnCleanContext
{
    /* With nothing pending the window is exact on both platforms: the
       store applies the sort, offset and limit itself. */
    self.ctx = [self contextWithStoreType:NSSQLiteStoreType];
    [self insertEmployeeNamed:@"a" salary:5 inContext:self.ctx];
    [self insertEmployeeNamed:@"b" salary:21 inContext:self.ctx];
    [self insertEmployeeNamed:@"c" salary:30 inContext:self.ctx];
    [self insertEmployeeNamed:@"d" salary:40 inContext:self.ctx];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Employee"
                                 inManagedObjectContext:self.ctx]];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"salary" ascending:YES]]];
    [fetch setFetchOffset:1];
    [fetch setFetchLimit:2];

    NSArray *result = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    XCTAssertEqualObjects([self namesOfObjects:result],
        ([NSArray arrayWithObjects:@"b", @"c", nil]));
}

- (void)testSortAndWindowWithPendingChanges
{
    [self buildDirtyFixture];

    /* In-memory salaries: alpha 5, charlie 21, delta 30, echo 40 (bravo
       deleted).  Sorted ascending, offset 1 and limit 2 over the MERGED
       set would be [charlie, delta].

       Apple documents fetchLimit combined with pending changes as
       unreliable, and indeed returns [alpha, charlie] here (verified on
       macOS: the window is applied in the store against saved values,
       the overlay is folded into that windowed result, and only the
       limit is re-applied).  So only the limit is asserted portably;
       the port's stronger post-merge windowing is asserted on GNUstep,
       where it is a deliberate improvement inside Apple's documented
       undefined zone. */
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Employee"
                                 inManagedObjectContext:self.ctx]];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"salary" ascending:YES]]];
    [fetch setFetchOffset:1];
    [fetch setFetchLimit:2];

    NSError *error = nil;
    NSArray *result = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    XCTAssertEqual([result count], (NSUInteger)2,
                   @"the limit applies even with pending changes");

#if !defined(__APPLE__)
    XCTAssertEqualObjects([self namesOfObjects:result],
        ([NSArray arrayWithObjects:@"charlie", @"delta", nil]));
#endif
}

/* ------------------------------------------------------------------ */
#pragma mark - Atomic stores
/* ------------------------------------------------------------------ */

- (void)testOverlayOnAtomicStore
{
    /* The overlay is context work, so it behaves identically for an
       atomic store. */
    self.ctx = [self contextWithStoreType:NSInMemoryStoreType];

    NSManagedObject *xray = [self insertEmployeeNamed:@"xray" salary:22
                                            inContext:self.ctx];
    NSManagedObject *yankee = [self insertEmployeeNamed:@"yankee" salary:10
                                              inContext:self.ctx];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [yankee setValue:[NSNumber numberWithInt:21] forKey:@"salary"];
    [self.ctx deleteObject:xray];
    [self insertEmployeeNamed:@"zulu" salary:30 inContext:self.ctx];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Employee"
                                 inManagedObjectContext:self.ctx]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"salary > 20"]];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];

    NSArray *result = [self.ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    XCTAssertEqualObjects([self namesOfObjects:result],
        ([NSArray arrayWithObjects:@"yankee", @"zulu", nil]));

    XCTAssertEqual([self.ctx countForFetchRequest:fetch error:&error],
                   (NSUInteger)2);
}

@end
