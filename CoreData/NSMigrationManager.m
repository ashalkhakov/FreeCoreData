/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSMigrationManager.h>
#import <CoreData/NSMappingModel.h>
#import <CoreData/NSEntityMapping.h>
#import <CoreData/NSEntityMigrationPolicy.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSFetchRequest.h>
#import <Foundation/NSExpression.h>
#import <Foundation/NSPredicate.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/CoreDataErrors.h>
#import <CoreData/NSPersistentStore.h>
#import "NSPersistentHistory-Private.h"

@implementation NSMigrationManager

-initWithSourceModel:(NSManagedObjectModel *)sourceModel destinationModel:(NSManagedObjectModel *)destinationModel {
   _sourceModel=[sourceModel retain];
   _destinationModel=[destinationModel retain];
   _associationsByMappingName=[[NSMutableDictionary alloc] init];
   return self;
}

-(void)dealloc {
   [_sourceModel release];
   [_destinationModel release];
   [_mappingModel release];
   [_sourceCoordinator release];
   [_destinationCoordinator release];
   [_sourceContext release];
   [_destinationContext release];
   [_associationsByMappingName release];
   [_userInfo release];
   [_migrationError release];
   [super dealloc];
}

-(NSManagedObjectModel *)sourceModel {
   return _sourceModel;
}

-(NSManagedObjectModel *)destinationModel {
   return _destinationModel;
}

-(NSMappingModel *)mappingModel {
   return _mappingModel;
}

-(NSManagedObjectContext *)sourceContext {
   return _sourceContext;
}

-(NSManagedObjectContext *)destinationContext {
   return _destinationContext;
}

-(NSEntityDescription *)sourceEntityForEntityMapping:(NSEntityMapping *)mEntity {
   NSString *name=[mEntity sourceEntityName];

   return (name==nil)?nil:[[_sourceModel entitiesByName] objectForKey:name];
}

-(NSEntityDescription *)destinationEntityForEntityMapping:(NSEntityMapping *)mEntity {
   NSString *name=[mEntity destinationEntityName];

   return (name==nil)?nil:[[_destinationModel entitiesByName] objectForKey:name];
}

-(NSEntityMapping *)currentEntityMapping {
   return _currentEntityMapping;
}

-(NSMutableDictionary *)_associationForMappingName:(NSString *)mappingName {
   NSMutableDictionary *association=[_associationsByMappingName objectForKey:mappingName];

   if(association==nil){
    association=[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSMutableArray array],@"sources",[NSMutableArray array],@"destinations",nil];
    [_associationsByMappingName setObject:association forKey:mappingName];
   }

   return association;
}

-(void)associateSourceInstance:(NSManagedObject *)sourceInstance withDestinationInstance:(NSManagedObject *)destinationInstance forEntityMapping:(NSEntityMapping *)entityMapping {
   NSMutableDictionary *association=[self _associationForMappingName:[entityMapping name]];

   [[association objectForKey:@"sources"] addObject:sourceInstance];
   [[association objectForKey:@"destinations"] addObject:destinationInstance];
}

/* What a source expression asks this manager for, and what a custom policy
   fetches with: a request on the source model's entity of that name,
   narrowed by a predicate written as a string.  "TRUEPREDICATE" - which is
   what an unfiltered mapping says - narrows nothing. */
-(NSFetchRequest *)fetchRequestForSourceEntityNamed:(NSString *)entityName predicateString:(NSString *)predicateString {
   NSEntityDescription *entity=[[_sourceModel entitiesByName] objectForKey:entityName];

   if(entity==nil)
    return nil;

   NSFetchRequest *request=[[[NSFetchRequest alloc] init] autorelease];

   [request setEntity:entity];

   if([predicateString length]>0)
    [request setPredicate:[NSPredicate predicateWithFormat:predicateString]];

   return request;
}

-(NSArray *)destinationInstancesForEntityMappingNamed:(NSString *)mappingName sourceInstances:(NSArray *)sourceInstances {
   NSDictionary   *association=[_associationsByMappingName objectForKey:mappingName];
   NSArray        *sources=[association objectForKey:@"sources"];
   NSArray        *destinations=[association objectForKey:@"destinations"];
   NSMutableArray *result=[NSMutableArray array];

   for(NSManagedObject *source in sourceInstances){
    NSUInteger index=[sources indexOfObjectIdenticalTo:source];

    if(index!=NSNotFound)
     [result addObject:[destinations objectAtIndex:index]];
   }

   return result;
}

-(NSArray *)sourceInstancesForEntityMappingNamed:(NSString *)mappingName destinationInstances:(NSArray *)destinationInstances {
   NSDictionary   *association=[_associationsByMappingName objectForKey:mappingName];
   NSArray        *sources=[association objectForKey:@"sources"];
   NSArray        *destinations=[association objectForKey:@"destinations"];
   NSMutableArray *result=[NSMutableArray array];

   for(NSManagedObject *destination in destinationInstances){
    NSUInteger index=[destinations indexOfObjectIdenticalTo:destination];

    if(index!=NSNotFound)
     [result addObject:[sources objectAtIndex:index]];
   }

   return result;
}

/* Private: global source instance to destination instance lookup used to
   recreate relationships across entity mappings. */
-(NSManagedObject *)_destinationInstanceForSourceInstance:(NSManagedObject *)sourceInstance {
   for(NSString *mappingName in _associationsByMappingName){
    NSDictionary *association=[_associationsByMappingName objectForKey:mappingName];
    NSArray      *sources=[association objectForKey:@"sources"];
    NSUInteger    index=[sources indexOfObjectIdenticalTo:sourceInstance];

    if(index!=NSNotFound)
     return [[association objectForKey:@"destinations"] objectAtIndex:index];
   }

   return nil;
}

-(float)migrationProgress {
   return _migrationProgress;
}

-(NSDictionary *)userInfo {
   return _userInfo;
}

-(void)setUserInfo:(NSDictionary *)userInfo {
   userInfo=[userInfo copy];
   [_userInfo release];
   _userInfo=userInfo;
}

-(void)reset {
   [_associationsByMappingName removeAllObjects];
   [_sourceContext release];
   _sourceContext=nil;
   [_destinationContext release];
   _destinationContext=nil;
   [_sourceCoordinator release];
   _sourceCoordinator=nil;
   [_destinationCoordinator release];
   _destinationCoordinator=nil;
   [_migrationError release];
   _migrationError=nil;
   _currentEntityMapping=nil;
   _migrationProgress=0.0f;
   _cancelled=NO;
}

-(void)cancelMigrationWithError:(NSError *)error {
   _cancelled=YES;
   error=[error retain];
   [_migrationError release];
   _migrationError=error;
}

/* Which of the source store's objects a mapping applies to.

   A mapping model written in Xcode says so in the mapping's source
   expression, which is of one shape:

     FETCH(FUNCTION($manager, "fetchRequestForSourceEntityNamed:predicateString:",
                    "Note", "text BEGINSWITH 'keep'"),
           FUNCTION($manager, "sourceContext"), NO)

   - a request this manager builds, run against the context it is asked
   for, which is how a mapping takes a subset of an entity.  Evaluating it
   is all that is needed: $manager is this object, and the methods the
   expression names are below.  A mapping without one - every inferred
   mapping, and every mapping built in code - means the whole entity. */
-(NSArray *)_sourceInstancesForEntityMapping:(NSEntityMapping *)mapping error:(NSError **)error {
   NSExpression *sourceExpression=[mapping sourceExpression];

   if(sourceExpression!=nil){
    NSMutableDictionary *context=[NSMutableDictionary dictionaryWithObject:self forKey:@"manager"];
    id                   instances=nil;

    NS_DURING
     instances=[sourceExpression expressionValueWithObject:nil context:context];
    NS_HANDLER
     if(error!=NULL)
      *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSMigrationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The source expression of entity mapping '%@' could not be evaluated: %@",[mapping name],[localException reason]] forKey:NSLocalizedDescriptionKey]];
     instances=nil;
     NS_VALUERETURN(nil,NSArray *);
    NS_ENDHANDLER

    if([instances isKindOfClass:[NSArray class]])
     return instances;
    if([instances isKindOfClass:[NSSet class]] || [instances isKindOfClass:[NSOrderedSet class]])
     return [instances allObjects];
    if(instances==nil)
     return [NSArray array];

    if(error!=NULL)
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSMigrationError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The source expression of entity mapping '%@' answered %@, not objects to migrate",[mapping name],[instances class]] forKey:NSLocalizedDescriptionKey]];
    return nil;
   }

   NSFetchRequest *request=[[[NSFetchRequest alloc] init] autorelease];

   [request setEntity:[self sourceEntityForEntityMapping:mapping]];

   return [_sourceContext executeFetchRequest:request error:error];
}

-(NSEntityMigrationPolicy *)_policyForEntityMapping:(NSEntityMapping *)mapping {
   NSString *className=[mapping entityMigrationPolicyClassName];
   Class     policyClass=(className!=nil)?NSClassFromString(className):Nil;

   if(policyClass==Nil)
    policyClass=[NSEntityMigrationPolicy class];

   return [[[policyClass alloc] init] autorelease];
}

static BOOL cancelledError(NSMigrationManager *self,NSError *migrationError,NSError **error){
   if(error!=NULL){
    if(migrationError!=nil)
     *error=migrationError;
    else
     *error=[NSError errorWithDomain:NSCocoaErrorDomain code:NSMigrationCancelledError userInfo:nil];
   }
   return NO;
}

/* The store comes through a migration as the same store, as on Apple: the
   destination takes the source's metadata - its UUID, and what an
   application keeps there - with the version stamps of its own model.

   Before the objects are saved, not after: an atomic store (XML, binary)
   writes its metadata and its identifier as part of saving, so metadata
   set afterwards would live in an ivar and never reach the file. */
-(BOOL)_carryOverMetadataWithError:(NSError **)error {
   NSPersistentStore *source=[[_sourceCoordinator persistentStores] lastObject];
   NSPersistentStore *destination=[[_destinationCoordinator persistentStores] lastObject];

   if(source==nil || destination==nil)
    return YES;

   NSDictionary        *own=[_destinationCoordinator metadataForPersistentStore:destination];
   NSMutableDictionary *metadata=[NSMutableDictionary dictionaryWithDictionary:[_sourceCoordinator metadataForPersistentStore:source]];

   for(NSString *key in [metadata allKeys])
    if([key hasPrefix:@"NSStoreModelVersion"])
     [metadata removeObjectForKey:key];
   for(NSString *key in own)
    if([key hasPrefix:@"NSStoreModelVersion"] || [key isEqualToString:NSStoreTypeKey])
     [metadata setObject:[own objectForKey:key] forKey:key];
   [_destinationCoordinator setMetadata:metadata forPersistentStore:destination];

   /* The store object's own identity, which the coordinator takes from the
      metadata when it opens a store and nothing else updates: left alone,
      -identifier would answer the UUID this store was born with while its
      metadata says the source's, and history read through
      -destinationContext would be stamped with the wrong store. */
   NSString *uuid=[metadata objectForKey:NSStoreUUIDKey];

   if([uuid length]>0)
    [destination setIdentifier:uuid];

   return YES;
}

/* And, between two SQLite stores tracking history, the source's history:
   its objects' keys made the destination's, and a transaction marking the
   migration (under the author Apple's migrations write as).  This half
   runs after the save, which is where the destination's objects get the
   permanent keys the history has to name. */
-(BOOL)_carryOverHistoryWithError:(NSError **)error {
   NSPersistentStore *source=[[_sourceCoordinator persistentStores] lastObject];
   NSPersistentStore *destination=[[_destinationCoordinator persistentStores] lastObject];

   if(source==nil || destination==nil)
    return YES;
   if(![source isKindOfClass:[NSSQLitePersistentStore class]] || ![destination isKindOfClass:[NSSQLitePersistentStore class]])
    return YES;

   /* Both keyed by the SOURCE entity's name: that is what a history row
      names, and its primary keys are in that entity's key space.  Keying
      the other way round would merge the key spaces of two source
      entities mapped into one destination entity, which both count from
      1, and one's history would land on the other's objects. */
   NSMutableDictionary *entityNames=[NSMutableDictionary dictionary];
   NSMutableDictionary *primaryKeys=[NSMutableDictionary dictionary];

   /* Where one source entity is mapped into several destination entities,
      a history row can name only one of them; the mapping model's order
      decides, rather than a dictionary's. */
   for(NSEntityMapping *mapping in [_mappingModel entityMappings])
    if([mapping sourceEntityName]!=nil && [mapping destinationEntityName]!=nil &&
       [mapping mappingType]!=NSRemoveEntityMappingType &&
       [entityNames objectForKey:[mapping sourceEntityName]]==nil)
     [entityNames setObject:[mapping destinationEntityName] forKey:[mapping sourceEntityName]];

   for(NSEntityMapping *mapping in [_mappingModel entityMappings]){
    NSDictionary *association=[_associationsByMappingName objectForKey:[mapping name]];
    NSArray      *sources=[association objectForKey:@"sources"];
    NSArray      *destinations=[association objectForKey:@"destinations"];
    NSUInteger    i,count=[sources count];

    for(i=0;i<count && i<[destinations count];i++){
     NSManagedObject     *s=[sources objectAtIndex:i];
     NSManagedObject     *d=[destinations objectAtIndex:i];
     NSString            *sourceName=[[s entity] name];
     NSMutableDictionary *keys=[primaryKeys objectForKey:sourceName];
     NSNumber            *sourceKey=[NSNumber numberWithLongLong:[(NSSQLitePersistentStore *)source _primaryKeyOfObjectID:[s objectID]]];

     if(keys==nil){
      keys=[NSMutableDictionary dictionary];
      [primaryKeys setObject:keys forKey:sourceName];
     }
     if([entityNames objectForKey:sourceName]==nil)
      [entityNames setObject:[[d entity] name] forKey:sourceName];

     /* The same rule as above, for the same reason: the first destination
        object a source object was mapped into is the one its history
        follows. */
     if([keys objectForKey:sourceKey]==nil)
      [keys setObject:[NSNumber numberWithLongLong:[(NSSQLitePersistentStore *)destination _primaryKeyOfObjectID:[d objectID]]]
               forKey:sourceKey];
    }
   }

   return [(NSSQLitePersistentStore *)destination _adoptHistoryOfStoreAtURL:[source URL]
                                                                entityNames:entityNames
                                                                primaryKeys:primaryKeys
                                                                     author:@"com.apple.coredata.schemamigrator: NSMigrationManager"
                                                                      error:error];
}

-(BOOL)migrateStoreFromURL:(NSURL *)sourceURL type:(NSString *)sStoreType options:(NSDictionary *)sOptions withMappingModel:(NSMappingModel *)mappings toDestinationURL:(NSURL *)dURL destinationType:(NSString *)dStoreType destinationOptions:(NSDictionary *)dOptions error:(NSError **)error {
   [self reset];

   mappings=[mappings retain];
   [_mappingModel release];
   _mappingModel=mappings;

   /* Open the source store, ignoring versioning so that a store written
      with the (older) source model can be read. */
   NSMutableDictionary *sourceOptions=(sOptions!=nil)?[NSMutableDictionary dictionaryWithDictionary:sOptions]:[NSMutableDictionary dictionary];
   [sourceOptions setObject:[NSNumber numberWithBool:YES] forKey:NSIgnorePersistentStoreVersioningOption];

   _sourceCoordinator=[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:_sourceModel];
   if([_sourceCoordinator addPersistentStoreWithType:sStoreType configuration:nil URL:sourceURL options:sourceOptions error:error]==nil)
    return NO;

   _sourceContext=[[NSManagedObjectContext alloc] init];
   [_sourceContext setPersistentStoreCoordinator:_sourceCoordinator];

   /* The destination store is created from scratch. */
   if([dURL isFileURL])
    [[NSFileManager defaultManager] removeItemAtPath:[dURL path] error:NULL];

   _destinationCoordinator=[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:_destinationModel];
   if([_destinationCoordinator addPersistentStoreWithType:dStoreType configuration:nil URL:dURL options:dOptions error:error]==nil)
    return NO;

   _destinationContext=[[NSManagedObjectContext alloc] init];
   [_destinationContext setPersistentStoreCoordinator:_destinationCoordinator];

   NSArray    *entityMappings=[_mappingModel entityMappings];
   NSUInteger  mappingIndex=0,mappingCount=[entityMappings count];

   /* First pass: create the destination instances. */
   for(NSEntityMapping *mapping in entityMappings){
    NSEntityMigrationPolicy *policy=[self _policyForEntityMapping:mapping];

    if(_cancelled)
     return cancelledError(self,_migrationError,error);

    _currentEntityMapping=mapping;

    if(![policy beginEntityMapping:mapping manager:self error:error])
     return NO;

    NSEntityDescription *sourceEntity=[self sourceEntityForEntityMapping:mapping];

    if(sourceEntity!=nil && [mapping mappingType]!=NSRemoveEntityMappingType){
     NSArray *sourceInstances=[self _sourceInstancesForEntityMapping:mapping error:error];

     if(sourceInstances==nil)
      return NO;

     for(NSManagedObject *sInstance in sourceInstances){
      if(_cancelled)
       return cancelledError(self,_migrationError,error);

      if(![policy createDestinationInstancesForSourceInstance:sInstance entityMapping:mapping manager:self error:error])
       return NO;
     }
    }

    if(![policy endInstanceCreationForEntityMapping:mapping manager:self error:error])
     return NO;

    mappingIndex++;
    _migrationProgress=0.5f*((float)mappingIndex/(float)((mappingCount==0)?1:mappingCount));
   }

   /* Second pass: recreate the relationships between the migrated
      instances, then validate and close out each mapping. */
   mappingIndex=0;
   for(NSEntityMapping *mapping in entityMappings){
    NSEntityMigrationPolicy *policy=[self _policyForEntityMapping:mapping];

    if(_cancelled)
     return cancelledError(self,_migrationError,error);

    _currentEntityMapping=mapping;

    NSArray *destinations=[[_associationsByMappingName objectForKey:[mapping name]] objectForKey:@"destinations"];

    for(NSManagedObject *dInstance in destinations){
     if(_cancelled)
      return cancelledError(self,_migrationError,error);

     if(![policy createRelationshipsForDestinationInstance:dInstance entityMapping:mapping manager:self error:error])
      return NO;
    }

    if(![policy endRelationshipCreationForEntityMapping:mapping manager:self error:error])
     return NO;

    if(![policy performCustomValidationForEntityMapping:mapping manager:self error:error])
     return NO;

    if(![policy endEntityMapping:mapping manager:self error:error])
     return NO;

    mappingIndex++;
    _migrationProgress=0.5f+0.4f*((float)mappingIndex/(float)((mappingCount==0)?1:mappingCount));
   }

   _currentEntityMapping=nil;

   if(![self _carryOverMetadataWithError:error])
    return NO;

   if(![_destinationContext save:error])
    return NO;

   if(![self _carryOverHistoryWithError:error])
    return NO;

   /* Apple resets the migration progress once the migration completes. */
   _migrationProgress=0.0f;

   return YES;
}

@end
