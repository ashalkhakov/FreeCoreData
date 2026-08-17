/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSXMLPersistentStoreTests - XML store roundtrip and format tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"

/* The XML store tests use the V1 Employee <->> Department model from
   VersioningTestModels so the schema lives in a single place. */
static NSManagedObjectModel *XMLStoreTestModel(void)
{
    return VersioningTestModelV1();
}

/* ------------------------------------------------------------------ */
#pragma mark - NSXMLPersistentStoreTests
/* ------------------------------------------------------------------ */

@interface NSXMLPersistentStoreTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;

@end

@implementation NSXMLPersistentStoreTests

- (void)setUp
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"xml"];
    self.storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:self.storeURL error:NULL];
    self.storeURL = nil;
}

/* Builds a fresh coordinator + context stack on top of the XML store at
   `storeURL`, simulating an independent application run. */
- (NSManagedObjectContext *)contextWithModel:(NSManagedObjectModel *)model
                                     options:(NSDictionary *)options
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSXMLStoreType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:options
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to open XML store: %@", error);
    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

- (NSManagedObjectContext *)contextWithModel:(NSManagedObjectModel *)model
{
    return [self contextWithModel:model options:nil];
}

- (NSArray *)fetchEntityNamed:(NSString *)entityName
                    inContext:(NSManagedObjectContext *)ctx
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[[[ctx persistentStoreCoordinator] managedObjectModel]
                          entitiesByName] objectForKey:entityName]];
    NSError *error = nil;
    NSArray *results = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(results, @"fetch failed: %@", error);
    return results;
}

/* -- attribute roundtrip --------------------------------------------- */

- (void)testAttributeRoundtrip
{
    NSDate *hireDate = [NSDate dateWithTimeIntervalSinceReferenceDate:445103622.25];

    /* First run: create the store and save one Employee. */
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    [alice setValue:[NSNumber numberWithInt:42] forKey:@"salary"];
    [alice setValue:hireDate forKey:@"hireDate"];

    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);
    XCTAssertTrue([[NSFileManager defaultManager]
                      fileExistsAtPath:[self.storeURL path]]);

    /* Second run: reopen the file with a completely fresh stack. */
    NSManagedObjectContext *ctx2 = [self contextWithModel:XMLStoreTestModel()];
    NSArray *employees = [self fetchEntityNamed:@"Employee" inContext:ctx2];
    XCTAssertEqual([employees count], (NSUInteger)1);

    NSManagedObject *reloaded = [employees objectAtIndex:0];
    XCTAssertEqualObjects([reloaded valueForKey:@"name"], @"Alice");
    XCTAssertEqual([[reloaded valueForKey:@"salary"] intValue], 42);

    NSDate *reloadedDate = [reloaded valueForKey:@"hireDate"];
    XCTAssertNotNil(reloadedDate);
    XCTAssertEqualWithAccuracy([reloadedDate timeIntervalSinceReferenceDate],
                               [hireDate timeIntervalSinceReferenceDate],
                               0.001);
}

- (void)testNilAttributeRoundtrip
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *bob =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [bob setValue:@"Bob" forKey:@"name"];
    /* salary and hireDate deliberately left nil. */

    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:XMLStoreTestModel()];
    NSArray *employees = [self fetchEntityNamed:@"Employee" inContext:ctx2];
    XCTAssertEqual([employees count], (NSUInteger)1);
    NSManagedObject *reloaded = [employees objectAtIndex:0];
    XCTAssertEqualObjects([reloaded valueForKey:@"name"], @"Bob");
    XCTAssertNil([reloaded valueForKey:@"hireDate"]);
}

/* -- relationship roundtrip ------------------------------------------ */

- (void)testRelationshipRoundtrip
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *engineering =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:ctx1];
    [engineering setValue:@"Engineering" forKey:@"name"];

    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    NSManagedObject *bob =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [bob setValue:@"Bob" forKey:@"name"];

    /* Set both sides of the relationship explicitly so the test does not
       depend on automatic inverse maintenance. */
    [alice setValue:engineering forKey:@"department"];
    [bob setValue:engineering forKey:@"department"];
    [engineering setValue:[NSSet setWithObjects:alice, bob, nil]
                   forKey:@"employees"];

    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:XMLStoreTestModel()];
    NSArray *departments = [self fetchEntityNamed:@"Department" inContext:ctx2];
    XCTAssertEqual([departments count], (NSUInteger)1);

    NSManagedObject *reloadedDept = [departments objectAtIndex:0];
    XCTAssertEqualObjects([reloadedDept valueForKey:@"name"], @"Engineering");

    NSSet *reloadedEmployees = [reloadedDept valueForKey:@"employees"];
    XCTAssertEqual([reloadedEmployees count], (NSUInteger)2);
    NSSet *names = [NSSet setWithArray:
        [[reloadedEmployees allObjects] valueForKey:@"name"]];
    XCTAssertEqualObjects(names,
        ([NSSet setWithObjects:@"Alice", @"Bob", nil]));

    for (NSManagedObject *employee in reloadedEmployees) {
        NSManagedObject *dept = [employee valueForKey:@"department"];
        XCTAssertEqualObjects([dept valueForKey:@"name"], @"Engineering");
    }
}

/* -- update and delete roundtrip -------------------------------------- */

- (void)testUpdateAndDeleteRoundtrip
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    [alice setValue:[NSNumber numberWithInt:42] forKey:@"salary"];
    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    /* Update in a second run. */
    NSManagedObjectContext *ctx2 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *reloaded =
        [[self fetchEntityNamed:@"Employee" inContext:ctx2] objectAtIndex:0];
    [reloaded setValue:[NSNumber numberWithInt:100] forKey:@"salary"];
    XCTAssertTrue([ctx2 save:&error], @"save failed: %@", error);

    /* Verify the update, then delete, in a third run. */
    NSManagedObjectContext *ctx3 = [self contextWithModel:XMLStoreTestModel()];
    NSArray *employees = [self fetchEntityNamed:@"Employee" inContext:ctx3];
    XCTAssertEqual([employees count], (NSUInteger)1);
    XCTAssertEqual(
        [[[employees objectAtIndex:0] valueForKey:@"salary"] intValue], 100);
    [ctx3 deleteObject:[employees objectAtIndex:0]];
    XCTAssertTrue([ctx3 save:&error], @"save failed: %@", error);

    /* Fourth run: the store is empty. */
    NSManagedObjectContext *ctx4 = [self contextWithModel:XMLStoreTestModel()];
    XCTAssertEqual([[self fetchEntityNamed:@"Employee" inContext:ctx4] count],
                   (NSUInteger)0);
}

/* -- store metadata ---------------------------------------------------- */

- (void)testMetadataRoundtrip
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    NSPersistentStore *store = [[[ctx1 persistentStoreCoordinator]
        persistentStores] objectAtIndex:0];

    NSDictionary *metadata = [NSPersistentStoreCoordinator
        metadataForPersistentStoreOfType:NSXMLStoreType
                                     URL:self.storeURL
                                   error:&error];
    XCTAssertNotNil(metadata, @"metadata read failed: %@", error);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreTypeKey],
                          NSXMLStoreType);
    XCTAssertEqualObjects([metadata objectForKey:NSStoreUUIDKey],
                          [store identifier]);
}

/* -- Apple interoperability -------------------------------------------- */

/* The on-disk format written by this store must match the format Apple's
   NSXMLStoreType writes: a <database> root, a <databaseInfo> header with
   UUID and nextObjectID, one <object> element per instance whose `type'
   attribute is the uppercased entity name, and <relationship> elements
   whose `idrefs' point at other object ids. */
- (void)testWrittenFileFormatMatchesApple
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLStoreTestModel()];
    NSManagedObject *engineering =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:ctx1];
    [engineering setValue:@"Engineering" forKey:@"name"];
    NSManagedObject *alice =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx1];
    [alice setValue:@"Alice" forKey:@"name"];
    [alice setValue:engineering forKey:@"department"];
    [engineering setValue:[NSSet setWithObject:alice] forKey:@"employees"];

    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    NSXMLDocument *doc = [[NSXMLDocument alloc]
        initWithContentsOfURL:self.storeURL options:0 error:&error];
    XCTAssertNotNil(doc, @"store file is not parseable XML: %@", error);

    NSXMLElement *database = [doc rootElement];
    XCTAssertEqualObjects([database name], @"database");

    NSXMLElement *databaseInfo =
        [[database elementsForName:@"databaseInfo"] lastObject];
    XCTAssertNotNil(databaseInfo);
    XCTAssertTrue([[[[databaseInfo elementsForName:@"UUID"] lastObject]
                       stringValue] length] > 0);
    XCTAssertTrue([[[[databaseInfo elementsForName:@"nextObjectID"] lastObject]
                       stringValue] integerValue] > 0);

    NSArray *objects = [database elementsForName:@"object"];
    XCTAssertEqual([objects count], (NSUInteger)2);

    NSMutableSet *objectIDs = [NSMutableSet set];
    NSMutableSet *typeNames = [NSMutableSet set];
    for (NSXMLElement *object in objects) {
        NSString *type = [[object attributeForName:@"type"] stringValue];
        NSString *objectID = [[object attributeForName:@"id"] stringValue];
        /* Apple writes entity names in uppercase. */
        XCTAssertEqualObjects(type, [type uppercaseString]);
        XCTAssertTrue([objectID length] > 0);
        [typeNames addObject:type];
        [objectIDs addObject:objectID];
    }
    XCTAssertEqualObjects(typeNames,
        ([NSSet setWithObjects:@"EMPLOYEE", @"DEPARTMENT", nil]));

    /* Attribute elements carry the value as element content. */
    NSXMLElement *aliceElement = nil;
    for (NSXMLElement *object in objects)
        if ([[[object attributeForName:@"type"] stringValue]
                isEqualToString:@"EMPLOYEE"])
            aliceElement = object;
    XCTAssertNotNil(aliceElement);

    BOOL foundName = NO;
    for (NSXMLElement *attribute in [aliceElement elementsForName:@"attribute"]) {
        if ([[[attribute attributeForName:@"name"] stringValue]
                isEqualToString:@"name"]) {
            foundName = YES;
            XCTAssertEqualObjects([attribute stringValue], @"Alice");
        }
    }
    XCTAssertTrue(foundName);

    /* Relationship idrefs reference object ids present in the file, and the
       destination is the uppercased entity name. */
    for (NSXMLElement *object in objects) {
        for (NSXMLElement *relationship in
                 [object elementsForName:@"relationship"]) {
            NSString *destination =
                [[relationship attributeForName:@"destination"] stringValue];
            XCTAssertEqualObjects(destination, [destination uppercaseString]);
            NSString *idrefs =
                [[relationship attributeForName:@"idrefs"] stringValue];
            for (NSString *ref in
                     [idrefs componentsSeparatedByString:@" "]) {
                if ([ref length] == 0)
                    continue;
                XCTAssertTrue([objectIDs containsObject:ref],
                              @"idref %@ does not match any object id", ref);
            }
        }
    }
}

/* Loads a fixture file written in the format Apple's NSXMLStoreType
   produces (DOCTYPE referencing CoreData.dtd, uppercase entity names,
   lowercase property names, z-prefixed object ids, dates as seconds since
   the reference date with 20 fractional digits) and verifies the object
   graph.  Mirrors an actual store file written by Apple's CoreData. */
- (void)testLoadsAppleGeneratedStore
{
    NSString *fixture =
        @"<?xml version=\"1.0\"?>\n"
        @"<!DOCTYPE database SYSTEM \"file:///System/Library/DTDs/CoreData.dtd\">\n"
        @"\n"
        @"<database>\n"
        @"    <databaseInfo>\n"
        @"        <version>134481920</version>\n"
        @"        <UUID>7DFA6DAB-A071-4B34-8DFB-BAC65DD66FDE</UUID>\n"
        @"        <nextObjectID>105</nextObjectID>\n"
        @"        <metadata></metadata>\n"
        @"    </databaseInfo>\n"
        @"    <object type=\"DEPARTMENT\" id=\"z104\">\n"
        @"        <attribute name=\"name\" type=\"string\">Engineering</attribute>\n"
        @"        <relationship name=\"employees\" type=\"0/0\" destination=\"EMPLOYEE\" idrefs=\"z102\"></relationship>\n"
        @"    </object>\n"
        @"    <object type=\"EMPLOYEE\" id=\"z102\">\n"
        @"        <attribute name=\"name\" type=\"string\">Alice</attribute>\n"
        @"        <attribute name=\"salary\" type=\"int32\">100</attribute>\n"
        @"        <attribute name=\"hiredate\" type=\"date\">445103622.25000000000000000000</attribute>\n"
        @"        <relationship name=\"department\" type=\"1/1\" destination=\"DEPARTMENT\" idrefs=\"z104\"></relationship>\n"
        @"    </object>\n"
        @"    <object type=\"EMPLOYEE\" id=\"z103\">\n"
        @"        <attribute name=\"name\" type=\"string\">Bob</attribute>\n"
        @"        <attribute name=\"salary\" type=\"int32\">90</attribute>\n"
        @"        <relationship name=\"department\" type=\"1/1\" destination=\"DEPARTMENT\"></relationship>\n"
        @"    </object>\n"
        @"</database>\n";

    NSError *error = nil;
    XCTAssertTrue([fixture writeToURL:self.storeURL
                           atomically:YES
                             encoding:NSUTF8StringEncoding
                                error:&error],
                  @"failed to write fixture: %@", error);

    /* The fixture has no model version hashes in its metadata, so ask
       CoreData to skip the model compatibility check (a no-op on the
       GNUstep port, required by Apple's CoreData). */
    NSDictionary *options = nil;
#ifdef __APPLE__
    options = [NSDictionary
        dictionaryWithObject:[NSNumber numberWithBool:YES]
                      forKey:NSIgnorePersistentStoreVersioningOption];
#endif
    NSManagedObjectContext *ctx = [self contextWithModel:XMLStoreTestModel()
                                                 options:options];

    NSArray *employees = [self fetchEntityNamed:@"Employee" inContext:ctx];
    XCTAssertEqual([employees count], (NSUInteger)2);
    NSSet *names =
        [NSSet setWithArray:[employees valueForKey:@"name"]];
    XCTAssertEqualObjects(names,
        ([NSSet setWithObjects:@"Alice", @"Bob", nil]));

    NSManagedObject *aliceObject = nil;
    NSManagedObject *bobObject = nil;
    for (NSManagedObject *employee in employees) {
        if ([[employee valueForKey:@"name"] isEqualToString:@"Alice"])
            aliceObject = employee;
        if ([[employee valueForKey:@"name"] isEqualToString:@"Bob"])
            bobObject = employee;
    }
    XCTAssertNotNil(aliceObject);
    XCTAssertEqual([[aliceObject valueForKey:@"salary"] intValue], 100);
    NSDate *hireDate = [aliceObject valueForKey:@"hireDate"];
    XCTAssertNotNil(hireDate);
    XCTAssertEqualWithAccuracy([hireDate timeIntervalSinceReferenceDate],
                               445103622.25, 0.001);

    NSManagedObject *department = [aliceObject valueForKey:@"department"];
    XCTAssertNotNil(department);
    XCTAssertEqualObjects([department valueForKey:@"name"], @"Engineering");

    /* Bob's department relationship has no idrefs attribute (the form
       Apple writes for an unset relationship). */
    XCTAssertNotNil(bobObject);
    XCTAssertNil([bobObject valueForKey:@"department"]);

    NSArray *departments = [self fetchEntityNamed:@"Department" inContext:ctx];
    XCTAssertEqual([departments count], (NSUInteger)1);
    NSSet *reloadedEmployees =
        [[departments objectAtIndex:0] valueForKey:@"employees"];
    XCTAssertEqual([reloadedEmployees count], (NSUInteger)1);
}

/* -- entity inheritance ------------------------------------------------ */

/* Person(name) with subentity Manager(reports). */
static NSManagedObjectModel *XMLInheritanceModel(void)
{
    NSAttributeDescription *personName = [[NSAttributeDescription alloc] init];
    [personName setName:@"name"];
    [personName setAttributeType:NSStringAttributeType];
    [personName setOptional:YES];

    NSAttributeDescription *reports = [[NSAttributeDescription alloc] init];
    [reports setName:@"reports"];
    [reports setAttributeType:NSInteger32AttributeType];
    [reports setOptional:YES];

    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    [person setName:@"Person"];
    [person setManagedObjectClassName:@"NSManagedObject"];
    [person setProperties:[NSArray arrayWithObject:personName]];

    NSEntityDescription *manager = [[NSEntityDescription alloc] init];
    [manager setName:@"Manager"];
    [manager setManagedObjectClassName:@"NSManagedObject"];
    [manager setProperties:[NSArray arrayWithObject:reports]];

    [person setSubentities:[NSArray arrayWithObject:manager]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObjects:person, manager, nil]];
    return model;
}

- (void)testSubentitiesRoundtrip
{
    NSManagedObjectContext *ctx1 = [self contextWithModel:XMLInheritanceModel()];

    NSManagedObject *boss =
        [NSEntityDescription insertNewObjectForEntityForName:@"Manager"
                                      inManagedObjectContext:ctx1];
    [boss setValue:@"Boss" forKey:@"name"];
    [boss setValue:[NSNumber numberWithInt:7] forKey:@"reports"];

    NSManagedObject *worker =
        [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                      inManagedObjectContext:ctx1];
    [worker setValue:@"Worker" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([ctx1 save:&error], @"save failed: %@", error);

    /* Reopen with a fresh stack: a fetch of the parent entity includes
       subentity instances, which keep their own entity and both the
       inherited and the subentity-specific attributes. */
    NSManagedObjectContext *ctx2 = [self contextWithModel:XMLInheritanceModel()];
    NSArray *people = [self fetchEntityNamed:@"Person" inContext:ctx2];
    XCTAssertEqual([people count], (NSUInteger)2);

    NSManagedObject *reloadedBoss = nil;
    for (NSManagedObject *personObject in people)
        if ([[[personObject entity] name] isEqualToString:@"Manager"])
            reloadedBoss = personObject;
    XCTAssertNotNil(reloadedBoss);
    XCTAssertEqualObjects([reloadedBoss valueForKey:@"name"], @"Boss");
    XCTAssertEqual([[reloadedBoss valueForKey:@"reports"] intValue], 7);

    /* A fetch of the subentity finds only its own instances. */
    NSArray *managers = [self fetchEntityNamed:@"Manager" inContext:ctx2];
    XCTAssertEqual([managers count], (NSUInteger)1);
    XCTAssertEqualObjects(
        [[managers objectAtIndex:0] valueForKey:@"name"], @"Boss");
}

@end
