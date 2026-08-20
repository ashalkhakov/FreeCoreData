/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSDerivedAttributeTests - tests for NSDerivedAttributeDescription
   (Apple: macOS 10.15/iOS 13).  These tests are written against Apple's
   documented behavior so they run identically against Apple's CoreData
   on macOS and against the GNUstep port; run them on macOS to validate
   assumptions about Apple's implementation.

   Documented behavior being verified (NSDerivedAttributeDescription
   class documentation):

   - supported derivations: a to-one key path ("name", "author.name"), a
     string transform (uppercase:/lowercase:/canonical: of a string key
     path, canonical: being the case- and diacritic-insensitive
     representation), a to-many aggregate with a *terminal* operator
     ("articles.@count", "articles.wordCount.@sum" - Apple rejects
     operators as intermediate components), and now();
   - derived values are recomputed when the context is saved, and a
     property "does not reflect unsaved changes until you save the
     context and refresh the object" (the tests therefore only assert
     the value after save + refresh, and never assert what is visible
     between save and refresh - Apple leaves it stale there, while this
     port may already show the fresh value);
   - because derived values are persisted, fetch-request predicates can
     compare them inside the store;
   - a non-optional derived attribute fails insert validation with
     NSValidationMissingMandatoryPropertyError (1570), since the value
     only exists after the first save (community-documented Apple
     behavior; the fix on Apple is a default in awakeFromInsert).

   Not asserted, deliberately: whether manually setting a derived
   attribute raises (unverified on Apple).

   Verified on macOS (2026-08): Apple only implements derived attributes
   in the SQLite store (via triggers); adding an XML or in-memory store
   whose model contains one raises NSInvalidArgumentException "Core Data
   provided atomic stores do not support derived properties".  The
   port's store-agnostic engine supports every store type as a
   deliberate superset, so the XML/in-memory tests are GNUstep-only. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#include <string.h>

@interface NSDerivedAttributeTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;

@end

/* ------------------------------------------------------------------ */
#pragma mark - Model construction
/* ------------------------------------------------------------------ */

static NSAttributeDescription *stringAttribute(NSString *name)
{
    NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
    [attribute setName:name];
    [attribute setAttributeType:NSStringAttributeType];
    [attribute setOptional:YES];
    return attribute;
}

static NSDerivedAttributeDescription *derivedAttribute(NSString *name,
                                                       NSAttributeType type,
                                                       NSExpression *expression)
{
    NSDerivedAttributeDescription *attribute =
        [[NSDerivedAttributeDescription alloc] init];
    [attribute setName:name];
    [attribute setAttributeType:type];
    [attribute setOptional:YES];
    [attribute setDerivationExpression:expression];
    return attribute;
}

/* canonical: is not one of Foundation's predefined functions, so Apple
   only accepts it through the format parser; GNUstep-base's format
   parser does not know it, but the port makes expressionForFunction:
   accept it. */
static NSExpression *canonicalExpression(NSString *keyPath)
{
#if defined(__APPLE__)
    return [NSExpression expressionWithFormat:
        [NSString stringWithFormat:@"canonical:(%@)", keyPath]];
#else
    return [NSExpression expressionForFunction:@"canonical:"
                                     arguments:[NSArray arrayWithObject:
        [NSExpression expressionForKeyPath:keyPath]]];
#endif
}

/* Author(name, articles ->> Article; derived: nameCopy = name,
   nameCanonical = canonical:(name), articlesCount = articles.@count,
   totalWords = articles.wordCount.@sum, updatedAt = now()) and
   Article(title, wordCount, author -> Author; derived:
   titleUpper = uppercase:(title), authorName = author.name). */
static NSManagedObjectModel *derivedModel(BOOL countIsOptional)
{
    NSAttributeDescription *authorName = stringAttribute(@"name");

    NSDerivedAttributeDescription *nameCopy =
        derivedAttribute(@"nameCopy", NSStringAttributeType,
                         [NSExpression expressionForKeyPath:@"name"]);
    NSDerivedAttributeDescription *nameCanonical =
        derivedAttribute(@"nameCanonical", NSStringAttributeType,
                         canonicalExpression(@"name"));
    NSDerivedAttributeDescription *articlesCount =
        derivedAttribute(@"articlesCount", NSInteger64AttributeType,
                         [NSExpression expressionForKeyPath:@"articles.@count"]);
    [articlesCount setOptional:countIsOptional];
    NSDerivedAttributeDescription *totalWords =
        derivedAttribute(@"totalWords", NSInteger64AttributeType,
                         [NSExpression expressionForKeyPath:
                                           @"articles.wordCount.@sum"]);
    NSDerivedAttributeDescription *updatedAt =
        derivedAttribute(@"updatedAt", NSDateAttributeType,
                         [NSExpression expressionForFunction:@"now"
                                                   arguments:[NSArray array]]);

    NSAttributeDescription *title = stringAttribute(@"title");

    NSAttributeDescription *wordCount = [[NSAttributeDescription alloc] init];
    [wordCount setName:@"wordCount"];
    [wordCount setAttributeType:NSInteger32AttributeType];
    [wordCount setOptional:YES];

    NSDerivedAttributeDescription *titleUpper =
        derivedAttribute(@"titleUpper", NSStringAttributeType,
                         [NSExpression expressionForFunction:@"uppercase:"
                                                   arguments:[NSArray arrayWithObject:
                             [NSExpression expressionForKeyPath:@"title"]]]);
    NSDerivedAttributeDescription *authorNameCopy =
        derivedAttribute(@"authorName", NSStringAttributeType,
                         [NSExpression expressionForKeyPath:@"author.name"]);

    NSRelationshipDescription *articles =
        [[NSRelationshipDescription alloc] init];
    [articles setName:@"articles"];
    [articles setMinCount:0];
    [articles setMaxCount:0];
    [articles setOptional:YES];

    NSRelationshipDescription *author = [[NSRelationshipDescription alloc] init];
    [author setName:@"author"];
    [author setMinCount:1];
    [author setMaxCount:1];
    [author setOptional:YES];

    NSEntityDescription *authorEntity = [[NSEntityDescription alloc] init];
    [authorEntity setName:@"Author"];
    [authorEntity setManagedObjectClassName:@"NSManagedObject"];

    NSEntityDescription *articleEntity = [[NSEntityDescription alloc] init];
    [articleEntity setName:@"Article"];
    [articleEntity setManagedObjectClassName:@"NSManagedObject"];

    [articles setDestinationEntity:articleEntity];
    [articles setInverseRelationship:author];
    [author setDestinationEntity:authorEntity];
    [author setInverseRelationship:articles];

    [authorEntity setProperties:[NSArray arrayWithObjects:authorName,
        nameCopy, nameCanonical, articlesCount, totalWords, updatedAt,
        articles, nil]];
    [articleEntity setProperties:[NSArray arrayWithObjects:title, wordCount,
        titleUpper, authorNameCopy, author, nil]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:
        [NSArray arrayWithObjects:authorEntity, articleEntity, nil]];
    return model;
}

@implementation NSDerivedAttributeTests

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

- (NSManagedObjectContext *)contextWithModel:(NSManagedObjectModel *)model
                                   storeType:(NSString *)storeType
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:storeType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to add %@ store: %@", storeType, error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

- (NSManagedObject *)insertAuthorNamed:(NSString *)name
                             inContext:(NSManagedObjectContext *)ctx
{
    NSManagedObject *author =
        [NSEntityDescription insertNewObjectForEntityForName:@"Author"
                                      inManagedObjectContext:ctx];
    [author setValue:name forKey:@"name"];
    return author;
}

- (NSManagedObject *)insertArticleTitled:(NSString *)title
                                   words:(int)words
                                  author:(NSManagedObject *)author
                               inContext:(NSManagedObjectContext *)ctx
{
    NSManagedObject *article =
        [NSEntityDescription insertNewObjectForEntityForName:@"Article"
                                      inManagedObjectContext:ctx];
    [article setValue:title forKey:@"title"];
    [article setValue:[NSNumber numberWithInt:words] forKey:@"wordCount"];
    [article setValue:author forKey:@"author"];
    return article;
}

- (void)saveContext:(NSManagedObjectContext *)ctx
{
    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
}

/* Save, then refresh - the state in which Apple documents derived
   values as visible. */
- (void)saveContext:(NSManagedObjectContext *)ctx
     refreshObjects:(NSArray *)objects
{
    [self saveContext:ctx];
    for (NSManagedObject *object in objects)
        [ctx refreshObject:object mergeChanges:NO];
}

- (NSArray *)fetchEntityNamed:(NSString *)entityName
                    inContext:(NSManagedObjectContext *)ctx
                    predicate:(NSPredicate *)predicate
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:entityName
                                 inManagedObjectContext:ctx]];
    [fetch setPredicate:predicate];

    NSError *error = nil;
    NSArray *result = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    return result;
}

/* ------------------------------------------------------------------ */
#pragma mark - API
/* ------------------------------------------------------------------ */

- (void)testDerivedAttributeDescriptionAPI
{
    NSDerivedAttributeDescription *attribute =
        [[NSDerivedAttributeDescription alloc] init];

    XCTAssertTrue([attribute isKindOfClass:[NSAttributeDescription class]],
                  @"a derived attribute is an attribute");
    XCTAssertNil([attribute derivationExpression]);

    NSExpression *expression = [NSExpression expressionForKeyPath:@"name"];
    [attribute setDerivationExpression:expression];
    XCTAssertEqualObjects([[attribute derivationExpression] keyPath], @"name");

    /* Derived attributes appear in the entity's properties like any
       other attribute. */
    NSManagedObjectModel *model = derivedModel(YES);
    NSEntityDescription *author =
        [[model entitiesByName] objectForKey:@"Author"];
    XCTAssertTrue([[[author propertiesByName] objectForKey:@"articlesCount"]
                      isKindOfClass:[NSDerivedAttributeDescription class]]);
    XCTAssertNotNil([[[author attributesByName] objectForKey:@"updatedAt"]
                        versionHash]);
}

/* ------------------------------------------------------------------ */
#pragma mark - Copies and string transforms
/* ------------------------------------------------------------------ */

- (void)testCopyAndStringTransformDerivations
{
    NSManagedObjectContext *ctx = [self contextWithModel:derivedModel(YES)
                                               storeType:NSSQLiteStoreType];
    NSManagedObject *author = [self insertAuthorNamed:@"Héllo Wörld"
                                            inContext:ctx];
    NSManagedObject *article = [self insertArticleTitled:@"Grand Café"
                                                   words:12
                                                  author:author
                                               inContext:ctx];

    [self saveContext:ctx refreshObjects:
        [NSArray arrayWithObjects:author, article, nil]];

    /* Same-table copy (a stored generated column in the SQLite store). */
    XCTAssertEqualObjects([author valueForKey:@"nameCopy"], @"Héllo Wörld");

    /* canonical: is the case- and diacritic-insensitive representation. */
    XCTAssertEqualObjects([author valueForKey:@"nameCanonical"],
                          @"hello world");

    /* uppercase: uses full Unicode semantics, not ASCII-only. */
    XCTAssertEqualObjects([article valueForKey:@"titleUpper"], @"GRAND CAFÉ");

    /* Copy across a to-one relationship. */
    XCTAssertEqualObjects([article valueForKey:@"authorName"],
                          @"Héllo Wörld");
}

/* ------------------------------------------------------------------ */
#pragma mark - Aggregates
/* ------------------------------------------------------------------ */

- (void)testAggregateDerivationsRecomputeOnSave
{
    NSManagedObjectContext *ctx = [self contextWithModel:derivedModel(YES)
                                               storeType:NSSQLiteStoreType];
    NSManagedObject *author = [self insertAuthorNamed:@"Alice" inContext:ctx];

    [self insertArticleTitled:@"one" words:10 author:author inContext:ctx];
    [self insertArticleTitled:@"two" words:32 author:author inContext:ctx];

    [self saveContext:ctx refreshObjects:[NSArray arrayWithObject:author]];
    XCTAssertEqual([[author valueForKey:@"articlesCount"] longLongValue],
                   (long long)2);
    XCTAssertEqual([[author valueForKey:@"totalWords"] longLongValue],
                   (long long)42);

    /* Adding to the relationship updates the aggregates at the next
       save, because the owning object is itself marked updated. */
    NSManagedObject *third = [self insertArticleTitled:@"three"
                                                 words:8
                                                author:author
                                             inContext:ctx];
    [self saveContext:ctx refreshObjects:[NSArray arrayWithObject:author]];
    XCTAssertEqual([[author valueForKey:@"articlesCount"] longLongValue],
                   (long long)3);
    XCTAssertEqual([[author valueForKey:@"totalWords"] longLongValue],
                   (long long)50);

    /* So does deleting a related object. */
    [ctx deleteObject:third];
    [self saveContext:ctx refreshObjects:[NSArray arrayWithObject:author]];
    XCTAssertEqual([[author valueForKey:@"articlesCount"] longLongValue],
                   (long long)2);
    XCTAssertEqual([[author valueForKey:@"totalWords"] longLongValue],
                   (long long)42);
}

/* ------------------------------------------------------------------ */
#pragma mark - now()
/* ------------------------------------------------------------------ */

- (void)testNowDerivationTracksSaves
{
    NSManagedObjectContext *ctx = [self contextWithModel:derivedModel(YES)
                                               storeType:NSSQLiteStoreType];
    NSManagedObject *author = [self insertAuthorNamed:@"Alice" inContext:ctx];

    [self saveContext:ctx refreshObjects:[NSArray arrayWithObject:author]];

    NSDate *firstSave = [author valueForKey:@"updatedAt"];
    XCTAssertNotNil(firstSave);
    XCTAssertTrue(fabs([firstSave timeIntervalSinceNow]) < 30.0,
                  @"updatedAt should be the save time, got %@", firstSave);

    [NSThread sleepForTimeInterval:1.1];

    /* Saving the object again moves the timestamp forward. */
    [author setValue:@"Alicia" forKey:@"name"];
    [self saveContext:ctx refreshObjects:[NSArray arrayWithObject:author]];

    NSDate *secondSave = [author valueForKey:@"updatedAt"];
    XCTAssertTrue([secondSave timeIntervalSinceDate:firstSave] > 0.5,
                  @"updatedAt %@ should be later than %@",
                  secondSave, firstSave);
}

/* ------------------------------------------------------------------ */
#pragma mark - Visibility and persistence
/* ------------------------------------------------------------------ */

- (void)testDerivedValueRequiresSaveToExist
{
    NSManagedObjectContext *ctx = [self contextWithModel:derivedModel(YES)
                                               storeType:NSSQLiteStoreType];
    NSManagedObject *author = [self insertAuthorNamed:@"Alice" inContext:ctx];

    [self insertArticleTitled:@"one" words:10 author:author inContext:ctx];

    /* Before the first save there is nothing derived yet. */
    XCTAssertNil([author valueForKey:@"articlesCount"]);
    XCTAssertNil([author valueForKey:@"updatedAt"]);

    /* (What is visible between save and refresh is deliberately not
       asserted: Apple documents the property as stale until the object
       is refreshed, while this port may already show the new value.) */
    [self saveContext:ctx refreshObjects:[NSArray arrayWithObject:author]];
    XCTAssertEqual([[author valueForKey:@"articlesCount"] longLongValue],
                   (long long)1);
}

- (void)testDerivedValuesPersistAndAreQueryable
{
    NSManagedObject *author=nil;
    {
        NSManagedObjectContext *ctx =
            [self contextWithModel:derivedModel(YES)
                         storeType:NSSQLiteStoreType];
        author = [self insertAuthorNamed:@"Héllo Wörld" inContext:ctx];
        [self insertArticleTitled:@"one" words:10 author:author inContext:ctx];
        [self insertArticleTitled:@"two" words:32 author:author inContext:ctx];
        [self saveContext:ctx];
    }

    /* A fresh stack sees the derived values without recomputation, and
       - the point of derived attributes - fetch predicates can compare
       them inside the store. */
    NSManagedObjectContext *ctx2 = [self contextWithModel:derivedModel(YES)
                                                storeType:NSSQLiteStoreType];

    NSArray *byCount = [self fetchEntityNamed:@"Author"
                                    inContext:ctx2
                                    predicate:[NSPredicate predicateWithFormat:
                                                  @"articlesCount == 2"]];
    XCTAssertEqual([byCount count], (NSUInteger)1);
    XCTAssertEqualObjects([[byCount lastObject] valueForKey:@"name"],
                          @"Héllo Wörld");

    /* Case- and diacritic-insensitive search against the canonical
       column. */
    NSArray *byCanonical = [self fetchEntityNamed:@"Author"
                                        inContext:ctx2
                                        predicate:[NSPredicate predicateWithFormat:
                                                      @"nameCanonical == %@",
                                                      @"hello world"]];
    XCTAssertEqual([byCanonical count], (NSUInteger)1);

    NSArray *bySum = [self fetchEntityNamed:@"Author"
                                  inContext:ctx2
                                  predicate:[NSPredicate predicateWithFormat:
                                                @"totalWords == 42"]];
    XCTAssertEqual([bySum count], (NSUInteger)1);
}

/* ------------------------------------------------------------------ */
#pragma mark - Validation
/* ------------------------------------------------------------------ */

- (void)testNonOptionalDerivedAttributeFailsInsertValidation
{
    /* The derived value only exists once the object has been saved, so
       a non-optional derived attribute cannot pass insert validation
       (Apple fails with NSValidationMissingMandatoryPropertyError; the
       usual fix is a placeholder default set in awakeFromInsert). */
    NSManagedObjectContext *ctx = [self contextWithModel:derivedModel(NO)
                                               storeType:NSSQLiteStoreType];
    [self insertAuthorNamed:@"Alice" inContext:ctx];

    NSError *error = nil;
    XCTAssertFalse([ctx save:&error]);
    XCTAssertEqual([error code],
                   (NSInteger)NSValidationMissingMandatoryPropertyError);
}

#if !defined(__APPLE__)
- (void)testIntermediateOperatorIsRejectedWhenAddingStore
{
    /* Apple rejects "articles.@sum.wordCount" ("The derivation
       expression key path uses an operator as an intermediate
       component"); the operator must be terminal, as in
       "articles.wordCount.@sum".  The port reports this when a store is
       added.  GNUstep-only until the exact Apple failure mode (error vs
       exception, and when) is verified on macOS. */
    NSAttributeDescription *name = stringAttribute(@"name");
    NSDerivedAttributeDescription *invalid =
        derivedAttribute(@"badSum", NSInteger64AttributeType,
                         [NSExpression expressionForKeyPath:
                                           @"articles.@sum.wordCount"]);

    NSEntityDescription *author = [[NSEntityDescription alloc] init];
    [author setName:@"Author"];
    [author setManagedObjectClassName:@"NSManagedObject"];
    [author setProperties:[NSArray arrayWithObjects:name, invalid, nil]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:author]];

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNil(store);
    XCTAssertNotNil(error);
    XCTAssertTrue([[error localizedDescription]
                      rangeOfString:@"intermediate"].location != NSNotFound,
                  @"unexpected error: %@", error);
}

- (void)testSameTableCopyUsesGeneratedColumn
{
    /* The port declares same-table plain copies as SQLite stored
       generated columns (GNUstep-only: Apple implements derived
       attributes with triggers instead). */
    NSManagedObjectContext *ctx = [self contextWithModel:derivedModel(YES)
                                               storeType:NSSQLiteStoreType];
    [self insertAuthorNamed:@"Alice" inContext:ctx];
    [self saveContext:ctx];

    NSData *file = [NSData dataWithContentsOfFile:[self.storeURL path]];
    const char *needle = "GENERATED ALWAYS AS";
    NSData *needleData = [NSData dataWithBytes:needle length:strlen(needle)];
    XCTAssertTrue([file rangeOfData:needleData
                            options:0
                              range:NSMakeRange(0, [file length])].location
                      != NSNotFound,
                  @"expected a generated column in the schema");
}
#endif

/* ------------------------------------------------------------------ */
#pragma mark - Other store types
/* ------------------------------------------------------------------ */

/* The port computes derived values with one shared engine for every
   store type - a deliberate superset of Apple, whose atomic stores
   raise NSInvalidArgumentException "Core Data provided atomic stores do
   not support derived properties" when the store is added (verified on
   macOS 2026-08).  These two tests are therefore GNUstep-only. */

#if !defined(__APPLE__)
- (void)testDerivationsInXMLStore
{
    NSManagedObject *author=nil;
    {
        NSManagedObjectContext *ctx = [self contextWithModel:derivedModel(YES)
                                                   storeType:NSXMLStoreType];
        author = [self insertAuthorNamed:@"Héllo Wörld" inContext:ctx];
        [self insertArticleTitled:@"one" words:10 author:author inContext:ctx];
        [self saveContext:ctx refreshObjects:[NSArray arrayWithObject:author]];

        XCTAssertEqualObjects([author valueForKey:@"nameCanonical"],
                              @"hello world");
        XCTAssertEqual([[author valueForKey:@"articlesCount"] longLongValue],
                       (long long)1);
    }

    /* And the values round-trip through the file. */
    NSManagedObjectContext *ctx2 = [self contextWithModel:derivedModel(YES)
                                                storeType:NSXMLStoreType];
    NSArray *authors = [self fetchEntityNamed:@"Author"
                                    inContext:ctx2
                                    predicate:nil];
    XCTAssertEqual([authors count], (NSUInteger)1);
    XCTAssertEqualObjects([[authors lastObject] valueForKey:@"nameCopy"],
                          @"Héllo Wörld");
    XCTAssertEqual([[[authors lastObject] valueForKey:@"articlesCount"]
                       longLongValue],
                   (long long)1);
}

- (void)testDerivationsInInMemoryStore
{
    NSManagedObjectContext *ctx = [self contextWithModel:derivedModel(YES)
                                               storeType:NSInMemoryStoreType];
    NSManagedObject *author = [self insertAuthorNamed:@"Héllo Wörld"
                                            inContext:ctx];
    [self insertArticleTitled:@"one" words:10 author:author inContext:ctx];

    [self saveContext:ctx refreshObjects:[NSArray arrayWithObject:author]];

    XCTAssertEqualObjects([author valueForKey:@"nameCanonical"],
                          @"hello world");
    XCTAssertEqual([[author valueForKey:@"articlesCount"] longLongValue],
                   (long long)1);
    XCTAssertNotNil([author valueForKey:@"updatedAt"]);
}
#endif

@end
