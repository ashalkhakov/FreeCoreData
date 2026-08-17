/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSMappingModel.h>
#import <CoreData/NSEntityMapping.h>
#import <CoreData/NSPropertyMapping.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSRelationshipDescription.h>

@implementation NSMappingModel

-(void)dealloc {
   [_entityMappings release];
   [super dealloc];
}

+(NSMappingModel *)mappingModelFromBundles:(NSArray *)bundles forSourceModel:(NSManagedObjectModel *)sourceModel destinationModel:(NSManagedObjectModel *)destinationModel {
   NSDictionary *sourceHashes=[sourceModel entityVersionHashesByName];
   NSDictionary *destinationHashes=[destinationModel entityVersionHashesByName];

   if(bundles==nil)
    bundles=[NSArray arrayWithObject:[NSBundle mainBundle]];

   for(NSBundle *bundle in bundles){
    for(NSString *path in [bundle pathsForResourcesOfType:@"cdm" inDirectory:nil]){
     NSMappingModel *model=[[[NSMappingModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]] autorelease];
     BOOL            matches=(model!=nil);

     /* The mapping model matches when every entity mapping's version
        hashes correspond to the given source and destination models. */
     for(NSEntityMapping *mapping in [model entityMappings]){
      NSString *sourceName=[mapping sourceEntityName];
      NSString *destinationName=[mapping destinationEntityName];

      if(sourceName!=nil && [mapping sourceEntityVersionHash]!=nil && ![[mapping sourceEntityVersionHash] isEqual:[sourceHashes objectForKey:sourceName]])
       matches=NO;
      if(destinationName!=nil && [mapping destinationEntityVersionHash]!=nil && ![[mapping destinationEntityVersionHash] isEqual:[destinationHashes objectForKey:destinationName]])
       matches=NO;

      if(!matches)
       break;
     }

     if(matches)
      return model;
    }
   }

   return nil;
}

+(NSMappingModel *)inferredMappingModelForSourceModel:(NSManagedObjectModel *)sourceModel destinationModel:(NSManagedObjectModel *)destinationModel error:(NSError **)error {
   NSMappingModel *result=[[[NSMappingModel alloc] init] autorelease];
   NSMutableArray *entityMappings=[NSMutableArray array];

   NSDictionary *sourceEntities=[sourceModel entitiesByName];
   NSDictionary *destinationEntities=[destinationModel entitiesByName];
   NSMutableSet *seenNames=[NSMutableSet set];

   for(NSEntityDescription *destinationEntity in [destinationModel entities]){
    NSString            *name=[destinationEntity name];
    NSEntityDescription *sourceEntity=[sourceEntities objectForKey:name];
    NSEntityMapping     *mapping=[[[NSEntityMapping alloc] init] autorelease];

    /* The model registers entities under multiple keys; process each
       entity only once. */
    if([seenNames containsObject:name])
     continue;
    [seenNames addObject:name];

    [mapping setDestinationEntityName:name];
    [mapping setDestinationEntityVersionHash:[destinationEntity versionHash]];

    if(sourceEntity==nil){
     [mapping setMappingType:NSAddEntityMappingType];
     [mapping setName:[NSString stringWithFormat:@"IEM_Add_%@",name]];
    }
    else {
     NSMutableArray *attributeMappings=[NSMutableArray array];
     NSMutableArray *relationshipMappings=[NSMutableArray array];
     NSDictionary   *sourceProperties=[sourceEntity propertiesByName];

     [mapping setSourceEntityName:name];
     [mapping setSourceEntityVersionHash:[sourceEntity versionHash]];
     [mapping setMappingType:[[sourceEntity versionHash] isEqual:[destinationEntity versionHash]]?NSCopyEntityMappingType:NSTransformEntityMappingType];

     /* Apple names inferred entity mappings IEM_<Type>_<EntityName>. */
     [mapping setName:[NSString stringWithFormat:@"IEM_%@_%@",([mapping mappingType]==NSCopyEntityMappingType)?@"Copy":@"Transform",name]];

     /* Apple creates an attribute mapping for every destination attribute:
        attributes that also exist in the source migrate by direct copy,
        new attributes get a mapping without a value expression so they
        keep their default values. Relationship mappings are only created
        for relationships present in both versions. */
     for(NSPropertyDescription *property in [destinationEntity properties]){
      NSString *propertyName=[property name];

      if([property isKindOfClass:[NSAttributeDescription class]]){
       NSPropertyMapping *propertyMapping=[[[NSPropertyMapping alloc] init] autorelease];
       [propertyMapping setName:propertyName];
       [attributeMappings addObject:propertyMapping];
      }
      else if([property isKindOfClass:[NSRelationshipDescription class]] && [sourceProperties objectForKey:propertyName]!=nil){
       NSPropertyMapping *propertyMapping=[[[NSPropertyMapping alloc] init] autorelease];
       [propertyMapping setName:propertyName];
       [relationshipMappings addObject:propertyMapping];
      }
     }

     [mapping setAttributeMappings:attributeMappings];
     [mapping setRelationshipMappings:relationshipMappings];
    }

    [entityMappings addObject:mapping];
   }

   /* Entities removed in the destination model. */
   for(NSEntityDescription *sourceEntity in [sourceModel entities]){
    NSString *name=[sourceEntity name];

    if([seenNames containsObject:name])
     continue;
    [seenNames addObject:name];

    if([destinationEntities objectForKey:name]==nil){
     NSEntityMapping *mapping=[[[NSEntityMapping alloc] init] autorelease];

     [mapping setSourceEntityName:name];
     [mapping setSourceEntityVersionHash:[sourceEntity versionHash]];
     [mapping setMappingType:NSRemoveEntityMappingType];
     [mapping setName:[NSString stringWithFormat:@"IEM_Remove_%@",name]];

     [entityMappings addObject:mapping];
    }
   }

   [result setEntityMappings:entityMappings];

   return result;
}

-initWithContentsOfURL:(NSURL *)url {
   [self release];
   self=nil;

   NSData *data=[[NSData alloc] initWithContentsOfURL:url];

   if(data==nil)
    return nil;

   NSKeyedUnarchiver *unarchiver=[[NSKeyedUnarchiver alloc] initForReadingWithData:data];
   NSMappingModel    *result=[[unarchiver decodeObjectForKey:@"root"] retain];

   [unarchiver release];
   [data release];

   return result;
}

-(NSArray *)entityMappings {
   return _entityMappings;
}

-(void)setEntityMappings:(NSArray *)mappings {
   mappings=[mappings copy];
   [_entityMappings release];
   _entityMappings=mappings;
}

-(NSDictionary *)entityMappingsByName {
   NSMutableDictionary *result=[NSMutableDictionary dictionary];

   for(NSEntityMapping *mapping in _entityMappings)
    [result setObject:mapping forKey:[mapping name]];

   return result;
}

@end
