/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>

@class NSManagedObjectContext, NSError, NSProgress, NSArray;
@class NSAsynchronousFetchRequest;

/* Abstract base class for the results returned by
   -[NSManagedObjectContext executeRequest:error:]. */
@interface NSPersistentStoreResult : NSObject
@end

/* The immediately-returned handle for a request that executes
   asynchronously: the context it runs against, the error (if any) the
   operation ended with, a progress object, and cancellation. */
@interface NSPersistentStoreAsynchronousResult : NSPersistentStoreResult {
    NSManagedObjectContext *_managedObjectContext;
    NSError *_operationError;
    NSProgress *_progress;
}

- (NSManagedObjectContext *)managedObjectContext;
- (NSError *)operationError;
- (NSProgress *)progress;

- (void)cancel;

@end

/* The result of an NSAsynchronousFetchRequest; finalResult carries the
   fetched objects once the request completes. */
@interface NSAsynchronousFetchResult : NSPersistentStoreAsynchronousResult {
    NSAsynchronousFetchRequest *_fetchRequest;
    NSArray *_finalResult;
}

- (NSAsynchronousFetchRequest *)fetchRequest;
- (NSArray *)finalResult;

@end

/* What a batch request's result carries: a bare success flag, the
   object IDs of the affected rows, or their count. */
enum {
    NSBatchInsertRequestResultTypeStatusOnly = 0x0,
    NSBatchInsertRequestResultTypeObjectIDs = 0x1,
    NSBatchInsertRequestResultTypeCount = 0x2
};
typedef NSUInteger NSBatchInsertRequestResultType;

enum {
    NSStatusOnlyResultType = 0x0,
    NSUpdatedObjectIDsResultType = 0x1,
    NSUpdatedObjectsCountResultType = 0x2
};
typedef NSUInteger NSBatchUpdateRequestResultType;

enum {
    NSBatchDeleteResultTypeStatusOnly = 0x0,
    NSBatchDeleteResultTypeObjectIDs = 0x1,
    NSBatchDeleteResultTypeCount = 0x2
};
typedef NSUInteger NSBatchDeleteRequestResultType;

/* result is an NSNumber (status or count) or an NSArray of
   NSManagedObjectIDs, per the request's resultType. */
@interface NSBatchInsertResult : NSPersistentStoreResult {
    id _result;
    NSBatchInsertRequestResultType _resultType;
}

- (id)result;
- (NSBatchInsertRequestResultType)resultType;

@end

@interface NSBatchUpdateResult : NSPersistentStoreResult {
    id _result;
    NSBatchUpdateRequestResultType _resultType;
}

- (id)result;
- (NSBatchUpdateRequestResultType)resultType;

@end

@interface NSBatchDeleteResult : NSPersistentStoreResult {
    id _result;
    NSBatchDeleteRequestResultType _resultType;
}

- (id)result;
- (NSBatchDeleteRequestResultType)resultType;

@end
