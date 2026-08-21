/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSFetchRequest.h>
#import "NSFetchRequest-Private.h"
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSPersistentStore.h>
#import "NSManagedObject-Private.h"
#import "NSManagedObjectID-Private.h"
#import "NSEntityDescription-Private.h"
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSAtomicStore.h>
#import <CoreData/NSIncrementalStore.h>
#import <CoreData/NSIncrementalStoreNode.h>
#import <CoreData/NSSaveChangesRequest.h>
#import <CoreData/CoreDataErrors.h>
#import <CoreData/NSMergePolicy.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import <CoreData/NSAtomicStoreCacheNode.h>
#import "NSPersistentStoreCoordinator-Private.h"
#import <Foundation/NSUndoManager.h>
#import <Foundation/NSNull.h>
#import "CoreDataUtilities.h"

NSString * const NSManagedObjectContextWillSaveNotification=@"NSManagedObjectContextWillSaveNotification";
NSString * const NSManagedObjectContextDidSaveNotification=@"NSManagedObjectContextDidSaveNotification";
NSString * const NSManagedObjectContextObjectsDidChangeNotification=@"NSManagedObjectContextObjectsDidChangeNotification";

NSString * const NSInsertedObjectsKey=@"NSInsertedObjectsKey";
NSString * const NSUpdatedObjectsKey=@"NSUpdatedObjectsKey";
NSString * const NSDeletedObjectsKey=@"NSDeletedObjectsKey";
NSString * const NSRefreshedObjectsKey=@"NSRefreshedObjectsKey";
NSString * const NSInvalidatedObjectsKey=@"NSInvalidatedObjectsKey";
NSString * const NSInvalidatedAllObjectsKey=@"NSInvalidatedAllObjectsKey";

@interface NSAtomicStore(private)
-(void)_uniqueObjectID:(NSManagedObjectID *)objectID;
-(void)_removeCacheNodes:(NSSet *)cacheNodes;
@end

@interface NSIncrementalStore(private)
-(void)_uniqueObjectID:(NSManagedObjectID *)objectID;
@end

@interface NSMergeConflict(private)
-(void)_setObjectSnapshot:(NSDictionary *)snapshot;
@end

@implementation NSManagedObjectContext

-init {
   _lock=[[NSLock alloc] init];
   _storeCoordinator=nil;
   _undoManager=[[NSUndoManager alloc] init];
   _registeredObjects=[[NSMutableSet alloc] init];
   _insertedObjects=[[NSMutableSet alloc] init];
   _updatedObjects=[[NSMutableSet alloc] init];
   _deletedObjects=[[NSMutableSet alloc] init];
   _pendingInsertedObjects=[[NSMutableSet alloc] init];
   _pendingUpdatedObjects=[[NSMutableSet alloc] init];
   _pendingDeletedObjects=[[NSMutableSet alloc] init];
   _pendingRefreshedObjects=[[NSMutableSet alloc] init];
   
   _objectIdToObject=NSCreateMapTable(NSObjectMapKeyCallBacks,NSObjectMapValueCallBacks,0);
   _requestedProcessPendingChanges = NO;
   [NSMergePolicy self]; // ensure the merge policy globals are initialized
   _mergePolicy=[NSErrorMergePolicy retain];
   return self;
}

-(void)dealloc {
   NSArray *registered=[_registeredObjects allObjects];

   if(_requestedProcessPendingChanges)
    [[NSRunLoop mainRunLoop] cancelPerformSelector: @selector(_processPendingChangesForRequest)
                             target: self
                             argument: nil];

   for(NSManagedObject *check in registered){
    NSArray *properties=[[[check entity] propertiesByName] allKeys];

    for(NSString *key in properties)
     [check removeObserver:self forKeyPath:key];
   }

   if(_storeCoordinator!=nil)
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSPersistentStoreCoordinatorStoresDidChangeNotification object:_storeCoordinator];

   [_storeCoordinator release];
   [_undoManager release];
   [_registeredObjects release];
   [_insertedObjects release];
   [_updatedObjects release];
   [_deletedObjects release];
   [_pendingInsertedObjects release];
   [_pendingUpdatedObjects release];
   [_pendingDeletedObjects release];
   [_pendingRefreshedObjects release];
   NSFreeMapTable(_objectIdToObject);
   [super dealloc];
}

-(NSPersistentStoreCoordinator *)persistentStoreCoordinator {
   return _storeCoordinator;
}

-(NSUndoManager *)undoManager {
    return _undoManager;
}

-(BOOL)retainsRegisteredObjects {
    return _retainsRegisteredObjects;
}

-(BOOL)propagatesDeletesAtEndOfEvent {
    return _propagatesDeletesAtEndOfEvent;
}

-(NSTimeInterval)stalenessInterval {
    return _stalenessInterval;
}

-mergePolicy {
    return _mergePolicy;
}

-(void)_discardPendingChangeNotifications {
   [_pendingInsertedObjects removeAllObjects];
   [_pendingUpdatedObjects removeAllObjects];
   [_pendingDeletedObjects removeAllObjects];
   [_pendingRefreshedObjects removeAllObjects];
}

-(void)persistentStoresDidChange:(NSNotification *)note {
   NSArray *stores=[[note userInfo] objectForKey:NSRemovedPersistentStoresKey];
      
   for(NSPersistentStore *store in stores){
    NSArray *allObjects=NSAllMapTableValues(_objectIdToObject);

    for(NSManagedObject *check in allObjects){
     NSManagedObjectID *objectID=[check objectID];
        
     if([objectID persistentStore]==store){
     
     NSEntityDescription *entity=[check entity];
      NSArray             *properties=[[entity propertiesByName] allKeys];

      for(NSString *key in properties)
       [check removeObserver:self forKeyPath:key];

      [_registeredObjects removeObject:check];
      [_insertedObjects removeObject:check];
      [_updatedObjects removeObject:check];
      [_deletedObjects removeObject:check];
      [_pendingInsertedObjects removeObject:check];
      [_pendingUpdatedObjects removeObject:check];
      [_pendingDeletedObjects removeObject:check];
      [_pendingRefreshedObjects removeObject:check];
      NSMapRemove(_objectIdToObject,objectID);
     }
    }
   }
}


-(void)setPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)value {
   if(_storeCoordinator!=nil)
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSPersistentStoreCoordinatorStoresDidChangeNotification object:_storeCoordinator];
    
   value=[value retain];
   [_storeCoordinator release];
   _storeCoordinator=value;

   if(_storeCoordinator!=nil)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(persistentStoresDidChange:) name:NSPersistentStoreCoordinatorStoresDidChangeNotification object:_storeCoordinator];
}

-(void)setUndoManager:(NSUndoManager *)value {
   value=[value retain];
   [_undoManager release];
   _undoManager=value;
}

-(void)setRetainsRegisteredObjects:(BOOL)value {
   _retainsRegisteredObjects=value;
   NSUnimplementedMethod();
}

-(void)setPropagatesDeletesAtEndOfEvent:(BOOL)value {
   _propagatesDeletesAtEndOfEvent=value;
}

-(void)setStalenessInterval:(NSTimeInterval)value {
   _stalenessInterval=value;
}

-(void)setMergePolicy:value {
   value=[value retain];
   [_mergePolicy release];
   _mergePolicy=value;
}

-(NSSet *)registeredObjects {
  return _registeredObjects;
}

-(NSSet *)insertedObjects {
    return _insertedObjects;
}

-(NSSet *)updatedObjects {
   return _updatedObjects;
}

-(NSSet *)deletedObjects {
   return _deletedObjects;
}

-(BOOL)hasChanges {
   /* Matching Apple: YES while there are unsaved inserted, deleted or
      updated objects.  Note that a change made behind KVC's back (such
      as mutating a mutable transformable value in place) is invisible
      here. */
   return [_insertedObjects count]>0 || [_updatedObjects count]>0 ||
          [_deletedObjects count]>0;
}

-(void)lock {
   [_lock lock];
}

-(void)unlock {
   [_lock unlock];
}

-(BOOL)tryLock {
   return [_lock tryLock];
}

-(void)undo {
    NSUnimplementedMethod();
}


-(void)redo {
    NSUnimplementedMethod();
}


-(void)reset {
   for(NSManagedObject *object in [[_registeredObjects copy] autorelease]){
    NSArray *properties=[[[object entity] propertiesByName] allKeys];

    for(NSString *key in properties)
     [object removeObserver:self forKeyPath:key];
   }

   [_registeredObjects removeAllObjects];
   [_insertedObjects removeAllObjects];
   [_updatedObjects removeAllObjects];
   [_deletedObjects removeAllObjects];
   [self _discardPendingChangeNotifications];
   NSResetMapTable(_objectIdToObject);
}


-(void)rollback {
   for(NSManagedObject *object in _registeredObjects){
    [object _discardChangedValues];
    [object _invalidateCommittedValues];
   }

   for(NSManagedObject *inserted in [[_insertedObjects copy] autorelease]){
    NSArray *properties=[[[inserted entity] propertiesByName] allKeys];

    for(NSString *key in properties)
     [inserted removeObserver:self forKeyPath:key];

    [_registeredObjects removeObject:inserted];
    NSMapRemove(_objectIdToObject,[inserted objectID]);
   }

   [_insertedObjects removeAllObjects];
   [_updatedObjects removeAllObjects];
   [_deletedObjects removeAllObjects];
   [self _discardPendingChangeNotifications];
}

-(NSAtomicStoreCacheNode *)_cacheNodeForObjectID:(NSManagedObjectID *)objectID {
   NSAtomicStore *store=(NSAtomicStore *)[_storeCoordinator _persistentStoreForObjectID:objectID];

   return [store cacheNodeForObjectID:objectID];
}

-(NSManagedObject *)objectRegisteredForID:(NSManagedObjectID *)objectID {
   return NSMapGet(_objectIdToObject,objectID);
}

-(void)_registerObject:(NSManagedObject *)object {
   [_registeredObjects addObject:object];
   NSMapInsert(_objectIdToObject,[object objectID],object);

   NSEntityDescription *entity=[object entity];
   NSArray             *properties=[[entity propertiesByName] allKeys];

   for(NSString *key in properties){
    [object addObserver:self forKeyPath:key options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:nil];
   }
}


-(NSManagedObject *)objectWithID:(NSManagedObjectID *)objectID {
   NSManagedObject *result=NSMapGet(_objectIdToObject,objectID);

   if(result==nil){
    result=[[NSManagedObject alloc] initWithObjectID:objectID managedObjectContext:self];
    NSMapInsert(_objectIdToObject,objectID,result);
    [result release];
    [self _registerObject:result];
   }
   
   return result;
}

/* Builds NSDictionaryResultType rows from saved snapshots (cache-node
   property caches or committed-value dictionaries).  Keys are limited to
   propertiesToFetch when set, otherwise every attribute of the entity;
   relationship values never appear in the rows.  returnsDistinctResults
   collapses equal rows, preserving order. */
-(NSArray *)_dictionaryResultsForRequest:(NSFetchRequest *)request snapshots:(NSArray *)snapshots {
   NSMutableArray *names=[NSMutableArray array];
   NSArray        *properties=[request propertiesToFetch];

   if([properties count]>0){
    for(id property in properties)
     [names addObject:[property isKindOfClass:[NSString class]]?property:[(NSPropertyDescription *)property name]];
   }
   else
    [names addObjectsFromArray:[[[[request entity] attributesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)]];

   NSMutableArray *result=[NSMutableArray array];

   for(NSDictionary *snapshot in snapshots){
    NSMutableDictionary *row=[NSMutableDictionary dictionary];

    for(NSString *name in names){
     id value=[snapshot objectForKey:name];

     if(value==nil || value==[NSNull null])
      continue;
     if([value isKindOfClass:[NSAtomicStoreCacheNode class]] ||
        [value isKindOfClass:[NSSet class]] || [value isKindOfClass:[NSManagedObjectID class]])
      continue; /* relationship values are not part of dictionary rows */
     [row setObject:value forKey:name];
    }

    if([request returnsDistinctResults] && [result containsObject:row])
     continue;

    [result addObject:row];
   }

   return result;
}

-(NSArray *)executeFetchRequest:(NSFetchRequest *)fetchRequest error:(NSError **)error {
   /* A request created with an entity name resolves it against the
      coordinator's model at execution time, matching Apple.  (The
      private accessor avoids the NSObjectInaccessibleException that
      -entity raises on an unresolved name-based request.) */
   if([fetchRequest _entityIfResolved]==nil && [fetchRequest entityName]!=nil){
    NSEntityDescription *named=[[[_storeCoordinator managedObjectModel] entitiesByName] objectForKey:[fetchRequest entityName]];

    if(named==nil){
     [NSException raise:NSInvalidArgumentException
                 format:@"executeFetchRequest:error: could not locate an entity named '%@' in this model.",[fetchRequest entityName]];
    }

    [fetchRequest setEntity:named];
   }

   NSArray *affectedStores=[fetchRequest affectedStores];

   if(affectedStores==nil)
    affectedStores=[_storeCoordinator persistentStores];

   NSFetchRequestResultType resultType=[fetchRequest resultType];
   NSPredicate             *predicate=[fetchRequest predicate];

   /* Apple's fetch is two layers: the store answers with the last saved
      state, then the context overlays this context's unsaved inserts,
      updates and deletes and emits the result in the shape resultType
      asked for.  The overlay is skipped when includesPendingChanges is
      NO, when there is nothing pending - and always for dictionary
      results, which Apple documents as reflecting the persistent store
      only ("A value of YES is not supported in conjunction with the
      result type NSDictionaryResultType"). */
   BOOL mergePending=[fetchRequest includesPendingChanges] &&
                     resultType!=NSDictionaryResultType &&
                     ([_insertedObjects count]>0 || [_updatedObjects count]>0 || [_deletedObjects count]>0);

   if(!mergePending){
    /* Pass-through: the store's answer, already in the requested shape
       when a single incremental store can produce it. */
    if([affectedStores count]==1 &&
       [[affectedStores objectAtIndex:0] isKindOfClass:[NSIncrementalStore class]])
     return [(NSIncrementalStore *)[affectedStores objectAtIndex:0] executeRequest:fetchRequest withContext:self error:error];

    /* Atomic stores (and multi-store unions): collect the saved
       membership, then shape it here.  Membership and dictionary values
       come from the stores' saved snapshots (cache nodes / committed
       values); note that returned managed objects still show this
       context's in-memory values - membership and values are separate
       questions, as on Apple. */
    NSMutableArray *objects=[NSMutableArray array];
    NSMutableArray *savedSnapshots=[NSMutableArray array]; /* parallel to objects */

    for(NSPersistentStore *genericStore in affectedStores){
     if([genericStore isKindOfClass:[NSIncrementalStore class]]){
      NSFetchRequest *inner=[[fetchRequest copy] autorelease];

      [inner setResultType:NSManagedObjectResultType];
      /* Limits apply to the union, not to each store. */
      [inner setFetchLimit:0];
      [inner setFetchOffset:0];

      NSArray *fetched=[(NSIncrementalStore *)genericStore executeRequest:inner withContext:self error:error];

      if(fetched==nil)
       return nil;

      for(NSManagedObject *check in fetched){
       [objects addObject:check];
       [savedSnapshots addObject:[check committedValuesForKeys:nil]];
      }
      continue;
     }

     if(![genericStore isKindOfClass:[NSAtomicStore class]])
      continue;

     for(NSAtomicStoreCacheNode *node in [(NSAtomicStore *)genericStore cacheNodes]){
      NSEntityDescription *nodeEntity=[[node objectID] entity];

      if(![nodeEntity _isKindOfEntity:[fetchRequest entity]])
       continue;
      if(![fetchRequest includesSubentities] &&
         ![[nodeEntity name] isEqualToString:[[fetchRequest entity] name]])
       continue;

      /* Saved membership: the predicate is evaluated against the cache
         node (KVC over the node's property cache). */
      if(predicate!=nil && ![predicate evaluateWithObject:node])
       continue;

      [objects addObject:[self objectWithID:[node objectID]]];
      [savedSnapshots addObject:[node propertyCache]];
     }
    }

    /* Order, then window, then shape. */
    if([[fetchRequest sortDescriptors] count]>0){
     NSArray *sorted=[objects sortedArrayUsingDescriptors:[fetchRequest sortDescriptors]];
     NSMutableArray *reorderedSnapshots=[NSMutableArray array];

     for(NSManagedObject *object in sorted)
      [reorderedSnapshots addObject:[savedSnapshots objectAtIndex:[objects indexOfObjectIdenticalTo:object]]];

     objects=[NSMutableArray arrayWithArray:sorted];
     savedSnapshots=reorderedSnapshots;
    }

    NSUInteger offset=[fetchRequest fetchOffset],limit=[fetchRequest fetchLimit];

    if(offset>0){
     if(offset>=[objects count]){
      [objects removeAllObjects];
      [savedSnapshots removeAllObjects];
     }
     else {
      [objects removeObjectsInRange:NSMakeRange(0,offset)];
      [savedSnapshots removeObjectsInRange:NSMakeRange(0,offset)];
     }
    }
    if(limit>0 && [objects count]>limit){
     [objects removeObjectsInRange:NSMakeRange(limit,[objects count]-limit)];
     [savedSnapshots removeObjectsInRange:NSMakeRange(limit,[savedSnapshots count]-limit)];
    }

    switch(resultType){

     case NSManagedObjectIDResultType: {
      NSMutableArray *ids=[NSMutableArray array];

      for(NSManagedObject *object in objects)
       [ids addObject:[object objectID]];
      return ids;
     }

     case NSCountResultType:
      return [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:[objects count]]];

     case NSDictionaryResultType:
      return [self _dictionaryResultsForRequest:fetchRequest snapshots:savedSnapshots];

     default:
      return objects;
    }
   }

   /* Overlay path: membership is recomputed with this context's
      in-memory state.  Saved candidates come from the stores with the
      predicate applied but without limit/offset (the window only makes
      sense after the merge); deletes are dropped, updated objects are
      re-tested with their current values (in both directions), unsaved
      inserts are added when they match. */
   NSMutableArray *merged=[NSMutableArray array];
   NSMutableSet   *seen=[NSMutableSet set];

   for(NSPersistentStore *genericStore in affectedStores){
    if([genericStore isKindOfClass:[NSIncrementalStore class]]){
     NSFetchRequest *inner=[[fetchRequest copy] autorelease];

     [inner setResultType:NSManagedObjectResultType];
     [inner setFetchLimit:0];
     [inner setFetchOffset:0];

     NSArray *fetched=[(NSIncrementalStore *)genericStore executeRequest:inner withContext:self error:error];

     if(fetched==nil)
      return nil;

     for(NSManagedObject *check in fetched){
      if(![seen containsObject:check]){
       [seen addObject:check];
       [merged addObject:check];
      }
     }
     continue;
    }

    if(![genericStore isKindOfClass:[NSAtomicStore class]])
     continue;

    for(NSAtomicStoreCacheNode *node in [(NSAtomicStore *)genericStore cacheNodes]){
     NSEntityDescription *nodeEntity=[[node objectID] entity];

     if(![nodeEntity _isKindOfEntity:[fetchRequest entity]])
      continue;
     if(predicate!=nil && ![predicate evaluateWithObject:node])
      continue;

     NSManagedObject *check=[self objectWithID:[node objectID]];

     if(![seen containsObject:check]){
      [seen addObject:check];
      [merged addObject:check];
     }
    }
   }

   /* Drop pending deletes; re-test pending updates with in-memory
      values. */
   NSMutableArray *overlaid=[NSMutableArray array];

   for(NSManagedObject *check in merged){
    if([_deletedObjects containsObject:check])
     continue;
    if(predicate!=nil && [_updatedObjects containsObject:check] &&
       ![predicate evaluateWithObject:check])
     continue;
    [overlaid addObject:check];
   }

   /* Pending updates that only match with their unsaved values, and
      pending inserts. */
   NSMutableSet *additions=[NSMutableSet setWithSet:_updatedObjects];

   [additions unionSet:_insertedObjects];

   for(NSManagedObject *check in additions){
    if([_deletedObjects containsObject:check])
     continue;
    if([seen containsObject:check] && ![overlaid containsObject:check])
     continue; /* store candidate that the overlay already rejected */
    if([overlaid containsObject:check])
     continue;
    if(![[check entity] _isKindOfEntity:[fetchRequest entity]])
     continue;
    if(![affectedStores containsObject:[[check objectID] persistentStore]])
     continue;
    if(predicate!=nil && ![predicate evaluateWithObject:check])
     continue;
    [overlaid addObject:check];
   }

   if([[fetchRequest sortDescriptors] count]>0)
    [overlaid sortUsingDescriptors:[fetchRequest sortDescriptors]];

   NSUInteger offset=[fetchRequest fetchOffset],limit=[fetchRequest fetchLimit];

   if(offset>0){
    if(offset>=[overlaid count])
     [overlaid removeAllObjects];
    else
     [overlaid removeObjectsInRange:NSMakeRange(0,offset)];
   }
   if(limit>0 && [overlaid count]>limit)
    [overlaid removeObjectsInRange:NSMakeRange(limit,[overlaid count]-limit)];

   switch(resultType){

    case NSManagedObjectIDResultType: {
     NSMutableArray *ids=[NSMutableArray array];

     for(NSManagedObject *object in overlaid)
      [ids addObject:[object objectID]];
     return ids;
    }

    case NSCountResultType:
     return [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:[overlaid count]]];

    default:
     return overlaid;
   }
}

-(NSUInteger)countForFetchRequest:(NSFetchRequest *)request error:(NSError **)error {
   /* Matching Apple: the number of objects the request would have
      returned from executeFetchRequest:, or NSNotFound on error. */
   NSFetchRequest *counted=[[request copy] autorelease];

   [counted setResultType:NSCountResultType];

   NSArray *result=[self executeFetchRequest:counted error:error];

   if(result==nil)
    return NSNotFound;

   return [[result lastObject] unsignedIntegerValue];
}

-(NSManagedObject *)existingObjectWithID:(NSManagedObjectID *)objectID error:(NSError **)error {
   /* Matching Apple: an object the context recognizes is returned
      directly; otherwise a fully realized object is fetched from the
      persistent store - this method never returns a fault.  When the
      object exists in neither, it fails. */
   NSManagedObject *registered=(objectID!=nil)?[self objectRegisteredForID:objectID]:nil;

   if(registered!=nil && ![registered isFault])
    return registered;

   BOOL exists=NO;

   if(objectID!=nil && ![objectID isTemporaryID]){
    NSPersistentStore *store=[objectID persistentStore];

    if([store isKindOfClass:[NSIncrementalStore class]]){
     NSError                *nodeError=nil;
     NSIncrementalStoreNode *node=[(NSIncrementalStore *)store newValuesForObjectWithID:objectID withContext:self error:&nodeError];

     exists=(node!=nil);
     [node release];
    }
    else if([store isKindOfClass:[NSAtomicStore class]])
     exists=([(NSAtomicStore *)store cacheNodeForObjectID:objectID]!=nil);
   }

   if(!exists){
    if(error!=NULL){
     NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

     [userInfo setObject:[NSString stringWithFormat:@"The object with ID %@ could not be found in the persistent store.",objectID] forKey:NSLocalizedDescriptionKey];

     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectReferentialIntegrityError userInfo:userInfo];
    }
    return nil;
   }

   NSManagedObject *object=[self objectWithID:objectID];

   /* Realize the object's values so a fault is never returned. */
   [object _committedValues];

   return object;
}

-(void)insertObject:(NSManagedObject *)object {
   NSPersistentStore *store=[_storeCoordinator _persistentStoreForObject:object];
   
   [[object objectID] setStoreIdentifier:[store identifier]];
   [[object objectID] setPersistentStore:store];

   [_insertedObjects addObject:object];
   [_updatedObjects addObject:object];
   [self _registerObject:object];

   [_pendingInsertedObjects addObject:object];
   [_pendingDeletedObjects removeObject:object];
   [self _requestProcessPendingChanges];
}

-(void)deleteObject:(NSManagedObject *)object {
   /* Apple re-invokes the callback each time deleteObject: is called,
      even when the object is already marked for deletion. */
   [object prepareForDeletion];

   [_deletedObjects addObject:object];

   /* An object that was inserted and deleted in the same event is not
      reported at all, matching Apple's behavior. */
   if([_pendingInsertedObjects containsObject:object])
    [_pendingInsertedObjects removeObject:object];
   else
    [_pendingDeletedObjects addObject:object];

   [_pendingUpdatedObjects removeObject:object];
   [_pendingRefreshedObjects removeObject:object];
   [self _requestProcessPendingChanges];
}

-(void)assignObject:object toPersistentStore:(NSPersistentStore *)store {
   [object retain];

   NSMapRemove(_objectIdToObject,[object objectID]);

   [[object objectID] setStoreIdentifier:[store identifier]];

   [[object objectID] setPersistentStore:store];

   NSMapInsert(_objectIdToObject,[object objectID],object);
   [object release];
}

-(void)detectConflictsForObject:(NSManagedObject *)object {
    NSUnimplementedMethod();
}

-(void)refreshObject:(NSManagedObject *)object mergeChanges:(BOOL)flag {
   if(flag){
    /* Reload persisted values from the store while keeping in-memory
       changes. */
    [object _invalidateCommittedValues];
   }
   else {
    /* Turn the object back into a fault, discarding in-memory changes. */
    [object willTurnIntoFault];
    [object _discardChangedValues];
    [object _invalidateCommittedValues];
    [object _setFault:YES];
    [_updatedObjects removeObject:object];
    [object didTurnIntoFault];
   }

   if(![_pendingDeletedObjects containsObject:object] && ![_pendingInsertedObjects containsObject:object]){
    [_pendingRefreshedObjects addObject:object];
    [_pendingUpdatedObjects removeObject:object];
    [self _requestProcessPendingChanges];
   }
}

-(void)_requestProcessPendingChanges {
    if(!_requestedProcessPendingChanges){

	NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
	[runLoop performSelector: @selector(_processPendingChangesForRequest)
		 target: self
		 argument: nil
		 order: 0
		 modes: [NSArray arrayWithObject:NSRunLoopCommonModes]];
	_requestedProcessPendingChanges = YES;
   }
}

-(void)_processPendingChanges {
    _requestedProcessPendingChanges = NO;

    if([_pendingInsertedObjects count]==0 && [_pendingUpdatedObjects count]==0 &&
       [_pendingDeletedObjects count]==0 && [_pendingRefreshedObjects count]==0)
     return;

    NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

    if([_pendingInsertedObjects count]>0)
     [userInfo setObject:[[_pendingInsertedObjects copy] autorelease] forKey:NSInsertedObjectsKey];
    if([_pendingUpdatedObjects count]>0)
     [userInfo setObject:[[_pendingUpdatedObjects copy] autorelease] forKey:NSUpdatedObjectsKey];
    if([_pendingDeletedObjects count]>0)
     [userInfo setObject:[[_pendingDeletedObjects copy] autorelease] forKey:NSDeletedObjectsKey];
    if([_pendingRefreshedObjects count]>0)
     [userInfo setObject:[[_pendingRefreshedObjects copy] autorelease] forKey:NSRefreshedObjectsKey];

    [_pendingInsertedObjects removeAllObjects];
    [_pendingUpdatedObjects removeAllObjects];
    [_pendingDeletedObjects removeAllObjects];
    [_pendingRefreshedObjects removeAllObjects];

    [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextObjectsDidChangeNotification object:self userInfo:userInfo];
}

-(void)processPendingChanges {
   if(_requestedProcessPendingChanges){
    [[NSRunLoop mainRunLoop] cancelPerformSelector: @selector(_processPendingChangesForRequest)
                             target: self
                             argument: nil];
   }
   
   [self _processPendingChanges];
}


-(void)_processPendingChangesForRequest {
    [self _processPendingChanges];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
   if(NSMapGet(_objectIdToObject,[object objectID])==object){
    [_updatedObjects addObject:object];

    if(![_pendingInsertedObjects containsObject:object] && ![_pendingDeletedObjects containsObject:object])
     [_pendingUpdatedObjects addObject:object];

    [self _requestProcessPendingChanges];
   }
}

-(BOOL)obtainPermanentIDsForObjects:(NSArray *)objects error:(NSError **)error {

   for(NSManagedObject *check in objects){
    NSManagedObjectID *checkID=[check objectID];
        
    if([checkID isTemporaryID]){
     NSPersistentStore *genericStore=[checkID persistentStore];
     
     NSMapRemove(_objectIdToObject,checkID);

     if(genericStore==nil)
      NSLog(@"internal inconsistency , object had no store %@",check);

     if([genericStore isKindOfClass:[NSIncrementalStore class]]){
      NSIncrementalStore *store=(NSIncrementalStore *)genericStore;
      NSError            *idError=nil;
      NSArray            *permanentIDs=[store obtainPermanentIDsForObjects:[NSArray arrayWithObject:check] error:&idError];

      if([permanentIDs count]==0){
       if(error!=NULL)
        *error=idError;

       NSMapInsert(_objectIdToObject,checkID,check);
       return NO;
      }

      NSManagedObjectID *permanentID=[permanentIDs objectAtIndex:0];
      id                 referenceObject=[store referenceObjectForObjectID:permanentID];

      /* Object IDs are uniqued by pointer in this port, so convert the
         existing temporary ID to a permanent one in place and re-register
         it in the store's uniquing table. */
      [checkID setReferenceObject:referenceObject];
      [store _uniqueObjectID:checkID];
     }
     else {
      NSAtomicStore *store=(NSAtomicStore *)genericStore;
      id referenceObject=[store newReferenceObjectForManagedObject:check];
     
      [checkID setReferenceObject:referenceObject];
     
      [store _uniqueObjectID:checkID];
     }
     
     NSMapInsert(_objectIdToObject,checkID,check);
    }
   }
   
   return YES;
}

/* Applies NSCascadeDeleteRule by deleting destination objects of cascade
   relationships of already-deleted objects, transitively. */
-(void)_propagateCascadeDeletes {
   NSMutableArray *worklist=[NSMutableArray arrayWithArray:[_deletedObjects allObjects]];
   NSUInteger      index;

   for(index=0;index<[worklist count];index++){
    NSManagedObject *deleted=[worklist objectAtIndex:index];
    NSDictionary    *relationships=[[deleted entity] relationshipsByName];

    for(NSString *key in relationships){
     NSRelationshipDescription *relationship=[relationships objectForKey:key];

     if([relationship deleteRule]!=NSCascadeDeleteRule)
      continue;

     id value=[deleted primitiveValueForKey:key];

     if(value==nil || value==[NSNull null])
      continue;

     NSSet *relatedIDs=[relationship isToMany]?[[value copy] autorelease]:[NSSet setWithObject:value];

     for(NSManagedObjectID *relatedID in relatedIDs){
      NSManagedObject *related=[self objectWithID:relatedID];

      if(![_deletedObjects containsObject:related]){
       [self deleteObject:related];
       [worklist addObject:related];
      }
     }
    }
   }
}

/* Validates the pending change sets, filling errorp and returning NO on
   the first per-Apple-shaped failure (single error or 1560 multiple). */
-(BOOL)_validateChangesForSave:(NSError **)errorp {
   NSMutableArray *errors=[NSMutableArray array];

   for(NSManagedObject *deleted in _deletedObjects){
    NSError *validationError=nil;

    if(![deleted validateForDelete:&validationError] && validationError!=nil)
     [errors addObject:validationError];
   }

   for(NSManagedObject *inserted in _insertedObjects){
    if([_deletedObjects containsObject:inserted])
     continue;

    NSError *validationError=nil;

    if(![inserted validateForInsert:&validationError] && validationError!=nil){
     if([validationError code]==NSValidationMultipleErrorsError)
      [errors addObjectsFromArray:[[validationError userInfo] objectForKey:NSDetailedErrorsKey]];
     else
      [errors addObject:validationError];
    }
   }

   for(NSManagedObject *updated in _updatedObjects){
    if([_deletedObjects containsObject:updated] || [_insertedObjects containsObject:updated])
     continue;

    NSError *validationError=nil;

    if(![updated validateForUpdate:&validationError] && validationError!=nil){
     if([validationError code]==NSValidationMultipleErrorsError)
      [errors addObjectsFromArray:[[validationError userInfo] objectForKey:NSDetailedErrorsKey]];
     else
      [errors addObject:validationError];
    }
   }

   if([errors count]==0)
    return YES;

   if(errorp!=NULL){
    if([errors count]==1)
     *errorp=[errors objectAtIndex:0];
    else {
     NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

     [userInfo setObject:errors forKey:NSDetailedErrorsKey];
     [userInfo setObject:@"Multiple validation errors occurred." forKey:NSLocalizedDescriptionKey];
     *errorp=[NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationMultipleErrorsError userInfo:userInfo];
    }
   }

   return NO;
}

/* Optimistic locking: detects rows whose persisted attribute values in an
   atomic store no longer match the snapshot this context last read. */
-(NSArray *)_detectSaveConflicts {
   NSMutableArray *conflicts=[NSMutableArray array];

   for(NSManagedObject *updated in _updatedObjects){
    if([_insertedObjects containsObject:updated] || [_deletedObjects containsObject:updated])
     continue;

    NSDictionary *cached=[updated _cachedCommittedValues];

    if(cached==nil)
     continue;

    if(![[[updated objectID] persistentStore] isKindOfClass:[NSAtomicStore class]])
     continue;

    NSAtomicStoreCacheNode *node=[self _cacheNodeForObjectID:[updated objectID]];

    if(node==nil)
     continue;

    NSDictionary        *attributes=[[updated entity] attributesByName];
    NSMutableDictionary *rowCacheSnapshot=[NSMutableDictionary dictionary];
    NSMutableDictionary *objectSnapshot=[NSMutableDictionary dictionary];
    BOOL                 hasConflict=NO;

    for(NSString *key in attributes){
     id rowCacheValue=[node valueForKey:key];
     id committedValue=[cached objectForKey:key];

     if(rowCacheValue!=nil)
      [rowCacheSnapshot setObject:rowCacheValue forKey:key];
     if(committedValue!=nil)
      [objectSnapshot setObject:committedValue forKey:key];

     if(rowCacheValue==committedValue)
      continue;
     if(rowCacheValue!=nil && committedValue!=nil && [rowCacheValue isEqual:committedValue])
      continue;

     hasConflict=YES;
    }

    if(hasConflict){
     /* Apple reports a context-versus-row-cache conflict: cachedSnapshot
        holds the coordinator's (newer) row cache values, objectSnapshot
        holds the (older) committed values the context last read, and
        persistedSnapshot is nil. The atomic stores do not yet track
        per-row optimistic-lock version stamps, so the version numbers
        reflect a single external update (old 1, new 2). */
     NSMergeConflict *conflict=[[[NSMergeConflict alloc] initWithSource:updated
                                                             newVersion:2
                                                             oldVersion:1
                                                         cachedSnapshot:rowCacheSnapshot
                                                      persistedSnapshot:nil] autorelease];
     [conflict _setObjectSnapshot:objectSnapshot];

     [conflicts addObject:conflict];
    }
   }

   return conflicts;
}

/* Resolves save conflicts according to the receiver's merge policy.
   Returns NO (with errorp filled) for the error policy. */
-(BOOL)_resolveSaveConflicts:(NSArray *)conflicts error:(NSError **)errorp {
   if([conflicts count]==0)
    return YES;

   NSMergePolicyType mergeType=NSErrorMergePolicyType;

   if([_mergePolicy isKindOfClass:[NSMergePolicy class]])
    mergeType=[_mergePolicy mergeType];

   switch(mergeType){

    case NSErrorMergePolicyType:{
     if(errorp!=NULL){
      NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

      [userInfo setObject:@"Could not merge changes." forKey:NSLocalizedDescriptionKey];
      [userInfo setObject:conflicts forKey:NSPersistentStoreSaveConflictsErrorKey];
      *errorp=[NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectMergeError userInfo:userInfo];
     }
     return NO;
    }

    case NSMergeByPropertyStoreTrumpMergePolicyType:
     for(NSMergeConflict *conflict in conflicts){
      NSManagedObject *object=[conflict sourceObject];
      NSDictionary    *committed=[conflict objectSnapshot];
      NSDictionary    *rowCache=[conflict cachedSnapshot];
      NSMutableSet    *keys=[NSMutableSet setWithArray:[committed allKeys]];

      [keys addObjectsFromArray:[rowCache allKeys]];

      for(NSString *key in keys){
       id committedValue=[committed objectForKey:key];
       id rowCacheValue=[rowCache objectForKey:key];

       if(committedValue==rowCacheValue)
        continue;
       if(committedValue!=nil && rowCacheValue!=nil && [committedValue isEqual:rowCacheValue])
        continue;

       /* The store changed this property; its value trumps any
          in-memory change. */
       [object _discardChangedValueForKey:key];
      }

      [object _invalidateCommittedValues];
     }
     return YES;

    case NSMergeByPropertyObjectTrumpMergePolicyType:
     for(NSMergeConflict *conflict in conflicts)
      [[conflict sourceObject] _invalidateCommittedValues];
     return YES;

    case NSOverwriteMergePolicyType:
     /* The in-memory object is written over the persisted version. */
     return YES;

    case NSRollbackMergePolicyType:
     for(NSMergeConflict *conflict in conflicts){
      NSManagedObject *object=[conflict sourceObject];

      [object _discardChangedValues];
      [object _invalidateCommittedValues];
      [_updatedObjects removeObject:object];
     }
     return YES;
   }

   return YES;
}

/* Applies NSNullifyDeleteRule semantics: disconnects deleted objects from
   the graph right before they are removed from their stores. */
-(void)_nullifyRelationshipsOfDeletedObjects {
   for(NSManagedObject *deleted in [[_deletedObjects copy] autorelease]){
    NSArray *properties=[[[deleted entity] propertiesByName] allValues];

    for(NSPropertyDescription *property in properties)
     if([property isKindOfClass:[NSRelationshipDescription class]])
      [deleted setValue:nil forKey:[property name]];
   }
}

-(BOOL)save:(NSError **)errorp {
   NSMutableArray *errors=[NSMutableArray array];
   NSMutableArray *errorStores=[NSMutableArray array];
   NSError        *idError=nil;
   NSMutableSet   *affectedStores=[NSMutableSet set];
   NSMutableSet   *incrementalInserted=[NSMutableSet set];
   NSMutableSet   *incrementalUpdated=[NSMutableSet set];
   NSMutableSet   *incrementalDeleted=[NSMutableSet set];

   /* Apple flushes pending changes (and thus posts the objects-did-change
      notification) before the save begins. */
   [self processPendingChanges];

   [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextWillSaveNotification object:self];

   /* Lifecycle: give every changed object a chance to react before
      validation and the actual write. */
   NSMutableSet *changedObjects=[NSMutableSet setWithSet:_insertedObjects];
   [changedObjects unionSet:_updatedObjects];
   [changedObjects unionSet:_deletedObjects];

   for(NSManagedObject *object in changedObjects)
    [object willSave];

   [self _propagateCascadeDeletes];

   if(![self _validateChangesForSave:errorp])
    return NO;

   if(![self _resolveSaveConflicts:[self _detectSaveConflicts] error:errorp])
    return NO;

   [self _nullifyRelationshipsOfDeletedObjects];

   /* Snapshots for the did-save notification and -didSave callbacks. */
   NSMutableSet *notifyInserted=[NSMutableSet set];
   NSMutableSet *notifyUpdated=[NSMutableSet set];
   NSSet        *notifyDeleted=[[_deletedObjects copy] autorelease];

   for(NSManagedObject *check in _insertedObjects)
    if(![_deletedObjects containsObject:check])
     [notifyInserted addObject:check];

   for(NSManagedObject *check in _updatedObjects)
    if(![_deletedObjects containsObject:check] && ![_insertedObjects containsObject:check])
     [notifyUpdated addObject:check];

   /* Capture the change sets destined for incremental stores before the
      bookkeeping below mutates them. */
   for(NSManagedObject *check in _insertedObjects){
    if([_deletedObjects containsObject:check])
     continue;
    if([[[check objectID] persistentStore] isKindOfClass:[NSIncrementalStore class]])
     [incrementalInserted addObject:check];
   }

   for(NSManagedObject *check in _updatedObjects){
    if([_deletedObjects containsObject:check] || [_insertedObjects containsObject:check])
     continue;
    if([[[check objectID] persistentStore] isKindOfClass:[NSIncrementalStore class]])
     [incrementalUpdated addObject:check];
   }

   for(NSManagedObject *check in _deletedObjects){
    if([[check objectID] isTemporaryID])
     continue;
    if([[[check objectID] persistentStore] isKindOfClass:[NSIncrementalStore class]])
     [incrementalDeleted addObject:check];
   }

   for(NSManagedObject *deleted in _deletedObjects){
    NSPersistentStore *store=[_storeCoordinator _persistentStoreForObject:deleted];

    if([store isKindOfClass:[NSAtomicStore class]]){
     NSAtomicStore          *atomicStore=(NSAtomicStore *)store;
     NSAtomicStoreCacheNode *node=[atomicStore cacheNodeForObjectID:[deleted objectID]];
    
     if(node!=nil){
      NSSet *nodeSet=[NSSet setWithObject:node];

      [atomicStore willRemoveCacheNodes:nodeSet];
      [atomicStore _removeCacheNodes:nodeSet];
     }
    }

    [affectedStores addObject:store];
    
    NSMapRemove(_objectIdToObject,[deleted objectID]);

    [_insertedObjects removeObject:deleted];
    [_updatedObjects removeObject:deleted];
   }

   if(![self obtainPermanentIDsForObjects:[_insertedObjects allObjects] error:&idError]){
    NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];
   
    [userInfo setObject:@"obtainPermanentIDsForObjects failed" forKey:NSLocalizedDescriptionKey];
   
    if(errorp!=NULL)
     *errorp=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreIncompleteSaveError userInfo:userInfo];
     
    return NO;
   }

   for(NSManagedObject *inserted in _insertedObjects){
    NSPersistentStore *store=[_storeCoordinator _persistentStoreForObject:inserted];

    if([store isKindOfClass:[NSAtomicStore class]]){
     NSAtomicStore          *atomicStore=(NSAtomicStore *)store;
     NSAtomicStoreCacheNode *node=[atomicStore newCacheNodeForManagedObject:inserted];
    
     [atomicStore addCacheNodes:[NSSet setWithObject:node]];
    }
    
    [affectedStores addObject:store];
   }

   [_insertedObjects removeAllObjects];
   
   for(NSManagedObject *updated in _updatedObjects){
    NSPersistentStore *store=[_storeCoordinator _persistentStoreForObject:updated];

    if([store isKindOfClass:[NSAtomicStore class]]){
     NSAtomicStore          *atomicStore=(NSAtomicStore *)store;
     NSAtomicStoreCacheNode *node=[atomicStore cacheNodeForObjectID:[updated objectID]];

     [atomicStore updateCacheNode:node fromManagedObject:updated];
    }

    [affectedStores addObject:store];
   }
   
   /* Apple sends a save changes request to every incremental store on
      save, even when the change sets destined for that store are empty. */
   for(NSPersistentStore *store in [_storeCoordinator persistentStores])
    if([store isKindOfClass:[NSIncrementalStore class]])
     [affectedStores addObject:store];
   
   for(NSPersistentStore *store in affectedStores){
    NSError           *saveError=nil;
    
    if([store isKindOfClass:[NSAtomicStore class]]){
     NSAtomicStore *atomicStore=(NSAtomicStore *)store;
     
     if(![atomicStore save:&saveError]){
      [errorStores addObject:atomicStore];
      [errors addObject:saveError];
     }
    }
    else if([store isKindOfClass:[NSIncrementalStore class]]){
     NSIncrementalStore *incrementalStore=(NSIncrementalStore *)store;
     NSMutableSet       *storeInserted=[NSMutableSet set];
     NSMutableSet       *storeUpdated=[NSMutableSet set];
     NSMutableSet       *storeDeleted=[NSMutableSet set];

     for(NSManagedObject *check in incrementalInserted)
      if([[check objectID] persistentStore]==store)
       [storeInserted addObject:check];
     for(NSManagedObject *check in incrementalUpdated)
      if([[check objectID] persistentStore]==store)
       [storeUpdated addObject:check];
     for(NSManagedObject *check in incrementalDeleted)
      if([[check objectID] persistentStore]==store)
       [storeDeleted addObject:check];

     NSSaveChangesRequest *request=[[[NSSaveChangesRequest alloc] initWithInsertedObjects:storeInserted updatedObjects:storeUpdated deletedObjects:storeDeleted lockedObjects:nil] autorelease];

     if([incrementalStore executeRequest:request withContext:self error:&saveError]==nil){
      [errorStores addObject:incrementalStore];

      if(saveError!=nil)
       [errors addObject:saveError];
     }
    }
   }

   if([errors count]==0){
    [_updatedObjects removeAllObjects];
    [_deletedObjects removeAllObjects];

    /* Fold the saved changes into the committed snapshots so that
       -changedValues is empty and -committedValuesForKeys: reflects the
       persisted state. */
    NSMutableSet *saved=[NSMutableSet setWithSet:notifyInserted];
    [saved unionSet:notifyUpdated];

    for(NSManagedObject *object in saved){
     [object _discardChangedValues];
     [object _invalidateCommittedValues];
    }

    for(NSManagedObject *object in saved)
     [object didSave];
    for(NSManagedObject *object in notifyDeleted)
     [object didSave];

    NSMutableDictionary *notifyInfo=[NSMutableDictionary dictionary];

    [notifyInfo setObject:notifyInserted forKey:NSInsertedObjectsKey];
    [notifyInfo setObject:notifyUpdated forKey:NSUpdatedObjectsKey];
    [notifyInfo setObject:notifyDeleted forKey:NSDeletedObjectsKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:NSManagedObjectContextDidSaveNotification object:self userInfo:notifyInfo];

    return YES;
   }
  
   NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];
   
   [userInfo setObject:@"Unable to save managed object context" forKey:NSLocalizedDescriptionKey];
   [userInfo setObject:errorStores forKey:NSAffectedStoresErrorKey];
   [userInfo setObject:errors forKey:NSDetailedErrorsKey];
   
   if(errorp!=NULL)
    *errorp=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreIncompleteSaveError userInfo:userInfo];
  
   return NO;
}

-(void)mergeChangesFromContextDidSaveNotification:(NSNotification *)notification {
   NSDictionary *userInfo=[notification userInfo];

   for(NSManagedObject *inserted in [userInfo objectForKey:NSInsertedObjectsKey]){
    /* Registers a fault for the newly saved object in the receiver. */
    [self objectWithID:[inserted objectID]];
   }

   for(NSManagedObject *updated in [userInfo objectForKey:NSUpdatedObjectsKey]){
    NSManagedObject *local=[self objectRegisteredForID:[updated objectID]];

    if(local!=nil)
     [self refreshObject:local mergeChanges:YES];
   }

   for(NSManagedObject *deleted in [userInfo objectForKey:NSDeletedObjectsKey]){
    NSManagedObject *local=[self objectRegisteredForID:[deleted objectID]];

    if(local!=nil){
     /* Apple keeps the local instance registered and materialized (its
        committed values remain readable) but marks it as deleted in the
        receiving context; it is not turned into a fault. */
     [local _discardChangedValues];

     [_insertedObjects removeObject:local];
     [_updatedObjects removeObject:local];
     [_deletedObjects addObject:local];
    }
   }
}


-(BOOL)commitEditing {
   NSUnimplementedMethod();
   return NO;
}

-(void)commitEditingWithDelegate:(id)delegate didCommitSelector:(SEL)didCommitSelector contextInfo:(void *)contextInfo {
   NSUnimplementedMethod();
}


-(void)discardEditing {
   NSUnimplementedMethod();
}


-(void)objectDidBeginEditing:(id)editor {
   NSUnimplementedMethod();
}


-(void)objectDidEndEditing:(id)editor {
   NSUnimplementedMethod();
}

@end
