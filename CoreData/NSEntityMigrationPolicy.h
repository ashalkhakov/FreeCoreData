/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/Foundation.h>
#import <CoreData/CoreDataExports.h>

@class NSManagedObject, NSEntityMapping, NSMigrationManager;

/* Keys available to property mapping value expressions during migration. */
COREDATA_EXPORT NSString *const NSMigrationManagerKey;
COREDATA_EXPORT NSString *const NSMigrationSourceObjectKey;
COREDATA_EXPORT NSString *const NSMigrationDestinationObjectKey;
COREDATA_EXPORT NSString *const NSMigrationEntityMappingKey;
COREDATA_EXPORT NSString *const NSMigrationPropertyMappingKey;
COREDATA_EXPORT NSString *const NSMigrationEntityPolicyKey;

@interface NSEntityMigrationPolicy : NSObject

- (BOOL)beginEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error;

- (BOOL)createDestinationInstancesForSourceInstance:(NSManagedObject *)sInstance entityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error;

- (BOOL)endInstanceCreationForEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error;

- (BOOL)createRelationshipsForDestinationInstance:(NSManagedObject *)dInstance entityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error;

- (BOOL)endRelationshipCreationForEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error;

- (BOOL)performCustomValidationForEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error;

- (BOOL)endEntityMapping:(NSEntityMapping *)mapping manager:(NSMigrationManager *)manager error:(NSError **)error;

@end
