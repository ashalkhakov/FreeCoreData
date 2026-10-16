/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSManagedObject.h>

@class NSIncrementalStoreNode, NSMapTable;

/* A store that reads many rows in one go (the SQLite store, and the SQL
   backends, which implement these without the framework's headers): the
   rows of objectIDs, by ID, read in a few queries; and how many writes it
   has made, so that a row read before the last of them is not used.  A
   context reads the rows of the faults a fetch found through it, and a
   fetch with a batch size reads its batches through it. */
@protocol CDRowPrefetchingStore
- (NSDictionary *)_rowsForObjectIDs:(NSArray *)objectIDs;
- (unsigned long long)_writeGeneration;
@end

@interface NSManagedObject (private)
/* The permanent ID its store gave, for its temporary one. */
-(void)_setObjectID:(NSManagedObjectID *)objectID;
/* Relationship values naming a temporary ID (a key of replacements) name
   its permanent one (its value) after. */
-(void)_replaceObjectIDs:(NSMapTable *)replacements;
- initWithObjectID:(NSManagedObjectID *)objectID managedObjectContext:(NSManagedObjectContext *)context;

/* Set when the object joins a context, and cleared when it leaves one -
   an object inserted and deleted before any save is taken out of its
   context entirely, as on Apple. */
- (void)_setManagedObjectContext:(NSManagedObjectContext *)context;
- (NSDictionary *)_committedValues;
/* The row a fetch read for this fault, for its first read - if its store
   has made no write since (generation).  Held only by a fault; given up
   when the object goes away or is turned into a fault again. */
- (void)_holdPrefetchedRow:(NSIncrementalStoreNode *)row generation:(unsigned long long)generation;
/* After a save: the committed values made those of row, the one the
   store has just written (read with the others the context saved), or
   read from the store when row is nil; transient values carried across. */
/* What absorbing snapshot changes in this object's values, as its
   key-value observers are to be told: a dictionary for each key that
   differs (see -_changeNoticesForSnapshot: in NSManagedObject.m). */
- (NSArray *)_changeNoticesForSnapshot:(NSDictionary *)snapshot;
- (void)_resetCommittedValuesAfterSaveFromRow:(NSIncrementalStoreNode *)row generation:(unsigned long long)generation;
- (NSDictionary *)_cachedCommittedValues;
- (void)_invalidateCommittedValues;
/* The version of the incremental store's row this object's committed
   values were read from (NSIncrementalStoreNode's), or 0 when it holds
   none: never read, or invalidated since.  A save is checked against it
   -- optimistic locking -- and 0 means the row is taken as it stands. */
- (unsigned long long)_storeVersion;
- (void)_setStoreVersion:(unsigned long long)version;
- (void)_resetCommittedValuesAfterSavePreservingTransients;
- (void)_discardChangedValues;
- (void)_discardChangedValueForKey:(NSString *)key;
- (void)_setFault:(BOOL)isFault;
/* -setValue:forKey: without calling a setter the class implements: the
   framework's own writes (see NSManagedObject.m). */
- (void)_setModeledValue:(id)value forKey:(NSString *)key;

/* Nested-context value transport (see NSManagedObject.m). */
- (NSDictionary *)_snapshotOfCurrentValuesChangedOnly:(BOOL)changedOnly;
- (void)_absorbChangedValuesFromSnapshot:(NSDictionary *)snapshot;
- (void)_promoteCurrentValuesToCommitted:(NSDictionary *)fullSnapshot;
@end
