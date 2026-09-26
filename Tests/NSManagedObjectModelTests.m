/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSManagedObjectModelTests - basic NSManagedObjectModel tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

@interface NSManagedObjectModelTests : XCTestCase
@end

@implementation NSManagedObjectModelTests

- (void)testModelCreation
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    XCTAssertNotNil(model);
    XCTAssertNotNil([model entities]);
}

/* Article.author <-> Author.articles, with the given names for the Author
   entity and its to-many relationship. */
static NSManagedObjectModel *MBTAuthorArticleModel(NSString *authorName,
                                                   NSString *articlesName,
                                                   NSEntityDescription **authorOut,
                                                   NSRelationshipDescription **articlesOut)
{
    NSEntityDescription *author = [[NSEntityDescription alloc] init];
    author.name = authorName;
    NSEntityDescription *article = [[NSEntityDescription alloc] init];
    article.name = @"Article";
    NSRelationshipDescription *articles = [[NSRelationshipDescription alloc] init];
    articles.name = articlesName;
    articles.destinationEntity = article;
    articles.maxCount = 0;
    NSRelationshipDescription *writer = [[NSRelationshipDescription alloc] init];
    writer.name = @"author";
    writer.destinationEntity = author;
    writer.maxCount = 1;
    articles.inverseRelationship = writer;
    writer.inverseRelationship = articles;
    author.properties = @[ articles ];
    article.properties = @[ writer ];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ author, article ];
    if (authorOut) *authorOut = author;
    if (articlesOut) *articlesOut = articles;
    return model;
}

/* Renaming a relationship's destination entity or its inverse leaves the
   relationship describing the new names: the version hashes are those of
   a model built with the new names, and an archive round trip resolves to
   them.  (The port cached the names, unretained, when the links were set:
   stale after a rename, and read after the old string was freed.) */
- (void)testRenamingRelatedEntityAndInverseKeepsRelationshipsCurrent
{
    NSEntityDescription *author = nil;
    NSRelationshipDescription *articles = nil;
    NSManagedObjectModel *model = MBTAuthorArticleModel(@"Author", @"articles",
                                                        &author, &articles);
    (void)[model entityVersionHashesByName];

    author.name = @"Writer";
    articles.name = @"writings";

    NSManagedObjectModel *expected = MBTAuthorArticleModel(@"Writer", @"writings", NULL, NULL);
    XCTAssertEqualObjects([model entityVersionHashesByName],
                          [expected entityVersionHashesByName]);

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:model];
    NSManagedObjectModel *copy = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    NSEntityDescription *article2 = copy.entitiesByName[@"Article"];
    NSRelationshipDescription *author2 = article2.relationshipsByName[@"author"];
    XCTAssertEqualObjects(author2.destinationEntity.name, @"Writer");
    XCTAssertEqualObjects(author2.inverseRelationship.name, @"writings");
}

/* An entity knows its model, and one renamed after it joined the model is
   found under the new name -- Apple re-keys the model. */
- (void)testRenamingEntityRekeysModel
{
    NSEntityDescription *author = [[NSEntityDescription alloc] init];
    author.name = @"Author";
    NSEntityDescription *article = [[NSEntityDescription alloc] init];
    article.name = @"Article";
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ author, article ];
    (void)model.entitiesByName;
    XCTAssertEqual(author.managedObjectModel, model);

    author.name = @"Writer";

    XCTAssertEqual(model.entitiesByName[@"Writer"], author);
    XCTAssertNil(model.entitiesByName[@"Author"]);
    XCTAssertEqual(model.entitiesByName[@"Article"], article);
    XCTAssertEqual(model.entitiesByName.count, (NSUInteger)2);
}

/* A new entity answers with empty collections, as on Apple, so a property
   appended to a fresh entity's properties is kept. */
- (void)testNewEntityHasEmptyCollections
{
    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    XCTAssertNotNil(entity.properties);
    XCTAssertEqual(entity.properties.count, (NSUInteger)0);
    XCTAssertNotNil(entity.propertiesByName);
    XCTAssertNotNil(entity.subentities);
    XCTAssertNotNil(entity.userInfo);
    XCTAssertNotNil(entity.uniquenessConstraints);

    NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
    attribute.name = @"attribute";
    attribute.attributeType = NSStringAttributeType;
    entity.properties = [entity.properties arrayByAddingObject:attribute];
    XCTAssertEqual(entity.properties.count, (NSUInteger)1);
    XCTAssertEqual(entity.propertiesByName[@"attribute"], attribute);
}

/* A property renamed after it joined its entity is found under the new
   name, and no longer under the old one -- Apple re-keys the entity. */
- (void)testRenamingPropertyRekeysEntity
{
    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    entity.name = @"Thing";
    NSAttributeDescription *first = [[NSAttributeDescription alloc] init];
    first.name = @"attribute";
    first.attributeType = NSStringAttributeType;
    NSAttributeDescription *second = [[NSAttributeDescription alloc] init];
    second.name = @"attribute2";
    second.attributeType = NSStringAttributeType;
    entity.properties = @[ first, second ];
    (void)entity.propertiesByName;

    second.name = @"attribute3";

    XCTAssertEqual(entity.propertiesByName[@"attribute3"], second);
    XCTAssertEqual(entity.attributesByName[@"attribute3"], second);
    XCTAssertNil(entity.propertiesByName[@"attribute2"]);
    XCTAssertEqual(entity.propertiesByName[@"attribute"], first);
    XCTAssertEqual(entity.propertiesByName.count, (NSUInteger)2);
}

- (void)testModelMergeEmpty
{
    NSManagedObjectModel *model =
        [NSManagedObjectModel modelByMergingModels:[NSArray array]];
    XCTAssertNotNil(model);
    XCTAssertEqual([[model entities] count], (NSUInteger)0);
}

- (void)testFetchRequestTemplate
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:@"MyEntity"];
    [model setEntities:[NSArray arrayWithObject:entity]];
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setEntity:entity];
    [model setFetchRequestTemplate:req forName:@"myTemplate"];
    XCTAssertEqualObjects([model fetchRequestTemplateForName:@"myTemplate"], req);
}

- (void)testConfigurations
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    XCTAssertNotNil([model configurations]);
}

- (void)testRelationshipIsToManyKeysOffMaxCount
{
    NSRelationshipDescription *relationship =
        [[NSRelationshipDescription alloc] init];

    /* To-one: a maximum count of one, regardless of the minimum count. */
    [relationship setMinCount:1];
    [relationship setMaxCount:1];
    XCTAssertFalse([relationship isToMany]);

    /* An optional to-one relationship is still to-one. */
    [relationship setMinCount:0];
    [relationship setMaxCount:1];
    XCTAssertFalse([relationship isToMany]);

    /* To-many: a maximum count of zero (unbounded) or greater than one. */
    [relationship setMinCount:0];
    [relationship setMaxCount:0];
    XCTAssertTrue([relationship isToMany]);

    [relationship setMinCount:1];
    [relationship setMaxCount:5];
    XCTAssertTrue([relationship isToMany]);
}

/* A model equivalent to a compiled .xcdatamodel: an abstract parent with a
   concrete subentity, mandatory/optional/transient attributes, a validation
   predicate and an inverse relationship pair. */
- (NSManagedObjectModel *)makeArchivableModel
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];
    [name setOptional:NO];

    NSAttributeDescription *note = [[NSAttributeDescription alloc] init];
    [note setName:@"note"];
    [note setAttributeType:NSStringAttributeType];
    [note setOptional:YES];
    [note setTransient:YES];

    NSAttributeDescription *amount = [[NSAttributeDescription alloc] init];
    [amount setName:@"amount"];
    [amount setAttributeType:NSInteger32AttributeType];
    [amount setOptional:NO];
    [amount setValidationPredicates:
        [NSArray arrayWithObject:[NSPredicate predicateWithFormat:@"NOT (SELF < 0)"]]
        withValidationWarnings:
        [NSArray arrayWithObject:@"amount must not be negative"]];

    NSRelationshipDescription *group = [[NSRelationshipDescription alloc] init];
    [group setName:@"group"];
    [group setMinCount:0];
    [group setMaxCount:1];
    [group setOptional:YES];
    [group setDeleteRule:NSNullifyDeleteRule];

    NSRelationshipDescription *items = [[NSRelationshipDescription alloc] init];
    [items setName:@"items"];
    [items setMinCount:0];
    [items setMaxCount:0];
    [items setOptional:YES];
    [items setDeleteRule:NSNullifyDeleteRule];

    NSEntityDescription *parent = [[NSEntityDescription alloc] init];
    [parent setName:@"Parent"];
    [parent setAbstract:YES];
    [parent setProperties:[NSArray arrayWithObject:name]];

    NSEntityDescription *item = [[NSEntityDescription alloc] init];
    [item setName:@"Item"];
    [item setProperties:[NSArray arrayWithObjects:note, amount, group, nil]];

    [parent setSubentities:[NSArray arrayWithObject:item]];

    NSEntityDescription *groupEntity = [[NSEntityDescription alloc] init];
    [groupEntity setName:@"Group"];
    [groupEntity setProperties:[NSArray arrayWithObject:items]];

    [group setDestinationEntity:groupEntity];
    [items setDestinationEntity:item];
    [group setInverseRelationship:items];
    [items setInverseRelationship:group];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObjects:parent, item, groupEntity, nil]];

    return model;
}

- (void)verifyDecodedModel:(NSManagedObjectModel *)decoded
{
    XCTAssertNotNil(decoded);

    NSEntityDescription *parent = [[decoded entitiesByName] objectForKey:@"Parent"];
    NSEntityDescription *item = [[decoded entitiesByName] objectForKey:@"Item"];
    NSEntityDescription *groupEntity = [[decoded entitiesByName] objectForKey:@"Group"];

    XCTAssertNotNil(parent);
    XCTAssertNotNil(item);
    XCTAssertNotNil(groupEntity);

    XCTAssertTrue([parent isAbstract]);
    XCTAssertFalse([item isAbstract]);
    XCTAssertEqualObjects([item superentity], parent);

    NSAttributeDescription *name = [[item propertiesByName] objectForKey:@"name"];
    XCTAssertNotNil(name);
    XCTAssertFalse([name isOptional]);
    XCTAssertFalse([name isTransient]);
    XCTAssertEqual([name attributeType], NSStringAttributeType);

    NSAttributeDescription *note = [[item propertiesByName] objectForKey:@"note"];
    XCTAssertNotNil(note);
    XCTAssertTrue([note isOptional]);
    XCTAssertTrue([note isTransient]);

    NSAttributeDescription *amount = [[item propertiesByName] objectForKey:@"amount"];
    XCTAssertNotNil(amount);
    XCTAssertEqual([amount attributeType], NSInteger32AttributeType);
    XCTAssertEqual([[amount validationPredicates] count], (NSUInteger)1);
    XCTAssertEqualObjects([[amount validationWarnings] lastObject],
                          @"amount must not be negative");

    NSPredicate *predicate = [[amount validationPredicates] lastObject];
#if !GNUSTEP
    // required on MacOS, not implemented on GNUstep
    [predicate allowEvaluation];
#endif
    XCTAssertTrue([predicate evaluateWithObject:[NSNumber numberWithInt:0]]);
    XCTAssertFalse([predicate evaluateWithObject:[NSNumber numberWithInt:-1]]);

    NSRelationshipDescription *group = [[item propertiesByName] objectForKey:@"group"];
    NSRelationshipDescription *items = [[groupEntity propertiesByName] objectForKey:@"items"];
    XCTAssertNotNil(group);
    XCTAssertNotNil(items);
    XCTAssertFalse([group isToMany]);
    XCTAssertTrue([items isToMany]);
    XCTAssertEqualObjects([group destinationEntity], groupEntity);
    XCTAssertEqualObjects([items destinationEntity], item);
    XCTAssertEqualObjects([group inverseRelationship], items);
    XCTAssertEqualObjects([items inverseRelationship], group);
    XCTAssertEqual([group deleteRule], NSNullifyDeleteRule);
}

- (void)testModelKeyedArchivingRoundTrip
{
    NSManagedObjectModel *model = [self makeArchivableModel];

    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver =
        [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:model forKey:@"root"];
    [archiver finishEncoding];

    XCTAssertTrue([data length] > 0);

    NSKeyedUnarchiver *unarchiver =
        [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    NSManagedObjectModel *decoded = [unarchiver decodeObjectForKey:@"root"];

    [self verifyDecodedModel:decoded];
}

- (void)testModelLoadsFromMomdBundle
{
    NSManagedObjectModel *model = [self makeArchivableModel];

    NSString *momdPath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"ModelTests.momd"];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    [fileManager removeItemAtPath:momdPath error:NULL];
    XCTAssertTrue([fileManager createDirectoryAtPath:momdPath
                              withIntermediateDirectories:YES
                              attributes:nil
                              error:NULL]);

    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver =
        [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:model forKey:@"root"];
    [archiver finishEncoding];

    XCTAssertTrue([data writeToFile:
        [momdPath stringByAppendingPathComponent:@"ModelTests.mom"] atomically:YES]);

    NSDictionary *versionInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        @"ModelTests", @"NSManagedObjectModel_CurrentVersionName", nil];
    XCTAssertTrue([versionInfo writeToFile:
        [momdPath stringByAppendingPathComponent:@"VersionInfo.plist"] atomically:YES]);

    NSManagedObjectModel *loaded = [[NSManagedObjectModel alloc]
        initWithContentsOfURL:[NSURL fileURLWithPath:momdPath]];

    [self verifyDecodedModel:loaded];

    [fileManager removeItemAtPath:momdPath error:NULL];
}

/* What Apple actually guarantees about -properties order: NOTHING.
   The arbitration run on macOS returned dictionary hash order (input
   zeta/alpha/middle/beta came back alpha/zeta/middle/beta), not
   setProperties: order - Apple stores a dictionary internally, and
   Xcode's own generator preserves editing order only because it works
   from its editor document, not from NSEntityDescription.  So the
   shared assertions here are the invariants both platforms hold: the
   set of properties, hash invariance under reordering, and order
   stability across an archive round trip.  The port additionally
   promises insertion order (its deterministic instance of
   "unspecified", carried through archives by GSPropertyOrder) - those
   assertions are port-only. */
- (void)testPropertiesPreserveTheirOrder
{
    /* deliberately non-alphabetical */
    NSArray *names = [NSArray arrayWithObjects:
        @"zeta", @"alpha", @"middle", @"beta", nil];
    NSMutableArray *properties = [NSMutableArray array];
    for (NSString *name in names) {
        NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
        [attribute setName:name];
        [attribute setAttributeType:NSStringAttributeType];
        [attribute setOptional:YES];
        [properties addObject:attribute];
    }

    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:@"Ordered"];
    [entity setManagedObjectClassName:@"NSManagedObject"];
    [entity setProperties:properties];

    XCTAssertEqualObjects(
        [NSSet setWithArray:[[entity properties] valueForKey:@"name"]],
        [NSSet setWithArray:names],
        @"every property is present, whatever the order");
#if !defined(__APPLE__)
    XCTAssertEqualObjects([[entity properties] valueForKey:@"name"], names,
                          @"port guarantee: -properties returns setProperties: order");
#endif

    /* reordering must not disturb the version hash (macOS-verified) */
    NSData *hashBefore = [entity versionHash];
    NSMutableArray *reversed = [NSMutableArray array];
    for (NSPropertyDescription *property in
             [[entity properties] reverseObjectEnumerator])
        [reversed addObject:property];
    [entity setProperties:reversed];
    XCTAssertEqualObjects([entity versionHash], hashBefore,
                          @"property order is not part of the version hash");
    [entity setProperties:properties];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:entity]];

    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver =
        [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:model forKey:@"root"];
    [archiver finishEncoding];

    NSKeyedUnarchiver *unarchiver =
        [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    NSManagedObjectModel *decoded = [unarchiver decodeObjectForKey:@"root"];
    NSEntityDescription *decodedEntity =
        [[decoded entitiesByName] objectForKey:@"Ordered"];

    XCTAssertEqualObjects([[decodedEntity properties] valueForKey:@"name"],
                          [[entity properties] valueForKey:@"name"],
                          @"whatever the order is, an archive round trip keeps it");
#if !defined(__APPLE__)
    XCTAssertEqualObjects([[decodedEntity properties] valueForKey:@"name"], names,
                          @"port guarantee: insertion order survives the archive "
                          @"(GSPropertyOrder)");
#endif
}

- (void)testUniquenessConstraintsStorageAndVersionHash
{
    NSAttributeDescription *code = [[NSAttributeDescription alloc] init];
    [code setName:@"code"];
    [code setAttributeType:NSStringAttributeType];

    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:@"Thing"];
    [entity setProperties:[NSArray arrayWithObject:code]];

    /* Default: an empty array, not nil, matching Apple. */
    XCTAssertEqualObjects([entity uniquenessConstraints], [NSArray array]);

    NSData *hashWithout = [entity versionHash];

    NSArray *constraints = [NSArray arrayWithObject:
        [NSArray arrayWithObject:@"code"]];
    [entity setUniquenessConstraints:constraints];
    XCTAssertEqualObjects([entity uniquenessConstraints], constraints);

    /* Matching Apple: "This value forms part of the entity's version
       hash." */
    XCTAssertNotEqualObjects([entity versionHash], hashWithout);

    [entity setCompoundIndexes:constraints];
#if defined(__APPLE__)
    /* Verified on macOS: the deprecated setter is a no-op there and the
       getter stays an empty array. */
    XCTAssertEqualObjects([entity compoundIndexes], [NSArray array]);
#else
    /* The port keeps the stored value for callers of the old API. */
    XCTAssertEqualObjects([entity compoundIndexes], constraints);
#endif
}

/* A model with what a copy has to carry: an inverse pair, a sub-entity,
   userInfo, a configuration, a fetch request template, version
   identifiers. */
static NSManagedObjectModel *CopyableModel(void)
{
    NSEntityDescription *department = [[NSEntityDescription alloc] init];
    [department setName:@"Department"];
    NSEntityDescription *employee = [[NSEntityDescription alloc] init];
    [employee setName:@"Employee"];
    NSEntityDescription *manager = [[NSEntityDescription alloc] init];
    [manager setName:@"Manager"];
    [employee setSubentities:@[ manager ]];

    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];
    [name setOptional:YES];
    [name setUserInfo:@{ @"key": @"value" }];
    NSRelationshipDescription *works = [[NSRelationshipDescription alloc] init];
    [works setName:@"department"];
    [works setDestinationEntity:department];
    [works setMaxCount:1];
    [works setOptional:YES];
    NSRelationshipDescription *staff = [[NSRelationshipDescription alloc] init];
    [staff setName:@"employees"];
    [staff setDestinationEntity:employee];
    [staff setMaxCount:0];
    [staff setOptional:YES];
    [works setInverseRelationship:staff];
    [staff setInverseRelationship:works];
    [employee setProperties:@[ name, works ]];
    [department setProperties:@[ staff ]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ department, employee, manager ]];
    [model setVersionIdentifiers:[NSSet setWithObject:@"7"]];
    [model setEntities:@[ employee ] forConfiguration:@"Staff"];
    NSFetchRequest *template = [[NSFetchRequest alloc] init];
    [template setEntity:employee];
    [template setPredicate:[NSPredicate predicateWithFormat:@"name == $NAME"]];
    [model setFetchRequestTemplate:template forName:@"ByName"];
    return model;
}

- (void)testCopyIsDeepAndPointsIntoItself
{
    /* Apple's model conforms to NSCopying, and its copy is deep: new
       entities and properties, each referring to the copy's. */
    NSManagedObjectModel *model = CopyableModel();
    XCTAssertTrue([model conformsToProtocol:@protocol(NSCopying)]);
    NSManagedObjectModel *copy = [model copy];
    XCTAssertNotNil(copy);
    XCTAssertTrue(copy != model);

    NSEntityDescription *employee = [[copy entitiesByName] objectForKey:@"Employee"];
    NSEntityDescription *department = [[copy entitiesByName] objectForKey:@"Department"];
    NSEntityDescription *manager = [[copy entitiesByName] objectForKey:@"Manager"];
    XCTAssertEqual([[copy entities] count], (NSUInteger)3);
    XCTAssertTrue(employee != [[model entitiesByName] objectForKey:@"Employee"]);
    XCTAssertTrue([employee managedObjectModel] == copy);

    NSRelationshipDescription *works = [[employee relationshipsByName] objectForKey:@"department"];
    XCTAssertTrue([works destinationEntity] == department);
    XCTAssertTrue([works inverseRelationship] == [[department relationshipsByName] objectForKey:@"employees"]);
    XCTAssertTrue([[employee subentities] firstObject] == manager);
    XCTAssertTrue([manager superentity] == employee);

    NSAttributeDescription *name = [[employee attributesByName] objectForKey:@"name"];
    XCTAssertTrue(name != [[[[model entitiesByName] objectForKey:@"Employee"] attributesByName] objectForKey:@"name"]);
    XCTAssertEqualObjects([name userInfo], @{ @"key": @"value" });

    XCTAssertEqualObjects([copy versionIdentifiers], [NSSet setWithObject:@"7"]);
    XCTAssertEqualObjects([[copy entitiesForConfiguration:@"Staff"] valueForKey:@"name"], @[ @"Employee" ]);
    NSFetchRequest *template = [copy fetchRequestTemplateForName:@"ByName"];
    XCTAssertEqualObjects([[template predicate] predicateFormat],
                          [[[model fetchRequestTemplateForName:@"ByName"] predicate] predicateFormat]);
    XCTAssertTrue([template entity] == employee);
    XCTAssertEqualObjects([copy entityVersionHashesByName], [model entityVersionHashesByName]);
}

- (void)testCopyOfAModelInUseCanBeEdited
{
    /* A model a coordinator uses can no longer be changed; its copy can,
       and changing the copy leaves the original as it was. */
    NSManagedObjectModel *model = CopyableModel();
    NSPersistentStoreCoordinator *coordinator =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType
                                              configuration:nil
                                                        URL:nil
                                                    options:nil
                                                      error:&error], @"%@", error);

    NSManagedObjectModel *copy = [model copy];
    NSEntityDescription *employee = [[copy entitiesByName] objectForKey:@"Employee"];
    XCTAssertNoThrow([employee setManagedObjectClassName:@"MBTEmployee"]);
    XCTAssertEqualObjects([employee managedObjectClassName], @"MBTEmployee");
    XCTAssertEqualObjects([[[model entitiesByName] objectForKey:@"Employee"] managedObjectClassName],
                          @"NSManagedObject");
}

- (void)testCopyServesAStore
{
    NSManagedObjectModel *copy = [CopyableModel() copy];
    NSPersistentStoreCoordinator *coordinator =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:copy];
    NSError *error = nil;
    XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType
                                              configuration:nil
                                                        URL:nil
                                                    options:nil
                                                      error:&error], @"%@", error);
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [context setPersistentStoreCoordinator:coordinator];
    NSManagedObject *sales = [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                                           inManagedObjectContext:context];
    NSManagedObject *ann = [NSEntityDescription insertNewObjectForEntityForName:@"Manager"
                                                         inManagedObjectContext:context];
    [ann setValue:@"Ann" forKey:@"name"];
    [ann setValue:sales forKey:@"department"];
    XCTAssertTrue([context save:&error], @"%@", error);
    XCTAssertEqualObjects([[sales valueForKey:@"employees"] valueForKey:@"name"], [NSSet setWithObject:@"Ann"]);
}

/* Employee, and Manager under it, with a shadowed property and an
   inherited relationship. */
static NSArray *InheritanceEntities(void)
{
    NSEntityDescription *employee = [[NSEntityDescription alloc] init];
    [employee setName:@"Employee"];
    NSEntityDescription *manager = [[NSEntityDescription alloc] init];
    [manager setName:@"Manager"];
    NSEntityDescription *department = [[NSEntityDescription alloc] init];
    [department setName:@"Department"];

    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];
    NSAttributeDescription *title = [[NSAttributeDescription alloc] init];
    [title setName:@"title"];
    [title setAttributeType:NSStringAttributeType];
    NSAttributeDescription *managerTitle = [[NSAttributeDescription alloc] init];
    [managerTitle setName:@"title"];
    [managerTitle setAttributeType:NSStringAttributeType];
    NSAttributeDescription *budget = [[NSAttributeDescription alloc] init];
    [budget setName:@"budget"];
    [budget setAttributeType:NSDecimalAttributeType];
    NSRelationshipDescription *works = [[NSRelationshipDescription alloc] init];
    [works setName:@"department"];
    [works setDestinationEntity:department];
    [works setMaxCount:1];
    NSRelationshipDescription *staff = [[NSRelationshipDescription alloc] init];
    [staff setName:@"staff"];
    [staff setDestinationEntity:employee];
    [staff setMaxCount:0];
    [works setInverseRelationship:staff];
    [staff setInverseRelationship:works];

    [employee setProperties:@[ name, title, works ]];
    [manager setProperties:@[ budget, managerTitle ]];
    [department setProperties:@[ staff ]];
    [employee setSubentities:@[ manager ]];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ employee, manager, department ]];
    return @[ employee, manager, department, model ];
}

- (void)testSubentityPropertiesIncludeWhatItInherits
{
    /* Apple's -properties of a subentity includes its superentity's, each
       once: a property the subentity declares again shadows the inherited
       one. The order is unspecified. */
    NSArray *entities = InheritanceEntities();
    NSEntityDescription *manager = entities[1];
    NSArray *names = [[manager properties] valueForKey:@"name"];
    XCTAssertEqualObjects([NSSet setWithArray:names], ([NSSet setWithObjects:@"budget", @"title", @"name", @"department", nil]));
    XCTAssertEqual([names count], (NSUInteger)4, @"each once");
    XCTAssertEqual([[manager properties] count], [[manager propertiesByName] count]);
    XCTAssertEqualObjects([NSSet setWithArray:[[entities[0] properties] valueForKey:@"name"]],
                          ([NSSet setWithObjects:@"name", @"title", @"department", nil]), @"a superentity is unchanged");
}

- (void)testIsKindOfEntity
{
    NSArray *entities = InheritanceEntities();
    NSEntityDescription *employee = entities[0], *manager = entities[1], *department = entities[2];
    XCTAssertTrue([manager isKindOfEntity:employee]);
    XCTAssertTrue([manager isKindOfEntity:manager]);
    XCTAssertFalse([employee isKindOfEntity:manager]);
    XCTAssertFalse([manager isKindOfEntity:department]);
}

- (void)testRelationshipsToADestinationIncludeInheritedOnes
{
    /* By destination: the relationships that lead to Department. */
    NSArray *entities = InheritanceEntities();
    XCTAssertEqualObjects([[entities[1] relationshipsWithDestinationEntity:entities[2]] valueForKey:@"name"], @[ @"department" ]);
    XCTAssertEqualObjects([[entities[2] relationshipsWithDestinationEntity:entities[0]] valueForKey:@"name"], @[ @"staff" ]);
    XCTAssertEqualObjects([entities[2] relationshipsWithDestinationEntity:entities[2]], @[]);
}

@end
