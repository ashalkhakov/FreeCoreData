/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSIncrementalStore.h>
#import <CoreData/NSIncrementalStoreNode.h>
#import <CoreData/NSPersistentStoreRequest.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/NSEntityDescription.h>
#import "NSManagedObjectID-Private.h"
#import "CoreDataUtilities.h"
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUUID.h>

@implementation NSIncrementalStore

-initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root configurationName:(NSString *)name URL:(NSURL *)url options:(NSDictionary *)options {
   if((self=[super initWithPersistentStoreCoordinator:root configurationName:name URL:url options:options])==nil)
    return nil;

   _incrementalMetadata=nil;
   _objectIDTable=[[NSMutableDictionary alloc] init];

   return self;
}

-(void)dealloc {
   [_incrementalMetadata release];
   [_objectIDTable release];
   [super dealloc];
}

+(id)identifierForNewStoreAtURL:(NSURL *)storeURL {
   return [[NSUUID UUID] UUIDString];
}

-(NSString *)type {
   NSString *type=[[self metadata] objectForKey:NSStoreTypeKey];

   if(type!=nil)
    return type;

   NSDictionary *types=[NSPersistentStoreCoordinator registeredStoreTypes];

   for(NSString *check in types)
    if([types objectForKey:check]==[self class])
     return check;

   return NSStringFromClass([self class]);
}

-(NSDictionary *)metadata {
   return _incrementalMetadata;
}

-(void)setMetadata:(NSDictionary *)value {
   value=[value copy];
   [_incrementalMetadata release];
   _incrementalMetadata=value;
}

-(BOOL)loadMetadata:(NSError **)error {
   NSInvalidAbstractInvocation();
   return NO;
}

-executeRequest:(NSPersistentStoreRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSInvalidAbstractInvocation();
   return nil;
}

-(NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSInvalidAbstractInvocation();
   return nil;
}

-newValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSInvalidAbstractInvocation();
   return nil;
}

-(NSArray *)obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)error {
   NSInvalidAbstractInvocation();
   return nil;
}

-(void)managedObjectContextDidRegisterObjectsWithIDs:(NSArray *)objectIDs {
}

-(void)managedObjectContextDidUnregisterObjectsWithIDs:(NSArray *)objectIDs {
}

-(NSMutableDictionary *)_objectIDTableForEntity:(NSEntityDescription *)entity {
   NSString            *entityName=[entity name];
   NSMutableDictionary *table=[_objectIDTable objectForKey:entityName];

   if(table==nil){
    table=[NSMutableDictionary dictionary];
    [_objectIDTable setObject:table forKey:entityName];
   }

   return table;
}

-(NSManagedObjectID *)newObjectIDForEntity:(NSEntityDescription *)entity referenceObject:data {
   NSMutableDictionary *table=[self _objectIDTableForEntity:entity];
   NSManagedObjectID   *objectID=[table objectForKey:data];

   if(objectID==nil){
    objectID=[[[NSManagedObjectID alloc] initWithEntity:entity] autorelease];
    [objectID setReferenceObject:data];
    [objectID setStoreIdentifier:[self identifier]];
    [objectID setPersistentStore:self];
    [table setObject:objectID forKey:data];
   }

   return [objectID retain];
}

-referenceObjectForObjectID:(NSManagedObjectID *)objectID {
   return [objectID referenceObject];
}

/* Re-registers objectID in the uniquing table under its (new) reference
   object, so subsequently created IDs for the same reference are uniqued to
   this instance.  Used when a temporary ID becomes permanent in place. */
-(void)_uniqueObjectID:(NSManagedObjectID *)objectID {
   NSMutableDictionary *table=[self _objectIDTableForEntity:[objectID entity]];

   [table setObject:objectID forKey:[objectID referenceObject]];
}

@end
