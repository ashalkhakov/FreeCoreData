/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSSQLitePersistentStoreTests - tests for the SQLite store
   (NSSQLiteStoreType).  These tests are written against Apple's documented
   behavior so they run identically against Apple's CoreData on macOS and
   against the GNUstep port; run them on macOS to validate assumptions
   about Apple's SQLite store implementation. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"
#import <sqlite3.h>

/* FreeCoreData's, declared here when building against Apple's. */
#if __has_include(<CoreData/CDExternalDataStore.h>)
#import <CoreData/CDExternalDataStore.h>
#else
@protocol CDExternalDataStore <NSObject>
- (BOOL)writeData:(NSData *)data named:(NSString *)name error:(NSError **)error;
- (NSData *)dataNamed:(NSString *)name;
- (BOOL)removeDataNamed:(NSString *)name error:(NSError **)error;
@optional
- (BOOL)removeAllDataWithError:(NSError **)error;
- (BOOL)copyDataNamed:(NSString *)name toName:(NSString *)newName error:(NSError **)error;
@end
@protocol CDExternalDataReference <NSObject>
- (id<CDExternalDataStore>)externalDataStore;
- (NSString *)externalDataName;
@end
#endif

/* Values kept the way a store keeping them in S3 would keep them: read
   only when their bytes are needed (a GET), copied by the server, and
   written by requests that can fail. */
@class RemoteLikeExternalDataStore;

@interface RemoteLikeData : NSData <CDExternalDataReference>
@property (nonatomic, strong) RemoteLikeExternalDataStore *store;
@property (nonatomic, copy) NSString *name;
@end

@interface RemoteLikeExternalDataStore : NSObject <CDExternalDataStore>
@property (nonatomic, strong) NSMutableDictionary *kept;
@property (nonatomic, assign) int writes, copies, loads, writesBeforeFailing;
@end

@implementation RemoteLikeData
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)freeWhenDone
{
    return self;   /* what GNUstep's -[NSData init] calls */
}
- (const void *)bytes
{
    self.store.loads++;
    return [self.store.kept[self.name] bytes];
}
- (NSUInteger)length
{
    return [self.store.kept[self.name] length];   /* a HEAD, not a GET */
}
- (id<CDExternalDataStore>)externalDataStore
{
    return self.store;
}
- (NSString *)externalDataName
{
    return self.name;
}
@end

@implementation RemoteLikeExternalDataStore
- (instancetype)init
{
    if ((self = [super init]) != nil) {
        _kept = [NSMutableDictionary dictionary];
        _writesBeforeFailing = -1;
    }
    return self;
}
- (BOOL)writeData:(NSData *)data named:(NSString *)name error:(NSError **)error
{
    if (self.writesBeforeFailing == 0) {
        if (error != NULL)
            *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
        return NO;
    }
    if (self.writesBeforeFailing > 0)
        self.writesBeforeFailing--;
    self.writes++;
    self.kept[name] = [NSData dataWithBytes:[data bytes] length:[data length]];
    return YES;
}
- (NSData *)dataNamed:(NSString *)name
{
    RemoteLikeData *data = [[RemoteLikeData alloc] init];
    data.store = self;
    data.name = name;
    return data;
}
- (BOOL)removeDataNamed:(NSString *)name error:(NSError **)error
{
    [self.kept removeObjectForKey:name];
    return YES;
}
- (BOOL)copyDataNamed:(NSString *)name toName:(NSString *)newName error:(NSError **)error
{
    self.copies++;
    self.kept[newName] = self.kept[name];
    return YES;
}
@end

/* Values kept in memory: what a store keeping its external values in S3,
   say, looks like to it. */
@interface MemoryExternalDataStore : NSObject <CDExternalDataStore>
@property (nonatomic, strong) NSMutableDictionary *kept;
@property (nonatomic, assign) int removedAll;
@end

@implementation MemoryExternalDataStore
- (instancetype)init
{
    if ((self = [super init]) != nil)
        _kept = [NSMutableDictionary dictionary];
    return self;
}
- (BOOL)writeData:(NSData *)data named:(NSString *)name error:(NSError **)error
{
    self.kept[name] = [data copy];
    return YES;
}
- (NSData *)dataNamed:(NSString *)name
{
    return self.kept[name];
}
- (BOOL)removeDataNamed:(NSString *)name error:(NSError **)error
{
    [self.kept removeObjectForKey:name];
    return YES;
}
- (BOOL)removeAllDataWithError:(NSError **)error
{
    self.removedAll++;
    [self.kept removeAllObjects];
    return YES;
}
@end

@interface NSSQLitePersistentStoreTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;
/* Every coordinator -contextWithModel:options: made, for its store to be
   closed before the files go (on Windows an open file is not deleted). */
@property (nonatomic, strong) NSMutableArray *coordinators;

@end

@implementation NSSQLitePersistentStoreTests

- (void)setUp
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"sqlite"];
    self.storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
}

- (void)removeStoreFilesAtURL:(NSURL *)url
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    for (NSPersistentStoreCoordinator *psc in self.coordinators)
        for (NSPersistentStore *store in [psc persistentStores])
            [psc removePersistentStore:store error:NULL];
    [self.coordinators removeAllObjects];

    [fileManager removeItemAtURL:url error:NULL];
    /* Apple's SQLite store may leave WAL/SHM journal files behind. */
    [fileManager removeItemAtPath:[[url path] stringByAppendingString:@"-wal"]
                            error:NULL];
    [fileManager removeItemAtPath:[[url path] stringByAppendingString:@"-shm"]
                            error:NULL];
}

- (void)tearDown
{
    [self removeStoreFilesAtURL:self.storeURL];
    self.storeURL = nil;
}

/* Builds a fresh coordinator + context stack on top of the SQLite store at
   `storeURL`, simulating an independent application run. */
- (NSManagedObjectContext *)contextWithModel:(NSManagedObjectModel *)model
                                     options:(NSDictionary *)options
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:options
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to add SQLite store: %@", error);
    if (self.coordinators == nil)
        self.coordinators = [NSMutableArray array];
    [self.coordinators addObject:psc];

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

- (NSArray *)fetchEntityNamed:(NSString *)entityName
                    inContext:(NSManagedObjectContext *)ctx
                    predicate:(NSPredicate *)predicate
              sortDescriptors:(NSArray *)sortDescriptors
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:entityName
                                 inManagedObjectContext:ctx]];
    [fetch setPredicate:predicate];
    [fetch setSortDescriptors:sortDescriptors];

    NSError *error = nil;
    NSArray *result = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    return result;
}

/* Inserts Alice (Engineering) and Bob (no department) and saves. */
- (void)populateStore
{
    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];

    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx];
    [alice setValue:@"Alice" forKey:@"name"];
    [alice setValue:[NSNumber numberWithInt:9] forKey:@"salary"];
    [alice setValue:[NSDate dateWithTimeIntervalSinceReferenceDate:1000]
             forKey:@"hireDate"];

    NSManagedObject *bob =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx];
    [bob setValue:@"Bob" forKey:@"name"];
    [bob setValue:[NSNumber numberWithInt:5] forKey:@"salary"];

    NSManagedObject *department =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:ctx];
    [department setValue:@"Engineering" forKey:@"name"];
    [alice setValue:department forKey:@"department"];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
}

- (void)testAddingStoreCreatesFileAndReportsType
{
    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSPersistentStore *store =
        [[[ctx persistentStoreCoordinator] persistentStores] firstObject];

    XCTAssertEqualObjects([store type], NSSQLiteStoreType);
    XCTAssertTrue([[NSFileManager defaultManager]
        fileExistsAtPath:[self.storeURL path]]);
}

- (void)testSaveAndFetchAcrossReopen
{
    [self populateStore];

    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSArray *employees =
        [self fetchEntityNamed:@"Employee"
                     inContext:ctx
                     predicate:nil
               sortDescriptors:[NSArray arrayWithObject:
                   [NSSortDescriptor sortDescriptorWithKey:@"name"
                                                 ascending:YES]]];
    XCTAssertEqual([employees count], (NSUInteger)2);

    NSManagedObject *alice = [employees objectAtIndex:0];
    XCTAssertEqualObjects([alice valueForKey:@"name"], @"Alice");
    XCTAssertEqual([[alice valueForKey:@"salary"] intValue], 9);
    XCTAssertEqualWithAccuracy(
        [[alice valueForKey:@"hireDate"] timeIntervalSinceReferenceDate],
        1000.0, 0.001);

    NSManagedObject *bob = [employees objectAtIndex:1];
    XCTAssertEqualObjects([bob valueForKey:@"name"], @"Bob");
    XCTAssertNil([bob valueForKey:@"hireDate"]);
    XCTAssertNil([bob valueForKey:@"department"]);
}

- (void)testRelationshipsAcrossReopen
{
    [self populateStore];

    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSArray *employees =
        [self fetchEntityNamed:@"Employee"
                     inContext:ctx
                     predicate:[NSPredicate predicateWithFormat:@"name == %@",
                                            @"Alice"]
               sortDescriptors:nil];
    XCTAssertEqual([employees count], (NSUInteger)1);

    NSManagedObject *alice = [employees objectAtIndex:0];
    NSManagedObject *department = [alice valueForKey:@"department"];
    XCTAssertNotNil(department);
    XCTAssertEqualObjects([department valueForKey:@"name"], @"Engineering");

    /* The inverse to-many relationship resolves through the store. */
    id members = [department valueForKey:@"employees"];
    XCTAssertEqual([members count], (NSUInteger)1);
    XCTAssertEqualObjects([[members anyObject] valueForKey:@"name"], @"Alice");
}

/* Nothing (NULL) sorts as less than any value: first ascending, last
   descending - Bob, hired on no date and in no department.  The SQL
   backends answer the same (CDSQLStore's nullsOrderingForAscending:). */
- (void)testNothingSortsFirstAscendingAndLastDescending
{
    [self populateStore];
    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];

    for (NSString *key in @[ @"hireDate", @"department.name" ]) {
        NSArray *ascending = [self fetchEntityNamed:@"Employee" inContext:ctx predicate:nil
                                    sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:key ascending:YES] ]];
        NSArray *descending = [self fetchEntityNamed:@"Employee" inContext:ctx predicate:nil
                                     sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:key ascending:NO] ]];

        XCTAssertEqualObjects([ascending valueForKey:@"name"], (@[ @"Bob", @"Alice" ]), @"%@", key);
        XCTAssertEqualObjects([descending valueForKey:@"name"], (@[ @"Alice", @"Bob" ]), @"%@", key);
    }
}

- (void)testUpdateAndDeletePersistAcrossReopen
{
    [self populateStore];

    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSArray *employees = [self fetchEntityNamed:@"Employee"
                                      inContext:ctx
                                      predicate:nil
                                sortDescriptors:[NSArray arrayWithObject:
                   [NSSortDescriptor sortDescriptorWithKey:@"name"
                                                 ascending:YES]]];
    NSManagedObject *alice = [employees objectAtIndex:0];
    NSManagedObject *bob = [employees objectAtIndex:1];

    [alice setValue:[NSNumber numberWithInt:12] forKey:@"salary"];
    [ctx deleteObject:bob];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:VersioningTestModelV1()
                                                  options:nil];
    NSArray *remaining = [self fetchEntityNamed:@"Employee"
                                      inContext:ctx2
                                      predicate:nil
                                sortDescriptors:nil];
    XCTAssertEqual([remaining count], (NSUInteger)1);
    XCTAssertEqualObjects([[remaining lastObject] valueForKey:@"name"],
                          @"Alice");
    XCTAssertEqual([[[remaining lastObject] valueForKey:@"salary"] intValue],
                   12);
}

- (void)testObjectIDURIUsesApplePrimaryKeyFormat
{
    [self populateStore];

    NSManagedObjectContext *ctx = [self contextWithModel:VersioningTestModelV1()
                                                 options:nil];
    NSArray *employees = [self fetchEntityNamed:@"Employee"
                                      inContext:ctx
                                      predicate:nil
                                sortDescriptors:nil];
    NSURL *uri = [[[employees lastObject] objectID] URIRepresentation];

    /* Apple's SQLite store object IDs look like
       x-coredata://<store-UUID>/<Entity>/p<primary key>. */
    XCTAssertEqualObjects([uri scheme], @"x-coredata");
    XCTAssertTrue([[uri lastPathComponent] hasPrefix:@"p"],
                  @"unexpected URI %@", uri);

    /* The URI round-trips back to the same object ID. */
    NSManagedObjectID *objectID = [[ctx persistentStoreCoordinator]
        managedObjectIDForURIRepresentation:uri];
    XCTAssertEqualObjects(objectID, [[employees lastObject] objectID]);
}

/* -- vacuum ------------------------------------------------------------ */

static NSManagedObjectModel *blobModel(void)
{
    NSAttributeDescription *data = [[NSAttributeDescription alloc] init];
    data.name = @"data";
    data.attributeType = NSBinaryDataAttributeType;
    data.optional = YES;
    NSEntityDescription *blob = [[NSEntityDescription alloc] init];
    blob.name = @"Blob";
    blob.properties = @[ data ];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ blob ];
    return model;
}

/* The store added and let go of again, so that its file is all written. */
- (void)closeStoreOf:(NSManagedObjectContext *)context
{
    NSPersistentStoreCoordinator *psc = [context persistentStoreCoordinator];
    [context reset];
    for (NSPersistentStore *store in [psc persistentStores])
        XCTAssertTrue([psc removePersistentStore:store error:NULL]);
}

- (unsigned long long)storeFileSize
{
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:[self.storeURL path] error:NULL] fileSize];
}

/* A big-endian 32-bit field of the SQLite file header. */
- (uint32_t)headerFieldAt:(NSUInteger)offset
{
    NSData *header = [[NSFileHandle fileHandleForReadingAtPath:[self.storeURL path]] readDataOfLength:100];
    const uint8_t *bytes = [header bytes];
    XCTAssertEqual([header length], (NSUInteger)100);
    return ([header length] < 100) ? 0 : ((uint32_t)bytes[offset] << 24 | (uint32_t)bytes[offset + 1] << 16 |
                                          (uint32_t)bytes[offset + 2] << 8 | (uint32_t)bytes[offset + 3]);
}

/* A store's file is made with incremental auto-vacuum, as Apple makes it:
   the header's largest root page (52) is set, and its incremental flag
   (64) is 1. */
- (void)testANewStoreFileVacuumsIncrementally
{
    NSManagedObjectContext *context = [self contextWithModel:blobModel() options:nil];
    [self closeStoreOf:context];

    XCTAssertNotEqual([self headerFieldAt:52], (uint32_t)0);
    XCTAssertEqual([self headerFieldAt:64], (uint32_t)1);
}

/* Deleted rows leave their space in the file, until the store is added
   with NSSQLiteManualVacuumOption. */
- (void)testTheManualVacuumOptionGivesBackTheSpaceOfDeletedRows
{
    XCTAssertEqualObjects(NSSQLiteManualVacuumOption, @"NSSQLiteManualVacuumOption");

    NSManagedObjectContext *context = [self contextWithModel:blobModel() options:nil];
    NSData *data = [NSMutableData dataWithLength:4000];
    for (int i = 0; i < 1000; i++)
        [[NSEntityDescription insertNewObjectForEntityForName:@"Blob" inManagedObjectContext:context] setValue:data forKey:@"data"];
    XCTAssertTrue([context save:NULL]);
    for (NSManagedObject *blob in [context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Blob"] error:NULL])
        [context deleteObject:blob];
    XCTAssertTrue([context save:NULL]);
    [self closeStoreOf:context];

    unsigned long long full = [self storeFileSize];
    XCTAssertGreaterThan(full, 4000000ULL);

    [self closeStoreOf:[self contextWithModel:blobModel() options:nil]];
    XCTAssertEqual([self storeFileSize], full, @"not given back unasked");

    NSManagedObjectContext *vacuumed = [self contextWithModel:blobModel() options:@{ NSSQLiteManualVacuumOption : @YES }];
    [self closeStoreOf:vacuumed];
    XCTAssertLessThan([self storeFileSize], 200000ULL);
}

- (int)storePragma:(const char *)pragma
{
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    int value = -1;

    sqlite3_open([[self.storeURL path] UTF8String], &database);
    sqlite3_prepare_v2(database, pragma, -1, &statement, NULL);
    if (sqlite3_step(statement) == SQLITE_ROW)
        value = sqlite3_column_int(statement, 0);
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return value;
}

/* After a save, now and then, the store gives back free pages, as Apple's
   does: it looks on the first save after it is opened and on every
   eleventh after that, and when less than 40% of the file is in use it
   frees all but as many pages as are. */
- (void)testSavesGiveBackFreePagesNowAndThen
{
    NSManagedObjectContext *context = [self contextWithModel:blobModel() options:nil];
    NSData *page = [NSMutableData dataWithLength:4000];
    for (int i = 0; i < 200; i++)
        [[NSEntityDescription insertNewObjectForEntityForName:@"Blob" inManagedObjectContext:context] setValue:page forKey:@"data"];
    XCTAssertTrue([context save:NULL]);   /* the first: looked, nothing free */
    for (NSManagedObject *blob in [context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Blob"] error:NULL])
        [context deleteObject:blob];
    XCTAssertTrue([context save:NULL]);   /* the second */
    int freed = [self storePragma:"PRAGMA freelist_count"];
    XCTAssertGreaterThan(freed, 190);

    for (int save = 3; save <= 11; save++) {
        [[NSEntityDescription insertNewObjectForEntityForName:@"Blob" inManagedObjectContext:context] setValue:[NSData dataWithBytes:"x" length:1] forKey:@"data"];
        XCTAssertTrue([context save:NULL]);
    }
    XCTAssertEqual([self storePragma:"PRAGMA freelist_count"], freed, @"not looked at again before the twelfth save");

    [[NSEntityDescription insertNewObjectForEntityForName:@"Blob" inManagedObjectContext:context] setValue:[NSData dataWithBytes:"x" length:1] forKey:@"data"];
    XCTAssertTrue([context save:NULL]);
    int pages = [self storePragma:"PRAGMA page_count"], free = [self storePragma:"PRAGMA freelist_count"];
    XCTAssertLessThan(free, freed / 4, @"the twelfth save gave pages back");
    XCTAssertEqual(free, pages - free, @"as many left free as are in use");
}

/* -- external binary data ----------------------------------------------- */

static NSManagedObjectModel *attachmentModel(BOOL withNote)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    name.name = @"name";
    name.attributeType = NSStringAttributeType;
    name.optional = YES;
    NSAttributeDescription *data = [[NSAttributeDescription alloc] init];
    data.name = @"data";
    data.attributeType = NSBinaryDataAttributeType;
    data.optional = YES;
    data.allowsExternalBinaryDataStorage = YES;
    NSMutableArray *properties = [NSMutableArray arrayWithObjects:name, data, nil];
    if (withNote) {
        NSAttributeDescription *note = [[NSAttributeDescription alloc] init];
        note.name = @"note";
        note.attributeType = NSStringAttributeType;
        note.optional = YES;
        [properties addObject:note];
    }
    NSEntityDescription *attachment = [[NSEntityDescription alloc] init];
    attachment.name = @"Attachment";
    attachment.properties = properties;
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ attachment ];
    return model;
}

static NSData *filledData(NSUInteger length, char fill)
{
    NSMutableData *data = [NSMutableData dataWithLength:length];
    memset([data mutableBytes], fill, length);
    return data;
}

- (NSString *)externalDataDirectory
{
    NSString *path = [self.storeURL path];
    return [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:
               [NSString stringWithFormat:@".%@_SUPPORT/_EXTERNAL_DATA", [[path lastPathComponent] stringByDeletingPathExtension]]];
}

- (NSArray *)externalFiles
{
    return [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self externalDataDirectory] error:NULL]
               sortedArrayUsingSelector:@selector(compare:)] ?: @[];
}

/* The data column of the attachment named name, as stored. */
- (NSData *)storedDataOfAttachmentNamed:(NSString *)name
{
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    NSData *stored = nil;

    sqlite3_open([[self.storeURL path] UTF8String], &database);
    sqlite3_prepare_v2(database, "SELECT ZDATA FROM ZATTACHMENT WHERE ZNAME = ?", -1, &statement, NULL);
    sqlite3_bind_text(statement, 1, [name UTF8String], -1, SQLITE_TRANSIENT);
    if (sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_type(statement, 0) != SQLITE_NULL)
        stored = [NSData dataWithBytes:sqlite3_column_blob(statement, 0) length:sqlite3_column_bytes(statement, 0)];
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return stored;
}

- (NSManagedObject *)attachmentNamed:(NSString *)name inContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Attachment"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"name == %@", name];
    return [[context executeFetchRequest:fetch error:NULL] firstObject];
}

- (NSManagedObject *)insertAttachmentNamed:(NSString *)name data:(NSData *)data inContext:(NSManagedObjectContext *)context
{
    NSManagedObject *attachment = [NSEntityDescription insertNewObjectForEntityForName:@"Attachment" inManagedObjectContext:context];
    [attachment setValue:name forKey:@"name"];
    [attachment setValue:data forKey:@"data"];
    return attachment;
}

/* Allowing external storage is a flag of the attribute: archived in its
   NSFlagsKey (4), as Apple's models carry it, and part of its version
   hash. */
- (void)testAllowingExternalStorageIsArchivedAndHashed
{
    NSAttributeDescription *data = [[NSAttributeDescription alloc] init];
    data.name = @"data";
    data.attributeType = NSBinaryDataAttributeType;
    XCTAssertFalse(data.allowsExternalBinaryDataStorage);
    NSData *plainHash = data.versionHash;
    data.allowsExternalBinaryDataStorage = YES;
    XCTAssertTrue(data.allowsExternalBinaryDataStorage);
    XCTAssertNotEqualObjects(data.versionHash, plainHash);

    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:data];
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:archive options:0 format:NULL error:NULL];
    NSNumber *flags = nil;
    for (id object in plist[@"$objects"])
        if ([object isKindOfClass:[NSDictionary class]] && object[@"NSAttributeType"] != nil)
            flags = object[@"NSFlagsKey"];
    XCTAssertEqual([flags integerValue], (NSInteger)4);

    NSAttributeDescription *back = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
    XCTAssertTrue(back.allowsExternalBinaryDataStorage);
}

/* A value up to 128 KiB stays in the row, after a 1; a larger one is a
   file of its own, which the row names after a 2 - as Apple's store
   writes them. */
- (void)testAValueOver128KiBIsAFileOfItsOwn
{
    NSManagedObjectContext *context = [self contextWithModel:attachmentModel(NO) options:nil];
    NSData *small = filledData(10, 'a'), *limit = filledData(131072, 'b'), *large = filledData(131073, 'c');
    [self insertAttachmentNamed:@"small" data:small inContext:context];
    [self insertAttachmentNamed:@"limit" data:limit inContext:context];
    [self insertAttachmentNamed:@"large" data:large inContext:context];
    [self insertAttachmentNamed:@"none" data:nil inContext:context];
    XCTAssertTrue([context save:NULL]);

    NSData *stored = [self storedDataOfAttachmentNamed:@"small"];
    XCTAssertEqual([stored length], (NSUInteger)11);
    XCTAssertEqual(((const uint8_t *)[stored bytes])[0], 1);
    XCTAssertEqual([[self storedDataOfAttachmentNamed:@"limit"] length], (NSUInteger)131073);
    XCTAssertNil([self storedDataOfAttachmentNamed:@"none"]);

    stored = [self storedDataOfAttachmentNamed:@"large"];
    XCTAssertEqual([stored length], (NSUInteger)38);
    XCTAssertEqual(((const uint8_t *)[stored bytes])[0], 2);
    XCTAssertEqual(((const uint8_t *)[stored bytes])[37], 0);
    NSString *name = [[NSString alloc] initWithBytes:(const uint8_t *)[stored bytes] + 1 length:36 encoding:NSASCIIStringEncoding];
    XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:name]);
    XCTAssertEqualObjects([self externalFiles], @[ name ]);

    NSManagedObjectContext *reopened = [self contextWithModel:attachmentModel(NO) options:nil];
    XCTAssertEqualObjects([[self attachmentNamed:@"small" inContext:reopened] valueForKey:@"data"], small);
    XCTAssertEqualObjects([[self attachmentNamed:@"limit" inContext:reopened] valueForKey:@"data"], limit);
    XCTAssertEqualObjects([[self attachmentNamed:@"large" inContext:reopened] valueForKey:@"data"], large);
    XCTAssertNil([[self attachmentNamed:@"none" inContext:reopened] valueForKey:@"data"]);

    NSFetchRequest *withData = [NSFetchRequest fetchRequestWithEntityName:@"Attachment"];
    withData.predicate = [NSPredicate predicateWithFormat:@"data != nil"];
    XCTAssertEqual([reopened countForFetchRequest:withData error:NULL], (NSUInteger)3);
}

/* A file goes when its value is written over or its row deleted, and
   stays while its value is not changed. */
- (void)testAFileGoesWithItsValue
{
    NSManagedObjectContext *context = [self contextWithModel:attachmentModel(NO) options:nil];
    NSManagedObject *attachment = [self insertAttachmentNamed:@"a" data:filledData(200000, 'a') inContext:context];
    XCTAssertTrue([context save:NULL]);
    NSArray *first = [self externalFiles];
    XCTAssertEqual([first count], (NSUInteger)1);

    [attachment setValue:@"renamed" forKey:@"name"];
    XCTAssertTrue([context save:NULL]);
    XCTAssertEqualObjects([self externalFiles], first, @"an unchanged value keeps its file");

    [attachment setValue:filledData(300000, 'b') forKey:@"data"];
    XCTAssertTrue([context save:NULL]);
    NSArray *second = [self externalFiles];
    XCTAssertEqual([second count], (NSUInteger)1);
    XCTAssertNotEqualObjects(second, first);

    [attachment setValue:filledData(10, 'c') forKey:@"data"];
    XCTAssertTrue([context save:NULL]);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)0);

    [attachment setValue:filledData(200000, 'd') forKey:@"data"];
    XCTAssertTrue([context save:NULL]);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)1);
    [context deleteObject:attachment];
    XCTAssertTrue([context save:NULL]);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)0);
}

/* A store migrated to a newer model keeps its external values, and its
   files go with it. */
- (void)testAMigratedStoreKeepsItsExternalValues
{
    NSManagedObjectContext *context = [self contextWithModel:attachmentModel(NO) options:nil];
    NSData *large = filledData(200000, 'm');
    [self insertAttachmentNamed:@"kept" data:large inContext:context];
    XCTAssertTrue([context save:NULL]);
    [self closeStoreOf:context];

    NSManagedObjectContext *migrated = [self contextWithModel:attachmentModel(YES)
                                                      options:@{ NSMigratePersistentStoresAutomaticallyOption : @YES,
                                                                 NSInferMappingModelAutomaticallyOption : @YES }];
    XCTAssertEqualObjects([[self attachmentNamed:@"kept" inContext:migrated] valueForKey:@"data"], large);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)1);

    NSString *name = [[self.storeURL lastPathComponent] stringByDeletingPathExtension];
    NSArray *beside = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self.storeURL path] stringByDeletingLastPathComponent] error:NULL];
    for (NSString *file in beside)
        if ([file rangeOfString:name].location != NSNotFound)
            XCTAssertEqual([file rangeOfString:@"~migrated"].location, (NSUInteger)NSNotFound, @"%@ left behind", file);
}

/* Batch requests write external values as a save does: a file for each
   row, and the files of rows deleted or written over go.  Apple's store
   raises on both (an unrecognized selector, -_bytesPtrForStore), so this
   is FreeCoreData's alone. */
- (void)testBatchRequestsWriteExternalValuesRowByRow
{
    if (NSClassFromString(@"NSSQLitePersistentStore") == nil)
        return;

    NSManagedObjectContext *context = [self contextWithModel:attachmentModel(NO) options:nil];
    NSBatchInsertRequest *insert = [[NSBatchInsertRequest alloc] initWithEntityName:@"Attachment"
        objects:@[ @{ @"name" : @"x", @"data" : filledData(200000, 'x') },
                   @{ @"name" : @"y", @"data" : filledData(200000, 'y') },
                   @{ @"name" : @"z", @"data" : filledData(5, 'z') } ]];
    XCTAssertNotNil([context executeRequest:insert error:NULL]);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)2);
    XCTAssertEqualObjects([[self attachmentNamed:@"y" inContext:context] valueForKey:@"data"], filledData(200000, 'y'));

    NSBatchUpdateRequest *update = [[NSBatchUpdateRequest alloc] initWithEntityName:@"Attachment"];
    update.propertiesToUpdate = @{ @"data" : filledData(150000, 'u') };
    XCTAssertNotNil([context executeRequest:update error:NULL]);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)3);

    NSManagedObjectContext *reopened = [self contextWithModel:attachmentModel(NO) options:nil];
    XCTAssertEqualObjects([[self attachmentNamed:@"z" inContext:reopened] valueForKey:@"data"], filledData(150000, 'u'));

    NSFetchRequest *matching = [NSFetchRequest fetchRequestWithEntityName:@"Attachment"];
    matching.predicate = [NSPredicate predicateWithFormat:@"data == %@", filledData(150000, 'u')];
    XCTAssertEqual([reopened countForFetchRequest:matching error:NULL], (NSUInteger)3);

    NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc] initWithFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Attachment"]];
    XCTAssertNotNil([reopened executeRequest:delete error:NULL]);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)0);
}

/* An external value's file is read only when its bytes are needed, as
   Apple's are: a value taken from an object, its file gone, raises only
   when its bytes are asked for; and an object whose external value is
   not changed is saved without its file. */
- (void)testAnExternalFileIsReadOnlyWhenItsBytesAre
{
    NSManagedObjectContext *context = [self contextWithModel:attachmentModel(NO) options:nil];
    [self insertAttachmentNamed:@"a" data:filledData(300000, 'a') inContext:context];
    [self insertAttachmentNamed:@"b" data:filledData(300000, 'b') inContext:context];
    XCTAssertTrue([context save:NULL]);

    NSManagedObjectContext *reader = [[NSManagedObjectContext alloc] init];
    reader.persistentStoreCoordinator = context.persistentStoreCoordinator;
    NSManagedObject *a = [self attachmentNamed:@"a" inContext:reader];
    NSData *value = [a valueForKey:@"data"];
    XCTAssertNotNil(value);
    for (NSString *file in [self externalFiles])
        [[NSFileManager defaultManager] removeItemAtPath:[[self externalDataDirectory] stringByAppendingPathComponent:file] error:NULL];

    XCTAssertThrows([value bytes], @"the file is read only now, and is gone");
    [a setValue:@"renamed" forKey:@"name"];
    NSError *error = nil;
    XCTAssertTrue([reader save:&error], @"saved without its file: %@", error);
}

/* Destroying a SQLite store leaves its database empty, in its file, and
   takes away the external values' files; nothing there is no error. */
- (void)testDestroyingAStoreEmptiesItAndTakesItsFilesAway
{
    NSManagedObjectContext *context = [self contextWithModel:attachmentModel(NO) options:nil];
    [self insertAttachmentNamed:@"a" data:filledData(300000, 'a') inContext:context];
    XCTAssertTrue([context save:NULL]);
    NSPersistentStoreCoordinator *coordinator = context.persistentStoreCoordinator;
    [self closeStoreOf:context];

    NSError *error = nil;
    XCTAssertTrue([coordinator destroyPersistentStoreAtURL:self.storeURL withType:NSSQLiteStoreType options:nil error:&error], @"%@", error);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[self.storeURL path]]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[[self externalDataDirectory] stringByDeletingLastPathComponent]]);

    NSManagedObjectContext *reopened = [self contextWithModel:attachmentModel(NO) options:nil];
    XCTAssertEqual([reopened countForFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Attachment"] error:NULL], (NSUInteger)0);

    NSURL *nothing = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]]];
    XCTAssertTrue([coordinator destroyPersistentStoreAtURL:nothing withType:NSSQLiteStoreType options:nil error:NULL]);
}

/* Replacing a SQLite store makes it a copy of another: its database, its
   UUID, and its external values' files; the source must be there. */
- (void)testReplacingAStoreCopiesAnother
{
    NSURL *destination = self.storeURL;
    self.storeURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                                [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"sqlite"]]];
    NSURL *source = self.storeURL;
    NSManagedObjectContext *context = [self contextWithModel:attachmentModel(NO) options:nil];
    [self insertAttachmentNamed:@"a" data:filledData(300000, 'a') inContext:context];
    [self insertAttachmentNamed:@"b" data:filledData(200000, 'b') inContext:context];
    XCTAssertTrue([context save:NULL]);
    NSString *uuid = [[context.persistentStoreCoordinator.persistentStores firstObject] identifier];
    NSPersistentStoreCoordinator *coordinator = context.persistentStoreCoordinator;
    [self closeStoreOf:context];

    self.storeURL = destination;
    NSManagedObjectContext *old = [self contextWithModel:attachmentModel(NO) options:nil];
    [self insertAttachmentNamed:@"old" data:filledData(300000, 'o') inContext:old];
    XCTAssertTrue([old save:NULL]);
    [self closeStoreOf:old];

    NSError *error = nil;
    XCTAssertTrue([coordinator replacePersistentStoreAtURL:destination destinationOptions:nil
                                withPersistentStoreFromURL:source sourceOptions:nil
                                                 storeType:NSSQLiteStoreType error:&error], @"%@", error);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)2);

    NSManagedObjectContext *copy = [self contextWithModel:attachmentModel(NO) options:nil];
    XCTAssertEqualObjects([[copy.persistentStoreCoordinator.persistentStores firstObject] identifier], uuid);
    XCTAssertEqual([copy countForFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Attachment"] error:NULL], (NSUInteger)2);
    XCTAssertEqualObjects([[self attachmentNamed:@"b" inContext:copy] valueForKey:@"data"], filledData(200000, 'b'));
    XCTAssertNil([self attachmentNamed:@"old" inContext:copy]);

    NSURL *nothing = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]]];
    error = nil;
    XCTAssertFalse([coordinator replacePersistentStoreAtURL:destination destinationOptions:nil
                                 withPersistentStoreFromURL:nothing sourceOptions:nil
                                                  storeType:NSSQLiteStoreType error:&error]);
    XCTAssertEqualObjects(error.domain, NSSQLiteErrorDomain);
    XCTAssertEqual(error.code, (NSInteger)14);

    [self removeStoreFilesAtURL:source];
    NSString *sourcePath = [source path];
    [[NSFileManager defaultManager] removeItemAtPath:[[sourcePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:
        [NSString stringWithFormat:@".%@_SUPPORT", [[sourcePath lastPathComponent] stringByDeletingPathExtension]]] error:NULL];
}

/* A store of another type kept in a file: destroying it removes the
   file, and replacing it copies the file. */
- (void)testAnXMLStoreIsDestroyedAndReplacedAsAFile
{
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *x = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"X.xml"]];
    NSURL *y = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"Y.xml"]];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:attachmentModel(NO)];
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:NSXMLStoreType configuration:nil URL:x options:nil error:NULL];
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
    context.persistentStoreCoordinator = coordinator;
    [self insertAttachmentNamed:@"x" data:filledData(10, 'x') inContext:context];
    XCTAssertTrue([context save:NULL]);
    XCTAssertTrue([coordinator removePersistentStore:store error:NULL]);

    NSError *error = nil;
    XCTAssertTrue([coordinator replacePersistentStoreAtURL:y destinationOptions:nil withPersistentStoreFromURL:x sourceOptions:nil
                                                 storeType:NSXMLStoreType error:&error], @"%@", error);
    XCTAssertEqualObjects([NSData dataWithContentsOfURL:y], [NSData dataWithContentsOfURL:x]);
    XCTAssertTrue([coordinator destroyPersistentStoreAtURL:y withType:NSXMLStoreType options:nil error:&error], @"%@", error);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[y path]]);
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* A store told where to keep its external values (CDExternalDataStoreOption,
   FreeCoreData's) keeps them there rather than in files beside it, and
   lets go of them there as it does of its files. */
- (void)testExternalValuesAreKeptWhereTheOptionsSay
{
    if (NSClassFromString(@"CDFileExternalDataStore") == nil)
        return;

    MemoryExternalDataStore *memory = [[MemoryExternalDataStore alloc] init];
    NSDictionary *options = @{ @"CDExternalDataStoreOption" : memory };
    NSManagedObjectContext *context = [self contextWithModel:attachmentModel(NO) options:options];
    NSManagedObject *attachment = [self insertAttachmentNamed:@"a" data:filledData(200000, 'a') inContext:context];
    [self insertAttachmentNamed:@"small" data:filledData(10, 's') inContext:context];
    XCTAssertTrue([context save:NULL]);
    XCTAssertEqual([memory.kept count], (NSUInteger)1);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)0, @"no files beside the store");
    NSData *stored = [self storedDataOfAttachmentNamed:@"a"];
    NSString *name = [[NSString alloc] initWithBytes:(const uint8_t *)[stored bytes] + 1 length:36 encoding:NSASCIIStringEncoding];
    XCTAssertEqualObjects([memory.kept allKeys], @[ name ]);

    NSManagedObjectContext *reopened = [self contextWithModel:attachmentModel(NO) options:options];
    XCTAssertEqualObjects([[self attachmentNamed:@"a" inContext:reopened] valueForKey:@"data"], filledData(200000, 'a'));

    [attachment setValue:filledData(300000, 'b') forKey:@"data"];
    XCTAssertTrue([context save:NULL]);
    XCTAssertEqual([memory.kept count], (NSUInteger)1);
    XCTAssertNil(memory.kept[name], @"the value written over is let go of");
    [context deleteObject:attachment];
    XCTAssertTrue([context save:NULL]);
    XCTAssertEqual([memory.kept count], (NSUInteger)0);

    [self closeStoreOf:context];
    [self closeStoreOf:reopened];
    XCTAssertTrue([context.persistentStoreCoordinator destroyPersistentStoreAtURL:self.storeURL withType:NSSQLiteStoreType options:options error:NULL]);
    XCTAssertEqual(memory.removedAll, 1);
}

/* -- migrating into and out of external storage -------------------------- */

static NSManagedObjectModel *itemModel(BOOL external)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    name.name = @"name";
    name.attributeType = NSStringAttributeType;
    name.optional = YES;
    NSAttributeDescription *data = [[NSAttributeDescription alloc] init];
    data.name = @"data";
    data.attributeType = NSBinaryDataAttributeType;
    data.optional = YES;
    data.allowsExternalBinaryDataStorage = external;
    NSEntityDescription *item = [[NSEntityDescription alloc] init];
    item.name = @"Item";
    item.properties = @[ name, data ];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ item ];
    return model;
}

/* Values whose first byte is what marks a value inline (1) or outside (2),
   one small, one large, and none. */
static NSDictionary *migratedValues(void)
{
    NSMutableData *one = [filledData(10, 'x') mutableCopy], *two = [filledData(40, 'y') mutableCopy];
    ((uint8_t *)[one mutableBytes])[0] = 1;
    ((uint8_t *)[two mutableBytes])[0] = 2;
    return @{ @"small" : filledData(10, 's'), @"starts1" : one, @"starts2" : two,
              @"large" : filledData(300000, 'L'), @"none" : [NSNull null] };
}

- (void)fillItemsWithModel:(NSManagedObjectModel *)model
{
    NSManagedObjectContext *context = [self contextWithModel:model options:nil];
    NSDictionary *values = migratedValues();
    for (NSString *name in values) {
        NSManagedObject *item = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:context];
        [item setValue:name forKey:@"name"];
        if (values[name] != [NSNull null])
            [item setValue:values[name] forKey:@"data"];
    }
    XCTAssertTrue([context save:NULL]);
    [self closeStoreOf:context];
}

/* The data column of each item, as stored, by name. */
- (NSDictionary *)storedItemData
{
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    NSMutableDictionary *stored = [NSMutableDictionary dictionary];

    sqlite3_open([[self.storeURL path] UTF8String], &database);
    sqlite3_prepare_v2(database, "SELECT ZNAME, ZDATA FROM ZITEM", -1, &statement, NULL);
    while (sqlite3_step(statement) == SQLITE_ROW)
        stored[[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)]] =
            (sqlite3_column_type(statement, 1) == SQLITE_NULL) ? [NSNull null]
                : [NSData dataWithBytes:sqlite3_column_blob(statement, 1) length:sqlite3_column_bytes(statement, 1)];
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return stored;
}

- (void)assertItemsReadBackWithModel:(NSManagedObjectModel *)model options:(NSDictionary *)options skippingNone:(BOOL)skippingNone
{
    NSManagedObjectContext *context = [self contextWithModel:model options:options];
    NSDictionary *values = migratedValues();
    NSArray *items = [context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Item"] error:NULL];
    XCTAssertEqual([items count], [values count]);
    for (NSManagedObject *item in items) {
        NSString *name = [item valueForKey:@"name"];
        if (values[name] == [NSNull null]) {
            if (!skippingNone)
                XCTAssertNil([item valueForKey:@"data"], @"none stays none");
        } else
            XCTAssertEqualObjects([item valueForKey:@"data"], values[name], @"%@", name);
    }
    [self closeStoreOf:context];
}

/* With a mapping model of one's own, values move into external storage -
   a byte in front of each, a large one into a file - and out of it again
   - as they were, and the file gone - as Apple's do. */
- (void)testAMappingModelMovesValuesIntoExternalStorageAndOut
{
    for (int into = 1; into >= 0; into--) {
        NSManagedObjectModel *source = itemModel(!into), *destination = itemModel(into);
        [self fillItemsWithModel:source];

        NSEntityMapping *entityMapping = [[NSEntityMapping alloc] init];
        entityMapping.name = @"ItemToItem";
        entityMapping.mappingType = NSCopyEntityMappingType;
        entityMapping.sourceEntityName = @"Item";
        entityMapping.destinationEntityName = @"Item";
        entityMapping.sourceEntityVersionHash = [source.entitiesByName[@"Item"] versionHash];
        entityMapping.destinationEntityVersionHash = [destination.entitiesByName[@"Item"] versionHash];
        entityMapping.sourceExpression = [NSExpression expressionWithFormat:
            @"FETCH(FUNCTION($manager, \"fetchRequestForSourceEntityNamed:predicateString:\" , \"Item\", \"TRUEPREDICATE\"), $manager.sourceContext, NO)"];
        NSMutableArray *propertyMappings = [NSMutableArray array];
        for (NSString *name in @[ @"name", @"data" ]) {
            NSPropertyMapping *propertyMapping = [[NSPropertyMapping alloc] init];
            propertyMapping.name = name;
            propertyMapping.valueExpression = [NSExpression expressionWithFormat:[NSString stringWithFormat:@"$source.%@", name]];
            [propertyMappings addObject:propertyMapping];
        }
        entityMapping.attributeMappings = propertyMappings;
        NSMappingModel *mapping = [[NSMappingModel alloc] init];
        mapping.entityMappings = @[ entityMapping ];

        NSURL *sourceURL = self.storeURL;
        NSURL *destinationURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                    [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"sqlite"]]];
        NSMigrationManager *manager = [[NSMigrationManager alloc] initWithSourceModel:source destinationModel:destination];
        NSError *error = nil;
        XCTAssertTrue([manager migrateStoreFromURL:sourceURL type:NSSQLiteStoreType options:nil withMappingModel:mapping
                                  toDestinationURL:destinationURL destinationType:NSSQLiteStoreType destinationOptions:nil error:&error], @"%@", error);
        manager = nil;

        self.storeURL = destinationURL;
        NSDictionary *stored = [self storedItemData];
        XCTAssertEqualObjects(stored[@"none"], [NSNull null]);
        if (into) {
            XCTAssertEqualObjects(stored[@"small"], ([@"\001ssssssssss" dataUsingEncoding:NSASCIIStringEncoding]));
            XCTAssertEqual([stored[@"starts2"] length], (NSUInteger)41);
            XCTAssertEqual(((const uint8_t *)[stored[@"large"] bytes])[0], 2);
            XCTAssertEqual([[self externalFiles] count], (NSUInteger)1);
        } else {
            XCTAssertEqualObjects(stored[@"starts1"], migratedValues()[@"starts1"]);
            XCTAssertEqualObjects(stored[@"large"], migratedValues()[@"large"]);
            XCTAssertEqual([[self externalFiles] count], (NSUInteger)0);
        }
        [self assertItemsReadBackWithModel:destination options:nil skippingNone:NO];

        [self removeStoreFilesAtURL:sourceURL];
        NSString *sourcePath = [sourceURL path];
        [[NSFileManager defaultManager] removeItemAtPath:[[sourcePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:
            [NSString stringWithFormat:@".%@_SUPPORT", [[sourcePath lastPathComponent] stringByDeletingPathExtension]]] error:NULL];
        [self removeStoreFilesAtURL:destinationURL];
        self.storeURL = sourceURL;
    }
}

/* Inferred, a migration into external storage keeps every value, each now
   with its byte in front (Apple's turns a nil value into empty data; this
   one leaves it nil). */
- (void)testAnInferredMigrationIntoExternalStorageKeepsTheValues
{
    [self fillItemsWithModel:itemModel(NO)];
    NSDictionary *automatic = @{ NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES };
    BOOL apples = (NSClassFromString(@"NSSQLitePersistentStore") == nil);
    [self assertItemsReadBackWithModel:itemModel(YES) options:automatic skippingNone:apples];

    NSDictionary *stored = [self storedItemData];
    for (NSString *name in @[ @"small", @"starts1", @"starts2", @"large" ]) {
        uint8_t marker = ((const uint8_t *)[stored[name] bytes])[0];
        XCTAssertTrue(marker == 1 || marker == 2, @"%@ is marked", name);
    }
}

/* Inferred, a migration out of external storage is refused, as Apple
   refuses it - even with no value kept outside - and the store is left as
   it was; a mapping model of one's own does it. */
- (void)testAnInferredMigrationOutOfExternalStorageIsRefused
{
    [self fillItemsWithModel:itemModel(YES)];
    NSDictionary *before = [self storedItemData];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:itemModel(NO)];
    NSDictionary *automatic = @{ NSMigratePersistentStoresAutomaticallyOption : @YES, NSInferMappingModelAutomaticallyOption : @YES };
    NSError *error = nil;
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:self.storeURL
                                                               options:automatic error:&error];
    XCTAssertNil(store);
    XCTAssertEqual(error.code, (NSInteger)NSMigrationMissingMappingModelError);
    XCTAssertEqual([error.userInfo[NSUnderlyingErrorKey] code], (NSInteger)NSInferredMappingModelError);
    XCTAssertEqualObjects([self storedItemData], before);
    XCTAssertEqual([[self externalFiles] count], (NSUInteger)1);
}

/* What an external data store that keeps its values remotely (S3, say)
   needs of a store, shown with one that behaves like it: a value fetched
   with its row is not downloaded until its bytes are used; one given to
   another row is copied by the server, not downloaded; and a request
   whose write fails fails, leaving nothing it wrote behind. */
- (void)testARemoteExternalDataStoreIsUsedAsItWouldWant
{
    if (NSClassFromString(@"CDFileExternalDataStore") == nil)
        return;

    RemoteLikeExternalDataStore *remote = [[RemoteLikeExternalDataStore alloc] init];
    NSDictionary *options = @{ @"CDExternalDataStoreOption" : remote };
    NSManagedObjectContext *context = [self contextWithModel:attachmentModel(NO) options:options];
    [self insertAttachmentNamed:@"a" data:filledData(200000, 'a') inContext:context];
    XCTAssertTrue([context save:NULL]);
    XCTAssertEqual(remote.writes, 1);

    NSManagedObjectContext *reader = [self contextWithModel:attachmentModel(NO) options:options];
    NSData *value = [[self attachmentNamed:@"a" inContext:reader] valueForKey:@"data"];
    XCTAssertEqual([value length], (NSUInteger)200000);
    XCTAssertEqual(remote.loads, 0, @"fetched, not downloaded");

    [self insertAttachmentNamed:@"b" data:value inContext:reader];
    XCTAssertTrue([reader save:NULL]);
    XCTAssertEqual(remote.copies, 1);
    XCTAssertEqual(remote.writes, 1, @"copied by the server");
    XCTAssertEqual(remote.loads, 0, @"and still not downloaded");
    XCTAssertEqual([remote.kept count], (NSUInteger)2);

    XCTAssertEqualObjects(value, filledData(200000, 'a'));
    XCTAssertGreaterThan(remote.loads, 0, @"downloaded when its bytes are used");

    remote.writesBeforeFailing = 1;
    [self insertAttachmentNamed:@"c" data:filledData(200000, 'c') inContext:reader];
    [self insertAttachmentNamed:@"d" data:filledData(200000, 'd') inContext:reader];
    NSError *error = nil;
    XCTAssertFalse([reader save:&error]);
    XCTAssertEqual(error.code, (NSInteger)NSURLErrorTimedOut);
    XCTAssertEqual([remote.kept count], (NSUInteger)2, @"what the failed save wrote is gone again");
    XCTAssertEqual([[[self storedItemNames] allObjects] count], (NSUInteger)2, @"and no row was written");
}

- (NSSet *)storedItemNames
{
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    NSMutableSet *names = [NSMutableSet set];

    sqlite3_open([[self.storeURL path] UTF8String], &database);
    sqlite3_prepare_v2(database, "SELECT ZNAME FROM ZATTACHMENT", -1, &statement, NULL);
    while (sqlite3_step(statement) == SQLITE_ROW)
        [names addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)]];
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return names;
}

/* -- permanent IDs ------------------------------------------------------ */

/* Thing, a subentity of it, Special, and Other, a root of its own. */
static NSManagedObjectModel *keyedModel(void)
{
    NSAttributeDescription *number = [[NSAttributeDescription alloc] init];
    number.name = @"number";
    number.attributeType = NSInteger64AttributeType;
    number.optional = YES;
    NSEntityDescription *thing = [[NSEntityDescription alloc] init];
    thing.name = @"Thing";
    thing.properties = @[ number ];
    NSEntityDescription *special = [[NSEntityDescription alloc] init];
    special.name = @"Special";
    thing.subentities = @[ special ];
    NSAttributeDescription *count = [[NSAttributeDescription alloc] init];
    count.name = @"count";
    count.attributeType = NSInteger64AttributeType;
    count.optional = YES;
    NSEntityDescription *other = [[NSEntityDescription alloc] init];
    other.name = @"Other";
    other.properties = @[ count ];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ thing, special, other ];
    return model;
}

static long long primaryKeyOf(NSManagedObject *object)
{
    return [[[[[object objectID] URIRepresentation] lastPathComponent] substringFromIndex:1] longLongValue];
}

/* The keys of objects, by their root entity's name. */
static NSDictionary *keysByRoot(NSArray *objects)
{
    NSMutableDictionary *keys = [NSMutableDictionary dictionary];
    for (NSManagedObject *object in objects) {
        NSEntityDescription *root = [object entity];
        while ([root superentity] != nil)
            root = [root superentity];
        if (keys[root.name] == nil)
            keys[root.name] = [NSMutableSet set];
        [keys[root.name] addObject:@(primaryKeyOf(object))];
    }
    return keys;
}

static NSSet *keysFrom(long long first, long long last)
{
    NSMutableSet *keys = [NSMutableSet set];
    for (long long key = first; key <= last; key++)
        [keys addObject:@(key)];
    return keys;
}

- (NSArray *)insertKeyed:(int)count inContext:(NSManagedObjectContext *)context
{
    NSMutableArray *objects = [NSMutableArray array];
    for (int i = 0; i < count; i++)
        [objects addObject:[NSEntityDescription insertNewObjectForEntityForName:(i % 3 == 0) ? @"Thing" : (i % 3 == 1) ? @"Special" : @"Other"
                                                         inManagedObjectContext:context]];
    return objects;
}

- (long long)maxKeyOf:(NSString *)entityName
{
    return [self storePragma:[[NSString stringWithFormat:@"SELECT Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = '%@'", entityName] UTF8String]];
}

/* New objects' keys come a block to each root entity, as Apple's do: an
   entity and its subentities draw from one key space, the keys are
   distinct and leave no gap, Z_MAX is the highest handed out, and a
   later save, from another context, reuses none. */
- (void)testPermanentIDsComeInABlockForEachRootEntity
{
    NSManagedObjectContext *context = [self contextWithModel:keyedModel() options:nil];
    NSArray *objects = [self insertKeyed:150 inContext:context];
    NSError *error = nil;
    XCTAssertTrue([context obtainPermanentIDsForObjects:objects error:&error], @"%@", error);
    for (NSManagedObject *object in objects)
        XCTAssertFalse([[object objectID] isTemporaryID]);
    NSDictionary *keys = keysByRoot(objects);
    XCTAssertEqualObjects(keys[@"Thing"], keysFrom(1, 100), @"Thing and Special share a key space");
    XCTAssertEqualObjects(keys[@"Other"], keysFrom(1, 50));
    XCTAssertTrue([context save:&error], @"%@", error);
    XCTAssertEqual([self maxKeyOf:@"Thing"], 100);
    XCTAssertEqual([self maxKeyOf:@"Other"], 50);

    NSManagedObjectContext *later = [[NSManagedObjectContext alloc] init];
    later.persistentStoreCoordinator = context.persistentStoreCoordinator;
    NSArray *more = [self insertKeyed:30 inContext:later];
    XCTAssertTrue([later save:&error], @"%@", error);
    keys = keysByRoot(more);
    XCTAssertEqualObjects(keys[@"Thing"], keysFrom(101, 120));
    XCTAssertEqualObjects(keys[@"Other"], keysFrom(51, 60));
    XCTAssertEqual([self maxKeyOf:@"Thing"], 120);
}

/* A store that cannot give every object its key gives none: no object
   takes a permanent ID, and every Z_MAX is as it was.  Made to fail by
   taking away Other's key row behind the store's back; FreeCoreData's
   alone, as nothing says what Apple's does then. */
- (void)testPermanentIDsAreAllOrNothing
{
    if (NSClassFromString(@"NSSQLitePersistentStore") == nil)
        return;

    NSManagedObjectContext *context = [self contextWithModel:keyedModel() options:nil];
    XCTAssertTrue([context save:NULL]);
    NSArray *objects = [self insertKeyed:30 inContext:context];
    XCTAssertTrue([context obtainPermanentIDsForObjects:@[ objects[0] ] error:NULL]);
    long long thingMax = [self maxKeyOf:@"Thing"];
    XCTAssertEqual(thingMax, 1);

    sqlite3 *database = NULL;
    sqlite3_open([[self.storeURL path] UTF8String], &database);
    XCTAssertEqual(sqlite3_exec(database, "DELETE FROM Z_PRIMARYKEY WHERE Z_NAME = 'Other'", NULL, NULL, NULL), SQLITE_OK);
    sqlite3_close(database);

    NSError *error = nil;
    XCTAssertFalse([context obtainPermanentIDsForObjects:objects error:&error]);
    XCTAssertNotNil(error);
    for (NSManagedObject *object in [objects subarrayWithRange:NSMakeRange(1, [objects count] - 1)])
        XCTAssertTrue([[object objectID] isTemporaryID], @"%@ took no permanent ID", [[object entity] name]);
    XCTAssertEqual([self maxKeyOf:@"Thing"], thingMax, @"Thing's keys were not taken");
}

- (void)testMetadataContainsTypeUUIDAndVersionHashes
{
    [self populateStore];

    NSError *error = nil;
    NSDictionary *metadata = [NSPersistentStoreCoordinator
        metadataForPersistentStoreOfType:NSSQLiteStoreType
                                     URL:self.storeURL
                                   error:&error];
    XCTAssertNotNil(metadata, @"failed to read metadata: %@", error);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreTypeKey],
                          NSSQLiteStoreType);
    XCTAssertNotNil([metadata objectForKey:NSStoreUUIDKey]);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreModelVersionHashesKey],
                          [VersioningTestModelV1() entityVersionHashesByName]);
}

/* The forms with options, Apple's since macOS 10.11: the same metadata,
   and what is set is read back. */
- (void)testMetadataWithOptions
{
    [self populateStore];

    NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                                        forKey:NSPersistentHistoryTrackingKey];
    NSError *error = nil;
    NSDictionary *metadata = [NSPersistentStoreCoordinator
        metadataForPersistentStoreOfType:NSSQLiteStoreType
                                     URL:self.storeURL
                                 options:options
                                   error:&error];
    XCTAssertNotNil(metadata, @"failed to read metadata: %@", error);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreModelVersionHashesKey],
                          [VersioningTestModelV1() entityVersionHashesByName]);

    NSMutableDictionary *changed = [metadata mutableCopy];
    [changed setObject:@"kept" forKey:@"CDTestKey"];
    XCTAssertTrue([NSPersistentStoreCoordinator setMetadata:changed
                                   forPersistentStoreOfType:NSSQLiteStoreType
                                                        URL:self.storeURL
                                                    options:options
                                                      error:&error], @"%@", error);
    NSDictionary *again = [NSPersistentStoreCoordinator
        metadataForPersistentStoreOfType:NSSQLiteStoreType
                                     URL:self.storeURL
                                 options:options
                                   error:&error];
    XCTAssertEqualObjects([again objectForKey:@"CDTestKey"], @"kept");
}

- (void)testReopeningWithIncompatibleModelFails
{
    [self populateStore];

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV2()];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNil(store);
    XCTAssertNotNil(error);
    XCTAssertEqual([error code],
                   (NSInteger)NSPersistentStoreIncompatibleVersionHashError);
}

- (void)testIgnoreVersioningOptionSkipsCompatibilityCheck
{
    [self populateStore];

    NSError *error = nil;
    NSDictionary *options = [NSDictionary
        dictionaryWithObject:[NSNumber numberWithBool:YES]
                      forKey:NSIgnorePersistentStoreVersioningOption];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV2()];
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:options
                                                         error:&error];
    XCTAssertNotNil(store, @"open with ignore option failed: %@", error);
}

- (void)testMigrationManagerMigratesStore
{
    [self populateStore];

    NSManagedObjectModel *sourceModel = VersioningTestModelV1();
    NSManagedObjectModel *destinationModel = VersioningTestModelV2();

    NSError *error = nil;
    NSMappingModel *mapping = [NSMappingModel
        inferredMappingModelForSourceModel:sourceModel
                          destinationModel:destinationModel
                                     error:&error];
    XCTAssertNotNil(mapping);

    NSURL *destinationURL = [NSURL fileURLWithPath:
        [[self.storeURL path] stringByAppendingString:@"-v2"]];

    NSMigrationManager *manager = [[NSMigrationManager alloc]
        initWithSourceModel:sourceModel destinationModel:destinationModel];
    BOOL ok = [manager migrateStoreFromURL:self.storeURL
                                      type:NSSQLiteStoreType
                                   options:nil
                          withMappingModel:mapping
                          toDestinationURL:destinationURL
                           destinationType:NSSQLiteStoreType
                        destinationOptions:nil
                                     error:&error];
    XCTAssertTrue(ok, @"migration failed: %@", error);

    /* Release the migration manager (and with it its open source and
       destination store connections) before the destination store files
       are touched again; deleting a SQLite database that still has an
       open connection is an API violation ("vnode unlinked while in
       use" on macOS). */
    manager = nil;

    /* The migrated store opens with the destination model and preserves
       the data and relationships. */
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:destinationModel];
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:destinationURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to open migrated store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[destinationModel entitiesByName] objectForKey:@"Employee"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"name == %@",
                                     @"Alice"]];
    NSArray *employees = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertEqual([employees count], (NSUInteger)1);

    NSManagedObject *alice = [employees objectAtIndex:0];
    XCTAssertEqual([[alice valueForKey:@"salary"] intValue], 9);
    XCTAssertNil([alice valueForKey:@"title"]);

    NSManagedObject *department = [alice valueForKey:@"department"];
    XCTAssertNotNil(department);
    XCTAssertEqualObjects([department valueForKey:@"name"], @"Engineering");

    /* Close the verification store's connection before deleting its
       files. */
    XCTAssertTrue([psc removePersistentStore:store error:&error],
                  @"failed to remove store: %@", error);

    [self removeStoreFilesAtURL:destinationURL];
}

/* Item <<->> Tag (many-to-many) plus Manager, a subentity of Person. */
static NSManagedObjectModel *manyToManyAndInheritanceModel(void)
{
    NSAttributeDescription *itemName = [[NSAttributeDescription alloc] init];
    [itemName setName:@"name"];
    [itemName setAttributeType:NSStringAttributeType];
    [itemName setOptional:YES];

    NSAttributeDescription *tagLabel = [[NSAttributeDescription alloc] init];
    [tagLabel setName:@"label"];
    [tagLabel setAttributeType:NSStringAttributeType];
    [tagLabel setOptional:YES];

    NSRelationshipDescription *tags = [[NSRelationshipDescription alloc] init];
    [tags setName:@"tags"];
    [tags setMinCount:0];
    [tags setMaxCount:0];
    [tags setOptional:YES];

    NSRelationshipDescription *items = [[NSRelationshipDescription alloc] init];
    [items setName:@"items"];
    [items setMinCount:0];
    [items setMaxCount:0];
    [items setOptional:YES];

    NSEntityDescription *item = [[NSEntityDescription alloc] init];
    [item setName:@"Item"];
    [item setManagedObjectClassName:@"NSManagedObject"];

    NSEntityDescription *tag = [[NSEntityDescription alloc] init];
    [tag setName:@"Tag"];
    [tag setManagedObjectClassName:@"NSManagedObject"];

    [tags setDestinationEntity:tag];
    [tags setInverseRelationship:items];
    [items setDestinationEntity:item];
    [items setInverseRelationship:tags];

    [item setProperties:[NSArray arrayWithObjects:itemName, tags, nil]];
    [tag setProperties:[NSArray arrayWithObjects:tagLabel, items, nil]];

    NSAttributeDescription *personName = [[NSAttributeDescription alloc] init];
    [personName setName:@"name"];
    [personName setAttributeType:NSStringAttributeType];
    [personName setOptional:YES];

    NSAttributeDescription *reports = [[NSAttributeDescription alloc] init];
    [reports setName:@"reports"];
    [reports setAttributeType:NSInteger32AttributeType];
    [reports setOptional:YES];

    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    [person setName:@"Person"];
    [person setManagedObjectClassName:@"NSManagedObject"];
    [person setProperties:[NSArray arrayWithObject:personName]];

    NSEntityDescription *manager = [[NSEntityDescription alloc] init];
    [manager setName:@"Manager"];
    [manager setManagedObjectClassName:@"NSManagedObject"];
    [manager setProperties:[NSArray arrayWithObject:reports]];

    [person setSubentities:[NSArray arrayWithObject:manager]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:
        [NSArray arrayWithObjects:item, tag, person, manager, nil]];
    return model;
}

/* A relationship can be its own inverse: "friends" whose inverse is
   "friends", which makes it symmetric - putting B in A's set puts A in
   B's.  Core Data models this, and its store has to, because the obvious
   naming gives both sides of the join table one name. */
static NSManagedObjectModel *reflexiveModel(BOOL ordered)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];
    [name setOptional:YES];

    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    [person setName:@"Person"];
    [person setManagedObjectClassName:@"NSManagedObject"];

    NSRelationshipDescription *friends = [[NSRelationshipDescription alloc] init];
    [friends setName:@"friends"];
    [friends setDestinationEntity:person];
    [friends setMinCount:0];
    [friends setMaxCount:0];
    [friends setOptional:YES];
    [friends setOrdered:ordered];
    [friends setInverseRelationship:friends];

    [person setProperties:[NSArray arrayWithObjects:name, friends, nil]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:person]];
    return model;
}

- (NSManagedObject *)insertPersonNamed:(NSString *)name
                             inContext:(NSManagedObjectContext *)ctx
{
    NSManagedObject *person =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:ctx];
    [person setValue:name forKey:@"name"];
    return person;
}

- (NSManagedObject *)personNamed:(NSString *)name
                       inContext:(NSManagedObjectContext *)ctx
{
    NSArray *found = [self fetchEntityNamed:@"Person"
                                  inContext:ctx
                                  predicate:[NSPredicate predicateWithFormat:
                                                @"name == %@", name]
                            sortDescriptors:nil];

    XCTAssertEqual([found count], (NSUInteger)1, @"no one named %@", name);
    return [found lastObject];
}

- (void)testReflexiveManyToManyPersistsAcrossReopen
{
    NSManagedObjectContext *ctx =
        [self contextWithModel:reflexiveModel(NO) options:nil];

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" inContext:ctx];
    NSManagedObject *grace = [self insertPersonNamed:@"Grace" inContext:ctx];
    [self insertPersonNamed:@"Bob" inContext:ctx];

    /* Written from one side only; the other side is the same relationship. */
    [[ada mutableSetValueForKey:@"friends"] addObject:grace];
    XCTAssertEqualObjects([[grace valueForKey:@"friends"] anyObject], ada,
        @"a reflexive relationship is symmetric before it is even saved");

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    ctx = [self contextWithModel:reflexiveModel(NO) options:nil];

    XCTAssertEqualObjects([[[self personNamed:@"Ada" inContext:ctx]
        valueForKey:@"friends"] valueForKey:@"name"],
        [NSSet setWithObject:@"Grace"]);
    XCTAssertEqualObjects([[[self personNamed:@"Grace" inContext:ctx]
        valueForKey:@"friends"] valueForKey:@"name"],
        [NSSet setWithObject:@"Ada"],
        @"the store answers the relationship from both sides");
    XCTAssertEqual([[[self personNamed:@"Bob" inContext:ctx]
        valueForKey:@"friends"] count], (NSUInteger)0);

    /* And a fetch reaches across it. */
    NSArray *friendsOfAda = [self fetchEntityNamed:@"Person"
                                         inContext:ctx
                                         predicate:[NSPredicate predicateWithFormat:
                                                       @"ANY friends.name == %@", @"Ada"]
                                   sortDescriptors:nil];
    XCTAssertEqual([friendsOfAda count], (NSUInteger)1);
    XCTAssertEqualObjects([[friendsOfAda lastObject] valueForKey:@"name"], @"Grace");

    /* Removing it from one side removes it from both. */
    [[[self personNamed:@"Ada" inContext:ctx] mutableSetValueForKey:@"friends"]
        removeObject:[self personNamed:@"Grace" inContext:ctx]];
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    ctx = [self contextWithModel:reflexiveModel(NO) options:nil];
    XCTAssertEqual([[[self personNamed:@"Ada" inContext:ctx]
        valueForKey:@"friends"] count], (NSUInteger)0);
    XCTAssertEqual([[[self personNamed:@"Grace" inContext:ctx]
        valueForKey:@"friends"] count], (NSUInteger)0);
}

- (void)testOrderedReflexiveManyToManyKeepsEachSidesOrder
{
    NSManagedObjectContext *ctx =
        [self contextWithModel:reflexiveModel(YES) options:nil];

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" inContext:ctx];
    NSManagedObject *grace = [self insertPersonNamed:@"Grace" inContext:ctx];
    NSManagedObject *bob = [self insertPersonNamed:@"Bob" inContext:ctx];

    /* Ada's order is Grace then Bob; each of them has an order of their
       own, in the same column pair, which is why both sides need a
       column and not just one. */
    [[ada mutableOrderedSetValueForKey:@"friends"] addObject:grace];
    [[ada mutableOrderedSetValueForKey:@"friends"] addObject:bob];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    ctx = [self contextWithModel:reflexiveModel(YES) options:nil];

    /* Through -array, not valueForKey: on the ordered set itself: Apple
       answers that with an ordered set and GNUstep with a plain one, and
       the order is the whole point here. */
    XCTAssertEqualObjects([[[[self personNamed:@"Ada" inContext:ctx]
        valueForKey:@"friends"] array] valueForKey:@"name"],
        ([NSArray arrayWithObjects:@"Grace", @"Bob", nil]));
    XCTAssertEqualObjects([[[[self personNamed:@"Grace" inContext:ctx]
        valueForKey:@"friends"] array] valueForKey:@"name"],
        [NSArray arrayWithObject:@"Ada"]);
    XCTAssertEqualObjects([[[[self personNamed:@"Bob" inContext:ctx]
        valueForKey:@"friends"] array] valueForKey:@"name"],
        [NSArray arrayWithObject:@"Ada"]);
}

- (void)testManyToManyAndSubentitiesPersistAcrossReopen
{
    NSManagedObjectContext *ctx =
        [self contextWithModel:manyToManyAndInheritanceModel() options:nil];

    NSManagedObject *pen =
        [NSEntityDescription insertNewObjectForEntityForName:@"Item"
                                      inManagedObjectContext:ctx];
    [pen setValue:@"Pen" forKey:@"name"];
    NSManagedObject *book =
        [NSEntityDescription insertNewObjectForEntityForName:@"Item"
                                      inManagedObjectContext:ctx];
    [book setValue:@"Book" forKey:@"name"];

    NSManagedObject *red =
        [NSEntityDescription insertNewObjectForEntityForName:@"Tag"
                                      inManagedObjectContext:ctx];
    [red setValue:@"red" forKey:@"label"];
    NSManagedObject *blue =
        [NSEntityDescription insertNewObjectForEntityForName:@"Tag"
                                      inManagedObjectContext:ctx];
    [blue setValue:@"blue" forKey:@"label"];

    [[pen mutableSetValueForKey:@"tags"] addObject:red];
    [[pen mutableSetValueForKey:@"tags"] addObject:blue];
    [[book mutableSetValueForKey:@"tags"] addObject:red];

    NSManagedObject *boss =
        [NSEntityDescription insertNewObjectForEntityForName:@"Manager"
                                      inManagedObjectContext:ctx];
    [boss setValue:@"Boss" forKey:@"name"];
    [boss setValue:[NSNumber numberWithInt:7] forKey:@"reports"];
    NSManagedObject *worker =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:ctx];
    [worker setValue:@"Worker" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* Reopen and verify the many-to-many relationship from both sides. */
    ctx = [self contextWithModel:manyToManyAndInheritanceModel() options:nil];

    NSArray *pens = [self fetchEntityNamed:@"Item"
                                 inContext:ctx
                                 predicate:[NSPredicate predicateWithFormat:
                                               @"name == %@", @"Pen"]
                           sortDescriptors:nil];
    XCTAssertEqual([pens count], (NSUInteger)1);
    pen = [pens objectAtIndex:0];
    XCTAssertEqual([[pen valueForKey:@"tags"] count], (NSUInteger)2);

    NSArray *reds = [self fetchEntityNamed:@"Tag"
                                 inContext:ctx
                                 predicate:[NSPredicate predicateWithFormat:
                                               @"label == %@", @"red"]
                           sortDescriptors:nil];
    XCTAssertEqual([reds count], (NSUInteger)1);
    red = [reds objectAtIndex:0];
    XCTAssertEqual([[red valueForKey:@"items"] count], (NSUInteger)2);

    /* A fetch of the parent entity includes subentity instances... */
    NSArray *people = [self fetchEntityNamed:@"Person"
                                   inContext:ctx
                                   predicate:nil
                             sortDescriptors:nil];
    XCTAssertEqual([people count], (NSUInteger)2);

    NSUInteger managerCount = 0;
    for (NSManagedObject *person in people)
        if ([[[person entity] name] isEqualToString:@"Manager"]) {
            managerCount++;
            XCTAssertEqual([[person valueForKey:@"reports"] intValue], 7);
        }
    XCTAssertEqual(managerCount, (NSUInteger)1);

    /* ...while a fetch of the subentity finds only its own instances. */
    NSArray *managers = [self fetchEntityNamed:@"Manager"
                                     inContext:ctx
                                     predicate:nil
                               sortDescriptors:nil];
    XCTAssertEqual([managers count], (NSUInteger)1);

    /* Removing from one side of a many-to-many persists. */
    [[pen mutableSetValueForKey:@"tags"] removeObject:
        [[pen valueForKey:@"tags"] anyObject]];
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    ctx = [self contextWithModel:manyToManyAndInheritanceModel() options:nil];
    pens = [self fetchEntityNamed:@"Item"
                        inContext:ctx
                        predicate:[NSPredicate predicateWithFormat:
                                      @"name == %@", @"Pen"]
                  sortDescriptors:nil];
    XCTAssertEqual([[[pens objectAtIndex:0] valueForKey:@"tags"] count],
                   (NSUInteger)1);
}

/* -- optimistic locking --------------------------------------------------

   Every row carries a version.  A context that saves an object is writing
   over the version it read; when another save has moved the row on since,
   the save is a merge conflict rather than a silent overwrite, settled by
   the context's merge policy.  Two contexts on one coordinator are the
   case that matters most in one process: both read through the same store,
   so nothing but the version each context read tells their saves apart. */

/* A coordinator with the SQLite store at storeURL, shared by the contexts
   made from it. */
- (NSPersistentStoreCoordinator *)sharedCoordinator
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV1()];
    NSError *error = nil;
    XCTAssertNotNil([psc addPersistentStoreWithType:NSSQLiteStoreType
                                      configuration:nil
                                                URL:self.storeURL
                                            options:nil
                                              error:&error],
                    @"failed to add SQLite store: %@", error);
    return psc;
}

- (NSManagedObjectContext *)contextOn:(NSPersistentStoreCoordinator *)psc
{
    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

/* Alice, read in ctx: her values are realized, so the context holds the
   version it read. */
- (NSManagedObject *)aliceIn:(NSManagedObjectContext *)ctx
{
    __block NSManagedObject *alice = nil;
    [ctx performBlockAndWait:^{
        alice = [[self fetchEntityNamed:@"Employee"
                              inContext:ctx
                              predicate:[NSPredicate predicateWithFormat:@"name == %@", @"Alice"]
                        sortDescriptors:nil] lastObject];
        (void)[alice valueForKey:@"salary"];
    }];
    return alice;
}

- (BOOL)setSalary:(int)salary of:(NSManagedObject *)employee error:(NSError **)error
{
    __block BOOL ok = NO;
    __block NSError *saveError = nil;
    NSManagedObjectContext *ctx = [employee managedObjectContext];
    [ctx performBlockAndWait:^{
        [employee setValue:[NSNumber numberWithInt:salary] forKey:@"salary"];
        NSError *localError = nil;
        ok = [ctx save:&localError];
        saveError = localError;
    }];
    if (error != NULL) {
        *error = saveError;
    }
    return ok;
}

- (int)storedSalaryOfAlice
{
    NSManagedObjectContext *fresh = [self contextOn:[self sharedCoordinator]];
    __block int salary = 0;
    NSManagedObject *alice = [self aliceIn:fresh];
    [fresh performBlockAndWait:^{
        salary = [[alice valueForKey:@"salary"] intValue];
    }];
    return salary;
}

- (void)testSecondContextOnOneCoordinatorGetsAMergeConflict
{
    [self populateStore];
    NSPersistentStoreCoordinator *psc = [self sharedCoordinator];
    /* An object does not keep its context alive: the test does. */
    NSManagedObjectContext *firstContext = [self contextOn:psc];
    NSManagedObjectContext *secondContext = [self contextOn:psc];
    NSManagedObject *first = [self aliceIn:firstContext];
    NSManagedObject *second = [self aliceIn:secondContext];

    NSError *error = nil;
    XCTAssertTrue([self setSalary:10 of:first error:&error], @"first save failed: %@", error);
    error = nil;
    XCTAssertFalse([self setSalary:11 of:second error:&error],
                   @"the second save wrote over a version it never read");
    XCTAssertEqualObjects([error domain], NSCocoaErrorDomain);
    XCTAssertEqual([error code], (NSInteger)NSManagedObjectMergeError);

    NSArray *conflicts = [[error userInfo] objectForKey:NSPersistentStoreSaveConflictsErrorKey];
    XCTAssertEqual([conflicts count], (NSUInteger)1);
    NSMergeConflict *conflict = [conflicts firstObject];
    XCTAssertEqual([conflict sourceObject], second);
    XCTAssertEqual([conflict oldVersionNumber], (NSUInteger)1);
    XCTAssertEqual([conflict newVersionNumber], (NSUInteger)2);

    XCTAssertEqual([self storedSalaryOfAlice], 10, @"the row keeps the first save");
}

- (void)testSavingTwiceFromOneContextIsNotAConflict
{
    [self populateStore];
    NSManagedObjectContext *ctx = [self contextOn:[self sharedCoordinator]];
    NSManagedObject *alice = [self aliceIn:ctx];
    NSError *error = nil;
    XCTAssertTrue([self setSalary:10 of:alice error:&error], @"%@", error);
    XCTAssertTrue([self setSalary:11 of:alice error:&error], @"%@", error);
    XCTAssertTrue([self setSalary:12 of:alice error:&error], @"%@", error);
    XCTAssertEqual([self storedSalaryOfAlice], 12);
}

- (void)testObjectTrumpPolicyWritesOverTheOtherSave
{
    [self populateStore];
    NSPersistentStoreCoordinator *psc = [self sharedCoordinator];
    NSManagedObjectContext *firstContext = [self contextOn:psc];
    NSManagedObject *first = [self aliceIn:firstContext];
    NSManagedObjectContext *secondContext = [self contextOn:psc];
    [secondContext setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
    NSManagedObject *second = [self aliceIn:secondContext];

    NSError *error = nil;
    XCTAssertTrue([self setSalary:10 of:first error:&error], @"%@", error);
    XCTAssertTrue([self setSalary:11 of:second error:&error],
                  @"object trump should settle the conflict: %@", error);
    XCTAssertEqual([self storedSalaryOfAlice], 11);
    /* Settled means the context now holds the row's version. */
    XCTAssertTrue([self setSalary:13 of:second error:&error], @"%@", error);
    XCTAssertEqual([self storedSalaryOfAlice], 13);
}

- (void)testStoreTrumpPolicyKeepsTheOtherSave
{
    [self populateStore];
    NSPersistentStoreCoordinator *psc = [self sharedCoordinator];
    NSManagedObjectContext *firstContext = [self contextOn:psc];
    NSManagedObject *first = [self aliceIn:firstContext];
    NSManagedObjectContext *secondContext = [self contextOn:psc];
    [secondContext setMergePolicy:NSMergeByPropertyStoreTrumpMergePolicy];
    NSManagedObject *second = [self aliceIn:secondContext];

    NSError *error = nil;
    XCTAssertTrue([self setSalary:10 of:first error:&error], @"%@", error);
    XCTAssertTrue([self setSalary:11 of:second error:&error],
                  @"store trump should settle the conflict: %@", error);
    XCTAssertEqual([self storedSalaryOfAlice], 10);
}

- (void)testDeletingARowChangedMeanwhileConflicts
{
    [self populateStore];
    NSPersistentStoreCoordinator *psc = [self sharedCoordinator];
    NSManagedObjectContext *firstContext = [self contextOn:psc];
    NSManagedObject *first = [self aliceIn:firstContext];
    NSManagedObjectContext *secondContext = [self contextOn:psc];
    NSManagedObject *second = [self aliceIn:secondContext];

    NSError *error = nil;
    XCTAssertTrue([self setSalary:10 of:first error:&error], @"%@", error);
    __block BOOL deleted = NO;
    __block NSError *deleteError = nil;
    [secondContext performBlockAndWait:^{
        [secondContext deleteObject:second];
        NSError *localError = nil;
        deleted = [secondContext save:&localError];
        deleteError = localError;
    }];
    XCTAssertFalse(deleted, @"the delete was of a version it never read");
    XCTAssertEqual([deleteError code], (NSInteger)NSManagedObjectMergeError);
    XCTAssertEqual([self storedSalaryOfAlice], 10, @"the row is still there");
}

- (void)testUpdatingARowDeletedMeanwhileFails
{
    [self populateStore];
    NSPersistentStoreCoordinator *psc = [self sharedCoordinator];
    NSManagedObjectContext *firstContext = [self contextOn:psc];
    NSManagedObject *first = [self aliceIn:firstContext];
    NSManagedObjectContext *secondContext = [self contextOn:psc];
    NSManagedObject *second = [self aliceIn:secondContext];

    __block BOOL deleted = NO;
    [firstContext performBlockAndWait:^{
        [firstContext deleteObject:first];
        deleted = [firstContext save:NULL];
    }];
    XCTAssertTrue(deleted);
    NSError *error = nil;
    XCTAssertFalse([self setSalary:11 of:second error:&error],
                   @"the row it would update is gone");
    XCTAssertNotNil(error);
    NSManagedObjectContext *fresh = [self contextOn:[self sharedCoordinator]];
    XCTAssertNil([self aliceIn:fresh], @"the update did not bring the row back");
    (void)secondContext;
}

- (void)testContextsOnSeparateCoordinatorsConflict
{
    [self populateStore];
    NSManagedObjectContext *firstContext = [self contextOn:[self sharedCoordinator]];
    NSManagedObjectContext *secondContext = [self contextOn:[self sharedCoordinator]];
    NSManagedObject *first = [self aliceIn:firstContext];
    NSManagedObject *second = [self aliceIn:secondContext];

    NSError *error = nil;
    XCTAssertTrue([self setSalary:10 of:first error:&error], @"%@", error);
    XCTAssertFalse([self setSalary:11 of:second error:&error]);
    XCTAssertEqual([error code], (NSInteger)NSManagedObjectMergeError);
    XCTAssertEqual([self storedSalaryOfAlice], 10);
}

/* Both contexts read, then both save at once: whatever the interleaving,
   one save wins and the other is refused. */
- (void)testConcurrentSavesOnOneCoordinatorLetOneWin
{
    [self populateStore];
    NSPersistentStoreCoordinator *psc = [self sharedCoordinator];
    for (int round = 0; round < 20; round++) {
        NSArray *contexts = @[ [self contextOn:psc], [self contextOn:psc] ];
        NSManagedObject *employees[2] = {
            [self aliceIn:contexts[0]], [self aliceIn:contexts[1]]
        };
        __block int wins = 0;
        dispatch_group_t group = dispatch_group_create();
        for (int i = 0; i < 2; i++) {
            NSManagedObject *employee = employees[i];
            int salary = 100 * round + i;
            dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if ([self setSalary:salary of:employee error:NULL]) {
                    @synchronized (self) {
                        wins += 1;
                    }
                }
            });
        }
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
#if !OS_OBJECT_USE_OBJC
        dispatch_release(group);
#endif
        XCTAssertEqual(wins, 1, @"round %d", round);
        (void)contexts;
    }
}

/* ------------------------------------------------------------------ */
#pragma mark - Predicates through to-many relationships
/* ------------------------------------------------------------------ */

/* Owners have vehicles, vehicles have fill-ups and tags (many to many).
   A fill-up is a Reading, which keeps the odometer; an Inspection is
   another, in the same table, with no vehicle.

     A - V1: f1 (1), F10 (10), fnil (no odometer); tagged x
       - V2: none
     B
     C - V3: f7 (7); tagged x
         V4: f3 (3)                 (no owner)
         V5: "V5" (no odometer)     (no owner)
         (no name): (no note) (4)   (no owner)
         orphan (2), with no vehicle

   Each expected answer below is what Apple's store answers (the macOS
   run), and, where the comment does not say otherwise, what evaluating
   the predicate in memory answers too. */
static NSAttributeDescription *fleetAttribute(NSString *name, NSAttributeType type)
{
    NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
    [attribute setName:name];
    [attribute setAttributeType:type];
    [attribute setOptional:YES];
    return attribute;
}

static NSRelationshipDescription *fleetRelationship(NSString *name, BOOL toMany)
{
    NSRelationshipDescription *relationship = [[NSRelationshipDescription alloc] init];
    [relationship setName:name];
    [relationship setMinCount:0];
    [relationship setMaxCount:toMany ? 0 : 1];
    [relationship setOptional:YES];
    [relationship setDeleteRule:NSNullifyDeleteRule];
    return relationship;
}

static NSEntityDescription *fleetEntity(NSString *name)
{
    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:name];
    [entity setManagedObjectClassName:@"NSManagedObject"];
    return entity;
}

static void fleetInverses(NSRelationshipDescription *one, NSEntityDescription *oneDestination,
                          NSRelationshipDescription *other, NSEntityDescription *otherDestination)
{
    [one setDestinationEntity:oneDestination];
    [other setDestinationEntity:otherDestination];
    [one setInverseRelationship:other];
    [other setInverseRelationship:one];
}

static NSManagedObjectModel *fleetModel(void)
{
    NSEntityDescription *owner = fleetEntity(@"Owner");
    NSEntityDescription *vehicle = fleetEntity(@"Vehicle");
    NSEntityDescription *reading = fleetEntity(@"Reading");
    NSEntityDescription *fillUp = fleetEntity(@"FillUp");
    NSEntityDescription *inspection = fleetEntity(@"Inspection");
    NSEntityDescription *tag = fleetEntity(@"Tag");

    NSRelationshipDescription *vehicles = fleetRelationship(@"vehicles", YES);
    NSRelationshipDescription *vehicleOwner = fleetRelationship(@"owner", NO);
    NSRelationshipDescription *fillUps = fleetRelationship(@"fillUps", YES);
    NSRelationshipDescription *fillUpVehicle = fleetRelationship(@"vehicle", NO);
    NSRelationshipDescription *tags = fleetRelationship(@"tags", YES);
    NSRelationshipDescription *tagged = fleetRelationship(@"vehicles", YES);

    fleetInverses(vehicles, vehicle, vehicleOwner, owner);
    fleetInverses(fillUps, fillUp, fillUpVehicle, vehicle);
    fleetInverses(tags, tag, tagged, vehicle);

    [owner setProperties:@[ fleetAttribute(@"name", NSStringAttributeType), vehicles ]];
    [vehicle setProperties:@[ fleetAttribute(@"name", NSStringAttributeType), vehicleOwner, fillUps, tags ]];
    [reading setProperties:@[ fleetAttribute(@"odometer", NSInteger64AttributeType) ]];
    [fillUp setProperties:@[ fleetAttribute(@"note", NSStringAttributeType), fillUpVehicle ]];
    [tag setProperties:@[ fleetAttribute(@"label", NSStringAttributeType), tagged ]];
    [reading setSubentities:@[ fillUp, inspection ]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ owner, vehicle, reading, fillUp, inspection, tag ]];
    return model;
}

static NSManagedObject *fleetObject(NSManagedObjectContext *ctx, NSString *entityName, NSDictionary *values)
{
    NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:entityName
                                                            inManagedObjectContext:ctx];
    [object setValuesForKeysWithDictionary:values];
    return object;
}

/* Saves the fleet, and answers the coordinator it is in. */
- (NSPersistentStoreCoordinator *)fleetCoordinator
{
    NSManagedObjectContext *ctx = [self contextWithModel:fleetModel() options:nil];

    NSManagedObject *a = fleetObject(ctx, @"Owner", @{ @"name" : @"A" });
    fleetObject(ctx, @"Owner", @{ @"name" : @"B" });
    NSManagedObject *c = fleetObject(ctx, @"Owner", @{ @"name" : @"C" });
    NSManagedObject *v1 = fleetObject(ctx, @"Vehicle", @{ @"name" : @"V1", @"owner" : a });
    fleetObject(ctx, @"Vehicle", @{ @"name" : @"V2", @"owner" : a });
    NSManagedObject *v3 = fleetObject(ctx, @"Vehicle", @{ @"name" : @"V3", @"owner" : c });
    NSManagedObject *v4 = fleetObject(ctx, @"Vehicle", @{ @"name" : @"V4" });
    NSManagedObject *v5 = fleetObject(ctx, @"Vehicle", @{ @"name" : @"V5" });
    NSManagedObject *unnamed = fleetObject(ctx, @"Vehicle", @{});
    fleetObject(ctx, @"FillUp", @{ @"note" : @"f1", @"odometer" : @1, @"vehicle" : v1 });
    fleetObject(ctx, @"FillUp", @{ @"note" : @"F10", @"odometer" : @10, @"vehicle" : v1 });
    fleetObject(ctx, @"FillUp", @{ @"note" : @"fnil", @"vehicle" : v1 });
    fleetObject(ctx, @"FillUp", @{ @"note" : @"f7", @"odometer" : @7, @"vehicle" : v3 });
    fleetObject(ctx, @"FillUp", @{ @"note" : @"f3", @"odometer" : @3, @"vehicle" : v4 });
    fleetObject(ctx, @"FillUp", @{ @"note" : @"V5", @"vehicle" : v5 });
    fleetObject(ctx, @"FillUp", @{ @"odometer" : @4, @"vehicle" : unnamed });
    fleetObject(ctx, @"FillUp", @{ @"note" : @"orphan", @"odometer" : @2 });
    fleetObject(ctx, @"Inspection", @{ @"odometer" : @100 });
    NSManagedObject *x = fleetObject(ctx, @"Tag", @{ @"label" : @"x" });
    fleetObject(ctx, @"Tag", @{ @"label" : @"y" });
    [[v1 mutableSetValueForKey:@"tags"] addObject:x];
    [[v3 mutableSetValueForKey:@"tags"] addObject:x];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
    return [ctx persistentStoreCoordinator];
}

static NSString *fleetNameKey(NSString *entityName)
{
    return [entityName isEqualToString:@"FillUp"] ? @"note" : @"name";
}

/* The names of objects, sorted, with "-" for a missing one. */
static NSArray *fleetNames(NSArray *objects, NSString *key)
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSManagedObject *object in objects) {
        id name = [object valueForKey:key];
        [names addObject:name != nil ? name : @"-"];
    }
    return [names sortedArrayUsingSelector:@selector(compare:)];
}

- (NSManagedObjectContext *)contextOnFleet:(NSPersistentStoreCoordinator *)psc
{
    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

/* Fetches with predicate, in a context of its own, and checks the answer;
   when inMemoryToo, also that evaluating the predicate over every object
   answers the same. */
- (void)assertFleet:(NSPersistentStoreCoordinator *)psc
             entity:(NSString *)entityName
          predicate:(NSPredicate *)predicate
            answers:(NSArray *)expected
         inMemoryToo:(BOOL)inMemoryToo
{
    NSManagedObjectContext *ctx = [self contextOnFleet:psc];
    NSString *key = fleetNameKey(entityName);
    NSArray *fetched = [self fetchEntityNamed:entityName inContext:ctx predicate:predicate sortDescriptors:nil];

    XCTAssertEqualObjects(fleetNames(fetched, key), expected, @"%@: %@", entityName, predicate);

    if (inMemoryToo) {
        NSManagedObjectContext *other = [self contextOnFleet:psc];
        NSArray *every = [self fetchEntityNamed:entityName inContext:other predicate:nil sortDescriptors:nil];
        XCTAssertEqualObjects(fleetNames([every filteredArrayUsingPredicate:predicate], key), expected,
                              @"in memory, %@: %@", entityName, predicate);
    }
}

- (void)assertFleet:(NSPersistentStoreCoordinator *)psc
             entity:(NSString *)entityName
             format:(NSString *)format
            answers:(NSArray *)expected
{
    [self assertFleet:psc entity:entityName predicate:[NSPredicate predicateWithFormat:format] answers:expected inMemoryToo:YES];
}

/* count:(SUBQUERY(collection, $variable, predicate)) <operator> number, as
   ODataKit writes an OData any() or all(). */
static NSPredicate *countedSubquery(NSString *collection, NSString *variable, NSString *format,
                                    NSPredicateOperatorType operator, NSInteger number)
{
    NSExpression *subquery = [NSExpression expressionForSubquery:[NSExpression expressionForKeyPath:collection]
                                           usingIteratorVariable:variable
                                                       predicate:[NSPredicate predicateWithFormat:format]];
    NSExpression *count = [NSExpression expressionForFunction:@"count:" arguments:@[ subquery ]];
    return [NSComparisonPredicate predicateWithLeftExpression:count
                                              rightExpression:[NSExpression expressionForConstantValue:@(number)]
                                                     modifier:NSDirectPredicateModifier
                                                         type:operator
                                                      options:0];
}

- (void)testAnyThroughAToMany
{
    NSPersistentStoreCoordinator *psc = [self fleetCoordinator];

    [self assertFleet:psc entity:@"Vehicle" format:@"ANY fillUps.odometer < 5" answers:@[ @"-", @"V1", @"V4" ]];
    /* A fill-up with no odometer is not unequal to 10 - in SQL, and in
       memory, where ANY passes over the nils. */
    [self assertFleet:psc entity:@"Vehicle" format:@"ANY fillUps.odometer != 10" answers:@[ @"-", @"V1", @"V3", @"V4" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"ANY fillUps.note ==[c] 'f10'" answers:@[ @"V1" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"ANY fillUps.note BEGINSWITH 'f'" answers:@[ @"V1", @"V3", @"V4" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"ANY fillUps.odometer IN {1, 7}" answers:@[ @"V1", @"V3" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"ANY fillUps.odometer > 3 OR fillUps.@count == 0"
              answers:@[ @"-", @"V1", @"V2", @"V3" ]];
    /* Many to many, through a join table. */
    [self assertFleet:psc entity:@"Vehicle" format:@"ANY tags.label == 'x'" answers:@[ @"V1", @"V3" ]];
    /* Through a to-one first: none where it is not set.  (Apple's
       Foundation answers so in memory too; gnustep-base raises, a nil
       not being a collection, which is why these are not checked in
       memory here.) */
    [self assertFleet:psc entity:@"Vehicle"
            predicate:[NSPredicate predicateWithFormat:@"ANY owner.vehicles.name == 'V2'"]
              answers:@[ @"V1", @"V2" ]
          inMemoryToo:NO];
    [self assertFleet:psc entity:@"FillUp"
            predicate:[NSPredicate predicateWithFormat:@"ANY vehicle.fillUps.odometer > 5"]
              answers:@[ @"F10", @"f1", @"f7", @"fnil" ]
          inMemoryToo:NO];
}

/* Key paths through to-ones are lookups, NULL where a to-one on the way
   is not set - as the key path's value is nil then. */
- (void)testKeyPathsThroughToOnes
{
    NSPersistentStoreCoordinator *psc = [self fleetCoordinator];

    [self assertFleet:psc entity:@"FillUp" format:@"vehicle.owner.name == 'A'" answers:@[ @"F10", @"f1", @"fnil" ]];
    [self assertFleet:psc entity:@"FillUp" format:@"vehicle.name == nil" answers:@[ @"-", @"orphan" ]];
    [self assertFleet:psc entity:@"FillUp" format:@"vehicle.owner == nil" answers:@[ @"-", @"V5", @"f3", @"orphan" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"owner.name BEGINSWITH 'C'" answers:@[ @"V3" ]];
}

/* A to-one back to the same entity: a family tree, whose table has the
   foreign key (ZPARENT) a lookup by parent reads in the same table. */
static NSManagedObjectModel *familyModel(void)
{
    NSEntityDescription *person = fleetEntity(@"Person");
    NSRelationshipDescription *parent = fleetRelationship(@"parent", NO);
    NSRelationshipDescription *children = fleetRelationship(@"children", YES);

    fleetInverses(parent, person, children, person);
    [person setProperties:@[ fleetAttribute(@"name", NSStringAttributeType), parent, children ]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ person ]];
    return model;
}

/* A and Z have no parent; B and C are A's children, D is B's, E is D's. */
- (NSPersistentStoreCoordinator *)familyCoordinator
{
    NSManagedObjectContext *ctx = [self contextWithModel:familyModel() options:nil];

    NSManagedObject *a = fleetObject(ctx, @"Person", @{ @"name" : @"A" });
    NSManagedObject *b = fleetObject(ctx, @"Person", @{ @"name" : @"B", @"parent" : a });
    fleetObject(ctx, @"Person", @{ @"name" : @"C", @"parent" : a });
    NSManagedObject *d = fleetObject(ctx, @"Person", @{ @"name" : @"D", @"parent" : b });
    fleetObject(ctx, @"Person", @{ @"name" : @"E", @"parent" : d });
    fleetObject(ctx, @"Person", @{ @"name" : @"Z" });

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
    return [ctx persistentStoreCoordinator];
}

- (void)testKeyPathsThroughAToOneToTheSameEntity
{
    NSPersistentStoreCoordinator *psc = [self familyCoordinator];

    [self assertFleet:psc entity:@"Person" format:@"parent.name == 'A'" answers:@[ @"B", @"C" ]];
    [self assertFleet:psc entity:@"Person" format:@"parent.parent.name == 'A'" answers:@[ @"D" ]];
    [self assertFleet:psc entity:@"Person" format:@"parent.parent.parent.name == 'A'" answers:@[ @"E" ]];
    [self assertFleet:psc entity:@"Person" format:@"parent.name BEGINSWITH 'D'" answers:@[ @"E" ]];
    [self assertFleet:psc entity:@"Person" format:@"parent.name == nil" answers:@[ @"A", @"Z" ]];
    [self assertFleet:psc entity:@"Person" format:@"parent.parent == nil" answers:@[ @"A", @"B", @"C", @"Z" ]];
    [self assertFleet:psc entity:@"Person" format:@"parent.name == name" answers:@[]];
}

- (void)testToManysOfTheSameEntity
{
    NSPersistentStoreCoordinator *psc = [self familyCoordinator];

    [self assertFleet:psc entity:@"Person" format:@"ANY children.name == 'D'" answers:@[ @"B" ]];
    [self assertFleet:psc entity:@"Person" format:@"children.@count == 2" answers:@[ @"A" ]];
    [self assertFleet:psc entity:@"Person" format:@"children.@count == 0" answers:@[ @"C", @"E", @"Z" ]];
    /* Correlated with the fetched row's own parent, a lookup in the same
       table: NULL for A, so none of A's children count (memory, where
       nil is unequal to every name, counts them). */
    [self assertFleet:psc entity:@"Person"
            predicate:[NSPredicate predicateWithFormat:@"SUBQUERY(children, $c, $c.name != parent.name).@count > 0"]
              answers:@[ @"B", @"D" ]
          inMemoryToo:NO];
    /* Siblings, through the parent: none for those who have none. */
    [self assertFleet:psc entity:@"Person"
            predicate:[NSPredicate predicateWithFormat:@"ANY parent.children.name == 'C'"]
              answers:@[ @"B", @"C" ]
          inMemoryToo:NO];
}

/* Unequal through a to-one that is not set: Apple's store finds no row
   there - the lookup is NULL, unequal to nothing - where memory finds
   one (nil is unequal to 'A').  The store's answer is Apple's. */
- (void)testUnequalThroughAToOneThatIsNotSet
{
    NSPersistentStoreCoordinator *psc = [self familyCoordinator];

    [self assertFleet:psc entity:@"Person"
            predicate:[NSPredicate predicateWithFormat:@"parent.name != 'A'"]
              answers:@[ @"D", @"E" ]
          inMemoryToo:NO];
    [self assertFleet:psc entity:@"Person"
            predicate:[NSPredicate predicateWithFormat:@"NOT (parent.name == 'A')"]
              answers:@[ @"D", @"E" ]
          inMemoryToo:NO];
}

- (void)testCountsOfAToMany
{
    NSPersistentStoreCoordinator *psc = [self fleetCoordinator];

    [self assertFleet:psc entity:@"Vehicle" format:@"fillUps.@count > 1" answers:@[ @"V1" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"fillUps.@count == 0" answers:@[ @"V2" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"fillUps.@count != 1" answers:@[ @"V1", @"V2" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"tags.@count == 0" answers:@[ @"-", @"V2", @"V4", @"V5" ]];
    [self assertFleet:psc entity:@"Owner" format:@"vehicles.@count == 0" answers:@[ @"B" ]];
    /* Through a to-one: an orphan's count is nil, unequal to 1 (Apple's
       store counts it as 0, which differs from memory only for a
       comparison 0 satisfies). */
    [self assertFleet:psc entity:@"FillUp" format:@"vehicle.fillUps.@count == 1" answers:@[ @"-", @"V5", @"f3", @"f7" ]];
    [self assertFleet:psc entity:@"FillUp" format:@"vehicle.fillUps.@count != 1"
              answers:@[ @"F10", @"f1", @"fnil", @"orphan" ]];
}

- (void)testSubqueriesOfAToMany
{
    NSPersistentStoreCoordinator *psc = [self fleetCoordinator];

    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(fillUps, $x, $x.odometer < 5).@count > 0"
              answers:@[ @"-", @"V1", @"V4" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(fillUps, $x, $x.odometer < 5).@count == 0"
              answers:@[ @"V2", @"V3", @"V5" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(fillUps, $x, $x.odometer < 5).@count == 1"
              answers:@[ @"-", @"V1", @"V4" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(fillUps, $x, $x.odometer == nil).@count > 0"
              answers:@[ @"V1", @"V5" ]];
    [self assertFleet:psc entity:@"Vehicle"
               format:@"SUBQUERY(fillUps, $x, $x.odometer > 0 AND $x.note CONTAINS[c] 'f').@count >= 2"
              answers:@[ @"V1" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(fillUps, $x, $x.odometer > 3 OR $x.note == 'V5').@count > 0"
              answers:@[ @"-", @"V1", @"V3", @"V5" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(fillUps, $x, $x.odometer > 3).@count > 0 AND name BEGINSWITH 'V'"
              answers:@[ @"V1", @"V3" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(tags, $t, $t.label == 'x').@count > 0"
              answers:@[ @"V1", @"V3" ]];
    /* Through to-ones inside, and the fetched object's own key paths. */
    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(fillUps, $x, $x.vehicle.owner.name == 'A').@count > 0"
              answers:@[ @"V1" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(fillUps, $x, $x.note != name).@count > 0"
              answers:@[ @"V1", @"V3", @"V4" ]];
    [self assertFleet:psc entity:@"Vehicle" format:@"SUBQUERY(fillUps, $x, name == nil).@count > 0" answers:@[ @"-" ]];
    /* Nested. */
    [self assertFleet:psc entity:@"Owner" format:@"SUBQUERY(vehicles, $v, ANY $v.fillUps.odometer > 5).@count > 0"
              answers:@[ @"A", @"C" ]];
    [self assertFleet:psc entity:@"Owner"
               format:@"SUBQUERY(vehicles, $v, SUBQUERY($v.fillUps, $f, $f.odometer > 5).@count > 0).@count > 0"
              answers:@[ @"A", @"C" ]];
}

/* The fill-ups with an earlier one in the same vehicle: a subquery of the
   fetched entity's own table, correlated with the fetched row through a
   to-one. */
- (void)testACorrelatedSubqueryThroughAToOne
{
    NSPersistentStoreCoordinator *psc = [self fleetCoordinator];

    [self assertFleet:psc entity:@"FillUp" format:@"SUBQUERY(vehicle.fillUps, $x, $x.odometer < odometer).@count > 0"
              answers:@[ @"F10" ]];
    [self assertFleet:psc entity:@"FillUp" format:@"SUBQUERY(vehicle.fillUps, $x, $x.odometer < odometer).@count != 1"
              answers:@[ @"-", @"V5", @"f1", @"f3", @"f7", @"fnil", @"orphan" ]];
}

/* Where Apple's store answers as SQL does rather than as memory does, the
   store answers as Apple's: NULL equals and is unequal to nothing. */
- (void)testNullsInASubqueryCompareAsInApplesStore
{
    NSPersistentStoreCoordinator *psc = [self fleetCoordinator];

    /* In memory V5's fill-up, with no odometer, is unequal to 10. */
    [self assertFleet:psc entity:@"Vehicle"
            predicate:[NSPredicate predicateWithFormat:@"SUBQUERY(fillUps, $x, $x.odometer != 10).@count > 0"]
              answers:@[ @"-", @"V1", @"V3", @"V4" ]
          inMemoryToo:NO];
    /* In memory the unnamed vehicle's fill-up, with no note, matches it. */
    [self assertFleet:psc entity:@"Vehicle"
            predicate:[NSPredicate predicateWithFormat:@"SUBQUERY(fillUps, $x, $x.note == name).@count > 0"]
              answers:@[ @"V5" ]
          inMemoryToo:NO];
}

/* What ODataKit makes of Vehicles?$filter=FillUps/any(f: f/Odometer lt 5),
   of FillUps/any(), and, through a to-one, of
   FillUps?$filter=Vehicle/FillUps/all(e: not (e/Odometer lt $it/Odometer)):
   a counted SUBQUERY, guarded by the to-one being there. */
- (void)testODataKitsLambdas
{
    NSPersistentStoreCoordinator *psc = [self fleetCoordinator];

    [self assertFleet:psc entity:@"Vehicle"
            predicate:countedSubquery(@"fillUps", @"v0", @"$v0.odometer != nil AND $v0.odometer < 5", NSGreaterThanPredicateOperatorType, 0)
              answers:@[ @"-", @"V1", @"V4" ]
          inMemoryToo:YES];

    NSExpression *count = [NSExpression expressionForFunction:@"count:"
                                                    arguments:@[ [NSExpression expressionForKeyPath:@"fillUps"] ]];
    [self assertFleet:psc entity:@"Vehicle"
            predicate:[NSComparisonPredicate predicateWithLeftExpression:count
                                                         rightExpression:[NSExpression expressionForConstantValue:@0]
                                                                modifier:NSDirectPredicateModifier
                                                                    type:NSGreaterThanPredicateOperatorType
                                                                 options:0]
              answers:@[ @"-", @"V1", @"V3", @"V4", @"V5" ]
          inMemoryToo:YES];

    NSPredicate *none = countedSubquery(@"vehicle.fillUps", @"v0", @"$v0.odometer != nil AND $v0.odometer < odometer",
                                        NSEqualToPredicateOperatorType, 0);
    [self assertFleet:psc entity:@"FillUp"
            predicate:[NSCompoundPredicate andPredicateWithSubpredicates:@[ [NSPredicate predicateWithFormat:@"vehicle != nil"], none ]]
              answers:@[ @"-", @"V5", @"f1", @"f3", @"f7", @"fnil" ]
          inMemoryToo:YES];
}

/* A predicate through a to-many is the store's to answer, not memory's:
   asked for object IDs, a fresh context is left with nothing registered
   (evaluating in memory would have registered every row and faulted in
   each one's fill-ups), and a page of the answer is that page. */
- (void)testPredicatesThroughToManysAreEvaluatedInSQL
{
    NSPersistentStoreCoordinator *psc = [self fleetCoordinator];
    NSArray *cases = @[
        @[ @"Vehicle", [NSPredicate predicateWithFormat:@"ANY fillUps.odometer < 5"] ],
        @[ @"Vehicle", [NSPredicate predicateWithFormat:@"fillUps.@count != 1"] ],
        @[ @"Vehicle", [NSPredicate predicateWithFormat:@"ANY tags.label == 'x' OR SUBQUERY(fillUps, $x, $x.odometer > 3).@count > 0"] ],
        @[ @"Vehicle", countedSubquery(@"fillUps", @"v0", @"$v0.odometer != nil AND $v0.odometer < 5", NSGreaterThanPredicateOperatorType, 0) ],
        @[ @"FillUp", [NSPredicate predicateWithFormat:@"SUBQUERY(vehicle.fillUps, $x, $x.odometer < odometer).@count == 0"] ],
        @[ @"Owner", [NSPredicate predicateWithFormat:@"SUBQUERY(vehicles, $v, ANY $v.fillUps.odometer > 5).@count > 0"] ],
    ];

    for (NSArray *each in cases) {
        NSString *entityName = each[0];
        NSPredicate *predicate = each[1];
        NSManagedObjectContext *ctx = [self contextOnFleet:psc];
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entityName];
        [fetch setPredicate:predicate];
        [fetch setResultType:NSManagedObjectIDResultType];

        NSError *error = nil;
        NSArray *objectIDs = [ctx executeFetchRequest:fetch error:&error];
        XCTAssertNotNil(objectIDs, @"%@: %@", predicate, error);
        XCTAssertTrue([objectIDs count] > 1, @"%@", predicate);
        XCTAssertEqual([[ctx registeredObjects] count], (NSUInteger)0, @"%@ registered objects", predicate);

        NSArray *sorted = @[ [NSSortDescriptor sortDescriptorWithKey:fleetNameKey(entityName) ascending:YES] ];
        NSArray *all = [self fetchEntityNamed:entityName inContext:ctx predicate:predicate sortDescriptors:sorted];

        [fetch setResultType:NSManagedObjectResultType];
        [fetch setSortDescriptors:sorted];
        [fetch setFetchOffset:1];
        [fetch setFetchLimit:1];
        NSArray *page = [ctx executeFetchRequest:fetch error:&error];
        XCTAssertEqualObjects(page, [all subarrayWithRange:NSMakeRange(1, 1)], @"%@", predicate);
    }
}


/* Two sibling entities, each declaring a to-one of the same name to the
   same entity with an inverse of its own: one table holds both, in one
   column, and each keeps its own destination and inverse. */
static NSManagedObjectModel *siblingsSharingARelationshipNameModel(NSArray *order, BOOL ordered)
{
    NSEntityDescription *unit = fleetEntity(@"Unit");
    NSEntityDescription *event = fleetEntity(@"Event");
    NSEntityDescription *metered = fleetEntity(@"Metered");
    NSEntityDescription *income = fleetEntity(@"Income");

    NSRelationshipDescription *meteredUnit = fleetRelationship(@"unit", NO);
    NSRelationshipDescription *meteredEvents = fleetRelationship(@"meteredEvents", YES);
    NSRelationshipDescription *incomeUnit = fleetRelationship(@"unit", NO);
    NSRelationshipDescription *incomes = fleetRelationship(@"incomes", YES);

    [meteredEvents setOrdered:ordered];
    [incomes setOrdered:ordered];
    fleetInverses(meteredUnit, unit, meteredEvents, metered);
    fleetInverses(incomeUnit, unit, incomes, income);

    [unit setProperties:@[ fleetAttribute(@"name", NSStringAttributeType), meteredEvents, incomes ]];
    [event setProperties:@[ fleetAttribute(@"note", NSStringAttributeType) ]];
    [metered setProperties:@[ meteredUnit ]];
    [income setProperties:@[ incomeUnit ]];
    NSDictionary *byName = @{ @"Metered" : metered, @"Income" : income };
    [event setSubentities:@[ byName[order[0]], byName[order[1]] ]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ unit, event, metered, income ]];
    return model;
}

/* The notes of a to-many's members: in order when it is ordered, sorted
   when it is not. */
static NSArray *siblingNotes(id members)
{
    if ([members isKindOfClass:[NSOrderedSet class]])
        return [[members array] valueForKey:@"note"];
    return [[[members allObjects] valueForKey:@"note"] sortedArrayUsingSelector:@selector(compare:)];
}

/* km and mi, by name, in a context of their own. */
- (NSArray *)siblingUnitsWithModel:(NSManagedObjectModel *)model context:(NSManagedObjectContext **)ctxp
{
    NSManagedObjectContext *ctx = [self contextWithModel:model options:nil];
    NSArray *units = [self fetchEntityNamed:@"Unit" inContext:ctx predicate:nil
                            sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
    *ctxp = ctx;
    return units;
}

- (void)assertSiblingUnits:(NSArray *)units
                   metered:(NSArray *)kmMetered :(NSArray *)miMetered
                   incomes:(NSArray *)kmIncomes :(NSArray *)miIncomes
                     label:(NSString *)label
{
    XCTAssertEqual([units count], (NSUInteger)2, @"%@", label);
    if ([units count] != 2)
        return;
    XCTAssertEqualObjects(siblingNotes([units[0] valueForKey:@"meteredEvents"]), kmMetered, @"km metered, %@", label);
    XCTAssertEqualObjects(siblingNotes([units[1] valueForKey:@"meteredEvents"]), miMetered, @"mi metered, %@", label);
    XCTAssertEqualObjects(siblingNotes([units[0] valueForKey:@"incomes"]), kmIncomes, @"km incomes, %@", label);
    XCTAssertEqualObjects(siblingNotes([units[1] valueForKey:@"incomes"]), miIncomes, @"mi incomes, %@", label);
}

- (void)assertSiblingsKeepTheirRelationshipsOfOneName:(NSArray *)order ordered:(BOOL)ordered
{
    NSString *label = [NSString stringWithFormat:@"%@%@", order, ordered ? @", ordered" : @""];
    NSManagedObjectContext *ctx = [self contextWithModel:siblingsSharingARelationshipNameModel(order, ordered) options:nil];
    NSManagedObject *km = fleetObject(ctx, @"Unit", @{ @"name" : @"km" });
    NSManagedObject *mi = fleetObject(ctx, @"Unit", @{ @"name" : @"mi" });
    fleetObject(ctx, @"Metered", @{ @"note" : @"a", @"unit" : km });
    fleetObject(ctx, @"Income", @{ @"note" : @"b", @"unit" : km });
    fleetObject(ctx, @"Income", @{ @"note" : @"c", @"unit" : mi });

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* Another, added to a unit already saved. */
    NSArray *units = [self siblingUnitsWithModel:siblingsSharingARelationshipNameModel(order, ordered) context:&ctx];
    XCTAssertEqual([units count], (NSUInteger)2, @"%@", label);
    if ([units count] != 2)
        return;
    fleetObject(ctx, @"Metered", @{ @"note" : @"d", @"unit" : units[1] });
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    ctx = [self contextWithModel:siblingsSharingARelationshipNameModel(order, ordered) options:nil];
    NSArray *events = [self fetchEntityNamed:@"Event" inContext:ctx predicate:nil
                             sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"note" ascending:YES] ]];
    XCTAssertEqualObjects([events valueForKeyPath:@"entity.name"], (@[ @"Metered", @"Income", @"Income", @"Metered" ]), @"%@", label);
    XCTAssertEqualObjects([events valueForKeyPath:@"unit.name"], (@[ @"km", @"km", @"mi", @"mi" ]), @"%@", label);

    units = [self siblingUnitsWithModel:siblingsSharingARelationshipNameModel(order, ordered) context:&ctx];
    [self assertSiblingUnits:units metered:@[ @"a" ] :@[ @"d" ] incomes:@[ @"b" ] :@[ @"c" ] label:label];

    /* A member moved between owners leaves only its own sibling's
       relationship: b to mi keeps a on km, the metered events of mi
       keep d. */
    units = [self siblingUnitsWithModel:siblingsSharingARelationshipNameModel(order, ordered) context:&ctx];
    if ([units count] != 2)
        return;
    NSManagedObject *b = [[[units[0] valueForKey:@"incomes"] objectEnumerator] nextObject];
    [b setValue:units[1] forKey:@"unit"];
    /* Ordered, b joins mi's incomes after c. */
    NSArray *miIncomes = ordered ? @[ @"c", @"b" ] : @[ @"b", @"c" ];
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    units = [self siblingUnitsWithModel:siblingsSharingARelationshipNameModel(order, ordered) context:&ctx];
    [self assertSiblingUnits:units metered:@[ @"a" ] :@[ @"d" ] incomes:@[] :miIncomes label:label];

    /* And one removed: a leaves km's metered events, b and c stay mi's
       incomes. */
    NSManagedObject *a = [[[units[0] valueForKey:@"meteredEvents"] objectEnumerator] nextObject];
    if (ordered)
        [[units[0] mutableOrderedSetValueForKey:@"meteredEvents"] removeObject:a];
    else
        [[units[0] mutableSetValueForKey:@"meteredEvents"] removeObject:a];
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    units = [self siblingUnitsWithModel:siblingsSharingARelationshipNameModel(order, ordered) context:&ctx];
    [self assertSiblingUnits:units metered:@[] :@[ @"d" ] incomes:@[] :miIncomes label:label];
    events = [self fetchEntityNamed:@"Event" inContext:ctx predicate:nil
                    sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"note" ascending:YES] ]];
    XCTAssertEqualObjects([events valueForKeyPath:@"unit.name"], (@[ [NSNull null], @"mi", @"mi", @"mi" ]), @"%@", label);

    /* Predicates through each sibling's inverse find only its own rows. */
    NSArray *found = [self fetchEntityNamed:@"Unit" inContext:ctx
                                  predicate:[NSPredicate predicateWithFormat:@"ANY incomes.note == 'b'"] sortDescriptors:nil];
    XCTAssertEqualObjects([found valueForKey:@"name"], @[ @"mi" ], @"%@", label);
    found = [self fetchEntityNamed:@"Unit" inContext:ctx
                         predicate:[NSPredicate predicateWithFormat:@"ANY meteredEvents.note == 'b'"] sortDescriptors:nil];
    XCTAssertEqualObjects([found valueForKey:@"name"], @[], @"%@", label);
    found = [self fetchEntityNamed:@"Unit" inContext:ctx
                         predicate:[NSPredicate predicateWithFormat:@"meteredEvents.@count == 1 AND incomes.@count == 2"] sortDescriptors:nil];
    XCTAssertEqualObjects([found valueForKey:@"name"], @[ @"mi" ], @"%@", label);
}

- (void)testSiblingsKeepTheirRelationshipsOfOneName
{
    for (NSNumber *ordered in @[ @NO, @YES ]) {
        [self assertSiblingsKeepTheirRelationshipsOfOneName:@[ @"Metered", @"Income" ] ordered:[ordered boolValue]];
        [self removeStoreFilesAtURL:self.storeURL];
        [self assertSiblingsKeepTheirRelationshipsOfOneName:@[ @"Income", @"Metered" ] ordered:[ordered boolValue]];
        [self removeStoreFilesAtURL:self.storeURL];
    }
}

/* Three siblings each declaring a to-one "unit" and an attribute "note"
   - a string in Ant and Cat, a number in Bee - declared out of name order;
   Ant's and Bee's units have ordered inverses. */
static NSManagedObjectModel *siblingColumnsModel(void)
{
    NSEntityDescription *unit = fleetEntity(@"Unit");
    NSEntityDescription *root = fleetEntity(@"Root");
    NSEntityDescription *cat = fleetEntity(@"Cat");
    NSEntityDescription *ant = fleetEntity(@"Ant");
    NSEntityDescription *bee = fleetEntity(@"Bee");
    NSMutableArray *inverses = [NSMutableArray array];

    for (NSEntityDescription *sibling in @[ cat, ant, bee ]) {
        NSRelationshipDescription *toUnit = fleetRelationship(@"unit", NO);
        NSRelationshipDescription *members = fleetRelationship([[sibling name] lowercaseString], YES);
        [members setOrdered:sibling != cat];
        fleetInverses(toUnit, unit, members, sibling);
        [inverses addObject:members];
        [sibling setProperties:@[ toUnit, fleetAttribute(@"note", sibling == bee ? NSInteger64AttributeType : NSStringAttributeType) ]];
    }
    [root setProperties:@[ fleetAttribute(@"base", NSStringAttributeType) ]];
    [root setSubentities:@[ cat, ant, bee ]];
    [unit setProperties:inverses];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ unit, root, cat, ant, bee ]];
    return model;
}

/* One unit with two of each sibling, in order; saved. */
- (void)fillSiblingColumnsInContext:(NSManagedObjectContext *)ctx
{
    NSManagedObject *unit = fleetObject(ctx, @"Unit", @{});
    for (NSString *name in @[ @"Cat", @"Ant", @"Bee" ])
        for (NSString *suffix in @[ @"1", @"2" ]) {
            id note = [name isEqualToString:@"Bee"] ? (id)@([suffix intValue] * 10) : [name stringByAppendingString:suffix];
            fleetObject(ctx, name, @{ @"base" : [name stringByAppendingString:suffix], @"note" : note, @"unit" : unit });
        }
    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
}

/* Each sibling's values and order read back. */
- (void)assertSiblingColumnsReadBackWithModel:(NSManagedObjectModel *)model label:(NSString *)label
{
    NSManagedObjectContext *ctx = [self contextWithModel:model options:nil];
    NSArray *units = [self fetchEntityNamed:@"Unit" inContext:ctx predicate:nil sortDescriptors:nil];
    XCTAssertEqual([units count], (NSUInteger)1, @"%@", label);
    if ([units count] != 1)
        return;

    XCTAssertEqualObjects([[[units[0] valueForKey:@"ant"] array] valueForKey:@"note"], (@[ @"Ant1", @"Ant2" ]), @"%@", label);
    XCTAssertEqualObjects([[[units[0] valueForKey:@"bee"] array] valueForKey:@"note"], (@[ @10, @20 ]), @"%@", label);
    XCTAssertEqualObjects([[[[units[0] valueForKey:@"cat"] allObjects] valueForKey:@"note"] sortedArrayUsingSelector:@selector(compare:)],
                          (@[ @"Cat1", @"Cat2" ]), @"%@", label);

    NSArray *roots = [self fetchEntityNamed:@"Root" inContext:ctx predicate:nil
                            sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"base" ascending:YES] ]];
    XCTAssertEqualObjects([roots valueForKeyPath:@"entity.name"], (@[ @"Ant", @"Ant", @"Bee", @"Bee", @"Cat", @"Cat" ]), @"%@", label);
    for (NSManagedObject *object in roots)
        XCTAssertEqual([object valueForKey:@"unit"], units[0], @"%@ %@", label, [object valueForKey:@"base"]);

    NSArray *found = [self fetchEntityNamed:@"Bee" inContext:ctx predicate:[NSPredicate predicateWithFormat:@"note > 15"] sortDescriptors:nil];
    XCTAssertEqualObjects([found valueForKey:@"base"], @[ @"Bee2" ], @"%@", label);
    found = [self fetchEntityNamed:@"Ant" inContext:ctx predicate:[NSPredicate predicateWithFormat:@"note == 'Ant2' AND unit != nil"] sortDescriptors:nil];
    XCTAssertEqualObjects([found valueForKey:@"base"], @[ @"Ant2" ], @"%@", label);
}

/* Rows of a sibling, as a column's values: "-" for NULL.  The column is
   not quoted: SQLite takes a quoted name that is no column for a string. */
- (NSArray *)storedColumn:(NSString *)column ofEntity:(NSString *)entityName
{
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    NSMutableArray *values = [NSMutableArray array];
    NSString *sql = [NSString stringWithFormat:
        @"SELECT %@ FROM ZROOT WHERE Z_ENT = (SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = '%@') ORDER BY ZBASE", column, entityName];

    sqlite3_open([[self.storeURL path] UTF8String], &database);
    if (sqlite3_prepare_v2(database, [sql UTF8String], -1, &statement, NULL) == SQLITE_OK)
        while (sqlite3_step(statement) == SQLITE_ROW)
            [values addObject:sqlite3_column_type(statement, 0) == SQLITE_NULL ? @"-"
                              : [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)]];
    else
        [values addObject:[NSString stringWithFormat:@"no column %@", column]];
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return values;
}

/* Order values, which Apple's store spaces apart: the first before the
   second. */
- (void)assertStoredOrder:(NSArray *)values label:(NSString *)label
{
    XCTAssertEqual([values count], (NSUInteger)2, @"%@: %@", label, values);
    if ([values count] != 2)
        return;
    XCTAssertFalse([values containsObject:@"-"], @"%@: %@", label, values);
    XCTAssertLessThan([values[0] longLongValue], [values[1] longLongValue], @"%@: %@", label, values);
}

/* As Apple's store names them: the first sibling by name takes ZUNIT and
   ZNOTE, each later one the next suffix, whatever the order the siblings
   were declared in; an ordered to-many's order sits beside its foreign
   key, named after it. */
- (void)testSiblingsPropertiesOfOneNameHaveColumnsOfTheirOwn
{
    NSManagedObjectContext *ctx = [self contextWithModel:siblingColumnsModel() options:nil];
    [self fillSiblingColumnsInContext:ctx];

    NSArray *expected = @[ @[ @"Ant", @"ZUNIT", @"ZNOTE", @"Z_FOK_UNIT" ],
                           @[ @"Bee", @"ZUNIT1", @"ZNOTE1", @"Z_FOK_UNIT1" ],
                           @[ @"Cat", @"ZUNIT2", @"ZNOTE2", @"" ] ];
    for (NSArray *row in expected) {
        for (NSString *column in @[ @"ZUNIT", @"ZUNIT1", @"ZUNIT2" ]) {
            NSArray *values = [self storedColumn:column ofEntity:row[0]];
            BOOL own = [column isEqualToString:row[1]];
            XCTAssertEqual([values count], (NSUInteger)2, @"%@ %@: %@", row[0], column, values);
            XCTAssertEqual([values containsObject:@"-"], !own, @"%@ %@: %@", row[0], column, values);
        }
        NSArray *notes = [self storedColumn:row[2] ofEntity:row[0]];
        NSArray *expectedNotes = [row[0] isEqualToString:@"Bee"] ? @[ @"10", @"20" ] : @[ [row[0] stringByAppendingString:@"1"], [row[0] stringByAppendingString:@"2"] ];
        XCTAssertEqualObjects(notes, expectedNotes, @"%@ %@", row[0], row[2]);
        if ([row[3] length] > 0)
            [self assertStoredOrder:[self storedColumn:row[3] ofEntity:row[0]] label:[NSString stringWithFormat:@"%@ %@", row[0], row[3]]];
    }

    [self assertSiblingColumnsReadBackWithModel:siblingColumnsModel() label:@"reopened"];
}

#if __has_include(<CoreData/CDExternalDataStore.h>)
/* A store made before siblings' properties had columns of their own: one
   ZUNIT and one ZNOTE for all of them, and the order of each ordered
   to-many in Z_FOK_<to-many>.  Opened, it gets the columns, each with its
   own entities' values. */
- (void)testAStoreWithSiblingsSharingAColumnIsGivenTheirOwn
{
    NSManagedObjectContext *ctx = [self contextWithModel:siblingColumnsModel() options:nil];
    [self fillSiblingColumnsInContext:ctx];
    ctx = nil;

    /* The columns as such a store had them. */
    sqlite3 *database = NULL;
    sqlite3_open([[self.storeURL path] UTF8String], &database);
    for (NSString *sql in @[ @"UPDATE ZROOT SET ZUNIT = COALESCE(ZUNIT, ZUNIT1, ZUNIT2), ZNOTE = COALESCE(ZNOTE, ZNOTE1, ZNOTE2)",
                             @"DROP INDEX ZROOT_ZUNIT1_INDEX", @"DROP INDEX ZROOT_ZUNIT2_INDEX",
                             @"ALTER TABLE ZROOT DROP COLUMN ZUNIT1", @"ALTER TABLE ZROOT DROP COLUMN ZUNIT2",
                             @"ALTER TABLE ZROOT DROP COLUMN ZNOTE1", @"ALTER TABLE ZROOT DROP COLUMN ZNOTE2",
                             @"ALTER TABLE ZROOT RENAME COLUMN Z_FOK_UNIT TO Z_FOK_ANT",
                             @"ALTER TABLE ZROOT RENAME COLUMN Z_FOK_UNIT1 TO Z_FOK_BEE" ]) {
        char *message = NULL;
        XCTAssertEqual(sqlite3_exec(database, [sql UTF8String], NULL, NULL, &message), SQLITE_OK, @"%@: %s", sql, message);
        sqlite3_free(message);
    }
    sqlite3_close(database);
    NSArray *before = [self storedColumn:@"ZUNIT1" ofEntity:@"Bee"];
    XCTAssertEqualObjects(before, @[ @"no column ZUNIT1" ], @"%@", before);

    [self assertSiblingColumnsReadBackWithModel:siblingColumnsModel() label:@"upgraded"];
    XCTAssertEqualObjects([self storedColumn:@"ZNOTE1" ofEntity:@"Bee"], (@[ @"10", @"20" ]));
    XCTAssertEqualObjects([self storedColumn:@"ZNOTE" ofEntity:@"Bee"], (@[ @"-", @"-" ]));
    XCTAssertEqualObjects([self storedColumn:@"ZUNIT" ofEntity:@"Ant"], (@[ @"1", @"1" ]));
    [self assertStoredOrder:[self storedColumn:@"Z_FOK_UNIT1" ofEntity:@"Bee"] label:@"upgraded Bee Z_FOK_UNIT1"];

    /* And it goes on as one made so: written, and read back again. */
    ctx = [self contextWithModel:siblingColumnsModel() options:nil];
    NSArray *bees = [self fetchEntityNamed:@"Bee" inContext:ctx predicate:nil
                           sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"base" ascending:YES] ]];
    [bees[0] setValue:@30 forKey:@"note"];
    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"%@", error);
    XCTAssertEqualObjects([self storedColumn:@"ZNOTE1" ofEntity:@"Bee"], (@[ @"30", @"20" ]));
}
#endif

/* A context that merged another context's save deleting objects saves as
   Apple's does: the rows are gone already, so it writes nothing for them
   - no conflict over rows it cannot find - but reports them deleted, and
   lets them go. */
- (void)testAContextThatMergedADeletionSaves
{
    NSEntityDescription *owner = fleetEntity(@"Owner"), *part = fleetEntity(@"Part"), *bit = fleetEntity(@"Bit");
    NSRelationshipDescription *parts = fleetRelationship(@"parts", YES), *partOwner = fleetRelationship(@"owner", NO);
    NSRelationshipDescription *bits = fleetRelationship(@"bits", YES), *bitPart = fleetRelationship(@"part", NO);
    [parts setDeleteRule:NSCascadeDeleteRule];
    [bits setDeleteRule:NSCascadeDeleteRule];
    fleetInverses(parts, part, partOwner, owner);
    fleetInverses(bits, bit, bitPart, part);
    [owner setProperties:@[ fleetAttribute(@"name", NSStringAttributeType), parts ]];
    [part setProperties:@[ fleetAttribute(@"name", NSStringAttributeType), partOwner, bits ]];
    [bit setProperties:@[ fleetAttribute(@"name", NSStringAttributeType), bitPart ]];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ owner, part, bit ]];

    NSManagedObjectContext *saving = [self contextWithModel:model options:nil];
    NSManagedObject *o = fleetObject(saving, @"Owner", @{ @"name" : @"o" });
    NSManagedObject *p = fleetObject(saving, @"Part", @{ @"name" : @"p", @"owner" : o });
    NSManagedObject *b = fleetObject(saving, @"Bit", @{ @"name" : @"b", @"part" : p });
    NSError *error = nil;
    XCTAssertTrue([saving save:&error], @"%@", error);

    NSManagedObjectContext *merging = [[NSManagedObjectContext alloc] init];
    [merging setPersistentStoreCoordinator:[saving persistentStoreCoordinator]];
    NSManagedObject *mergingOwner = [merging existingObjectWithID:[o objectID] error:NULL];
    NSManagedObject *mergingPart = [merging existingObjectWithID:[p objectID] error:NULL];
    XCTAssertNotNil([merging existingObjectWithID:[b objectID] error:NULL]);

    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification
                                                                    object:saving queue:nil usingBlock:^(NSNotification *note) {
        [merging mergeChangesFromContextDidSaveNotification:note];
    }];
    [saving deleteObject:p];
    XCTAssertTrue([saving save:&error], @"%@", error);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    [merging processPendingChanges];
    XCTAssertEqual([[merging deletedObjects] count], (NSUInteger)2);
    XCTAssertEqual([[merging updatedObjects] count], (NSUInteger)0);
    XCTAssertEqual([[mergingOwner valueForKey:@"parts"] count], (NSUInteger)0);

    __block NSDictionary *saved = nil;
    observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification
                                                                 object:merging queue:nil usingBlock:^(NSNotification *note) {
        saved = [note userInfo];
    }];
    XCTAssertTrue([merging save:&error], @"%@", error);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    XCTAssertEqual([saved[NSDeletedObjectsKey] count], (NSUInteger)2);
    XCTAssertEqual([saved[NSUpdatedObjectsKey] count], (NSUInteger)0);
    XCTAssertFalse([merging hasChanges]);
    XCTAssertNil([mergingPart managedObjectContext]);

    /* And it goes on saving its own changes. */
    [mergingOwner setValue:@"renamed" forKey:@"name"];
    XCTAssertTrue([merging save:&error], @"%@", error);
    NSManagedObjectContext *reader = [[NSManagedObjectContext alloc] init];
    [reader setPersistentStoreCoordinator:[saving persistentStoreCoordinator]];
    NSArray *owners = [self fetchEntityNamed:@"Owner" inContext:reader predicate:nil sortDescriptors:nil];
    XCTAssertEqualObjects([owners valueForKey:@"name"], @[ @"renamed" ]);
    XCTAssertEqual([[self fetchEntityNamed:@"Part" inContext:reader predicate:nil sortDescriptors:nil] count], (NSUInteger)0);
}

/* -- the coordinator's row cache ------------------------------------------- */

static NSManagedObjectModel *rowCacheModel(void)
{
    NSEntityDescription *item = fleetEntity(@"Item");
    [item setProperties:@[ fleetAttribute(@"name", NSStringAttributeType) ]];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ item ]];
    return model;
}

/* The name of the item, read in a new context of coordinator with the
   staleness interval given, the context let go of after. */
- (NSString *)nameOfItem:(NSManagedObjectID *)objectID
           inCoordinator:(NSPersistentStoreCoordinator *)coordinator
               staleness:(NSTimeInterval)staleness
{
    NSString *name = nil;
    @autoreleasepool {
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
        [context setPersistentStoreCoordinator:coordinator];
        [context setStalenessInterval:staleness];
        name = [[[context objectWithID:objectID] valueForKey:@"name"] copy];
    }
    return name;
}

/* The item renamed by another coordinator - another process. */
- (void)renameItem:(NSManagedObjectID *)objectID to:(NSString *)name
{
    @autoreleasepool {
        NSManagedObjectContext *other = [self contextWithModel:rowCacheModel() options:nil];
        NSManagedObjectID *otherID = [[other persistentStoreCoordinator]
            managedObjectIDForURIRepresentation:[objectID URIRepresentation]];
        NSError *error = nil;
        [[other existingObjectWithID:otherID error:&error] setValue:name forKey:@"name"];
        XCTAssertTrue([other save:&error], @"%@", error);
    }
}

/* A saved item, and its coordinator; no context holds it. */
- (NSManagedObjectID *)savedItemNamed:(NSString *)name coordinator:(NSPersistentStoreCoordinator **)coordinatorp
{
    NSManagedObjectID *objectID = nil;
    @autoreleasepool {
        NSManagedObjectContext *context = [self contextWithModel:rowCacheModel() options:nil];
        NSManagedObject *item = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:context];
        [item setValue:name forKey:@"name"];
        NSError *error = nil;
        XCTAssertTrue([context save:&error], @"%@", error);
        objectID = [item objectID];
        *coordinatorp = [context persistentStoreCoordinator];
    }
    return objectID;
}

/* As Apple's coordinator: a row it read is kept while some context holds
   its object, and fills a fault in any of its contexts - unchanged by
   another coordinator's write - unless the context's stalenessInterval
   is 0, which reads the store and keeps what it read.  Once no context
   holds the object, the row is let go and read again. */
- (void)testTheCoordinatorKeepsTheRowsItsContextsHold
{
    NSPersistentStoreCoordinator *coordinator = nil;
    NSManagedObjectID *objectID = [self savedItemNamed:@"v1" coordinator:&coordinator];

    NSManagedObjectContext *holder = [[NSManagedObjectContext alloc] init];
    [holder setPersistentStoreCoordinator:coordinator];
    NSManagedObject *held = [holder objectWithID:objectID];
    XCTAssertEqualObjects([held valueForKey:@"name"], @"v1");

    [self renameItem:objectID to:@"v2"];
    XCTAssertEqualObjects([self nameOfItem:objectID inCoordinator:coordinator staleness:-1], @"v1", @"the row kept");
    XCTAssertEqualObjects([self nameOfItem:objectID inCoordinator:coordinator staleness:0], @"v2", @"staleness 0 reads the store");
    XCTAssertEqualObjects([self nameOfItem:objectID inCoordinator:coordinator staleness:-1], @"v2", @"and keeps what it read");

    held = nil;
    holder = nil;
    [self renameItem:objectID to:@"v3"];
    XCTAssertEqualObjects([self nameOfItem:objectID inCoordinator:coordinator staleness:-1], @"v3", @"let go once no context holds it");
}

/* A row older than a context's positive stalenessInterval is read again. */
- (void)testARowOlderThanTheStalenessIntervalIsReadAgain
{
    NSPersistentStoreCoordinator *coordinator = nil;
    NSManagedObjectID *objectID = [self savedItemNamed:@"v1" coordinator:&coordinator];

    NSManagedObjectContext *holder = [[NSManagedObjectContext alloc] init];
    [holder setPersistentStoreCoordinator:coordinator];
    XCTAssertEqualObjects([[holder objectWithID:objectID] valueForKey:@"name"], @"v1");

    [self renameItem:objectID to:@"v2"];
    XCTAssertEqualObjects([self nameOfItem:objectID inCoordinator:coordinator staleness:60], @"v1");
    [NSThread sleepForTimeInterval:0.5];
    XCTAssertEqualObjects([self nameOfItem:objectID inCoordinator:coordinator staleness:0.25], @"v2");
    XCTAssertEqualObjects([self nameOfItem:objectID inCoordinator:coordinator staleness:60], @"v2", @"kept as read again");
}

/* A fetch reads its objects' rows, and the coordinator keeps them: an
   object the fetching context had already read keeps its values, but
   another context filling a fault reads the row as fetched. */
- (void)testAFetchRefreshesTheRowsKept
{
    NSPersistentStoreCoordinator *coordinator = nil;
    NSManagedObjectID *objectID = [self savedItemNamed:@"v1" coordinator:&coordinator];

    NSManagedObjectContext *holder = [[NSManagedObjectContext alloc] init];
    [holder setPersistentStoreCoordinator:coordinator];
    NSManagedObject *held = [holder objectWithID:objectID];
    XCTAssertEqualObjects([held valueForKey:@"name"], @"v1");

    [self renameItem:objectID to:@"v2"];
    NSArray *fetched = [holder executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Item"] error:NULL];
    XCTAssertEqual([fetched firstObject], held);
    XCTAssertEqualObjects([held valueForKey:@"name"], @"v1", @"the fetching context's object keeps its values");
    XCTAssertEqualObjects([self nameOfItem:objectID inCoordinator:coordinator staleness:-1], @"v2", @"the row kept is the fetched one");
}

/* Refreshing an object fills its fault again as any fault is filled: from
   the row kept, if the context's stalenessInterval allows. */
- (void)testARefreshedObjectIsFilledFromTheRowKept
{
    NSPersistentStoreCoordinator *coordinator = nil;
    NSManagedObjectID *objectID = [self savedItemNamed:@"v1" coordinator:&coordinator];

    NSManagedObjectContext *holder = [[NSManagedObjectContext alloc] init];
    [holder setPersistentStoreCoordinator:coordinator];
    NSManagedObject *held = [holder objectWithID:objectID];
    XCTAssertEqualObjects([held valueForKey:@"name"], @"v1");

    XCTAssertEqual([holder stalenessInterval], (NSTimeInterval)-1, @"Apple's default");
    [self renameItem:objectID to:@"v2"];
    [holder refreshObject:held mergeChanges:NO];
    XCTAssertEqualObjects([held valueForKey:@"name"], @"v1", @"staleness -1: the row kept");

    [holder setStalenessInterval:0];
    [holder refreshObject:held mergeChanges:NO];
    XCTAssertEqualObjects([held valueForKey:@"name"], @"v2", @"staleness 0: the store's");
}

@end
