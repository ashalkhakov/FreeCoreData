/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPersistentStoreRequest.h>
#import <CoreData/NSPersistentStoreResult.h>

@class NSDate, NSFetchRequest;
@class NSPersistentHistoryToken, NSPersistentHistoryTransaction;

/* Fetches or purges a store's persistent history through
   -[NSManagedObjectContext executeRequest:error:], answering with an
   NSPersistentHistoryResult.  Both anchor directions are exclusive
   (verified on macOS): fetching "after" an anchor returns strictly
   newer transactions, and deleting "before" an anchor removes strictly
   older ones - the anchor's own transaction survives the purge. */
@interface NSPersistentHistoryChangeRequest : NSPersistentStoreRequest {
    BOOL _isPurge;
    NSDate *_anchorDate;
    NSPersistentHistoryToken *_anchorToken;
    int64_t _anchorTransactionNumber;   /* -1: none */
    NSPersistentHistoryResultType _resultType;
}

+ (instancetype)fetchHistoryAfterDate:(NSDate *)date;
+ (instancetype)fetchHistoryAfterToken:(NSPersistentHistoryToken *)token;
+ (instancetype)fetchHistoryAfterTransaction:(NSPersistentHistoryTransaction *)transaction;

+ (instancetype)deleteHistoryBeforeDate:(NSDate *)date;
+ (instancetype)deleteHistoryBeforeToken:(NSPersistentHistoryToken *)token;
+ (instancetype)deleteHistoryBeforeTransaction:(NSPersistentHistoryTransaction *)transaction;

/* Apple's predicate-filtered flavor (fetchHistoryWithFetchRequest:,
   the fetchRequest property, entityDescriptionWithContext:) is not
   implemented; the anchor-based requests above are. */

- (NSPersistentHistoryResultType)resultType;   /* default TransactionsAndChanges */
- (void)setResultType:(NSPersistentHistoryResultType)resultType;

- (NSPersistentHistoryToken *)token;   /* the token anchor, when that is what was given */

@end
