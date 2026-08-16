/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPersistentStore.h>

@class NSManagedObjectContext, NSManagedObjectID, NSEntityDescription, NSRelationshipDescription, NSPersistentStoreRequest, NSIncrementalStoreNode, NSArray, NSMutableDictionary;

/* Abstract superclass for stores which load and save data incrementally
   (record by record), such as SQL-backed stores.  Subclasses must override:

   - loadMetadata:
   - executeRequest:withContext:error:
   - newValuesForObjectWithID:withContext:error:
   - newValueForRelationship:forObjectWithID:withContext:error:
   - obtainPermanentIDsForObjects:error:

   See Apple's NSIncrementalStore documentation for the contract. */
@interface NSIncrementalStore : NSPersistentStore {
    NSDictionary *_incrementalMetadata;
    NSMutableDictionary *_objectIDTable;
}

/* Returns a unique identifier for a new store at the given URL. */
+ (id)identifierForNewStoreAtURL:(NSURL *)storeURL;

/* Subclasses must load store metadata (including NSStoreTypeKey and
   NSStoreUUIDKey) and perform validation/setup here. */
- (BOOL)loadMetadata:(NSError **)error;

/* Executes a fetch (NSFetchRequest) or save (NSSaveChangesRequest) request.
   For fetch requests with managed-object result type, returns an NSArray of
   managed objects; for save requests, returns an empty NSArray on success. */
- (id)executeRequest:(NSPersistentStoreRequest *)request withContext:(NSManagedObjectContext *)context error:(NSError **)error;

/* Returns a node containing the attribute values (and to-one relationship
   object IDs) for the given object, used to fulfill faults. */
- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError **)error;

/* Returns the value of the given relationship: an NSManagedObjectID for a
   to-one relationship, or a collection of NSManagedObjectIDs for to-many. */
- (id)newValueForRelationship:(NSRelationshipDescription *)relationship forObjectWithID:(NSManagedObjectID *)objectID withContext:(NSManagedObjectContext *)context error:(NSError **)error;

/* Returns permanent object IDs (created with
   newObjectIDForEntity:referenceObject:) for the given newly inserted
   objects, in the same order. */
- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)error;

- (void)managedObjectContextDidRegisterObjectsWithIDs:(NSArray *)objectIDs;
- (void)managedObjectContextDidUnregisterObjectsWithIDs:(NSArray *)objectIDs;

/* Creates (or returns the uniqued, previously created) permanent object ID
   for the given entity and store-specific reference data. */
- (NSManagedObjectID *)newObjectIDForEntity:(NSEntityDescription *)entity referenceObject:(id)data;

/* Returns the reference data used to create the given object ID. */
- (id)referenceObjectForObjectID:(NSManagedObjectID *)objectID;

@end
