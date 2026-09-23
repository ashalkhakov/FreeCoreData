/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPersistentStoreRequest.h>

@class NSFetchRequest, NSAsynchronousFetchResult;

typedef void (^NSPersistentStoreAsynchronousFetchResultCompletionBlock)(NSAsynchronousFetchResult *result);

/* Wraps a fetch request for asynchronous execution through
   -[NSManagedObjectContext executeRequest:error:]: executeRequest:
   returns an NSAsynchronousFetchResult immediately, the fetch runs as
   its own event on the context's queue, and the completion block is
   called there with the populated result. */
@interface NSAsynchronousFetchRequest : NSPersistentStoreRequest {
    NSFetchRequest *_fetchRequest;
    NSPersistentStoreAsynchronousFetchResultCompletionBlock _completionBlock;
    NSInteger _estimatedResultCount;
}

- (instancetype)initWithFetchRequest:(NSFetchRequest *)request
                     completionBlock:(NSPersistentStoreAsynchronousFetchResultCompletionBlock)blk;

- (NSFetchRequest *)fetchRequest;
- (NSPersistentStoreAsynchronousFetchResultCompletionBlock)completionBlock;

/* A hint used to seed the progress' total unit count; 0 (the default)
   means unknown. */
- (NSInteger)estimatedResultCount;
- (void)setEstimatedResultCount:(NSInteger)count;

@end
