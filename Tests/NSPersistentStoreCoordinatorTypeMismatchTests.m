/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSPersistentStoreCoordinatorTypeMismatchTests - store type mismatch tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "MemoryIncrementalStore.h"

@interface NSPersistentStoreCoordinatorTypeMismatchTests : XCTestCase
@end

@implementation NSPersistentStoreCoordinatorTypeMismatchTests

- (void)testAddStoreWithMismatchedTypeFails
{
    [NSPersistentStoreCoordinator registerStoreClass:[MismatchIncrementalStore class]
                                        forStoreType:MismatchIncrementalStoreType];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:IncrementalStoreTestModel()];
    NSURL *url = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
            [[NSProcessInfo processInfo] globallyUniqueString]]];

    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:MismatchIncrementalStoreType
                          configuration:nil
                                    URL:url
                                options:nil
                                  error:&error];
    XCTAssertNil(store);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([error domain], NSCocoaErrorDomain);
    XCTAssertEqual([error code], (NSInteger)NSPersistentStoreTypeMismatchError);
    XCTAssertEqual([[psc persistentStores] count], (NSUInteger)0);
}

@end
