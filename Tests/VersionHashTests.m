/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* VersionHashTests - entity/property version hash tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"

@interface VersionHashTests : XCTestCase
@end

@implementation VersionHashTests

- (void)testIdenticalModelsHaveEqualEntityVersionHashes
{
    NSManagedObjectModel *a = VersioningTestModelV1();
    NSManagedObjectModel *b = VersioningTestModelV1();
    NSDictionary *hashesA = [a entityVersionHashesByName];
    NSDictionary *hashesB = [b entityVersionHashesByName];
    XCTAssertEqual([hashesA count], (NSUInteger)2);
    XCTAssertEqualObjects(hashesA, hashesB);
}

- (void)testDifferentModelsHaveDifferentEntityVersionHashes
{
    NSDictionary *hashesV1 = [VersioningTestModelV1() entityVersionHashesByName];
    NSDictionary *hashesV2 = [VersioningTestModelV2() entityVersionHashesByName];
    XCTAssertNotEqualObjects([hashesV1 objectForKey:@"Employee"],
                             [hashesV2 objectForKey:@"Employee"]);
    /* Department is unchanged between the versions. */
    XCTAssertEqualObjects([hashesV1 objectForKey:@"Department"],
                          [hashesV2 objectForKey:@"Department"]);
}

- (void)testAttributeTypeAffectsVersionHash
{
    NSAttributeDescription *a = [[NSAttributeDescription alloc] init];
    [a setName:@"value"];
    [a setAttributeType:NSStringAttributeType];

    NSAttributeDescription *b = [[NSAttributeDescription alloc] init];
    [b setName:@"value"];
    [b setAttributeType:NSInteger32AttributeType];

    XCTAssertNotEqualObjects([a versionHash], [b versionHash]);
}

- (void)testVersionHashModifierAffectsHashes
{
    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:@"Thing"];
    NSData *before = [entity versionHash];
    [entity setVersionHashModifier:@"v2"];
    XCTAssertEqualObjects([entity versionHashModifier], @"v2");
    XCTAssertNotEqualObjects(before, [entity versionHash]);

    NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
    [attribute setName:@"value"];
    NSData *attributeBefore = [attribute versionHash];
    [attribute setVersionHashModifier:@"v2"];
    XCTAssertNotEqualObjects(attributeBefore, [attribute versionHash]);
}

- (void)testVersionIdentifiers
{
    NSManagedObjectModel *model = VersioningTestModelV1();
    XCTAssertEqual([[model versionIdentifiers] count], (NSUInteger)0);
    [model setVersionIdentifiers:[NSSet setWithObject:@"2"]];
    XCTAssertEqualObjects([model versionIdentifiers], [NSSet setWithObject:@"2"]);
}

@end
