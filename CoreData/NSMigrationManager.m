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
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/CoreDataErrors.h>

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

-(BOOL)migrateStoreFromURL:(NSURL *)sourceURL type:(NSString *)sStoreType options:(NSDictionary *)sOptions withMappingModel:(NSMappingModel *)mappings toDestinationURL:(NSURL *)dURL destinationType:(NSString *)dStoreType destinationOptions:(NSDictionary *)dOptions error:(NSError **)error {
   [self reset];

   mappings=[mappings retain];
   [_mappingModel release];
   _mappingModel=mappings;

   /* Open the source store, ignoring versioning so that a store written
      with the (older) source model can be read. */
   NSMutableDictionary *sourceOptions=[NSMutableDictionary dictionaryWithDictionary:sOptions];
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
     NSFetchRequest *request=[[[NSFetchRequest alloc] init] autorelease];

     [request setEntity:sourceEntity];

     NSArray *sourceInstances=[_sourceContext executeFetchRequest:request error:error];

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

   if(![_destinationContext save:error])
    return NO;

   _migrationProgress=1.0f;

   return YES;
}

@end
