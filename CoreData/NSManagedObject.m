/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSManagedObject.h>
#import "NSManagedObjectID-Private.h"
#import "NSManagedObject-Private.h"
#import "NSManagedObjectContext-Private.h"
#import "NSEntityDescription-Private.h"
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import <CoreData/CoreDataErrors.h>
#import <Foundation/NSError.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSException.h>
#import <CoreData/NSAtomicStoreCacheNode.h>
#import <CoreData/NSIncrementalStore.h>
#import <CoreData/NSIncrementalStoreNode.h>
#import "CoreDataUtilities.h"
#import "NSManagedObjectSet.h"
#import "NSManagedObjectSetEnumerator.h"
#import "NSManagedObjectMutableSet.h"

/* Placeholder stored under a to-many key in _committedValues while the
   relationship is still a fault.  To-many relationships cost their
   newValueForRelationship: round trip only when actually accessed
   (matching Apple - no N+1 while merely browsing rows); to-one
   relationships are part of the row snapshot and resolve while the row
   fault fires (also matching Apple - see
   _committedValuesFromIncrementalStore:).  Resolved and replaced by
   -primitiveValueForKey:. */
@interface CDRelationshipFault : NSObject {
   NSRelationshipDescription *_relationship;
}
-(NSRelationshipDescription *)relationship;
@end

@implementation CDRelationshipFault

-initWithRelationship:(NSRelationshipDescription *)relationship {
   _relationship=[relationship retain];
   return self;
}

-(void)dealloc {
   [_relationship release];
   [super dealloc];
}

-(NSRelationshipDescription *)relationship {
   return _relationship;
}

@end

/* Mutable proxy handed out by -mutableOrderedSetValueForKey:.  Like
   NSManagedObjectMutableSet it goes through the public accessors on
   every operation (copy, mutate, set back), so change tracking and
   inverse maintenance happen exactly as for -setValue:forKey:. */
@interface CDManagedObjectMutableOrderedSet : NSMutableOrderedSet {
   NSManagedObject *_object;
   NSString        *_key;
}
@end

@implementation CDManagedObjectMutableOrderedSet

-initWithManagedObject:(NSManagedObject *)object key:(NSString *)key {
   _object=[object retain];
   _key=[key copy];
   return self;
}

-(void)dealloc {
   [_object release];
   [_key release];
   [super dealloc];
}

-(NSOrderedSet *)_current {
   /* Read through the PRIMITIVE value (an array of object IDs) rather
      than -valueForKey:, which hands out this proxy itself - the live
      view must not recurse into itself. */
   NSMutableOrderedSet *resolved=[NSMutableOrderedSet orderedSet];
   NSManagedObjectContext *context=[_object managedObjectContext];

   /* By ID, as the framework keeps it - or, inside a custom setter that
      stored objects, until -setValue:forKey: has made them IDs (see
      there), as objects. */
   for(id member in [_object primitiveValueForKey:_key])
    [resolved addObject:[member isKindOfClass:[NSManagedObject class]]?member:[context objectWithID:member]];
   return resolved;
}

-(NSUInteger)count {
   return [[self _current] count];
}

-objectAtIndex:(NSUInteger)index {
   return [[self _current] objectAtIndex:index];
}

-(NSUInteger)indexOfObject:object {
   return [[self _current] indexOfObject:object];
}

-(NSEnumerator *)objectEnumerator {
   return [[self _current] objectEnumerator];
}

-(NSEnumerator *)reverseObjectEnumerator {
   return [[self _current] reverseObjectEnumerator];
}

-(void)insertObject:object atIndex:(NSUInteger)index {
   NSMutableOrderedSet *ordered=[[self _current] mutableCopy];

   [ordered insertObject:object atIndex:index];
   [_object _setModeledValue:ordered forKey:_key];
   [ordered release];
}

-(void)removeObjectAtIndex:(NSUInteger)index {
   NSMutableOrderedSet *ordered=[[self _current] mutableCopy];

   [ordered removeObjectAtIndex:index];
   [_object _setModeledValue:ordered forKey:_key];
   [ordered release];
}

-(void)replaceObjectAtIndex:(NSUInteger)index withObject:object {
   NSMutableOrderedSet *ordered=[[self _current] mutableCopy];

   [ordered replaceObjectAtIndex:index withObject:object];
   [_object _setModeledValue:ordered forKey:_key];
   [ordered release];
}

@end

@interface NSManagedObject (CDRelationshipFaultResolution)
-(id)_resolveRelationshipFault:(CDRelationshipFault *)fault forKey:(NSString *)key;
@end

@implementation NSManagedObject

-init {
   NSLog(@"Error - can't initialize an NSManagedObject with -init");
   return nil;
}

-initWithObjectID:(NSManagedObjectID *)objectID managedObjectContext:(NSManagedObjectContext *)context {
   NSEntityDescription *entity=[objectID entity];
   NSString            *className=[entity managedObjectClassName];
   Class                class=NSClassFromString(className);
 
   if(class==Nil){
    NSLog(@"Unable to find class %@ specified by entity %@ in the runtime, using NSManagedObject,objectID=%@",className,[entity name],objectID);
    
    class=[NSManagedObject class];
   }
   
   [super dealloc];
   self=[class allocWithZone:NULL];
   
   _objectID=[objectID copy];
   _context=context;
   _committedValues = nil;
   /* Made at the first change (-_changes): most objects a fetch brings
      are only read. */
   _changedValues = nil;
   _isFault=YES;
   return self;
}

-initWithEntity:(NSEntityDescription *)entity insertIntoManagedObjectContext:(NSManagedObjectContext *)context {
   NSManagedObjectID *objectID=[[[NSManagedObjectID alloc] initWithEntity:entity] autorelease];
   
   if((self=[self initWithObjectID:objectID managedObjectContext:context])==nil)
    return nil;

   NSDictionary *attributes=[entity attributesByName];
   NSEnumerator *state=[attributes keyEnumerator];
   NSString     *key;
   
   while((key=[state nextObject])!=nil){
    id object=[attributes objectForKey:key];
    id value=[object defaultValue];
    
    if(value!=nil)
     [self setPrimitiveValue:value forKey:key]; 
   }

   [context insertObject:self];

   _isFault=NO;

   [self awakeFromInsert];

   return self;
}

/* What changed, made when first needed. */
-(NSMutableDictionary *)_changes {
   if(_changedValues==nil)
    _changedValues=[[NSMutableDictionary alloc] init];
   return _changedValues;
}

-(void)dealloc {
   [self didTurnIntoFault];
   
   [_prefetchedRow release];
   [_objectID release];
   [_committedValues release];
   [_changedValues release];
   [super dealloc];
}

/* As on Apple, identity: a context has one object for a row, and an
   inserted object's ID changes when it is saved (see _setObjectID:). */
-(NSUInteger)hash {
   return [super hash];
}

-(BOOL)isEqual:otherX {
   return otherX==self;
}

/* The permanent ID its store gave, for the temporary one it had. */
-(void)_setObjectID:(NSManagedObjectID *)objectID {
   objectID=[objectID copy];
   [_objectID release];
   _objectID=objectID;
}

/* A relationship value with each ID in replacements (temporary ID ->
   permanent ID) replaced; the value itself when it holds none. */
static id CDValueReplacingObjectIDs(id value,NSMapTable *replacements){
   if([value isKindOfClass:[NSManagedObjectID class]]){
    id replacement=NSMapGet(replacements,value);
    return (replacement!=nil)?replacement:value;
   }
   if([value isKindOfClass:[NSSet class]] || [value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSOrderedSet class]]){
    BOOL changed=NO;
    for(id member in value)
     if([member isKindOfClass:[NSManagedObjectID class]] && NSMapGet(replacements,member)!=nil){
      changed=YES;
      break;
     }
    if(!changed)
     return value;

    NSMutableArray *members=[NSMutableArray array];
    for(id member in value)
     [members addObject:CDValueReplacingObjectIDs(member,replacements)];
    if([value isKindOfClass:[NSOrderedSet class]])
     return [NSMutableOrderedSet orderedSetWithArray:members];
    if([value isKindOfClass:[NSArray class]])
     return members;
    return [NSMutableSet setWithArray:members];
   }
   return value;
}

/* Relationship values name related objects by ID: those an inserted
   object had are the permanent ones once saved. */
-(void)_replaceObjectIDs:(NSMapTable *)replacements {
   for(NSString *key in [_changedValues allKeys]){
    id value=[_changedValues objectForKey:key];
    id replaced=CDValueReplacingObjectIDs(value,replacements);
    if(replaced!=value)
     [[self _changes] setObject:replaced forKey:key];
   }
   if(_committedValues!=nil){
    NSMutableDictionary *committed=nil;
    for(NSString *key in _committedValues){
     id value=[_committedValues objectForKey:key];
     id replaced=CDValueReplacingObjectIDs(value,replacements);
     if(replaced!=value){
      if(committed==nil)
       committed=[[_committedValues mutableCopy] autorelease];
      [committed setObject:replaced forKey:key];
     }
    }
    if(committed!=nil){
     [_committedValues release];
     _committedValues=[committed copy];
    }
   }
}

-(NSEntityDescription *)entity {
   return [_objectID entity];
}

-(NSManagedObjectID *)objectID {
   return _objectID;
}

-self {
   return self;
}

-(NSManagedObjectContext *)managedObjectContext {
   return _context;
}

-(BOOL)isInserted {
   return [_context _hasInsertedObject:self];
}

-(BOOL)isUpdated {
   return [_context _hasUpdatedObject:self] && ![_context _hasInsertedObject:self];
}

-(BOOL)isDeleted {
   return [_context _hasDeletedObject:self];
}

-(BOOL)hasChanges {
   return [self isInserted] || [self isDeleted] || [self isUpdated] ||
          [_changedValues count]>0;
}

-(BOOL)isFault {
   return _isFault;
}

-(void)_setFault:(BOOL)isFault {
   _isFault=isFault;
   /* Turned into a fault again (refreshed): read again, not from a fetch. */
   if(isFault){
    [_prefetchedRow release];
    _prefetchedRow=nil;
   }
}

/* As Apple's row cache keeps a row while an object holds it: the object
   holds it, and it goes with the object. */
-(void)_holdPrefetchedRow:(NSIncrementalStoreNode *)row generation:(unsigned long long)generation {
   if(!_isFault)
    return;
   [row retain];
   [_prefetchedRow release];
   _prefetchedRow=row;
   _prefetchedGeneration=generation;
}

- (BOOL) hasFaultForRelationshipNamed:(NSString *) key {
    if(_isFault)
     return YES;
    if([_changedValues objectForKey:key]!=nil)
     return NO;
    return [[_committedValues objectForKey:key]
               isKindOfClass:[CDRelationshipFault class]];
}

- (void) awakeFromFetch {
}

- (void) awakeFromInsert {
}

- (void) prepareForDeletion {
}

/* Persistent properties only, matching Apple's documentation and its
   behavior (Mac-arbitrated): a transient change dirties the object -
   -hasChanges says so - but is never reported here. */
/* An object's ID, or the ID itself: a pending relationship value may
   hold either. */
static id CDIDOf(id objectOrID){
   return [objectOrID isKindOfClass:[NSManagedObject class]]?[objectOrID objectID]:objectOrID;
}

/* Whether value, the pending change of property, is the value saved:
   a to-one as its object's ID, a to-many as the IDs of its members.  An
   unfired to-many is not fired to tell, so a change to it counts. */
static BOOL CDValueIsCommitted(NSPropertyDescription *property,id value,id committed){
   if(committed==nil)
    committed=[NSNull null];
   if(value==[NSNull null] || committed==[NSNull null])
    return value==committed;
   if([committed isKindOfClass:[CDRelationshipFault class]])
    return NO;
   if(![property isKindOfClass:[NSRelationshipDescription class]])
    return [value isEqual:committed];
   if(![(NSRelationshipDescription *)property isToMany])
    return [CDIDOf(value) isEqual:committed];

   if([(NSRelationshipDescription *)property isOrdered]){
    NSMutableArray *ids=[NSMutableArray arrayWithCapacity:[value count]];

    for(id member in value)
     [ids addObject:CDIDOf(member)];
    return [ids isEqual:([committed isKindOfClass:[NSOrderedSet class]]?[committed array]:[committed allObjects])];
   }

   NSMutableSet *ids=[NSMutableSet setWithCapacity:[value count]];

   for(id member in value)
    [ids addObject:CDIDOf(member)];
   return [ids isEqualToSet:([committed isKindOfClass:[NSSet class]]?committed:[NSSet setWithArray:[committed allObjects]])];
}

/* A value as Apple's -changedValues and -committedValuesForKeys: give it:
   a relationship's objects, not the object IDs the framework keeps them
   by (a to-many as a set, or an ordered set where it is ordered); nothing
   as NSNull. */
static id CDPublicValue(NSManagedObjectContext *context,NSPropertyDescription *property,id value){
   if(value==nil || value==[NSNull null])
    return [NSNull null];
   if(![property isKindOfClass:[NSRelationshipDescription class]])
    return value;

   NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

   if(![relationship isToMany])
    return ([value isKindOfClass:[NSManagedObjectID class]] && context!=nil)?[context objectWithID:value]:value;

   id objects=[relationship isOrdered]?(id)[NSMutableOrderedSet orderedSet]:(id)[NSMutableSet set];

   for(id member in value)
    [objects addObject:([member isKindOfClass:[NSManagedObjectID class]] && context!=nil)?[context objectWithID:member]:member];
   return objects;
}

/* The names of the persistent properties whose pending value is not the
   saved one: what -changedValues gives, without making its values
   objects - for the framework's own callers, which want only the names. */
-(NSArray *)_changedPersistentKeys {
   if([_changedValues count]==0)
    return [NSArray array];

   NSDictionary   *properties=[[self entity] propertiesByName];
   NSDictionary   *committed=[self isInserted]?nil:[self _committedValues];
   NSMutableArray *keys=[NSMutableArray arrayWithCapacity:[_changedValues count]];

   for(NSString *name in _changedValues){
    NSPropertyDescription *property=[properties objectForKey:name];

    if([property isTransient])
     continue;
    if(committed!=nil && CDValueIsCommitted(property,[_changedValues objectForKey:name],[committed objectForKey:name]))
     continue;
    [keys addObject:name];
   }
   return keys;
}

-(NSDictionary *)changedValues {
   NSDictionary        *properties=[[self entity] propertiesByName];
   NSMutableDictionary *changed=[NSMutableDictionary dictionary];

   for(NSString *name in [self _changedPersistentKeys])
    [changed setObject:CDPublicValue(_context,[properties objectForKey:name],[_changedValues objectForKey:name]) forKey:name];
   return changed;
}

-(BOOL)hasPersistentChangedValues {
   return [[self _changedPersistentKeys] count]>0;
}

-(NSDictionary *)_committedValuesFromIncrementalStore:(NSIncrementalStore *)store {
   NSError                *nodeError=nil;
   NSIncrementalStoreNode *node;

   /* Store round trips are serialized through the coordinator's
      recursive lock (contexts on different queues share the stores). */
   [[_context persistentStoreCoordinator] lock];
   /* The row its fetch read, unless the store has written since. */
   if(_prefetchedRow!=nil && [store respondsToSelector:@selector(_writeGeneration)] &&
      [(id<CDRowPrefetchingStore>)store _writeGeneration]==_prefetchedGeneration)
    node=[_prefetchedRow retain];
   else
    node=[store newValuesForObjectWithID:[self objectID] withContext:_context error:&nodeError];
   [_prefetchedRow release];
   _prefetchedRow=nil;
   [[_context persistentStoreCoordinator] unlock];
   /* The version these values are, for the optimistic lock of the next
      save. */
   if(node!=nil)
    _storeVersion=[node version];
   NSMutableDictionary    *storedValues=[[NSMutableDictionary alloc] init];

   /* propertiesByName includes inherited properties, [entity properties]
      does not. */
   NSArray *properties=[[[self entity] propertiesByName] allValues];

   for(NSPropertyDescription *property in properties){
    NSString *name=[property name];

    /* The store neither has nor answers for transient properties: a
       transient to-one must not cost a newValueForRelationship round
       trip against a column that does not exist, and a transient
       to-many must not be seeded as a store-backed fault.  Absent from
       the snapshot, they read as nil until set. */
    if([property isTransient])
     continue;

    if([property isKindOfClass:[NSAttributeDescription class]]){
     id value=[node valueForPropertyDescription:property];

     if(value!=nil && value!=[NSNull null])
      [storedValues setObject:value forKey:name];
    }
    else if([property isKindOfClass:[NSRelationshipDescription class]]){
     NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

     if(![relationship isToMany]){
      id value=[node valueForPropertyDescription:property];

      /* A to-one missing from the node is resolved NOW, as part of
         completing the row snapshot - Apple does the same (verified
         2026-08-22: firing a row fault whose node lacked a to-one cost
         exactly one newValueForRelationship for it).  NSNull is the
         store saying there is none, and is not asked again: Apple's
         asks nothing for it (checked on macOS 15). */
      if(value==nil){
       NSError *relationshipError=nil;

       /* A round trip like the one above, serialized the same way. */
       [[_context persistentStoreCoordinator] lock];
       value=[store newValueForRelationship:relationship forObjectWithID:[self objectID] withContext:_context error:&relationshipError];
       [[_context persistentStoreCoordinator] unlock];
       [value autorelease];
      }

      if(value!=nil && value!=[NSNull null])
       [storedValues setObject:value forKey:name];
     }
     else {
      /* To-many relationships stay faults while the row loads - one
         newValueForRelationship: round trip happens on first ACCESS,
         not here (matching Apple's laziness; avoids N+1 fetches). */
      CDRelationshipFault *fault=[[CDRelationshipFault alloc] initWithRelationship:relationship];

      [storedValues setObject:fault forKey:name];
      [fault release];
     }
    }
   }

   [node release];

   return storedValues;
}

-(NSDictionary *)_committedValues {

   /* Values already realized or seeded (a child context seeds them
      after saving into its parent) win over every lazy source. */
   if(_committedValues!=nil)
    return _committedValues;

   /* A child context realizes committed values from its PARENT's
      current state, exactly as a root context realizes them from a
      store; the recursion bottoms out at the root.  A temporary-ID
      object the parent has never seen is an unsaved local insert:
      nothing committed. */
   {
    NSManagedObjectContext *parent=[_context parentContext];

    if(parent!=nil){
     NSManagedObjectID *oid=[self objectID];

     if([oid isTemporaryID]){
      __block BOOL parentKnowsIt=NO;

      [parent _performAsChainMemberAndWait:^{
        parentKnowsIt=([parent objectRegisteredForID:oid]!=nil);
       }];
      if(!parentKnowsIt)
       return nil;
     }

     __block NSDictionary *snapshot=nil;

     [parent _performAsChainMemberAndWait:^{
       NSManagedObject *local=[parent objectWithID:oid];

       snapshot=[[local _snapshotOfCurrentValuesChangedOnly:NO] retain];
      }];
     [snapshot autorelease];

     NSMutableDictionary *storedValues=[[NSMutableDictionary alloc] init];

     for(NSString *key in snapshot){
      id value=[snapshot objectForKey:key];

      if(value!=[NSNull null])
       [storedValues setObject:value forKey:key];
     }
     _committedValues=storedValues;

     if(_isFault){
      _isFault=NO;
      [_context _disableUndoRegistration];
      [self awakeFromFetch];
      [_context _enableUndoRegistration];
     }
     return _committedValues;
    }
   }

   if([[self objectID] isTemporaryID])
    return nil;
    
   if(_committedValues==nil){
    NSPersistentStore *store=[[self objectID] persistentStore];

    if([store isKindOfClass:[NSIncrementalStore class]]){
     [_committedValues release];
     _committedValues=[self _committedValuesFromIncrementalStore:(NSIncrementalStore *)store];

     if(_isFault){
      _isFault=NO;
      /* Changes made in awakeFromFetch are not undoable (Apple disables
         undo registration around it). */
      [_context _disableUndoRegistration];
      [self awakeFromFetch];
      [_context _enableUndoRegistration];
     }

     return _committedValues;
    }

    NSAtomicStoreCacheNode *node=[_context _cacheNodeForObjectID:[self objectID]];
    NSDictionary           *propertyCache=[node propertyCache];
    NSMutableDictionary    *storedValues=[[NSMutableDictionary alloc] init];
    
    /* propertiesByName includes inherited properties, [entity properties]
       does not. */
    NSArray *properties=[[[self entity] propertiesByName] allValues];
    
    for(NSPropertyDescription *property in properties){
     NSString *name=[property name];
     
     if([property isKindOfClass:[NSAttributeDescription class]]){
      id value=[propertyCache objectForKey:name];
      
      if(value!=nil){
       [storedValues setObject:value forKey:name];
      }
     }
     else if([property isKindOfClass:[NSRelationshipDescription class]]){
      NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;
      id                         indirectValue=[propertyCache objectForKey:name];
 
      if(indirectValue!=nil){
       id value;
             
       if(![relationship isToMany])
        value=[indirectValue objectID];
       else {
        value=[relationship isOrdered]?(id)[NSMutableArray array]:(id)[NSMutableSet set];

        for(NSAtomicStoreCacheNode *relNode in indirectValue){
         [value addObject:[relNode objectID]];
        }
       }
       
       [storedValues setObject:value forKey:name];
      }
     }
    }
    
    [_committedValues release];
    _committedValues=storedValues;

    if(_isFault){
     _isFault=NO;
     /* See the incremental-store path: awakeFromFetch changes are not
        undoable. */
     [_context _disableUndoRegistration];
     [self awakeFromFetch];
     [_context _enableUndoRegistration];
    }
   }
   return _committedValues;
}

-(NSDictionary *)_cachedCommittedValues {
   return _committedValues;
}

/* --- Nested-context value transport --------------------------------

   Canonical snapshot shape (the committed-values shape): attributes
   as plain values, to-ones as NSManagedObjectIDs, to-manys as
   NSMutableSet/NSMutableArray of IDs, NSNull for an explicit nil, an
   unfired CDRelationshipFault carried through as-is (it resolves
   against the store, which holds exactly the saved state it stands
   for).  IDs are uniqued by pointer across the whole context chain,
   so either side can resolve them. */

-(NSDictionary *)_snapshotOfCurrentValuesChangedOnly:(BOOL)changedOnly {
   NSMutableDictionary *snapshot=[NSMutableDictionary dictionary];
   NSDictionary *properties=[[self entity] propertiesByName];
   NSDictionary *committed=changedOnly?nil:[self _committedValues];

   for(NSString *name in properties){
    NSPropertyDescription *property=[properties objectForKey:name];

    if(![property isKindOfClass:[NSAttributeDescription class]] &&
       ![property isKindOfClass:[NSRelationshipDescription class]])
     continue;

    id value=[_changedValues objectForKey:name];

    if(value==nil){
     if(changedOnly)
      continue;
     value=[committed objectForKey:name];
     if(value==nil)
      continue;
    }

    if(value==[NSNull null]){
     [snapshot setObject:[NSNull null] forKey:name];
     continue;
    }
    if([value isKindOfClass:[CDRelationshipFault class]]){
     [snapshot setObject:value forKey:name];
     continue;
    }

    if([property isKindOfClass:[NSRelationshipDescription class]]){
     NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

     if(![relationship isToMany]){
      [snapshot setObject:([value isKindOfClass:[NSManagedObjectID class]]?value:[value objectID])
                   forKey:name];
     }
     else {
      id members=[relationship isOrdered]?(id)[NSMutableArray array]:(id)[NSMutableSet set];

      for(id member in value)
       [members addObject:([member isKindOfClass:[NSManagedObjectID class]]?member:[(NSManagedObject *)member objectID])];
      [snapshot setObject:members forKey:name];
     }
     continue;
    }

    [snapshot setObject:value forKey:name];
   }
   return snapshot;
}

/* Parent-side injection of a child's saved values: straight into the
   changed-values storage, in the internal representation - to-one
   values and to-many members stay NSManagedObjectIDs, exactly as
   -setValue:forKey: would store them (valueForKey: resolves IDs on
   the way out; storing resolved objects here instead put objects
   where every reader expects IDs and broke the root save).
   No KVO, no undo capture, no inverse maintenance - the child already
   maintained inverses and pushes every affected object explicitly. */
/* The key-value changes absorbing snapshot (a child's save) makes to this
   object, as its observers are to be told of them, before the values
   change: for each key whose value differs, a dictionary - its key, and
   for a to-many an NSKeyValueSetMutationKind and the objects it adds or
   removes; one that does both is a removal (with the members "between")
   and then an addition.  A value the same as this object's is no
   change, as on Apple. */
-(NSArray *)_changeNoticesForSnapshot:(NSDictionary *)snapshot {
   NSDictionary   *properties=[[self entity] propertiesByName];
   NSMutableArray *notices=[NSMutableArray array];

   for(NSString *name in snapshot){
    NSPropertyDescription *property=[properties objectForKey:name];
    id                     value=[snapshot objectForKey:name];

    if(property==nil || [value isKindOfClass:[CDRelationshipFault class]])
     continue;
    if(value==[NSNull null])
     value=nil;

    if(![property isKindOfClass:[NSRelationshipDescription class]]){
     id current=[self primitiveValueForKey:name];

     if(current!=value && ![current isEqual:value])
      [notices addObject:[NSDictionary dictionaryWithObject:name forKey:@"key"]];
     continue;
    }

    NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;
    id                         current=[self primitiveValueForKey:name];

    if(![relationship isToMany]){
     if(!(current==nil && value==nil) && ![CDIDOf(current) isEqual:value])
      [notices addObject:[NSDictionary dictionaryWithObject:name forKey:@"key"]];
     continue;
    }

    NSMutableArray *currentIDs=[NSMutableArray array];

    for(id member in current)
     [currentIDs addObject:CDIDOf(member)];

    if([relationship isOrdered]){
     if(![currentIDs isEqualToArray:([value isKindOfClass:[NSOrderedSet class]]?[value array]:[value allObjects])])
      [notices addObject:[NSDictionary dictionaryWithObject:name forKey:@"key"]];
     continue;
    }

    NSMutableSet *added=[NSMutableSet setWithArray:[value allObjects]];
    NSMutableSet *removed=[NSMutableSet setWithArray:currentIDs];

    [added minusSet:[NSSet setWithArray:currentIDs]];
    [removed minusSet:[NSSet setWithArray:[value allObjects]]];
    if([added count]==0 && [removed count]==0)
     continue;

    /* Members taken away, then members added, as Apple tells of them: a
       to-many that does both passes through its members without the
       removed ones ("between"), which the context sets first. */
    if([removed count]>0){
     NSMutableSet *objects=[NSMutableSet set];
     NSMutableSet *between=[NSMutableSet setWithArray:currentIDs];

     for(NSManagedObjectID *memberID in removed)
      [objects addObject:[_context objectWithID:memberID]];
     [between minusSet:removed];
     [notices addObject:[NSDictionary dictionaryWithObjectsAndKeys:name,@"key",[NSNumber numberWithUnsignedInteger:NSKeyValueMinusSetMutation],@"mutation",objects,@"objects",
                                                                 ([added count]>0)?(id)between:(id)[NSNull null],@"between",nil]];
    }
    if([added count]>0){
     NSMutableSet *objects=[NSMutableSet set];

     for(NSManagedObjectID *memberID in added)
      [objects addObject:[_context objectWithID:memberID]];
     [notices addObject:[NSDictionary dictionaryWithObjectsAndKeys:name,@"key",[NSNumber numberWithUnsignedInteger:NSKeyValueUnionSetMutation],@"mutation",objects,@"objects",nil]];
    }
   }
   return notices;
}

-(void)_absorbChangedValuesFromSnapshot:(NSDictionary *)snapshot {
   NSDictionary *properties=[[self entity] propertiesByName];

   for(NSString *name in snapshot){
    id value=[snapshot objectForKey:name];
    NSPropertyDescription *property=[properties objectForKey:name];

    if(value==[NSNull null]){
     [[self _changes] setObject:[NSNull null] forKey:name];
     continue;
    }
    if([value isKindOfClass:[CDRelationshipFault class]])
     continue;   /* unchanged saved state; nothing to absorb */

    if([property isKindOfClass:[NSRelationshipDescription class]]){
     NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

     if(![relationship isToMany])
      [[self _changes] setObject:value forKey:name];
     else {
      id members=[relationship isOrdered]?(id)[NSMutableArray array]:(id)[NSMutableSet set];

      for(NSManagedObjectID *memberID in value)
       [members addObject:memberID];
      [[self _changes] setObject:members forKey:name];
     }
     continue;
    }

    [[self _changes] setObject:value forKey:name];
   }
}

/* Child-side bookkeeping after saving into the parent: the given full
   snapshot (or one built now) becomes the committed base and the
   changed values are cleared - NOT invalidated, which would re-realize
   from a store that does not have this data until the root saves. */
-(void)_promoteCurrentValuesToCommitted:(NSDictionary *)fullSnapshot {
   if(fullSnapshot==nil)
    fullSnapshot=[self _snapshotOfCurrentValuesChangedOnly:NO];

   NSMutableDictionary *storedValues=[[NSMutableDictionary alloc] init];

   for(NSString *key in fullSnapshot){
    id value=[fullSnapshot objectForKey:key];

    if(value!=[NSNull null])
     [storedValues setObject:value forKey:key];
   }
   [_committedValues release];
   _committedValues=storedValues;
   [_changedValues removeAllObjects];
   _isFault=NO;
}

-(void)_invalidateCommittedValues {
   [_committedValues release];
   _committedValues=nil;
   /* Whatever is read next is the row as it then stands. */
   _storeVersion=0;
}

-(unsigned long long)_storeVersion {
   return _storeVersion;
}

-(void)_setStoreVersion:(unsigned long long)version {
   _storeVersion=version;
}

/* Post-save reset: the committed snapshot re-realizes from the store,
   which knows nothing of transient properties - their current values
   (changed if a change is pending, committed otherwise) are lifted
   out first and folded back in afterwards, so a transient attribute
   or relationship keeps its value across a save exactly as a
   persistent one does.  Values stay in the internal representation
   (relationships as object IDs), which is what the committed snapshot
   holds anyway. */
-(void)_resetCommittedValuesAfterSavePreservingTransients {
   [self _resetCommittedValuesAfterSaveFromRow:nil generation:0];
}

/* The same, from the row the store has just written, when the context
   read it with the others it saved (a store's rows read in a few
   queries, not one each); used if the store has made no write since. */
-(void)_resetCommittedValuesAfterSaveFromRow:(NSIncrementalStoreNode *)row generation:(unsigned long long)generation {
   NSDictionary        *properties=[[self entity] propertiesByName];
   NSMutableDictionary *transients=nil;

   for(NSString *name in properties){
    NSPropertyDescription *property=[properties objectForKey:name];

    if(![property isTransient])
     continue;

    id value=[_changedValues objectForKey:name];

    if(value==nil)
     value=[_committedValues objectForKey:name];
    if(value==nil || value==[NSNull null])
     continue;   /* absent and explicitly-nil both mean nil */

    if(transients==nil)
     transients=[NSMutableDictionary dictionary];
    [transients setObject:value forKey:name];
   }

   [self _discardChangedValues];
   [self _invalidateCommittedValues];
   if(row!=nil){
    [row retain];
    [_prefetchedRow release];
    _prefetchedRow=row;
    _prefetchedGeneration=generation;
   }
   [self _committedValues];

   if(transients!=nil){
    if(_committedValues==nil)
     _committedValues=[[NSMutableDictionary alloc] init];
    [(NSMutableDictionary *)_committedValues addEntriesFromDictionary:transients];
   }
}

-(void)_discardChangedValues {
   [_changedValues removeAllObjects];
}

-(NSDictionary *)committedValuesForKeys:(NSArray *)keys {
   /* As Apple's: each property asked for (every one, for nil keys) with
      its saved value - nil as NSNull, a relationship's as its objects -
      and nothing for an object never saved. */
   NSDictionary        *committed=[self _committedValues];
   NSDictionary        *properties=[[self entity] propertiesByName];
   NSMutableDictionary *result=[NSMutableDictionary dictionary];

   if(committed==nil)
    return result;

   if(keys==nil){
    /* Unfired to-many faults are omitted rather than fired - asking
       for everything must not cost one store round trip per to-many
       relationship.  (Internal callers that only need the row use
       -_committedValues directly.) */
    for(NSString *name in properties){
     NSPropertyDescription *property=[properties objectForKey:name];
     id                     value=[committed objectForKey:name];

     if([property isTransient] || [value isKindOfClass:[CDRelationshipFault class]])
      continue;
     [result setObject:CDPublicValue(_context,property,value) forKey:name];
    }
    return result;
   }

   for(NSString *key in keys){
    NSPropertyDescription *property=[properties objectForKey:key];
    id                     object=[committed objectForKey:key];

    if(property==nil)
     continue;
    /* An explicitly requested to-many fires its fault. */
    if([object isKindOfClass:[CDRelationshipFault class]])
     object=[self _resolveRelationshipFault:object forKey:key];
    [result setObject:CDPublicValue(_context,property,object) forKey:key];
   }
   return result;
}

- (void) didSave {
}

- (void) willTurnIntoFault {
}

- (void) didTurnIntoFault {
}

- (void) willSave {
}

-valueForKey:(NSString *)key {
   if(!key)
    return [self valueForUndefinedKey:nil];

   SEL selector=NSSelectorFromString(key);
   NSPropertyDescription *property=[[self entity] _propertyForSelector:selector];
   NSString *propertyName=[property name];

   /* A custom accessor implemented by the subclass (e.g. a computed
      transient property) takes precedence over the modeled storage.
      Standard KVC finds and invokes it, boxing scalar return types. */
   if(property!=nil && [self respondsToSelector:selector] &&
      !_NSManagedObjectIMPIsGeneratedAccessor([self methodForSelector:selector]))
    return [super valueForKey:key];

   if([property isKindOfClass:[NSAttributeDescription class]]){
    [self willAccessValueForKey:propertyName];
    
    id result=[self primitiveValueForKey:propertyName];
    
    [self didAccessValueForKey:propertyName];
    
    return result;
   }
   else if([property isKindOfClass:[NSRelationshipDescription class]]){
    NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

    
    [self willAccessValueForKey:propertyName];

    id result=[self primitiveValueForKey:propertyName];
    
    if(result!=nil){
     if([relationship isToMany]){
      if([relationship isOrdered]){
       /* Live mutable view, same policy as the unordered case below:
          reads track the relationship, mutations route through
          -setValue:forKey: (a detached snapshot here would let an
          NSArrayController edit a throwaway collection - accepted,
          silently lost). */
       result=[[[CDManagedObjectMutableOrderedSet alloc] initWithManagedObject:self key:propertyName] autorelease];
      }
      else
       /* Live mutable view - reads track the relationship, mutations
          route through -setValue:forKey:.  Deliberate divergence:
          Apple's faulting set accepts in-place mutation but silently
          skips inverse maintenance and change tracking; the port
          routes because GNUstep's NSArrayController mutates a bound
          contentSet in place (see NSManagedObjectSet.h). */
       result=[[[NSManagedObjectSet alloc] initWithManagedObject:self key:propertyName] autorelease];
     }
     else if(![result isKindOfClass:[NSManagedObject class]])
      /* An object, not its ID, inside a custom setter that stored one:
         -setValue:forKey: makes it an ID after (see there), but an
         observer told of the change reads it before. */
      result=[_context objectWithID:result];
    }
    
    [self didAccessValueForKey:propertyName];
    
    return result;
   }
  
   return [super valueForKey:key];
}


/* A relationship holds a row of the same context.  An object of another
   context, or one that has left its context - deleted before it was ever
   saved - is refused, as on Apple, rather than saved as a relationship to
   a row that will never exist. */
-(void)_requireSameContextAs:(id)object forRelationship:(NSString *)name {
   /* A relationship value may arrive as an object or, from the framework's
      own paths, as an object ID; only an object carries a context to
      check. */
   if(![object isKindOfClass:[NSManagedObject class]])
    return;
   if([(NSManagedObject *)object managedObjectContext]==_context)
    return;

   [NSException raise:NSInvalidArgumentException
               format:@"Illegal attempt to establish a relationship '%@' between objects in different contexts (source = %@, destination = %@)",
                      name,self,object];
}

-(void)_setManagedObjectContext:(NSManagedObjectContext *)context {
   _context=context;
}

/* A relationship's value as the framework keeps it: a to-one as its
   object's ID, a to-many as a fresh mutable set - an array when ordered -
   of its members' IDs. */
static id CDRelationshipValueByID(NSRelationshipDescription *relationship,id value){
   if(![relationship isToMany])
    return CDIDOf(value);

   if([relationship isOrdered]){
    NSMutableArray *ordered=[NSMutableArray array];

    for(id member in value)
     if(![ordered containsObject:CDIDOf(member)])
      [ordered addObject:CDIDOf(member)];
    return ordered;
   }

   NSMutableSet *set=[NSMutableSet set];

   for(id member in value)
    [set addObject:CDIDOf(member)];
   return set;
}

/* As KVC has it, and as on Apple: a modelled property whose setter the
   class implements itself is set by calling that setter - from bindings,
   an array controller, undo, -setValue:forKey: in app code - so a setter
   that does more than store the value is not bypassed.  Generated setters
   come back here and are not custom. */
-(void)setValue:value forKey:(NSString *) key {
   NSPropertyDescription *property=[[self entity] _propertyForSelector:NSSelectorFromString(key)];

   if(property!=nil && [[self entity] _hasCustomSetterForPropertyNamed:[property name]]){
    [super setValue:value forKey:key];
    return;
   }

   [self _setValue:value forKey:key property:property];
}

/* A relationship's custom setter, called directly or by -setValue:forKey:
   (NSEntityDescription.m wraps it to come here): it stores its value -
   usually with -setPrimitiveValue:forKey:, often as objects - and, as on
   Apple, the inverse is kept in step as for a generated one.  So the
   value is kept by ID afterwards, as the framework keeps it, and the
   objects it left and joined are told. */
-(void)_setValue:value forRelationshipNamed:(NSString *)name withSetter:(IMP)setter selector:(SEL)selector {
   NSRelationshipDescription *relationship=[[[self entity] propertiesByName] objectForKey:name];

   if(![relationship isKindOfClass:[NSRelationshipDescription class]]){
    ((void (*)(id,SEL,id))setter)(self,selector,value);
    return;
   }

   [self _requireSameContextAsValue:value forRelationship:relationship];

   id previous=CDRelationshipValueByID(relationship,[self primitiveValueForKey:name]);

   ((void (*)(id,SEL,id))setter)(self,selector,value);

   id stored=[_changedValues objectForKey:name];
   id current=CDRelationshipValueByID(relationship,[self primitiveValueForKey:name]);

   if(stored!=nil && stored!=[NSNull null])
    [self setPrimitiveValue:current forKey:name];

   [self _detachInverseOf:relationship from:previous];
   [self _attachInverseOf:relationship to:current];
}

-(void)_requireSameContextAsValue:value forRelationship:(NSRelationshipDescription *)relationship {
   if([relationship isToMany]){
    for(NSManagedObject *object in value)
     [self _requireSameContextAs:object forRelationship:[relationship name]];
   }
   else
    [self _requireSameContextAs:value forRelationship:[relationship name]];
}

/* The objects the receiver named under relationship (previous, by ID)
   no longer name it under the inverse. */
-(void)_detachInverseOf:(NSRelationshipDescription *)relationship from:previous {
   NSRelationshipDescription *inverse=[relationship inverseRelationship];
   NSString                  *inverseName=[inverse name];

   if(inverse==nil || previous==nil)
    return;

   id allPrevious=[relationship isToMany]?previous:[NSSet setWithObject:previous];

   for(NSManagedObjectID *previousID in allPrevious){
    NSManagedObject *previousObject=[_context objectWithID:previousID];

    [previousObject willChangeValueForKey:inverseName];

    if([inverse isToMany])
     [[previousObject _pendingToManyForKey:inverseName ordered:[inverse isOrdered]] removeObject:[self objectID]];
    else
     [previousObject setPrimitiveValue:nil forKey:inverseName];

    [previousObject didChangeValueForKey:inverseName];
   }
}

/* The objects the receiver names under relationship (current, by ID)
   name it under the inverse. */
-(void)_attachInverseOf:(NSRelationshipDescription *)relationship to:current {
   NSRelationshipDescription *inverse=[relationship inverseRelationship];
   NSString                  *inverseName=[inverse name];
   NSString                  *propertyName=[relationship name];

   if(inverse==nil)
    return;

   id allValues;

   if([relationship isToMany])
    allValues=current;
   else
    allValues=(current==nil)?[NSSet set]:[NSSet setWithObject:current];

   for(NSManagedObjectID *valueID in allValues){
    NSManagedObject *relValue=[_context objectWithID:valueID];

    [relValue willChangeValueForKey:inverseName];

    if([inverse isToMany]){
     id collection=[relValue _pendingToManyForKey:inverseName ordered:[inverse isOrdered]];

     if(![collection containsObject:[self objectID]])
      [collection addObject:[self objectID]];
    }
    else{
     /* As on Apple, an object that joins the receiver leaves the one
        its to-one inverse named before: a product added to a category
        is no longer among its old category's products, a partner's
        old partner has none. */
     NSManagedObjectID *ownerID=[relValue primitiveValueForKey:inverseName];

     if(ownerID!=nil && ![ownerID isEqual:[self objectID]]){
      NSManagedObject *owner=[_context objectWithID:ownerID];

      [owner willChangeValueForKey:propertyName];
      if([relationship isToMany])
       [[owner _pendingToManyForKey:propertyName ordered:[relationship isOrdered]] removeObject:valueID];
      else
       [owner setPrimitiveValue:nil forKey:propertyName];
      [owner didChangeValueForKey:propertyName];
     }

     [relValue setPrimitiveValue:[self objectID] forKey:inverseName];
    }

    [relValue didChangeValueForKey:inverseName];
   }
}

/* -setValue:forKey: without the custom setters: what the framework's own
   paths - the collection proxies, the delete rules, a store's copy - set,
   as Apple's do. */
-(void)_setModeledValue:value forKey:(NSString *)key {
   [self _setValue:value forKey:key property:[[self entity] _propertyForSelector:NSSelectorFromString(key)]];
}

-(void)_setValue:value forKey:(NSString *)key property:(NSPropertyDescription *)property {
   NSString *propertyName=[property name];
   
   if([property isKindOfClass:[NSAttributeDescription class]]){
    [self willChangeValueForKey:propertyName];
    [self setPrimitiveValue:value forKey:propertyName];
    [self didChangeValueForKey:propertyName];
    return;
   }
   else if([property isKindOfClass:[NSRelationshipDescription class]]){
    NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

    [self _requireSameContextAsValue:value forRelationship:relationship];

    id valueByID=CDRelationshipValueByID(relationship,value);

    [self _detachInverseOf:relationship from:CDRelationshipValueByID(relationship,[self primitiveValueForKey:propertyName])];

    [self willChangeValueForKey:propertyName];
    [self setPrimitiveValue:valueByID forKey:propertyName];
    [self didChangeValueForKey:propertyName];

    [self _attachInverseOf:relationship to:valueByID];
    return;
   }
   
   [super setValue:value forKey:key];
}

/* Every modeled mutation funnels through will/didChangeValueForKey: -
   the public setters, the collection proxies (which copy, mutate and
   set back), and inverse maintenance on the other object all emit it -
   so this is the single choke point where the context can snapshot the
   pre-change value for the undo manager. */
-(void)willChangeValueForKey:(NSString *)key {
   [_context _object:self willChangeValueForKey:key];
   [super willChangeValueForKey:key];
}

/* And after it, the context told that the object changed - as Apple's
   objects tell theirs, rather than the context observing every property
   of every object it has (twelve KVO observers and their bookkeeping for
   an object of twelve properties, and every setter through KVO). */
-(void)didChangeValueForKey:(NSString *)key {
   [super didChangeValueForKey:key];
   [_context _object:self didChangeValueForKey:key];
}

-(void)didChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)mutation usingObjects:(NSSet *)objects {
   [super didChangeValueForKey:key withSetMutation:mutation usingObjects:objects];
   [_context _object:self didChangeValueForKey:key];
}

-(void)didChange:(NSKeyValueChange)change valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key {
   [super didChange:change valuesAtIndexes:indexes forKey:key];
   [_context _object:self didChangeValueForKey:key];
}

-(NSMutableSet *) mutableSetValueForKey:(NSString *) key {
   return [[[NSManagedObjectMutableSet alloc] initWithManagedObject:self key:key] autorelease];
}

-(NSMutableOrderedSet *) mutableOrderedSetValueForKey:(NSString *) key {
   return [[[CDManagedObjectMutableOrderedSet alloc] initWithManagedObject:self key:key] autorelease];
}

/* Fires a lazy relationship fault: asks the store, replaces the
   placeholder in _committedValues with the real value - a set of object
   IDs for a to-many, a single object ID for a to-one - and returns it
   (nil when the store answers with nothing; the placeholder is removed
   so the answer is cached either way). */
-(id)_resolveRelationshipFault:(CDRelationshipFault *)fault forKey:(NSString *)key {
   NSPersistentStore *store=[[self objectID] persistentStore];
   NSError           *relationshipError=nil;
   id                 value;

   [[_context persistentStoreCoordinator] lock];
   value=[(NSIncrementalStore *)store newValueForRelationship:[fault relationship]
                                              forObjectWithID:[self objectID]
                                                  withContext:_context
                                                        error:&relationshipError];
   [[_context persistentStoreCoordinator] unlock];

   [value autorelease];

   NSMutableDictionary *committed=(NSMutableDictionary *)_committedValues;

   if(value==nil || value==[NSNull null]){
    [committed removeObjectForKey:key];
    return nil;
   }

   if(![[fault relationship] isToMany]){
    [committed setObject:value forKey:key];
    return value;
   }

   /* Ordered to-many keeps the store's order in an array; unordered
      stays a set. */
   if([[fault relationship] isOrdered]){
    NSMutableArray *relatedIDs=[NSMutableArray array];

    for(NSManagedObjectID *relatedID in value)
     if(![relatedIDs containsObject:relatedID])
      [relatedIDs addObject:relatedID];

    [committed setObject:relatedIDs forKey:key];
    return relatedIDs;
   }

   NSMutableSet *relatedIDs=[NSMutableSet set];

   for(NSManagedObjectID *relatedID in value)
    [relatedIDs addObject:relatedID];

   [committed setObject:relatedIDs forKey:key];
   return relatedIDs;
}

/* A to-many's members, to be changed in place by inverse maintenance:
   its pending value - a copy of the saved one made pending first, so that
   the saved value stays what was saved (for -committedValuesForKeys:, a
   rollback) and the change is one this object has, which a child context
   hands its parent with the others. */
-(id)_pendingToManyForKey:(NSString *)key ordered:(BOOL)ordered {
   id pending=[_changedValues objectForKey:key];

   if(pending!=nil && pending!=[NSNull null])
    return pending;

   id      current=[self primitiveValueForKey:key];
   NSArray *members=[current isKindOfClass:[NSArray class]]?current:
                    [current isKindOfClass:[NSOrderedSet class]]?[current array]:
                    (current!=nil)?[current allObjects]:[NSArray array];

   pending=ordered?(id)[NSMutableArray arrayWithArray:members]:(id)[NSMutableSet setWithArray:members];
   [[self _changes] setObject:pending forKey:key];
   return pending;
}

-primitiveValueForKey:(NSString *) key {
   id result=[_changedValues objectForKey:key];

   if(result==nil)
    result=[[self _committedValues] objectForKey:key];

   if([result isKindOfClass:[CDRelationshipFault class]])
    result=[self _resolveRelationshipFault:result forKey:key];

   if(result==[NSNull null])
    result=nil;

   return result;
}

-(void)setPrimitiveValue:value forKey:(NSString *)key {
   /* An explicit nil must shadow the committed value, so it is recorded
      as NSNull rather than removed from the pending changes. */
   if(value==nil)
    value=[NSNull null];

   [[self _changes] setObject:value forKey:key];
}

/* Private: drops the pending change for key so the committed value shows
   through again (used by merge policies, not part of Apple's API). */
-(void)_discardChangedValueForKey:(NSString *)key {
   [_changedValues removeObjectForKey:key];
}

static NSError *_validationError(NSInteger code,NSManagedObject *object,NSString *key,id value,NSString *description){
   NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

   if(object!=nil)
    [userInfo setObject:object forKey:NSValidationObjectErrorKey];
   if(key!=nil)
    [userInfo setObject:key forKey:NSValidationKeyErrorKey];
   if(value!=nil)
    [userInfo setObject:value forKey:NSValidationValueErrorKey];
   if(description!=nil)
    [userInfo setObject:description forKey:NSLocalizedDescriptionKey];

   return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:userInfo];
}

static BOOL _valueIsEmpty(NSPropertyDescription *property,id value){
   if(value==nil || value==[NSNull null])
    return YES;

   if([property isKindOfClass:[NSRelationshipDescription class]] &&
      [(NSRelationshipDescription *)property isToMany])
    return ([value count]==0);

   return NO;
}

- (BOOL) validateValue:(id *) value forKey:(NSString *) key error:(NSError **) error {
    NSPropertyDescription *property=[[[self entity] propertiesByName] objectForKey:key];

    if(property!=nil){
     id checkValue=(value!=NULL)?*value:nil;

     if(![property isOptional] && _valueIsEmpty(property,checkValue)){
      if(error!=NULL)
       *error=_validationError(NSValidationMissingMandatoryPropertyError,self,key,nil,
          [NSString stringWithFormat:@"%@ is a required value.",key]);
      return NO;
     }

     if([property isKindOfClass:[NSRelationshipDescription class]]){
      NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

      if([relationship isToMany] && checkValue!=nil && checkValue!=[NSNull null]){
       NSUInteger count=[checkValue count];

       if([relationship minCount]>0 && count<(NSUInteger)[relationship minCount]){
        if(error!=NULL)
         *error=_validationError(NSValidationRelationshipLacksMinimumCountError,self,key,checkValue,
            [NSString stringWithFormat:@"%@ has too few related objects.",key]);
        return NO;
       }
       if([relationship maxCount]>0 && count>(NSUInteger)[relationship maxCount]){
        if(error!=NULL)
         *error=_validationError(NSValidationRelationshipExceedsMaximumCountError,self,key,checkValue,
            [NSString stringWithFormat:@"%@ has too many related objects.",key]);
        return NO;
       }
      }
     }

     if(checkValue!=nil && checkValue!=[NSNull null]){
      NSArray *predicates=[property validationPredicates];
      NSArray *warnings=[property validationWarnings];
      NSUInteger i,count=[predicates count];

      for(i=0;i<count;i++){
       NSPredicate *predicate=[predicates objectAtIndex:i];
       BOOL valid=NO;

       @try {
        valid=[predicate evaluateWithObject:checkValue];
       }
       @catch(NSException *e){
        valid=NO;
       }

       if(!valid){
        NSString *warning=(i<[warnings count])?[warnings objectAtIndex:i]:
           [NSString stringWithFormat:@"%@ failed validation.",key];

        if(error!=NULL){
         NSError *predicateError=_validationError(NSManagedObjectValidationError,self,key,checkValue,warning);
         NSMutableDictionary *userInfo=[NSMutableDictionary dictionaryWithDictionary:[predicateError userInfo]];

         [userInfo setObject:predicate forKey:NSValidationPredicateErrorKey];
         *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectValidationError userInfo:userInfo];
        }
        return NO;
       }
      }
     }
    }

    /* Dispatches to custom -validate<Key>:error: methods when implemented. */
    return [super validateValue:value forKey:key error:error];
}

-(BOOL)_validatePropertiesWithError:(NSError **) error {
    NSDictionary   *properties=[[self entity] propertiesByName];
    NSMutableArray *errors=[NSMutableArray array];

    for(NSString *key in properties){
     NSPropertyDescription *property=[properties objectForKey:key];

     if(![property isKindOfClass:[NSAttributeDescription class]] &&
        ![property isKindOfClass:[NSRelationshipDescription class]])
      continue;

     id       value=[self primitiveValueForKey:key];
     NSError *keyError=nil;

     if(![self validateValue:&value forKey:key error:&keyError]){
      if(keyError!=nil)
       [errors addObject:keyError];
     }
    }

    if([errors count]==0)
     return YES;

    if(error!=NULL){
     if([errors count]==1)
      *error=[errors objectAtIndex:0];
     else {
      NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

      [userInfo setObject:errors forKey:NSDetailedErrorsKey];
      [userInfo setObject:@"Multiple validation errors occurred." forKey:NSLocalizedDescriptionKey];
      *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationMultipleErrorsError userInfo:userInfo];
     }
    }

    return NO;
}

- (BOOL) validateForDelete:(NSError **) error {
    NSDictionary *relationships=[[self entity] relationshipsByName];

    for(NSString *key in relationships){
     NSRelationshipDescription *relationship=[relationships objectForKey:key];

     if([relationship deleteRule]!=NSDenyDeleteRule)
      continue;

     id value=[self primitiveValueForKey:key];

     if(value==nil || value==[NSNull null])
      continue;

     NSSet *relatedIDs=[relationship isToMany]?value:[NSSet setWithObject:value];
     BOOL   hasRemaining=NO;

     for(NSManagedObjectID *relatedID in relatedIDs){
      NSManagedObject *related=[_context objectRegisteredForID:relatedID];

      if(related==nil || ![related isDeleted]){
       hasRemaining=YES;
       break;
      }
     }

     if(hasRemaining){
      if(error!=NULL)
       *error=_validationError(NSValidationRelationshipDeniedDeleteError,self,key,value,
          [NSString stringWithFormat:@"%@ denies deletion while it has related objects.",key]);
      return NO;
     }
    }

    return YES;
}

- (BOOL) validateForInsert:(NSError **) error {
    return [self _validatePropertiesWithError:error];
}

- (BOOL) validateForUpdate:(NSError **) error {
    return [self _validatePropertiesWithError:error];
}


+(BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
   return NO;
}

-(void)didAccessValueForKey:(NSString *) key {
}

-(void)willAccessValueForKey:(NSString *)key {
}

-(NSString *)description {
   NSMutableDictionary *values=[NSMutableDictionary dictionaryWithDictionary:[self _committedValues]];
   
   if(_changedValues!=nil)
    [values addEntriesFromDictionary:_changedValues];
   
   return [NSString stringWithFormat:@"<%@ %p:objectID=%@ entity name=%@, values=%@>",
           NSStringFromClass([self class]),self,_objectID,[self entity],values];
}

@end
