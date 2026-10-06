/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* MappingModelTests - inferred mapping model tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"

@interface MappingModelTests : XCTestCase
@end

@implementation MappingModelTests

- (void)testInferredMappingModel
{
    NSError *error = nil;
    NSMappingModel *mapping = [NSMappingModel
        inferredMappingModelForSourceModel:VersioningTestModelV1()
                          destinationModel:VersioningTestModelV2()
                                     error:&error];
    XCTAssertNotNil(mapping);

    NSDictionary *byName = [mapping entityMappingsByName];
    XCTAssertEqual([[mapping entityMappings] count], (NSUInteger)2);

    NSEntityMapping *employee = [byName objectForKey:@"IEM_Transform_Employee"];
    XCTAssertNotNil(employee);
    XCTAssertEqual([employee mappingType],
                   (NSEntityMappingType)NSTransformEntityMappingType);
    /* Every destination attribute gets a mapping: name, salary and title. */
    XCTAssertEqual([[employee attributeMappings] count], (NSUInteger)3);
    XCTAssertEqual([[employee relationshipMappings] count], (NSUInteger)1);

    NSEntityMapping *department = [byName objectForKey:@"IEM_Copy_Department"];
    XCTAssertNotNil(department);
    XCTAssertEqual([department mappingType],
                   (NSEntityMappingType)NSCopyEntityMappingType);
}

/* A mapping model is a keyed archive of its entity mappings, their
   property mappings and the expressions in them - the shape Core Data
   writes, down to the keys, so that what one framework writes the other
   reads.  (What Xcode's own compiler puts in a .cdm is not checked here:
   a mapping model can only be authored in its editor.) */
- (void)testAMappingModelRoundTripsThroughAnArchive
{
    NSPropertyMapping *textMapping = [[NSPropertyMapping alloc] init];
    [textMapping setName:@"text"];
    [textMapping setValueExpression:[NSExpression expressionWithFormat:@"$source.text"]];

    NSEntityMapping *notes = [[NSEntityMapping alloc] init];
    [notes setName:@"KeepSome"];
    [notes setMappingType:NSTransformEntityMappingType];
    [notes setSourceEntityName:@"Note"];
    [notes setDestinationEntityName:@"Note"];
    [notes setAttributeMappings:[NSArray arrayWithObject:textMapping]];
    [notes setSourceExpression:[NSExpression expressionWithFormat:
        @"FETCH(FUNCTION($manager, 'fetchRequestForSourceEntityNamed:predicateString:', 'Note', 'TRUEPREDICATE'), FUNCTION($manager, 'sourceContext'), NO)"]];

    NSMappingModel *mapping = [[NSMappingModel alloc] init];
    [mapping setEntityMappings:[NSArray arrayWithObject:notes]];

    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:mapping];
    NSMappingModel *read = [NSKeyedUnarchiver unarchiveObjectWithData:archive];

    XCTAssertEqual([[read entityMappings] count], (NSUInteger)1);

    NSEntityMapping *readNotes = [[read entityMappings] lastObject];

    XCTAssertEqualObjects([readNotes name], @"KeepSome");
    XCTAssertEqual([readNotes mappingType], (NSEntityMappingType)NSTransformEntityMappingType);
    XCTAssertEqualObjects([readNotes sourceEntityName], @"Note");
    NSUInteger readType = [[readNotes sourceExpression] expressionType];

    XCTAssertEqual(readType, (NSUInteger)NSFetchRequestExpressionType);
    XCTAssertEqualObjects([[[readNotes attributeMappings] lastObject] name], @"text");
}

/* A mapping model written in Xcode says which objects a mapping applies to
   in the mapping's source expression - a fetch request this manager builds,
   narrowed by a predicate, run against the source context.  That is how a
   mapping takes a subset of an entity, and ignoring it migrates everybody.

   The mapping model is built here rather than inferred: an inferred one
   describes a whole-store migration, and Apple's migration takes its own
   way through that whichever expressions it is given. */
- (void)testSourceExpressionChoosesWhatIsMigrated
{
    NSError *error = nil;
    NSAttributeDescription *(^textAttribute)(void) = ^NSAttributeDescription *(void) {
        NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
        [text setName:@"text"];
        [text setAttributeType:NSStringAttributeType];
        [text setOptional:YES];
        return text;
    };
    NSManagedObjectModel *(^noteModel)(void) = ^NSManagedObjectModel *(void) {
        NSEntityDescription *note = [[NSEntityDescription alloc] init];
        [note setName:@"Note"];
        [note setManagedObjectClassName:@"NSManagedObject"];
        [note setProperties:[NSArray arrayWithObject:textAttribute()]];
        NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
        [model setEntities:[NSArray arrayWithObject:note]];
        return model;
    };

    NSManagedObjectModel *sourceModel = noteModel();
    NSManagedObjectModel *destinationModel = noteModel();
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[NSProcessInfo processInfo] globallyUniqueString]];

    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    NSURL *sourceURL = [NSURL fileURLWithPath:
        [directory stringByAppendingPathComponent:@"source.sqlite"]];
    NSPersistentStoreCoordinator *sourcePSC = [[NSPersistentStoreCoordinator alloc]
                                                  initWithManagedObjectModel:sourceModel];

    XCTAssertNotNil([sourcePSC addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                                      URL:sourceURL options:nil error:&error],
                    @"open: %@", error);

    NSManagedObjectContext *sourceCtx = [[NSManagedObjectContext alloc] init];
    [sourceCtx setPersistentStoreCoordinator:sourcePSC];

    for (NSString *text in [NSArray arrayWithObjects:@"keep me", @"keep her", @"drop him", nil]) {
        NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                                             inManagedObjectContext:sourceCtx];
        [note setValue:text forKey:@"text"];
    }
    XCTAssertTrue([sourceCtx save:&error], @"save: %@", error);
    XCTAssertTrue([sourcePSC removePersistentStore:[[sourcePSC persistentStores] lastObject]
                                             error:&error], @"remove: %@", error);

    NSPropertyMapping *textMapping = [[NSPropertyMapping alloc] init];
    [textMapping setName:@"text"];
    [textMapping setValueExpression:[NSExpression expressionWithFormat:@"$source.text"]];

    NSEntityMapping *notes = [[NSEntityMapping alloc] init];
    [notes setName:@"KeepSome"];
    [notes setMappingType:NSTransformEntityMappingType];
    [notes setSourceEntityName:@"Note"];
    [notes setSourceEntityVersionHash:[[[sourceModel entitiesByName] objectForKey:@"Note"] versionHash]];
    [notes setDestinationEntityName:@"Note"];
    [notes setDestinationEntityVersionHash:[[[destinationModel entitiesByName] objectForKey:@"Note"] versionHash]];
    [notes setAttributeMappings:[NSArray arrayWithObject:textMapping]];
    [notes setSourceExpression:[NSExpression expressionWithFormat:
        @"FETCH(FUNCTION($manager, 'fetchRequestForSourceEntityNamed:predicateString:', 'Note', 'text BEGINSWITH \"keep\"'), FUNCTION($manager, 'sourceContext'), NO)"]];

    NSMappingModel *mapping = [[NSMappingModel alloc] init];
    [mapping setEntityMappings:[NSArray arrayWithObject:notes]];

    NSURL *destinationURL = [NSURL fileURLWithPath:
        [directory stringByAppendingPathComponent:@"destination.sqlite"]];
    NSMigrationManager *manager = [[NSMigrationManager alloc] initWithSourceModel:sourceModel
                                                                destinationModel:destinationModel];

    XCTAssertTrue([manager migrateStoreFromURL:sourceURL type:NSSQLiteStoreType options:nil
                              withMappingModel:mapping toDestinationURL:destinationURL
                               destinationType:NSSQLiteStoreType destinationOptions:nil
                                         error:&error], @"migrate: %@", error);
    [manager reset];

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
                                            initWithManagedObjectModel:destinationModel];

    XCTAssertNotNil([psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                                URL:destinationURL options:nil error:&error],
                    @"open the migrated store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"text" ascending:YES]]];

    XCTAssertEqualObjects([[ctx executeFetchRequest:fetch error:&error] valueForKey:@"text"],
        ([NSArray arrayWithObjects:@"keep her", @"keep me", nil]),
        @"only what the source expression fetched: %@", error);

    [psc removePersistentStore:[[psc persistentStores] lastObject] error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

- (void)testInferredMappingModelAddsAndRemovesEntities
{
    NSEntityDescription *added = [[NSEntityDescription alloc] init];
    [added setName:@"Added"];
    NSManagedObjectModel *destination = [[NSManagedObjectModel alloc] init];
    [destination setEntities:[NSArray arrayWithObject:added]];

    NSEntityDescription *removed = [[NSEntityDescription alloc] init];
    [removed setName:@"Removed"];
    NSManagedObjectModel *source = [[NSManagedObjectModel alloc] init];
    [source setEntities:[NSArray arrayWithObject:removed]];

    NSError *error = nil;
    NSMappingModel *mapping = [NSMappingModel
        inferredMappingModelForSourceModel:source
                          destinationModel:destination
                                     error:&error];
    XCTAssertNotNil(mapping);
    XCTAssertEqual([[mapping entityMappings] count], (NSUInteger)2);

    for (NSEntityMapping *entityMapping in [mapping entityMappings]) {
        if ([[entityMapping destinationEntityName] isEqualToString:@"Added"])
            XCTAssertEqual([entityMapping mappingType],
                           (NSEntityMappingType)NSAddEntityMappingType);
        else
            XCTAssertEqual([entityMapping mappingType],
                           (NSEntityMappingType)NSRemoveEntityMappingType);
    }
}

@end
