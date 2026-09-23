/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSPersistentContainer.h"
#import "NSPersistentStoreDescription.h"
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

@implementation NSPersistentContainer

+(instancetype)persistentContainerWithName:(NSString *)name {
   return [[[self alloc] initWithName:name] autorelease];
}

+(instancetype)persistentContainerWithName:(NSString *)name
                        managedObjectModel:(NSManagedObjectModel *)model {
   return [[[self alloc] initWithName:name managedObjectModel:model] autorelease];
}

+(NSURL *)defaultDirectoryURL {
   NSArray  *paths=NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES);
   NSString *path=([paths count]>0)?[paths objectAtIndex:0]:NSTemporaryDirectory();

   return [NSURL fileURLWithPath:path isDirectory:YES];
}

/* <name>.momd / <name>.mom in the main bundle, else the bundle's
   merged model (mirrors Apple's name-only initializer). */
+(NSManagedObjectModel *)_modelNamed:(NSString *)name {
   NSBundle *bundle=[NSBundle mainBundle];
   NSURL    *modelURL=[bundle URLForResource:name withExtension:@"momd"];

   if(modelURL==nil)
    modelURL=[bundle URLForResource:name withExtension:@"mom"];
   if(modelURL!=nil)
    return [[[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL] autorelease];

   return [NSManagedObjectModel mergedModelFromBundles:[NSArray arrayWithObject:bundle]];
}

-(instancetype)initWithName:(NSString *)name {
   return [self initWithName:name
          managedObjectModel:[[self class] _modelNamed:name]];
}

-(instancetype)initWithName:(NSString *)name
         managedObjectModel:(NSManagedObjectModel *)model {
   if(model==nil){
    [self release];
    [NSException raise:NSInvalidArgumentException
                format:@"NSPersistentContainer: no managed object model named '%@' could be found.",name];
    return nil;
   }

   _name=[name copy];
   _managedObjectModel=[model retain];
   _persistentStoreCoordinator=[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];

   _viewContext=[[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
   [_viewContext setPersistentStoreCoordinator:_persistentStoreCoordinator];

   NSURL *storeURL=[[[self class] defaultDirectoryURL]
       URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"sqlite"]];

   _persistentStoreDescriptions=[[NSArray alloc] initWithObjects:
       [NSPersistentStoreDescription persistentStoreDescriptionWithURL:storeURL],nil];
   return self;
}

-(void)dealloc {
   [_name release];
   [_managedObjectModel release];
   [_persistentStoreCoordinator release];
   [_viewContext release];
   [_persistentStoreDescriptions release];
   [super dealloc];
}

-(NSString *)name {
   return _name;
}

-(NSManagedObjectModel *)managedObjectModel {
   return _managedObjectModel;
}

-(NSPersistentStoreCoordinator *)persistentStoreCoordinator {
   return _persistentStoreCoordinator;
}

-(NSManagedObjectContext *)viewContext {
   return _viewContext;
}

-(NSArray *)persistentStoreDescriptions {
   return _persistentStoreDescriptions;
}

-(void)setPersistentStoreDescriptions:(NSArray *)descriptions {
   descriptions=[descriptions copy];
   [_persistentStoreDescriptions release];
   _persistentStoreDescriptions=descriptions;
}

-(void)_addStoreForDescription:(NSPersistentStoreDescription *)description
             completionHandler:(void (^)(NSPersistentStoreDescription *,NSError *))handler {
   NSMutableDictionary *options=[NSMutableDictionary dictionaryWithDictionary:[description options]];

   if([description shouldMigrateStoreAutomatically])
    [options setObject:[NSNumber numberWithBool:YES] forKey:NSMigratePersistentStoresAutomaticallyOption];
   if([description shouldInferMappingModelAutomatically])
    [options setObject:[NSNumber numberWithBool:YES] forKey:NSInferMappingModelAutomaticallyOption];

   /* the default store directory may not exist yet */
   NSURL *storeURL=[description URL];

   if([storeURL isFileURL])
    [[NSFileManager defaultManager]
        createDirectoryAtPath:[[storeURL path] stringByDeletingLastPathComponent]
  withIntermediateDirectories:YES
                   attributes:nil
                        error:NULL];

   NSError *error=nil;
   NSPersistentStore *store=[_persistentStoreCoordinator
       addPersistentStoreWithType:[description type]
                    configuration:[description configuration]
                              URL:storeURL
                          options:options
                            error:&error];

   handler(description,(store==nil)?error:nil);
}

-(void)loadPersistentStoresWithCompletionHandler:(void (^)(NSPersistentStoreDescription *,NSError *))handler {
   for(NSPersistentStoreDescription *description in _persistentStoreDescriptions){
    if(![description shouldAddStoreAsynchronously]){
     [self _addStoreForDescription:description completionHandler:handler];
     continue;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
      NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];

      [self _addStoreForDescription:description completionHandler:handler];
      [pool release];
     });
   }
}

-(NSManagedObjectContext *)newBackgroundContext {
   NSManagedObjectContext *context=[[NSManagedObjectContext alloc]
       initWithConcurrencyType:NSPrivateQueueConcurrencyType];

   [context setPersistentStoreCoordinator:_persistentStoreCoordinator];
   return context;   /* -new… convention: the caller owns it */
}

-(void)performBackgroundTask:(void (^)(NSManagedObjectContext *))block {
   NSManagedObjectContext *context=[self newBackgroundContext];

   [context performBlock:^{
     block(context);
    }];
   [context release];   /* the queued block keeps it alive until it runs */
}

@end
