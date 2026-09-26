/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSManagedObjectPredicateTests - fetching and counting with managed
   objects and object IDs in the predicate, on every store type.

   A predicate that compares a relationship, or SELF, with a managed object
   is ordinary Core Data: [NSPredicate predicateWithFormat:@"department ==
   %@", department]. Apple accepts the object or its NSManagedObjectID as
   the constant, in a fetch and in a count, on the SQLite, XML and
   in-memory stores alike (verified by the macOS run).

   Both used to fail here. The atomic stores (in-memory, XML) evaluate a
   fetch's predicate against their cache nodes, where a relationship's
   value is a node, never equal to a managed object or an ID, so every such
   fetch matched nothing. And counting copied the fetch request's
   predicate, which in gnustep-base copies each constant value; a managed
   object cannot be copied, so the count raised, on every store. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "VersioningTestModels.h"

@interface NSManagedObjectPredicateTests : XCTestCase
@property (nonatomic, strong) NSURL *storeURL;
@end

@implementation NSManagedObjectPredicateTests

- (void)setUp
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"store"];
    self.storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
}

- (void)tearDown
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    for (NSString *storeType in [self storeTypes]) {
        for (NSString *suffix in @[ @"", @"-wal", @"-shm" ]) {
            [fileManager removeItemAtPath:[[[self URLForStoreType:storeType] path] stringByAppendingString:suffix]
                                    error:NULL];
        }
    }
    self.storeURL = nil;
}

/* A file of its own for each store type: the SQLite store's database is
   not XML. */
- (NSURL *)URLForStoreType:(NSString *)storeType
{
    return [NSURL fileURLWithPath:[[self.storeURL path] stringByAppendingPathExtension:storeType]];
}

- (NSArray *)storeTypes
{
    return @[ NSInMemoryStoreType, NSSQLiteStoreType, NSXMLStoreType ];
}

/* Two departments, three employees, saved: Sales has Ann and Bob,
   Support has Cy. */
- (NSManagedObjectContext *)seededContextWithStoreType:(NSString *)storeType
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:VersioningTestModelV1()];
    NSError *error = nil;
    NSURL *url = [storeType isEqualToString:NSInMemoryStoreType] ? nil : [self URLForStoreType:storeType];
    NSPersistentStore *store = [psc addPersistentStoreWithType:storeType
                                                 configuration:nil
                                                           URL:url
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to add %@ store: %@", storeType, error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [ctx setPersistentStoreCoordinator:psc];

    NSManagedObject *sales = [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                                           inManagedObjectContext:ctx];
    [sales setValue:@"Sales" forKey:@"name"];
    NSManagedObject *support = [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                                             inManagedObjectContext:ctx];
    [support setValue:@"Support" forKey:@"name"];
    NSArray *people = @[ @[ @"Ann", sales ], @[ @"Bob", sales ], @[ @"Cy", support ] ];
    for (NSArray *person in people) {
        NSManagedObject *employee = [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                                                  inManagedObjectContext:ctx];
        [employee setValue:person[0] forKey:@"name"];
        [employee setValue:@1000 forKey:@"salary"];
        [employee setValue:person[1] forKey:@"department"];
    }
    XCTAssertTrue([ctx save:&error], @"save failed on %@: %@", storeType, error);
    return ctx;
}

- (NSManagedObject *)objectOf:(NSString *)entity named:(NSString *)name inContext:(NSManagedObjectContext *)ctx
{
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entity];
    [request setPredicate:[NSComparisonPredicate
        predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"name"]
                    rightExpression:[NSExpression expressionForConstantValue:name]
                           modifier:NSDirectPredicateModifier
                               type:NSEqualToPredicateOperatorType
                            options:0]];
    return [[ctx executeFetchRequest:request error:NULL] firstObject];
}

/* The names the request fetches, sorted, and what counting it gives. */
- (void)assertEntity:(NSString *)entity
           predicate:(NSPredicate *)predicate
             context:(NSManagedObjectContext *)ctx
             matches:(NSArray *)names
               label:(NSString *)label
{
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entity];
    [request setPredicate:predicate];
    NSError *error = nil;
    NSArray *fetched = [ctx executeFetchRequest:request error:&error];
    XCTAssertNotNil(fetched, @"%@: %@", label, error);
    XCTAssertEqualObjects([[fetched valueForKey:@"name"] sortedArrayUsingSelector:@selector(compare:)],
                          names, @"%@: fetch", label);

    NSUInteger count = NSNotFound;
    XCTAssertNoThrow(count = [ctx countForFetchRequest:request error:&error], @"%@: count", label);
    XCTAssertEqual(count, [names count], @"%@: count %@", label, error);
}

- (void)testRelationshipEqualToObject
{
    for (NSString *storeType in [self storeTypes]) {
        NSManagedObjectContext *ctx = [self seededContextWithStoreType:storeType];
        NSManagedObject *sales = [self objectOf:@"Department" named:@"Sales" inContext:ctx];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"department == %@", sales];
        [self assertEntity:@"Employee" predicate:predicate context:ctx
                   matches:@[ @"Ann", @"Bob" ]
                     label:[storeType stringByAppendingString:@" department == object"]];
        predicate = [NSPredicate predicateWithFormat:@"department != %@", sales];
        [self assertEntity:@"Employee" predicate:predicate context:ctx
                   matches:@[ @"Cy" ]
                     label:[storeType stringByAppendingString:@" department != object"]];
    }
}

- (void)testRelationshipEqualToObjectID
{
    for (NSString *storeType in [self storeTypes]) {
        NSManagedObjectContext *ctx = [self seededContextWithStoreType:storeType];
        NSManagedObject *support = [self objectOf:@"Department" named:@"Support" inContext:ctx];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"department == %@", [support objectID]];
        [self assertEntity:@"Employee" predicate:predicate context:ctx
                   matches:@[ @"Cy" ]
                     label:[storeType stringByAppendingString:@" department == objectID"]];
    }
}

- (void)testSelfEqualToAndInObjects
{
    for (NSString *storeType in [self storeTypes]) {
        NSManagedObjectContext *ctx = [self seededContextWithStoreType:storeType];
        NSManagedObject *ann = [self objectOf:@"Employee" named:@"Ann" inContext:ctx];
        NSManagedObject *cy = [self objectOf:@"Employee" named:@"Cy" inContext:ctx];
        [self assertEntity:@"Employee"
                 predicate:[NSPredicate predicateWithFormat:@"SELF == %@", ann]
                   context:ctx
                   matches:@[ @"Ann" ]
                     label:[storeType stringByAppendingString:@" SELF == object"]];
        [self assertEntity:@"Employee"
                 predicate:[NSPredicate predicateWithFormat:@"SELF IN %@", @[ ann, cy ]]
                   context:ctx
                   matches:@[ @"Ann", @"Cy" ]
                     label:[storeType stringByAppendingString:@" SELF IN objects"]];
        [self assertEntity:@"Employee"
                 predicate:[NSPredicate predicateWithFormat:@"SELF IN %@", [NSSet setWithObjects:[ann objectID], [cy objectID], nil]]
                   context:ctx
                   matches:@[ @"Ann", @"Cy" ]
                     label:[storeType stringByAppendingString:@" SELF IN objectIDs"]];
    }
}

- (void)testToManyContainsObject
{
    for (NSString *storeType in [self storeTypes]) {
        NSManagedObjectContext *ctx = [self seededContextWithStoreType:storeType];
        NSManagedObject *bob = [self objectOf:@"Employee" named:@"Bob" inContext:ctx];
        [self assertEntity:@"Department"
                 predicate:[NSPredicate predicateWithFormat:@"ANY employees == %@", bob]
                   context:ctx
                   matches:@[ @"Sales" ]
                     label:[storeType stringByAppendingString:@" ANY employees == object"]];
    }
}

/* An object from another context of the same coordinator names the same
   row; one that was never saved names none. */
- (void)testObjectsFromElsewhere
{
    for (NSString *storeType in [self storeTypes]) {
        NSManagedObjectContext *ctx = [self seededContextWithStoreType:storeType];
        NSManagedObjectContext *other = [[NSManagedObjectContext alloc]
            initWithConcurrencyType:NSMainQueueConcurrencyType];
        [other setPersistentStoreCoordinator:[ctx persistentStoreCoordinator]];
        NSManagedObject *sales = [self objectOf:@"Department" named:@"Sales" inContext:other];
        [self assertEntity:@"Employee"
                 predicate:[NSPredicate predicateWithFormat:@"department == %@", sales]
                   context:ctx
                   matches:@[ @"Ann", @"Bob" ]
                     label:[storeType stringByAppendingString:@" object from another context"]];

        NSManagedObject *unsaved = [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                                                 inManagedObjectContext:other];
        [unsaved setValue:@"Legal" forKey:@"name"];
        [self assertEntity:@"Employee"
                 predicate:[NSPredicate predicateWithFormat:@"department == %@", unsaved]
                   context:ctx
                   matches:@[]
                     label:[storeType stringByAppendingString:@" unsaved object"]];
    }
}

@end
