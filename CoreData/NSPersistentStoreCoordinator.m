/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPersistentStoreCoordinator.h>
#import "NSXMLPersistentStore.h"
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSIncrementalStore.h>
#import <CoreData/CoreDataErrors.h>
#import <CoreData/NSMappingModel.h>
#import <CoreData/NSMigrationManager.h>
#import <CoreData/NSEntityDescription.h>
#import "NSInMemoryPersistentStore.h"
#import "NSSQLitePersistentStore.h"
#import "NSManagedObjectID-Private.h"
#import "NSDerivedAttributeDescription-Private.h"
#import "CoreDataUtilities.h"

NSString * const NSStoreTypeKey=@"NSStoreTypeKey";
NSString * const NSStoreUUIDKey=@"NSStoreUUIDKey";
NSString * const NSStoreModelVersionHashesKey=@"NSStoreModelVersionHashes";
NSString * const NSStoreModelVersionIdentifiersKey=@"NSStoreModelVersionIdentifiers";

NSString * const NSXMLStoreType=@"NSXMLStoreType";
NSString * const NSSQLiteStoreType=@"SQLite";
NSString * const NSInMemoryStoreType=@"NSInMemoryStoreType";
NSString * const NSMigratePersistentStoresAutomaticallyOption=@"NSMigratePersistentStoresAutomaticallyOption";
NSString * const NSInferMappingModelAutomaticallyOption=@"NSInferMappingModelAutomaticallyOption";
NSString * const NSIgnorePersistentStoreVersioningOption=@"NSIgnorePersistentStoreVersioningOption";

NSString * const NSPersistentStoreCoordinatorStoresDidChangeNotification=@"NSPersistentStoreCoordinatorStoresDidChangeNotification";
NSString * const NSAddedPersistentStoresKey=@"NSAddedPersistentStoresKey";
NSString * const NSRemovedPersistentStoresKey=@"NSRemovedPersistentStoresKey";
NSString * const NSUUIDChangedPersistentStoresKey=@"NSUUIDChangedPersistentStoresKey";

@implementation NSPersistentStoreCoordinator

static NSMutableDictionary *_storeTypes=nil;

+(void)initialize {
   if(self==[NSPersistentStoreCoordinator class]){
    _storeTypes=[NSMutableDictionary new];
    [_storeTypes setObject:[NSInMemoryPersistentStore class] forKey:NSInMemoryStoreType];
    [_storeTypes setObject:[NSXMLPersistentStore class] forKey:NSXMLStoreType];
    [_storeTypes setObject:[NSSQLitePersistentStore class] forKey:NSSQLiteStoreType];
   }
}

+(NSDictionary *)registeredStoreTypes {
    return _storeTypes;
}

+(void)registerStoreClass:(Class)storeClass forStoreType:(NSString *)storeType {
   [_storeTypes setObject:storeClass forKey:storeType];
}

-initWithManagedObjectModel:(NSManagedObjectModel *)model {
   _lock=[[NSLock alloc] init];
   _model=[model retain];
   _stores=[[NSMutableArray alloc] init];
   return self;
}

-(void)dealloc {
   [_lock release];
   [_model release];
   [_stores release];
   [super dealloc];
}

-(NSManagedObjectModel *)managedObjectModel {
   return _model;
}

/* Version hashes for the entities in the given configuration (all
   entities when configuration is nil). */
-(NSDictionary *)_versionHashesForConfiguration:(NSString *)configuration {
   if(configuration==nil)
    return [_model entityVersionHashesByName];

   NSMutableDictionary *result=[NSMutableDictionary dictionary];

   for(NSEntityDescription *entity in [_model entitiesForConfiguration:configuration])
    [result setObject:[entity versionHash] forKey:[entity name]];

   return result;
}

/* Checks whether the on-disk store at storeURL is compatible with the
   coordinator's model, and performs an in-place automatic migration when
   requested. Returns NO with an error when the store is incompatible. */
-(BOOL)_checkVersionCompatibilityOfStoreClass:(Class)class type:(NSString *)storeType configuration:(NSString *)configuration URL:(NSURL *)storeURL options:(NSDictionary *)options error:(NSError **)error {
   if(storeURL==nil)
    return YES;

   if([[options objectForKey:NSIgnorePersistentStoreVersioningOption] boolValue])
    return YES;

   NSDictionary *metadata=[class metadataForPersistentStoreWithURL:storeURL error:NULL];

   /* New stores and stores without version information are accepted. */
   if([metadata objectForKey:NSStoreModelVersionHashesKey]==nil)
    return YES;

   if([_model isConfiguration:configuration compatibleWithStoreMetadata:metadata])
    return YES;

   if(![[options objectForKey:NSMigratePersistentStoresAutomaticallyOption] boolValue]){
    if(error!=NULL){
     NSDictionary *userInfo=[NSDictionary dictionaryWithObject:@"The model used to open the store is incompatible with the one used to create the store" forKey:NSLocalizedDescriptionKey];

     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreIncompatibleVersionHashError userInfo:userInfo];
    }
    return NO;
   }

   NSManagedObjectModel *sourceModel=[NSManagedObjectModel mergedModelFromBundles:nil forStoreMetadata:metadata];

   if(sourceModel==nil){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSMigrationMissingSourceModelError userInfo:[NSDictionary dictionaryWithObject:@"Can't find source model for migration" forKey:NSLocalizedDescriptionKey]];
    return NO;
   }

   NSMappingModel *mappingModel=[NSMappingModel mappingModelFromBundles:nil forSourceModel:sourceModel destinationModel:_model];

   if(mappingModel==nil && [[options objectForKey:NSInferMappingModelAutomaticallyOption] boolValue])
    mappingModel=[NSMappingModel inferredMappingModelForSourceModel:sourceModel destinationModel:_model error:error];

   if(mappingModel==nil){
    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSMigrationMissingMappingModelError userInfo:[NSDictionary dictionaryWithObject:@"Can't find mapping model for migration" forKey:NSLocalizedDescriptionKey]];
    return NO;
   }

   NSURL              *temporaryURL=[NSURL fileURLWithPath:[[storeURL path] stringByAppendingString:@"~migrated"]];
   NSMigrationManager *manager=[[[NSMigrationManager alloc] initWithSourceModel:sourceModel destinationModel:_model] autorelease];

   if(![manager migrateStoreFromURL:storeURL type:storeType options:nil withMappingModel:mappingModel toDestinationURL:temporaryURL destinationType:storeType destinationOptions:nil error:error])
    return NO;

   /* Release the manager's stores (closing their connections, e.g. SQLite
      file descriptors) before deleting and renaming the files underneath
      them. */
   [manager reset];

   NSFileManager *fileManager=[NSFileManager defaultManager];

   if(![fileManager removeItemAtPath:[storeURL path] error:error])
    return NO;

   return [fileManager moveItemAtPath:[temporaryURL path] toPath:[storeURL path] error:error];
}

/* Stamps the store's metadata with the version hashes and identifiers of
   the coordinator's model so that compatibility can be verified when the
   store is reopened later. */
-(void)_stampVersioningMetadataForStore:(NSAtomicStore *)store configuration:(NSString *)configuration {
   NSMutableDictionary *metadata=[NSMutableDictionary dictionaryWithDictionary:[store metadata]];

   [metadata setObject:[self _versionHashesForConfiguration:configuration] forKey:NSStoreModelVersionHashesKey];
   [metadata setObject:[[_model versionIdentifiers] allObjects] forKey:NSStoreModelVersionIdentifiersKey];

   [store setMetadata:metadata];
}

-(NSPersistentStore *)addPersistentStoreWithType:(NSString *)storeType configuration:(NSString *)configuration URL:(NSURL *)storeURL options:(NSDictionary *)options error:(NSError **)error {
   /* Unsupported or malformed derivation expressions are rejected when
      the first store is added, for every store type. */
   if(!_NSValidateDerivedAttributesInModel([self managedObjectModel],error))
    return nil;

   if(storeType==nil){
    for(Class class in [_storeTypes allValues]){
     NSDictionary *metadata=[class metadataForPersistentStoreWithURL:storeURL error:nil];
     if((storeType=[metadata objectForKey:NSStoreTypeKey])!=nil)
      break;
    }
   }
   
   Class          class=[[[self class] registeredStoreTypes] objectForKey:storeType];

   if([class isSubclassOfClass:[NSIncrementalStore class]]){
    /* Verify (and, when requested, migrate) the on-disk store before it
       is opened, like the atomic-store path below.  Only stores which can
       read metadata from disk (e.g. the SQLite store) participate;
       incremental store classes which inherit the abstract
       +metadataForPersistentStoreWithURL:error: are skipped. */
    if([class methodForSelector:@selector(metadataForPersistentStoreWithURL:error:)]!=[NSPersistentStore methodForSelector:@selector(metadataForPersistentStoreWithURL:error:)]){
     if(![self _checkVersionCompatibilityOfStoreClass:class type:storeType configuration:configuration URL:storeURL options:options error:error])
      return nil;
    }

    NSIncrementalStore *store=[[[class alloc] initWithPersistentStoreCoordinator:self configurationName:configuration URL:storeURL options:options] autorelease];

    if(![store loadMetadata:error])
     return nil;

    /* Apple verifies that the store's type matches the requested store
       type after -loadMetadata: returns and fails with
       NSPersistentStoreTypeMismatchError (134010) if it does not. */
    if(storeType!=nil && ![storeType isEqualToString:[store type]]){
     if(error!=NULL){
      NSDictionary *userInfo=[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The store type '%@' does not match the requested type '%@'",[store type],storeType] forKey:NSLocalizedDescriptionKey];

      *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreTypeMismatchError userInfo:userInfo];
     }
     return nil;
    }

    NSString *uuid=[[store metadata] objectForKey:NSStoreUUIDKey];

    if(uuid!=nil)
     [store setIdentifier:uuid];

    [_stores addObject:store];
    [store didAddToPersistentStoreCoordinator:self];

    return store;
   }

   /* Verify (and, when requested, migrate) the on-disk store before it is
      opened so the current model reads up-to-date data. */
   if(![self _checkVersionCompatibilityOfStoreClass:class type:storeType configuration:configuration URL:storeURL options:options error:error])
    return nil;

   NSAtomicStore *store=[[[class alloc] initWithPersistentStoreCoordinator:self configurationName:configuration URL:storeURL options:options] autorelease];

   if(![store load:error])
    return nil;

   [self _stampVersioningMetadataForStore:store configuration:configuration];

   [_stores addObject:store];

   return store;
}

-(BOOL)setURL:(NSURL *)url forPersistentStore:(NSPersistentStore *)store {
   [store setURL:url];
   return YES;
}

- (BOOL)removePersistentStore:(NSPersistentStore *)store error:(NSError **)error {
   NSArray      *remove=[NSArray arrayWithObject:store];
   NSDictionary *userInfo=[NSDictionary dictionaryWithObject:remove forKey:NSRemovedPersistentStoresKey];

   [store willRemoveFromPersistentStoreCoordinator:self];

   [[NSNotificationCenter defaultCenter] postNotificationName:NSPersistentStoreCoordinatorStoresDidChangeNotification object:self userInfo:userInfo];
   
   [_stores removeObjectIdenticalTo:store];
   
   return YES;
}

-(NSPersistentStore *)migratePersistentStore:(NSPersistentStore *)store toURL:(NSURL *)URL options:(NSDictionary *)options withType:(NSString *)storeType error:(NSError **)error {
    NSUnimplementedMethod();
    return nil;
}

-(NSArray *)persistentStores {
   return _stores;
}

-(NSPersistentStore *)persistentStoreForURL:(NSURL *)URL {
   for(NSPersistentStore *check in _stores){
    if([[check URL] isEqual:URL])
     return check;
   }
   
   return nil;
}

-(NSURL *)URLForPersistentStore:(NSPersistentStore *)store {
   return [store URL];
}

-(void)lock {
   [_lock lock];
}


-(BOOL)tryLock {
   return [_lock tryLock];
}

-(void)unlock {
   [_lock unlock];
}

-(NSDictionary *)metadataForPersistentStore:(NSPersistentStore *)store {
   return [store metadata];
}

- (void)setMetadata:(NSDictionary *)value forPersistentStore:(NSPersistentStore *)store {
   [store setMetadata:value];
}

+(BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreOfType:(NSString *)storeType URL:(NSURL *)url error:(NSError **)error {
   Class check=[[self registeredStoreTypes] objectForKey:storeType];
   
   return [check setMetadata:metadata forPersistentStoreWithURL:url error:error];
}

+(NSDictionary *)metadataForPersistentStoreOfType:(NSString *)storeType URL:(NSURL *)url error:(NSError **)error {
   Class check=[[self registeredStoreTypes] objectForKey:storeType];
   
   return [check metadataForPersistentStoreWithURL:url error:error];
}

-(NSPersistentStore *)_persistentStoreWithIdentifier:(NSString *)identifier {
   for(NSPersistentStore *check in _stores)
    if([[check identifier] isEqualToString:identifier])
     return check;
   
   return nil;
}

-(NSPersistentStore *)_persistentStoreForObjectID:(NSManagedObjectID *)objectID {
   NSEntityDescription  *entity=[objectID entity];
   NSString             *storeIdentifier=[objectID storeIdentifier];
   NSPersistentStore    *check=[self _persistentStoreWithIdentifier:storeIdentifier];
   
   if(check!=nil)
    return check;
    
   NSManagedObjectModel *model=[self managedObjectModel];
   
   if([_stores count]==0){
    [NSException raise:NSInvalidArgumentException format:@"-[%@ %@] no persistent stores",
                 NSStringFromClass([self class]),NSStringFromSelector(_cmd)];
    return nil;
   }
   
   /* Find the first store whose configuration contains the entity. */
   for(check in _stores){
    NSString *configurationName=[check configurationName];
    NSArray  *entities=[model entitiesForConfiguration:configurationName];
        
    if([entities containsObject:entity])
     return check;
   }

   return [_stores objectAtIndex:0];
}

-(NSPersistentStore *)_persistentStoreForObject:(NSManagedObject *)object {
   return [self _persistentStoreForObjectID:[object objectID]];
}

-(NSManagedObjectID *)managedObjectIDForURIRepresentation:(NSURL *)URL {
   NSString             *scheme=[URL scheme];
   NSString             *host=[URL host];
   NSString             *path=[URL path];
   NSString             *referenceObject=[path lastPathComponent];
   NSString             *entityName=[[path stringByDeletingLastPathComponent] lastPathComponent];
   NSManagedObjectModel *model=[self managedObjectModel];
   NSEntityDescription  *entity=[[model entitiesByName] objectForKey:entityName];
   NSPersistentStore    *store=[self _persistentStoreWithIdentifier:host];

   if([store isKindOfClass:[NSIncrementalStore class]])
    return [[(NSIncrementalStore *)store newObjectIDForEntity:entity referenceObject:referenceObject] autorelease];

   return [(NSAtomicStore *)store objectIDForEntity:entity referenceObject:referenceObject];
}

@end
