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
    if ([predicate respondsToSelector:@selector(allowEvaluation)]) {
        // required on MacOS, not implemented on GNUstep
        [predicate allowEvaluation];
    }
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

@end
