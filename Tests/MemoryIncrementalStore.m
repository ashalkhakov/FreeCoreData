/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* MemoryIncrementalStore - a minimal in-memory NSIncrementalStore subclass
   shared by the incremental store test cases. */

#import "MemoryIncrementalStore.h"

NSString * const MemoryIncrementalStoreType = @"MemoryIncrementalStoreType";
NSString * const MismatchIncrementalStoreType = @"MismatchIncrementalStoreType";

@implementation MemoryIncrementalStore

/* Apple's -[NSPersistentStoreCoordinator addPersistentStoreWithType:...]
   verifies that the store's `type` matches the requested store type after
   -loadMetadata: returns; without these overrides it fails with
   NSPersistentStoreTypeMismatchError (134010) on macOS.  Apple's instance
   -type delegates to the +type class method, so both are provided. */
+ (NSString *)type
{
    return MemoryIncrementalStoreType;
}

- (NSString *)type
{
    return MemoryIncrementalStoreType;
}

- (NSMutableDictionary *)tableForEntityName:(NSString *)entityName
{
    NSMutableDictionary *table = [self.rows objectForKey:entityName];
    if (table == nil) {
        table = [NSMutableDictionary dictionary];
        [self.rows setObject:table forKey:entityName];
    }
    return table;
}

- (BOOL)loadMetadata:(NSError **)error
{
    self.loadMetadataCallCount++;
    if (self.rows == nil)
        self.rows = [NSMutableDictionary dictionary];
    NSString *uuid = [[NSProcessInfo processInfo] globallyUniqueString];
    [self setMetadata:[NSDictionary dictionaryWithObjectsAndKeys:
                          MemoryIncrementalStoreType, NSStoreTypeKey,
                          uuid, NSStoreUUIDKey, nil]];
    return YES;
}

- (void)writeRowForObject:(NSManagedObject *)object
{
    id ref = [self referenceObjectForObjectID:[object objectID]];
    NSMutableDictionary *table = [self tableForEntityName:[[object entity] name]];
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    /* Walk the superentity chain so inherited attributes are persisted
       too. */
    NSEntityDescription *entity;
    for (entity = [object entity]; entity != nil; entity = [entity superentity]) {
        for (NSString *key in [entity attributesByName]) {
            if ([row objectForKey:key] != nil)
                continue;
            id value = [object valueForKey:key];
            if (value != nil)
                [row setObject:value forKey:key];
        }
        /* Relationships are stored as reference objects: the
           destination's reference for a to-one, an array of references
           for a to-many. */
        for (NSString *key in [entity relationshipsByName]) {
            if ([row objectForKey:key] != nil)
                continue;
            NSRelationshipDescription *relationship =
                [[entity relationshipsByName] objectForKey:key];
            id value = [object valueForKey:key];
            if (value == nil)
                continue;
            if ([relationship isToMany]) {
                NSMutableArray *refs = [NSMutableArray array];
                for (NSManagedObject *member in value)
                    [refs addObject:[self referenceObjectForObjectID:
                                              [member objectID]]];
                [row setObject:refs forKey:key];
            }
            else
                [row setObject:[self referenceObjectForObjectID:
                                         [(NSManagedObject *)value objectID]]
                        forKey:key];
        }
    }
    [table setObject:row forKey:ref];
}

- (id)executeRequest:(NSPersistentStoreRequest *)request
         withContext:(NSManagedObjectContext *)context
               error:(NSError **)error
{
    if ([request requestType] == NSFetchRequestType) {
        self.fetchRequestCount++;
        NSFetchRequest *fetch = (NSFetchRequest *)request;
        NSEntityDescription *entity = [fetch entity];
        NSMutableArray *results = [NSMutableArray array];
        NSMutableArray *entities =
            [NSMutableArray arrayWithObject:entity];
        /* The store is responsible for including subentity instances when
           the fetch asks for them (the default). */
        if ([fetch includesSubentities]) {
            NSUInteger i;
            for (i = 0; i < [entities count]; i++)
                [entities addObjectsFromArray:
                    [[entities objectAtIndex:i] subentities]];
        }
        for (NSEntityDescription *fetchEntity in entities) {
            NSDictionary *table = [self.rows objectForKey:[fetchEntity name]];
            for (id ref in table) {
                NSManagedObjectID *objectID =
                    [self newObjectIDForEntity:fetchEntity referenceObject:ref];
                [results addObject:[context objectWithID:objectID]];
            }
        }
        if ([fetch predicate] != nil)
            [results filterUsingPredicate:[fetch predicate]];
        /* An incremental store handles NSCountResultType itself (the
           context forwards the request), returning an array holding a
           single NSNumber. */
        if ([fetch resultType] == NSCountResultType)
            return [NSArray arrayWithObject:
                [NSNumber numberWithUnsignedInteger:[results count]]];
        if ([[fetch sortDescriptors] count] > 0)
            [results sortUsingDescriptors:[fetch sortDescriptors]];
        /* Dictionary rows come straight from the persisted rows,
           matching Apple's "reflects the store, never pending changes"
           contract for NSDictionaryResultType. */
        if ([fetch resultType] == NSDictionaryResultType) {
            NSMutableArray *names = [NSMutableArray array];
            if ([[fetch propertiesToFetch] count] > 0) {
                for (id p in [fetch propertiesToFetch])
                    [names addObject:[p isKindOfClass:[NSString class]]
                        ? p : [(NSPropertyDescription *)p name]];
            }
            else
                [names addObjectsFromArray:
                    [[[entity attributesByName] allKeys]
                        sortedArrayUsingSelector:@selector(compare:)]];

            NSMutableArray *rows = [NSMutableArray array];
            for (NSManagedObject *object in results) {
                NSDictionary *stored = [[self.rows
                    objectForKey:[[[object objectID] entity] name]]
                    objectForKey:[self referenceObjectForObjectID:
                                           [object objectID]]];
                NSMutableDictionary *row = [NSMutableDictionary dictionary];
                for (NSString *name in names) {
                    id value = [stored objectForKey:name];
                    if (value != nil)
                        [row setObject:value forKey:name];
                }
                if ([fetch returnsDistinctResults] &&
                    [rows containsObject:row])
                    continue;
                [rows addObject:row];
            }
            return rows;
        }
        return results;
    }

    if ([request requestType] == NSSaveRequestType) {
        self.saveRequestCount++;
        NSSaveChangesRequest *save = (NSSaveChangesRequest *)request;
        self.lastInsertedCount = [[save insertedObjects] count];
        self.lastUpdatedCount = [[save updatedObjects] count];
        self.lastDeletedCount = [[save deletedObjects] count];
        for (NSManagedObject *object in [save insertedObjects])
            [self writeRowForObject:object];
        for (NSManagedObject *object in [save updatedObjects])
            [self writeRowForObject:object];
        for (NSManagedObject *object in [save deletedObjects]) {
            id ref = [self referenceObjectForObjectID:[object objectID]];
            [[self tableForEntityName:[[object entity] name]] removeObjectForKey:ref];
        }
        return [NSArray array];
    }

    return nil;
}

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                         withContext:(NSManagedObjectContext *)context
                                               error:(NSError **)error
{
    self.newValuesCallCount++;
    id ref = [self referenceObjectForObjectID:objectID];
    NSDictionary *row = [[self.rows objectForKey:[[objectID entity] name]] objectForKey:ref];
    if (row == nil) {
        if (error != NULL)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:133000
                                     userInfo:nil];
        return nil;
    }

    /* Attributes are returned as stored; a to-one relationship is
       returned as a real NSManagedObjectID so faulting can satisfy it
       from the node without a newValueForRelationship: round trip.
       To-many relationships are not part of the node, matching Apple's
       contract. */
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSDictionary *relationships = [[objectID entity] relationshipsByName];
    for (NSString *key in row) {
        NSRelationshipDescription *relationship =
            [relationships objectForKey:key];
        if (relationship == nil) {
            [values setObject:[row objectForKey:key] forKey:key];
            continue;
        }
        if ([relationship isToMany])
            continue;
        [values setObject:[self newObjectIDForEntity:
                                    [relationship destinationEntity]
                                     referenceObject:[row objectForKey:key]]
                   forKey:key];
    }
    return [[NSIncrementalStoreNode alloc] initWithObjectID:objectID
                                                 withValues:values
                                                    version:1];
}

- (id)newValueForRelationship:(NSRelationshipDescription *)relationship
              forObjectWithID:(NSManagedObjectID *)objectID
                  withContext:(NSManagedObjectContext *)context
                        error:(NSError **)error
{
    self.relationshipCallCount++;

    id ref = [self referenceObjectForObjectID:objectID];
    NSDictionary *row = [[self.rows objectForKey:[[objectID entity] name]]
                            objectForKey:ref];
    id stored = [row objectForKey:[relationship name]];

    if ([relationship isToMany]) {
        NSMutableArray *ids = [NSMutableArray array];
        for (id memberRef in stored)
            [ids addObject:[self newObjectIDForEntity:
                                     [relationship destinationEntity]
                                  referenceObject:memberRef]];
        return ids;
    }

    if (stored == nil)
        return [NSNull null];
    return [self newObjectIDForEntity:[relationship destinationEntity]
                      referenceObject:stored];
}

- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)error
{
    self.obtainPermanentIDsCallCount++;
    NSMutableArray *result = [NSMutableArray array];
    for (NSManagedObject *object in array) {
        self.nextReferenceNumber++;
        NSString *ref =
            [NSString stringWithFormat:@"ref-%lld", self.nextReferenceNumber];
        [result addObject:[self newObjectIDForEntity:[object entity]
                                     referenceObject:ref]];
    }
    return result;
}

@end

@implementation MismatchIncrementalStore
@end

NSManagedObjectModel *IncrementalStoreTestModel(void)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];

    NSAttributeDescription *age = [[NSAttributeDescription alloc] init];
    [age setName:@"age"];
    [age setAttributeType:NSInteger32AttributeType];

    /* manager <-->> reports, both on Person, so relationship faulting
       can be exercised against the store. */
    NSRelationshipDescription *managerRel =
        [[NSRelationshipDescription alloc] init];
    [managerRel setName:@"manager"];
    [managerRel setMinCount:1];
    [managerRel setMaxCount:1];
    [managerRel setOptional:YES];

    NSRelationshipDescription *reportsRel =
        [[NSRelationshipDescription alloc] init];
    [reportsRel setName:@"reports"];
    [reportsRel setMinCount:0];
    [reportsRel setMaxCount:0];
    [reportsRel setOptional:YES];

    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    [entity setName:@"Person"];
    [entity setManagedObjectClassName:@"NSManagedObject"];

    [managerRel setDestinationEntity:entity];
    [managerRel setInverseRelationship:reportsRel];
    [reportsRel setDestinationEntity:entity];
    [reportsRel setInverseRelationship:managerRel];

    [entity setProperties:
        [NSArray arrayWithObjects:name, age, managerRel, reportsRel, nil]];

    /* Manager is a subentity of Person and adds a `level' attribute. */
    NSAttributeDescription *level = [[NSAttributeDescription alloc] init];
    [level setName:@"level"];
    [level setAttributeType:NSInteger32AttributeType];

    NSEntityDescription *manager = [[NSEntityDescription alloc] init];
    [manager setName:@"Manager"];
    [manager setManagedObjectClassName:@"NSManagedObject"];
    [manager setProperties:[NSArray arrayWithObject:level]];

    [entity setSubentities:[NSArray arrayWithObject:manager]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObjects:entity, manager, nil]];
    return model;
}
