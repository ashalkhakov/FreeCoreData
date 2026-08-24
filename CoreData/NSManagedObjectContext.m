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
#import <CoreData/NSExpressionDescription.h>
#import <CoreData/NSAtomicStoreCacheNode.h>
#import <Foundation/NSExpression.h>
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

/* The object a havingPredicate is evaluated against.  Column keys
   (grouped columns and expression-description names) answer with the
   assembled row's value; any other key path answers with the array of
   that key path's non-null values across the group's rows, so an
   aggregate expression in the predicate - Apple's required form,
   count:(name) > 1 - computes over the group exactly like SQL's
   HAVING COUNT(name). */
@interface CDGroupRow : NSObject {
   NSDictionary *_row;
   NSArray      *_group;
}
@end

@implementation CDGroupRow

-initWithRow:(NSDictionary *)row group:(NSArray *)group {
   _row=[row retain];
   _group=[group retain];
   return self;
}

-(void)dealloc {
   [_row release];
   [_group release];
   [super dealloc];
}

-(id)valueForKey:(NSString *)key {
   id value=[_row objectForKey:key];

   if(value!=nil)
    return value;

   NSMutableArray *values=[NSMutableArray array];

   for(NSDictionary *snapshot in _group){
    id snapshotValue=[snapshot valueForKey:key];

    if(snapshotValue!=nil && snapshotValue!=[NSNull null])
     [values addObject:snapshotValue];
   }
   return values;
}

@end

@implementation NSManagedObjectContext

-init {
   _lock=[[NSLock alloc] init];
   _storeCoordinator=nil;
   /* No undo manager by default, matching Apple since macOS 10.12 /
      iOS: undo support costs a pre-change snapshot per mutation, so it
      is opt-in via -setUndoManager:. */
   _undoManager=nil;
   _undoEventOldValues=NSCreateMapTable(NSObjectMapKeyCallBacks,NSObjectMapValueCallBacks,0);
   _undoEventInserted=[[NSMutableArray alloc] init];
   _undoEventDeleted=[[NSMutableArray alloc] init];
   _undoRegistrationDisabled=0;
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

   /* Undo operations target this context; leaving them behind would let
      the undo manager message a deallocated object. */
   [_undoManager removeAllActionsWithTarget:self];

   [_storeCoordinator release];
   [_undoManager release];
   NSFreeMapTable(_undoEventOldValues);
   [_undoEventInserted release];
   [_undoEventDeleted release];
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
   if(value==_undoManager)
    return;

   /* Operations already registered target this context and would apply
      stale state if replayed by an orphaned manager. */
   [_undoManager removeAllActionsWithTarget:self];
   [self _clearUndoEventCapture];

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
   [self processPendingChanges];
   [_undoManager undo];
}


-(void)redo {
   [self processPendingChanges];
   [_undoManager redo];
}


-(void)reset {
   /* Registered undo operations reference objects this context is about
      to forget.  removeAllActions (not just ...WithTarget:) also clears
      the automatic event group NSUndoManager holds open between run
      loop turns. */
   [_undoManager removeAllActions];
   [self _clearUndoEventCapture];

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
   /* Apple documents -rollback as removing EVERYTHING from the undo
      stack (removeAllActions, which also clears the automatic event
      group held open between run loop turns). */
   [_undoManager removeAllActions];
   [self _clearUndoEventCapture];

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

/* --- NSDictionaryResultType shaping ------------------------------- */

enum {
   CDColumnAttribute,
   CDColumnRelationship,
   CDColumnExpression,
   CDColumnAggregate
};

static NSString *CDStrippedFunctionName(NSString *name){
   return [name hasSuffix:@":"]?[name substringToIndex:[name length]-1]:name;
}

/* Recognizes count:/sum:/min:/max:/average: over a single key path;
   returns the canonical function name and the key path, or nil. */
static NSString *CDAggregateFunction(NSExpression *expression,NSString **keyPathOut){
   if([expression expressionType]!=NSFunctionExpressionType)
    return nil;

   NSString *name=CDStrippedFunctionName([expression function]);

   if([name isEqualToString:@"avg"])
    name=@"average";
   if(!([name isEqualToString:@"count"] || [name isEqualToString:@"sum"] ||
        [name isEqualToString:@"min"] || [name isEqualToString:@"max"] ||
        [name isEqualToString:@"average"]))
    return nil;

   NSArray *arguments=[expression arguments];

   if([arguments count]!=1 ||
      [(NSExpression *)[arguments objectAtIndex:0] expressionType]!=NSKeyPathExpressionType)
    return nil;

   if(keyPathOut!=NULL)
    *keyPathOut=[[arguments objectAtIndex:0] keyPath];
   return name;
}

/* A relationship value in a snapshot may be a managed object (committed
   values), a cache node (atomic property caches), or already an object
   ID; dictionary rows carry the object ID, as on Apple. */
static id CDObjectIDFromRelationshipValue(id value){
   if([value isKindOfClass:[NSManagedObjectID class]])
    return value;
   if([value isKindOfClass:[NSManagedObject class]])
    return [(NSManagedObject *)value objectID];
   if([value isKindOfClass:[NSAtomicStoreCacheNode class]])
    return [(NSAtomicStoreCacheNode *)value objectID];
   return nil;
}

static id CDSnapshotValueForKeyPath(NSDictionary *snapshot,NSString *keyPath){
   id value=[snapshot valueForKeyPath:keyPath];

   return (value==[NSNull null])?nil:value;
}

static id CDAggregateValue(NSString *function,NSString *keyPath,NSArray *snapshots){
   NSMutableArray *values=[NSMutableArray array];

   for(NSDictionary *snapshot in snapshots){
    id value=CDSnapshotValueForKeyPath(snapshot,keyPath);

    if(value!=nil)
     [values addObject:value];
   }

   if([function isEqualToString:@"count"])
    return [NSNumber numberWithUnsignedInteger:[values count]];
   if([values count]==0)
    return nil;
   if([function isEqualToString:@"sum"])
    return [values valueForKeyPath:@"@sum.self"];
   if([function isEqualToString:@"min"])
    return [values valueForKeyPath:@"@min.self"];
   if([function isEqualToString:@"max"])
    return [values valueForKeyPath:@"@max.self"];
   if([function isEqualToString:@"average"])
    return [values valueForKeyPath:@"@avg.self"];
   return nil;
}

/* YES when the request's dictionary shaping goes beyond plain attribute
   columns - grouping, a having filter, expression columns, or
   relationship columns - and must therefore be done by the context
   rather than passed through to a store. */
-(BOOL)_dictionaryRequestNeedsContextShaping:(NSFetchRequest *)request {
   if([[request propertiesToGroupBy] count]>0 || [request havingPredicate]!=nil)
    return YES;

   for(id property in [request propertiesToFetch]){
    if([property isKindOfClass:[NSExpressionDescription class]] ||
       [property isKindOfClass:[NSRelationshipDescription class]])
     return YES;
    if([property isKindOfClass:[NSString class]] &&
       [[[request entity] relationshipsByName] objectForKey:property]!=nil)
     return YES;
   }
   return NO;
}

/* Builds NSDictionaryResultType rows from saved snapshots (cache-node
   property caches or committed-value dictionaries).

   Columns come from propertiesToFetch - attribute names or
   descriptions, to-one relationships (the row carries the related
   object's ID), and NSExpressionDescriptions (the row carries the
   expression's value under the description's name; aggregates
   [count:/sum:/min:/max:/average: of a key path] compute over the
   row group).  A to-many relationship column raises, as on Apple.
   With no propertiesToFetch, every attribute of the entity is a
   column.

   When propertiesToGroupBy is set the snapshots are grouped by those
   values and one row per group is returned; havingPredicate then
   filters the assembled rows ("the predicate will be run after",
   requiring propertiesToGroupBy).  Aggregate columns with no grouping
   collapse everything into a single row.  Otherwise one row per
   snapshot, with returnsDistinctResults collapsing equal rows in
   order.  Rows here are unwindowed - the caller applies
   fetchOffset/fetchLimit to the returned rows, matching SQL LIMIT
   applying after grouping and DISTINCT. */
-(NSArray *)_dictionaryResultsForRequest:(NSFetchRequest *)request snapshots:(NSArray *)snapshots {
   NSMutableArray *columnNames=[NSMutableArray array];
   NSMutableArray *columnKinds=[NSMutableArray array];
   NSMutableArray *columnExpressions=[NSMutableArray array]; /* NSNull for non-expression columns */
   NSArray        *properties=[request propertiesToFetch];
   NSDictionary   *relationships=[[request entity] relationshipsByName];
   BOOL            hasAggregates=NO;

   if([properties count]>0){
    for(id property in properties){
     if([property isKindOfClass:[NSExpressionDescription class]]){
      NSExpression *expression=[(NSExpressionDescription *)property expression];
      NSString     *aggregateKeyPath=nil;
      BOOL          aggregate=(CDAggregateFunction(expression,&aggregateKeyPath)!=nil);

      [columnNames addObject:[(NSExpressionDescription *)property name]];
      [columnKinds addObject:[NSNumber numberWithInt:aggregate?CDColumnAggregate:CDColumnExpression]];
      [columnExpressions addObject:expression];
      if(aggregate)
       hasAggregates=YES;
      continue;
     }

     NSString *name=[property isKindOfClass:[NSString class]]?property:[(NSPropertyDescription *)property name];
     NSRelationshipDescription *relationship=[relationships objectForKey:name];

     if(relationship!=nil){
      if([relationship isToMany])
       [NSException raise:NSInvalidArgumentException
                   format:@"Invalid to-many relationship in setPropertiesToFetch: (%@)",name];
      [columnNames addObject:name];
      [columnKinds addObject:[NSNumber numberWithInt:CDColumnRelationship]];
      [columnExpressions addObject:[NSNull null]];
      continue;
     }

     [columnNames addObject:name];
     [columnKinds addObject:[NSNumber numberWithInt:CDColumnAttribute]];
     [columnExpressions addObject:[NSNull null]];
    }
   }
   else {
    for(NSString *name in [[[[request entity] attributesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)]){
     [columnNames addObject:name];
     [columnKinds addObject:[NSNumber numberWithInt:CDColumnAttribute]];
     [columnExpressions addObject:[NSNull null]];
    }
   }

   /* Group membership: each element of groups is the array of snapshots
      the row is built from - one group per distinct groupBy tuple, one
      group per snapshot without grouping, or a single all-rows group
      for ungrouped aggregates. */
   NSArray *groupBy=[request propertiesToGroupBy];
   NSMutableArray *groups=[NSMutableArray array];

   if([groupBy count]>0){
    NSMutableArray *groupKeys=[NSMutableArray array]; /* parallel, first-seen order */

    for(NSDictionary *snapshot in snapshots){
     NSMutableArray *key=[NSMutableArray array];

     for(id property in groupBy){
      id value=nil;

      if([property isKindOfClass:[NSExpressionDescription class]])
       value=[[(NSExpressionDescription *)property expression] expressionValueWithObject:snapshot context:nil];
      else {
       NSString *name=[property isKindOfClass:[NSString class]]?property:[(NSPropertyDescription *)property name];

       value=CDSnapshotValueForKeyPath(snapshot,name);
      }
      [key addObject:(value!=nil)?value:[NSNull null]];
     }

     NSUInteger index=[groupKeys indexOfObject:key];

     if(index==NSNotFound){
      [groupKeys addObject:key];
      [groups addObject:[NSMutableArray arrayWithObject:snapshot]];
     }
     else
      [[groups objectAtIndex:index] addObject:snapshot];
    }
   }
   else if(hasAggregates)
    [groups addObject:snapshots];
   else {
    for(NSDictionary *snapshot in snapshots)
     [groups addObject:[NSArray arrayWithObject:snapshot]];
   }

   NSPredicate    *having=[request havingPredicate];
   NSMutableArray *result=[NSMutableArray array];
   BOOL            perRow=([groupBy count]==0 && !hasAggregates);

   for(NSArray *group in groups){
    NSDictionary        *first=[group count]>0?[group objectAtIndex:0]:nil;
    NSMutableDictionary *row=[NSMutableDictionary dictionary];
    NSUInteger           i,count=[columnNames count];

    for(i=0;i<count;i++){
     NSString *name=[columnNames objectAtIndex:i];
     id        value=nil;

     switch([[columnKinds objectAtIndex:i] intValue]){

      case CDColumnAttribute:
       value=CDSnapshotValueForKeyPath(first,name);
       if([value isKindOfClass:[NSAtomicStoreCacheNode class]] ||
          [value isKindOfClass:[NSSet class]] || [value isKindOfClass:[NSArray class]] ||
          [value isKindOfClass:[NSManagedObjectID class]] ||
          [value isKindOfClass:[NSManagedObject class]])
        value=nil; /* stray relationship value under an attribute-style column */
       break;

      case CDColumnRelationship:
       value=CDObjectIDFromRelationshipValue([first objectForKey:name]);
       break;

      case CDColumnExpression:
       value=[[columnExpressions objectAtIndex:i] expressionValueWithObject:first context:nil];
       if(value==[NSNull null])
        value=nil;
       break;

      case CDColumnAggregate: {
       NSString *keyPath=nil;
       NSString *function=CDAggregateFunction([columnExpressions objectAtIndex:i],&keyPath);

       value=CDAggregateValue(function,keyPath,group);
       break;
      }
     }

     if(value!=nil)
      [row setObject:value forKey:name];
    }

    if(having!=nil){
     CDGroupRow *evaluationRow=[[[CDGroupRow alloc] initWithRow:row group:group] autorelease];

     if(![having evaluateWithObject:evaluationRow])
      continue;
    }
    if(perRow && [request returnsDistinctResults] && [result containsObject:row])
     continue;

    [result addObject:row];
   }

   return result;
}

/* Applies the request's object-realization options to an object-result
   array: returnsObjectsAsFaults NO realizes every returned fault, and
   relationshipKeyPathsForPrefetching is fulfilled by walking each key
   path (for incremental stores this drives newValueForRelationship
   during the fetch instead of at first access).  Used on results the
   context shaped itself; a store handling a pass-through request is
   responsible for its own options. */
-(void)_finalizeFetchedObjects:(NSArray *)objects request:(NSFetchRequest *)request {
   if([request resultType]!=NSManagedObjectResultType)
    return;

   BOOL     realize=![request returnsObjectsAsFaults];
   NSArray *keyPaths=[request relationshipKeyPathsForPrefetching];

   if(!realize && [keyPaths count]==0)
    return;

   for(NSManagedObject *object in objects){
    if(realize && [object isFault])
     [object _committedValues]; /* fires the row fault; to-many stay lazy */

    for(NSString *keyPath in keyPaths)
     [object valueForKeyPath:keyPath];
   }
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
       when a single incremental store can produce it.  Dictionary
       requests that need grouping, having, expression or relationship
       columns are shaped here instead - stores only shape plain
       attribute rows. */
    if([affectedStores count]==1 &&
       [[affectedStores objectAtIndex:0] isKindOfClass:[NSIncrementalStore class]] &&
       !(resultType==NSDictionaryResultType &&
         [self _dictionaryRequestNeedsContextShaping:fetchRequest])){
     NSArray *passed=[(NSIncrementalStore *)[affectedStores objectAtIndex:0] executeRequest:fetchRequest withContext:self error:error];

     /* Realization options are enforced here too - a store is free to
        return faults regardless of them (realizing an already-realized
        object, or re-walking a prefetched key path, is a no-op). */
     if(passed!=nil)
      [self _finalizeFetchedObjects:passed request:fetchRequest];
     return passed;
    }

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
      /* Limits apply to the union, not to each store; a store answers
         with saved state by definition, so the pending-changes flag is
         cleared on the request it sees. */
      [inner setFetchLimit:0];
      [inner setFetchOffset:0];
      [inner setIncludesPendingChanges:NO];

      NSArray *fetched=[(NSIncrementalStore *)genericStore executeRequest:inner withContext:self error:error];

      if(fetched==nil)
       return nil;

      for(NSManagedObject *check in fetched){
       [objects addObject:check];
       /* Raw row snapshot - unfired to-many faults stay unfired (the
          dictionary builder never reads to-many values). */
       [savedSnapshots addObject:[check _committedValues]];
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

    /* Dictionary rows window after shaping - grouping, DISTINCT and
       LIMIT compose in that order, as in SQL. */
    if(resultType==NSDictionaryResultType){
     NSMutableArray *rows=[NSMutableArray arrayWithArray:
      [self _dictionaryResultsForRequest:fetchRequest snapshots:savedSnapshots]];

     if(offset>0){
      if(offset>=[rows count])
       [rows removeAllObjects];
      else
       [rows removeObjectsInRange:NSMakeRange(0,offset)];
     }
     if(limit>0 && [rows count]>limit)
      [rows removeObjectsInRange:NSMakeRange(limit,[rows count]-limit)];
     return rows;
    }

    if(offset>0){
     if(offset>=[objects count])
      [objects removeAllObjects];
     else
      [objects removeObjectsInRange:NSMakeRange(0,offset)];
    }
    if(limit>0 && [objects count]>limit)
     [objects removeObjectsInRange:NSMakeRange(limit,[objects count]-limit)];

    switch(resultType){

     case NSManagedObjectIDResultType: {
      NSMutableArray *ids=[NSMutableArray array];

      for(NSManagedObject *object in objects)
       [ids addObject:[object objectID]];
      return ids;
     }

     case NSCountResultType:
      return [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:[objects count]]];

     default:
      [self _finalizeFetchedObjects:objects request:fetchRequest];
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
     [inner setIncludesPendingChanges:NO];

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
     if(![fetchRequest includesSubentities] &&
        ![[nodeEntity name] isEqualToString:[[fetchRequest entity] name]])
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
    if(![fetchRequest includesSubentities] &&
       ![[[check entity] name] isEqualToString:[[fetchRequest entity] name]])
     continue;
    if(![affectedStores containsObject:[[check objectID] persistentStore]])
     continue;
    /* Membership of pending objects is decided with their in-memory
       values; a relationship key path in the predicate can fire faults
       here, as it does on Apple ("changes are evaluated in memory"). */
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
     /* Sorted like the object fetch.  (Apple does not reliably sort
        the overlay-only portion of an ID fetch - the port's fully
        sorted answer is a deliberate divergence inside behavior Apple
        leaves unspecified; do not rely on Apple-identical ID order.) */
     NSMutableArray *ids=[NSMutableArray array];

     for(NSManagedObject *object in overlaid)
      [ids addObject:[object objectID]];
     return ids;
    }

    case NSCountResultType:
     return [NSArray arrayWithObject:[NSNumber numberWithUnsignedInteger:[overlaid count]]];

    default:
     [self _finalizeFetchedObjects:overlaid request:fetchRequest];
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

   [self _noteObjectInsertedForUndo:object];

   [_pendingInsertedObjects addObject:object];
   [_pendingDeletedObjects removeObject:object];
   [self _requestProcessPendingChanges];
}

-(void)deleteObject:(NSManagedObject *)object {
   /* Apple re-invokes the callback each time deleteObject: is called,
      even when the object is already marked for deletion. */
   [object prepareForDeletion];

   if(![_deletedObjects containsObject:object])
    [self _noteObjectDeletedForUndo:object];

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
	/* Concrete mode names rather than NSRunLoopCommonModes: GNUstep's
	   run loop performers match mode strings literally (the constant
	   exists but nothing expands it), so a performer filed under the
	   "common modes" pseudo-mode never fires and pending-change
	   processing (change notifications, undo registration) is deferred
	   until the next explicit -processPendingChanges, typically the
	   save.  The AppKit modes are spelled as literals to keep CoreData
	   off AppKit.  (Reported by UDQuakeTools.) */
	[runLoop performSelector: @selector(_processPendingChangesForRequest)
		 target: self
		 argument: nil
		 order: 0
		 modes: [NSArray arrayWithObjects:
		            NSDefaultRunLoopMode,
		            @"NSModalPanelRunLoopMode",
		            @"NSEventTrackingRunLoopMode",
		            nil]];
	_requestedProcessPendingChanges = YES;
   }
}

-(void)_processPendingChanges {
    _requestedProcessPendingChanges = NO;

    /* Undo registration happens at event granularity, before the early
       return: an insert-then-delete of the same object nets out of the
       pending sets but must still be captured (its undo resurrects and
       re-removes, arriving back at nothing). */
    [self _registerUndoEventIfNeeded];

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

/* --- undo support -------------------------------------------------- */

/* Values held for the undo manager: primitive relationship collections
   are mutated in place by inverse maintenance, so they are copied on
   capture and again on restore; attribute values are retained as-is.
   nil is boxed as NSNull. */
static id CDUndoCapturedValue(id value){
   if(value==nil)
    return [NSNull null];
   if([value isKindOfClass:[NSSet class]] || [value isKindOfClass:[NSArray class]])
    return [[value mutableCopy] autorelease];
   return value;
}

static id CDUndoRestoredValue(id value){
   if(value==(id)[NSNull null])
    return nil;
   if([value isKindOfClass:[NSSet class]] || [value isKindOfClass:[NSArray class]])
    return [[value mutableCopy] autorelease];
   return value;
}

-(void)_clearUndoEventCapture {
   NSResetMapTable(_undoEventOldValues);
   [_undoEventInserted removeAllObjects];
   [_undoEventDeleted removeAllObjects];
}

-(void)_disableUndoRegistration {
   _undoRegistrationDisabled++;
}

-(void)_enableUndoRegistration {
   _undoRegistrationDisabled--;
}

/* Called by NSManagedObject BEFORE a modeled property changes.  The
   first change to each (object, key) in an event wins: the recorded
   value is the property's value at the event boundary, which is what
   undoing the event must restore. */
-(void)_object:(NSManagedObject *)object willChangeValueForKey:(NSString *)key {
   if(_undoManager==nil || _undoRegistrationDisabled>0)
    return;
   if(NSMapGet(_objectIdToObject,[object objectID])!=object)
    return;
   if([[[object entity] propertiesByName] objectForKey:key]==nil)
    return;

   NSMutableDictionary *byKey=NSMapGet(_undoEventOldValues,object);

   if(byKey==nil){
    byKey=[NSMutableDictionary dictionary];
    NSMapInsert(_undoEventOldValues,object,byKey);
   }
   if([byKey objectForKey:key]==nil)
    [byKey setObject:CDUndoCapturedValue([object primitiveValueForKey:key]) forKey:key];
}

-(void)_noteObjectInsertedForUndo:(NSManagedObject *)object {
   if(_undoManager==nil || _undoRegistrationDisabled>0)
    return;
   if(![_undoEventInserted containsObject:object])
    [_undoEventInserted addObject:object];
}

-(void)_noteObjectDeletedForUndo:(NSManagedObject *)object {
   if(_undoManager==nil || _undoRegistrationDisabled>0)
    return;

   /* Snapshot every primitive so the object can be resurrected even
      after the deletion has been saved (when its row is gone). */
   NSMutableDictionary *snapshot=[NSMutableDictionary dictionary];

   for(NSString *key in [[object entity] propertiesByName])
    [snapshot setObject:CDUndoCapturedValue([object primitiveValueForKey:key]) forKey:key];

   [_undoEventDeleted addObject:[NSDictionary dictionaryWithObjectsAndKeys:
       object,@"object",
       snapshot,@"snapshot",
       [NSNumber numberWithBool:[_insertedObjects containsObject:object]],@"wasInserted",
       nil]];
}

/* One undo operation per change event, registered by
   -_processPendingChanges.  Undoing resurrects the event's deletions,
   restores the event's pre-change values, and removes the event's
   insertions.  Every step goes back through the normal change paths, so
   the redo operation is captured the same way and NSUndoManager files
   it on the redo stack. */
-(void)_registerUndoEventIfNeeded {
   if(_undoManager==nil)
    return;
   if(NSCountMapTable(_undoEventOldValues)==0 &&
      [_undoEventInserted count]==0 && [_undoEventDeleted count]==0)
    return;

   NSMutableArray *updated=[NSMutableArray array];
   NSMapEnumerator state=NSEnumerateMapTable(_undoEventOldValues);
   void *mapKey,*mapValue;

   while(NSNextMapEnumeratorPair(&state,&mapKey,&mapValue))
    [updated addObject:[NSDictionary dictionaryWithObjectsAndKeys:
        (NSManagedObject *)mapKey,@"object",
        (NSMutableDictionary *)mapValue,@"values",
        nil]];
   NSEndMapTableEnumeration(&state);

   NSDictionary *event=[NSDictionary dictionaryWithObjectsAndKeys:
       updated,@"updated",
       [[_undoEventInserted copy] autorelease],@"inserted",
       [[_undoEventDeleted copy] autorelease],@"deleted",
       nil];

   [_undoManager registerUndoWithTarget:self
                               selector:@selector(_undoApplyEvent:)
                                 object:event];
   [self _clearUndoEventCapture];
}

-(void)_undoApplyEvent:(NSDictionary *)event {
   /* Resurrect deletions first so value restores may reference the
      objects again. */
   for(NSDictionary *record in [event objectForKey:@"deleted"]){
    NSManagedObject *object=[record objectForKey:@"object"];
    BOOL             wasInserted=[[record objectForKey:@"wasInserted"] boolValue];

    if(NSMapGet(_objectIdToObject,[object objectID])!=object){
     /* The deletion was saved and the object dropped from the object
        map: bring it back as a fresh insertion carrying its old values.
        A save leaves the KVO observations of deleted objects in place
        (they are balanced out in dealloc via _registeredObjects), so
        when the object is still in _registeredObjects only the
        bookkeeping is redone - _registerObject would observe it twice. */
     if([_registeredObjects containsObject:object]){
      NSPersistentStore *store=[_storeCoordinator _persistentStoreForObject:object];

      [[object objectID] setStoreIdentifier:[store identifier]];
      [[object objectID] setPersistentStore:store];
      NSMapInsert(_objectIdToObject,[object objectID],object);
      [_insertedObjects addObject:object];
      [_updatedObjects addObject:object];
      [self _noteObjectInsertedForUndo:object];
      [_pendingInsertedObjects addObject:object];
      [self _requestProcessPendingChanges];
     }
     else
      [self insertObject:object];

     NSDictionary *snapshot=[record objectForKey:@"snapshot"];

     for(NSString *key in snapshot){
      [object willChangeValueForKey:key];
      [object setPrimitiveValue:CDUndoRestoredValue([snapshot objectForKey:key]) forKey:key];
      [object didChangeValueForKey:key];
     }
    }
    else {
     /* Unsaved deletion: the object still holds its values - just
        unmark it.  Recorded as an insertion for the redo operation, so
        redo deletes it again. */
     [_deletedObjects removeObject:object];
     [_pendingDeletedObjects removeObject:object];

     if(wasInserted){
      [_insertedObjects addObject:object];
      [_pendingInsertedObjects addObject:object];
     }
     else
      [_pendingUpdatedObjects addObject:object];

     [self _noteObjectInsertedForUndo:object];
     [self _requestProcessPendingChanges];
    }
   }

   for(NSDictionary *record in [event objectForKey:@"updated"]){
    NSManagedObject *object=[record objectForKey:@"object"];
    NSDictionary    *values=[record objectForKey:@"values"];

    for(NSString *key in values){
     [object willChangeValueForKey:key];
     [object setPrimitiveValue:CDUndoRestoredValue([values objectForKey:key]) forKey:key];
     [object didChangeValueForKey:key];
    }
   }

   for(NSManagedObject *object in [[event objectForKey:@"inserted"] reverseObjectEnumerator]){
    /* An "inserted" record covers two cases.  A never-saved object (it
       is still insert-pending) is forgotten outright: after undoing its
       insertion the context reports no inserted OR deleted objects, as
       if it had never existed.  An object whose insertion record stems
       from resurrecting an unsaved deletion (redo of a delete) has a
       persisted row, so it must become deletion-pending instead.
       deleteObject: first, so the inverse operation resurrects it
       either way. */
    BOOL neverSaved=[_insertedObjects containsObject:object];

    [self deleteObject:object];

    if(neverSaved){
     NSArray *properties=[[[object entity] propertiesByName] allKeys];

     for(NSString *key in properties)
      [object removeObserver:self forKeyPath:key];

     [_registeredObjects removeObject:object];
     [_insertedObjects removeObject:object];
     [_updatedObjects removeObject:object];
     [_deletedObjects removeObject:object];
     [_pendingInsertedObjects removeObject:object];
     [_pendingUpdatedObjects removeObject:object];
     [_pendingDeletedObjects removeObject:object];
     NSMapRemove(_objectIdToObject,[object objectID]);
    }
   }

   /* Flush now, while the undo manager is still undoing/redoing, so the
      inverse operation registered above lands on the correct stack. */
   [self processPendingChanges];
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
