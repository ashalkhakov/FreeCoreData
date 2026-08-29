/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* MomcSerializerTests - CDModelSerializer round-trip.

   The serializer is CDModelCompiler's inverse and the foundation of the
   ModelBuilder editor's save path: compile(serialize(model)) must
   reproduce the model, and serialize must be deterministic.  The rich
   fixture below exercises every schema feature the pair supports:
   all attribute types with defaults, transformable metadata, derived
   attributes (function, key path, now()), transient, UUID/URI,
   relationships (to-one/to-many/ordered/min/max/delete rules/inverses),
   entity inheritance, abstract, versionHashModifier, uniqueness
   constraints, entity- and property-level userInfo, configurations,
   and fetch request templates with predicate and limit.

   These tests compile the SAME compiler/serializer sources on macOS
   against Apple CoreData, so the XML the editor writes stays loadable
   by Xcode's toolchain and vice versa. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"

static NSString *const kRichModelXML = @""
"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
"<model type=\"com.apple.IDECoreDataModeler.DataModel\" documentVersion=\"1.0\" sourceLanguage=\"Objective-C\">\n"
"  <entity name=\"Article\" representedClassName=\"NSManagedObject\" versionHashModifier=\"v2\" syncable=\"YES\">\n"
"    <attribute name=\"title\" attributeType=\"String\" defaultValueString=\"Untitled\"/>\n"
"    <attribute name=\"titleUpper\" optional=\"YES\" attributeType=\"String\" derived=\"YES\" derivationExpression=\"uppercase:(title)\"/>\n"
"    <attribute name=\"titleCopy\" optional=\"YES\" attributeType=\"String\" derived=\"YES\" derivationExpression=\"title\"/>\n"
"    <attribute name=\"stamp\" optional=\"YES\" attributeType=\"Date\" derived=\"YES\" derivationExpression=\"now()\"/>\n"
"    <attribute name=\"wordCount\" optional=\"YES\" attributeType=\"Integer 32\" defaultValueString=\"7\"/>\n"
"    <attribute name=\"rating\" optional=\"YES\" attributeType=\"Double\" defaultValueString=\"1.5\"/>\n"
"    <attribute name=\"price\" optional=\"YES\" attributeType=\"Decimal\" defaultValueString=\"9.99\"/>\n"
"    <attribute name=\"published\" optional=\"YES\" attributeType=\"Boolean\" defaultValueString=\"YES\"/>\n"
"    <attribute name=\"createdAt\" optional=\"YES\" attributeType=\"Date\" defaultDateTimeInterval=\"631152000\"/>\n"
"    <attribute name=\"externalID\" optional=\"YES\" attributeType=\"UUID\"/>\n"
"    <attribute name=\"homepage\" optional=\"YES\" attributeType=\"URI\"/>\n"
"    <attribute name=\"blob\" optional=\"YES\" attributeType=\"Binary\"/>\n"
"    <attribute name=\"payload\" optional=\"YES\" attributeType=\"Transformable\" valueTransformerName=\"NSSecureUnarchiveFromData\" customClassName=\"NSDictionary\"/>\n"
"    <attribute name=\"cached\" optional=\"YES\" transient=\"YES\" versionHashModifier=\"pv1\" attributeType=\"String\">\n"
"      <userInfo>\n"
"        <entry key=\"note\" value=\"per-property info\"/>\n"
"      </userInfo>\n"
"    </attribute>\n"
"    <relationship name=\"author\" optional=\"YES\" maxCount=\"1\" deletionRule=\"Nullify\" destinationEntity=\"Author\" inverseName=\"articles\" inverseEntity=\"Author\"/>\n"
"    <userInfo>\n"
"      <entry key=\"team\" value=\"docs\"/>\n"
"    </userInfo>\n"
"  </entity>\n"
"  <entity name=\"Author\" representedClassName=\"NSManagedObject\" syncable=\"YES\">\n"
"    <attribute name=\"name\" attributeType=\"String\"/>\n"
"    <relationship name=\"articles\" optional=\"YES\" toMany=\"YES\" ordered=\"YES\" minCount=\"1\" maxCount=\"12\" deletionRule=\"Cascade\" destinationEntity=\"Article\" inverseName=\"author\" inverseEntity=\"Article\">\n"
"      <userInfo>\n"
"        <entry key=\"hint\" value=\"ordered shelf\"/>\n"
"      </userInfo>\n"
"    </relationship>\n"
"    <relationship name=\"muse\" optional=\"YES\" transient=\"YES\" maxCount=\"1\" deletionRule=\"No Action\" destinationEntity=\"Author\"/>\n"
"    <uniquenessConstraints>\n"
"      <uniquenessConstraint>\n"
"        <constraint value=\"name\"/>\n"
"      </uniquenessConstraint>\n"
"    </uniquenessConstraints>\n"
"  </entity>\n"
"  <entity name=\"FeaturedArticle\" representedClassName=\"NSManagedObject\" parentEntity=\"Article\" syncable=\"YES\">\n"
"    <attribute name=\"badge\" optional=\"YES\" attributeType=\"String\"/>\n"
"  </entity>\n"
"  <entity name=\"Ghost\" representedClassName=\"NSManagedObject\" isAbstract=\"YES\" syncable=\"YES\">\n"
"    <attribute name=\"ectoplasm\" optional=\"YES\" attributeType=\"Float\" defaultValueString=\"0.5\"/>\n"
"  </entity>\n"
"  <configuration name=\"Publishing\">\n"
"    <memberEntity name=\"Article\"/>\n"
"    <memberEntity name=\"Author\"/>\n"
"    <memberEntity name=\"FeaturedArticle\"/>\n"
"  </configuration>\n"
"  <fetchRequest name=\"LongArticles\" entity=\"Article\" predicateString=\"wordCount &gt; 100\" fetchLimit=\"5\"/>\n"
"</model>\n";

@interface MomcSerializerTests : XCTestCase

@property (nonatomic, strong) NSString *scratchDir;

@end

@implementation MomcSerializerTests

- (void)setUp
{
    self.scratchDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"CDSerializerTests-%@", [[NSProcessInfo processInfo] globallyUniqueString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.scratchDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtPath:self.scratchDir error:NULL];
}

- (NSManagedObjectModel *)compileXML:(NSString *)xml named:(NSString *)name
{
    NSString *modelDir = [self.scratchDir stringByAppendingPathComponent:
        [name stringByAppendingPathExtension:@"xcdatamodel"]];
    [[NSFileManager defaultManager] createDirectoryAtPath:modelDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    NSError *error = nil;
    XCTAssertTrue([xml writeToFile:[modelDir stringByAppendingPathComponent:@"contents"]
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:&error], @"write failed: %@", error);
    NSManagedObjectModel *model = [CDModelCompiler compileModelAtPath:modelDir error:&error];
    XCTAssertNotNil(model, @"compile of %@ failed: %@", name, error);
    return model;
}

- (void)testRoundTripReproducesTheModel
{
    NSManagedObjectModel *original = [self compileXML:kRichModelXML named:@"original"];

    NSError *error = nil;
    NSString *serialized = [CDModelSerializer contentsXMLForModel:original error:&error];
    XCTAssertNotNil(serialized, @"serialize failed: %@", error);

    NSManagedObjectModel *reparsed = [self compileXML:serialized named:@"reparsed"];

    /* Same entity set. */
    NSArray *names = [[[original entitiesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(names,
        [[[reparsed entitiesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)]);

    /* The strongest single check: identical version hashes entity by
       entity - the hash digests names, types, defaults, relationship
       shapes, inheritance and constraints. */
    for (NSString *name in names) {
        NSEntityDescription *a = [[original entitiesByName] objectForKey:name];
        NSEntityDescription *b = [[reparsed entitiesByName] objectForKey:name];
        XCTAssertEqualObjects([a versionHash], [b versionHash],
                              @"version hash of %@ changed across round trip", name);
        XCTAssertEqual([a isAbstract], [b isAbstract]);
        XCTAssertEqualObjects([a versionHashModifier], [b versionHashModifier]);
        XCTAssertEqualObjects([[a superentity] name], [[b superentity] name]);
        XCTAssertEqualObjects([a userInfo], [b userInfo]);
        XCTAssertEqualObjects(
            [[[a propertiesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)],
            [[[b propertiesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)]);
    }

    /* Property details that the version hash may not digest. */
    NSEntityDescription *articleA = [[original entitiesByName] objectForKey:@"Article"];
    NSEntityDescription *articleB = [[reparsed entitiesByName] objectForKey:@"Article"];
    NSAttributeDescription *cachedB = [[articleB attributesByName] objectForKey:@"cached"];
    XCTAssertTrue([cachedB isTransient]);
    XCTAssertEqualObjects([cachedB versionHashModifier], @"pv1",
                          @"property-level versionHashModifier round-trips");
    XCTAssertEqualObjects([cachedB userInfo],
                          [[[articleA attributesByName] objectForKey:@"cached"] userInfo]);

    NSAttributeDescription *payloadB = [[articleB attributesByName] objectForKey:@"payload"];
    XCTAssertEqualObjects([payloadB valueTransformerName], @"NSSecureUnarchiveFromData");
    XCTAssertEqualObjects([payloadB attributeValueClassName], @"NSDictionary");

    NSAttributeDescription *titleB = [[articleB attributesByName] objectForKey:@"title"];
    XCTAssertEqualObjects([titleB defaultValue], @"Untitled");
    XCTAssertEqualObjects([[[articleB attributesByName] objectForKey:@"published"] defaultValue],
                          [NSNumber numberWithBool:YES]);
    XCTAssertEqualObjects([[[articleB attributesByName] objectForKey:@"createdAt"] defaultValue],
                          [NSDate dateWithTimeIntervalSinceReferenceDate:631152000]);

    NSEntityDescription *authorB = [[reparsed entitiesByName] objectForKey:@"Author"];
    NSRelationshipDescription *articlesB = [[authorB relationshipsByName] objectForKey:@"articles"];
    XCTAssertTrue([articlesB isToMany]);
    XCTAssertTrue([articlesB isOrdered]);
    XCTAssertEqual([articlesB minCount], (NSInteger)1);
    XCTAssertEqual([articlesB maxCount], (NSInteger)12);
    XCTAssertEqual([articlesB deleteRule], NSCascadeDeleteRule);
    XCTAssertEqualObjects([[articlesB destinationEntity] name], @"Article");
    XCTAssertEqualObjects([[articlesB inverseRelationship] name], @"author");
    XCTAssertEqualObjects([articlesB userInfo],
        [NSDictionary dictionaryWithObject:@"ordered shelf" forKey:@"hint"]);

    NSRelationshipDescription *museB = [[authorB relationshipsByName] objectForKey:@"muse"];
    XCTAssertTrue([museB isTransient]);
    XCTAssertEqual([museB deleteRule], NSNoActionDeleteRule);
    XCTAssertNil([museB inverseRelationship]);

    /* Derived attributes survive with their expressions. */
    NSDerivedAttributeDescription *upperB = (NSDerivedAttributeDescription *)
        [[articleB attributesByName] objectForKey:@"titleUpper"];
    XCTAssertTrue([upperB isKindOfClass:[NSDerivedAttributeDescription class]]);
    XCTAssertNotNil([upperB derivationExpression]);

    /* Constraints. */
    NSArray *constraints = [authorB uniquenessConstraints];
    XCTAssertEqual([constraints count], (NSUInteger)1);
    NSArray *firstConstraint = [constraints objectAtIndex:0];
    XCTAssertEqual([firstConstraint count], (NSUInteger)1);
    id member = [firstConstraint objectAtIndex:0];
    NSString *memberName =
        [member respondsToSelector:@selector(name)] ? [member name] : member;
    XCTAssertEqualObjects(memberName, @"name");

    /* Configurations. */
    XCTAssertEqualObjects(
        [[reparsed configurations] sortedArrayUsingSelector:@selector(compare:)],
        [[original configurations] sortedArrayUsingSelector:@selector(compare:)]);
    XCTAssertEqual([[reparsed entitiesForConfiguration:@"Publishing"] count], (NSUInteger)3);

    /* Fetch request templates. */
    NSFetchRequest *template = [reparsed fetchRequestTemplateForName:@"LongArticles"];
    XCTAssertNotNil(template);
    XCTAssertEqualObjects([[template entity] name], @"Article");
    XCTAssertEqual([template fetchLimit], (NSUInteger)5);
    XCTAssertEqualObjects(
        [[template predicate] predicateFormat],
        [[[original fetchRequestTemplateForName:@"LongArticles"] predicate] predicateFormat]);
}

/* serialize(compile(serialize(m))) == serialize(m): the output is
   deterministic and stable, so saving an unmodified document rewrites
   the identical file. */
- (void)testSerializationIsDeterministic
{
    NSManagedObjectModel *original = [self compileXML:kRichModelXML named:@"original"];

    NSError *error = nil;
    NSString *first = [CDModelSerializer contentsXMLForModel:original error:&error];
    XCTAssertNotNil(first, @"serialize failed: %@", error);

    NSManagedObjectModel *reparsed = [self compileXML:first named:@"reparsed"];
    NSString *second = [CDModelSerializer contentsXMLForModel:reparsed error:&error];
    XCTAssertNotNil(second, @"second serialize failed: %@", error);

    XCTAssertEqualObjects(first, second);
}

/* Layout geometry lands in the <elements> section and round-trips
   through a reparse of the written XML. */
- (void)testEntityLayoutsAreWritten
{
    NSManagedObjectModel *model = [self compileXML:kRichModelXML named:@"original"];
    NSDictionary *layouts = [NSDictionary dictionaryWithObject:
        [NSDictionary dictionaryWithObjectsAndKeys:
            @"10", @"positionX", @"-20", @"positionY",
            @"200", @"width", @"90", @"height", nil]
        forKey:@"Article"];

    NSError *error = nil;
    NSString *xml = [CDModelSerializer contentsXMLForModel:model
                                             entityLayouts:layouts
                                                     error:&error];
    XCTAssertNotNil(xml, @"serialize failed: %@", error);

    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:&error];
    XCTAssertNotNil(doc, @"reparse failed: %@", error);
    NSArray *elements = [[doc rootElement] elementsForName:@"elements"];
    XCTAssertEqual([elements count], (NSUInteger)1);

    BOOL found = NO;
    for (NSXMLElement *element in [[elements objectAtIndex:0] elementsForName:@"element"]) {
        if (![[[element attributeForName:@"name"] stringValue] isEqualToString:@"Article"])
            continue;
        found = YES;
        XCTAssertEqualObjects([[element attributeForName:@"positionX"] stringValue], @"10");
        XCTAssertEqualObjects([[element attributeForName:@"positionY"] stringValue], @"-20");
        XCTAssertEqualObjects([[element attributeForName:@"width"] stringValue], @"200");
        XCTAssertEqualObjects([[element attributeForName:@"height"] stringValue], @"90");
    }
    XCTAssertTrue(found);
}

@end
