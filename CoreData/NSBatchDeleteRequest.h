/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPersistentStoreRequest.h>
#import <CoreData/NSPersistentStoreResult.h>

@class NSFetchRequest;

/* Deletes the rows matched by a fetch request (or an explicit list of
   object IDs) directly in a persistent store, bypassing contexts: no
   delete rules run beyond the store's own referential cleanup, no
   validation, and loaded contexts keep their objects until
   mergeChangesFromRemoteContextSave:intoContexts: (or a refresh)
   tells them. */
@interface NSBatchDeleteRequest : NSPersistentStoreRequest {
    NSFetchRequest *_fetchRequest;
    NSArray *_objectIDs;
    NSBatchDeleteRequestResultType _resultType;
}

- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetch;
- (instancetype)initWithObjectIDs:(NSArray *)objects;

- (NSFetchRequest *)fetchRequest;

- (NSBatchDeleteRequestResultType)resultType;   /* default StatusOnly */
- (void)setResultType:(NSBatchDeleteRequestResultType)resultType;

@end
