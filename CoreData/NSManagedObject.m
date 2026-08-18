/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSManagedObject.h>
#import "NSManagedObjectID-Private.h"
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
   _changedValues = [[NSMutableDictionary alloc] init];
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

-(void)dealloc {
   [self didTurnIntoFault];
   
   [_objectID release];
   [_changedValues release];
   [super dealloc];
}

-(NSUInteger)hash {
   return [_objectID hash];
}

-(BOOL)isEqual:otherX {
   if(![otherX isKindOfClass:[NSManagedObject class]])
    return NO;
   
   NSManagedObject *other=otherX;
   
   return [_objectID isEqual:other->_objectID];
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
   return [[_context insertedObjects] containsObject:self];
}

-(BOOL)isUpdated {
   return [[_context updatedObjects] containsObject:self] &&
          ![[_context insertedObjects] containsObject:self];
}

-(BOOL)isDeleted {
   return [[_context deletedObjects] containsObject:self];
}

-(BOOL)isFault {
   return _isFault;
}

-(void)_setFault:(BOOL)isFault {
   _isFault=isFault;
}

- (BOOL) hasFaultForRelationshipNamed:(NSString *) key {
    return _isFault;
}

- (void) awakeFromFetch {
}

- (void) awakeFromInsert {
}

- (void) prepareForDeletion {
}

-(NSDictionary *)changedValues {
   return _changedValues;
}

-(NSDictionary *)_committedValuesFromIncrementalStore:(NSIncrementalStore *)store {
   NSError                *nodeError=nil;
   NSIncrementalStoreNode *node=[store newValuesForObjectWithID:[self objectID] withContext:_context error:&nodeError];
   NSMutableDictionary    *storedValues=[[NSMutableDictionary alloc] init];

   /* propertiesByName includes inherited properties, [entity properties]
      does not. */
   NSArray *properties=[[[self entity] propertiesByName] allValues];

   for(NSPropertyDescription *property in properties){
    NSString *name=[property name];

    if([property isKindOfClass:[NSAttributeDescription class]]){
     id value=[node valueForPropertyDescription:property];

     if(value!=nil && value!=[NSNull null])
      [storedValues setObject:value forKey:name];
    }
    else if([property isKindOfClass:[NSRelationshipDescription class]]){
     NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;

     if(![relationship isToMany]){
      id value=[node valueForPropertyDescription:property];

      if(value==nil || value==[NSNull null]){
       NSError *relationshipError=nil;

       value=[store newValueForRelationship:relationship forObjectWithID:[self objectID] withContext:_context error:&relationshipError];
       [value autorelease];
      }

      if(value!=nil && value!=[NSNull null])
       [storedValues setObject:value forKey:name];
     }
     else {
      NSError *relationshipError=nil;
      id       value=[store newValueForRelationship:relationship forObjectWithID:[self objectID] withContext:_context error:&relationshipError];

      [value autorelease];

      if(value!=nil && value!=[NSNull null]){
       NSMutableSet *relatedIDs=[NSMutableSet set];

       for(NSManagedObjectID *relatedID in value)
        [relatedIDs addObject:relatedID];

       [storedValues setObject:relatedIDs forKey:name];
      }
     }
    }
   }

   [node release];

   return storedValues;
}

-(NSDictionary *)_committedValues {

   if([[self objectID] isTemporaryID])
    return nil;
    
   if(_committedValues==nil){
    NSPersistentStore *store=[[self objectID] persistentStore];

    if([store isKindOfClass:[NSIncrementalStore class]]){
     [_committedValues release];
     _committedValues=[self _committedValuesFromIncrementalStore:(NSIncrementalStore *)store];

     if(_isFault){
      _isFault=NO;
      [self awakeFromFetch];
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
        value=[NSMutableSet set];
        
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
     [self awakeFromFetch];
    }
   }
   return _committedValues;
}

-(NSDictionary *)_cachedCommittedValues {
   return _committedValues;
}

-(void)_invalidateCommittedValues {
   [_committedValues release];
   _committedValues=nil;
}

-(void)_discardChangedValues {
   [_changedValues removeAllObjects];
}

-(NSDictionary *)committedValuesForKeys:(NSArray *)keys {   
   if(keys==nil)
    return [self _committedValues];
   else {
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    
    for(NSString *key in keys){
     id object=[[self _committedValues] objectForKey:key];
     
     if(object!=nil){
      [result setObject:object forKey:key];
     }
    }
    
    return result;
   }
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
      transient property) takes precedence over the modeled storage. */
   if(property!=nil && [self respondsToSelector:selector] &&
      !_NSManagedObjectIMPIsGeneratedAccessor([self methodForSelector:selector]))
    return [self performSelector:selector];

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
     if([relationship isToMany])
      result=[[[NSManagedObjectSet alloc] initWithManagedObjectContext:_context set:result] autorelease];
     else
      result=[_context objectWithID:result];
    }
    
    [self didAccessValueForKey:propertyName];
    
    return result;
   }
  
   return [super valueForKey:key];
}


-(void)setValue:value forKey:(NSString *) key {
   NSPropertyDescription *property= [[self entity] _propertyForSelector:NSSelectorFromString(key)];
   NSString              *propertyName=[property name];
   
   if([property isKindOfClass:[NSAttributeDescription class]]){
    [self willChangeValueForKey:propertyName];
    [self setPrimitiveValue:value forKey:propertyName];
    [self didChangeValueForKey:propertyName];
    return;
   }
   else if([property isKindOfClass:[NSRelationshipDescription class]]){
    NSRelationshipDescription *relationship=(NSRelationshipDescription *)property;
    NSRelationshipDescription *inverse=[relationship inverseRelationship];
    NSString                  *inverseName=[inverse name];
    id                         valueByID;
        
    if([relationship isToMany]){
     NSMutableSet *set=[NSMutableSet set];
     
     for(NSManagedObject *object in value)
      [set addObject:[object objectID]];
      
     valueByID=set;
    }
    else {
     valueByID=[value objectID];
    }

    if(inverse!=nil){
     id primitivePrevious=[self primitiveValueForKey:key];
     
     if(primitivePrevious!=nil){
      NSSet *allPrevious=[relationship isToMany]?primitivePrevious:[NSSet setWithObject:primitivePrevious];
      
      for(NSManagedObjectID *previousID in allPrevious){
       NSManagedObject *previous=[_context objectWithID:previousID];

       [previous willChangeValueForKey:inverseName];

       if([inverse isToMany])
        [[previous primitiveValueForKey:inverseName] removeObject:[self objectID]];
       else
        [previous setPrimitiveValue:nil forKey:inverseName];
      
       [previous didChangeValueForKey:inverseName];
      }
     }
    }

    [self willChangeValueForKey:propertyName];
    [self setPrimitiveValue:valueByID forKey:propertyName];
    [self didChangeValueForKey:propertyName];

    if(inverse!=nil){     
     NSSet *allValues;

     if([relationship isToMany])
      allValues=valueByID;
     else
      allValues=(valueByID==nil)?[NSSet set]:[NSSet setWithObject:valueByID];

     for(NSManagedObjectID *valueID in allValues){
      NSManagedObject *relValue=[_context objectWithID:valueID];

      [relValue willChangeValueForKey:inverseName];
     
      if([inverse isToMany]){
       NSMutableSet *set=[relValue primitiveValueForKey:inverseName];
    
       if(set==nil){
        set=[NSMutableSet set];
        [relValue setPrimitiveValue:set forKey:inverseName];
       }

       [set addObject:[self objectID]];
      }
      else{
       [relValue setPrimitiveValue:[self objectID] forKey:inverseName];
      }
     
      [relValue didChangeValueForKey:inverseName];
     }
    }
    return;
   }
   
   [super setValue:value forKey:key];
}

-(NSMutableSet *) mutableSetValueForKey:(NSString *) key {
   return [[[NSManagedObjectMutableSet alloc] initWithManagedObject:self key:key] autorelease];
}

-primitiveValueForKey:(NSString *) key {
   id result=[_changedValues objectForKey:key];

   if(result==nil)
    result=[[self _committedValues] objectForKey:key];

   if(result==[NSNull null])
    result=nil;

   return result;
}

-(void)setPrimitiveValue:value forKey:(NSString *)key {
   /* An explicit nil must shadow the committed value, so it is recorded
      as NSNull rather than removed from the pending changes. */
   if(value==nil)
    value=[NSNull null];

   [_changedValues setObject:value forKey:key];
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
   
   [values addEntriesFromDictionary:_changedValues];
   
   return [NSString stringWithFormat:@"<%@ %p:objectID=%@ entity name=%@, values=%@>",
           NSStringFromClass([self class]),self,_objectID,[self entity],values];
}

@end
