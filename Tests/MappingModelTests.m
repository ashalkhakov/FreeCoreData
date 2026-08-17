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
