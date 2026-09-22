/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSManagedObjectContextConcurrencyTests - queue-confined contexts:
   initWithConcurrencyType:, performBlock: / performBlockAndWait:
   semantics (ordering, reentrancy, the "user event" boundary), and
   cross-context work against a shared coordinator.  These compile on
   macOS against Apple CoreData, so every semantic asserted here is
   arbitrated by Apple's implementation. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

/* Spins the calling thread's run loop while polling; the portable
   stand-in for XCTestExpectation (which the GNUstep XCTest port does
   not provide). */
static BOOL CDWaitFor(NSTimeInterval timeout, BOOL (^condition)(void))
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

@interface NSManagedObjectContextConcurrencyTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSString *storePath;

@end

@implementation NSManagedObjectContextConcurrencyTests

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
        [NSString stringWithFormat:@"concurrency-%@.sqlite",
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

/* ---------------------------------------------------------------- */

- (void)testConcurrencyTypesAreStored
{
    NSManagedObjectContext *private = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    NSManagedObjectContext *main = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    XCTAssertEqual([private concurrencyType], NSPrivateQueueConcurrencyType);
    XCTAssertEqual([main concurrencyType], NSMainQueueConcurrencyType);

    /* the legacy initializer remains a thread-confined context */
    NSManagedObjectContext *legacy = [[NSManagedObjectContext alloc] init];
    XCTAssertEqual([legacy concurrencyType], NSConfinementConcurrencyType);
}

- (void)testNameIsStored
{
    NSManagedObjectContext *ctx = [self privateContext];
    XCTAssertNil([ctx name]);
    [ctx setName:@"background work"];
    XCTAssertEqualObjects([ctx name], @"background work");
}

- (void)testPerformBlockRunsOffTheCallingThread
{
    NSManagedObjectContext *ctx = [self privateContext];
    __block NSThread *blockThread = nil;
    __block BOOL done = NO;

    [ctx performBlock:^{
        blockThread = [NSThread currentThread];
        done = YES;
    }];

    XCTAssertTrue(CDWaitFor(5, ^{ return done; }));
    XCTAssertNotNil(blockThread);
    XCTAssertNotEqualObjects(blockThread, [NSThread mainThread],
                             @"a private queue is never the main thread");

    /* Deliberately NOT asserted: that two blocks share one OS thread.
       A serial dispatch queue guarantees ordering, not a pinned
       thread - on Apple and on swift-corelibs-libdispatch alike. */
}

- (void)testBlocksExecuteInSubmissionOrder
{
    NSManagedObjectContext *ctx = [self privateContext];
    NSMutableArray *order = [NSMutableArray array];  /* queue-confined */

    for (NSUInteger i = 0; i < 8; i++) {
        [ctx performBlock:^{
            [order addObject:[NSNumber numberWithUnsignedInteger:i]];
        }];
    }

    __block NSArray *seen = nil;
    [ctx performBlockAndWait:^{ seen = [order copy]; }];

    NSMutableArray *expected = [NSMutableArray array];
    for (NSUInteger i = 0; i < 8; i++)
        [expected addObject:[NSNumber numberWithUnsignedInteger:i]];
    XCTAssertEqualObjects(seen, expected,
        @"performBlockAndWait queues behind earlier asynchronous blocks");
}

- (void)testPerformBlockAndWaitIsSynchronousAndReentrant
{
    NSManagedObjectContext *ctx = [self privateContext];
    __block BOOL outer = NO, inner = NO, insidePerform = NO;

    [ctx performBlockAndWait:^{
        outer = YES;
        [ctx performBlockAndWait:^{ inner = YES; }];
    }];
    XCTAssertTrue(outer, @"performBlockAndWait is synchronous");
    XCTAssertTrue(inner, @"nested performBlockAndWait runs inline, no deadlock");

    /* reentrant from inside performBlock: too */
    __block BOOL done = NO;
    [ctx performBlock:^{
        [ctx performBlockAndWait:^{ insidePerform = YES; }];
        done = YES;
    }];
    XCTAssertTrue(CDWaitFor(5, ^{ return done; }));
    XCTAssertTrue(insidePerform);
}

- (void)testConfinementContextRaisesOnQueueAPI
{
    NSManagedObjectContext *legacy = [[NSManagedObjectContext alloc] init];
    XCTAssertThrows([legacy performBlock:^{}]);
    XCTAssertThrows([legacy performBlockAndWait:^{}]);
}

- (void)testMainQueueContextRunsBlocksOnTheMainThread
{
    NSManagedObjectContext *mainCtx = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [mainCtx setPersistentStoreCoordinator:self.psc];

    /* performBlockAndWait on the main thread runs inline */
    __block BOOL inline_ = NO;
    [mainCtx performBlockAndWait:^{ inline_ = YES; }];
    XCTAssertTrue(inline_);

    /* performBlock is asynchronous even from the main thread, and is
       delivered on it by the run loop */
    __block BOOL delivered = NO;
    __block BOOL wasMainThread = NO;
    [mainCtx performBlock:^{
        wasMainThread = [NSThread isMainThread];
        delivered = YES;
    }];
    XCTAssertFalse(delivered, @"performBlock never runs inline");
    XCTAssertTrue(CDWaitFor(5, ^{ return delivered; }));
    XCTAssertTrue(wasMainThread);

    /* reaching a main-queue context from another queue */
    NSManagedObjectContext *bg = [self privateContext];
    __block BOOL crossDelivered = NO;
    __block BOOL crossWasMain = NO;
    [bg performBlock:^{
        [mainCtx performBlock:^{
            crossWasMain = [NSThread isMainThread];
            crossDelivered = YES;
        }];
    }];
    XCTAssertTrue(CDWaitFor(5, ^{ return crossDelivered; }));
    XCTAssertTrue(crossWasMain);
}

- (void)testPerformBlockEndsAUserEvent
{
    /* Apple documents performBlock: as encapsulating a user event:
       the objects-did-change notification for changes made inside the
       block fires when the block finishes, without a run loop. */
    NSManagedObjectContext *ctx = [self privateContext];
    __block BOOL notified = NO;
    __block BOOL sawInsert = NO;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                    object:ctx
                     queue:nil
                usingBlock:^(NSNotification *note) {
        sawInsert = [[[note userInfo] objectForKey:NSInsertedObjectsKey] count] == 1;
        notified = YES;
    }];

    [ctx performBlock:^{
        [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                      inManagedObjectContext:ctx];
    }];

    XCTAssertTrue(CDWaitFor(5, ^{ return notified; }));
    XCTAssertTrue(sawInsert);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testBackgroundSaveIsVisibleToOtherContexts
{
    NSManagedObjectContext *bg = [self privateContext];
    __block BOOL saved = NO;
    __block NSError *saveError = nil;

    [bg performBlock:^{
        NSManagedObject *note = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note" inManagedObjectContext:bg];
        [note setValue:@"from the background" forKey:@"text"];
        NSError *err = nil;
        [bg save:&err];
        saveError = err;
        saved = YES;
    }];
    XCTAssertTrue(CDWaitFor(5, ^{ return saved; }));
    XCTAssertNil(saveError);

    NSManagedObjectContext *reader = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [reader setPersistentStoreCoordinator:self.psc];
    __block NSArray *found = nil;
    [reader performBlockAndWait:^{
        NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
        [fetch setEntity:[[[self.model entitiesByName] allValues] objectAtIndex:0]];
        NSError *err = nil;
        found = [reader executeFetchRequest:fetch error:&err];
    }];
    XCTAssertEqual([found count], (NSUInteger)1);
    XCTAssertEqualObjects([[found objectAtIndex:0] valueForKey:@"text"],
                          @"from the background");
}

- (void)testDidSaveNotificationMergesIntoAnotherQueueContext
{
    /* What Apple guarantees for a merged INSERT (arbitrated on macOS):
       the receiving context posts objects-did-change carrying the
       incoming object, and the object is reachable there afterwards.
       NOT guaranteed: that it stays in registeredObjects - nothing
       retains the merged-in fault unless retainsRegisteredObjects is
       set, so an earlier version of this test asserting registration
       failed against Apple. */
    NSManagedObjectContext *bg = [self privateContext];
    NSManagedObjectContext *main = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [main setPersistentStoreCoordinator:self.psc];

    __block NSManagedObjectID *savedID = nil;
    NSMutableSet *changedIDs = [NSMutableSet set];   /* main-queue confined */
    __block NSUInteger changeNotifications = 0;
    id changeObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                    object:main
                     queue:nil
                usingBlock:^(NSNotification *note) {
        changeNotifications++;
        for (NSString *key in @[ NSInsertedObjectsKey, NSUpdatedObjectsKey,
                                 NSRefreshedObjectsKey ])
            for (NSManagedObject *object in [[note userInfo] objectForKey:key])
                [changedIDs addObject:[object objectID]];
    }];

    __block BOOL merged = NO;
    id saveObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextDidSaveNotification
                    object:bg
                     queue:nil
                usingBlock:^(NSNotification *note) {
        /* the notification arrives on the background queue; merging
           must happen on the receiving context's queue */
        [main performBlock:^{
            [main mergeChangesFromContextDidSaveNotification:note];
            merged = YES;
        }];
    }];

    [bg performBlock:^{
        NSManagedObject *note = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note" inManagedObjectContext:bg];
        [note setValue:@"merge me" forKey:@"text"];
        [bg save:NULL];
        savedID = [note objectID];   /* permanent after the save */
    }];

    XCTAssertTrue(CDWaitFor(5, ^{ return merged; }));

    /* run the loop once more so the merge's own change notification
       (posted at the event boundary) has fired */
    XCTAssertTrue(CDWaitFor(5, ^{ return (BOOL)(changeNotifications > 0); }),
                  @"the merge surfaces through objects-did-change on the receiver");
    XCTAssertTrue([changedIDs containsObject:savedID],
                  @"...naming the merged-in object");

    __block NSString *text = nil;
    [main performBlockAndWait:^{
        NSError *err = nil;
        NSManagedObject *local = [main existingObjectWithID:savedID error:&err];
        text = [local valueForKey:@"text"];
    }];
    XCTAssertEqualObjects(text, @"merge me",
                          @"the merged object is reachable in the receiver");

    [[NSNotificationCenter defaultCenter] removeObserver:changeObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:saveObserver];
}

- (void)testConcurrentSavesSerializeThroughTheCoordinator
{
    /* Two private-queue contexts hammer one coordinator; every insert
       must land.  This exercises the coordinator-level serialization
       of store access. */
    enum { PER_CONTEXT = 12 };
    NSManagedObjectContext *a = [self privateContext];
    NSManagedObjectContext *b = [self privateContext];

    for (NSUInteger i = 0; i < PER_CONTEXT; i++) {
        [a performBlock:^{
            [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                          inManagedObjectContext:a];
            [a save:NULL];
        }];
        [b performBlock:^{
            [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                          inManagedObjectContext:b];
            [b save:NULL];
        }];
    }

    /* barrier both queues instead of counting across threads */
    [a performBlockAndWait:^{}];
    [b performBlockAndWait:^{}];

    NSManagedObjectContext *reader = [self privateContext];
    __block NSUInteger total = 0;
    [reader performBlockAndWait:^{
        NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
        [fetch setEntity:[[[self.model entitiesByName] allValues] objectAtIndex:0]];
        total = [[reader executeFetchRequest:fetch error:NULL] count];
    }];
    XCTAssertEqual(total, (NSUInteger)(2 * PER_CONTEXT));
}

- (void)testPerformBlockAndWaitDoesNotEndTheEvent
{
    /* Apple: performBlockAndWait does NOT process pending changes -
       the change notification waits for the next event boundary. */
    NSManagedObjectContext *ctx = [self privateContext];
    __block NSUInteger notifications = 0;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                    object:ctx
                     queue:nil
                usingBlock:^(NSNotification *note) { notifications++; }];

    [ctx performBlockAndWait:^{
        [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                      inManagedObjectContext:ctx];
    }];
    XCTAssertEqual(notifications, (NSUInteger)0,
        @"no event boundary inside performBlockAndWait");

    /* The next performBlock event flushes it.  The notification posts
       AFTER the user block returns (the event wrapper's order), so
       wait for the notification itself - asserting right after the
       block's own flag is a race the suite run loses. */
    __block BOOL done = NO;
    [ctx performBlock:^{ done = YES; }];
    XCTAssertTrue(CDWaitFor(5, ^{ return done; }));
    XCTAssertTrue(CDWaitFor(5, ^{ return (BOOL)(notifications == 1); }),
        @"the pending insert flushes at the next event boundary");
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

@end
