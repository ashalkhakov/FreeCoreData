/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSFetchRequest.h>
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
   
   _objectIdToObject=NSCreateMapTable(NSObjectMapKeyCallBacks,NSObjectMapValueCallBacks,0);
   _requestedProcessPendingChanges = NO;
   [NSMergePolicy self]; // ensure the merge policy globals are initialized
   _mergePolicy=[NSErrorMergePolicy retain];
   return self;
}

-(void)dealloc {
   NSArray *registered=[_registeredObjects allObjects];

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

-(void)_setHasChanges:(BOOL)value {
   _hasChanges=value;
}

-(BOOL)hasChanges {
    return _hasChanges;
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

-(NSArray *)executeFetchRequest:(NSFetchRequest *)fetchRequest error:(NSError **)error {
   NSArray *affectedStores=[fetchRequest affectedStores];

   if(affectedStores==nil)
    affectedStores=[_storeCoordinator persistentStores];
  
   NSMutableSet *resultSet=[NSMutableSet set];

   for(NSManagedObject *check in _insertedObjects){
    NSEntityDescription *entity=[check entity];
    
    if([entity _isKindOfEntity:[fetchRequest entity]]){       
     if(![_deletedObjects containsObject:check]){
      if([affectedStores containsObject:[[check objectID] persistentStore]]){
       [resultSet addObject:check];
       }
     }
    }
   }

   /* An incremental store returns results that are already filtered,
      sorted and limited; when the context has no pending inserts or
      deletes to merge in, return them as-is, preserving the store's
      ordering. */
   if([resultSet count]==0 && [_deletedObjects count]==0 && [affectedStores count]==1){
    NSPersistentStore *onlyStore=[affectedStores objectAtIndex:0];

    if([onlyStore isKindOfClass:[NSIncrementalStore class]])
     return [(NSIncrementalStore *)onlyStore executeRequest:fetchRequest withContext:self error:error];
   }
   
   for(NSPersistentStore *genericStore in affectedStores){
    if([genericStore isKindOfClass:[NSIncrementalStore class]]){
     NSArray *fetched=[(NSIncrementalStore *)genericStore executeRequest:fetchRequest withContext:self error:error];

     if(fetched==nil)
      return nil;

     for(NSManagedObject *check in fetched){
      if(![_deletedObjects containsObject:check])
       [resultSet addObject:check];
     }
     continue;
    }

    if(![genericStore isKindOfClass:[NSAtomicStore class]])
     continue;

    NSAtomicStore *store=(NSAtomicStore *)genericStore;
    NSSet *nodes=[store cacheNodes];
    
    for(NSAtomicStoreCacheNode *node in nodes){
     NSManagedObjectID   *checkID=[node objectID];
     NSEntityDescription *entity=[checkID entity];
    
     if([entity _isKindOfEntity:[fetchRequest entity]]){
      NSManagedObject *check=[self objectWithID:checkID];
      
      if(![_deletedObjects containsObject:check]){
       [resultSet addObject:check];
       }
	 }
    }
   }
   
   NSMutableArray *result=[NSMutableArray arrayWithArray:[resultSet allObjects]];

   NSPredicate *p=[fetchRequest predicate];
   
   if(p!=nil)
    [result filterUsingPredicate:p];

   [result sortUsingDescriptors:[fetchRequest sortDescriptors]];
 
   return result;
}

-(NSUInteger)countForFetchRequest:(NSFetchRequest *)request error:(NSError **)error {
   return [[self executeFetchRequest:request error:error] count];
}

-(void)insertObject:(NSManagedObject *)object {
   NSPersistentStore *store=[_storeCoordinator _persistentStoreForObject:object];
   
   [[object objectID] setStoreIdentifier:[store identifier]];
   [[object objectID] setPersistentStore:store];

   [_insertedObjects addObject:object];
   [_updatedObjects addObject:object];
   [self _registerObject:object];
}

-(void)deleteObject:(NSManagedObject *)object {
   /* Apple re-invokes the callback each time deleteObject: is called,
      even when the object is already marked for deletion. */
   [object prepareForDeletion];

   [_deletedObjects addObject:object];
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
   if(NSMapGet(_objectIdToObject,[object objectID])==object)
    [_updatedObjects addObject:object];
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
