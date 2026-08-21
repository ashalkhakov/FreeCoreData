/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSFetchRequestTests - basic NSFetchRequest tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"

@interface NSFetchRequestTests : XCTestCase
@end

@implementation NSFetchRequestTests

- (void)testDefaults
{
    /* Apple's documented defaults. */
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    XCTAssertNil([req entity]);
    XCTAssertNil([req predicate]);
    XCTAssertEqual([req fetchLimit], (NSUInteger)0);
    XCTAssertEqual([req resultType],
                   (NSFetchRequestResultType)NSManagedObjectResultType);
    XCTAssertTrue([req includesSubentities]);
    XCTAssertTrue([req includesPendingChanges]);
    XCTAssertTrue([req includesPropertyValues]);
    XCTAssertTrue([req returnsObjectsAsFaults]);
    XCTAssertFalse([req returnsDistinctResults]);
    XCTAssertFalse([req shouldRefreshRefetchedObjects]);
    XCTAssertNil([req propertiesToGroupBy]);
    XCTAssertNil([req havingPredicate]);
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

- (void)testFetchRequestWithEntityNameStoresOnlyTheName
{
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:
                                              @"Employee"];

    XCTAssertEqualObjects([req entityName], @"Employee");

    /* Verified against Apple's CoreData: -entity on a name-based request
       raises NSObjectInaccessibleException ("...was created with a
       string name (Employee), and cannot respond to -entity until used
       by an NSManagedObjectContext") until the request is executed. */
    BOOL raised = NO;
    @try {
        (void)[req entity];
    }
    @catch (NSException *e) {
        raised = YES;
        XCTAssertEqualObjects([e name], NSObjectInaccessibleException);
    }
    XCTAssertTrue(raised,
                  @"-entity must raise before the request has been used");

    NSFetchRequest *copy = [req copy];
    XCTAssertEqualObjects([copy entityName], @"Employee");
}

- (void)testEntityNameIsResolvedWhenExecuted
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV1()];
    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store, @"failed to add store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    NSManagedObject *employee =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx];
    [employee setValue:@"Alice" forKey:@"name"];
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:
                                              @"Employee"];
    NSArray *result = [ctx executeFetchRequest:req error:&error];
    XCTAssertEqual([result count], (NSUInteger)1);
    XCTAssertEqualObjects([[result lastObject] valueForKey:@"name"],
                          @"Alice");

    /* Once the request has been used by a context, -entity responds
       with the resolved entity ("...until used by an
       NSManagedObjectContext"). */
    XCTAssertEqualObjects([[req entity] name], @"Employee");

    /* An entity name that is not in the model raises. */
    NSFetchRequest *bogus = [NSFetchRequest fetchRequestWithEntityName:
                                                @"NoSuchEntity"];
    BOOL raised = NO;
    @try {
        [ctx executeFetchRequest:bogus error:&error];
    }
    @catch (NSException *e) {
        raised = YES;
    }
    XCTAssertTrue(raised,
                  @"executing with an unknown entity name must raise");
}

@end
