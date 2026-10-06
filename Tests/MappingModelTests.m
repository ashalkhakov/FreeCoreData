/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* MappingModelTests - inferred mapping model tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"
#import "CDMappingCompiler.h"
#import "CDMappingSerializer.h"

@interface MappingModelTests : XCTestCase
@end

@implementation MappingModelTests

- (void)testInferredMappingModel
{
    NSError *error = nil;
    NSMappingModel *mapping = [NSMappingModel
        inferredMappingModelForSourceModel:VersioningTestModelV1()
                          destinationModel:VersioningTestModelV2()
                                     error:&error];
    XCTAssertNotNil(mapping);

    NSDictionary *byName = [mapping entityMappingsByName];
    XCTAssertEqual([[mapping entityMappings] count], (NSUInteger)2);

    NSEntityMapping *employee = [byName objectForKey:@"IEM_Transform_Employee"];
    XCTAssertNotNil(employee);
    XCTAssertEqual([employee mappingType],
                   (NSEntityMappingType)NSTransformEntityMappingType);
    /* Every destination attribute gets a mapping: name, salary and title. */
    XCTAssertEqual([[employee attributeMappings] count], (NSUInteger)3);
    XCTAssertEqual([[employee relationshipMappings] count], (NSUInteger)1);

    NSEntityMapping *department = [byName objectForKey:@"IEM_Copy_Department"];
    XCTAssertNotNil(department);
    XCTAssertEqual([department mappingType],
                   (NSEntityMappingType)NSCopyEntityMappingType);
}

/* A mapping model is a keyed archive of its entity mappings, their
   property mappings and the expressions in them - the shape Core Data
   writes, down to the keys, so that what one framework writes the other
   reads.  (What Xcode's own compiler puts in a .cdm is not checked here:
   a mapping model can only be authored in its editor.) */
- (void)testAMappingModelRoundTripsThroughAnArchive
{
    NSPropertyMapping *textMapping = [[NSPropertyMapping alloc] init];
    [textMapping setName:@"text"];
    [textMapping setValueExpression:[NSExpression expressionWithFormat:@"$source.text"]];

    NSEntityMapping *notes = [[NSEntityMapping alloc] init];
    [notes setName:@"KeepSome"];
    [notes setMappingType:NSTransformEntityMappingType];
    [notes setSourceEntityName:@"Note"];
    [notes setDestinationEntityName:@"Note"];
    [notes setAttributeMappings:[NSArray arrayWithObject:textMapping]];
    [notes setSourceExpression:[NSExpression expressionWithFormat:
        @"FETCH(FUNCTION($manager, 'fetchRequestForSourceEntityNamed:predicateString:', 'Note', 'TRUEPREDICATE'), FUNCTION($manager, 'sourceContext'), NO)"]];

    NSMappingModel *mapping = [[NSMappingModel alloc] init];
    [mapping setEntityMappings:[NSArray arrayWithObject:notes]];

    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:mapping];
    NSMappingModel *read = [NSKeyedUnarchiver unarchiveObjectWithData:archive];

    XCTAssertEqual([[read entityMappings] count], (NSUInteger)1);

    NSEntityMapping *readNotes = [[read entityMappings] lastObject];

    XCTAssertEqualObjects([readNotes name], @"KeepSome");
    XCTAssertEqual([readNotes mappingType], (NSEntityMappingType)NSTransformEntityMappingType);
    XCTAssertEqualObjects([readNotes sourceEntityName], @"Note");
    NSUInteger readType = [[readNotes sourceExpression] expressionType];

    XCTAssertEqual(readType, (NSUInteger)NSFetchRequestExpressionType);
    XCTAssertEqualObjects([[[readNotes attributeMappings] lastObject] name], @"text");
}

/* The mapping model in the bundle was authored in Xcode's editor and
   compiled with its mapc: MappingFixture.xcdatamodeld's two versions, and
   between them a NoteToNote mapping whose source expression fetches only
   the notes whose text begins with "keep", an attribute mapping that puts
   the old author in the new writer, relationship mappings that go through
   the migration manager, and an Add mapping for an entity that is new in
   the second version.

   So this is the whole of it: a mapping model this port never wrote,
   read and then followed. */
- (NSManagedObjectModel *)fixtureModelNamed:(NSString *)version
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSURL *momd = [bundle URLForResource:@"MappingFixture" withExtension:@"momd"];

    XCTAssertNotNil(momd, @"MappingFixture.momd missing from the test bundle");

    NSURL *mom = [momd URLByAppendingPathComponent:
        [version stringByAppendingPathExtension:@"mom"]];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:mom];

    XCTAssertNotNil(model, @"%@ missing from MappingFixture.momd", version);
    return model;
}

/* And the same mapping model compiled here rather than by Xcode: the
   source says which entity maps to which, the predicate that narrows a
   mapping, and the one value expression written by hand; everything else -
   the kind of each mapping, the version hashes, the expressions nobody
   wrote - is worked out from the two models.  The two compilers should
   agree, so the test is run twice over the same assertions.

   Only where the source is at hand: Xcode's build compiles it rather than
   copying it, so on macOS the bundle holds the compiled one alone. */
- (NSMappingModel *)fixtureMappingCompiledHere
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *source = [[bundle resourcePath]
        stringByAppendingPathComponent:@"MappingFixture.xcmappingmodel"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:source])
        return nil;

    NSError *error = nil;
    NSMappingModel *mapping = [CDMappingCompiler
        mappingModelAtPath:source
               sourceModel:[self fixtureModelNamed:@"MappingFixture"]
          destinationModel:[self fixtureModelNamed:@"MappingFixture 2"]
                     error:&error];

    XCTAssertNotNil(mapping, @"compiling %@: %@", source, error);
    return mapping;
}

/* Written back out as a mapping model's source and compiled again: what
   an author chose survives the trip - which entity maps to which, the
   predicate that narrows one, and the one expression written by hand -
   and what the compiler works out for itself is worked out again.
   (Xcode's editor opens such a file: that is what the source form is
   for.) */
- (void)testAMappingModelWrittenHereCompilesBackToWhatItWas
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSMappingModel *original = [[NSMappingModel alloc] initWithContentsOfURL:
        [bundle URLForResource:@"MappingFixture" withExtension:@"cdm"]];

    XCTAssertNotNil(original);

    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *source = [directory stringByAppendingPathComponent:@"Written.xcmappingmodel"];
    NSError *error = nil;

    XCTAssertTrue([CDMappingSerializer writeMappingModel:original
                                                  toPath:source
                                         sourceModelPath:@"MappingFixture.xcdatamodeld/MappingFixture.xcdatamodel"
                                    destinationModelPath:@"MappingFixture.xcdatamodeld/MappingFixture 2.xcdatamodel"
                                                   error:&error],
                  @"write: %@", error);

    NSMappingModel *again = [CDMappingCompiler
        mappingModelAtPath:source
               sourceModel:[self fixtureModelNamed:@"MappingFixture"]
          destinationModel:[self fixtureModelNamed:@"MappingFixture 2"]
                     error:&error];

    XCTAssertNotNil(again, @"compile: %@", error);
    XCTAssertEqual([[again entityMappings] count], [[original entityMappings] count]);

    NSDictionary *byName = [again entityMappingsByName];

    for (NSEntityMapping *was in [original entityMappings]) {
        NSEntityMapping *is = [byName objectForKey:[was name]];

        XCTAssertNotNil(is, @"%@ came back", [was name]);
        XCTAssertEqual([is mappingType], [was mappingType], @"%@", [was name]);
        XCTAssertEqualObjects([is sourceEntityName], [was sourceEntityName], @"%@", [was name]);
        XCTAssertEqualObjects([is destinationEntityName], [was destinationEntityName], @"%@", [was name]);
        XCTAssertEqual([[is attributeMappings] count], [[was attributeMappings] count], @"%@", [was name]);
        XCTAssertEqual([[is relationshipMappings] count], [[was relationshipMappings] count], @"%@", [was name]);
    }

    /* The predicate an author wrote is the one thing a source file keeps
       that nothing else could put back. */
    NSExpression *fetch = [[byName objectForKey:@"NoteToNote"] sourceExpression];
    NSExpression *request = [(NSFetchRequestExpression *)fetch requestExpression];

    XCTAssertEqualObjects([[[request arguments] lastObject] constantValue],
                          @"text BEGINSWITH \"keep\"");

    /* And it still migrates the same way. */
    [self migrateWithMappingModel:again];

    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* What Xcode's inspector lets an author set, beyond expressions: a mapping's
   own name and policy class, user info on a mapping and on its properties,
   and the key path and mapping a relationship is filled through.  Each
   survives a write and a compile, and the relationship is filled through
   the renamed mapping. */
- (void)testWhatTheInspectorSetsSurvivesAWrite
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSMappingModel *original = [[NSMappingModel alloc] initWithContentsOfURL:
        [bundle URLForResource:@"MappingFixture" withExtension:@"cdm"]];
    NSEntityMapping *tags = [[original entityMappingsByName] objectForKey:@"TagToTag"];
    NSEntityMapping *notes = [[original entityMappingsByName] objectForKey:@"NoteToNote"];

    XCTAssertNotNil(tags);
    XCTAssertNotNil(notes);

    [tags setName:@"CarryTags"];
    [tags setEntityMigrationPolicyClassName:@"NSEntityMigrationPolicy"];
    [tags setUserInfo:@{ @"why": @"renamed" }];

    for (NSPropertyMapping *property in [notes relationshipMappings])
        if ([[property name] isEqualToString:@"tags"]) {
            [property setValueExpression:[CDMappingCompiler valueExpressionForRelationshipKeyPath:@"tags"
                                                                                   throughMapping:@"CarryTags"]];
            [property setUserInfo:@{ @"note": @"through CarryTags" }];
        }

    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *source = [directory stringByAppendingPathComponent:@"Inspected.xcmappingmodel"];
    NSError *error = nil;

    XCTAssertTrue([CDMappingSerializer writeMappingModel:original
                                                  toPath:source
                                         sourceModelPath:@"MappingFixture.xcdatamodeld/MappingFixture.xcdatamodel"
                                    destinationModelPath:@"MappingFixture.xcdatamodeld/MappingFixture 2.xcdatamodel"
                                                   error:&error],
                  @"write: %@", error);

    NSMappingModel *again = [CDMappingCompiler
        mappingModelAtPath:source
               sourceModel:[self fixtureModelNamed:@"MappingFixture"]
          destinationModel:[self fixtureModelNamed:@"MappingFixture 2"]
                     error:&error];

    XCTAssertNotNil(again, @"compile: %@", error);

    NSEntityMapping *carried = [[again entityMappingsByName] objectForKey:@"CarryTags"];

    XCTAssertNotNil(carried, @"the mapping keeps its name");
    XCTAssertEqualObjects([carried entityMigrationPolicyClassName], @"NSEntityMigrationPolicy");
    XCTAssertEqualObjects([carried userInfo], @{ @"why": @"renamed" });

    NSPropertyMapping *filled = nil;

    for (NSPropertyMapping *property in [[[again entityMappingsByName] objectForKey:@"NoteToNote"] relationshipMappings])
        if ([[property name] isEqualToString:@"tags"]) filled = property;

    NSString *mappingName = nil, *keyPath = nil;

    XCTAssertTrue([CDMappingSerializer relationshipExpression:[filled valueExpression]
                                                  mappingName:&mappingName
                                                      keyPath:&keyPath],
                  @"%@", [filled valueExpression]);
    XCTAssertEqualObjects(mappingName, @"CarryTags");
    XCTAssertEqualObjects(keyPath, @"tags");
    XCTAssertEqualObjects([filled userInfo], @{ @"note": @"through CarryTags" });

    /* And the notes still arrive with their tags. */
    [self migrateWithMappingModel:again];

    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

- (void)testTheMappingModelCompiledHereIsTheOneXcodeCompiled
{
    NSMappingModel *ours = [self fixtureMappingCompiledHere];

    if (ours == nil) return;

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSMappingModel *theirs = [[NSMappingModel alloc] initWithContentsOfURL:
        [bundle URLForResource:@"MappingFixture" withExtension:@"cdm"]];

    XCTAssertNotNil(theirs);
    XCTAssertEqual([[ours entityMappings] count], [[theirs entityMappings] count]);

    NSDictionary *oursByName = [ours entityMappingsByName];
    NSDictionary *theirsByName = [theirs entityMappingsByName];

    XCTAssertEqualObjects([[[oursByName allKeys] sortedArrayUsingSelector:@selector(compare:)]
                             componentsJoinedByString:@","],
                          [[[theirsByName allKeys] sortedArrayUsingSelector:@selector(compare:)]
                             componentsJoinedByString:@","],
                          @"the same mappings, under the same names");

    for (NSString *name in oursByName) {
        NSEntityMapping *mine = [oursByName objectForKey:name];
        NSEntityMapping *theirMapping = [theirsByName objectForKey:name];

        XCTAssertEqual([mine mappingType], [theirMapping mappingType], @"%@", name);
        XCTAssertEqualObjects([mine sourceEntityName], [theirMapping sourceEntityName], @"%@", name);
        XCTAssertEqualObjects([mine destinationEntityName], [theirMapping destinationEntityName], @"%@", name);
        XCTAssertEqual([[mine attributeMappings] count], [[theirMapping attributeMappings] count], @"%@", name);
        XCTAssertEqual([[mine relationshipMappings] count], [[theirMapping relationshipMappings] count], @"%@", name);
        XCTAssertEqual([mine sourceExpression] == nil, [theirMapping sourceExpression] == nil, @"%@", name);
    }
}

- (void)testAMappingModelMadeInXcodeIsReadAndFollowed
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSURL *cdm = [bundle URLForResource:@"MappingFixture" withExtension:@"cdm"];

    XCTAssertNotNil(cdm, @"MappingFixture.cdm missing from the test bundle");
    [self migrateWithMappingModel:[[NSMappingModel alloc] initWithContentsOfURL:cdm]];
}

/* The same migration, driven by the mapping model this project compiled. */
- (void)testAMappingModelCompiledHereIsFollowedTheSameWay
{
    NSMappingModel *ours = [self fixtureMappingCompiledHere];

    if (ours != nil)
        [self migrateWithMappingModel:ours];
}

- (void)migrateWithMappingModel:(NSMappingModel *)mapping
{
    NSError *error = nil;

    XCTAssertNotNil(mapping, @"a mapping model to migrate with");
    XCTAssertEqual([[mapping entityMappings] count], (NSUInteger)3);

    NSEntityMapping *notes = [[mapping entityMappingsByName] objectForKey:@"NoteToNote"];

    XCTAssertNotNil(notes, @"%@", [[mapping entityMappingsByName] allKeys]);
    XCTAssertEqual([notes mappingType], (NSEntityMappingType)NSTransformEntityMappingType);
    XCTAssertNotNil([notes sourceExpression], @"the mapping says what to fetch");

    /* An attribute that changed its name, and one entity added whole. */
    NSMutableDictionary *byDestination = [NSMutableDictionary dictionary];

    for (NSPropertyMapping *property in [notes attributeMappings])
        [byDestination setObject:property forKey:[property name]];

    XCTAssertNotNil([byDestination objectForKey:@"writer"]);
    XCTAssertNotNil([[byDestination objectForKey:@"writer"] valueExpression]);
    XCTAssertEqual([[[mapping entityMappingsByName] objectForKey:@"Fresh"] mappingType],
                   (NSEntityMappingType)NSAddEntityMappingType);

    /* Now migrate a store with it. */
    NSManagedObjectModel *v1 = [self fixtureModelNamed:@"MappingFixture"];
    NSManagedObjectModel *v2 = [self fixtureModelNamed:@"MappingFixture 2"];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[NSProcessInfo processInfo] globallyUniqueString]];

    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    NSURL *sourceURL = [NSURL fileURLWithPath:
        [directory stringByAppendingPathComponent:@"source.sqlite"]];
    NSPersistentStoreCoordinator *sourcePSC = [[NSPersistentStoreCoordinator alloc]
                                                  initWithManagedObjectModel:v1];

    XCTAssertNotNil([sourcePSC addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                                      URL:sourceURL options:nil error:&error],
                    @"open: %@", error);

    NSManagedObjectContext *sourceCtx = [[NSManagedObjectContext alloc] init];
    [sourceCtx setPersistentStoreCoordinator:sourcePSC];

    NSManagedObject *red = [NSEntityDescription insertNewObjectForEntityForName:@"Tag"
                                                        inManagedObjectContext:sourceCtx];
    [red setValue:@"red" forKey:@"label"];

    NSManagedObject *kept = [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                                         inManagedObjectContext:sourceCtx];
    [kept setValue:@"keep me" forKey:@"text"];
    [kept setValue:@"Ada" forKey:@"author"];
    [[kept mutableSetValueForKey:@"tags"] addObject:red];

    NSManagedObject *dropped = [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                                            inManagedObjectContext:sourceCtx];
    [dropped setValue:@"drop him" forKey:@"text"];
    [dropped setValue:@"Bob" forKey:@"author"];

    NSManagedObject *obsolete = [NSEntityDescription insertNewObjectForEntityForName:@"Obsolete"
                                                             inManagedObjectContext:sourceCtx];
    [obsolete setValue:@"junk" forKey:@"junk"];

    XCTAssertTrue([sourceCtx save:&error], @"save: %@", error);
    XCTAssertTrue([sourcePSC removePersistentStore:[[sourcePSC persistentStores] lastObject]
                                             error:&error], @"remove: %@", error);

    NSURL *destinationURL = [NSURL fileURLWithPath:
        [directory stringByAppendingPathComponent:@"destination.sqlite"]];
    NSMigrationManager *manager = [[NSMigrationManager alloc] initWithSourceModel:v1
                                                                destinationModel:v2];

    XCTAssertTrue([manager migrateStoreFromURL:sourceURL type:NSSQLiteStoreType options:nil
                              withMappingModel:mapping toDestinationURL:destinationURL
                               destinationType:NSSQLiteStoreType destinationOptions:nil
                                         error:&error], @"migrate: %@", error);
    [manager reset];

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
                                            initWithManagedObjectModel:v2];

    XCTAssertNotNil([psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                                URL:destinationURL options:nil error:&error],
                    @"open the migrated store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    /* The predicate in the mapping chose one of the two notes. */
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    NSArray *migrated = [ctx executeFetchRequest:fetch error:&error];

    XCTAssertEqual([migrated count], (NSUInteger)1,
                   @"only the note the source expression fetched: %@",
                   [migrated valueForKey:@"text"]);

    NSManagedObject *note = [migrated lastObject];

    XCTAssertEqualObjects([note valueForKey:@"text"], @"keep me");
    XCTAssertEqualObjects([note valueForKey:@"writer"], @"Ada",
                          @"the attribute mapping put the author in the writer");

    /* The relationship was rebuilt through the manager, both ways. */
    NSSet *tags = [note valueForKey:@"tags"];

    XCTAssertEqual([tags count], (NSUInteger)1, @"%@", tags);
    XCTAssertEqualObjects([[tags anyObject] valueForKey:@"label"], @"red");
    XCTAssertEqualObjects([[[[tags anyObject] valueForKey:@"notes"] anyObject] valueForKey:@"text"],
                          @"keep me", @"and the inverse came with it");

    /* The entity added in the second version is there, and empty; the one
       the second version drops has no mapping, so nothing of it came. */
    XCTAssertNotNil([[v2 entitiesByName] objectForKey:@"Fresh"]);
    XCTAssertEqual([ctx countForFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Fresh"]
                                       error:NULL], (NSUInteger)0);
    XCTAssertNil([[v2 entitiesByName] objectForKey:@"Obsolete"]);

    [psc removePersistentStore:[[psc persistentStores] lastObject] error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* A mapping model written in Xcode says which objects a mapping applies to
   in the mapping's source expression - a fetch request this manager builds,
   narrowed by a predicate, run against the source context.  That is how a
   mapping takes a subset of an entity, and ignoring it migrates everybody.

   The mapping model is built here rather than inferred: an inferred one
   describes a whole-store migration, and Apple's migration takes its own
   way through that whichever expressions it is given. */
- (void)testSourceExpressionChoosesWhatIsMigrated
{
    NSError *error = nil;
    NSAttributeDescription *(^textAttribute)(void) = ^NSAttributeDescription *(void) {
        NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
        [text setName:@"text"];
        [text setAttributeType:NSStringAttributeType];
        [text setOptional:YES];
        return text;
    };
    NSManagedObjectModel *(^noteModel)(void) = ^NSManagedObjectModel *(void) {
        NSEntityDescription *note = [[NSEntityDescription alloc] init];
        [note setName:@"Note"];
        [note setManagedObjectClassName:@"NSManagedObject"];
        [note setProperties:[NSArray arrayWithObject:textAttribute()]];
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
        [model setEntities:[NSArray arrayWithObject:note]];
        return model;
    };

    NSManagedObjectModel *sourceModel = noteModel();
    NSManagedObjectModel *destinationModel = noteModel();
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[NSProcessInfo processInfo] globallyUniqueString]];

    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    NSURL *sourceURL = [NSURL fileURLWithPath:
        [directory stringByAppendingPathComponent:@"source.sqlite"]];
    NSPersistentStoreCoordinator *sourcePSC = [[NSPersistentStoreCoordinator alloc]
                                                  initWithManagedObjectModel:sourceModel];

    XCTAssertNotNil([sourcePSC addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                                      URL:sourceURL options:nil error:&error],
                    @"open: %@", error);

    NSManagedObjectContext *sourceCtx = [[NSManagedObjectContext alloc] init];
    [sourceCtx setPersistentStoreCoordinator:sourcePSC];

    for (NSString *text in [NSArray arrayWithObjects:@"keep me", @"keep her", @"drop him", nil]) {
        NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                                             inManagedObjectContext:sourceCtx];
        [note setValue:text forKey:@"text"];
    }
    XCTAssertTrue([sourceCtx save:&error], @"save: %@", error);
    XCTAssertTrue([sourcePSC removePersistentStore:[[sourcePSC persistentStores] lastObject]
                                             error:&error], @"remove: %@", error);

    NSPropertyMapping *textMapping = [[NSPropertyMapping alloc] init];
    [textMapping setName:@"text"];
    [textMapping setValueExpression:[NSExpression expressionWithFormat:@"$source.text"]];

    NSEntityMapping *notes = [[NSEntityMapping alloc] init];
    [notes setName:@"KeepSome"];
    [notes setMappingType:NSTransformEntityMappingType];
    [notes setSourceEntityName:@"Note"];
    [notes setSourceEntityVersionHash:[[[sourceModel entitiesByName] objectForKey:@"Note"] versionHash]];
    [notes setDestinationEntityName:@"Note"];
    [notes setDestinationEntityVersionHash:[[[destinationModel entitiesByName] objectForKey:@"Note"] versionHash]];
    [notes setAttributeMappings:[NSArray arrayWithObject:textMapping]];
    [notes setSourceExpression:[NSExpression expressionWithFormat:
        @"FETCH(FUNCTION($manager, 'fetchRequestForSourceEntityNamed:predicateString:', 'Note', 'text BEGINSWITH \"keep\"'), FUNCTION($manager, 'sourceContext'), NO)"]];

    NSMappingModel *mapping = [[NSMappingModel alloc] init];
    [mapping setEntityMappings:[NSArray arrayWithObject:notes]];

    NSURL *destinationURL = [NSURL fileURLWithPath:
        [directory stringByAppendingPathComponent:@"destination.sqlite"]];
    NSMigrationManager *manager = [[NSMigrationManager alloc] initWithSourceModel:sourceModel
                                                                destinationModel:destinationModel];

    XCTAssertTrue([manager migrateStoreFromURL:sourceURL type:NSSQLiteStoreType options:nil
                              withMappingModel:mapping toDestinationURL:destinationURL
                               destinationType:NSSQLiteStoreType destinationOptions:nil
                                         error:&error], @"migrate: %@", error);
    [manager reset];

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
                                            initWithManagedObjectModel:destinationModel];

    XCTAssertNotNil([psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                                URL:destinationURL options:nil error:&error],
                    @"open the migrated store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]]];

    XCTAssertEqualObjects([[ctx executeFetchRequest:fetch error:&error] valueForKey:@"text"],
        ([NSArray arrayWithObjects:@"keep her", @"keep me", nil]),
        @"only what the source expression fetched: %@", error);

    [psc removePersistentStore:[[psc persistentStores] lastObject] error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

- (void)testInferredMappingModelAddsAndRemovesEntities
{
    NSEntityDescription *added = [[NSEntityDescription alloc] init];
    [added setName:@"Added"];
    NSManagedObjectModel *destination = [[NSManagedObjectModel alloc] init];
    [destination setEntities:[NSArray arrayWithObject:added]];

    NSEntityDescription *removed = [[NSEntityDescription alloc] init];
    [removed setName:@"Removed"];
    NSManagedObjectModel *source = [[NSManagedObjectModel alloc] init];
    [source setEntities:[NSArray arrayWithObject:removed]];

    NSError *error = nil;
    NSMappingModel *mapping = [NSMappingModel
        inferredMappingModelForSourceModel:source
                          destinationModel:destination
                                     error:&error];
    XCTAssertNotNil(mapping);
    XCTAssertEqual([[mapping entityMappings] count], (NSUInteger)2);

    for (NSEntityMapping *entityMapping in [mapping entityMappings]) {
        if ([[entityMapping destinationEntityName] isEqualToString:@"Added"])
            XCTAssertEqual([entityMapping mappingType],
                           (NSEntityMappingType)NSAddEntityMappingType);
        else
            XCTAssertEqual([entityMapping mappingType],
                           (NSEntityMappingType)NSRemoveEntityMappingType);
    }
}

@end
