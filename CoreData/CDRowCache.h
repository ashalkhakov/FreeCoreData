/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/Foundation.h>

@class NSIncrementalStoreNode, NSManagedObjectID, NSPersistentStore;

/* A coordinator's row cache, as Apple's coordinator keeps one for its
   SQLite store: the rows the framework's own stores (CDRowPrefetchingStores)
   answered, by object ID, each with the time it
   was read.  A row is kept while some context of the coordinator holds
   its object (has it registered) and let go when none does.  A context
   filling a fault takes the row from here when it is no older than the
   context's stalenessInterval allows (a negative interval: any age; 0:
   none), and asks the store otherwise; a fetch's rows and a save's
   rows read back refresh it.  Safe from any thread. */
@interface CDRowCache : NSObject {
   NSLock              *_lock;
   NSMutableDictionary *_entries;   /* object ID -> CDRowCacheEntry */
}

/* A context holds, or lets go of, the object of a permanent ID. */
- (void)holdObjectID:(NSManagedObjectID *)objectID;
- (void)releaseObjectID:(NSManagedObjectID *)objectID;

/* The row of objectID read no longer ago than staleness, or nil. */
- (NSIncrementalStoreNode *)rowForObjectID:(NSManagedObjectID *)objectID staleness:(NSTimeInterval)staleness;
/* Keeps row as objectID's, read now - if some context holds the object. */
- (void)setRow:(NSIncrementalStoreNode *)row forObjectID:(NSManagedObjectID *)objectID;
/* Forgets objectID's row, keeping its holders: the next read asks the store. */
- (void)forgetRowForObjectID:(NSManagedObjectID *)objectID;
/* Forgets every row of store (removed from its coordinator). */
- (void)forgetRowsOfStore:(NSPersistentStore *)store;

@end
