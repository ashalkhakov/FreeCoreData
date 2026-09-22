/* This file is part of the CoreData framework port for GNUstep.
   Ported from the Cocotron project (https://github.com/cjwl/cocotron).

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>
   Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMapTable.h>
#import <CoreData/CoreDataExports.h>

@class NSSet, NSMutableSet, NSNotification, NSUndoManager, NSMapTable;
@class NSManagedObject, NSManagedObjectID, NSFetchRequest, NSPersistentStore, NSPersistentStoreCoordinator;

COREDATA_EXPORT NSString *const NSManagedObjectContextWillSaveNotification;
COREDATA_EXPORT NSString *const NSManagedObjectContextDidSaveNotification;
COREDATA_EXPORT NSString *const NSManagedObjectContextObjectsDidChangeNotification;

COREDATA_EXPORT NSString *const NSInsertedObjectsKey;
COREDATA_EXPORT NSString *const NSUpdatedObjectsKey;
COREDATA_EXPORT NSString *const NSDeletedObjectsKey;
COREDATA_EXPORT NSString *const NSRefreshedObjectsKey;
COREDATA_EXPORT NSString *const NSInvalidatedObjectsKey;
COREDATA_EXPORT NSString *const NSInvalidatedAllObjectsKey;

/* Queue association, as on Apple: a context created with a queue type
   owns a serial execution context that all access must go through
   (performBlock: / performBlockAndWait:).  A context created with
   plain -init is a legacy thread-confined context. */
enum {
    NSConfinementConcurrencyType = 0x00,
    NSPrivateQueueConcurrencyType = 0x01,
    NSMainQueueConcurrencyType = 0x02
};
typedef NSUInteger NSManagedObjectContextConcurrencyType;

@interface NSManagedObjectContext : NSObject <NSLocking> {
    NSLock *_lock;
    NSPersistentStoreCoordinator *_storeCoordinator;
    NSUndoManager *_undoManager;
    BOOL _retainsRegisteredObjects;
    BOOL _propagatesDeletesAtEndOfEvent;
    NSTimeInterval _stalenessInterval;
    id _mergePolicy;

    NSManagedObjectContextConcurrencyType _concurrencyType;
    void *_workQueue;       /* dispatch_queue_t: owned serial queue for
                               private contexts, the main queue for
                               main-queue contexts */
    NSString *_contextName;

    /* Nested contexts: a child saves into its parent instead of the
       store, and fetches through it. */
    NSManagedObjectContext *_parentContext;
    BOOL _automaticallyMergesChangesFromParent;
    id _parentMergeObserver;

    NSMutableSet *_registeredObjects;

    NSMutableSet *_insertedObjects;
    NSMutableSet *_updatedObjects;
    NSMutableSet *_deletedObjects;

    /* Changes accumulated since the last objects-did-change notification. */
    NSMutableSet *_pendingInsertedObjects;
    NSMutableSet *_pendingUpdatedObjects;
    NSMutableSet *_pendingDeletedObjects;
    NSMutableSet *_pendingRefreshedObjects;

    NSMapTable *_objectIdToObject;

    BOOL _requestedProcessPendingChanges;

    /* Undo support: pre-change values, insertions and deletions captured
       since the last processPendingChanges, registered with the undo
       manager as one operation per change event. */
    NSMapTable     *_undoEventOldValues;   /* object -> {key -> old primitive} */
    NSMutableArray *_undoEventInserted;
    NSMutableArray *_undoEventDeleted;     /* records: object, snapshot, wasInserted */
    NSUInteger      _undoRegistrationDisabled;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator;
- (NSUndoManager *)undoManager;
- (BOOL)retainsRegisteredObjects;
- (BOOL)propagatesDeletesAtEndOfEvent;
- (NSTimeInterval)stalenessInterval;
- (id)mergePolicy;

/* The designated initializer on Apple since 10.7; plain -init remains
   the legacy thread-confined context. */
- (instancetype)initWithConcurrencyType:(NSManagedObjectContextConcurrencyType)concurrencyType;
- (NSManagedObjectContextConcurrencyType)concurrencyType;

/* Queue access.  performBlock: runs asynchronously on the context's
   queue, wrapped in an autorelease pool and followed by
   processPendingChanges (a "user event", as Apple documents);
   performBlockAndWait: runs synchronously with neither wrapper, and is
   reentrant - called from the context's own queue it executes
   immediately.  Both raise on a confinement context. */
- (void)performBlock:(void (^)(void))block;
- (void)performBlockAndWait:(void (^)(void))block;

/* Debug label, as on Apple. */
- (NSString *)name;
- (void)setName:(NSString *)value;

/* Nested contexts.  A child context uses its parent as its "store":
   fetches are answered from the parent's current state (including the
   parent's unsaved changes), and -save: pushes the child's changes
   into the parent without touching any persistent store - only the
   root of the chain writes to disk.  Object IDs are shared down the
   chain, so IDs stay temporary until the root context saves.
   persistentStoreCoordinator walks up the chain when unset locally.
   Setting a parent on a confinement context raises, as on Apple. */
- (NSManagedObjectContext *)parentContext;
- (void)setParentContext:(NSManagedObjectContext *)parent;

/* When set, saves by the parent (for a child context) or by sibling
   contexts of the same coordinator (for a coordinator-backed context)
   are merged into this context automatically, on its queue. */
- (BOOL)automaticallyMergesChangesFromParent;
- (void)setAutomaticallyMergesChangesFromParent:(BOOL)value;

- (void)setPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)value;
- (void)setUndoManager:(NSUndoManager *)value;
- (void)setRetainsRegisteredObjects:(BOOL)value;
- (void)setPropagatesDeletesAtEndOfEvent:(BOOL)value;
- (void)setStalenessInterval:(NSTimeInterval)value;
- (void)setMergePolicy:(id)value;

- (NSSet *)registeredObjects;
- (NSSet *)insertedObjects;
- (NSSet *)updatedObjects;
- (NSSet *)deletedObjects;

- (BOOL)hasChanges;

- (void)lock;
- (void)unlock;
- (BOOL)tryLock;

- (void)undo;
- (void)redo;
- (void)reset;
- (void)rollback;

- (NSManagedObject *)objectRegisteredForID:(NSManagedObjectID *)objectID;

- (NSManagedObject *)objectWithID:(NSManagedObjectID *)objectID;

/* Returns the recognized object, or a fully realized (never faulted)
   object fetched from the persistent store; nil with *error set
   (NSManagedObjectReferentialIntegrityError) when the object exists in
   neither, matching Apple. */
- (NSManagedObject *)existingObjectWithID:(NSManagedObjectID *)objectID error:(NSError **)error;

- (NSArray *)executeFetchRequest:(NSFetchRequest *)request error:(NSError **)error;
- (NSUInteger)countForFetchRequest:(NSFetchRequest *)request error:(NSError **)error;

- (void)insertObject:(NSManagedObject *)object;
- (void)deleteObject:(NSManagedObject *)object;

- (void)assignObject:object toPersistentStore:(NSPersistentStore *)store;

- (void)detectConflictsForObject:(NSManagedObject *)object;

- (void)refreshObject:(NSManagedObject *)object mergeChanges:(BOOL)flag;

- (void)processPendingChanges;

- (BOOL)obtainPermanentIDsForObjects:(NSArray *)objects error:(NSError **)error;
- (BOOL)save:(NSError **)error;
- (void)mergeChangesFromContextDidSaveNotification:(NSNotification *)notification;

- (BOOL)commitEditing;
- (void)commitEditingWithDelegate:(id)delegate didCommitSelector:(SEL)didCommitSelector contextInfo:(void *)contextInfo;
- (void)discardEditing;
- (void)objectDidBeginEditing:(id)editor;
- (void)objectDidEndEditing:(id)editor;

@end
