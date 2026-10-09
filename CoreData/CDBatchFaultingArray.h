/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSArray.h>

@class NSManagedObjectContext, NSFetchRequest, NSPersistentStore;

/* The answer to a fetch with a batch size, as Apple's batch-faulting
   array: every object's ID is read when the fetch runs, but an object is
   registered in the context, and the rows of its batch read in one go,
   only when it or another of its batch is first asked for.  The store
   reads rows as a CDRowPrefetchingStore. */
@interface CDBatchFaultingArray : NSArray {
    NSArray                *_objectIDs;
    NSPersistentStore      *_store;
    NSManagedObjectContext *_context;
    NSFetchRequest         *_request;
    NSUInteger              _batchSize;
    id                     *_objects;
}

- (instancetype)initWithObjectIDs:(NSArray *)objectIDs
                            store:(NSPersistentStore *)store
                          context:(NSManagedObjectContext *)context
                          request:(NSFetchRequest *)request;

@end
