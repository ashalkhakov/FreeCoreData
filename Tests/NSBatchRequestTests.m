/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSBatchRequestTests - NSBatchInsertRequest / NSBatchUpdateRequest /
   NSBatchDeleteRequest through executeRequest:error: on the SQLite
   store, and mergeChangesFromRemoteContextSave:intoContexts:.  These
   compile on macOS against Apple CoreData, so every semantic asserted
   here is arbitrated by Apple's implementation. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

@interface NSBatchRequestTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSString *storePath;
@property (nonatomic, strong) NSManagedObjectContext *ctx;

@end

@implementation NSBatchRequestTests

- (NSManagedObjectModel *)makeModel
{
    NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
    [text setName:@"text"];
    [text setAttributeType:NSStringAttributeType];
    [text setOptional:YES];

    NSAttributeDescription *rank = [[NSAttributeDescription alloc] init];
    [rank setName:@"rank"];
    [rank setAttributeType:NSInteger64AttributeType];
    [rank setOptional:YES];
    [rank setDefaultValue:[NSNumber numberWithLongLong:7]];

    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"NSManagedObject"];
    [note setProperties:[NSArray arrayWithObjects:text, rank, nil]];

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
        [NSString stringWithFormat:@"batch-%@.sqlite",
         [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSError *err = nil;
    XCTAssertNotNil([self.psc
        addPersistentStoreWithType:NSSQLiteStoreType
                     configuration:nil
                               URL:[NSURL fileURLWithPath:self.storePath]
                           options:nil
                             error:&err], @"add store: %@", err);

    /* XCTest runs on the main thread, which is a main-queue context's
       own queue, so the context is used directly (the viewContext
       pattern). */
    self.ctx = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [self.ctx setPersistentStoreCoordinator:self.psc];
}

- (void)tearDown
{
    self.ctx = nil;
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

/* Saves one Note per string through the ordinary context machinery. */
- (NSArray *)seedTexts:(NSArray *)texts
{
    NSMutableArray *objects = [NSMutableArray array];
    for (NSString *text in texts) {
        NSManagedObject *note = [NSEntityDescription
            insertNewObjectForEntityForName:@"Note"
                     inManagedObjectContext:self.ctx];
        [note setValue:text forKey:@"text"];
        [objects addObject:note];
    }
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"seed save: %@", err);
    return objects;
}

- (NSArray *)fetchTextsSortedInFreshContext
{
    NSManagedObjectContext *fresh = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [fresh setPersistentStoreCoordinator:self.psc];

    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]]];
    NSError *err = nil;
    NSArray *rows = [fresh executeFetchRequest:fetch error:&err];
    XCTAssertNotNil(rows, @"%@", err);

    NSMutableArray *texts = [NSMutableArray array];
    for (NSManagedObject *row in rows)
        [texts addObject:[row valueForKey:@"text"]];
    return texts;
}

/* ---------------------------------------------------------------- */

- (void)testBatchRequestShapes
{
    NSBatchInsertRequest *insert = [[NSBatchInsertRequest alloc]
        initWithEntityName:@"Note"
                   objects:[NSArray arrayWithObject:
                               [NSDictionary dictionaryWithObject:@"x" forKey:@"text"]]];
    XCTAssertEqual([insert requestType], (NSPersistentStoreRequestType)NSBatchInsertRequestType);
    XCTAssertEqualObjects([insert entityName], @"Note");
    XCTAssertEqual([insert resultType], NSBatchInsertRequestResultTypeStatusOnly);

    NSBatchUpdateRequest *update = [[NSBatchUpdateRequest alloc]
        initWithEntityName:@"Note"];
    XCTAssertEqual([update requestType], (NSPersistentStoreRequestType)NSBatchUpdateRequestType);
    XCTAssertEqualObjects([update entityName], @"Note");
    XCTAssertEqual([update resultType], NSStatusOnlyResultType);

    NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc]
        initWithFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Note"]];
    XCTAssertEqual([delete requestType], (NSPersistentStoreRequestType)NSBatchDeleteRequestType);
    XCTAssertEqual([delete resultType], NSBatchDeleteResultTypeStatusOnly);
    XCTAssertNotNil([delete fetchRequest]);
}

- (void)testBatchInsertInsertsRowsBypassingTheContext
{
    NSArray *dicts = [NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObject:@"a" forKey:@"text"],
        [NSDictionary dictionaryWithObject:@"b" forKey:@"text"],
        [NSDictionary dictionaryWithObject:@"c" forKey:@"text"],
        nil];
    NSBatchInsertRequest *insert = [[NSBatchInsertRequest alloc]
        initWithEntityName:@"Note" objects:dicts];
    [insert setResultType:NSBatchInsertRequestResultTypeCount];

    NSError *err = nil;
    NSBatchInsertResult *result =
        (NSBatchInsertResult *)[self.ctx executeRequest:insert error:&err];
    XCTAssertNotNil(result, @"%@", err);
    XCTAssertTrue([result isKindOfClass:[NSBatchInsertResult class]]);
    XCTAssertEqualObjects([result result], [NSNumber numberWithUnsignedInteger:3]);

    /* the context was bypassed entirely */
    XCTAssertEqual([[self.ctx insertedObjects] count], (NSUInteger)0);
    XCTAssertFalse([self.ctx hasChanges]);

    XCTAssertEqualObjects([self fetchTextsSortedInFreshContext],
        ([NSArray arrayWithObjects:@"a", @"b", @"c", nil]));
}

- (void)testBatchInsertAppliesModelDefaultValues
{
    NSBatchInsertRequest *insert = [[NSBatchInsertRequest alloc]
        initWithEntityName:@"Note"
                   objects:[NSArray arrayWithObject:
                               [NSDictionary dictionaryWithObject:@"defaulted" forKey:@"text"]]];
    NSError *err = nil;
    XCTAssertNotNil([self.ctx executeRequest:insert error:&err], @"%@", err);

    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    NSArray *rows = [self.ctx executeFetchRequest:fetch error:&err];
    XCTAssertEqual([rows count], (NSUInteger)1);
    XCTAssertEqualObjects([[rows objectAtIndex:0] valueForKey:@"rank"],
        [NSNumber numberWithLongLong:7],
        @"attributes absent from the dictionary take the model default");
}

- (void)testBatchInsertObjectIDResultsAreUsable
{
    NSBatchInsertRequest *insert = [[NSBatchInsertRequest alloc]
        initWithEntityName:@"Note"
                   objects:[NSArray arrayWithObjects:
                               [NSDictionary dictionaryWithObject:@"one" forKey:@"text"],
                               [NSDictionary dictionaryWithObject:@"two" forKey:@"text"],
                               nil]];
    [insert setResultType:NSBatchInsertRequestResultTypeObjectIDs];

    NSError *err = nil;
    NSBatchInsertResult *result =
        (NSBatchInsertResult *)[self.ctx executeRequest:insert error:&err];
    XCTAssertNotNil(result, @"%@", err);

    NSArray *objectIDs = [result result];
    XCTAssertEqual([objectIDs count], (NSUInteger)2);

    NSMutableSet *texts = [NSMutableSet set];
    for (NSManagedObjectID *objectID in objectIDs) {
        XCTAssertFalse([objectID isTemporaryID]);
        NSManagedObject *object = [self.ctx existingObjectWithID:objectID error:&err];
        XCTAssertNotNil(object, @"%@", err);
        [texts addObject:[object valueForKey:@"text"]];
    }
    XCTAssertEqualObjects(texts,
        ([NSSet setWithObjects:@"one", @"two", nil]));
}

- (void)testBatchInsertDictionaryHandler
{
    __block NSUInteger index = 0;
    NSBatchInsertRequest *insert = [[NSBatchInsertRequest alloc]
        initWithEntityName:@"Note"
         dictionaryHandler:^BOOL(NSMutableDictionary *obj) {
             if (index == 2)
                 return YES;   /* done; this dictionary is not inserted */
             [obj setObject:[NSString stringWithFormat:@"row-%lu", (unsigned long)index]
                     forKey:@"text"];
             index++;
             return NO;
         }];
    [insert setResultType:NSBatchInsertRequestResultTypeCount];

    NSError *err = nil;
    NSBatchInsertResult *result =
        (NSBatchInsertResult *)[self.ctx executeRequest:insert error:&err];
    XCTAssertNotNil(result, @"%@", err);
    XCTAssertEqualObjects([result result], [NSNumber numberWithUnsignedInteger:2]);
    XCTAssertEqualObjects([self fetchTextsSortedInFreshContext],
        ([NSArray arrayWithObjects:@"row-0", @"row-1", nil]));
}

- (void)testBatchUpdateUpdatesTheStoreButNotLoadedObjects
{
    NSArray *seeded = [self seedTexts:[NSArray arrayWithObjects:@"a", @"b", @"c", nil]];
    NSManagedObject *b = [seeded objectAtIndex:1];

    NSBatchUpdateRequest *update = [[NSBatchUpdateRequest alloc]
        initWithEntityName:@"Note"];
    [update setPredicate:[NSPredicate predicateWithFormat:@"text == %@", @"b"]];
    [update setPropertiesToUpdate:[NSDictionary dictionaryWithObject:
        [NSExpression expressionForConstantValue:@"B"] forKey:@"text"]];
    [update setResultType:NSUpdatedObjectsCountResultType];

    NSError *err = nil;
    NSBatchUpdateResult *result =
        (NSBatchUpdateResult *)[self.ctx executeRequest:update error:&err];
    XCTAssertNotNil(result, @"%@", err);
    XCTAssertTrue([result isKindOfClass:[NSBatchUpdateResult class]]);
    XCTAssertEqualObjects([result result], [NSNumber numberWithUnsignedInteger:1]);

    /* the store has the new value... */
    XCTAssertEqualObjects([self fetchTextsSortedInFreshContext],
        ([NSArray arrayWithObjects:@"B", @"a", @"c", nil]));

    /* ...but the loaded object was bypassed and is stale */
    XCTAssertEqualObjects([b valueForKey:@"text"], @"b",
        @"batch updates bypass loaded contexts");

    /* refreshing re-reads the row */
    [self.ctx refreshObject:b mergeChanges:NO];
    XCTAssertEqualObjects([b valueForKey:@"text"], @"B");
}

- (void)testBatchUpdateObjectIDsResult
{
    NSArray *seeded = [self seedTexts:[NSArray arrayWithObjects:@"a", @"b", nil]];
    NSManagedObject *b = [seeded objectAtIndex:1];

    NSBatchUpdateRequest *update = [[NSBatchUpdateRequest alloc]
        initWithEntityName:@"Note"];
    [update setPredicate:[NSPredicate predicateWithFormat:@"text == %@", @"b"]];
    [update setPropertiesToUpdate:[NSDictionary dictionaryWithObject:@"B" forKey:@"text"]];
    [update setResultType:NSUpdatedObjectIDsResultType];

    NSError *err = nil;
    NSBatchUpdateResult *result =
        (NSBatchUpdateResult *)[self.ctx executeRequest:update error:&err];
    XCTAssertNotNil(result, @"%@", err);

    NSArray *objectIDs = [result result];
    XCTAssertEqual([objectIDs count], (NSUInteger)1);
    XCTAssertEqualObjects([objectIDs objectAtIndex:0], [b objectID]);
}

- (void)testBatchDeleteViaFetchRequest
{
    [self seedTexts:[NSArray arrayWithObjects:@"a", @"b", @"c", nil]];

    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"text != %@", @"b"]];

    NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc]
        initWithFetchRequest:fetch];
    [delete setResultType:NSBatchDeleteResultTypeCount];

    NSError *err = nil;
    NSBatchDeleteResult *result =
        (NSBatchDeleteResult *)[self.ctx executeRequest:delete error:&err];
    XCTAssertNotNil(result, @"%@", err);
    XCTAssertTrue([result isKindOfClass:[NSBatchDeleteResult class]]);
    XCTAssertEqualObjects([result result], [NSNumber numberWithUnsignedInteger:2]);

    XCTAssertEqualObjects([self fetchTextsSortedInFreshContext],
        [NSArray arrayWithObject:@"b"]);
}

- (void)testBatchDeleteViaObjectIDs
{
    NSArray *seeded = [self seedTexts:[NSArray arrayWithObjects:@"keep", @"drop", nil]];
    NSManagedObjectID *dropID = [(NSManagedObject *)[seeded objectAtIndex:1] objectID];

    NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc]
        initWithObjectIDs:[NSArray arrayWithObject:dropID]];
    [delete setResultType:NSBatchDeleteResultTypeCount];

    NSError *err = nil;
    NSBatchDeleteResult *result =
        (NSBatchDeleteResult *)[self.ctx executeRequest:delete error:&err];
    XCTAssertNotNil(result, @"%@", err);
    XCTAssertEqualObjects([result result], [NSNumber numberWithUnsignedInteger:1]);

    XCTAssertEqualObjects([self fetchTextsSortedInFreshContext],
        [NSArray arrayWithObject:@"keep"]);
}

- (void)testBatchRequestsOnUnsupportedStoresReportAnError
{
    NSPersistentStoreCoordinator *memory = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:self.model];
    NSError *err = nil;
    XCTAssertNotNil([memory addPersistentStoreWithType:NSInMemoryStoreType
                                         configuration:nil
                                                   URL:nil
                                               options:nil
                                                 error:&err], @"%@", err);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [ctx setPersistentStoreCoordinator:memory];

    NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc]
        initWithFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Note"]];

    NSError *batchErr = nil;
    NSPersistentStoreResult *result = nil;
    @try {
        result = [ctx executeRequest:delete error:&batchErr];
    }
    @catch (NSException *e) {
        /* also acceptable: some implementations raise instead */
        return;
    }
    XCTAssertNil(result, @"batch requests need a SQLite store");
    XCTAssertNotNil(batchErr);
}

- (void)testMergeChangesFromRemoteContextSaveRefreshesUpdates
{
    NSArray *seeded = [self seedTexts:[NSArray arrayWithObject:@"old"]];
    NSManagedObject *object = [seeded objectAtIndex:0];

    NSBatchUpdateRequest *update = [[NSBatchUpdateRequest alloc]
        initWithEntityName:@"Note"];
    [update setPropertiesToUpdate:[NSDictionary dictionaryWithObject:@"new" forKey:@"text"]];
    [update setResultType:NSUpdatedObjectIDsResultType];

    NSError *err = nil;
    NSBatchUpdateResult *result =
        (NSBatchUpdateResult *)[self.ctx executeRequest:update error:&err];
    XCTAssertNotNil(result, @"%@", err);
    XCTAssertEqualObjects([object valueForKey:@"text"], @"old", @"stale before the merge");

    [NSManagedObjectContext
        mergeChangesFromRemoteContextSave:[NSDictionary dictionaryWithObject:[result result]
                                                                      forKey:NSUpdatedObjectsKey]
                             intoContexts:[NSArray arrayWithObject:self.ctx]];

    XCTAssertEqualObjects([object valueForKey:@"text"], @"new",
        @"the merge refreshes registered objects from the store");
}

- (void)testMergeChangesFromRemoteContextSaveAppliesDeletes
{
    NSArray *seeded = [self seedTexts:[NSArray arrayWithObject:@"doomed"]];
    NSManagedObject *object = [seeded objectAtIndex:0];

    NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc]
        initWithObjectIDs:[NSArray arrayWithObject:[object objectID]]];
    [delete setResultType:NSBatchDeleteResultTypeObjectIDs];

    NSError *err = nil;
    NSBatchDeleteResult *result =
        (NSBatchDeleteResult *)[self.ctx executeRequest:delete error:&err];
    XCTAssertNotNil(result, @"%@", err);
    XCTAssertEqual([(NSArray *)[result result] count], (NSUInteger)1);

    [NSManagedObjectContext
        mergeChangesFromRemoteContextSave:[NSDictionary dictionaryWithObject:[result result]
                                                                      forKey:NSDeletedObjectsKey]
                             intoContexts:[NSArray arrayWithObject:self.ctx]];

    XCTAssertTrue([object isDeleted],
        @"the merge marks registered instances of remotely deleted rows as deleted");
}

@end
