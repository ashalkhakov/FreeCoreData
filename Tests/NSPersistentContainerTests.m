/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSPersistentContainerTests - the modern container stack: store
   descriptions, synchronous and asynchronous loading, the main-queue
   view context, newBackgroundContext and performBackgroundTask:.
   On macOS these run against Apple's real NSPersistentContainer, so
   every shared assertion is Apple-arbitrated. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

static BOOL CDCWaitFor(NSTimeInterval timeout, BOOL (^condition)(void))
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

@interface NSPersistentContainerTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSString *storePath;

@end

@implementation NSPersistentContainerTests

- (void)setUp
{
    NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
    [text setName:@"text"];
    [text setAttributeType:NSStringAttributeType];
    [text setOptional:YES];

    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"NSManagedObject"];
    [note setProperties:[NSArray arrayWithObject:text]];

    self.model = [[NSManagedObjectModel alloc] init];
    [self.model setEntities:[NSArray arrayWithObject:note]];

    self.storePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"container-%@.sqlite",
         [[NSProcessInfo processInfo] globallyUniqueString]]];
}

- (void)tearDown
{
    self.model = nil;
    if (self.storePath) {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:self.storePath error:NULL];
        [fm removeItemAtPath:[self.storePath stringByAppendingString:@"-wal"] error:NULL];
        [fm removeItemAtPath:[self.storePath stringByAppendingString:@"-shm"] error:NULL];
    }
}

/* a container pointed at this test's temporary store, stores loaded */
- (NSPersistentContainer *)loadedContainer
{
    NSPersistentContainer *container = [[NSPersistentContainer alloc]
        initWithName:@"ContainerTests" managedObjectModel:self.model];
    NSPersistentStoreDescription *description =
        [NSPersistentStoreDescription persistentStoreDescriptionWithURL:
            [NSURL fileURLWithPath:self.storePath]];
    [container setPersistentStoreDescriptions:
        [NSArray arrayWithObject:description]];

    __block NSError *loadError = nil;
    [container loadPersistentStoresWithCompletionHandler:
        ^(NSPersistentStoreDescription *loaded, NSError *error) {
        loadError = error;
    }];
    XCTAssertNil(loadError, @"load failed: %@", loadError);
    return container;
}

/* ---------------------------------------------------------------- */

- (void)testStoreDescriptionDefaults
{
    NSURL *url = [NSURL fileURLWithPath:self.storePath];
    NSPersistentStoreDescription *description =
        [NSPersistentStoreDescription persistentStoreDescriptionWithURL:url];

    XCTAssertEqualObjects([description type], NSSQLiteStoreType);
    XCTAssertEqualObjects([[description URL] path], [url path]);
    XCTAssertNil([description configuration]);
    XCTAssertFalse([description isReadOnly]);
    XCTAssertFalse([description shouldAddStoreAsynchronously],
        @"stores load synchronously by default");
    XCTAssertTrue([description shouldMigrateStoreAutomatically]);
    XCTAssertTrue([description shouldInferMappingModelAutomatically]);
}

- (void)testContainerWiring
{
    NSPersistentContainer *container = [[NSPersistentContainer alloc]
        initWithName:@"ContainerTests" managedObjectModel:self.model];

    XCTAssertEqualObjects([container name], @"ContainerTests");
    XCTAssertEqual([container managedObjectModel], self.model);
    XCTAssertNotNil([container persistentStoreCoordinator]);
    XCTAssertEqual([[container persistentStoreCoordinator] managedObjectModel],
                   self.model);

    NSManagedObjectContext *view = [container viewContext];
    XCTAssertEqual([view concurrencyType], NSMainQueueConcurrencyType);
    XCTAssertEqual([view persistentStoreCoordinator],
                   [container persistentStoreCoordinator]);
    XCTAssertNil([view parentContext],
        @"the view context sits directly on the coordinator");

    /* the default description points at <name>.sqlite */
    XCTAssertEqual([[container persistentStoreDescriptions] count], (NSUInteger)1);
    NSPersistentStoreDescription *description =
        [[container persistentStoreDescriptions] lastObject];
    XCTAssertEqualObjects([[[description URL] path] lastPathComponent],
                          @"ContainerTests.sqlite");
    XCTAssertNotNil([NSPersistentContainer defaultDirectoryURL]);
}

- (void)testSynchronousLoadAddsTheStore
{
    NSPersistentContainer *container = [self loadedContainer];

    /* handler already ran (helper asserted no error); the store is up */
    XCTAssertEqual([[[container persistentStoreCoordinator] persistentStores] count],
                   (NSUInteger)1);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:self.storePath]);
}

- (void)testAsynchronousLoad
{
    NSPersistentContainer *container = [[NSPersistentContainer alloc]
        initWithName:@"ContainerTests" managedObjectModel:self.model];
    NSPersistentStoreDescription *description =
        [NSPersistentStoreDescription persistentStoreDescriptionWithURL:
            [NSURL fileURLWithPath:self.storePath]];
    [description setShouldAddStoreAsynchronously:YES];
    [container setPersistentStoreDescriptions:
        [NSArray arrayWithObject:description]];

    __block BOOL loaded = NO;
    __block NSError *loadError = nil;
    [container loadPersistentStoresWithCompletionHandler:
        ^(NSPersistentStoreDescription *done, NSError *error) {
        loadError = error;
        loaded = YES;
    }];

    XCTAssertTrue(CDCWaitFor(5, ^{ return loaded; }));
    XCTAssertNil(loadError);
    XCTAssertEqual([[[container persistentStoreCoordinator] persistentStores] count],
                   (NSUInteger)1);
}

- (void)testLoadReportsErrors
{
    /* Arbitrated on macOS: an impossible file path did NOT surface an
       error through the handler there (an earlier version of this test
       asserted that and failed), so the error path is provoked with
       something both implementations definitely refuse at add time: a
       store written under a DIFFERENT model, loaded with automatic
       migration disabled. */
    NSAttributeDescription *extra = [[NSAttributeDescription alloc] init];
    [extra setName:@"extra"];
    [extra setAttributeType:NSStringAttributeType];
    [extra setOptional:YES];
    NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
    [text setName:@"text"];
    [text setAttributeType:NSStringAttributeType];
    [text setOptional:YES];
    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"NSManagedObject"];
    [note setProperties:[NSArray arrayWithObjects:text, extra, nil]];
    NSManagedObjectModel *otherModel = [[NSManagedObjectModel alloc] init];
    [otherModel setEntities:[NSArray arrayWithObject:note]];

    NSPersistentStoreCoordinator *writer = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:otherModel];
    XCTAssertNotNil([writer addPersistentStoreWithType:NSSQLiteStoreType
                                         configuration:nil
                                                   URL:[NSURL fileURLWithPath:self.storePath]
                                               options:nil
                                                 error:NULL]);
    for (NSPersistentStore *store in [[writer persistentStores] copy])
        [writer removePersistentStore:store error:NULL];

    NSPersistentContainer *container = [[NSPersistentContainer alloc]
        initWithName:@"ContainerTests" managedObjectModel:self.model];
    NSPersistentStoreDescription *description =
        [NSPersistentStoreDescription persistentStoreDescriptionWithURL:
            [NSURL fileURLWithPath:self.storePath]];
    [description setShouldMigrateStoreAutomatically:NO];
    [container setPersistentStoreDescriptions:
        [NSArray arrayWithObject:description]];

    __block BOOL called = NO;
    __block NSError *loadError = nil;
    [container loadPersistentStoresWithCompletionHandler:
        ^(NSPersistentStoreDescription *done, NSError *error) {
        called = YES;
        loadError = error;
    }];
    XCTAssertTrue(called);
    XCTAssertNotNil(loadError,
        @"an incompatible store with migration disabled surfaces through the handler");
}

- (void)testNewBackgroundContext
{
    NSPersistentContainer *container = [self loadedContainer];
    NSManagedObjectContext *background = [container newBackgroundContext];

    XCTAssertEqual([background concurrencyType], NSPrivateQueueConcurrencyType);
    XCTAssertEqual([background persistentStoreCoordinator],
                   [container persistentStoreCoordinator]);
    XCTAssertNil([background parentContext],
        @"background contexts sit directly on the coordinator");
}

- (void)testPerformBackgroundTask
{
    NSPersistentContainer *container = [self loadedContainer];

    __block BOOL ran = NO;
    __block BOOL wasMainThread = YES;
    __block NSManagedObjectContextConcurrencyType type = NSConfinementConcurrencyType;
    [container performBackgroundTask:^(NSManagedObjectContext *context) {
        type = [context concurrencyType];
        wasMainThread = [NSThread isMainThread];
        ran = YES;
    }];

    XCTAssertTrue(CDCWaitFor(5, ^{ return ran; }));
    XCTAssertEqual(type, NSPrivateQueueConcurrencyType);
    XCTAssertFalse(wasMainThread);
}

- (void)testBackgroundSaveReachesTheViewContext
{
    NSPersistentContainer *container = [self loadedContainer];
    NSManagedObjectContext *view = [container viewContext];
    [view setAutomaticallyMergesChangesFromParent:YES];

    __block BOOL merged = NO;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                    object:view
                     queue:nil
                usingBlock:^(NSNotification *note) { merged = YES; }];

    [container performBackgroundTask:^(NSManagedObjectContext *context) {
        NSManagedObject *note = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [note setValue:@"container round trip" forKey:@"text"];
        [context save:NULL];
    }];

    XCTAssertTrue(CDCWaitFor(5, ^{ return merged; }),
        @"a background save surfaces in the auto-merging view context");
    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Note"]];
    __block NSUInteger count = 0;
    [view performBlockAndWait:^{
        count = [[view executeFetchRequest:fetch error:NULL] count];
    }];
    XCTAssertEqual(count, (NSUInteger)1);
}

@end
