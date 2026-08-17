/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSIncrementalStoreNodeTests - NSIncrementalStoreNode tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "MemoryIncrementalStore.h"

@interface NSIncrementalStoreNodeTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) MemoryIncrementalStore *store;
@property (nonatomic, strong) NSEntityDescription *entity;

@end

@implementation NSIncrementalStoreNodeTests

- (void)setUp
{
    [NSPersistentStoreCoordinator registerStoreClass:[MemoryIncrementalStore class]
                                        forStoreType:MemoryIncrementalStoreType];
    self.model = IncrementalStoreTestModel();
    self.psc = [[NSPersistentStoreCoordinator alloc]
                   initWithManagedObjectModel:self.model];
    NSURL *url = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSError *error = nil;
    self.store = (MemoryIncrementalStore *)
        [self.psc addPersistentStoreWithType:MemoryIncrementalStoreType
                               configuration:nil
                                         URL:url
                                     options:nil
                                       error:&error];
    self.entity = [[self.model entitiesByName] objectForKey:@"Person"];
}

- (void)tearDown
{
    self.store = nil;
    self.psc = nil;
    self.model = nil;
    self.entity = nil;
}

- (NSIncrementalStoreNode *)nodeWithValues:(NSDictionary *)values version:(uint64_t)version
{
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"node-ref"];
    return [[NSIncrementalStoreNode alloc] initWithObjectID:objectID
                                                 withValues:values
                                                    version:version];
}

- (void)testNodeStoresObjectIDAndVersion
{
    NSManagedObjectID *objectID =
        [self.store newObjectIDForEntity:self.entity referenceObject:@"node-ref"];
    NSIncrementalStoreNode *node = [[NSIncrementalStoreNode alloc]
        initWithObjectID:objectID
              withValues:[NSDictionary dictionaryWithObject:@"Bob" forKey:@"name"]
                 version:7];
    XCTAssertEqualObjects([node objectID], objectID);
    XCTAssertEqual([node version], (uint64_t)7);
}

- (void)testNodeValueForPropertyDescription
{
    NSIncrementalStoreNode *node =
        [self nodeWithValues:[NSDictionary dictionaryWithObjectsAndKeys:
                                 @"Bob", @"name",
                                 [NSNumber numberWithInt:30], @"age", nil]
                     version:1];
    NSPropertyDescription *nameProperty =
        [[self.entity attributesByName] objectForKey:@"name"];
    NSPropertyDescription *ageProperty =
        [[self.entity attributesByName] objectForKey:@"age"];
    XCTAssertEqualObjects([node valueForPropertyDescription:nameProperty], @"Bob");
    XCTAssertEqualObjects([node valueForPropertyDescription:ageProperty],
                          [NSNumber numberWithInt:30]);
}

- (void)testNodeUpdateWithValues
{
    NSIncrementalStoreNode *node =
        [self nodeWithValues:[NSDictionary dictionaryWithObjectsAndKeys:
                                 @"Bob", @"name",
                                 [NSNumber numberWithInt:30], @"age", nil]
                     version:1];
    [node updateWithValues:[NSDictionary dictionaryWithObjectsAndKeys:
                               @"Carol", @"name",
                               [NSNumber numberWithInt:31], @"age", nil]
                   version:2];
    NSPropertyDescription *nameProperty =
        [[self.entity attributesByName] objectForKey:@"name"];
    XCTAssertEqualObjects([node valueForPropertyDescription:nameProperty], @"Carol");
    XCTAssertEqual([node version], (uint64_t)2);
}

@end
