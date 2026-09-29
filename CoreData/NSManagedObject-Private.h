/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSManagedObject.h>

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

/* Nested-context value transport (see NSManagedObject.m). */
- (NSDictionary *)_snapshotOfCurrentValuesChangedOnly:(BOOL)changedOnly;
- (void)_absorbChangedValuesFromSnapshot:(NSDictionary *)snapshot;
- (void)_promoteCurrentValuesToCommitted:(NSDictionary *)fullSnapshot;
@end
