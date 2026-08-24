/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSUUIDAndOrderedRelationshipTests - NSUUIDAttributeType and
   NSURIAttributeType round-trip as NSUUID/NSURL values, and ordered
   to-many relationships keep their order across saves, stores and
   reopens.  Everything here is documented Apple behavior, so the tests
   run identically against Apple's CoreData on macOS. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

@interface NSUUIDAndOrderedRelationshipTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;

@end

@implementation NSUUIDAndOrderedRelationshipTests

- (void)setUp
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"store"];
    self.storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
}

- (void)tearDown
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    [fileManager removeItemAtURL:self.storeURL error:NULL];
    [fileManager removeItemAtPath:[[self.storeURL path]
                                      stringByAppendingString:@"-wal"]
                            error:NULL];
    [fileManager removeItemAtPath:[[self.storeURL path]
                                      stringByAppendingString:@"-shm"]
                            error:NULL];
    self.storeURL = nil;
}

/* Playlist(name, uuid UUID, homepage URI; tracks ordered ->> Track,
   tags ordered <->> Tag), Track(title; playlist -> Playlist),
   Tag(label; playlists ->> Playlist). */
static NSManagedObjectModel *playlistModel(void)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];
    [name setOptional:YES];

    NSAttributeDescription *uuid = [[NSAttributeDescription alloc] init];
    [uuid setName:@"uuid"];
    [uuid setAttributeType:NSUUIDAttributeType];
    [uuid setOptional:YES];

    NSAttributeDescription *homepage = [[NSAttributeDescription alloc] init];
    [homepage setName:@"homepage"];
    [homepage setAttributeType:NSURIAttributeType];
    [homepage setOptional:YES];

    NSAttributeDescription *title = [[NSAttributeDescription alloc] init];
    [title setName:@"title"];
    [title setAttributeType:NSStringAttributeType];
    [title setOptional:YES];

    NSAttributeDescription *label = [[NSAttributeDescription alloc] init];
    [label setName:@"label"];
    [label setAttributeType:NSStringAttributeType];
    [label setOptional:YES];

    NSRelationshipDescription *tracks = [[NSRelationshipDescription alloc] init];
    [tracks setName:@"tracks"];
    [tracks setMinCount:0];
    [tracks setMaxCount:0];
    [tracks setOptional:YES];
    [tracks setOrdered:YES];
    [tracks setDeleteRule:NSCascadeDeleteRule];

    NSRelationshipDescription *playlist = [[NSRelationshipDescription alloc] init];
    [playlist setName:@"playlist"];
    [playlist setMinCount:0];
    [playlist setMaxCount:1];
    [playlist setOptional:YES];
    [playlist setDeleteRule:NSNullifyDeleteRule];

    NSRelationshipDescription *tags = [[NSRelationshipDescription alloc] init];
    [tags setName:@"tags"];
    [tags setMinCount:0];
    [tags setMaxCount:0];
    [tags setOptional:YES];
    [tags setOrdered:YES];
    [tags setDeleteRule:NSNullifyDeleteRule];

    NSRelationshipDescription *playlists = [[NSRelationshipDescription alloc] init];
    [playlists setName:@"playlists"];
    [playlists setMinCount:0];
    [playlists setMaxCount:0];
    [playlists setOptional:YES];
    [playlists setDeleteRule:NSNullifyDeleteRule];

    NSEntityDescription *playlistEntity = [[NSEntityDescription alloc] init];
    [playlistEntity setName:@"Playlist"];
    [playlistEntity setManagedObjectClassName:@"NSManagedObject"];
    [playlistEntity setProperties:
        [NSArray arrayWithObjects:name, uuid, homepage, tracks, tags, nil]];

    NSEntityDescription *trackEntity = [[NSEntityDescription alloc] init];
    [trackEntity setName:@"Track"];
    [trackEntity setManagedObjectClassName:@"NSManagedObject"];
    [trackEntity setProperties:[NSArray arrayWithObjects:title, playlist, nil]];

    NSEntityDescription *tagEntity = [[NSEntityDescription alloc] init];
    [tagEntity setName:@"Tag"];
    [tagEntity setManagedObjectClassName:@"NSManagedObject"];
    [tagEntity setProperties:[NSArray arrayWithObjects:label, playlists, nil]];

    [tracks setDestinationEntity:trackEntity];
    [playlist setDestinationEntity:playlistEntity];
    [tags setDestinationEntity:tagEntity];
    [playlists setDestinationEntity:playlistEntity];
    [tracks setInverseRelationship:playlist];
    [playlist setInverseRelationship:tracks];
    [tags setInverseRelationship:playlists];
    [playlists setInverseRelationship:tags];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObjects:
        playlistEntity, trackEntity, tagEntity, nil]];
    return model;
}

- (NSManagedObjectContext *)contextWithStoreType:(NSString *)storeType
                                     coordinator:(NSPersistentStoreCoordinator **)coordinatorOut
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:playlistModel()];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:storeType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to add %@ store: %@", storeType, error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    if (coordinatorOut != NULL)
        *coordinatorOut = psc;
    return ctx;
}

- (NSManagedObject *)insertTrack:(NSString *)title
                       inContext:(NSManagedObjectContext *)ctx
{
    NSManagedObject *track =
        [NSEntityDescription insertNewObjectForEntityForName:@"Track"
                                      inManagedObjectContext:ctx];
    [track setValue:title forKey:@"title"];
    return track;
}

- (NSArray *)titlesOfOrderedSet:(NSOrderedSet *)tracks
{
    NSMutableArray *titles = [NSMutableArray array];

    for (NSManagedObject *track in tracks)
        [titles addObject:[track valueForKey:@"title"]];
    return titles;
}

/* -- API ------------------------------------------------------------- */

- (void)testIsOrderedDefaultsToNo
{
    NSRelationshipDescription *relationship =
        [[NSRelationshipDescription alloc] init];

    XCTAssertFalse([relationship isOrdered]);
    [relationship setOrdered:YES];
    XCTAssertTrue([relationship isOrdered]);
}

/* -- UUID and URI attributes ----------------------------------------- */

- (void)checkUUIDAndURIRoundTripWithStoreType:(NSString *)storeType
{
    NSPersistentStoreCoordinator *psc = nil;
    NSManagedObjectContext *ctx = [self contextWithStoreType:storeType
                                                 coordinator:&psc];

    NSUUID *uuid = [NSUUID UUID];
    NSURL  *homepage = [NSURL URLWithString:
        @"https://example.org/lists/road%20trip?rev=2"];

    NSManagedObject *playlist =
        [NSEntityDescription insertNewObjectForEntityForName:@"Playlist"
                                      inManagedObjectContext:ctx];
    [playlist setValue:@"Road Trip" forKey:@"name"];
    [playlist setValue:uuid forKey:@"uuid"];
    [playlist setValue:homepage forKey:@"homepage"];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* A fresh context re-reads through the store. */
    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Playlist"
                                 inManagedObjectContext:ctx2]];

    NSArray *fetched = [ctx2 executeFetchRequest:fetch error:&error];
    XCTAssertEqual([fetched count], (NSUInteger)1);

    NSManagedObject *reloaded = [fetched lastObject];
    id reloadedUUID = [reloaded valueForKey:@"uuid"];
    id reloadedHomepage = [reloaded valueForKey:@"homepage"];

    XCTAssertTrue([reloadedUUID isKindOfClass:[NSUUID class]],
                  @"got %@", [reloadedUUID class]);
    XCTAssertEqualObjects(reloadedUUID, uuid);
    XCTAssertTrue([reloadedHomepage isKindOfClass:[NSURL class]],
                  @"got %@", [reloadedHomepage class]);
    XCTAssertEqualObjects(reloadedHomepage, homepage);
}

- (void)testUUIDAndURIRoundTripThroughSQLite
{
    [self checkUUIDAndURIRoundTripWithStoreType:NSSQLiteStoreType];
}

- (void)testUUIDAndURIRoundTripThroughXMLStore
{
    [self checkUUIDAndURIRoundTripWithStoreType:NSXMLStoreType];
}

- (void)testUUIDEqualityPredicate
{
    NSPersistentStoreCoordinator *psc = nil;
    NSManagedObjectContext *ctx = [self contextWithStoreType:NSSQLiteStoreType
                                                 coordinator:&psc];

    NSUUID *wanted = [NSUUID UUID];
    NSManagedObject *first =
        [NSEntityDescription insertNewObjectForEntityForName:@"Playlist"
                                      inManagedObjectContext:ctx];
    [first setValue:@"first" forKey:@"name"];
    [first setValue:wanted forKey:@"uuid"];

    NSManagedObject *second =
        [NSEntityDescription insertNewObjectForEntityForName:@"Playlist"
                                      inManagedObjectContext:ctx];
    [second setValue:@"second" forKey:@"name"];
    [second setValue:[NSUUID UUID] forKey:@"uuid"];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Playlist"
                                 inManagedObjectContext:ctx2]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"uuid == %@",
                                     wanted]];

    NSArray *fetched = [ctx2 executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(fetched, @"fetch failed: %@", error);
    XCTAssertEqual([fetched count], (NSUInteger)1);
    XCTAssertEqualObjects([[fetched lastObject] valueForKey:@"name"],
                          @"first");
}

/* -- ordered to-many -------------------------------------------------- */

- (void)checkOrderedTracksWithStoreType:(NSString *)storeType
{
    NSPersistentStoreCoordinator *psc = nil;
    NSManagedObjectContext *ctx = [self contextWithStoreType:storeType
                                                 coordinator:&psc];

    NSManagedObject *playlist =
        [NSEntityDescription insertNewObjectForEntityForName:@"Playlist"
                                      inManagedObjectContext:ctx];
    [playlist setValue:@"mix" forKey:@"name"];

    NSManagedObject *charlie = [self insertTrack:@"charlie" inContext:ctx];
    NSManagedObject *alpha = [self insertTrack:@"alpha" inContext:ctx];
    NSManagedObject *bravo = [self insertTrack:@"bravo" inContext:ctx];

    /* Deliberately NOT alphabetical and NOT insertion order. */
    [playlist setValue:[NSOrderedSet orderedSetWithObjects:
                           charlie, alpha, bravo, nil]
                forKey:@"tracks"];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* Order must come back from the STORE, not from memory. */
    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Playlist"
                                 inManagedObjectContext:ctx2]];

    NSArray *fetched = [ctx2 executeFetchRequest:fetch error:&error];
    XCTAssertEqual([fetched count], (NSUInteger)1);

    id tracks = [[fetched lastObject] valueForKey:@"tracks"];
    XCTAssertTrue([tracks isKindOfClass:[NSOrderedSet class]],
                  @"ordered to-many must come back as an ordered set, got %@",
                  [tracks class]);
    XCTAssertEqualObjects([self titlesOfOrderedSet:tracks],
        ([NSArray arrayWithObjects:@"charlie", @"alpha", @"bravo", nil]));

    /* Reorder and save; the new order persists. */
    NSManagedObject *reloaded = [fetched lastObject];
    NSMutableOrderedSet *reversed = [NSMutableOrderedSet orderedSet];

    for (NSManagedObject *track in [[tracks reversedOrderedSet] array])
        [reversed addObject:track];
    [reloaded setValue:reversed forKey:@"tracks"];
    XCTAssertTrue([ctx2 save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx3 = [[NSManagedObjectContext alloc] init];
    [ctx3 setPersistentStoreCoordinator:psc];

    fetched = [ctx3 executeFetchRequest:fetch error:&error];
    XCTAssertEqual([fetched count], (NSUInteger)1);
    XCTAssertEqualObjects(
        [self titlesOfOrderedSet:[[fetched lastObject] valueForKey:@"tracks"]],
        ([NSArray arrayWithObjects:@"bravo", @"alpha", @"charlie", nil]));
}

- (void)testOrderedTracksPersistOrderInSQLite
{
    [self checkOrderedTracksWithStoreType:NSSQLiteStoreType];
}

- (void)testOrderedTracksPersistOrderInXMLStore
{
    [self checkOrderedTracksWithStoreType:NSXMLStoreType];
}

- (void)testOrderedTracksPersistOrderInMemoryStore
{
    [self checkOrderedTracksWithStoreType:NSInMemoryStoreType];
}

- (void)testMutableOrderedSetValueForKey
{
    NSPersistentStoreCoordinator *psc = nil;
    NSManagedObjectContext *ctx = [self contextWithStoreType:NSSQLiteStoreType
                                                 coordinator:&psc];

    NSManagedObject *playlist =
        [NSEntityDescription insertNewObjectForEntityForName:@"Playlist"
                                      inManagedObjectContext:ctx];
    NSManagedObject *one = [self insertTrack:@"one" inContext:ctx];
    NSManagedObject *two = [self insertTrack:@"two" inContext:ctx];

    NSMutableOrderedSet *tracks =
        [playlist mutableOrderedSetValueForKey:@"tracks"];

    [tracks addObject:one];
    [tracks addObject:two];
    XCTAssertEqual([tracks count], (NSUInteger)2);

    [tracks insertObject:[self insertTrack:@"zero" inContext:ctx] atIndex:0];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Playlist"
                                 inManagedObjectContext:ctx2]];

    NSArray *fetched = [ctx2 executeFetchRequest:fetch error:&error];
    XCTAssertEqualObjects(
        [self titlesOfOrderedSet:[[fetched lastObject] valueForKey:@"tracks"]],
        ([NSArray arrayWithObjects:@"zero", @"one", @"two", nil]));
}

- (void)testOrderedManyToManyPersistsOrder
{
    NSPersistentStoreCoordinator *psc = nil;
    NSManagedObjectContext *ctx = [self contextWithStoreType:NSSQLiteStoreType
                                                 coordinator:&psc];

    NSManagedObject *playlist =
        [NSEntityDescription insertNewObjectForEntityForName:@"Playlist"
                                      inManagedObjectContext:ctx];
    [playlist setValue:@"mix" forKey:@"name"];

    NSMutableArray *tags = [NSMutableArray array];

    for (NSString *label in [NSArray arrayWithObjects:
                                @"rock", @"calm", @"summer", nil]) {
        NSManagedObject *tag =
            [NSEntityDescription insertNewObjectForEntityForName:@"Tag"
                                          inManagedObjectContext:ctx];
        [tag setValue:label forKey:@"label"];
        [tags addObject:tag];
    }

    /* summer, rock, calm - neither insertion nor alphabetical order. */
    [playlist setValue:[NSOrderedSet orderedSetWithObjects:
                           [tags objectAtIndex:2], [tags objectAtIndex:0],
                           [tags objectAtIndex:1], nil]
                forKey:@"tags"];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Playlist"
                                 inManagedObjectContext:ctx2]];

    NSArray *fetched = [ctx2 executeFetchRequest:fetch error:&error];
    XCTAssertEqual([fetched count], (NSUInteger)1);

    id reloadedTags = [[fetched lastObject] valueForKey:@"tags"];
    NSMutableArray *labels = [NSMutableArray array];

    for (NSManagedObject *tag in reloadedTags)
        [labels addObject:[tag valueForKey:@"label"]];
    XCTAssertEqualObjects(labels,
        ([NSArray arrayWithObjects:@"summer", @"rock", @"calm", nil]));
}


/* The ordered collection returned by -valueForKey: is a live mutable
   view, mirroring the unordered NSManagedObjectSet: in-place mutation
   (GNUstep's NSArrayController mutates bound collections in place)
   must edit the relationship - order preserved, change tracked,
   inverse maintained - never a detached snapshot whose edits are
   silently lost. */
- (void)testOrderedRelationshipValueIsMutable
{
    NSPersistentStoreCoordinator *psc = nil;
    NSManagedObjectContext *ctx = [self contextWithStoreType:NSSQLiteStoreType
                                                 coordinator:&psc];

    NSManagedObject *playlist =
        [NSEntityDescription insertNewObjectForEntityForName:@"Playlist"
                                      inManagedObjectContext:ctx];
    NSManagedObject *one = [self insertTrack:@"one" inContext:ctx];
    NSManagedObject *two = [self insertTrack:@"two" inContext:ctx];
    [playlist setValue:[NSOrderedSet orderedSetWithObjects:one, two, nil]
                forKey:@"tracks"];
    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSMutableOrderedSet *tracks =
        (NSMutableOrderedSet *)[playlist valueForKey:@"tracks"];
    XCTAssertTrue([tracks isKindOfClass:[NSMutableOrderedSet class]]);
    XCTAssertEqualObjects([self titlesOfOrderedSet:tracks],
        ([NSArray arrayWithObjects:@"one", @"two", nil]));

    NSManagedObject *zero = [self insertTrack:@"zero" inContext:ctx];

#if defined(__APPLE__)
    /* Apple's faulting ordered set accepts in-place mutation but, like
       its unordered sibling, bypasses change processing (Mac-verified
       for the unordered case; encoded symmetrically here). */
    [tracks insertObject:zero atIndex:0];
    XCTAssertEqual([tracks count], (NSUInteger)3);
    [tracks removeObjectAtIndex:0];
    XCTAssertEqual([tracks count], (NSUInteger)2);
    [ctx deleteObject:zero];
#else
    /* The port routes in-place mutation through the model. */
    [tracks insertObject:zero atIndex:0];
    XCTAssertEqual([tracks count], (NSUInteger)3);
    XCTAssertEqualObjects([self titlesOfOrderedSet:tracks],
        ([NSArray arrayWithObjects:@"zero", @"one", @"two", nil]));
    XCTAssertEqualObjects([zero valueForKey:@"playlist"], playlist);

    [tracks removeObjectAtIndex:1];
    XCTAssertEqualObjects([self titlesOfOrderedSet:tracks],
        ([NSArray arrayWithObjects:@"zero", @"two", nil]));
    XCTAssertNil([one valueForKey:@"playlist"]);
    [ctx deleteObject:one];
#endif

    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Playlist"
                                 inManagedObjectContext:ctx2]];

    NSArray *fetched = [ctx2 executeFetchRequest:fetch error:&error];
#if defined(__APPLE__)
    XCTAssertEqualObjects(
        [self titlesOfOrderedSet:[[fetched lastObject] valueForKey:@"tracks"]],
        ([NSArray arrayWithObjects:@"one", @"two", nil]));
#else
    XCTAssertEqualObjects(
        [self titlesOfOrderedSet:[[fetched lastObject] valueForKey:@"tracks"]],
        ([NSArray arrayWithObjects:@"zero", @"two", nil]));
#endif
}

@end
