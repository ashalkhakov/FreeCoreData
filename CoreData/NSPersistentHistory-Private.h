/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPersistentHistoryToken.h>
#import <CoreData/NSPersistentHistoryChange.h>
#import <CoreData/NSPersistentHistoryTransaction.h>
#import <CoreData/NSPersistentHistoryChangeRequest.h>
#import <CoreData/NSAttributeDescription.h>

@class NSManagedObjectID, NSPropertyDescription, NSEntityDescription;

/* Shared by the two synthetic history entities (defined in
   NSPersistentHistoryTransaction.m). */
NSAttributeDescription *CDHistoryEntityAttribute(NSString *name,NSAttributeType type);

#import "NSSQLitePersistentStore.h"

@interface NSPersistentHistoryToken (CDPrivate)

/* positions: store identifier -> NSNumber (last transaction number). */
- (instancetype)_initWithPositions:(NSDictionary *)positions;
- (NSDictionary *)_positions;

/* The transaction number this token stands at for the given store; 0
   (everything is "after") when the token has never seen the store. */
- (long long)_transactionNumberForStoreIdentifier:(NSString *)identifier;

@end

@interface NSPersistentHistoryChange (CDPrivate)

- (instancetype)_initWithChangeID:(int64_t)changeID
                             type:(NSPersistentHistoryChangeType)type
                         objectID:(NSManagedObjectID *)objectID
                updatedProperties:(NSSet *)updatedProperties
                        tombstone:(NSDictionary *)tombstone;

/* Back-pointer set by the owning transaction; not retained. */
- (void)_setTransaction:(NSPersistentHistoryTransaction *)transaction;

@end

@interface NSPersistentHistoryTransaction (CDPrivate)

- (instancetype)_initWithNumber:(int64_t)number
                      timestamp:(NSDate *)timestamp
                         author:(NSString *)author
                    contextName:(NSString *)contextName
                      processID:(NSString *)processID
                       bundleID:(NSString *)bundleID
                        storeID:(NSString *)storeID
                        changes:(NSArray *)changes;

- (void)_setChanges:(NSArray *)changes;

@end

@interface NSPersistentHistoryChangeRequest (CDPrivate)

- (BOOL)_isPurge;
- (NSDate *)_anchorDate;
- (NSPersistentHistoryToken *)_anchorToken;
- (int64_t)_anchorTransactionNumber;   /* -1: none */

@end

/* What NSMigrationManager carries into the SQLite store it migrated to, so
   that the store comes through a migration as the same store, as on Apple:
   its history (the source's transactions under their numbers, each change's
   entity and key as they are in the destination), and a transaction marking
   the migration itself. */
@interface NSSQLitePersistentStore (CDMigrationHistory)
- (long long)_primaryKeyOfObjectID:(NSManagedObjectID *)objectID;
/* entityNames: source entity name to destination entity name; primaryKeys:
   destination entity name to {source key: destination key}. A change of an
   entity the destination has not is left out; one of an object not migrated
   (deleted since, say) gets a key no object of the destination has. */
- (BOOL)_adoptHistoryOfStoreAtURL:(NSURL *)sourceURL
                      entityNames:(NSDictionary *)entityNames
                      primaryKeys:(NSDictionary *)primaryKeys
                           author:(NSString *)author
                            error:(NSError **)error;
@end
