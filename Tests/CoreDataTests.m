/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* CoreDataTests.m - Basic CoreData runtime tests.
   Compiled with ARC (-fobjc-arc).
   Runs via GNUstep's xctest(1) runner on Linux and via Xcode on macOS.
   On both platforms the real XCTest framework is used — no custom shim. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

/* ------------------------------------------------------------------ */
#pragma mark - NSManagedObjectModelTests
/* ------------------------------------------------------------------ */

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

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSFetchRequestTests
/* ------------------------------------------------------------------ */

@interface NSFetchRequestTests : XCTestCase
@end

@implementation NSFetchRequestTests

- (void)testDefaults
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    XCTAssertNil([req entity]);
    XCTAssertNil([req predicate]);
    XCTAssertEqual([req fetchLimit], (NSUInteger)0);
}

- (void)testSettersGetters
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setFetchLimit:42];
    XCTAssertEqual([req fetchLimit], (NSUInteger)42);
    [req setFetchOffset:10];
    XCTAssertEqual([req fetchOffset], (NSUInteger)10);
}

- (void)testCopy
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setFetchLimit:7];
    NSFetchRequest *copy = [req copy];
    XCTAssertNotNil(copy);
    XCTAssertEqual([copy fetchLimit], (NSUInteger)7);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSPersistentStoreCoordinatorTests
/* ------------------------------------------------------------------ */

@interface NSPersistentStoreCoordinatorTests : XCTestCase
@end

@implementation NSPersistentStoreCoordinatorTests

- (void)testRegisteredStoreTypes
{
    NSDictionary *types = [NSPersistentStoreCoordinator registeredStoreTypes];
    XCTAssertNotNil(types);
    XCTAssertNotNil([types objectForKey:NSInMemoryStoreType]);
    XCTAssertNotNil([types objectForKey:NSXMLStoreType]);
}

- (void)testInMemoryStore
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    NSPersistentStoreCoordinator *psc =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    XCTAssertNotNil(psc);

    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store);
    XCTAssertNil(error);
    XCTAssertEqual([[psc persistentStores] count], (NSUInteger)1);
}

- (void)testRemoveStore
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    NSPersistentStoreCoordinator *psc =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];

    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store);
    BOOL removed = [psc removePersistentStore:store error:&error];
    XCTAssertTrue(removed);
    XCTAssertEqual([[psc persistentStores] count], (NSUInteger)0);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSManagedObjectContextTests
/* ------------------------------------------------------------------ */

@interface NSManagedObjectContextTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSManagedObjectContext *ctx;

@end

@implementation NSManagedObjectContextTests

- (void)setUp
{
    self.model = [[NSManagedObjectModel alloc] init];
    self.psc   = [[NSPersistentStoreCoordinator alloc]
                     initWithManagedObjectModel:self.model];
    NSError *err = nil;
    [self.psc addPersistentStoreWithType:NSInMemoryStoreType
                           configuration:nil URL:nil options:nil error:&err];
    self.ctx = [[NSManagedObjectContext alloc] init];
    [self.ctx setPersistentStoreCoordinator:self.psc];
}

- (void)tearDown
{
    self.ctx   = nil;
    self.psc   = nil;
    self.model = nil;
}

- (void)testContextCreation
{
    XCTAssertNotNil(self.ctx);
    XCTAssertNotNil([self.ctx persistentStoreCoordinator]);
    XCTAssertFalse([self.ctx hasChanges]);
}

- (void)testRegisteredObjects
{
    XCTAssertNotNil([self.ctx registeredObjects]);
    XCTAssertEqual([[self.ctx registeredObjects] count], (NSUInteger)0);
}

- (void)testSaveWithNoChanges
{
    NSError *err = nil;
    BOOL ok = [self.ctx save:&err];
    XCTAssertTrue(ok);
    XCTAssertNil(err);
}

@end
