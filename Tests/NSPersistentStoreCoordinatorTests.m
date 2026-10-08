/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSPersistentStoreCoordinatorTests - basic coordinator tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

@interface NSPersistentStoreCoordinatorTests : XCTestCase
@end

@implementation NSPersistentStoreCoordinatorTests

- (void)testRegisteredStoreTypes
{
    NSDictionary *types = [NSPersistentStoreCoordinator registeredStoreTypes];
    XCTAssertNotNil(types);
    XCTAssertNotNil([types objectForKey:NSInMemoryStoreType]);
    XCTAssertNotNil([types objectForKey:NSXMLStoreType]);
}

- (void)testInMemoryStore
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    NSPersistentStoreCoordinator *psc =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    XCTAssertNotNil(psc);

    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store);
    XCTAssertNil(error);
    XCTAssertEqual([[psc persistentStores] count], (NSUInteger)1);
}

- (void)testRemoveStore
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    NSPersistentStoreCoordinator *psc =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];

    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store);
    BOOL removed = [psc removePersistentStore:store error:&error];
    XCTAssertTrue(removed);
    XCTAssertEqual([[psc persistentStores] count], (NSUInteger)0);
}

/* Authors and their books (a novel is a book): attributes, a to-one, a
   to-many, and a subentity. */
- (NSManagedObjectModel *)libraryModel
{
    NSEntityDescription *author = [[NSEntityDescription alloc] init];
    author.name = @"Author";
    NSEntityDescription *book = [[NSEntityDescription alloc] init];
    book.name = @"Book";
    NSEntityDescription *novel = [[NSEntityDescription alloc] init];
    novel.name = @"Novel";

    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    name.name = @"name";
    name.attributeType = NSStringAttributeType;
    NSAttributeDescription *title = [[NSAttributeDescription alloc] init];
    title.name = @"title";
    title.attributeType = NSStringAttributeType;
    NSAttributeDescription *pages = [[NSAttributeDescription alloc] init];
    pages.name = @"pages";
    pages.attributeType = NSInteger32AttributeType;
    pages.optional = YES;
    NSAttributeDescription *genre = [[NSAttributeDescription alloc] init];
    genre.name = @"genre";
    genre.attributeType = NSStringAttributeType;
    genre.optional = YES;

    NSRelationshipDescription *books = [[NSRelationshipDescription alloc] init];
    books.name = @"books";
    books.destinationEntity = book;
    books.minCount = 0;
    books.maxCount = 0;
    books.optional = YES;
    books.deleteRule = NSNullifyDeleteRule;
    NSRelationshipDescription *writer = [[NSRelationshipDescription alloc] init];
    writer.name = @"author";
    writer.destinationEntity = author;
    writer.minCount = 0;
    writer.maxCount = 1;
    writer.optional = YES;
    writer.deleteRule = NSNullifyDeleteRule;
    books.inverseRelationship = writer;
    writer.inverseRelationship = books;

    author.properties = @[ name, books ];
    book.properties = @[ title, pages, writer ];
    novel.properties = @[ genre ];
    book.subentities = @[ novel ];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ author, book, novel ];
    return model;
}

- (NSURL *)temporarySQLiteURL
{
    NSString *name = [NSString stringWithFormat:@"psc-migrate-%@.sqlite", [[NSProcessInfo processInfo] globallyUniqueString]];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
}

- (void)removeSQLiteAt:(NSURL *)url
{
    for (NSString *suffix in @[ @"", @"-wal", @"-shm" ])
        [[NSFileManager defaultManager] removeItemAtPath:[url.path stringByAppendingString:suffix] error:NULL];
}

- (void)testMigratePersistentStoreCopiesObjectsRelationshipsAndMetadata
{
    NSManagedObjectModel *model = [self libraryModel];
    NSURL *from = [self temporarySQLiteURL], *to = [self temporarySQLiteURL];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:from options:nil error:&error];
    XCTAssertNotNil(store, @"%@", error);

    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.persistentStoreCoordinator = psc;
    NSManagedObject *austen = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:context];
    [austen setValue:@"Austen" forKey:@"name"];
    NSManagedObject *emma = [NSEntityDescription insertNewObjectForEntityForName:@"Novel" inManagedObjectContext:context];
    [emma setValue:@"Emma" forKey:@"title"];
    [emma setValue:@474 forKey:@"pages"];
    [emma setValue:@"comedy" forKey:@"genre"];
    [emma setValue:austen forKey:@"author"];
    NSManagedObject *letters = [NSEntityDescription insertNewObjectForEntityForName:@"Book" inManagedObjectContext:context];
    [letters setValue:@"Letters" forKey:@"title"];
    [letters setValue:austen forKey:@"author"];
    NSManagedObject *loose = [NSEntityDescription insertNewObjectForEntityForName:@"Book" inManagedObjectContext:context];
    [loose setValue:@"Anonymous" forKey:@"title"];
    XCTAssertTrue([context save:&error], @"%@", error);
    NSMutableDictionary *metadata = [[psc metadataForPersistentStore:store] mutableCopy];
    metadata[@"Example.kept"] = @"yes";
    [psc setMetadata:metadata forPersistentStore:store];
    XCTAssertTrue([context save:&error], @"%@", error);
    NSString *oldUUID = [psc metadataForPersistentStore:store][NSStoreUUIDKey];

    NSPersistentStore *moved = [psc migratePersistentStore:store toURL:to options:nil withType:NSSQLiteStoreType error:&error];
    XCTAssertNotNil(moved, @"%@", error);
    XCTAssertEqual(psc.persistentStores.count, (NSUInteger)1);
    XCTAssertTrue(psc.persistentStores.firstObject == moved);
    XCTAssertEqualObjects([psc metadataForPersistentStore:moved][@"Example.kept"], @"yes");

    /* Read back from the new file alone, in a coordinator of its own. */
    NSPersistentStoreCoordinator *other = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSPersistentStore *reopened = [other addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:to options:nil error:&error];
    XCTAssertNotNil(reopened, @"%@", error);
    XCTAssertNotEqualObjects([other metadataForPersistentStore:reopened][NSStoreUUIDKey], oldUUID);
    NSManagedObjectContext *reader = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    reader.persistentStoreCoordinator = other;
    NSFetchRequest *authors = [NSFetchRequest fetchRequestWithEntityName:@"Author"];
    NSArray *found = [reader executeFetchRequest:authors error:&error];
    XCTAssertEqual(found.count, (NSUInteger)1, @"%@", error);
    NSManagedObject *author = found.firstObject;
    XCTAssertEqualObjects([author valueForKey:@"name"], @"Austen");
    NSSet *titles = [[author valueForKey:@"books"] valueForKey:@"title"];
    XCTAssertEqualObjects(titles, ([NSSet setWithObjects:@"Emma", @"Letters", nil]));

    NSFetchRequest *books = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
    books.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES] ];
    found = [reader executeFetchRequest:books error:&error];
    XCTAssertEqualObjects([found valueForKey:@"title"], (@[ @"Anonymous", @"Emma", @"Letters" ]));
    NSManagedObject *novel = found[1];
    XCTAssertEqualObjects(novel.entity.name, @"Novel");
    XCTAssertEqualObjects([novel valueForKey:@"genre"], @"comedy");
    XCTAssertEqualObjects([novel valueForKey:@"pages"], @474);
    XCTAssertEqualObjects([[novel valueForKey:@"author"] valueForKey:@"name"], @"Austen");
    XCTAssertNil([found[0] valueForKey:@"author"]);

    /* The old file is left as it was. */
    NSPersistentStoreCoordinator *old = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    XCTAssertNotNil([old addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:from options:nil error:&error], @"%@", error);
    NSManagedObjectContext *oldReader = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    oldReader.persistentStoreCoordinator = old;
    XCTAssertEqual([oldReader countForFetchRequest:books error:NULL], (NSUInteger)3);

    [self removeSQLiteAt:from];
    [self removeSQLiteAt:to];
}


/* Playlists of songs, in order, and people who are each other's friends:
   an ordered many-to-many, and a many-to-many that is its own inverse. */
- (NSManagedObjectModel *)playlistModel
{
    NSEntityDescription *playlist = [[NSEntityDescription alloc] init];
    playlist.name = @"Playlist";
    NSEntityDescription *song = [[NSEntityDescription alloc] init];
    song.name = @"Song";
    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    person.name = @"Person";

    NSAttributeDescription *(^text)(NSString *) = ^(NSString *name) {
        NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
        attribute.name = name;
        attribute.attributeType = NSStringAttributeType;
        attribute.optional = YES;
        return attribute;
    };
    NSRelationshipDescription *(^toMany)(NSString *, NSEntityDescription *) = ^(NSString *name, NSEntityDescription *destination) {
        NSRelationshipDescription *relationship = [[NSRelationshipDescription alloc] init];
        relationship.name = name;
        relationship.destinationEntity = destination;
        relationship.minCount = 0;
        relationship.maxCount = 0;
        relationship.optional = YES;
        relationship.deleteRule = NSNullifyDeleteRule;
        return relationship;
    };

    NSRelationshipDescription *songs = toMany(@"songs", song);
    songs.ordered = YES;
    NSRelationshipDescription *playlists = toMany(@"playlists", playlist);
    songs.inverseRelationship = playlists;
    playlists.inverseRelationship = songs;
    NSRelationshipDescription *friends = toMany(@"friends", person);
    friends.inverseRelationship = friends;

    playlist.properties = @[ text(@"name"), songs ];
    song.properties = @[ text(@"title"), playlists ];
    person.properties = @[ text(@"name"), friends ];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ playlist, song, person ];
    return model;
}

/* An ordered relationship keeps its order through a migration - between
   SQLite files and memory - however the songs were inserted; friends stay
   each other's. */
- (void)testMigratePersistentStoreKeepsOrderAndBothSides
{
    NSManagedObjectModel *model = [self playlistModel];

    /* SQLite to SQLite, SQLite to memory, and memory to SQLite. */
    for (NSArray *types in @[ @[ NSSQLiteStoreType, NSSQLiteStoreType ], @[ NSSQLiteStoreType, NSInMemoryStoreType ],
                              @[ NSInMemoryStoreType, NSSQLiteStoreType ] ]) {
        NSString *source = types[0], *type = types[1];
        NSURL *from = [self temporarySQLiteURL], *to = [self temporarySQLiteURL];
        NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        NSError *error = nil;
        NSPersistentStore *store = [psc addPersistentStoreWithType:source configuration:nil
                                                               URL:[source isEqualToString:NSInMemoryStoreType] ? nil : from
                                                           options:nil error:&error];
        XCTAssertNotNil(store, @"%@", error);

        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        context.persistentStoreCoordinator = psc;
        NSManagedObject *mix = [NSEntityDescription insertNewObjectForEntityForName:@"Playlist" inManagedObjectContext:context];
        [mix setValue:@"mix" forKey:@"name"];
        NSArray *order = @[ @"third", @"first", @"second", @"fourth" ];
        for (NSString *title in order) {
            NSManagedObject *track = [NSEntityDescription insertNewObjectForEntityForName:@"Song" inManagedObjectContext:context];
            [track setValue:title forKey:@"title"];
            [[mix mutableOrderedSetValueForKey:@"songs"] addObject:track];
        }
        NSManagedObject *ann = [NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context];
        [ann setValue:@"ann" forKey:@"name"];
        NSManagedObject *bob = [NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context];
        [bob setValue:@"bob" forKey:@"name"];
        [[ann mutableSetValueForKey:@"friends"] addObject:bob];
        XCTAssertTrue([context save:&error], @"%@", error);

        NSPersistentStore *moved = [psc migratePersistentStore:store
                                                         toURL:[type isEqualToString:NSInMemoryStoreType] ? nil : to
                                                       options:nil
                                                      withType:type
                                                         error:&error];
        XCTAssertNotNil(moved, @"%@: %@", type, error);

        /* Read through the coordinator that now has only the new store. */
        NSManagedObjectContext *reader = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        reader.persistentStoreCoordinator = psc;
        NSManagedObject *list = [[reader executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Playlist"] error:&error] firstObject];
        XCTAssertEqualObjects([[[list valueForKey:@"songs"] array] valueForKey:@"title"], order, @"%@", type);

        NSFetchRequest *people = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
        people.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
        NSArray *found = [reader executeFetchRequest:people error:&error];
        XCTAssertEqual(found.count, (NSUInteger)2, @"%@", type);
        XCTAssertEqualObjects([[found[0] valueForKey:@"friends"] valueForKey:@"name"], [NSSet setWithObject:@"bob"], @"%@", type);
        XCTAssertEqualObjects([[found[1] valueForKey:@"friends"] valueForKey:@"name"], [NSSet setWithObject:@"ann"], @"%@", type);

        [self removeSQLiteAt:from];
        [self removeSQLiteAt:to];
    }
}


/* More songs than one batch of a migration holds, in one playlist: all of
   them arrive, in order. */
- (void)testMigratingALargeStoreKeepsEverythingInOrder
{
    NSManagedObjectModel *model = [self playlistModel];
    NSURL *from = [self temporarySQLiteURL], *to = [self temporarySQLiteURL];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:from options:nil error:&error];
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.persistentStoreCoordinator = psc;
    NSManagedObject *all = [NSEntityDescription insertNewObjectForEntityForName:@"Playlist" inManagedObjectContext:context];
    [all setValue:@"all" forKey:@"name"];
    NSMutableArray *order = [NSMutableArray array];
    for (NSUInteger n = 0; n < 2500; n++) {
        NSString *title = [NSString stringWithFormat:@"%04lu", (unsigned long)((n * 7919) % 2500)];
        NSManagedObject *track = [NSEntityDescription insertNewObjectForEntityForName:@"Song" inManagedObjectContext:context];
        [track setValue:title forKey:@"title"];
        [[all mutableOrderedSetValueForKey:@"songs"] addObject:track];
        [order addObject:title];
    }
    XCTAssertTrue([context save:&error], @"%@", error);

    XCTAssertNotNil([psc migratePersistentStore:store toURL:to options:nil withType:NSSQLiteStoreType error:&error], @"%@", error);

    NSPersistentStoreCoordinator *other = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    XCTAssertNotNil([other addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:to options:nil error:&error], @"%@", error);
    NSManagedObjectContext *reader = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    reader.persistentStoreCoordinator = other;
    XCTAssertEqual([reader countForFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Song"] error:NULL], (NSUInteger)2500);
    NSManagedObject *list = [[reader executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Playlist"] error:&error] firstObject];
    XCTAssertEqualObjects([[[list valueForKey:@"songs"] array] valueForKey:@"title"], order);

    [self removeSQLiteAt:from];
    [self removeSQLiteAt:to];
}

/* Things whose names a stricter version of the model refuses: a store
   holds them under the lax one, and the strict one - with the same version
   hash - opens it, but cannot save copies of them. */
- (NSManagedObjectModel *)thingModelStrict:(BOOL)strict
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    name.name = @"name";
    name.attributeType = NSStringAttributeType;
    name.optional = YES;
    if (strict)
        [name setValidationPredicates:@[ [NSPredicate predicateWithFormat:@"length > 3"] ]
               withValidationWarnings:@[ @"too short" ]];
    NSEntityDescription *thing = [[NSEntityDescription alloc] init];
    thing.name = @"Thing";
    thing.properties = @[ name ];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ thing ];
    return model;
}

- (void)putThingsNamed:(NSArray *)names inStoreAt:(NSURL *)url
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self thingModelStrict:NO]];
    NSError *error = nil;
    XCTAssertNotNil([psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:&error], @"%@", error);
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.persistentStoreCoordinator = psc;
    for (NSString *name in names)
        [[NSEntityDescription insertNewObjectForEntityForName:@"Thing" inManagedObjectContext:context] setValue:name forKey:@"name"];
    XCTAssertTrue([context save:&error], @"%@", error);
    XCTAssertTrue([psc removePersistentStore:psc.persistentStores.firstObject error:&error], @"%@", error);
}

- (NSArray *)namesOfThingsAt:(NSURL *)url
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self thingModelStrict:NO]];
    NSError *error = nil;
    XCTAssertNotNil([psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:&error], @"%@", error);
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.persistentStoreCoordinator = psc;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Thing"];
    fetch.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
    NSArray *names = [[context executeFetchRequest:fetch error:&error] valueForKey:@"name"];
    [psc removePersistentStore:psc.persistentStores.firstObject error:NULL];
    return names;
}

/* A migration that cannot save the copies fails, and the old store stays
   in the coordinator; a store that was there already is left as it was,
   and a new one holds nothing. */
- (void)testAFailedMigrationChangesNothing
{
    for (NSNumber *targetExisted in @[ @NO, @YES ]) {
        NSURL *from = [self temporarySQLiteURL], *to = [self temporarySQLiteURL];
        [self putThingsNamed:@[ @"long enough", @"ab" ] inStoreAt:from];
        if ([targetExisted boolValue])
            [self putThingsNamed:@[ @"already here" ] inStoreAt:to];

        NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self thingModelStrict:YES]];
        NSError *error = nil;
        NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:from options:nil error:&error];
        XCTAssertNotNil(store, @"%@", error);

        error = nil;
        XCTAssertNil([psc migratePersistentStore:store toURL:to options:nil withType:NSSQLiteStoreType error:&error]);
        XCTAssertNotNil(error);
        XCTAssertEqualObjects(psc.persistentStores, @[ store ], @"the old store is still the coordinator's");
        [psc removePersistentStore:store error:NULL];

        XCTAssertEqualObjects([self namesOfThingsAt:to], [targetExisted boolValue] ? @[ @"already here" ] : @[],
                              @"target existed: %@", targetExisted);
        XCTAssertEqual([[self namesOfThingsAt:from] count], (NSUInteger)2);

        [self removeSQLiteAt:from];
        [self removeSQLiteAt:to];
    }
}

@end
