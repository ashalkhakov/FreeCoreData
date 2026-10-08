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
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSFetchRequest.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import "NSInMemoryPersistentStore.h"
#import "NSSQLitePersistentStore.h"
#import "NSManagedObjectID-Private.h"
#import "NSDerivedAttributeDescription-Private.h"
#import "NSPersistentHistory-Private.h"
#import "CoreDataUtilities.h"

NSString * const NSStoreTypeKey=@"NSStoreTypeKey";
NSString * const NSStoreUUIDKey=@"NSStoreUUIDKey";
NSString * const NSStoreModelVersionHashesKey=@"NSStoreModelVersionHashes";
NSString * const NSStoreModelVersionIdentifiersKey=@"NSStoreModelVersionIdentifiers";

NSString * const NSXMLStoreType=@"NSXMLStoreType";
NSString * const NSSQLiteStoreType=@"SQLite";
NSString * const NSInMemoryStoreType=@"NSInMemoryStoreType";
NSString * const NSMigratePersistentStoresAutomaticallyOption=@"NSMigratePersistentStoresAutomaticallyOption";
NSString * const NSReadOnlyPersistentStoreOption=@"NSReadOnlyPersistentStoreOption";
NSString * const NSInferMappingModelAutomaticallyOption=@"NSInferMappingModelAutomaticallyOption";
NSString * const NSIgnorePersistentStoreVersioningOption=@"NSIgnorePersistentStoreVersioningOption";

NSString * const NSPersistentStoreCoordinatorStoresDidChangeNotification=@"NSPersistentStoreCoordinatorStoresDidChangeNotification";
NSString * const NSAddedPersistentStoresKey=@"NSAddedPersistentStoresKey";
NSString * const NSRemovedPersistentStoresKey=@"NSRemovedPersistentStoresKey";
NSString * const NSUUIDChangedPersistentStoresKey=@"NSUUIDChangedPersistentStoresKey";

NSString * const NSPersistentHistoryTrackingKey=@"NSPersistentHistoryTrackingKey";
NSString * const NSPersistentStoreRemoteChangeNotificationPostOptionKey=@"NSPersistentStoreRemoteChangeNotificationOptionKey";
NSString * const NSPersistentStoreRemoteChangeNotification=@"NSPersistentStoreRemoteChangeNotification";
NSString * const NSPersistentHistoryTokenKey=@"historyToken";

/* Implemented by stores that track persistent history (the SQLite
   store); other store classes are simply skipped when a token is
   assembled. */
@interface NSPersistentStore(CDModelCache)
/* Implemented by store classes that keep the model in the store (the
   SQLite one does); asked only when the bundles hold no matching model. */
+(NSManagedObjectModel *)_cachedModelForPersistentStoreWithURL:(NSURL *)url options:(NSDictionary *)options;
@end

@interface NSPersistentStore(CDHistoryTracking)
-(BOOL)_historyTrackingEnabled;
-(long long)_lastHistoryTransactionNumber;
@end

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
   _lock=[[NSRecursiveLock alloc] init];
   _model=[model retain];
   _stores=[[NSMutableArray alloc] init];

   /* The model is in use from here on: freeze its entities and make
      sure every entity's generated property accessors exist - however
      the model was built (compiled and decoded, or assembled in
      code). */
   for(NSEntityDescription *entity in [model entities])
    [entity _setInstantiated];

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

   /* Failing that, the model the store itself was written with, which is
      where Apple looks too (its Z_MODELCACHE): a model built in code, or
      one whose compiled copy is no longer in any bundle, is otherwise a
      store nothing can migrate. */
   if(sourceModel==nil && [class respondsToSelector:@selector(_cachedModelForPersistentStoreWithURL:options:)])
    sourceModel=[class _cachedModelForPersistentStoreWithURL:storeURL options:options];

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

   /* The store's own options go to both ends of the migration.  Chiefly
      NSPersistentHistoryTrackingKey: a store that tracks history has to
      migrate into one that does, or the destination keeps the source's
      UUID - the same store, as far as any token says - while starting its
      transaction numbering again, and a token held from before the
      migration then names a transaction that will not come round again
      for as many saves as the store had made.  The migration's own keys
      do not travel, and neither does read-only: the destination is
      written to by definition. */
   NSMutableDictionary *migrationOptions=[NSMutableDictionary dictionaryWithDictionary:(options!=nil)?options:[NSDictionary dictionary]];

   [migrationOptions removeObjectForKey:NSMigratePersistentStoresAutomaticallyOption];
   [migrationOptions removeObjectForKey:NSInferMappingModelAutomaticallyOption];
   [migrationOptions removeObjectForKey:NSReadOnlyPersistentStoreOption];

   if(![manager migrateStoreFromURL:storeURL type:storeType options:migrationOptions withMappingModel:mappingModel toDestinationURL:temporaryURL destinationType:storeType destinationOptions:migrationOptions error:error])
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

/* Every object of store copied into target, which has the same
   configuration: each entity's own objects (not its subentities', which
   are fetched as themselves) with their attributes, then their
   relationships pointed at the copies. Not saved. */
-(BOOL)_copyObjectsOfStore:(NSPersistentStore *)store toStore:(NSPersistentStore *)target inContext:(NSManagedObjectContext *)context error:(NSError **)error {
   NSMutableDictionary *copies=[NSMutableDictionary dictionary];
   NSMutableArray      *originals=[NSMutableArray array];
   NSArray             *stores=[NSArray arrayWithObject:store];
   NSString            *configuration=[store configurationName];
   /* No configuration: the default one, which has every entity. */
   NSArray             *entities=(configuration!=nil)?[[self managedObjectModel] entitiesForConfiguration:configuration]:[[self managedObjectModel] entities];

   for(NSEntityDescription *entity in entities){
    if([entity isAbstract])
     continue;

    NSFetchRequest *fetch=[[[NSFetchRequest alloc] init] autorelease];

    [fetch setEntity:entity];
    [fetch setIncludesSubentities:NO];
    [fetch setAffectedStores:stores];

    NSArray *found=[context executeFetchRequest:fetch error:error];

    if(found==nil)
     return NO;

    for(NSManagedObject *original in found){
     NSManagedObject *copy=[NSEntityDescription insertNewObjectForEntityForName:[entity name] inManagedObjectContext:context];

     [context assignObject:copy toPersistentStore:target];
     for(NSAttributeDescription *attribute in [[entity attributesByName] allValues]){
      if([attribute isTransient] || [attribute isKindOfClass:[NSDerivedAttributeDescription class]])
       continue;
      [copy setValue:[original valueForKey:[attribute name]] forKey:[attribute name]];
     }
     [copies setObject:copy forKey:[original objectID]];
     [originals addObject:original];
    }
   }

   for(NSManagedObject *original in originals){
    NSManagedObject *copy=[copies objectForKey:[original objectID]];

    for(NSRelationshipDescription *relationship in [[[original entity] relationshipsByName] allValues]){
     if([relationship isTransient])
      continue;

     NSString *name=[relationship name];
     id        value=[original valueForKey:name];

     if(![relationship isToMany]){
      [copy setValue:(value!=nil ? [copies objectForKey:[value objectID]] : nil) forKey:name];
      continue;
     }

     NSMutableArray *related=[NSMutableArray array];

     for(NSManagedObject *each in value){
      NSManagedObject *mapped=[copies objectForKey:[each objectID]];

      if(mapped!=nil)
       [related addObject:mapped];
     }
     if([relationship isOrdered])
      [copy setValue:[NSOrderedSet orderedSetWithArray:related] forKey:name];
     else
      [copy setValue:[NSSet setWithArray:related] forKey:name];
    }
   }
   return YES;
}

/* As Apple's: a store of storeType at URL, with store's configuration,
   given every object store has and its metadata (but its type and
   UUID, the new store's own); then store is removed from the
   coordinator (its file, or database, is left as it was). The new store
   is returned; nil, with store left in place, when it cannot be made or
   saved. Apple's also takes another coordinator's store; this one does
   not (it fetches through itself). */
-(NSPersistentStore *)migratePersistentStore:(NSPersistentStore *)store toURL:(NSURL *)URL options:(NSDictionary *)options withType:(NSString *)storeType error:(NSError **)error {
   if(![_stores containsObject:store]){
    if(error!=NULL){
     NSDictionary *userInfo=[NSDictionary dictionaryWithObject:@"The store to migrate is not one of this coordinator's" forKey:NSLocalizedDescriptionKey];

     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError userInfo:userInfo];
    }
    return nil;
   }

   NSPersistentStore *target=[self addPersistentStoreWithType:storeType configuration:[store configurationName] URL:URL options:options error:error];

   if(target==nil)
    return nil;

   NSAutoreleasePool      *pool=[NSAutoreleasePool new];
   NSManagedObjectContext *context=[[NSManagedObjectContext alloc] init];
   NSError                *failure=nil;
   BOOL                    copied;

   [context setPersistentStoreCoordinator:self];
   [context setUndoManager:nil];
   copied=[self _copyObjectsOfStore:store toStore:target inContext:context error:&failure];
   if(copied){
    NSMutableDictionary *metadata=[[[self metadataForPersistentStore:target] mutableCopy] autorelease];
    NSDictionary        *old=[self metadataForPersistentStore:store];

    for(NSString *key in old){
     if([key isEqualToString:NSStoreTypeKey] || [key isEqualToString:NSStoreUUIDKey])
      continue;
     [metadata setObject:[old objectForKey:key] forKey:key];
    }
    [self setMetadata:metadata forPersistentStore:target];
    copied=[context save:&failure];
   }
   [failure retain];
   [context release];
   [pool release];
   [failure autorelease];

   if(!copied){
    [self removePersistentStore:target error:NULL];
    if(error!=NULL)
     *error=failure;
    return nil;
   }

   [target retain];
   [self removePersistentStore:store error:NULL];
   return [target autorelease];
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

-(NSPersistentHistoryToken *)currentPersistentHistoryTokenFromStores:(NSArray *)stores {
   NSMutableDictionary *positions=[NSMutableDictionary dictionary];

   [self lock];
   if(stores==nil)
    stores=[[_stores copy] autorelease];

   for(NSPersistentStore *store in stores){
    if(![store respondsToSelector:@selector(_historyTrackingEnabled)] || ![store _historyTrackingEnabled])
     continue;

    [positions setObject:[NSNumber numberWithLongLong:[store _lastHistoryTransactionNumber]] forKey:[store identifier]];
   }
   [self unlock];

   if([positions count]==0)
    return nil;

   return [[[NSPersistentHistoryToken alloc] _initWithPositions:positions] autorelease];
}

-(NSDictionary *)metadataForPersistentStore:(NSPersistentStore *)store {
   return [store metadata];
}

- (void)setMetadata:(NSDictionary *)value forPersistentStore:(NSPersistentStore *)store {
   [store setMetadata:value];
}

/* An unregistered store type: nothing can be said about the URL, and a
   caller reading *error after a nil return has to find something there. */
+(Class)_storeClassForType:(NSString *)storeType error:(NSError **)error {
   Class check=[[self registeredStoreTypes] objectForKey:storeType];

   if(check==nil && error!=NULL){
    NSDictionary *userInfo=[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"No persistent store class is registered for the type '%@'",storeType] forKey:NSLocalizedDescriptionKey];

    *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreInvalidTypeError userInfo:userInfo];
   }
   return check;
}

/* The four of these go through the store class's options-aware pair, whose
   default drops the options again: a store that cares (a SQL backend whose
   schema is in its options) overrides that pair, and then asking for a
   store's metadata with the options it is opened with reaches the store
   that was asked about rather than whatever the connection's default
   schema holds. */
+(BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreOfType:(NSString *)storeType URL:(NSURL *)url error:(NSError **)error {
   return [self setMetadata:metadata forPersistentStoreOfType:storeType URL:url options:nil error:error];
}

+(NSDictionary *)metadataForPersistentStoreOfType:(NSString *)storeType URL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error {
   Class check=[self _storeClassForType:storeType error:error];

   if(check==Nil)
    return nil;

   return [check metadataForPersistentStoreWithURL:url options:options error:error];
}

+(BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreOfType:(NSString *)storeType URL:(NSURL *)url options:(NSDictionary *)options error:(NSError **)error {
   Class check=[self _storeClassForType:storeType error:error];

   if(check==Nil)
    return NO;

   return [check setMetadata:metadata forPersistentStoreWithURL:url options:options error:error];
}

+(NSDictionary *)metadataForPersistentStoreOfType:(NSString *)storeType URL:(NSURL *)url error:(NSError **)error {
   return [self metadataForPersistentStoreOfType:storeType URL:url options:nil error:error];
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

   /* Parse the raw URI string: x-coredata://HOST/Entity/pREFERENCE.
      Verified on macOS: the reference is everything after the entity
      component with the generic "p" prefix stripped, kept VERBATIM -
      percent escapes are not decoded and a "/" inside a reference stays
      part of it (Apple returns e.g. "key%20with/slash").  A missing "p"
      (URIs written by older versions of this port) is tolerated. */
   NSString *absolute=[URL absoluteString];
   NSString *referenceObject=nil;
   NSString *entityName=nil;
   NSRange   schemeMarker=[absolute rangeOfString:@"://"];

   if(schemeMarker.location!=NSNotFound){
    NSRange hostEnd=[absolute rangeOfString:@"/" options:0 range:NSMakeRange(NSMaxRange(schemeMarker),[absolute length]-NSMaxRange(schemeMarker))];

    if(hostEnd.location!=NSNotFound){
     NSString *pathPart=[absolute substringFromIndex:NSMaxRange(hostEnd)];
     NSRange   entityEnd=[pathPart rangeOfString:@"/"];

     if(entityEnd.location!=NSNotFound){
      entityName=[[pathPart substringToIndex:entityEnd.location] stringByRemovingPercentEncoding];
      referenceObject=[pathPart substringFromIndex:NSMaxRange(entityEnd)];

      if([referenceObject hasPrefix:@"p"])
       referenceObject=[referenceObject substringFromIndex:1];
     }
    }
   }
   NSManagedObjectModel *model=[self managedObjectModel];
   NSEntityDescription  *entity=[[model entitiesByName] objectForKey:entityName];
   NSPersistentStore    *store=[self _persistentStoreWithIdentifier:host];

   if([store isKindOfClass:[NSIncrementalStore class]])
    return [[(NSIncrementalStore *)store newObjectIDForEntity:entity referenceObject:referenceObject] autorelease];

   return [(NSAtomicStore *)store objectIDForEntity:entity referenceObject:referenceObject];
}

@end
