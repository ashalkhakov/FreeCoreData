/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSFetchRequestTests - basic NSFetchRequest tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"

@interface NSFetchRequestTests : XCTestCase
@end

@implementation NSFetchRequestTests

- (void)testDefaults
{
    /* Apple's documented defaults. */
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    XCTAssertNil([req entity]);
    XCTAssertNil([req predicate]);
    XCTAssertEqual([req fetchLimit], (NSUInteger)0);
    XCTAssertEqual([req resultType],
                   (NSFetchRequestResultType)NSManagedObjectResultType);
    XCTAssertTrue([req includesSubentities]);
    XCTAssertTrue([req includesPendingChanges]);
    XCTAssertTrue([req includesPropertyValues]);
    XCTAssertTrue([req returnsObjectsAsFaults]);
    XCTAssertFalse([req returnsDistinctResults]);
    XCTAssertFalse([req shouldRefreshRefetchedObjects]);
    XCTAssertNil([req propertiesToGroupBy]);
    XCTAssertNil([req havingPredicate]);
}

- (void)testSettersGetters
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setFetchLimit:42];
    XCTAssertEqual([req fetchLimit], (NSUInteger)42);
    [req setFetchOffset:10];
    XCTAssertEqual([req fetchOffset], (NSUInteger)10);
}

- (void)testCopy
{
    NSFetchRequest *req = [[NSFetchRequest alloc] init];
    [req setFetchLimit:7];
    NSFetchRequest *copy = [req copy];
    XCTAssertNotNil(copy);
    XCTAssertEqual([copy fetchLimit], (NSUInteger)7);
}

- (void)testCopySharesThePredicate
{
    /* Apple's copy keeps the same predicate object, so a predicate whose
       constants cannot be copied (a managed object) survives the copy
       that -countForFetchRequest:error: makes. */
    NSObject *constant = [[NSObject alloc] init];
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Employee"];
    [req setPredicate:[NSComparisonPredicate
        predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"department"]
                    rightExpression:[NSExpression expressionForConstantValue:constant]
                           modifier:NSDirectPredicateModifier
                               type:NSEqualToPredicateOperatorType
                            options:0]];
    NSFetchRequest *copy = nil;
    XCTAssertNoThrow(copy = [req copy]);
    XCTAssertTrue([copy predicate] == [req predicate]);
}

- (void)testFetchRequestWithEntityNameStoresOnlyTheName
{
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:
                                              @"Employee"];

    XCTAssertEqualObjects([req entityName], @"Employee");

    /* Verified against Apple's CoreData: -entity on a name-based request
       raises NSObjectInaccessibleException ("...was created with a
       string name (Employee), and cannot respond to -entity until used
       by an NSManagedObjectContext") until the request is executed. */
    BOOL raised = NO;
    @try {
        (void)[req entity];
    }
    @catch (NSException *e) {
        raised = YES;
        XCTAssertEqualObjects([e name], NSObjectInaccessibleException);
    }
    XCTAssertTrue(raised,
                  @"-entity must raise before the request has been used");

    NSFetchRequest *copy = [req copy];
    XCTAssertEqualObjects([copy entityName], @"Employee");
}

- (void)testEntityNameIsResolvedWhenExecuted
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV1()];
    NSError *error = nil;
    NSPersistentStore *store =
        [psc addPersistentStoreWithType:NSInMemoryStoreType
                          configuration:nil
                                    URL:nil
                                options:nil
                                  error:&error];
    XCTAssertNotNil(store, @"failed to add store: %@", error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    NSManagedObject *employee =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:ctx];
    [employee setValue:@"Alice" forKey:@"name"];
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:
                                              @"Employee"];
    NSArray *result = [ctx executeFetchRequest:req error:&error];
    XCTAssertEqual([result count], (NSUInteger)1);
    XCTAssertEqualObjects([[result lastObject] valueForKey:@"name"],
                          @"Alice");

    /* Once the request has been used by a context, -entity responds
       with the resolved entity ("...until used by an
       NSManagedObjectContext"). */
    XCTAssertEqualObjects([[req entity] name], @"Employee");

    /* An entity name that is not in the model raises. */
    NSFetchRequest *bogus = [NSFetchRequest fetchRequestWithEntityName:
                                                @"NoSuchEntity"];
    BOOL raised = NO;
    @try {
        [ctx executeFetchRequest:bogus error:&error];
    }
    @catch (NSException *e) {
        raised = YES;
    }
    XCTAssertTrue(raised,
                  @"executing with an unknown entity name must raise");
}

static NSAttributeDescription *EntityTestAttribute(NSString *name, NSAttributeType type)
{
    NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
    [attribute setName:name];
    [attribute setAttributeType:type];
    [attribute setOptional:YES];
    return attribute;
}

/* Employee > Manager > Executive; a Department with a head and staff. */
static NSManagedObjectModel *EntityTestModel(void)
{
    NSEntityDescription *employee = [[NSEntityDescription alloc] init];
    [employee setName:@"Employee"];
    NSEntityDescription *manager = [[NSEntityDescription alloc] init];
    [manager setName:@"Manager"];
    NSEntityDescription *executive = [[NSEntityDescription alloc] init];
    [executive setName:@"Executive"];
    NSEntityDescription *department = [[NSEntityDescription alloc] init];
    [department setName:@"Department"];
    for (NSEntityDescription *entity in @[ employee, manager, executive, department ]) {
        [entity setManagedObjectClassName:@"NSManagedObject"];
    }
    NSRelationshipDescription *works = [[NSRelationshipDescription alloc] init];
    [works setName:@"department"];
    [works setDestinationEntity:department];
    [works setMaxCount:1];
    [works setOptional:YES];
    NSRelationshipDescription *staff = [[NSRelationshipDescription alloc] init];
    [staff setName:@"staff"];
    [staff setDestinationEntity:employee];
    [staff setMaxCount:0];
    [staff setOptional:YES];
    [works setInverseRelationship:staff];
    [staff setInverseRelationship:works];
    NSRelationshipDescription *head = [[NSRelationshipDescription alloc] init];
    [head setName:@"head"];
    [head setDestinationEntity:employee];
    [head setMaxCount:1];
    [head setOptional:YES];
    [employee setProperties:@[ EntityTestAttribute(@"name", NSStringAttributeType), works ]];
    [manager setProperties:@[ EntityTestAttribute(@"budget", NSInteger64AttributeType) ]];
    [executive setProperties:@[ EntityTestAttribute(@"bonus", NSInteger64AttributeType) ]];
    [department setProperties:@[ EntityTestAttribute(@"title", NSStringAttributeType), staff, head ]];
    [manager setSubentities:@[ executive ]];
    [employee setSubentities:@[ manager ]];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ employee, manager, executive, department ]];
    return model;
}

- (void)testPredicatesTestAnObjectsEntityInEveryStore
{
    /* Apple's stores all answer "entity" in a predicate, of the fetched
       object or one it reaches, so a fetch can pick objects by type; with
       it first, a subentity's property can follow it in an AND. */
    NSManagedObjectModel *model = EntityTestModel();
    NSDictionary *entities = [model entitiesByName];
    NSArray *managers = @[ entities[@"Manager"], entities[@"Executive"] ];
    NSArray *probes = @[
        @[ @"Employee", [NSPredicate predicateWithFormat:@"entity == %@", entities[@"Manager"]], @"m" ],
        @[ @"Employee", [NSPredicate predicateWithFormat:@"entity IN %@", managers], @"m,x" ],
        @[ @"Employee", [NSPredicate predicateWithFormat:@"name == 'e' OR (entity IN %@ AND budget > 15)", managers], @"e,x" ],
        @[ @"Department", [NSPredicate predicateWithFormat:@"head.entity IN %@", managers], @"D" ],
        @[ @"Department", [NSPredicate predicateWithFormat:@"head.entity IN %@ AND head.budget > 5", managers], @"D" ],
        @[ @"Department", [NSPredicate predicateWithFormat:@"SUBQUERY(staff, $s, $s.entity IN %@ AND $s.budget > 15).@count > 0", managers], @"D2" ],
        @[ @"Department", [NSPredicate predicateWithFormat:@"SUBQUERY(staff, $s, $s.entity == %@).@count > 0", entities[@"Executive"]], @"D2" ],
    ];
    for (NSString *type in @[ NSInMemoryStoreType, NSXMLStoreType, NSSQLiteStoreType ]) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
        NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        NSError *error = nil;
        XCTAssertNotNil([psc addPersistentStoreWithType:type configuration:nil URL:[NSURL fileURLWithPath:path] options:nil error:&error], @"%@", error);
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [context setPersistentStoreCoordinator:psc];
        [context performBlockAndWait:^{
            NSManagedObject *d = [NSEntityDescription insertNewObjectForEntityForName:@"Department" inManagedObjectContext:context];
            [d setValue:@"D" forKey:@"title"];
            NSManagedObject *d2 = [NSEntityDescription insertNewObjectForEntityForName:@"Department" inManagedObjectContext:context];
            [d2 setValue:@"D2" forKey:@"title"];
            NSManagedObject *e = [NSEntityDescription insertNewObjectForEntityForName:@"Employee" inManagedObjectContext:context];
            [e setValue:@"e" forKey:@"name"];
            [e setValue:d forKey:@"department"];
            NSManagedObject *m = [NSEntityDescription insertNewObjectForEntityForName:@"Manager" inManagedObjectContext:context];
            [m setValue:@"m" forKey:@"name"];
            [m setValue:@10 forKey:@"budget"];
            [m setValue:d forKey:@"department"];
            NSManagedObject *x = [NSEntityDescription insertNewObjectForEntityForName:@"Executive" inManagedObjectContext:context];
            [x setValue:@"x" forKey:@"name"];
            [x setValue:@20 forKey:@"budget"];
            [x setValue:d2 forKey:@"department"];
            [d setValue:m forKey:@"head"];
            [d2 setValue:e forKey:@"head"];
            NSError *saveError = nil;
            XCTAssertTrue([context save:&saveError], @"%@", saveError);
            [context reset];
        }];
        /* Then again from the file, but for the in-memory store: a store
           that loads a head before its element must know it as a Manager. */
        NSUInteger rounds = [type isEqualToString:NSInMemoryStoreType] ? 1 : 2;
        for (NSUInteger round = 0; round < rounds; round++) {
            if (round == 1) {
                psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
                XCTAssertNotNil([psc addPersistentStoreWithType:type configuration:nil URL:[NSURL fileURLWithPath:path] options:nil error:&error], @"%@", error);
                context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
                [context setPersistentStoreCoordinator:psc];
            }
            [context performBlockAndWait:^{
                for (NSArray *probe in probes) {
                    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:probe[0]];
                    [request setPredicate:probe[1]];
                    NSError *fetchError = nil;
                    NSArray *found = [context executeFetchRequest:request error:&fetchError];
                    NSString *key = [probe[0] isEqualToString:@"Department"] ? @"title" : @"name";
                    NSArray *names = [[found valueForKey:key] sortedArrayUsingSelector:@selector(compare:)];
                    NSString *joined = [names componentsJoinedByString:@","];
                    XCTAssertEqualObjects(joined, probe[2], @"%@ (round %lu): %@ (%@)", type, (unsigned long)round, probe[1], fetchError);
                }
            }];
        }
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    }
}

@end
