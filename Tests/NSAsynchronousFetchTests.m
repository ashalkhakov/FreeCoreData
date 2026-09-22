/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSAsynchronousFetchTests - NSAsynchronousFetchRequest through
   -[NSManagedObjectContext executeRequest:error:]: the immediately
   returned NSAsynchronousFetchResult, completion delivery on the
   context's queue, predicate/sort fidelity, and cancellation.  These
   compile on macOS against Apple CoreData, so every semantic asserted
   here is arbitrated by Apple's implementation. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

/* Spins the calling thread's run loop while polling; the portable
   stand-in for XCTestExpectation (which the GNUstep XCTest port does
   not provide). */
static BOOL CDAFWaitFor(NSTimeInterval timeout, BOOL (^condition)(void))
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition()) {
        if ([deadline timeIntervalSinceNow] < 0)
            return NO;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return YES;
}

@interface NSAsynchronousFetchTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSString *storePath;

@end

@implementation NSAsynchronousFetchTests

- (NSManagedObjectModel *)makeModel
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
    return model;
}

- (void)setUp
{
    self.model = [self makeModel];
    self.psc = [[NSPersistentStoreCoordinator alloc]
                   initWithManagedObjectModel:self.model];
    self.storePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"asyncfetch-%@.sqlite",
         [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSError *err = nil;
    XCTAssertNotNil([self.psc
        addPersistentStoreWithType:NSSQLiteStoreType
                     configuration:nil
                               URL:[NSURL fileURLWithPath:self.storePath]
                           options:nil
                             error:&err], @"add store: %@", err);
}

- (void)tearDown
{
    /* Close the store before unlinking its file: deleting a live
       SQLite database is an API violation on macOS ("vnode unlinked
       while in use"). */
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

- (NSManagedObjectContext *)privateContext
{
    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [ctx setPersistentStoreCoordinator:self.psc];
    return ctx;
}

/* Saves one Note per string in the given context, on its queue. */
- (void)seedContext:(NSManagedObjectContext *)ctx withTexts:(NSArray *)texts
{
    [ctx performBlockAndWait:^{
        for (NSString *text in texts) {
            NSManagedObject *note = [NSEntityDescription
                insertNewObjectForEntityForName:@"Note"
                         inManagedObjectContext:ctx];
            [note setValue:text forKey:@"text"];
        }
        NSError *err = nil;
        XCTAssertTrue([ctx save:&err], @"seed save: %@", err);
    }];
}

/* ---------------------------------------------------------------- */

- (void)testRequestShape
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    NSAsynchronousFetchRequest *request = [[NSAsynchronousFetchRequest alloc]
        initWithFetchRequest:fetch
             completionBlock:^(NSAsynchronousFetchResult *result) {}];

    XCTAssertEqual([request fetchRequest], fetch,
        @"the wrapped fetch request is held, not copied");
    XCTAssertNotNil([request completionBlock]);
    XCTAssertEqual([request estimatedResultCount], (NSInteger)0);
    [request setEstimatedResultCount:42];
    XCTAssertEqual([request estimatedResultCount], (NSInteger)42);
}

- (void)testRequestTypeIsFetch
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    NSAsynchronousFetchRequest *request = [[NSAsynchronousFetchRequest alloc]
        initWithFetchRequest:fetch completionBlock:nil];

    XCTAssertEqual((NSUInteger)[request requestType], (NSUInteger)NSFetchRequestType);
}

- (void)testAsynchronousFetchDeliversFinalResult
{
    NSManagedObjectContext *ctx = [self privateContext];
    [self seedContext:ctx withTexts:[NSArray arrayWithObjects:@"b", @"a", @"c", nil]];

    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]]];

    __block BOOL done = NO;
    __block NSAsynchronousFetchResult *delivered = nil;
    NSAsynchronousFetchRequest *request = [[NSAsynchronousFetchRequest alloc]
        initWithFetchRequest:fetch
             completionBlock:^(NSAsynchronousFetchResult *result) {
                 delivered = result;
                 done = YES;
             }];

    __block NSAsynchronousFetchResult *returned = nil;
    [ctx performBlockAndWait:^{
        NSError *err = nil;
        returned = (NSAsynchronousFetchResult *)[ctx executeRequest:request error:&err];
        XCTAssertNotNil(returned, @"executeRequest returns the result handle immediately: %@", err);
        XCTAssertTrue([returned isKindOfClass:[NSAsynchronousFetchResult class]]);
    }];

    XCTAssertTrue(CDAFWaitFor(5.0, ^BOOL{ return done; }),
        @"the completion block runs");
    XCTAssertEqual(delivered, returned,
        @"the completion block receives the same result executeRequest returned");
    XCTAssertEqual([returned managedObjectContext], ctx);
    XCTAssertNil([returned operationError]);

    NSArray *rows = [returned finalResult];
    XCTAssertEqual([rows count], (NSUInteger)3);
    XCTAssertEqualObjects([[rows objectAtIndex:0] valueForKey:@"text"], @"a");
    XCTAssertEqualObjects([[rows objectAtIndex:1] valueForKey:@"text"], @"b");
    XCTAssertEqualObjects([[rows objectAtIndex:2] valueForKey:@"text"], @"c");
    XCTAssertEqual([(NSManagedObject *)[rows objectAtIndex:0] managedObjectContext], ctx,
        @"fetched objects belong to the executing context");
}

- (void)testPredicateAndSortAreHonored
{
    NSManagedObjectContext *ctx = [self privateContext];
    [self seedContext:ctx withTexts:[NSArray arrayWithObjects:@"a", @"b", @"c", nil]];

    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"text != %@", @"b"]];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"text" ascending:NO]]];

    __block BOOL done = NO;
    __block NSArray *rows = nil;
    NSAsynchronousFetchRequest *request = [[NSAsynchronousFetchRequest alloc]
        initWithFetchRequest:fetch
             completionBlock:^(NSAsynchronousFetchResult *result) {
                 rows = [result finalResult];
                 done = YES;
             }];

    [ctx performBlockAndWait:^{
        NSError *err = nil;
        XCTAssertNotNil([ctx executeRequest:request error:&err], @"%@", err);
    }];

    XCTAssertTrue(CDAFWaitFor(5.0, ^BOOL{ return done; }));
    XCTAssertEqual([rows count], (NSUInteger)2);
    XCTAssertEqualObjects([[rows objectAtIndex:0] valueForKey:@"text"], @"c");
    XCTAssertEqualObjects([[rows objectAtIndex:1] valueForKey:@"text"], @"a");
}

- (void)testCompletionBlockRunsOnTheMainQueueForMainQueueContexts
{
    NSManagedObjectContext *background = [self privateContext];
    [self seedContext:background withTexts:[NSArray arrayWithObject:@"hello"]];

    NSManagedObjectContext *main = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [main setPersistentStoreCoordinator:self.psc];

    __block BOOL done = NO;
    __block BOOL onMainThread = NO;
    __block NSUInteger count = 0;
    NSAsynchronousFetchRequest *request = [[NSAsynchronousFetchRequest alloc]
        initWithFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Note"]
             completionBlock:^(NSAsynchronousFetchResult *result) {
                 onMainThread = [NSThread isMainThread];
                 count = [[result finalResult] count];
                 done = YES;
             }];

    /* the documented viewContext usage: execute directly from the main
       thread, which is a main-queue context's own queue */
    NSError *err = nil;
    XCTAssertNotNil([main executeRequest:request error:&err], @"%@", err);
    XCTAssertFalse(done, @"delivery is asynchronous even from the context's own queue");

    XCTAssertTrue(CDAFWaitFor(5.0, ^BOOL{ return done; }),
        @"the completion block is delivered through the main run loop");
    XCTAssertTrue(onMainThread,
        @"a main-queue context delivers its completion on the main thread");
    XCTAssertEqual(count, (NSUInteger)1);
}

- (void)testCancelBeforeExecutionDeliversEmptyResult
{
    /* Arbitrated on macOS: cancelling the result before the fetch
       event runs does NOT surface NSUserCancelledError (an earlier
       version of this test asserted that and failed) - Apple delivers
       the completion with an EMPTY finalResult and a nil
       operationError. */
    NSManagedObjectContext *ctx = [self privateContext];
    [self seedContext:ctx withTexts:[NSArray arrayWithObject:@"x"]];

    __block BOOL done = NO;
    __block NSError *operationError = nil;
    __block NSArray *rows = nil;
    NSAsynchronousFetchRequest *request = [[NSAsynchronousFetchRequest alloc]
        initWithFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Note"]
             completionBlock:^(NSAsynchronousFetchResult *result) {
                 operationError = [result operationError];
                 rows = [result finalResult];
                 done = YES;
             }];

    [ctx performBlockAndWait:^{
        NSError *err = nil;
        NSAsynchronousFetchResult *result =
            (NSAsynchronousFetchResult *)[ctx executeRequest:request error:&err];
        XCTAssertNotNil(result, @"%@", err);
        /* the fetch event is queued behind this block on the context's
           serial queue, so this cancel deterministically precedes it */
        [result cancel];
    }];

    XCTAssertTrue(CDAFWaitFor(5.0, ^BOOL{ return done; }),
        @"a cancelled request still delivers its completion");
    XCTAssertNotNil(rows, @"cancellation delivers an empty result, not a nil one");
    XCTAssertEqual([rows count], (NSUInteger)0,
        @"the seeded row is not fetched once the request is cancelled");
    XCTAssertNil(operationError, @"cancellation is not an operation error");
}

- (void)testConfinementContextsCannotExecuteAsynchronousFetches
{
    NSManagedObjectContext *legacy = [[NSManagedObjectContext alloc] init];
    [legacy setPersistentStoreCoordinator:self.psc];

    NSAsynchronousFetchRequest *request = [[NSAsynchronousFetchRequest alloc]
        initWithFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Note"]
             completionBlock:^(NSAsynchronousFetchResult *result) {}];

    NSError *err = nil;
    XCTAssertThrows([legacy executeRequest:request error:&err],
        @"asynchronous fetches need a queue-backed context");
}

@end
