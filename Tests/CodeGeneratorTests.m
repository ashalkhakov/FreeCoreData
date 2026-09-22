/* Tests for CDCodeGenerator: the Xcode-style Objective-C
   NSManagedObject subclass source generator.  String-level, so the
   same expectations run against Apple's description classes on macOS
   (the generator input) and the port's on GNUstep; the generated
   sources are additionally compile-tested against the built framework
   by the CI container.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "CDModelCompiler.h"
#import "CDCodeGenerator.h"

static NSString *const kCodegenModelXML = @""
"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
"<model type=\"com.apple.IDECoreDataModeler.DataModel\" documentVersion=\"1.0\" sourceLanguage=\"Objective-C\">\n"
"  <entity name=\"Author\" representedClassName=\"CDGAuthor\" codeGenerationType=\"class\" syncable=\"YES\">\n"
"    <attribute name=\"name\" attributeType=\"String\"/>\n"
"    <attribute name=\"age\" optional=\"YES\" attributeType=\"Integer 32\" usesScalarValueType=\"YES\"/>\n"
"    <attribute name=\"rating\" optional=\"YES\" attributeType=\"Double\"/>\n"
"    <attribute name=\"joined\" optional=\"YES\" attributeType=\"Date\" usesScalarValueType=\"YES\"/>\n"
"    <attribute name=\"payload\" optional=\"YES\" attributeType=\"Transformable\" valueTransformerName=\"NSSecureUnarchiveFromData\" customClassName=\"NSDictionary\"/>\n"
"    <relationship name=\"books\" optional=\"YES\" toMany=\"YES\" ordered=\"YES\" deletionRule=\"Cascade\" destinationEntity=\"Book\" inverseName=\"author\" inverseEntity=\"Book\"/>\n"
"    <relationship name=\"drafts\" optional=\"YES\" toMany=\"YES\" deletionRule=\"Nullify\" destinationEntity=\"Book\"/>\n"
"  </entity>\n"
"  <entity name=\"Book\" representedClassName=\"CDGBook\" codeGenerationType=\"category\" syncable=\"YES\">\n"
"    <attribute name=\"title\" attributeType=\"String\"/>\n"
"    <relationship name=\"author\" optional=\"YES\" maxCount=\"1\" deletionRule=\"Nullify\" destinationEntity=\"Author\" inverseName=\"books\" inverseEntity=\"Author\"/>\n"
"  </entity>\n"
"  <entity name=\"Novel\" representedClassName=\"CDGNovel\" parentEntity=\"Book\" codeGenerationType=\"class\" syncable=\"YES\">\n"
"    <attribute name=\"genre\" optional=\"YES\" attributeType=\"String\"/>\n"
"  </entity>\n"
"  <entity name=\"Unmarked\" representedClassName=\"CDGUnmarked\" syncable=\"YES\">\n"
"    <attribute name=\"x\" optional=\"YES\" attributeType=\"Integer 16\"/>\n"
"  </entity>\n"
"  <entity name=\"Plain\" representedClassName=\"NSManagedObject\" syncable=\"YES\">\n"
"    <attribute name=\"y\" optional=\"YES\" attributeType=\"String\"/>\n"
"  </entity>\n"
"</model>\n";

@interface CodeGeneratorTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;

@end

@implementation CodeGeneratorTests

- (void)setUp
{
    NSError *error = nil;
    self.model = [CDModelCompiler compileModelContentsXML:kCodegenModelXML
                                                    error:&error];
    XCTAssertNotNil(self.model, @"compile failed: %@", error);
}

- (NSEntityDescription *)entity:(NSString *)name
{
    return [[self.model entitiesByName] objectForKey:name];
}

- (void)testEligibilityFollowsClassAndMarking
{
    NSArray *marked = [CDCodeGenerator generatableEntitiesInModel:self.model
                                                       onlyMarked:YES];
    XCTAssertEqualObjects([marked valueForKey:@"name"],
                          (@[ @"Author", @"Book", @"Novel" ]),
                          @"marked entities only, sorted");
    NSArray *all = [CDCodeGenerator generatableEntitiesInModel:self.model
                                                    onlyMarked:NO];
    XCTAssertEqualObjects([all valueForKey:@"name"],
                          (@[ @"Author", @"Book", @"Novel", @"Unmarked" ]),
                          @"--all adds unmarked custom classes; never plain NSManagedObject");
}

- (void)testClassModeEmitsBothFilePairs
{
    NSDictionary *files = [CDCodeGenerator sourcesForEntity:[self entity:@"Author"]];
    NSArray *names = [[files allKeys] sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(names, (@[
        @"CDGAuthor+CoreDataClass.h", @"CDGAuthor+CoreDataClass.m",
        @"CDGAuthor+CoreDataProperties.h", @"CDGAuthor+CoreDataProperties.m" ]));

    NSString *classHeader = [files objectForKey:@"CDGAuthor+CoreDataClass.h"];
    XCTAssertTrue([classHeader containsString:@"@interface CDGAuthor : NSManagedObject"]);
    XCTAssertTrue([classHeader containsString:@"@class CDGBook, NSDictionary;"],
                  @"forwards on one comma-joined sorted line, Xcode-style "
                  @"(relationship destinations and transformable value classes)");
    XCTAssertTrue([classHeader containsString:
        @"#import \"CDGAuthor+CoreDataProperties.h\""],
                  @"Xcode's bottom import of the properties header");
}

- (void)testPropertyDeclarationsFollowXcodeSpellings
{
    NSDictionary *files = [CDCodeGenerator sourcesForEntity:[self entity:@"Author"]];
    NSString *h = [files objectForKey:@"CDGAuthor+CoreDataProperties.h"];

    XCTAssertTrue([h containsString:
        @"+ (NSFetchRequest<CDGAuthor *> *)fetchRequest NS_SWIFT_NAME(fetchRequest());"],
        @"NS_SWIFT_NAME on leaf entities, as Xcode emits");
    XCTAssertTrue([h containsString:
        @"@property (nullable, nonatomic, copy) NSString *name;"],
        @"object properties are always nullable, optional or not (Xcode parity)");
    XCTAssertTrue([h containsString:@"@property (nonatomic) int32_t age;"],
        @"usesScalarValueType turns the NSNumber into int32_t");
    XCTAssertTrue([h containsString:
        @"@property (nullable, nonatomic, copy) NSNumber *rating;"],
        @"unmarked numeric stays NSNumber");
    XCTAssertTrue([h containsString:@"@property (nonatomic) NSTimeInterval joined;"],
        @"scalar dates are NSTimeInterval");
    XCTAssertTrue([h containsString:
        @"@property (nullable, nonatomic, retain) NSDictionary *payload;"],
        @"transformable uses its custom value class, retained");
    XCTAssertTrue([h containsString:
        @"@property (nullable, nonatomic, retain) NSOrderedSet<CDGBook *> *books;"]);
    XCTAssertTrue([h containsString:
        @"@property (nullable, nonatomic, retain) NSSet<CDGBook *> *drafts;"]);

    /* the generated to-many accessors, unordered and ordered */
    XCTAssertTrue([h containsString:@"- (void)addDraftsObject:(CDGBook *)value;"]);
    XCTAssertTrue([h containsString:
        @"- (void)insertObject:(CDGBook *)value inBooksAtIndex:(NSUInteger)idx;"]);
    XCTAssertTrue([h containsString:
        @"- (void)replaceBooksAtIndexes:(NSIndexSet *)indexes withBooks:(NSArray<CDGBook *> *)values;"]);

    NSString *m = [files objectForKey:@"CDGAuthor+CoreDataProperties.m"];
    XCTAssertTrue([m containsString:
        @"return [NSFetchRequest fetchRequestWithEntityName:@\"Author\"];"],
        @"fetchRequest uses the ENTITY name, not the class name");
    XCTAssertTrue([m containsString:@"@dynamic books;"]);
}

- (void)testCategoryModeLeavesTheClassToItsAuthor
{
    NSDictionary *files = [CDCodeGenerator sourcesForEntity:[self entity:@"Book"]];
    NSArray *names = [[files allKeys] sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(names, (@[
        @"CDGBook+CoreDataProperties.h", @"CDGBook+CoreDataProperties.m" ]),
        @"category mode emits only the properties pair");

    NSString *h = [files objectForKey:@"CDGBook+CoreDataProperties.h"];
    XCTAssertTrue([h containsString:@"#import \"CDGBook.h\""],
                  @"the hand-written class header is imported");
    XCTAssertTrue([h containsString:@"@class CDGAuthor;"],
                  @"forwards move into the properties header in category mode");
    XCTAssertTrue([h containsString:
        @"+ (NSFetchRequest<CDGBook *> *)fetchRequest;"] &&
        ![h containsString:@"NS_SWIFT_NAME"],
        @"no NS_SWIFT_NAME on an entity with subentities (Swift collision)");
}

- (void)testSubclassImportsItsParentsGeneratedHeader
{
    NSDictionary *files = [CDCodeGenerator sourcesForEntity:[self entity:@"Novel"]];
    NSString *h = [files objectForKey:@"CDGNovel+CoreDataClass.h"];
    XCTAssertTrue([h containsString:@"@interface CDGNovel : CDGBook"]);
    XCTAssertTrue([h containsString:@"#import \"CDGBook.h\""],
                  @"category-mode parent means a hand-written parent header");
    XCTAssertFalse([h containsString:@"CoreData/CoreData.h"],
                   @"a subclass imports only Foundation and its parent's header");
}

- (void)testWritingCreatesTheDirectoryAndFiles
{
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"CDCodegenTests-%@",
         [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSError *error = nil;
    NSArray *entities = [CDCodeGenerator generatableEntitiesInModel:self.model
                                                         onlyMarked:YES];
    NSArray *written = [CDCodeGenerator writeSourcesForEntities:entities
                                                    toDirectory:dir
                                                          error:&error];
    XCTAssertNotNil(written, @"write failed: %@", error);
    XCTAssertEqual([written count], (NSUInteger)10,
                   @"4 (Author) + 2 (Book, category) + 4 (Novel)");
    for (NSString *filename in written)
        XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:
            [dir stringByAppendingPathComponent:filename]]);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
}

@end
