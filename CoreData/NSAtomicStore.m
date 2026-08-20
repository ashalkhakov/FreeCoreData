/* This file is part of the CoreData framework port for GNUstep.
   Ported from the Cocotron project (https://github.com/cjwl/cocotron).

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>
   Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSAtomicStore.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSAtomicStoreCacheNode.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import "NSDerivedAttributeDescription-Private.h"
#import "NSManagedObjectID-Private.h"
#import "NSManagedObject-Private.h"
#import "CoreDataUtilities.h"
#import <Foundation/Foundation.h>

@implementation NSAtomicStore

-initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator configurationName:(NSString *)configurationName URL:(NSURL *)url options:(NSDictionary *)options {
   if([super initWithPersistentStoreCoordinator:coordinator configurationName:configurationName URL:url options:options]==nil)
    return nil;

   _metadata=[[NSDictionary alloc] init];
   _cacheNodes=[[NSMutableSet alloc] init];
   _objectIDToCacheNode=[[NSMutableDictionary alloc] init];
   _objectIDTable=[[NSMutableDictionary alloc] init];
   return self;
}

-(void)dealloc {
   [_metadata release];
   [_cacheNodes release];
   [_objectIDToCacheNode release];
   [_objectIDTable release];
   [super dealloc];
}

-(NSSet *)cacheNodes {
   return _cacheNodes;
}

-(NSDictionary *)metadata {
   return _metadata;
}

-(void)setMetadata:(NSDictionary *)value {
   value=[value copy];
   [_metadata release];
   _metadata=value;
}

-(void)addCacheNodes:(NSSet *)values {
   for(NSAtomicStoreCacheNode *node in values){
    [_objectIDToCacheNode setObject:node forKey:[node objectID]];
   }
   [_cacheNodes unionSet:values];
}

-(NSAtomicStoreCacheNode *)cacheNodeForObjectID:(NSManagedObjectID *)objectID {
   NSAtomicStoreCacheNode *result= [_objectIDToCacheNode objectForKey:objectID];

   return result;
}

-(NSAtomicStoreCacheNode *)newCacheNodeForManagedObject:(NSManagedObject *)managedObject {
   return [[NSAtomicStoreCacheNode alloc] initWithObjectID:[managedObject objectID]];
}

-(NSManagedObjectID *)objectIDForEntity:(NSEntityDescription *)entity referenceObject:referenceObject {
   NSMutableDictionary *refTable=[_objectIDTable objectForKey:[entity name]];

   if(refTable==nil){
    refTable=[NSMutableDictionary dictionary];
    [_objectIDTable setObject:refTable forKey:[entity name]];
   }
   
   NSManagedObjectID *result=[refTable objectForKey:referenceObject];
   
   if(result==nil){
    result=[[[NSManagedObjectID alloc] initWithEntity:entity] autorelease];
   
    [result setReferenceObject:referenceObject];
    [result setStoreIdentifier:[self identifier]];
    [result setPersistentStore:self];

    [refTable setObject:result forKey:referenceObject];
   }
   
   return result;
}

-(void)_uniqueObjectID:(NSManagedObjectID *)objectID {
   NSEntityDescription *entity=[objectID entity];
   NSMutableDictionary *refTable=[_objectIDTable objectForKey:[entity name]];
   
   if(refTable==nil){
    refTable=[NSMutableDictionary dictionary];
    [_objectIDTable setObject:refTable forKey:[entity name]];
   }
   
   id referenceObject=[objectID referenceObject];

   [refTable setObject:objectID forKey:referenceObject];
}

-referenceObjectForObjectID:(NSManagedObjectID *)objectID {   
   return [objectID referenceObject];
}

-(void)willRemoveCacheNodes:(NSSet *)cacheNodes {
}

/* Private: performs the actual removal after willRemoveCacheNodes: is invoked. */
-(void)_removeCacheNodes:(NSSet *)cacheNodes {
   for(NSAtomicStoreCacheNode *node in cacheNodes){
    [_objectIDToCacheNode removeObjectForKey:[node objectID]];
   }
   [_cacheNodes minusSet:cacheNodes];
}

-newReferenceObjectForManagedObject:(NSManagedObject *)managedObject {
   NSInvalidAbstractInvocation();
   return nil;
}

-(void)updateCacheNode:(NSAtomicStoreCacheNode *)node fromManagedObject:(NSManagedObject *)managedObject {
   NSEntityDescription *entity=[managedObject entity];
   NSDictionary        *attributesByName=[entity attributesByName];

   for(NSString *attributeName in attributesByName){
    NSAttributeDescription *attribute=[attributesByName objectForKey:attributeName];
    id                      value;

    /* Derived attributes are recomputed at save time; see
       NSDerivedAttributeDescription. */
    if([attribute isKindOfClass:[NSDerivedAttributeDescription class]])
     value=[(NSDerivedAttributeDescription *)attribute _derivedValueForObject:managedObject];
    else
     value=[managedObject primitiveValueForKey:attributeName];

    [node setValue:value forKey:attributeName];
   }

   NSDictionary *relationshipsByName=[entity relationshipsByName];

   for(NSString *relationshipName in relationshipsByName){
    NSRelationshipDescription *relationship=[relationshipsByName objectForKey:relationshipName];
    id                         value=[managedObject primitiveValueForKey:relationshipName];

    if([relationship isToMany]){
     NSMutableSet *nodeSet=[NSMutableSet set];

     for(NSManagedObjectID *relatedID in value){
      NSAtomicStoreCacheNode *relatedNode=[self cacheNodeForObjectID:relatedID];

      if(relatedNode!=nil)
       [nodeSet addObject:relatedNode];
     }

     [node setValue:nodeSet forKey:relationshipName];
    }
    else {
     NSAtomicStoreCacheNode *relatedNode=(value==nil)?nil:[self cacheNodeForObjectID:value];

     [node setValue:relatedNode forKey:relationshipName];
    }
   }
}

-(BOOL)load:(NSError **)error {
   NSInvalidAbstractInvocation();
   return NO;
}

-(BOOL)save:(NSError **)error {
   NSInvalidAbstractInvocation();
   return NO;
}

@end
