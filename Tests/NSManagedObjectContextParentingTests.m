/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSManagedObjectContextParentingTests - nested contexts: a child
   saves into its parent instead of the store, fetches through the
   parent's current state, IDs stay temporary until the root saves,
   and automaticallyMergesChangesFromParent.  Compiled against Apple
   CoreData on macOS, so every shared assertion is Apple-arbitrated. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

static BOOL CDPWaitFor(NSTimeInterval timeout, BOOL (^condition)(void))
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

/* What a parent's objects' observers hear: "name.key kind" lines, and the
   names of the objects a to-many change carried. */
@interface CDPChangeLog : NSObject
@property (nonatomic, strong) NSMutableArray *lines;
@end

@implementation CDPChangeLog
- (instancetype)init
{
    if ((self = [super init]) != nil)
        _lines = [NSMutableArray array];
    return self;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([change[NSKeyValueChangeNotificationIsPriorKey] boolValue])
        return;
    id carried = change[NSKeyValueChangeNewKey];
    if (carried == nil || carried == [NSNull null])
        carried = change[NSKeyValueChangeOldKey];
    NSString *what = @"";
    if ([carried isKindOfClass:[NSSet class]])
        what = [[[[carried valueForKey:@"name"] allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
    [self.lines addObject:[NSString stringWithFormat:@"%@ %@ %@", keyPath, change[NSKeyValueChangeKindKey], what]];
}
@end

@interface NSManagedObjectContextParentingTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSString *storePath;

@end

@implementation NSManagedObjectContextParentingTests

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

    self.psc = [[NSPersistentStoreCoordinator alloc]
                   initWithManagedObjectModel:self.model];
    self.storePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"parenting-%@.sqlite",
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

- (NSManagedObjectContext *)rootContext
{
    NSManagedObjectContext *root = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [root setPersistentStoreCoordinator:self.psc];
    return root;
}

- (NSManagedObjectContext *)childOf:(NSManagedObjectContext *)parent
{
    NSManagedObjectContext *child = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [child setParentContext:parent];
    return child;
}

- (NSFetchRequest *)noteFetch
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Note"]];
    return fetch;
}

/* ---------------------------------------------------------------- */

/* Owners with items, in a store of their own. */
static NSManagedObjectModel *CDPOwnerModel(void)
{
    NSEntityDescription *owner = [[NSEntityDescription alloc] init];
    owner.name = @"Owner";
    NSEntityDescription *item = [[NSEntityDescription alloc] init];
    item.name = @"Item";
    NSAttributeDescription *ownerName = [[NSAttributeDescription alloc] init];
    ownerName.name = @"name";
    ownerName.attributeType = NSStringAttributeType;
    ownerName.optional = YES;
    NSAttributeDescription *count = [[NSAttributeDescription alloc] init];
    count.name = @"count";
    count.attributeType = NSInteger32AttributeType;
    count.optional = YES;
    NSAttributeDescription *itemName = [[NSAttributeDescription alloc] init];
    itemName.name = @"name";
    itemName.attributeType = NSStringAttributeType;
    itemName.optional = YES;
    NSRelationshipDescription *items = [[NSRelationshipDescription alloc] init];
    NSRelationshipDescription *back = [[NSRelationshipDescription alloc] init];
    items.name = @"items";
    items.destinationEntity = item;
    items.maxCount = 0;
    items.optional = YES;
    back.name = @"owner";
    back.destinationEntity = owner;
    back.maxCount = 1;
    back.optional = YES;
    items.inverseRelationship = back;
    back.inverseRelationship = items;
    owner.properties = @[ ownerName, count, items ];
    item.properties = @[ itemName, back ];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ owner, item ];
    return model;
}

/* A child's save tells the parent's objects' observers what it changed,
   as Apple's does: an attribute set, a to-many's members added and taken
   away (an item moved to another owner, one added, one deleted) - and
   nothing of a value set to the one it had.  A binding to the parent
   sees a sheet's child context saved. */
- (void)testAChildsSaveTellsTheParentsObserversWhatChanged
{
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:CDPOwnerModel()];
    XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL]);
    NSManagedObjectContext *parent = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    parent.persistentStoreCoordinator = coordinator;
    NSManagedObject *a = [NSEntityDescription insertNewObjectForEntityForName:@"Owner" inManagedObjectContext:parent];
    [a setValue:@"A" forKey:@"name"];
    [a setValue:@1 forKey:@"count"];
    NSManagedObject *b = [NSEntityDescription insertNewObjectForEntityForName:@"Owner" inManagedObjectContext:parent];
    [b setValue:@"B" forKey:@"name"];
    NSManagedObject *moved = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:parent];
    [moved setValue:@"moved" forKey:@"name"];
    [moved setValue:a forKey:@"owner"];
    NSManagedObject *gone = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:parent];
    [gone setValue:@"gone" forKey:@"name"];
    [gone setValue:b forKey:@"owner"];
    XCTAssertTrue([parent save:NULL]);

    CDPChangeLog *aLog = [[CDPChangeLog alloc] init], *bLog = [[CDPChangeLog alloc] init], *movedLog = [[CDPChangeLog alloc] init];
    NSKeyValueObservingOptions options = NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld;
    for (NSString *key in @[ @"name", @"count", @"items" ]) {
        [a addObserver:aLog forKeyPath:key options:options context:NULL];
        [b addObserver:bLog forKeyPath:key options:options context:NULL];
    }
    [moved addObserver:movedLog forKeyPath:@"owner" options:options context:NULL];

    NSManagedObjectContext *child = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    child.parentContext = parent;
    NSManagedObject *childA = [child objectWithID:a.objectID];
    [childA setValue:@"A2" forKey:@"name"];
    [childA setValue:@1 forKey:@"count"];
    [[child objectWithID:moved.objectID] setValue:[child objectWithID:b.objectID] forKey:@"owner"];
    NSManagedObject *added = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:child];
    [added setValue:@"added" forKey:@"name"];
    [[childA mutableSetValueForKey:@"items"] addObject:added];
    [child deleteObject:[child objectWithID:gone.objectID]];
    NSError *error = nil;
    XCTAssertTrue([child save:&error], @"%@", error);

    NSString *setting = [NSString stringWithFormat:@"%lu", (unsigned long)NSKeyValueChangeSetting];
    NSString *insertion = [NSString stringWithFormat:@"%lu", (unsigned long)NSKeyValueChangeInsertion];
    NSString *removal = [NSString stringWithFormat:@"%lu", (unsigned long)NSKeyValueChangeRemoval];
    NSString *nameSet = [NSString stringWithFormat:@"name %@ ", setting];
    NSString *addedToA = [NSString stringWithFormat:@"items %@ added", insertion];
    NSString *movedFromA = [NSString stringWithFormat:@"items %@ moved", removal];
    NSString *movedToB = [NSString stringWithFormat:@"items %@ moved", insertion];
    NSString *goneFromB = [NSString stringWithFormat:@"items %@ gone", removal];
    XCTAssertTrue([aLog.lines containsObject:nameSet], @"%@", aLog.lines);
    XCTAssertTrue([aLog.lines containsObject:addedToA], @"%@", aLog.lines);
    XCTAssertTrue([aLog.lines containsObject:movedFromA], @"%@", aLog.lines);
    XCTAssertFalse([[aLog.lines componentsJoinedByString:@"|"] containsString:@"count"], @"a value set to the one it had: %@", aLog.lines);
    XCTAssertTrue([bLog.lines containsObject:movedToB], @"%@", bLog.lines);
    XCTAssertTrue([bLog.lines containsObject:goneFromB], @"%@", bLog.lines);
    XCTAssertGreaterThan([movedLog.lines count], (NSUInteger)0);

    XCTAssertEqualObjects([a valueForKey:@"name"], @"A2");
    XCTAssertEqualObjects([[[[a valueForKey:@"items"] valueForKey:@"name"] allObjects] sortedArrayUsingSelector:@selector(compare:)], @[ @"added" ]);
    XCTAssertEqualObjects([[[[b valueForKey:@"items"] valueForKey:@"name"] allObjects] sortedArrayUsingSelector:@selector(compare:)], @[ @"moved" ]);
    XCTAssertEqualObjects([[moved valueForKey:@"owner"] valueForKey:@"name"], @"B");

    for (NSString *key in @[ @"name", @"count", @"items" ]) {
        [a removeObserver:aLog forKeyPath:key];
        [b removeObserver:bLog forKeyPath:key];
    }
    [moved removeObserver:movedLog forKeyPath:@"owner"];
}

/* A to-many changed only as the inverse of another object's change - an
   item moved to another owner - is a change of its own: its saved value
   stays what was saved, and a rollback brings the item back. */
- (void)testAnInverseChangeLeavesTheSavedValueAsItWas
{
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:CDPOwnerModel()];
    XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL]);
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.persistentStoreCoordinator = coordinator;
    NSManagedObject *a = [NSEntityDescription insertNewObjectForEntityForName:@"Owner" inManagedObjectContext:context];
    NSManagedObject *b = [NSEntityDescription insertNewObjectForEntityForName:@"Owner" inManagedObjectContext:context];
    NSManagedObject *item = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:context];
    [item setValue:a forKey:@"owner"];
    XCTAssertTrue([context save:NULL]);

    [item setValue:b forKey:@"owner"];
    XCTAssertEqual([[a valueForKey:@"items"] count], (NSUInteger)0);
    XCTAssertEqual([[[a committedValuesForKeys:@[ @"items" ]] objectForKey:@"items"] count], (NSUInteger)1, @"a's saved items are as saved");
    XCTAssertEqual([[[b committedValuesForKeys:@[ @"items" ]] objectForKey:@"items"] count], (NSUInteger)0, @"b's saved items are as saved");

    [context rollback];
    XCTAssertEqualObjects([item valueForKey:@"owner"], a);
    XCTAssertEqualObjects([a valueForKey:@"items"], [NSSet setWithObject:item]);
    XCTAssertEqual([[b valueForKey:@"items"] count], (NSUInteger)0);
}

- (void)testCoordinatorWalksTheChain
{
    NSManagedObjectContext *root = [self rootContext];
    NSManagedObjectContext *child = [self childOf:root];
    NSManagedObjectContext *grandchild = [self childOf:child];

    XCTAssertEqualObjects([child parentContext], root);
    XCTAssertEqual([child persistentStoreCoordinator], self.psc);
    XCTAssertEqual([grandchild persistentStoreCoordinator], self.psc);
}

- (void)testConfinementContextsMayJoinAChain
{
    /* Arbitrated on macOS: setting a parent on a legacy thread-confined
       context does NOT throw (an earlier version of this test asserted
       a throw and failed against Apple).  The legacy context behaves as
       a normal child: it saves into its parent. */
    NSManagedObjectContext *legacy = [[NSManagedObjectContext alloc] init];
    NSManagedObjectContext *root = [self rootContext];
    XCTAssertNoThrow([legacy setParentContext:root]);
    XCTAssertEqualObjects([legacy parentContext], root);

    NSManagedObject *note = [NSEntityDescription
        insertNewObjectForEntityForName:@"Note" inManagedObjectContext:legacy];
    [note setValue:@"via a legacy child" forKey:@"text"];
    XCTAssertTrue([legacy save:NULL]);

    __block NSUInteger parentCount = 0;
    [root performBlockAndWait:^{
        parentCount = [[root executeFetchRequest:[self noteFetch] error:NULL] count];
    }];
    XCTAssertEqual(parentCount, (NSUInteger)1);
}

- (void)testChildSavePushesIntoParentWithoutTouchingTheStore
{
    NSManagedObjectContext *root = [self rootContext];
    NSManagedObjectContext *child = [self childOf:root];

    __block BOOL childSaved = NO;
    [child performBlockAndWait:^{
        NSManagedObject *note = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note" inManagedObjectContext:child];
        [note setValue:@"from the child" forKey:@"text"];
        NSError *err = nil;
        childSaved = [child save:&err];
        XCTAssertNil(err);
    }];
    XCTAssertTrue(childSaved);

    /* the child is clean, the parent is dirty */
    __block BOOL childHasChanges = YES, parentHasChanges = NO;
    [child performBlockAndWait:^{ childHasChanges = [child hasChanges]; }];
    [root performBlockAndWait:^{ parentHasChanges = [root hasChanges]; }];
    XCTAssertFalse(childHasChanges, @"a saved child context is clean");
    XCTAssertTrue(parentHasChanges, @"...its parent now carries the changes");

    /* the parent sees the object with its values */
    __block NSUInteger parentCount = 0;
    __block NSString *parentText = nil;
    [root performBlockAndWait:^{
        NSArray *found = [root executeFetchRequest:[self noteFetch] error:NULL];
        parentCount = [found count];
        parentText = [[found lastObject] valueForKey:@"text"];
    }];
    XCTAssertEqual(parentCount, (NSUInteger)1);
    XCTAssertEqualObjects(parentText, @"from the child");

    /* the store has NOT been written: an independent context sees nothing */
    NSManagedObjectContext *reader = [self rootContext];
    __block NSUInteger storeCount = 42;
    [reader performBlockAndWait:^{
        storeCount = [[reader executeFetchRequest:[self noteFetch] error:NULL] count];
    }];
    XCTAssertEqual(storeCount, (NSUInteger)0,
        @"only the root of the chain writes to disk");

    /* the root save lands it */
    __block BOOL rootSaved = NO;
    [root performBlockAndWait:^{ rootSaved = [root save:NULL]; }];
    XCTAssertTrue(rootSaved);
    [reader performBlockAndWait:^{
        storeCount = [[reader executeFetchRequest:[self noteFetch] error:NULL] count];
    }];
    XCTAssertEqual(storeCount, (NSUInteger)1);
}

- (void)testIDsStayTemporaryUntilTheRootSaves
{
    NSManagedObjectContext *root = [self rootContext];
    NSManagedObjectContext *child = [self childOf:root];

    __block NSManagedObject *note = nil;
    [child performBlockAndWait:^{
        note = [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                             inManagedObjectContext:child];
        [child save:NULL];
    }];

    __block BOOL temporaryAfterChildSave = NO;
    [child performBlockAndWait:^{
        temporaryAfterChildSave = [[note objectID] isTemporaryID];
    }];
    XCTAssertTrue(temporaryAfterChildSave,
        @"a child save does not mint permanent IDs");

    /* Capture the permanent ID by fetching it back - NOT via
       registeredObjects: on macOS nothing retains the absorbed object
       in the parent (retainsRegisteredObjects is off), so the
       registered set is empty again after the save.  An earlier
       version of this test tripped over exactly that. */
    __block NSManagedObjectID *parentID = nil;
    [root performBlockAndWait:^{
        [root save:NULL];
        NSArray *found = [root executeFetchRequest:[self noteFetch] error:NULL];
        parentID = [[found lastObject] objectID];
    }];
    XCTAssertNotNil(parentID);
    XCTAssertFalse([parentID isTemporaryID],
        @"the root save mints the permanent ID");

    /* As on Apple, the child's object keeps the temporary ID it has: the
       root's save gives the root's object its permanent ID, and a fetch in
       the child finds the object the child has. */
    __block BOOL childTemporary = NO;
    [child performBlockAndWait:^{
        [child executeFetchRequest:[self noteFetch] error:NULL];
        childTemporary = [[note objectID] isTemporaryID];
    }];
    XCTAssertTrue(childTemporary);
}

- (void)testChildFetchSeesParentsUnsavedChanges
{
    NSManagedObjectContext *root = [self rootContext];
    NSManagedObjectContext *child = [self childOf:root];

    [root performBlockAndWait:^{
        NSManagedObject *note = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note" inManagedObjectContext:root];
        [note setValue:@"unsaved in the parent" forKey:@"text"];
        /* NOT saved */
    }];

    __block NSUInteger count = 0;
    __block NSString *text = nil;
    [child performBlockAndWait:^{
        NSArray *found = [child executeFetchRequest:[self noteFetch] error:NULL];
        count = [found count];
        text = [[found lastObject] valueForKey:@"text"];
    }];
    XCTAssertEqual(count, (NSUInteger)1,
        @"the parent's CURRENT state is the child's baseline");
    XCTAssertEqualObjects(text, @"unsaved in the parent");
}

- (void)testChildFetchSeesStoreDataThroughTheChain
{
    /* a saved row, then a fresh two-level chain reads it */
    NSManagedObjectContext *writer = [self rootContext];
    [writer performBlockAndWait:^{
        NSManagedObject *note = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note" inManagedObjectContext:writer];
        [note setValue:@"on disk" forKey:@"text"];
        [writer save:NULL];
    }];

    NSManagedObjectContext *root = [self rootContext];
    NSManagedObjectContext *child = [self childOf:root];
    NSManagedObjectContext *grandchild = [self childOf:child];

    __block NSUInteger count = 0;
    __block NSString *text = nil;
    [grandchild performBlockAndWait:^{
        NSArray *found = [grandchild executeFetchRequest:[self noteFetch] error:NULL];
        count = [found count];
        text = [[found lastObject] valueForKey:@"text"];
    }];
    XCTAssertEqual(count, (NSUInteger)1);
    XCTAssertEqualObjects(text, @"on disk",
        @"values realize through every level of the chain");
}

- (void)testChildOverlaysItsOwnPendingChanges
{
    NSManagedObjectContext *writer = [self rootContext];
    [writer performBlockAndWait:^{
        NSManagedObject *note = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note" inManagedObjectContext:writer];
        [note setValue:@"saved" forKey:@"text"];
        [writer save:NULL];
    }];

    NSManagedObjectContext *root = [self rootContext];
    NSManagedObjectContext *child = [self childOf:root];

    __block NSUInteger count = 0;
    [child performBlockAndWait:^{
        /* one unsaved child insert alongside the stored row */
        [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                      inManagedObjectContext:child];
        count = [[child executeFetchRequest:[self noteFetch] error:NULL] count];
    }];
    XCTAssertEqual(count, (NSUInteger)2,
        @"child pending inserts overlay the parent's answer");

    [child performBlockAndWait:^{
        NSFetchRequest *fetch = [self noteFetch];
        [fetch setPredicate:[NSPredicate predicateWithFormat:@"text == %@", @"saved"]];
        NSManagedObject *stored = [[child executeFetchRequest:fetch error:NULL] lastObject];
        [child deleteObject:stored];
        count = [[child executeFetchRequest:[self noteFetch] error:NULL] count];
    }];
    XCTAssertEqual(count, (NSUInteger)1,
        @"child pending deletes drop out of the answer");
}

- (void)testUpdateAndDeleteFlowUpTheChain
{
    NSManagedObjectContext *writer = [self rootContext];
    [writer performBlockAndWait:^{
        NSManagedObject *a = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note" inManagedObjectContext:writer];
        [a setValue:@"keep me" forKey:@"text"];
        NSManagedObject *b = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note" inManagedObjectContext:writer];
        [b setValue:@"delete me" forKey:@"text"];
        [writer save:NULL];
    }];

    NSManagedObjectContext *root = [self rootContext];
    NSManagedObjectContext *child = [self childOf:root];

    [child performBlockAndWait:^{
        NSFetchRequest *keep = [self noteFetch];
        [keep setPredicate:[NSPredicate predicateWithFormat:@"text == %@", @"keep me"]];
        NSManagedObject *kept = [[child executeFetchRequest:keep error:NULL] lastObject];
        [kept setValue:@"updated in the child" forKey:@"text"];

        NSFetchRequest *doomed = [self noteFetch];
        [doomed setPredicate:[NSPredicate predicateWithFormat:@"text == %@", @"delete me"]];
        NSManagedObject *gone = [[child executeFetchRequest:doomed error:NULL] lastObject];
        [child deleteObject:gone];

        [child save:NULL];
    }];

    /* visible in the parent, not yet on disk */
    __block NSUInteger parentCount = 0;
    __block NSString *parentText = nil;
    [root performBlockAndWait:^{
        NSArray *found = [root executeFetchRequest:[self noteFetch] error:NULL];
        parentCount = [found count];
        parentText = [[found lastObject] valueForKey:@"text"];
        [root save:NULL];
    }];
    XCTAssertEqual(parentCount, (NSUInteger)1);
    XCTAssertEqualObjects(parentText, @"updated in the child");

    /* after the root save, on disk */
    NSManagedObjectContext *reader = [self rootContext];
    __block NSUInteger storeCount = 0;
    __block NSString *storeText = nil;
    [reader performBlockAndWait:^{
        NSArray *found = [reader executeFetchRequest:[self noteFetch] error:NULL];
        storeCount = [found count];
        storeText = [[found lastObject] valueForKey:@"text"];
    }];
    XCTAssertEqual(storeCount, (NSUInteger)1);
    XCTAssertEqualObjects(storeText, @"updated in the child");
}

- (void)testAutomaticallyMergesChangesFromParent
{
    NSManagedObjectContext *root = [self rootContext];
    NSManagedObjectContext *child = [self childOf:root];
    [child setAutomaticallyMergesChangesFromParent:YES];

    __block BOOL childNotified = NO;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                    object:child
                     queue:nil
                usingBlock:^(NSNotification *note) {
        if ([[[note userInfo] objectForKey:NSInsertedObjectsKey] count] > 0 ||
            [[[note userInfo] objectForKey:NSUpdatedObjectsKey] count] > 0 ||
            [[[note userInfo] objectForKey:NSRefreshedObjectsKey] count] > 0)
            childNotified = YES;
    }];

    [root performBlock:^{
        [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                      inManagedObjectContext:root];
        [root save:NULL];
    }];

    XCTAssertTrue(CDPWaitFor(5, ^{ return childNotified; }),
        @"the parent's save surfaces in the child automatically");
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testAutomaticallyMergesFromCoordinatorSiblings
{
    NSManagedObjectContext *receiver = [self rootContext];
    [receiver setAutomaticallyMergesChangesFromParent:YES];
    NSManagedObjectContext *sibling = [self rootContext];

    __block BOOL notified = NO;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
                    object:receiver
                     queue:nil
                usingBlock:^(NSNotification *note) { notified = YES; }];

    [sibling performBlock:^{
        [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                      inManagedObjectContext:sibling];
        [sibling save:NULL];
    }];

    XCTAssertTrue(CDPWaitFor(5, ^{ return notified; }),
        @"for a coordinator-backed context, 'parent' means the coordinator: "
        @"sibling saves merge in automatically");
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

/* Regression: a child-context transaction that inserts RELATED objects
   (owner + member of a to-many with an inverse) must survive the child
   save, the root save, and a fetch from the store, with the
   relationship intact in both directions.  (The parent-side absorb
   path once stored resolved objects where the internal representation
   keeps object IDs, and the root save crashed writing the inverse.) */
- (void)testChildSaveCarriesRelationshipsToTheStore
{
    /* A two-entity model of its own: the shared fixture has none. */
    NSAttributeDescription *title = [[NSAttributeDescription alloc] init];
    [title setName:@"title"];
    [title setAttributeType:NSStringAttributeType];
    [title setOptional:YES];

    NSAttributeDescription *itemText = [[NSAttributeDescription alloc] init];
    [itemText setName:@"text"];
    [itemText setAttributeType:NSStringAttributeType];
    [itemText setOptional:YES];

    NSEntityDescription *folder = [[NSEntityDescription alloc] init];
    [folder setName:@"Folder"];
    [folder setManagedObjectClassName:@"NSManagedObject"];

    NSEntityDescription *item = [[NSEntityDescription alloc] init];
    [item setName:@"Item"];
    [item setManagedObjectClassName:@"NSManagedObject"];

    NSRelationshipDescription *items = [[NSRelationshipDescription alloc] init];
    [items setName:@"items"];
    [items setDestinationEntity:item];
    [items setMaxCount:0];
    [items setOptional:YES];
    [items setDeleteRule:NSCascadeDeleteRule];

    NSRelationshipDescription *owner = [[NSRelationshipDescription alloc] init];
    [owner setName:@"folder"];
    [owner setDestinationEntity:folder];
    [owner setMaxCount:1];
    [owner setOptional:YES];
    [owner setDeleteRule:NSNullifyDeleteRule];

    [items setInverseRelationship:owner];
    [owner setInverseRelationship:items];
    [folder setProperties:[NSArray arrayWithObjects:title, items, nil]];
    [item setProperties:[NSArray arrayWithObjects:itemText, owner, nil]];

    NSManagedObjectModel *relModel = [[NSManagedObjectModel alloc] init];
    [relModel setEntities:[NSArray arrayWithObjects:folder, item, nil]];

    NSPersistentStoreCoordinator *relPsc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:relModel];
    NSString *relStorePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"parenting-rel-%@.sqlite",
         [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSError *err = nil;
    XCTAssertNotNil([relPsc addPersistentStoreWithType:NSSQLiteStoreType
                                         configuration:nil
                                                   URL:[NSURL fileURLWithPath:relStorePath]
                                               options:nil
                                                 error:&err], @"add store: %@", err);

    NSManagedObjectContext *root = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [root setPersistentStoreCoordinator:relPsc];

    NSManagedObjectContext *child = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [child setParentContext:root];

    NSManagedObject *newFolder = [NSEntityDescription
        insertNewObjectForEntityForName:@"Folder" inManagedObjectContext:child];
    [newFolder setValue:@"inbox" forKey:@"title"];
    NSManagedObject *newItem = [NSEntityDescription
        insertNewObjectForEntityForName:@"Item" inManagedObjectContext:child];
    [newItem setValue:@"hello" forKey:@"text"];
    [[newFolder mutableSetValueForKey:@"items"] addObject:newItem];

    XCTAssertTrue([child save:&err], @"child save: %@", err);
    XCTAssertTrue([root save:&err], @"root save: %@", err);

    /* A fresh context reads it back from the store, both directions. */
    NSManagedObjectContext *reader = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [reader setPersistentStoreCoordinator:relPsc];

    NSArray *folders = [reader executeFetchRequest:
        [NSFetchRequest fetchRequestWithEntityName:@"Folder"] error:&err];
    XCTAssertEqual([folders count], (NSUInteger)1, @"%@", err);

    NSManagedObject *fetchedFolder = [folders objectAtIndex:0];
    NSSet *fetchedItems = [fetchedFolder valueForKey:@"items"];
    XCTAssertEqual([fetchedItems count], (NSUInteger)1);

    NSManagedObject *fetchedItem = [fetchedItems anyObject];
    XCTAssertEqualObjects([fetchedItem valueForKey:@"text"], @"hello");
    XCTAssertEqualObjects([[fetchedItem valueForKey:@"folder"] objectID],
                          [fetchedFolder objectID],
        @"the inverse survives the trip through the chain and the store");

    for (NSPersistentStore *store in [[relPsc persistentStores] copy])
        [relPsc removePersistentStore:store error:NULL];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:relStorePath error:NULL];
    [fm removeItemAtPath:[relStorePath stringByAppendingString:@"-wal"] error:NULL];
    [fm removeItemAtPath:[relStorePath stringByAppendingString:@"-shm"] error:NULL];
}

@end
