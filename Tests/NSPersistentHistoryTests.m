/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSPersistentHistoryTests - persistent history tracking on the SQLite
   store: NSPersistentHistoryChangeRequest fetch/purge,
   NSPersistentHistoryTransaction/Change/Token, tombstones, the remote
   change notification and history replay via objectIDNotification.
   These compile on macOS against Apple CoreData, so every semantic
   asserted here is arbitrated by Apple's implementation. */

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

@interface NSPersistentHistoryTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSString *storePath;
@property (nonatomic, strong) NSManagedObjectContext *ctx;

@end

@implementation NSPersistentHistoryTests

- (NSManagedObjectModel *)makeModel
{
    NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
    [text setName:@"text"];
    [text setAttributeType:NSStringAttributeType];
    [text setOptional:YES];

    /* Deletions preserve this attribute's last value in the change's
       tombstone. */
    NSAttributeDescription *title = [[NSAttributeDescription alloc] init];
    [title setName:@"title"];
    [title setAttributeType:NSStringAttributeType];
    [title setOptional:YES];
    [title setPreservesValueInHistoryOnDeletion:YES];

    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"NSManagedObject"];
    [note setProperties:[NSArray arrayWithObjects:text, title, nil]];

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
        [NSString stringWithFormat:@"history-%@.sqlite",
         [[NSProcessInfo processInfo] globallyUniqueString]]];

    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:YES], NSPersistentHistoryTrackingKey,
        [NSNumber numberWithBool:YES], NSPersistentStoreRemoteChangeNotificationPostOptionKey,
        nil];
    NSError *err = nil;
    XCTAssertNotNil([self.psc
        addPersistentStoreWithType:NSSQLiteStoreType
                     configuration:nil
                               URL:[NSURL fileURLWithPath:self.storePath]
                           options:options
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

- (NSManagedObject *)insertNoteWithText:(NSString *)text
{
    NSManagedObject *note = [NSEntityDescription
        insertNewObjectForEntityForName:@"Note"
                 inManagedObjectContext:self.ctx];
    [note setValue:text forKey:@"text"];
    return note;
}

/* All transactions recorded so far, with their changes. */
- (NSArray *)fetchAllTransactions
{
    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]];
    NSError *err = nil;
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:request error:&err];
    XCTAssertNotNil(result, @"history fetch: %@", err);
    XCTAssertTrue([result isKindOfClass:[NSPersistentHistoryResult class]]);
    return [result result];
}

- (void)testSaveRecordsTransactionWithInsertChanges
{
    NSManagedObject *a = [self insertNoteWithText:@"a"];
    NSManagedObject *b = [self insertNoteWithText:@"b"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);

    NSArray *transactions = [self fetchAllTransactions];
    XCTAssertEqual((NSUInteger)1, [transactions count]);

    NSPersistentHistoryTransaction *tx = [transactions objectAtIndex:0];
    XCTAssertTrue([tx transactionNumber] > 0);
    XCTAssertNotNil([tx timestamp]);
    XCTAssertTrue(fabs([[tx timestamp] timeIntervalSinceNow]) < 60.0,
                  @"timestamp should be recent, got %@", [tx timestamp]);

    NSArray *changes = [tx changes];
    XCTAssertEqual((NSUInteger)2, [changes count]);

    NSMutableSet *changedURIs = [NSMutableSet set];
    for (NSPersistentHistoryChange *change in changes) {
        XCTAssertEqual(NSPersistentHistoryChangeTypeInsert, [change changeType]);
        XCTAssertNotNil([change changedObjectID]);
        [changedURIs addObject:[[[change changedObjectID] URIRepresentation] absoluteString]];
    }
    NSSet *expected = [NSSet setWithObjects:
        [[[a objectID] URIRepresentation] absoluteString],
        [[[b objectID] URIRepresentation] absoluteString], nil];
    XCTAssertEqualObjects(expected, changedURIs);
}

- (void)testTransactionRecordsAuthorAndContextName
{
    [self.ctx setTransactionAuthor:@"history-tests"];
    [self.ctx setName:@"main-context"];

    [self insertNoteWithText:@"authored"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);

    NSArray *transactions = [self fetchAllTransactions];
    XCTAssertEqual((NSUInteger)1, [transactions count]);

    NSPersistentHistoryTransaction *tx = [transactions objectAtIndex:0];
    XCTAssertEqualObjects(@"history-tests", [tx author]);
    XCTAssertEqualObjects(@"main-context", [tx contextName]);
}

- (void)testTokenFiltersOutEarlierTransactions
{
    [self insertNoteWithText:@"first"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save 1: %@", err);

    NSPersistentHistoryToken *token =
        [self.psc currentPersistentHistoryTokenFromStores:nil];
    XCTAssertNotNil(token);

    NSManagedObject *second = [self insertNoteWithText:@"second"];
    XCTAssertTrue([self.ctx save:&err], @"save 2: %@", err);

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterToken:token];
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:request error:&err];
    XCTAssertNotNil(result, @"history fetch: %@", err);

    NSArray *transactions = [result result];
    XCTAssertEqual((NSUInteger)1, [transactions count]);

    NSPersistentHistoryTransaction *tx = [transactions objectAtIndex:0];
    XCTAssertEqual((NSUInteger)1, [[tx changes] count]);
    XCTAssertEqualObjects(
        [[[second objectID] URIRepresentation] absoluteString],
        [[[[[tx changes] objectAtIndex:0] changedObjectID] URIRepresentation] absoluteString]);
}

- (void)testUpdateChangeCarriesUpdatedProperties
{
    NSManagedObject *note = [self insertNoteWithText:@"before"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"seed save: %@", err);

    NSPersistentHistoryToken *token =
        [self.psc currentPersistentHistoryTokenFromStores:nil];

    [note setValue:@"after" forKey:@"text"];
    XCTAssertTrue([self.ctx save:&err], @"update save: %@", err);

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterToken:token];
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:request error:&err];
    XCTAssertNotNil(result, @"history fetch: %@", err);

    NSArray *transactions = [result result];
    XCTAssertEqual((NSUInteger)1, [transactions count]);

    NSArray *changes = [[transactions objectAtIndex:0] changes];
    XCTAssertEqual((NSUInteger)1, [changes count]);

    NSPersistentHistoryChange *change = [changes objectAtIndex:0];
    XCTAssertEqual(NSPersistentHistoryChangeTypeUpdate, [change changeType]);

    NSMutableSet *names = [NSMutableSet set];
    for (NSPropertyDescription *property in [change updatedProperties])
        [names addObject:[property name]];
    XCTAssertTrue([names containsObject:@"text"],
                  @"updatedProperties %@ should include 'text'", names);
}

- (void)testDeleteChangeCarriesTombstone
{
    NSManagedObject *note = [self insertNoteWithText:@"doomed"];
    [note setValue:@"Keep Me" forKey:@"title"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"seed save: %@", err);

    NSPersistentHistoryToken *token =
        [self.psc currentPersistentHistoryTokenFromStores:nil];

    [self.ctx deleteObject:note];
    XCTAssertTrue([self.ctx save:&err], @"delete save: %@", err);

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterToken:token];
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:request error:&err];
    XCTAssertNotNil(result, @"history fetch: %@", err);

    NSArray *transactions = [result result];
    XCTAssertEqual((NSUInteger)1, [transactions count]);

    NSArray *changes = [[transactions objectAtIndex:0] changes];
    XCTAssertEqual((NSUInteger)1, [changes count]);

    NSPersistentHistoryChange *change = [changes objectAtIndex:0];
    XCTAssertEqual(NSPersistentHistoryChangeTypeDelete, [change changeType]);
    XCTAssertEqualObjects(@"Keep Me",
        [[change tombstone] objectForKey:@"title"],
        @"tombstone %@ should preserve the flagged attribute", [change tombstone]);
}

- (void)testDeleteHistoryBeforeTokenPurgesOlderTransactions
{
    [self insertNoteWithText:@"one"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save 1: %@", err);
    [self insertNoteWithText:@"two"];
    XCTAssertTrue([self.ctx save:&err], @"save 2: %@", err);

    NSArray *before = [self fetchAllTransactions];
    XCTAssertEqual((NSUInteger)2, [before count]);

    int64_t newest = [[before objectAtIndex:1] transactionNumber];

    NSPersistentHistoryToken *token =
        [self.psc currentPersistentHistoryTokenFromStores:nil];
    NSPersistentHistoryChangeRequest *purge =
        [NSPersistentHistoryChangeRequest deleteHistoryBeforeToken:token];
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:purge error:&err];
    XCTAssertNotNil(result, @"purge: %@", err);

    /* Arbitrated on macOS: "before" is strictly exclusive - purging
       before the current token removes older transactions but keeps
       the token's own (newest) transaction, even though a fetch after
       that token would not return it either. */
    NSArray *after = [self fetchAllTransactions];
    XCTAssertEqual((NSUInteger)1, [after count]);
    XCTAssertEqual(newest, [[after objectAtIndex:0] transactionNumber]);
}

- (void)testBatchInsertIsRecordedInHistory
{
    NSArray *rows = [NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObject:@"m1" forKey:@"text"],
        [NSDictionary dictionaryWithObject:@"m2" forKey:@"text"],
        [NSDictionary dictionaryWithObject:@"m3" forKey:@"text"],
        nil];
    NSBatchInsertRequest *insert = [[NSBatchInsertRequest alloc]
        initWithEntityName:@"Note" objects:rows];
    NSError *err = nil;
    XCTAssertNotNil([self.ctx executeRequest:insert error:&err],
                    @"batch insert: %@", err);

    NSArray *transactions = [self fetchAllTransactions];
    XCTAssertEqual((NSUInteger)1, [transactions count]);

    NSArray *changes = [[transactions objectAtIndex:0] changes];
    XCTAssertEqual((NSUInteger)3, [changes count]);
    for (NSPersistentHistoryChange *change in changes)
        XCTAssertEqual(NSPersistentHistoryChangeTypeInsert, [change changeType]);
}

- (void)testTokenRoundTripsThroughKeyedArchiving
{
    [self insertNoteWithText:@"tokenized"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);

    NSPersistentHistoryToken *token =
        [self.psc currentPersistentHistoryTokenFromStores:nil];
    XCTAssertNotNil(token);

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:token
                                         requiringSecureCoding:YES
                                                         error:&err];
    XCTAssertNotNil(data, @"archive: %@", err);

    NSPersistentHistoryToken *decoded =
        [NSKeyedUnarchiver unarchivedObjectOfClass:[NSPersistentHistoryToken class]
                                          fromData:data
                                             error:&err];
    XCTAssertNotNil(decoded, @"unarchive: %@", err);
    XCTAssertEqualObjects(token, decoded);
}

- (void)testRemoteChangeNotificationCarriesToken
{
    __block BOOL delivered = NO;
    __block NSDictionary *userInfo = nil;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSPersistentStoreRemoteChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        userInfo = [note userInfo];
        delivered = YES;
    }];

    [self insertNoteWithText:@"remote"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);

    XCTAssertTrue(CDWaitFor(5, ^{ return delivered; }),
                  @"remote change notification should be posted");
    XCTAssertTrue([[userInfo objectForKey:NSPersistentHistoryTokenKey]
                      isKindOfClass:[NSPersistentHistoryToken class]],
                  @"userInfo %@ should carry a history token", userInfo);

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testObjectIDNotificationReplaysHistoryIntoAnotherContext
{
    NSManagedObject *note = [self insertNoteWithText:@"original"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"seed save: %@", err);

    /* A second context with the object registered and materialized. */
    NSManagedObjectContext *other = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [other setPersistentStoreCoordinator:self.psc];
    NSManagedObject *mirror = [other objectWithID:[note objectID]];
    XCTAssertEqualObjects(@"original", [mirror valueForKey:@"text"]);

    NSPersistentHistoryToken *token =
        [self.psc currentPersistentHistoryTokenFromStores:nil];

    [note setValue:@"replayed" forKey:@"text"];
    XCTAssertTrue([self.ctx save:&err], @"update save: %@", err);

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterToken:token];
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[other executeRequest:request error:&err];
    XCTAssertNotNil(result, @"history fetch: %@", err);

    NSArray *transactions = [result result];
    XCTAssertEqual((NSUInteger)1, [transactions count]);

    for (NSPersistentHistoryTransaction *tx in transactions)
        [other mergeChangesFromContextDidSaveNotification:[tx objectIDNotification]];

    XCTAssertEqualObjects(@"replayed", [mirror valueForKey:@"text"],
                          @"replaying history should refresh the registered object");
}

/* Apple's context-less +entityDescription / +fetchRequest answer nil
   unless a loaded persistent container lets CoreData find "the" model
   (arbitrated on macOS: they were nil under this test's bare
   coordinator), so the portable construction goes through
   entityDescriptionWithContext:. */
- (NSFetchRequest *)historyFetchRequestWithEntity:(NSEntityDescription *)entity
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:entity];
    return fetch;
}

- (void)testFetchRequestFlavorEchoesRequest
{
    NSEntityDescription *txEntity =
        [NSPersistentHistoryTransaction entityDescriptionWithContext:self.ctx];
    NSEntityDescription *changeEntity =
        [NSPersistentHistoryChange entityDescriptionWithContext:self.ctx];
    XCTAssertNotNil(txEntity);
    XCTAssertNotNil(changeEntity);
    XCTAssertEqualObjects(@"Transaction", [txEntity name]);
    XCTAssertEqualObjects(@"Change", [changeEntity name]);

    NSFetchRequest *fetch = [self historyFetchRequestWithEntity:txEntity];

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryWithFetchRequest:fetch];
    XCTAssertEqualObjects(fetch, [request fetchRequest]);
    XCTAssertEqual(NSPersistentHistoryResultTypeTransactionsAndChanges,
                   [request resultType]);
}

/* The canonical multi-writer merge filter: each writer sets a distinct
   transactionAuthor and merges only the other writers' transactions. */
- (void)testAuthorPredicateFiltersTransactions
{
    [self.ctx setTransactionAuthor:@"writer-a"];
    [self insertNoteWithText:@"from a"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save a: %@", err);

    [self.ctx setTransactionAuthor:@"writer-b"];
    NSManagedObject *fromB = [self insertNoteWithText:@"from b"];
    XCTAssertTrue([self.ctx save:&err], @"save b: %@", err);

    NSFetchRequest *fetch = [self historyFetchRequestWithEntity:
        [NSPersistentHistoryTransaction entityDescriptionWithContext:self.ctx]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"author != %@",
                                                         @"writer-a"]];

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryWithFetchRequest:fetch];
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:request error:&err];
    XCTAssertNotNil(result, @"filtered fetch: %@", err);

    NSArray *transactions = [result result];
    XCTAssertEqual((NSUInteger)1, [transactions count]);

    NSPersistentHistoryTransaction *tx = [transactions objectAtIndex:0];
    XCTAssertEqualObjects(@"writer-b", [tx author]);
    XCTAssertEqual((NSUInteger)1, [[tx changes] count]);
    XCTAssertEqualObjects(
        [[[fromB objectID] URIRepresentation] absoluteString],
        [[[[[tx changes] objectAtIndex:0] changedObjectID] URIRepresentation] absoluteString]);
}

- (void)testTransactionNumberPredicateFiltersTransactions
{
    [self insertNoteWithText:@"first"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save 1: %@", err);
    [self insertNoteWithText:@"second"];
    XCTAssertTrue([self.ctx save:&err], @"save 2: %@", err);

    int64_t firstNumber =
        [[[self fetchAllTransactions] objectAtIndex:0] transactionNumber];

    NSFetchRequest *fetch = [self historyFetchRequestWithEntity:
        [NSPersistentHistoryTransaction entityDescriptionWithContext:self.ctx]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"transactionNumber > %@",
        [NSNumber numberWithLongLong:firstNumber]]];

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryWithFetchRequest:fetch];
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:request error:&err];
    XCTAssertNotNil(result, @"filtered fetch: %@", err);

    NSArray *transactions = [result result];
    XCTAssertEqual((NSUInteger)1, [transactions count]);
    XCTAssertTrue([[transactions objectAtIndex:0] transactionNumber] > firstNumber);
}

- (void)testChangeEntityPredicateFiltersChanges
{
    NSManagedObject *tracked = [self insertNoteWithText:@"tracked"];
    [self insertNoteWithText:@"noise"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"seed save: %@", err);

    [tracked setValue:@"tracked v2" forKey:@"text"];
    XCTAssertTrue([self.ctx save:&err], @"update save: %@", err);

    NSFetchRequest *fetch = [self historyFetchRequestWithEntity:
        [NSPersistentHistoryChange entityDescriptionWithContext:self.ctx]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"changedObjectID == %@",
                                                         [tracked objectID]]];

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryWithFetchRequest:fetch];
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:request error:&err];
    XCTAssertNotNil(result, @"filtered fetch: %@", err);

    /* Arbitrated on macOS: a Change-entity fetch request answers the
       matching changes themselves, not transactions.  The tracked
       object was touched twice (insert, then update); the first save's
       "noise" insert is filtered out. */
    NSArray *changes = [result result];
    XCTAssertEqual((NSUInteger)2, [changes count]);

    NSString *trackedURI = [[[tracked objectID] URIRepresentation] absoluteString];
    NSMutableSet *changeTypes = [NSMutableSet set];
    for (NSPersistentHistoryChange *change in changes) {
        XCTAssertEqualObjects(trackedURI,
            [[[change changedObjectID] URIRepresentation] absoluteString]);
        [changeTypes addObject:[NSNumber numberWithInteger:[change changeType]]];
    }
    XCTAssertTrue([changeTypes containsObject:
        [NSNumber numberWithInteger:NSPersistentHistoryChangeTypeInsert]]);
    XCTAssertTrue([changeTypes containsObject:
        [NSNumber numberWithInteger:NSPersistentHistoryChangeTypeUpdate]]);
}

/* Arbitrated on macOS: sort descriptors on a history fetch raise for
   every public keypath (Apple resolves them against its internal
   TRANSACTION entity, whose attribute names differ from the public
   accessors - transactionNumber and timestamp both threw "keypath not
   found in entity TRANSACTION"), even though the same keypaths work in
   a predicate.  History results are consumed in transaction order. */
- (void)testSortDescriptorsAreRejectedOnHistoryFetches
{
    [self insertNoteWithText:@"unsortable"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);

    NSFetchRequest *fetch = [self historyFetchRequestWithEntity:
        [NSPersistentHistoryTransaction entityDescriptionWithContext:self.ctx]];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"timestamp"
                                      ascending:NO]]];

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryWithFetchRequest:fetch];
    XCTAssertThrowsSpecificNamed(
        [self.ctx executeRequest:request error:NULL],
        NSException, NSInvalidArgumentException,
        @"sorted history fetches raise on Apple; the port matches");
}

/* The arrangement the Bulletin example is built on: a second, fully
   independent stack (its own coordinator, its own context) on the SAME
   store file, whose saves the first stack replays via the canonical
   token-anchored, author-filtered history fetch. */
- (void)testTwoStacksOnOneFileSyncThroughHistory
{
    /* Arbitrated on macOS: without this, the final assertion reads the
       OLD value.  Apple caches fetched rows per coordinator, and a
       refresh refetches through that cache; with the default (infinite)
       staleness interval, a row written by ANOTHER coordinator stays
       invisible to this stack forever, merge or no merge.  A history
       consumer that shares its store file with other writers sets the
       staleness interval to 0 so every refresh goes back to the store.
       (FreeCoreData reads the store on every refresh regardless, so
       this is a no-op there.) */
    [self.ctx setStalenessInterval:0];

    /* The mirror object exists first, so the first stack has something
       registered to refresh. */
    NSManagedObject *note = [self insertNoteWithText:@"v1"];
    [self.ctx setTransactionAuthor:@"reader"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"seed save: %@", err);

    NSPersistentHistoryToken *token =
        [self.psc currentPersistentHistoryTokenFromStores:nil];

    /* An independent writer stack on the same file. */
    NSPersistentStoreCoordinator *writerPSC = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:self.model];
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:YES], NSPersistentHistoryTrackingKey, nil];
    XCTAssertNotNil([writerPSC addPersistentStoreWithType:NSSQLiteStoreType
                                            configuration:nil
                                                      URL:[NSURL fileURLWithPath:self.storePath]
                                                  options:options
                                                    error:&err], @"writer store: %@", err);

    NSManagedObjectContext *writerCtx = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [writerCtx setPersistentStoreCoordinator:writerPSC];
    [writerCtx setTransactionAuthor:@"writer"];

    NSManagedObject *writerNote = [writerCtx objectWithID:[note objectID]];
    XCTAssertEqualObjects(@"v1", [writerNote valueForKey:@"text"]);
    [writerNote setValue:@"v2" forKey:@"text"];
    XCTAssertTrue([writerCtx save:&err], @"writer save: %@", err);

    /* The reader has not heard about it... */
    XCTAssertEqualObjects(@"v1", [note valueForKey:@"text"]);

    /* ...until it runs the canonical merge against its own stack. */
    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterToken:token];
    NSFetchRequest *othersOnly = [self historyFetchRequestWithEntity:
        [NSPersistentHistoryTransaction entityDescriptionWithContext:self.ctx]];
    [othersOnly setPredicate:[NSPredicate predicateWithFormat:@"author != %@", @"reader"]];
    [request setFetchRequest:othersOnly];

    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:request error:&err];
    XCTAssertNotNil(result, @"history fetch: %@", err);

    NSArray *transactions = [result result];
    XCTAssertEqual((NSUInteger)1, [transactions count]);
    XCTAssertEqualObjects(@"writer", [[transactions objectAtIndex:0] author]);

    for (NSPersistentHistoryTransaction *tx in transactions)
        [self.ctx mergeChangesFromContextDidSaveNotification:[tx objectIDNotification]];

    XCTAssertEqualObjects(@"v2", [note valueForKey:@"text"],
                          @"the merge should refresh the reader's registered object");

    for (NSPersistentStore *store in [[writerPSC persistentStores] copy])
        [writerPSC removePersistentStore:store error:NULL];
}

- (void)testResultTypeVariants
{
    [self insertNoteWithText:@"variant"];
    NSError *err = nil;
    XCTAssertTrue([self.ctx save:&err], @"save: %@", err);

    /* Count: the number of matching transactions, as an NSNumber. */
    NSPersistentHistoryChangeRequest *countRequest =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]];
    [countRequest setResultType:NSPersistentHistoryResultTypeCount];
    NSPersistentHistoryResult *countResult =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:countRequest error:&err];
    XCTAssertNotNil(countResult, @"count fetch: %@", err);
    XCTAssertEqualObjects([NSNumber numberWithUnsignedInteger:1],
                          [countResult result]);

    /* TransactionsOnly: transactions whose changes are nil. */
    NSPersistentHistoryChangeRequest *txOnlyRequest =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]];
    [txOnlyRequest setResultType:NSPersistentHistoryResultTypeTransactionsOnly];
    NSPersistentHistoryResult *txOnlyResult =
        (NSPersistentHistoryResult *)[self.ctx executeRequest:txOnlyRequest error:&err];
    XCTAssertNotNil(txOnlyResult, @"transactions-only fetch: %@", err);

    NSArray *transactions = [txOnlyResult result];
    XCTAssertEqual((NSUInteger)1, [transactions count]);
    XCTAssertNil([[transactions objectAtIndex:0] changes]);
}

@end
