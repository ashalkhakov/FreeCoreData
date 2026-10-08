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

@end
