/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>
#import <CoreData/NSManagedObjectContext.h>

@class NSString, NSURL, NSArray, NSError;
@class NSManagedObjectModel, NSPersistentStoreCoordinator, NSPersistentStoreDescription;

/* The modern one-stop stack: model + coordinator + a main-queue view
   context, with store loading driven by NSPersistentStoreDescriptions
   and background work through newBackgroundContext /
   performBackgroundTask:. */
@interface NSPersistentContainer : NSObject {
    NSString *_name;
    NSManagedObjectModel *_managedObjectModel;
    NSPersistentStoreCoordinator *_persistentStoreCoordinator;
    NSManagedObjectContext *_viewContext;
    NSArray *_persistentStoreDescriptions;
}

+ (instancetype)persistentContainerWithName:(NSString *)name;
+ (instancetype)persistentContainerWithName:(NSString *)name
                         managedObjectModel:(NSManagedObjectModel *)model;

/* The directory store files default into; subclasses may override.
   (The Application Support directory, as on Apple.) */
+ (NSURL *)defaultDirectoryURL;

/* The name-only initializer loads <name>.momd / <name>.mom from the
   main bundle, falling back to the bundle's merged model. */
- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name
          managedObjectModel:(NSManagedObjectModel *)model;

- (NSString *)name;
- (NSManagedObjectModel *)managedObjectModel;
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator;

/* A main-queue context connected to the coordinator. */
- (NSManagedObjectContext *)viewContext;

/* Defaults to one SQLite description at
   defaultDirectoryURL/<name>.sqlite. */
- (NSArray *)persistentStoreDescriptions;
- (void)setPersistentStoreDescriptions:(NSArray *)descriptions;

/* Adds every described store, calling the handler once per store -
   synchronously for descriptions with shouldAddStoreAsynchronously NO
   (the default), from a background queue otherwise. */
- (void)loadPersistentStoresWithCompletionHandler:(void (^)(NSPersistentStoreDescription *description, NSError *error))handler;

/* A fresh private-queue context connected to the coordinator (not a
   child of viewContext).  Follows the -new… ownership convention. */
- (NSManagedObjectContext *)newBackgroundContext;

/* Runs the block on a fresh background context's queue. */
- (void)performBackgroundTask:(void (^)(NSManagedObjectContext *context))block;

@end
