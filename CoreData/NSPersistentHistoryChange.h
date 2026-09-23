/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>

@class NSManagedObjectID, NSDictionary, NSSet;
@class NSPersistentHistoryTransaction, NSEntityDescription, NSFetchRequest, NSManagedObjectContext;

enum {
    NSPersistentHistoryChangeTypeInsert = 0,
    NSPersistentHistoryChangeTypeUpdate = 1,
    NSPersistentHistoryChangeTypeDelete = 2
};
typedef NSInteger NSPersistentHistoryChangeType;

/* One insertion, update or deletion as the store recorded it.
   updatedProperties (updates only) names what changed; tombstone
   (deletions only) carries the last values of attributes marked
   preservesValueInHistoryOnDeletion, keyed by attribute name. */
@interface NSPersistentHistoryChange : NSObject <NSCopying> {
    int64_t _changeID;
    NSPersistentHistoryChangeType _changeType;
    NSManagedObjectID *_changedObjectID;
    NSDictionary *_tombstone;
    NSSet *_updatedProperties;
    NSPersistentHistoryTransaction *_transaction;   /* not retained */
}

/* A synthetic entity (named "Change") describing one history change,
   for building the fetch request that NSPersistentHistoryChangeRequest's
   fetchHistoryWithFetchRequest: filters by (predicates may use the
   accessor names below, e.g. changedObjectID == %@).  The entity is
   not part of the application's model.  Portable code builds its fetch
   request from entityDescriptionWithContext: - see the note in
   NSPersistentHistoryTransaction.h. */
+ (NSEntityDescription *)entityDescription;
+ (NSEntityDescription *)entityDescriptionWithContext:(NSManagedObjectContext *)context;

/* A fetch request preconfigured with that entity. */
+ (NSFetchRequest *)fetchRequest;

- (int64_t)changeID;
- (NSPersistentHistoryChangeType)changeType;
- (NSManagedObjectID *)changedObjectID;
- (NSDictionary *)tombstone;
- (NSSet *)updatedProperties;   /* NSPropertyDescription */
- (NSPersistentHistoryTransaction *)transaction;


/* --- Building a change (a FreeCoreData addition) --------------------
 
   A store outside the framework has to hand these back when it answers a
   history request, and Apple publishes no way to make one.  See
   NSPersistentHistoryToken.h for the compatibility note. */
+ (instancetype)changeWithID:(int64_t)changeID
                        type:(NSPersistentHistoryChangeType)type
                    objectID:(NSManagedObjectID *)objectID
           updatedProperties:(NSSet *)updatedProperties
                   tombstone:(NSDictionary *)tombstone;

@end
