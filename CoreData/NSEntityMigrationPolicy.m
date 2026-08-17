/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSEntityMigrationPolicy.h>
#import <CoreData/NSEntityMapping.h>
#import <CoreData/NSPropertyMapping.h>
#import <CoreData/NSMigrationManager.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSRelationshipDescription.h>

NSString * const NSMigrationManagerKey=@"manager";
NSString * const NSMigrationSourceObjectKey=@"source";
NSString * const NSMigrationDestinationObjectKey=@"destination";
NSString * const NSMigrationEntityMappingKey=@"entityMapping";
NSString * const NSMigrationPropertyMappingKey=@"propertyMapping";
NSString * const NSMigrationEntityPolicyKey=@"entityPolicy";

@interface NSMigrationManager(MigrationPrivate)
- (NSManagedObject *)_destinationInstanceForSourceInstance:(NSManagedObject *)sourceInstance;
@end

@implementation NSEntityMigrationPolicy

-(BOOL)beginEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error {
   return YES;
}

-(id)_valueForPropertyMapping:(NSPropertyMapping *)propertyMapping sourceInstance:(NSManagedObject *)sInstance entityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager {
   NSExpression *expression=[propertyMapping valueExpression];

   if(expression!=nil){
    NSMutableDictionary *context=[NSMutableDictionary dictionary];

    if(sInstance!=nil)
     [context setObject:sInstance forKey:NSMigrationSourceObjectKey];
    [context setObject:manager forKey:NSMigrationManagerKey];
    [context setObject:mapping forKey:NSMigrationEntityMappingKey];
    [context setObject:propertyMapping forKey:NSMigrationPropertyMappingKey];
    [context setObject:self forKey:NSMigrationEntityPolicyKey];

    return [expression expressionValueWithObject:sInstance context:context];
   }

   /* No expression: copy the identically named source property when it
      exists. */
   NSEntityDescription *sourceEntity=[sInstance entity];

   if([[sourceEntity propertiesByName] objectForKey:[propertyMapping name]]==nil)
    return nil;

   return [sInstance valueForKey:[propertyMapping name]];
}

-(BOOL)createDestinationInstancesForSourceInstance:(NSManagedObject *)sInstance entityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error {
   NSEntityDescription *destinationEntity=[manager destinationEntityForEntityMapping:mapping];

   if(destinationEntity==nil)
    return YES;

   NSManagedObject *dInstance=[NSEntityDescription insertNewObjectForEntityForName:[destinationEntity name] inManagedObjectContext:[manager destinationContext]];

   for(NSPropertyMapping *propertyMapping in [mapping attributeMappings]){
    id value=[self _valueForPropertyMapping:propertyMapping sourceInstance:sInstance entityMapping:mapping manager:manager];

    if(value!=nil)
     [dInstance setValue:value forKey:[propertyMapping name]];
   }

   [manager associateSourceInstance:sInstance withDestinationInstance:dInstance forEntityMapping:mapping];

   [dInstance release];

   return YES;
}

-(BOOL)endInstanceCreationForEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error {
   return YES;
}

-(BOOL)createRelationshipsForDestinationInstance:(NSManagedObject *)dInstance entityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error {
   NSArray         *sourceInstances=[manager sourceInstancesForEntityMappingNamed:[mapping name] destinationInstances:[NSArray arrayWithObject:dInstance]];
   NSManagedObject *sInstance=[sourceInstances lastObject];

   if(sInstance==nil)
    return YES;

   NSDictionary *destinationRelationships=[[dInstance entity] relationshipsByName];

   for(NSPropertyMapping *propertyMapping in [mapping relationshipMappings]){
    NSString                  *name=[propertyMapping name];
    NSRelationshipDescription *relationship=[destinationRelationships objectForKey:name];
    id                         sourceValue=[self _valueForPropertyMapping:propertyMapping sourceInstance:sInstance entityMapping:mapping manager:manager];

    if(sourceValue==nil)
     continue;

    if([relationship isToMany]){
     NSMutableSet *destinationSet=[dInstance mutableSetValueForKey:name];

     for(NSManagedObject *related in sourceValue){
      NSManagedObject *destinationRelated=[manager _destinationInstanceForSourceInstance:related];

      if(destinationRelated!=nil)
       [destinationSet addObject:destinationRelated];
     }
    }
    else {
     NSManagedObject *destinationRelated=[manager _destinationInstanceForSourceInstance:sourceValue];

     if(destinationRelated!=nil)
      [dInstance setValue:destinationRelated forKey:name];
    }
   }

   return YES;
}

-(BOOL)endRelationshipCreationForEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error {
   return YES;
}

-(BOOL)performCustomValidationForEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error {
   return YES;
}

-(BOOL)endEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error {
   return YES;
}

@end
