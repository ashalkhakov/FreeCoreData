/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/Foundation.h>

@class NSManagedObjectModel, NSManagedObjectContext, NSMappingModel, NSEntityMapping, NSEntityDescription, NSManagedObject, NSPersistentStoreCoordinator;

@interface NSMigrationManager : NSObject {
    NSManagedObjectModel *_sourceModel;
    NSManagedObjectModel *_destinationModel;
    NSMappingModel *_mappingModel;
    NSPersistentStoreCoordinator *_sourceCoordinator;
    NSPersistentStoreCoordinator *_destinationCoordinator;
    NSManagedObjectContext *_sourceContext;
    NSManagedObjectContext *_destinationContext;
    NSEntityMapping *_currentEntityMapping;
    NSMutableDictionary *_associationsByMappingName;
    NSDictionary *_userInfo;
    NSError *_migrationError;
    float _migrationProgress;
    BOOL _cancelled;
}

- initWithSourceModel:(NSManagedObjectModel *)sourceModel destinationModel:(NSManagedObjectModel *)destinationModel;

- (BOOL)migrateStoreFromURL:(NSURL *)sourceURL type:(NSString *)sStoreType options:(NSDictionary *)sOptions withMappingModel:(NSMappingModel *)mappings toDestinationURL:(NSURL *)dURL destinationType:(NSString *)dStoreType destinationOptions:(NSDictionary *)dOptions error:(NSError **)error;

- (NSManagedObjectModel *)sourceModel;
- (NSManagedObjectModel *)destinationModel;
- (NSMappingModel *)mappingModel;

- (NSManagedObjectContext *)sourceContext;
- (NSManagedObjectContext *)destinationContext;

- (NSEntityDescription *)sourceEntityForEntityMapping:(NSEntityMapping *)mEntity;
- (NSEntityDescription *)destinationEntityForEntityMapping:(NSEntityMapping *)mEntity;

- (NSEntityMapping *)currentEntityMapping;

- (void)associateSourceInstance:(NSManagedObject *)sourceInstance withDestinationInstance:(NSManagedObject *)destinationInstance forEntityMapping:(NSEntityMapping *)entityMapping;

- (NSArray *)destinationInstancesForEntityMappingNamed:(NSString *)mappingName sourceInstances:(NSArray *)sourceInstances;
- (NSArray *)sourceInstancesForEntityMappingNamed:(NSString *)mappingName destinationInstances:(NSArray *)destinationInstances;

- (float)migrationProgress;

- (NSDictionary *)userInfo;
- (void)setUserInfo:(NSDictionary *)userInfo;

- (void)reset;
- (void)cancelMigrationWithError:(NSError *)error;

@end
