/* Fetch indexes: NSFetchIndexDescription and NSFetchIndexElementDescription,
   an entity's indexes and a property's indexed flag, and what an archive
   keeps of them.  Every expectation here was taken from Apple's Core Data
   on macOS, where this suite runs against it.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import <sqlite3.h>

@interface FetchIndexTests : XCTestCase
@end

@implementation FetchIndexTests

static NSAttributeDescription *attribute(NSString *name, NSAttributeType type)
{
    NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];

    [attribute setName:name];
    [attribute setAttributeType:type];
    [attribute setOptional:YES];
    return attribute;
}

static NSEntityDescription *entityWith(NSString *name, NSArray *properties)
{
    NSEntityDescription *entity = [[NSEntityDescription alloc] init];

    [entity setName:name];
    [entity setProperties:properties];
    return entity;
}

static NSArray *names(NSArray *indexes)
{
    return [indexes valueForKey:@"name"];
}

- (void)testAnElementIsAscendingBinaryOrAnRTreeOfNumbers
{
    NSAttributeDescription *title = attribute(@"title", NSStringAttributeType);
    NSAttributeDescription *lat = attribute(@"lat", NSFloatAttributeType);
    NSAttributeDescription *rank = attribute(@"rank", NSInteger16AttributeType);
    NSFetchIndexElementDescription *element =
        [[NSFetchIndexElementDescription alloc] initWithProperty:title collationType:NSFetchIndexElementTypeBinary];

    XCTAssertTrue([element isAscending], @"ascending unless said otherwise");
    XCTAssertEqualObjects([element propertyName], @"title");
    XCTAssertEqual([element property], title);
    XCTAssertEqual([element collationType], NSFetchIndexElementTypeBinary);
    XCTAssertNil([element indexDescription]);

    XCTAssertNoThrow([[NSFetchIndexElementDescription alloc] initWithProperty:lat collationType:NSFetchIndexElementTypeRTree]);
    XCTAssertNoThrow([[NSFetchIndexElementDescription alloc] initWithProperty:rank collationType:NSFetchIndexElementTypeRTree]);
    XCTAssertThrows([[NSFetchIndexElementDescription alloc] initWithProperty:title collationType:NSFetchIndexElementTypeRTree],
                    @"an R-tree holds numbers");
    XCTAssertThrows([[NSFetchIndexElementDescription alloc] initWithProperty:[[NSAttributeDescription alloc] init]
                                                              collationType:NSFetchIndexElementTypeBinary],
                    @"an element names its property");
}

- (void)testAnIndexOwnsItsElementsAndAnEntityItsIndexes
{
    NSAttributeDescription *title = attribute(@"title", NSStringAttributeType);
    NSEntityDescription *note = entityWith(@"Note", @[ title ]);
    NSFetchIndexElementDescription *element =
        [[NSFetchIndexElementDescription alloc] initWithProperty:title collationType:NSFetchIndexElementTypeBinary];
    NSFetchIndexDescription *index = [[NSFetchIndexDescription alloc] initWithName:@"byTitle" elements:@[ element ]];

    XCTAssertEqual([element indexDescription], index);
    XCTAssertNil([index entity]);
    XCTAssertEqualObjects([note indexes], @[], @"no indexes, not nil");

    [index setPartialIndexPredicate:[NSPredicate predicateWithFormat:@"title != nil"]];
    [note setIndexes:@[ index ]];

    XCTAssertEqual([index entity], note);
    XCTAssertEqualObjects(names([note indexes]), @[ @"byTitle" ]);

    NSFetchIndexDescription *copy = [index copy];

    XCTAssertTrue(copy != index, @"a copy is another index");
    XCTAssertEqual([copy entity], note, @"of the same entity");
    XCTAssertEqualObjects([copy name], @"byTitle");
    XCTAssertEqualObjects([[copy partialIndexPredicate] predicateFormat], @"title != nil");
    XCTAssertTrue([[copy elements] firstObject] != element, @"with elements of its own");
    XCTAssertEqual([[[copy elements] firstObject] indexDescription], copy);
}

- (void)testAPropertyIsIndexedByAnIndexOfItAlone
{
    NSAttributeDescription *a = attribute(@"a", NSStringAttributeType);
    NSAttributeDescription *b = attribute(@"b", NSStringAttributeType);
    NSAttributeDescription *c = attribute(@"c", NSStringAttributeType);
    NSEntityDescription *thing = entityWith(@"Thing", @[ a, b, c ]);

    XCTAssertFalse([a isIndexed]);

    /* Marking one indexed makes an index named after it. */
    [a setIndexed:YES];
    XCTAssertTrue([a isIndexed]);
    XCTAssertEqualObjects(names([thing indexes]), @[ @"a" ]);

    /* Setting the indexes decides it: only a one-element binary index
       makes its property indexed. */
    NSFetchIndexDescription *byB = [[NSFetchIndexDescription alloc] initWithName:@"byB" elements:@[
        [[NSFetchIndexElementDescription alloc] initWithProperty:b collationType:NSFetchIndexElementTypeBinary] ]];
    NSFetchIndexDescription *byAC = [[NSFetchIndexDescription alloc] initWithName:@"byAC" elements:@[
        [[NSFetchIndexElementDescription alloc] initWithProperty:a collationType:NSFetchIndexElementTypeBinary],
        [[NSFetchIndexElementDescription alloc] initWithProperty:c collationType:NSFetchIndexElementTypeBinary] ]];

    [thing setIndexes:@[ byB, byAC ]];
    XCTAssertTrue([b isIndexed]);
    XCTAssertFalse([a isIndexed], @"one element of several");
    XCTAssertFalse([c isIndexed]);

    /* Ascending, that is; partial or not. */
    NSFetchIndexElementDescription *down =
        [[NSFetchIndexElementDescription alloc] initWithProperty:c collationType:NSFetchIndexElementTypeBinary];
    NSFetchIndexDescription *partial = [[NSFetchIndexDescription alloc] initWithName:@"partialA" elements:@[
        [[NSFetchIndexElementDescription alloc] initWithProperty:a collationType:NSFetchIndexElementTypeBinary] ]];

    [down setAscending:NO];
    [partial setPartialIndexPredicate:[NSPredicate predicateWithFormat:@"a != nil"]];
    [thing setIndexes:@[ [[NSFetchIndexDescription alloc] initWithName:@"downC" elements:@[ down ]], partial ]];
    XCTAssertFalse([c isIndexed], @"a descending index");
    XCTAssertTrue([a isIndexed], @"a partial one");
}

- (void)testARelationshipIsAlwaysIndexed
{
    NSEntityDescription *folder = entityWith(@"Folder", @[]);
    NSRelationshipDescription *toOne = [[NSRelationshipDescription alloc] init];
    NSRelationshipDescription *toMany = [[NSRelationshipDescription alloc] init];

    [toOne setName:@"folder"];
    [toOne setDestinationEntity:folder];
    [toOne setMaxCount:1];
    [toMany setName:@"notes"];
    [toMany setMaxCount:0];
    [toOne setInverseRelationship:toMany];
    [toMany setInverseRelationship:toOne];

    NSEntityDescription *note = entityWith(@"Note", @[ toOne ]);

    [toMany setDestinationEntity:note];
    [folder setProperties:@[ toMany ]];

    XCTAssertTrue([toOne isIndexed], @"by its foreign key");
    XCTAssertTrue([toMany isIndexed]);
}

/* An archive keeps the indexes and the indexed flag of each attribute;
   reading it back makes an index of every indexed attribute, named after
   it, ahead of the archived ones - Apple's way, and why a compiled model
   has a "b" index beside the "byB" it was given. */
- (void)testAnArchiveKeepsTheIndexes
{
    NSAttributeDescription *a = attribute(@"a", NSStringAttributeType);
    NSAttributeDescription *b = attribute(@"b", NSStringAttributeType);
    NSAttributeDescription *lat = attribute(@"lat", NSFloatAttributeType);
    NSEntityDescription *thing = entityWith(@"Thing", @[ a, b, lat ]);
    NSFetchIndexElementDescription *descending =
        [[NSFetchIndexElementDescription alloc] initWithProperty:a collationType:NSFetchIndexElementTypeBinary];

    [descending setAscending:NO];

    NSFetchIndexDescription *byB = [[NSFetchIndexDescription alloc] initWithName:@"byB" elements:@[
        [[NSFetchIndexElementDescription alloc] initWithProperty:b collationType:NSFetchIndexElementTypeBinary] ]];
    NSFetchIndexDescription *byADown = [[NSFetchIndexDescription alloc] initWithName:@"byADown" elements:@[ descending ]];
    NSFetchIndexDescription *byPlace = [[NSFetchIndexDescription alloc] initWithName:@"byPlace" elements:@[
        [[NSFetchIndexElementDescription alloc] initWithProperty:lat collationType:NSFetchIndexElementTypeRTree] ]];

    [byADown setPartialIndexPredicate:[NSPredicate predicateWithFormat:@"a != nil"]];
    [thing setIndexes:@[ byB, byADown, byPlace ]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];

    [model setEntities:@[ thing ]];

    /* The calls gnustep-base has, as the other archive tests use. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSManagedObjectModel *back = [NSKeyedUnarchiver unarchiveObjectWithData:
        [NSKeyedArchiver archivedDataWithRootObject:model]];
#pragma clang diagnostic pop
    NSEntityDescription *entity = [[back entitiesByName] objectForKey:@"Thing"];
    NSMutableDictionary *byName = [NSMutableDictionary dictionary];

    for (NSFetchIndexDescription *index in [entity indexes])
        [byName setObject:index forKey:[index name]];

    XCTAssertEqualObjects(names([entity indexes]), (@[ @"b", @"byB", @"byADown", @"byPlace" ]));
    XCTAssertTrue([[[entity attributesByName] objectForKey:@"b"] isIndexed]);
    XCTAssertFalse([[[entity attributesByName] objectForKey:@"a"] isIndexed]);

    NSFetchIndexElementDescription *element = [[[byName objectForKey:@"byADown"] elements] firstObject];

    XCTAssertEqual([element property], [[entity attributesByName] objectForKey:@"a"], @"found again by name");
    XCTAssertFalse([element isAscending]);
    XCTAssertEqual([[byName objectForKey:@"byADown"] entity], entity);
    XCTAssertEqualObjects([[[byName objectForKey:@"byADown"] partialIndexPredicate] predicateFormat], @"a != nil");
    NSFetchIndexElementDescription *rtree = [[[byName objectForKey:@"byPlace"] elements] firstObject];

    XCTAssertEqual([rtree collationType], NSFetchIndexElementTypeRTree);
}

/* Indexes are no part of the schema a store must migrate. */
- (void)testIndexesLeaveTheVersionHashAlone
{
    NSAttributeDescription *title = attribute(@"title", NSStringAttributeType);
    NSEntityDescription *note = entityWith(@"Note", @[ title ]);
    NSData *before = [note versionHash];

    [note setIndexes:@[ [[NSFetchIndexDescription alloc] initWithName:@"byTitle" elements:@[
        [[NSFetchIndexElementDescription alloc] initWithProperty:title collationType:NSFetchIndexElementTypeBinary] ]] ]];

    XCTAssertEqualObjects([note versionHash], before);
}

/* ------------------------------------------------------------------ */
/* The SQLite store                                                    */
/* ------------------------------------------------------------------ */

static NSFetchIndexElementDescription *element(NSPropertyDescription *property, BOOL ascending)
{
    NSFetchIndexElementDescription *element =
        [[NSFetchIndexElementDescription alloc] initWithProperty:property collationType:NSFetchIndexElementTypeBinary];

    [element setAscending:ascending];
    return element;
}

static NSFetchIndexDescription *fetchIndex(NSString *name, NSArray *elements)
{
    return [[NSFetchIndexDescription alloc] initWithName:name elements:elements];
}

static NSRelationshipDescription *relationship(NSString *name, NSEntityDescription *destination, BOOL toMany)
{
    NSRelationshipDescription *relationship = [[NSRelationshipDescription alloc] init];

    [relationship setName:name];
    [relationship setDestinationEntity:destination];
    [relationship setMaxCount:toMany ? 0 : 1];
    [relationship setOptional:YES];
    [relationship setDeleteRule:NSNullifyDeleteRule];
    return relationship;
}

static void inverse(NSRelationshipDescription *a, NSRelationshipDescription *b)
{
    [a setInverseRelationship:b];
    [b setInverseRelationship:a];
}

/* Folder <-->> Note; Place, with its subentity Cafe, <<-->> Tag.  With
   indexes when asked: on a string, descending and ascending together, a
   to-one alone and with an attribute, an R-tree, a partial one, and one on
   the subentity. */
- (NSManagedObjectModel *)storeModelWithIndexes:(BOOL)withIndexes
{
    NSEntityDescription *folder = entityWith(@"Folder", @[]);
    NSEntityDescription *note = entityWith(@"Note", @[]);
    NSEntityDescription *place = entityWith(@"Place", @[]);
    NSEntityDescription *cafe = entityWith(@"Cafe", @[]);
    NSEntityDescription *tag = entityWith(@"Tag", @[]);
    NSAttributeDescription *title = attribute(@"title", NSStringAttributeType);
    NSAttributeDescription *stamp = attribute(@"stamp", NSDateAttributeType);
    NSAttributeDescription *lat = attribute(@"lat", NSFloatAttributeType);
    NSAttributeDescription *roast = attribute(@"roast", NSStringAttributeType);
    NSRelationshipDescription *toFolder = relationship(@"folder", folder, NO);
    NSRelationshipDescription *notes = relationship(@"notes", note, YES);
    NSRelationshipDescription *tags = relationship(@"tags", tag, YES);
    NSRelationshipDescription *places = relationship(@"places", place, YES);

    inverse(toFolder, notes);
    inverse(tags, places);
    [folder setProperties:@[ attribute(@"name", NSStringAttributeType), notes ]];
    [note setProperties:@[ title, stamp, lat, toFolder ]];
    [place setProperties:@[ attribute(@"label", NSStringAttributeType), tags ]];
    [cafe setProperties:@[ roast ]];
    [tag setProperties:@[ attribute(@"word", NSStringAttributeType), places ]];
    [place setSubentities:@[ cafe ]];

    if (withIndexes) {
        NSFetchIndexDescription *titled = fetchIndex(@"byTitledOnly", @[ element(title, YES) ]);

        [titled setPartialIndexPredicate:[NSPredicate predicateWithFormat:@"title != nil"]];
        [note setIndexes:@[
            fetchIndex(@"byTitle", @[ element(title, YES) ]),
            fetchIndex(@"byStampAndTitle", @[ element(stamp, NO), element(title, YES) ]),
            fetchIndex(@"byFolder", @[ element(toFolder, YES) ]),
            fetchIndex(@"byFolderAndTitle", @[ element(toFolder, YES), element(title, NO) ]),
            fetchIndex(@"byPlace", @[ [[NSFetchIndexElementDescription alloc] initWithProperty:lat collationType:NSFetchIndexElementTypeRTree] ]),
            titled ]];
        [cafe setIndexes:@[ fetchIndex(@"byRoast", @[ element(roast, YES) ]) ]];
    }

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];

    [model setEntities:@[ folder, note, place, cafe, tag ]];
    return model;
}

- (NSString *)storePath
{
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"FetchIndexTests-%@.sqlite", [[NSProcessInfo processInfo] globallyUniqueString]]];
}

- (BOOL)openStoreAt:(NSString *)path model:(NSManagedObjectModel *)model
{
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:NSSQLiteStoreType
                                                         configuration:nil
                                                                   URL:[NSURL fileURLWithPath:path]
                                                               options:nil
                                                                 error:&error];

    XCTAssertNotNil(store, @"%@", error);
    return store != nil && [coordinator removePersistentStore:store error:&error];
}

/* name -> sql of every index (or, for type "table", every table) of the file. */
static NSDictionary *schemaObjects(NSString *path, const char *type)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;

    if (sqlite3_open([path UTF8String], &database) != SQLITE_OK)
        return result;
    sqlite3_prepare_v2(database, "SELECT name, sql FROM sqlite_master WHERE type = ? AND sql IS NOT NULL", -1, &statement, NULL);
    sqlite3_bind_text(statement, 1, type, -1, SQLITE_STATIC);
    while (sqlite3_step(statement) == SQLITE_ROW)
        [result setObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 1)]
                   forKey:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)]];
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return result;
}

static NSArray *columnsOf(NSString *path, NSString *table)
{
    NSMutableArray *result = [NSMutableArray array];
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;

    sqlite3_open([path UTF8String], &database);
    sqlite3_prepare_v2(database, [[NSString stringWithFormat:@"PRAGMA table_info(%@)", table] UTF8String], -1, &statement, NULL);
    while (sqlite3_step(statement) == SQLITE_ROW)
        [result addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 1)]];
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return result;
}

/* The indexes Apple's store creates for this model, as it writes them. */
- (void)testTheStoreCreatesTheIndexesAppleDoes
{
    NSString *path = [self storePath];

    XCTAssertTrue([self openStoreAt:path model:[self storeModelWithIndexes:YES]]);

    NSDictionary *indexes = schemaObjects(path, "index");
    NSString *join = nil;

    for (NSString *table in schemaObjects(path, "table"))
        if ([table hasPrefix:@"Z_"] && [table hasSuffix:@"TAGS"])
            join = table;

    XCTAssertNotNil(join, @"the many-to-many's join table");

    NSArray *joinColumns = columnsOf(path, join);
    NSString *first = [joinColumns firstObject], *second = [joinColumns lastObject];
    NSString *joinIndex = [NSString stringWithFormat:@"%@_%@_INDEX", join, second];
    NSDictionary *expected = @{
        @"ZNOTE_ZFOLDER_INDEX": @"CREATE INDEX ZNOTE_ZFOLDER_INDEX ON ZNOTE (ZFOLDER)",
        @"ZPLACE_Z_ENT_INDEX": @"CREATE INDEX ZPLACE_Z_ENT_INDEX ON ZPLACE (Z_ENT)",
        joinIndex: [NSString stringWithFormat:@"CREATE INDEX %@ ON %@ (%@, %@)", joinIndex, join, second, first],
        @"Z_Note_byTitle": @"CREATE INDEX Z_Note_byTitle ON ZNOTE (ZTITLE COLLATE BINARY ASC)",
        @"Z_Note_byStampAndTitle": @"CREATE INDEX Z_Note_byStampAndTitle ON ZNOTE (ZSTAMP COLLATE BINARY DESC, ZTITLE COLLATE BINARY ASC)",
        @"Z_Note_byFolderAndTitle": @"CREATE INDEX Z_Note_byFolderAndTitle ON ZNOTE (ZFOLDER COLLATE BINARY ASC, ZTITLE COLLATE BINARY DESC)",
        @"Z_Note_byTitledOnly": @"CREATE INDEX Z_Note_byTitledOnly ON ZNOTE (ZTITLE COLLATE BINARY ASC) WHERE ZTITLE IS NOT NULL",
        @"Z_Cafe_byRoast": @"CREATE INDEX Z_Cafe_byRoast ON ZPLACE (ZROAST COLLATE BINARY ASC)",
    };

    /* No byFolder (the foreign key's index is it), no byPlace (an R-tree). */
    XCTAssertEqualObjects([NSSet setWithArray:[indexes allKeys]], [NSSet setWithArray:[expected allKeys]]);
    for (NSString *name in expected)
        XCTAssertEqualObjects([indexes objectForKey:name], [expected objectForKey:name], @"%@", name);

    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

/* Made with the schema, as Apple's are: a store that exists keeps what it
   has when a model with more indexes - and the same version hashes -
   opens it. */
- (void)testAnExistingStoreKeepsTheIndexesItHas
{
    NSString *path = [self storePath];

    XCTAssertTrue([self openStoreAt:path model:[self storeModelWithIndexes:NO]]);

    NSSet *before = [NSSet setWithArray:[schemaObjects(path, "index") allKeys]];

    XCTAssertTrue([self openStoreAt:path model:[self storeModelWithIndexes:YES]]);
    XCTAssertEqualObjects([NSSet setWithArray:[schemaObjects(path, "index") allKeys]], before);
    XCTAssertFalse([before containsObject:@"Z_Note_byTitle"]);

    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

@end
