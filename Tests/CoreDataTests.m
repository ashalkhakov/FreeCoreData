/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* CoreDataTests.m - Basic CoreData runtime tests.
   These tests run against our GNUstep port on Linux and against
   Apple's real CoreData on macOS/Xcode. */

#if __has_include(<XCTest/XCTest.h>)
#  import <XCTest/XCTest.h>
#  import <CoreData/CoreData.h>
#else
#  import "XCTestShim.h"
#  import <CoreData/CoreData.h>
#endif

/* ------------------------------------------------------------------ */
/* A minimal in-memory CoreData stack used by most tests.             */
/* ------------------------------------------------------------------ */

static NSManagedObjectModel *buildTestModel(void)
{
    /* Entity: Person { name:String, age:Integer32 } */
    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    [person setName:@"Person"];
    [person setManagedObjectClassName:@"NSManagedObject"];

    NSAttributeDescription *nameAttr = [[NSAttributeDescription alloc] init];
    /* NSAttributeDescription cannot be init'd via -init (abstract).
       We build the model programmatically only when the framework
       supports it; otherwise we skip this test on GNUstep where
       NSAttributeDescription is keyed-unarchive-only. */
    [nameAttr release];
    [person release];

    /* Return a minimal (entity-less) model that at least exists. */
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    return [model autorelease];
}

/* ------------------------------------------------------------------ */
#pragma mark - NSManagedObjectModelTests
/* ------------------------------------------------------------------ */

@interface NSManagedObjectModelTests : XCTestCase
@end

@implementation NSManagedObjectModelTests

- (void)setUp    {}
- (void)tearDown {}

+ (NSString *)testSuiteName { return @"NSManagedObjectModelTests"; }

- (void)testModelCreation
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    XCTAssertNotNil(model);
    XCTAssertNotNil([model entities]);
    [model release];
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
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [model setFetchRequestTemplate:req forName:@"myTemplate"];
    XCTAssertEqualObjects([model fetchRequestTemplateForName:@"myTemplate"], req);
    [req release];
    [model release];
}

- (void)testConfigurations
{
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    XCTAssertNotNil([model configurations]);
    [model release];
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSFetchRequestTests
/* ------------------------------------------------------------------ */

@interface NSFetchRequestTests : XCTestCase
@end

@implementation NSFetchRequestTests

- (void)setUp    {}
- (void)tearDown {}

+ (NSString *)testSuiteName { return @"NSFetchRequestTests"; }

- (void)testDefaults
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    XCTAssertNil([req entity]);
    XCTAssertNil([req predicate]);
    XCTAssertEqual([req fetchLimit], (NSUInteger)0);
    [req release];
}

- (void)testSettersGetters
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setFetchLimit:42];
    XCTAssertEqual([req fetchLimit], (NSUInteger)42);
    [req setFetchOffset:10];
    XCTAssertEqual([req fetchOffset], (NSUInteger)10);
    [req release];
}

- (void)testCopy
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setFetchLimit:7];
    NSFetchRequest *copy = [req copy];
    XCTAssertNotNil(copy);
    XCTAssertEqual([copy fetchLimit], (NSUInteger)7);
    [copy release];
    [req release];
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSPersistentStoreCoordinatorTests
/* ------------------------------------------------------------------ */

@interface NSPersistentStoreCoordinatorTests : XCTestCase
@end

@implementation NSPersistentStoreCoordinatorTests

- (void)setUp    {}
- (void)tearDown {}

+ (NSString *)testSuiteName { return @"NSPersistentStoreCoordinatorTests"; }

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

    [psc release];
    [model release];
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

    [psc release];
    [model release];
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSManagedObjectContextTests
/* ------------------------------------------------------------------ */

@interface NSManagedObjectContextTests : XCTestCase
{
    NSManagedObjectModel *_model;
    NSPersistentStoreCoordinator *_psc;
    NSManagedObjectContext *_ctx;
}
@end

@implementation NSManagedObjectContextTests

- (void)setUp
{
    _model = [[NSManagedObjectModel alloc] init];
    _psc   = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:_model];
    NSError *err = nil;
    [_psc addPersistentStoreWithType:NSInMemoryStoreType
                       configuration:nil URL:nil options:nil error:&err];
    _ctx = [[NSManagedObjectContext alloc] init];
    [_ctx setPersistentStoreCoordinator:_psc];
}

- (void)tearDown
{
    [_ctx release]; _ctx = nil;
    [_psc release]; _psc = nil;
    [_model release]; _model = nil;
}

+ (NSString *)testSuiteName { return @"NSManagedObjectContextTests"; }

- (void)testContextCreation
{
    XCTAssertNotNil(_ctx);
    XCTAssertNotNil([_ctx persistentStoreCoordinator]);
    XCTAssertFalse([_ctx hasChanges]);
}

- (void)testRegisteredObjects
{
    XCTAssertNotNil([_ctx registeredObjects]);
    XCTAssertEqual([[_ctx registeredObjects] count], (NSUInteger)0);
}

- (void)testSaveWithNoChanges
{
    NSError *err = nil;
    BOOL ok = [_ctx save:&err];
    XCTAssertTrue(ok);
    XCTAssertNil(err);
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - GNUstep-only test runner main()
/* ------------------------------------------------------------------ */

#if !__has_include(<XCTest/XCTest.h>)

int _xctest_failureCount = 0;

@implementation XCTestCase
- (void)setUp    {}
- (void)tearDown {}
+ (NSString *)testSuiteName { return NSStringFromClass(self); }
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSLog(@"=== CoreData Test Suite ===");
        int totalFailures = 0;
        Class suites[] = {
            [NSManagedObjectModelTests class],
            [NSFetchRequestTests class],
            [NSPersistentStoreCoordinatorTests class],
            [NSManagedObjectContextTests class],
        };
        for (size_t i = 0; i < sizeof(suites)/sizeof(suites[0]); i++) {
            NSLog(@"\n--- %@ ---", [suites[i] testSuiteName]);
            totalFailures += XCTestRunClass(suites[i]);
        }
        NSLog(@"\n=== %s (%d failure(s)) ===",
              totalFailures == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED",
              totalFailures);
        return totalFailures == 0 ? 0 : 1;
    }
}
#endif /* !XCTest */
