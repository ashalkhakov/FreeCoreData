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

@interface NSSQLitePersistentStoreTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;

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

    NSArray *beside = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[self.storeURL path] stringByDeletingLastPathComponent] error:NULL];
    for (NSString *file in beside)
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

@end
