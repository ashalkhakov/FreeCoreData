/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSMappingModel.h>
#import <Foundation/NSExpression.h>
#import <Foundation/NSPredicate.h>
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
   NSMutableSet *seenNames=[NSMutableSet set];
   NSMutableSet *mappedSources=[NSMutableSet set];

   for(NSEntityDescription *destinationEntity in [destinationModel entities]){
    NSString            *name=[destinationEntity name];
    /* What it was called: its renaming identifier (Xcode's Renaming ID),
       which is its name when it has none. */
    NSString            *sourceName=[destinationEntity renamingIdentifier];
    NSEntityDescription *sourceEntity=sourceName!=nil?[sourceEntities objectForKey:sourceName]:nil;
    NSEntityMapping     *mapping=[[[NSEntityMapping alloc] init] autorelease];

    /* The model registers entities under multiple keys; process each
       entity only once. */
    if([seenNames containsObject:name])
     continue;
    [seenNames addObject:name];
    if(sourceEntity==nil)
     sourceEntity=[sourceEntities objectForKey:name];
    if(sourceEntity!=nil)
     [mappedSources addObject:[sourceEntity name]];

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

     [mapping setSourceEntityName:[sourceEntity name]];
     [mapping setSourceEntityVersionHash:[sourceEntity versionHash]];
     [mapping setMappingType:[[sourceEntity versionHash] isEqual:[destinationEntity versionHash]]?NSCopyEntityMappingType:NSTransformEntityMappingType];

     /* Apple names inferred entity mappings IEM_<Type>_<EntityName>, the
        source entity's name (a renamed entity's old one). */
     [mapping setName:[NSString stringWithFormat:@"IEM_%@_%@",([mapping mappingType]==NSCopyEntityMappingType)?@"Copy":@"Transform",[sourceEntity name]]];

     /* Apple creates an attribute mapping for every destination attribute
        and a relationship mapping for every destination relationship the
        source has, each with the expression that reads it from the source
        object - by its old name, for one with a renaming identifier.  A
        new attribute gets no expression, and so keeps its default. */
     for(NSPropertyDescription *property in [destinationEntity properties]){
      NSString *propertyName=[property name];
      NSString *oldName=[property renamingIdentifier];
      BOOL      renamed=(oldName!=nil && ![oldName isEqualToString:propertyName] && [sourceProperties objectForKey:oldName]!=nil);
      NSString *sourcePropertyName=renamed?oldName:propertyName;
      id        sourceProperty=[sourceProperties objectForKey:sourcePropertyName];
      NSExpression *read=[NSExpression expressionWithFormat:@"FUNCTION($source, 'valueForKey:', %@)",sourcePropertyName];

      if([property isKindOfClass:[NSAttributeDescription class]]){
       NSPropertyMapping *propertyMapping=[[[NSPropertyMapping alloc] init] autorelease];
       [propertyMapping setName:propertyName];
       if([sourceProperty isKindOfClass:[NSAttributeDescription class]])
        [propertyMapping setValueExpression:read];
       [attributeMappings addObject:propertyMapping];
      }
      else if([property isKindOfClass:[NSRelationshipDescription class]] && [sourceProperty isKindOfClass:[NSRelationshipDescription class]]){
       NSPropertyMapping *propertyMapping=[[[NSPropertyMapping alloc] init] autorelease];
       [propertyMapping setName:propertyName];
       /* Built, not formatted: a format's %@ splices an expression in on
          Apple's Foundation and wraps it as a constant on gnustep-base. */
       [propertyMapping setValueExpression:[NSExpression expressionForFunction:[NSExpression expressionForVariable:@"manager"]
                                                                  selectorName:@"destinationInstancesForSourceRelationshipNamed:sourceInstances:"
                                                                     arguments:[NSArray arrayWithObjects:[NSExpression expressionForConstantValue:sourcePropertyName],read,nil]]];
       [relationshipMappings addObject:propertyMapping];
      }
     }

     [mapping setAttributeMappings:attributeMappings];
     [mapping setRelationshipMappings:relationshipMappings];
    }

    [entityMappings addObject:mapping];
   }

   /* Entities removed in the destination model: those no destination
      entity was mapped from. */
   for(NSEntityDescription *sourceEntity in [sourceModel entities]){
    NSString *name=[sourceEntity name];

    if([mappedSources containsObject:name])
     continue;
    [mappedSources addObject:name];

    {
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

   /* A mapping model is made of predicates and expressions, whose archive
      class names gnustep-base registers in +initialize; poke the classes
      before unarchiving, or reading a mapping model as the very first
      CoreData call fails with "no class for name 'NSKeyPathExpression'".
      The managed object model's loader does the same. */
   [NSPredicate class];
   [NSExpression class];

   NSKeyedUnarchiver *unarchiver=[[NSKeyedUnarchiver alloc] initForReadingWithData:data];
   NSMappingModel    *result=[[unarchiver decodeObjectForKey:@"root"] retain];

   [unarchiver release];
   [data release];

   return result;
}

/* A mapping model compiled by Xcode is a keyed archive, and these are the
   keys it carries - the same ones this writes, so a model written here can
   be read there. */
-(id)initWithCoder:(NSCoder *)coder {
   if((self=[super init])==nil)
    return nil;

   if([coder allowsKeyedCoding])
    _entityMappings=[[coder decodeObjectForKey:@"NSEntityMappings"] copy];
   else
    _entityMappings=[[coder decodeObject] copy];

   if(_entityMappings==nil)
    _entityMappings=[[NSArray alloc] init];

   return self;
}

-(void)encodeWithCoder:(NSCoder *)coder {
   if([coder allowsKeyedCoding]){
    [coder encodeObject:_entityMappings forKey:@"NSEntityMappings"];
    [coder encodeObject:[self entityMappingsByName] forKey:@"NSEntityMappingsByName"];
   }
   else
    [coder encodeObject:_entityMappings];
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
