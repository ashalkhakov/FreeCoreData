/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDSQLStoreTestCase.h"

/* For +destroyStoreAtURL:options:error:, which every backend inherits and
   -tearDown uses to drop the schema a test worked in. */
#import "CDSQLStore.h"

/* A model with the shapes the store has to get right: every attribute type,
   a to-one/to-many pair backed by a foreign key, an ordered to-many, and a
   many-to-many backed by a join table. */
NSManagedObjectModel *CDSQLTestModel(void)
{
    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    [person setName:@"Person"];
    [person setManagedObjectClassName:@"NSManagedObject"];

    NSEntityDescription *company = [[NSEntityDescription alloc] init];
    [company setName:@"Company"];
    [company setManagedObjectClassName:@"NSManagedObject"];

    NSMutableArray *personProperties = [NSMutableArray array];
    NSDictionary *attributeTypes = @{
        @"name" : @(NSStringAttributeType),
        @"age" : @(NSInteger32AttributeType),
        @"score" : @(NSDoubleAttributeType),
        @"active" : @(NSBooleanAttributeType),
        @"birthday" : @(NSDateAttributeType),
        @"identifier" : @(NSUUIDAttributeType),
        @"picture" : @(NSBinaryDataAttributeType),
        @"balance" : @(NSDecimalAttributeType),
        @"homepage" : @(NSURIAttributeType),
        @"settings" : @(NSTransformableAttributeType),
    };

    for (NSString *name in attributeTypes) {
        NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
        [attribute setName:name];
        [attribute setAttributeType:[attributeTypes[name] unsignedIntegerValue]];
        [attribute setOptional:YES];
        [personProperties addObject:attribute];
    }

    NSRelationshipDescription *employer = [[NSRelationshipDescription alloc] init];
    [employer setName:@"employer"];
    [employer setDestinationEntity:company];
    [employer setMinCount:0];
    [employer setMaxCount:1];
    [employer setOptional:YES];

    NSRelationshipDescription *employees = [[NSRelationshipDescription alloc] init];
    [employees setName:@"employees"];
    [employees setDestinationEntity:person];
    [employees setMinCount:0];
    [employees setMaxCount:0];
    [employees setOrdered:YES];
    [employees setOptional:YES];

    [employer setInverseRelationship:employees];
    [employees setInverseRelationship:employer];

    /* Many-to-many: both sides are to-many, so this lives in a join table.
       The two sides are named differently because a relationship that is its
       own inverse is not something Core Data models. */
    NSRelationshipDescription *friends = [[NSRelationshipDescription alloc] init];
    [friends setName:@"friends"];
    [friends setDestinationEntity:person];
    [friends setMinCount:0];
    [friends setMaxCount:0];
    [friends setOptional:YES];

    NSRelationshipDescription *friendOf = [[NSRelationshipDescription alloc] init];
    [friendOf setName:@"friendOf"];
    [friendOf setDestinationEntity:person];
    [friendOf setMinCount:0];
    [friendOf setMaxCount:0];
    [friendOf setOptional:YES];

    [friends setInverseRelationship:friendOf];
    [friendOf setInverseRelationship:friends];

    [personProperties addObject:employer];
    [personProperties addObject:friends];
    [personProperties addObject:friendOf];
    [person setProperties:personProperties];

    /* A subentity, so that the root-table/Z_ENT machinery is exercised:
       Manager rows live in Person's table and carry their own column. */
    NSEntityDescription *manager = [[NSEntityDescription alloc] init];
    [manager setName:@"Manager"];
    [manager setManagedObjectClassName:@"NSManagedObject"];

    NSAttributeDescription *reports = [[NSAttributeDescription alloc] init];
    [reports setName:@"reports"];
    [reports setAttributeType:NSInteger32AttributeType];
    [reports setOptional:YES];

    [manager setProperties:@[ reports ]];
    [person setSubentities:@[ manager ]];

    NSAttributeDescription *companyName = [[NSAttributeDescription alloc] init];
    [companyName setName:@"name"];
    [companyName setAttributeType:NSStringAttributeType];
    [companyName setOptional:YES];

    [company setProperties:@[ companyName, employees ]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ person, company, manager ]];

    /* A configuration holding only the people half of the model. */
    [model setEntities:@[ person, manager ] forConfiguration:@"PeopleOnly"];

    return model;
}

@implementation CDSQLStoreTestCase

/* -- what the backend supplies ----------------------------------------- */

/* Abstract: a backend's suite overrides each of these.  The base class
   declares no tests, so nothing here is ever reached unless a backend
   forgot one. */

- (Class)storeClass                       { [self doesNotRecognizeSelector:_cmd]; return Nil; }
- (NSString *)storeType                   { [self doesNotRecognizeSelector:_cmd]; return nil; }
- (NSString *)schemaNameOptionKey         { [self doesNotRecognizeSelector:_cmd]; return nil; }
- (NSString *)migrateSchemaOptionKey      { [self doesNotRecognizeSelector:_cmd]; return nil; }
- (NSString *)URLEnvironmentVariableName  { [self doesNotRecognizeSelector:_cmd]; return nil; }
- (int)terminateOtherConnections          { [self doesNotRecognizeSelector:_cmd]; return 0; }

/* -- the fixture -------------------------------------------------------- */

/* The tests are no-ops without a server; XCTSkip is not available in every
   XCTest this project runs against, so each test asks first.

   A suite that skips itself reports success, which is the right answer on a
   developer's machine with no server and the wrong one in CI, where a
   database that failed to start would go unnoticed.  Setting
   CD_TEST_REQUIRE_DATABASE turns the skip into a failure. */
- (BOOL)databaseAvailable
{
    if (self.storeURL != nil)
        return YES;

    NSString *required = [[NSProcessInfo processInfo] environment][@"CD_TEST_REQUIRE_DATABASE"];

    if ([required length] > 0)
        XCTFail(@"CD_TEST_REQUIRE_DATABASE is set, but %@ names no reachable server",
                [self URLEnvironmentVariableName]);

    return NO;
}

- (void)setUp
{
    [super setUp];

    [NSPersistentStoreCoordinator registerStoreClass:[self storeClass]
                                        forStoreType:[self storeType]];

    /* Empty counts as absent: xcodebuild does not hand the shell's
       environment to the test process, so under Xcode this arrives through
       the TEST_RUNNER_ prefix (see README), and a variable set to nothing
       means the same as one that was never set. */
    NSString *variable = [self URLEnvironmentVariableName];
    NSString *url = [[NSProcessInfo processInfo] environment][variable];

    if ([url length] == 0) {
        static BOOL announced = NO;
        if (!announced) {
            NSLog(@"%@: set %@ to run these tests", [self class], variable);
            announced = YES;
        }
        return;
    }

    self.storeURL = [NSURL URLWithString:url];
    self.model = CDSQLTestModel();

    /* Short on purpose: PostgreSQL truncates identifiers past 63 bytes
       (MySQL at 64), and
       -globallyUniqueString is long enough (on macOS) that the part which
       makes it unique would be the part that gets cut off - leaving
       different tests sharing one schema. */
    static NSUInteger counter = 0;
    NSString *schema = [NSString stringWithFormat:@"cdtest_%d_%lu",
        (int)[[NSProcessInfo processInfo] processIdentifier], (unsigned long)(++counter)];

    self.storeOptions = @{ [self schemaNameOptionKey] : schema };
    self.context = [self newContext];
}

- (void)tearDown
{
    self.context = nil;

    if (self.storeURL != nil) {
        NSError *error = nil;
        if (![[self storeClass] destroyStoreAtURL:self.storeURL
                                             options:self.storeOptions
                                               error:&error])
            NSLog(@"could not drop the test schema: %@", error);
    }

    self.model = nil;
    self.storeURL = nil;
    self.storeOptions = nil;

    [super tearDown];
}

/* A fresh coordinator and context over the same schema, which is what an
   independent application run looks like.
 
   Callers keep the returned context in a local: a managed object does not
   retain its context, so objects read through a context that has already
   been released are reading freed memory. */
- (NSManagedObjectContext *)newContext
{
    NSPersistentStoreCoordinator *coordinator =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
    NSError *error = nil;
    NSPersistentStore *store =
        [coordinator addPersistentStoreWithType:[self storeType]
                                  configuration:nil
                                            URL:self.storeURL
                                        options:self.storeOptions
                                          error:&error];

    XCTAssertNotNil(store, @"could not open the store: %@", error);

    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
    [context setPersistentStoreCoordinator:coordinator];

    return context;
}

- (NSManagedObject *)insertPersonNamed:(NSString *)name age:(int)age
{
    NSManagedObject *person = [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                                            inManagedObjectContext:self.context];
    [person setValue:name forKey:@"name"];
    [person setValue:@(age) forKey:@"age"];

    return person;
}

- (NSArray *)fetchPeopleWithPredicate:(NSPredicate *)predicate
                      sortDescriptors:(NSArray *)sortDescriptors
                              context:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setPredicate:predicate];
    [fetch setSortDescriptors:sortDescriptors];

    NSError *error = nil;
    NSArray *result = [context executeFetchRequest:fetch error:&error];

    XCTAssertNotNil(result, @"fetch failed: %@", error);

    return result;
}

/* Fetches through the given context's own coordinator, so the object (and
   its object ID) belong to that context's store.  Handing an object ID from
   another coordinator to -objectWithID: does not: the fault is then served
   by the store the ID came from, which is not what two independent clients
   look like. */
- (NSManagedObject *)personNamed:(NSString *)name inContext:(NSManagedObjectContext *)context
{
    return [[self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"name == %@", name]
                           sortDescriptors:nil
                                   context:context] firstObject];
}

/* A predicate no store can translate - the SQL side has nothing to work
   with - so it is always the in-memory evaluator that answers it.  (A
   [c] comparison would do as well on Apple, but gnustep-base's in-memory
   evaluator does not honour the case-insensitive option for ==, so it
   would be testing the framework rather than the store.) */
- (NSPredicate *)namedPredicate:(NSString *)name
{
    return [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return [[object valueForKey:@"name"] isEqual:name];
    }];
}

- (BOOL)save
{
    NSError *error = nil;
    BOOL saved = [self.context save:&error];

    XCTAssertTrue(saved, @"save failed: %@", error);

    return saved;
}

@end
