/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>

@class NSString, NSDate, NSArray, NSNotification;
@class NSPersistentHistoryToken;

/* One recorded unit of change: a context save or a batch operation
   against a history-tracking store.  objectIDNotification wraps the
   changed object IDs in a notification that
   mergeChangesFromContextDidSaveNotification: understands, which is
   how history is replayed into a context. */
@interface NSPersistentHistoryTransaction : NSObject <NSCopying> {
    int64_t _transactionNumber;
    NSDate *_timestamp;
    NSString *_author;
    NSString *_contextName;
    NSString *_processID;
    NSString *_bundleID;
    NSString *_storeID;
    NSArray *_changes;
}

- (int64_t)transactionNumber;
- (NSDate *)timestamp;
- (NSString *)author;
- (NSString *)contextName;
- (NSString *)processID;
- (NSString *)bundleID;
- (NSString *)storeID;
- (NSPersistentHistoryToken *)token;

/* nil for a transactions-only fetch. */
- (NSArray *)changes;

- (NSNotification *)objectIDNotification;

@end
