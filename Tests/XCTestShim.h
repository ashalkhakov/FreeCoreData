/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* XCTestShim.h - Minimal XCTest-compatible shim for running CoreData tests
   on GNUstep without a real XCTest framework.
   On Apple platforms, import the real XCTest instead. */

#ifndef XCTEST_SHIM_H
#define XCTEST_SHIM_H

#import <Foundation/Foundation.h>

/* ---- XCTestCase stand-in ---- */
@interface XCTestCase : NSObject
- (void)setUp;
- (void)tearDown;
+ (NSString *)testSuiteName;
@end

/* ---- Assertion macros ---- */

#define XCTFail(format, ...) \
    do { \
        NSLog(@"FAIL [%s:%d]: " format, __FILE__, __LINE__, ##__VA_ARGS__); \
        _xctest_failureCount++; \
    } while(0)

#define XCTAssert(expr, ...) \
    do { \
        if (!(expr)) { \
            XCTFail("XCTAssert(%s) " #__VA_ARGS__, #expr, ##__VA_ARGS__); \
        } \
    } while(0)

#define XCTAssertTrue(expr, ...) XCTAssert(expr, ##__VA_ARGS__)

#define XCTAssertFalse(expr, ...) \
    do { \
        if ((expr)) { \
            XCTFail("XCTAssertFalse(%s) " #__VA_ARGS__, #expr, ##__VA_ARGS__); \
        } \
    } while(0)

#define XCTAssertNotNil(obj, ...) \
    do { \
        if ((obj) == nil) { \
            XCTFail("XCTAssertNotNil(%s) " #__VA_ARGS__, #obj, ##__VA_ARGS__); \
        } \
    } while(0)

#define XCTAssertNil(obj, ...) \
    do { \
        if ((obj) != nil) { \
            XCTFail("XCTAssertNil(%s) was %@ " #__VA_ARGS__, #obj, (obj), ##__VA_ARGS__); \
        } \
    } while(0)

#define XCTAssertEqual(a, b, ...) \
    do { \
        if ((a) != (b)) { \
            XCTFail("XCTAssertEqual(%s, %s) " #__VA_ARGS__, #a, #b, ##__VA_ARGS__); \
        } \
    } while(0)

#define XCTAssertEqualObjects(a, b, ...) \
    do { \
        id _a = (a); id _b = (b); \
        if ((_a == nil && _b != nil) || (_a != nil && ![_a isEqual:_b])) { \
            XCTFail("XCTAssertEqualObjects(%s=%@, %s=%@) " #__VA_ARGS__, #a, _a, #b, _b, ##__VA_ARGS__); \
        } \
    } while(0)

#define XCTAssertNoThrow(expr, ...) \
    do { \
        @try { (void)(expr); } \
        @catch (NSException *_e) { \
            XCTFail("XCTAssertNoThrow(%s) threw %@ " #__VA_ARGS__, #expr, [_e reason], ##__VA_ARGS__); \
        } \
    } while(0)

/* ---- Test runner (GNUstep-only) ---- */

extern int _xctest_failureCount;

/* Run all test methods (prefixed with "test") on the given class. */
static inline int XCTestRunClass(Class cls)
{
    int failures = 0;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    id suite = [[cls alloc] init];

    [suite setUp];

    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *name = sel_getName(sel);
        if (strncmp(name, "test", 4) == 0) {
            _xctest_failureCount = 0;
            NSLog(@"  Running %s...", name);
            @try {
                [suite performSelector:sel];
            } @catch (NSException *e) {
                NSLog(@"  EXCEPTION: %@", e);
                _xctest_failureCount++;
            }
            if (_xctest_failureCount == 0)
                NSLog(@"  PASS");
            else {
                NSLog(@"  FAIL (%d assertion(s) failed)", _xctest_failureCount);
                failures += _xctest_failureCount;
            }
        }
    }
    free(methods);
    [suite tearDown];
    [suite release];
    return failures;
}

#import <objc/runtime.h>
#import <string.h>

#endif /* XCTEST_SHIM_H */
