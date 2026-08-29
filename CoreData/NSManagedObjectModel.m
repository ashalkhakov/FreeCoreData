/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSPersistentStoreCoordinator.h>

#import <Foundation/Foundation.h>
#import "CoreDataUtilities.h"

@implementation NSManagedObjectModel

+(NSManagedObjectModel *)modelByMergingModels:(NSArray *)models {
   NSManagedObjectModel *result=[[NSManagedObjectModel alloc] init];
   NSMutableArray       *entities=[NSMutableArray array];
   
   for(NSManagedObjectModel *merge in models){
    [entities addObjectsFromArray:[merge entities]];
   }
   
   [result setEntities:entities];
      
   return [result autorelease];
}

+(NSManagedObjectModel *)modelByMergingModels:(NSArray *)models forStoreMetadata:(NSDictionary *)metadata {
   NSManagedObjectModel *result=[self modelByMergingModels:models];

   if(![result isConfiguration:nil compatibleWithStoreMetadata:metadata])
    return nil;

   return result;
}

/* Returns the paths of every .mom in the bundle, including the model
   versions contained in .momd bundles. */
static NSArray *allModelPathsInBundle(NSBundle *bundle){
   NSMutableArray *result=[NSMutableArray array];

   [result addObjectsFromArray:[bundle pathsForResourcesOfType:@"mom" inDirectory:nil]];

   for(NSString *momd in [bundle pathsForResourcesOfType:@"momd" inDirectory:nil]){
    for(NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:momd error:NULL]){
     if([[name pathExtension] isEqualToString:@"mom"])
      [result addObject:[momd stringByAppendingPathComponent:name]];
    }
   }

   return result;
}

+(NSManagedObjectModel *)mergedModelFromBundles:(NSArray *)bundles {
   NSMutableArray *models=[NSMutableArray array];
   
   if(bundles==nil)
    bundles=[NSArray arrayWithObject:[NSBundle mainBundle]];
  
   for(NSBundle *bundle in bundles){
    NSMutableArray *moms=[NSMutableArray array];

    [moms addObjectsFromArray:[bundle pathsForResourcesOfType:@"mom" inDirectory:nil]];
    /* For versioned models only the current version participates. */
    [moms addObjectsFromArray:[bundle pathsForResourcesOfType:@"momd" inDirectory:nil]];
        
    for(NSString *path in moms){
     NSURL                *url=[NSURL fileURLWithPath:path];
     NSManagedObjectModel *model=[[NSManagedObjectModel alloc] initWithContentsOfURL:url];
     
     if(model==nil)
      NSLog(@"-[%@ initWithContentsOfURL:] failed. url=%@",[self class],url);
     
     if(model!=nil){
      [models addObject:model];
      [model release];
     }
    }
    
   }
   
   return [self modelByMergingModels:models];
}

+(NSManagedObjectModel *)mergedModelFromBundles:(NSArray *)bundles forStoreMetadata:(NSDictionary *)metadata {
   if(bundles==nil)
    bundles=[NSArray arrayWithObject:[NSBundle mainBundle]];

   /* Search every model version in the given bundles for one that is
      compatible with the store metadata. */
   for(NSBundle *bundle in bundles){
    for(NSString *path in allModelPathsInBundle(bundle)){
     NSURL                *url=[NSURL fileURLWithPath:path];
     NSManagedObjectModel *model=[[[NSManagedObjectModel alloc] initWithContentsOfURL:url] autorelease];

     if([model isConfiguration:nil compatibleWithStoreMetadata:metadata])
      return model;
    }
   }

   return nil;
}

-init {
   _entities=[[NSMutableDictionary alloc] init];
   _fetchRequestTemplates=[[NSMutableDictionary alloc] init];
   _configurations=[[NSMutableDictionary alloc] init];
   return self;
}

-initWithCoder: (NSCoder *) coder {
   if(![coder allowsKeyedCoding])
    [NSException raise:NSInvalidArgumentException format: @"%@ can not initWithCoder:%@", [self class], [coder class]];

   _entities=[[coder decodeObjectForKey: @"NSEntities"] mutableCopy] ?: [[NSMutableDictionary alloc] init];
   
   _fetchRequestTemplates=[[coder decodeObjectForKey: @"NSFetchRequestTemplates"] mutableCopy] ?: [[NSMutableDictionary alloc] init];
   _configurations=[[coder decodeObjectForKey: @"NSConfigurations"] mutableCopy] ?: [[NSMutableDictionary alloc] init];
   _versionIdentifiers=[[coder decodeObjectForKey: @"NSVersionIdentifiers"] retain];
   
   return self;
}

-(void)encodeWithCoder: (NSCoder *) coder {
   if(![coder allowsKeyedCoding])
    [NSException raise:NSInvalidArgumentException format: @"%@ can not encodeWithCoder:%@", [self class], [coder class]];

   /* _entities holds each entity under both its name and the uppercased
      name; only the exact names are archived. */
   NSMutableDictionary *entities=[NSMutableDictionary dictionary];

   for(NSEntityDescription *entity in [_entities allValues])
    [entities setObject:entity forKey:[entity name]];

   [coder encodeObject:entities forKey: @"NSEntities"];
   [coder encodeObject:_fetchRequestTemplates forKey: @"NSFetchRequestTemplates"];
   if([_configurations count]>0)
    [coder encodeObject:_configurations forKey: @"NSConfigurations"];
   if(_versionIdentifiers!=nil)
    [coder encodeObject:_versionIdentifiers forKey: @"NSVersionIdentifiers"];
}

-initWithContentsOfURL:(NSURL *)url {
   /* Replace self: release the alloc'd shell and return the unarchived model.
      The result is retained here so ownership is correctly transferred to
      the caller (who expects a +1 object from alloc+init). */
   [self release];
   self = nil;

   NSString *path=[url path];
   BOOL      isDirectory=NO;

   /* A .momd bundle is a directory of versioned models; load the current
      version as designated by VersionInfo.plist. */
   if([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory){
    NSString     *versionInfoPath=[path stringByAppendingPathComponent:@"VersionInfo.plist"];
    NSDictionary *versionInfo=[NSDictionary dictionaryWithContentsOfFile:versionInfoPath];
    NSString     *currentVersionName=[versionInfo objectForKey:@"NSManagedObjectModel_CurrentVersionName"];
    NSString     *momPath=nil;

    if(currentVersionName!=nil)
     momPath=[path stringByAppendingPathComponent:[currentVersionName stringByAppendingPathExtension:@"mom"]];
    else {
     /* No version info; fall back to the first .mom inside the bundle. */
     for(NSString *name in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:NULL] sortedArrayUsingSelector:@selector(compare:)]){
      if([[name pathExtension] isEqualToString:@"mom"]){
       momPath=[path stringByAppendingPathComponent:name];
       break;
      }
     }
    }

    if(momPath==nil)
     return nil;

    url=[NSURL fileURLWithPath:momPath];
   }

   NSData *data=[[NSData alloc] initWithContentsOfURL:url];
   
   if(data==nil)
    return nil;

   /* Model archives contain predicates and expressions; gnustep-base
      registers its Apple-compatible archive class aliases
      (NSKeyPathExpression and friends) in +initialize, so poke the
      classes before unarchiving - otherwise loading a model as the
      very first CoreData call fails with "no class for name
      'NSKeyPathExpression'". */
   [NSPredicate class];
   [NSExpression class];

   NSKeyedUnarchiver *unarchiver=[[NSKeyedUnarchiver alloc] initForReadingWithData: data];
   NSManagedObjectModel *result=[[unarchiver decodeObjectForKey: @"root"] retain];
   
   [unarchiver release];
   [data release];
   
   return result;
}

-(NSArray *)entities {
   return [_entities allValues];
}

-(NSDictionary *)entitiesByName {
   return _entities;
}

-(NSDictionary *) localizationDictionary {
   return _localizationDictionary;
}

-(void)setEntities: (NSArray *)entities {
   [_entities removeAllObjects];
   
   /* Exact names only: an uppercased alias key inherited from Cocotron
      polluted -entities and -entitiesByName with duplicates, and nothing
      ever looked entities up case-insensitively. */
   for(NSEntityDescription *entity in entities)
    [_entities setObject:entity forKey:[entity name]];
}

-(void)setLocalizationDictionary:(NSDictionary *)dictionary {
   dictionary=[dictionary copy];
   [_localizationDictionary release];
   _localizationDictionary=dictionary;
}

-(NSArray *)configurations {
   return [_configurations allKeys];
}

-(NSArray *)entitiesForConfiguration: (NSString *) configuration {
   return [_configurations objectForKey:configuration];
}

-(void)setEntities:(NSArray *)entities forConfiguration:(NSString *)configuration {
   [_configurations setObject:entities forKey:configuration];
}

-(NSFetchRequest *)fetchRequestTemplateForName: (NSString *) name {
   return [_fetchRequestTemplates objectForKey:name];
}

-(NSDictionary *)fetchRequestTemplatesByName {
   return [[_fetchRequestTemplates copy] autorelease];
}

-(NSFetchRequest *)fetchRequestFromTemplateWithName:(NSString *)name substitutionVariables:(NSDictionary *)variables {
    NSUnimplementedMethod();
    return nil;
}

-(void)setFetchRequestTemplate: (NSFetchRequest *) fetchRequest forName: (NSString *) name {
   /* Apple removes the template when passed nil. */
   if(fetchRequest==nil)
    [_fetchRequestTemplates removeObjectForKey:name];
   else
    [_fetchRequestTemplates setObject:fetchRequest forKey:name];
}

-(NSSet *)versionIdentifiers {
   return (_versionIdentifiers!=nil)?_versionIdentifiers:[NSSet set];
}

-(void)setVersionIdentifiers:(NSSet *)identifiers {
   identifiers=[identifiers copy];
   [_versionIdentifiers release];
   _versionIdentifiers=identifiers;
}

-(NSDictionary *)entityVersionHashesByName {
   NSMutableDictionary *result=[NSMutableDictionary dictionary];

   /* _entities also stores each entity under an uppercased key; only the
      canonical names participate in the version hashes. */
   for(NSString *name in _entities){
    NSEntityDescription *entity=[_entities objectForKey:name];

    if([name isEqualToString:[entity name]])
     [result setObject:[entity versionHash] forKey:name];
   }

   return result;
}

-(BOOL)isConfiguration:(NSString *)configuration compatibleWithStoreMetadata:(NSDictionary *)metadata {
   NSDictionary *storeHashes=[metadata objectForKey:NSStoreModelVersionHashesKey];

   if(![storeHashes isKindOfClass:[NSDictionary class]])
    return NO;

   NSArray *entities;

   if(configuration==nil)
    entities=[[self entityVersionHashesByName] allKeys];
   else {
    NSMutableArray *names=[NSMutableArray array];

    for(NSEntityDescription *entity in [self entitiesForConfiguration:configuration])
     [names addObject:[entity name]];

    entities=names;
   }

   if(configuration==nil && [entities count]!=[storeHashes count])
    return NO;

   for(NSString *name in entities){
    NSEntityDescription *entity=[_entities objectForKey:name];
    NSData              *storeHash=[storeHashes objectForKey:name];

    if(entity==nil || storeHash==nil || ![storeHash isEqual:[entity versionHash]])
     return NO;
   }

   return YES;
}

@end
