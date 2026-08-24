/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* MomcCompiledModelTests - the same MomcFixture.xcdatamodeld source is
   compiled by Apple's model compiler on macOS (Xcode compiles it into
   the test bundle) and by the port's momc on GNUstep (the test
   GNUmakefile runs it through coredata-model.make).  These assertions
   run against whichever .momd ended up in the bundle, so they prove
   the two compilers agree on what the model means. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

@interface MomcCompiledModelTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;

@end

@implementation MomcCompiledModelTests

- (void)setUp
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSURL *url = [bundle URLForResource:@"MomcFixture" withExtension:@"momd"];

    XCTAssertNotNil(url, @"MomcFixture.momd missing from the test bundle");
    self.model = [[NSManagedObjectModel alloc] initWithContentsOfURL:url];
    XCTAssertNotNil(self.model, @"could not load the compiled model");
}

- (void)testEntitiesAndCurrentVersion
{
    NSDictionary *entities = [self.model entitiesByName];

    XCTAssertNotNil([entities objectForKey:@"Author"]);
    XCTAssertNotNil([entities objectForKey:@"Article"]);
    XCTAssertNotNil([entities objectForKey:@"FeaturedArticle"]);

    /* The bundle's current version is version 2, which added
       Article.subtitle. */
    NSEntityDescription *article = [entities objectForKey:@"Article"];
    XCTAssertNotNil([[article attributesByName] objectForKey:@"subtitle"],
                    @"the CURRENT version (2) must have been loaded");
}

- (void)testAttributeTypesAndDefaults
{
    NSDictionary *attributes =
        [[[self.model entitiesByName] objectForKey:@"Article"] attributesByName];

    NSAttributeDescription *title = [attributes objectForKey:@"title"];
    XCTAssertEqual([title attributeType], NSStringAttributeType);
    XCTAssertFalse([title isOptional]);
    XCTAssertEqualObjects([title defaultValue], @"Untitled");

    NSAttributeDescription *wordCount = [attributes objectForKey:@"wordCount"];
    XCTAssertEqual([wordCount attributeType], NSInteger32AttributeType);
    XCTAssertEqualObjects([wordCount defaultValue],
                          [NSNumber numberWithInt:0]);

    XCTAssertEqual([[attributes objectForKey:@"createdAt"] attributeType],
                   NSDateAttributeType);
}

- (void)testTransformableAttribute
{
    NSAttributeDescription *payload =
        [[[[self.model entitiesByName] objectForKey:@"Article"]
             attributesByName] objectForKey:@"payload"];

    XCTAssertEqual([payload attributeType], NSTransformableAttributeType);
    XCTAssertEqualObjects([payload valueTransformerName],
                          @"NSSecureUnarchiveFromData");
    XCTAssertEqualObjects([payload attributeValueClassName], @"NSDictionary");
}

- (void)testDerivedAttributes
{
    NSEntityDescription *article =
        [[self.model entitiesByName] objectForKey:@"Article"];
    NSDerivedAttributeDescription *titleUpper =
        [[article attributesByName] objectForKey:@"titleUpper"];

    XCTAssertTrue([titleUpper
        isKindOfClass:[NSDerivedAttributeDescription class]]);

    NSExpression *derivation = [titleUpper derivationExpression];
    XCTAssertEqual([derivation expressionType], NSFunctionExpressionType);
    XCTAssertTrue([[derivation function] hasPrefix:@"uppercase"],
                  @"unexpected function %@", [derivation function]);

    NSDerivedAttributeDescription *nameCopy =
        [[[[self.model entitiesByName] objectForKey:@"Author"]
             attributesByName] objectForKey:@"nameCopy"];
    XCTAssertTrue([nameCopy
        isKindOfClass:[NSDerivedAttributeDescription class]]);
    XCTAssertEqual([[nameCopy derivationExpression] expressionType],
                   NSKeyPathExpressionType);
    XCTAssertEqualObjects([[nameCopy derivationExpression] keyPath], @"name");
}

/* Version 2 adds a UUID attribute, a URI attribute and makes
   Author.articles ordered; both compilers must carry all three. */
- (void)testUUIDURIAndOrderedCompile
{
    NSDictionary *attributes =
        [[[self.model entitiesByName] objectForKey:@"Article"]
            attributesByName];

    XCTAssertEqual([[attributes objectForKey:@"externalID"] attributeType],
                   NSUUIDAttributeType);
    XCTAssertEqual([[attributes objectForKey:@"homepage"] attributeType],
                   NSURIAttributeType);

    NSRelationshipDescription *articles =
        [[[[self.model entitiesByName] objectForKey:@"Author"]
             relationshipsByName] objectForKey:@"articles"];
    XCTAssertTrue([articles isOrdered]);
}

- (void)testRelationshipsAndInverses
{
    NSEntityDescription *author =
        [[self.model entitiesByName] objectForKey:@"Author"];
    NSEntityDescription *article =
        [[self.model entitiesByName] objectForKey:@"Article"];

    NSRelationshipDescription *articles =
        [[author relationshipsByName] objectForKey:@"articles"];
    NSRelationshipDescription *authorRel =
        [[article relationshipsByName] objectForKey:@"author"];

    XCTAssertTrue([articles isToMany]);
    XCTAssertFalse([authorRel isToMany]);
    XCTAssertEqualObjects([[articles destinationEntity] name], @"Article");
    XCTAssertEqualObjects([[authorRel destinationEntity] name], @"Author");
    XCTAssertEqual([articles inverseRelationship], authorRel);
    XCTAssertEqual([authorRel inverseRelationship], articles);
    XCTAssertEqual([articles deleteRule], NSCascadeDeleteRule);
    XCTAssertEqual([authorRel deleteRule], NSNullifyDeleteRule);
}

- (void)testSubentities
{
    NSEntityDescription *article =
        [[self.model entitiesByName] objectForKey:@"Article"];
    NSEntityDescription *featured =
        [[self.model entitiesByName] objectForKey:@"FeaturedArticle"];

    XCTAssertEqual([featured superentity], article);
    XCTAssertNotNil([[article subentitiesByName]
                        objectForKey:@"FeaturedArticle"]);

    /* Inherited + own properties. */
    XCTAssertNotNil([[featured attributesByName] objectForKey:@"title"]);
    XCTAssertNotNil([[featured attributesByName] objectForKey:@"badge"]);
}

- (void)testUniquenessConstraints
{
    NSArray *constraints =
        [[[self.model entitiesByName] objectForKey:@"Author"]
            uniquenessConstraints];

    XCTAssertEqual([constraints count], (NSUInteger)1);
    XCTAssertEqual([[constraints lastObject] count], (NSUInteger)1);

    /* Elements may come back as strings or property descriptions. */
    id item = [[constraints lastObject] lastObject];
    NSString *name = [item isKindOfClass:[NSString class]]
                         ? item : [(NSPropertyDescription *)item name];
    XCTAssertEqualObjects(name, @"name");
}

- (void)testConfiguration
{
    NSArray *members =
        [self.model entitiesForConfiguration:@"Publishing"];

    XCTAssertEqual([members count], (NSUInteger)3);
}

- (void)testFetchRequestTemplate
{
    NSFetchRequest *template =
        [self.model fetchRequestTemplateForName:@"LongArticles"];

    XCTAssertNotNil(template);
    XCTAssertEqualObjects([[template entity] name], @"Article");
    XCTAssertNotNil([template predicate]);
    XCTAssertTrue([[[template predicate] predicateFormat]
                      rangeOfString:@"wordCount"].location != NSNotFound);
}

/* The compiled model is usable, not just inspectable: open a SQLite
   store with it and round-trip an object. */
- (void)testCompiledModelOpensAStore
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"store"];
    NSURL *storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:self.model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:storeURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to open store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    NSManagedObject *author =
        [NSEntityDescription insertNewObjectForEntityForName:@"Author"
                                      inManagedObjectContext:ctx];
    [author setValue:@"Cocoa" forKey:@"name"];
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    [ctx refreshObject:author mergeChanges:NO];
    XCTAssertEqualObjects([author valueForKey:@"nameCopy"], @"Cocoa",
                          @"derived attribute computed on save");

    [[NSFileManager defaultManager] removeItemAtURL:storeURL error:NULL];
    [[NSFileManager defaultManager]
        removeItemAtPath:[[storeURL path] stringByAppendingString:@"-wal"]
                   error:NULL];
    [[NSFileManager defaultManager]
        removeItemAtPath:[[storeURL path] stringByAppendingString:@"-shm"]
                   error:NULL];
}

@end
