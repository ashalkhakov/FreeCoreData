/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* Tests for the PostgreSQL backend.  They need a database: set

      CD_TEST_POSTGRES_URL=postgresql://user:password@localhost/testdb

   and they run; leave it unset and every test returns immediately, so the
   suite is harmless on a machine without a server.  Each run works inside a
   schema of its own, dropped in -tearDown, so concurrent runs and leftovers
   from a crashed run cannot affect each other.

   Written against behavior Apple's CoreData defines, so that the same tests
   can be run on macOS against Apple's framework once this backend is built
   there. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "CDPostgreSQLStore.h"

/* One test needs a connection of its own, to pull the rug from under the
   store's. */
#import <libpq-fe.h>

/* Declared so the tests can ask, at runtime, whether they are running
   against a CoreData a store can implement history against.  This is
   FreeCoreData's own API; Apple's CoreData has no equivalent. */
@interface NSPersistentHistoryChangeRequest (CDFreeCoreDataAPI)
- (BOOL)isPurgeRequest;
@end

/* A model with the shapes the store has to get right: every attribute type,
   a to-one/to-many pair backed by a foreign key, an ordered to-many, and a
   many-to-many backed by a join table. */
static NSManagedObjectModel *CDPostgreSQLTestModel(void)
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

@interface CDPostgreSQLStoreTests : XCTestCase
@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSURL *storeURL;
@property (nonatomic, strong) NSDictionary *storeOptions;
@property (nonatomic, strong) NSManagedObjectContext *context;
@end

@implementation CDPostgreSQLStoreTests

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
        XCTFail(@"CD_TEST_REQUIRE_DATABASE is set, but CD_TEST_POSTGRES_URL names no reachable server");

    return NO;
}

- (void)setUp
{
    [super setUp];

    [NSPersistentStoreCoordinator registerStoreClass:[CDPostgreSQLStore class]
                                        forStoreType:CDPostgreSQLStoreType];

    /* Empty counts as absent: xcodebuild does not hand the shell's
       environment to the test process, so under Xcode this arrives through
       the TEST_RUNNER_ prefix (see README), and a variable set to nothing
       means the same as one that was never set. */
    NSString *url = [[NSProcessInfo processInfo] environment][@"CD_TEST_POSTGRES_URL"];

    if ([url length] == 0) {
        static BOOL announced = NO;
        if (!announced) {
            NSLog(@"CDPostgreSQLStoreTests: set CD_TEST_POSTGRES_URL to run these tests");
            announced = YES;
        }
        return;
    }

    self.storeURL = [NSURL URLWithString:url];
    self.model = CDPostgreSQLTestModel();

    /* Short on purpose: PostgreSQL truncates identifiers past 63 bytes, and
       -globallyUniqueString is long enough (on macOS) that the part which
       makes it unique would be the part that gets cut off - leaving
       different tests sharing one schema. */
    static NSUInteger counter = 0;
    NSString *schema = [NSString stringWithFormat:@"cdtest_%d_%lu",
        (int)[[NSProcessInfo processInfo] processIdentifier], (unsigned long)(++counter)];

    self.storeOptions = @{ CDPostgreSQLSchemaNameOption : schema };
    self.context = [self newContext];
}

- (void)tearDown
{
    self.context = nil;

    if (self.storeURL != nil) {
        NSError *error = nil;
        if (![CDPostgreSQLStore destroyStoreAtURL:self.storeURL
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
        [coordinator addPersistentStoreWithType:CDPostgreSQLStoreType
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

/* -- store setup ------------------------------------------------------ */

- (void)testStoreCreatesItsSchemaAndStampsMetadata
{
    if (![self databaseAvailable]) return;

    NSPersistentStore *store = [[[self.context persistentStoreCoordinator] persistentStores] firstObject];
    NSDictionary *metadata = [store metadata];

    XCTAssertEqualObjects([metadata objectForKey:NSStoreTypeKey], CDPostgreSQLStoreType);
    XCTAssertNotNil([metadata objectForKey:NSStoreUUIDKey]);

    NSDictionary *hashes = [metadata objectForKey:NSStoreModelVersionHashesKey];

    XCTAssertNotNil([hashes objectForKey:@"Person"]);
    XCTAssertNotNil([hashes objectForKey:@"Company"]);
}

- (void)testMetadataSurvivesReopening
{
    if (![self databaseAvailable]) return;

    NSString *uuid = [[[[[self.context persistentStoreCoordinator] persistentStores] firstObject] metadata]
                         objectForKey:NSStoreUUIDKey];

    NSManagedObjectContext *reopened = [self newContext];
    NSString *reopenedUUID = [[[[[reopened persistentStoreCoordinator] persistentStores] firstObject] metadata]
                                 objectForKey:NSStoreUUIDKey];

    XCTAssertEqualObjects(uuid, reopenedUUID);
}

/* -- round trips ------------------------------------------------------ */

- (void)testInsertedObjectIsReadBackByAFreshStack
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *people = [self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened];

    XCTAssertEqual([people count], (NSUInteger)1);
    XCTAssertEqualObjects([[people firstObject] valueForKey:@"name"], @"Ada");
    XCTAssertEqualObjects([[people firstObject] valueForKey:@"age"], @36);
}

- (void)testEveryAttributeTypeRoundTrips
{
    if (![self databaseAvailable]) return;

    NSUUID *identifier = [NSUUID UUID];
    NSDate *birthday = [NSDate dateWithTimeIntervalSinceReferenceDate:123456.75];
    NSData *picture = [@"not really a picture" dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *homepage = [NSURL URLWithString:@"https://example.org/ada"];
    NSDecimalNumber *balance = [NSDecimalNumber decimalNumberWithString:@"1234.56"];
    NSArray *settings = @[ @"dark", @42 ];

    NSManagedObject *person = [self insertPersonNamed:@"Ada" age:36];
    [person setValue:@(99.5) forKey:@"score"];
    [person setValue:@YES forKey:@"active"];
    [person setValue:birthday forKey:@"birthday"];
    [person setValue:identifier forKey:@"identifier"];
    [person setValue:picture forKey:@"picture"];
    [person setValue:balance forKey:@"balance"];
    [person setValue:homepage forKey:@"homepage"];
    [person setValue:settings forKey:@"settings"];

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened] firstObject];

    XCTAssertEqualObjects([read valueForKey:@"name"], @"Ada");
    XCTAssertEqualObjects([read valueForKey:@"age"], @36);
    XCTAssertEqualObjects([read valueForKey:@"score"], @(99.5));
    XCTAssertEqualObjects([read valueForKey:@"active"], @YES);
    XCTAssertEqualObjects([read valueForKey:@"birthday"], birthday);
    XCTAssertEqualObjects([read valueForKey:@"identifier"], identifier);
    XCTAssertEqualObjects([read valueForKey:@"picture"], picture);
    XCTAssertEqualObjects([read valueForKey:@"balance"], balance);
    XCTAssertEqualObjects([read valueForKey:@"homepage"], homepage);
    XCTAssertEqualObjects([read valueForKey:@"settings"], settings);
}

- (void)testNilAttributesStayNil
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened] firstObject];

    XCTAssertNil([read valueForKey:@"birthday"]);
    XCTAssertNil([read valueForKey:@"picture"]);
    XCTAssertNil([read valueForKey:@"employer"]);
}

- (void)testUpdateAndDelete
{
    if (![self databaseAvailable]) return;

    NSManagedObject *person = [self insertPersonNamed:@"Ada" age:36];
    if (![self save]) return;

    [person setValue:@37 forKey:@"age"];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened] firstObject];
    XCTAssertEqualObjects([read valueForKey:@"age"], @37);

    [self.context deleteObject:person];
    if (![self save]) return;

    NSManagedObjectContext *afterDelete = [self newContext];
    XCTAssertEqual([[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:afterDelete] count],
                   (NSUInteger)0);
}

/* -- predicates ------------------------------------------------------- */

- (void)testComparisonPredicates
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"alan" age:41];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];

    NSArray *equal = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"name == %@", @"Ada"]
                                    sortDescriptors:nil context:reopened];
    XCTAssertEqual([equal count], (NSUInteger)1);

    NSArray *greater = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"age > %d", 40]
                                      sortDescriptors:nil context:reopened];
    XCTAssertEqual([greater count], (NSUInteger)2);

    NSArray *between = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"age BETWEEN {%d, %d}", 40, 44]
                                      sortDescriptors:nil context:reopened];
    XCTAssertEqual([between count], (NSUInteger)1);

    NSArray *in = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"name IN %@", @[ @"Ada", @"Grace" ]]
                                 sortDescriptors:nil context:reopened];
    XCTAssertEqual([in count], (NSUInteger)2);
}

- (void)testStringMatchingIsCaseSensitiveUnlessAskedOtherwise
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"alan" age:41];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];

    NSArray *sensitive = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"name BEGINSWITH %@", @"A"]
                                        sortDescriptors:nil context:reopened];
    XCTAssertEqual([sensitive count], (NSUInteger)1);

    NSArray *insensitive = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"name BEGINSWITH[c] %@", @"a"]
                                          sortDescriptors:nil context:reopened];
    XCTAssertEqual([insensitive count], (NSUInteger)2);

    NSArray *equalInsensitive = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"name ==[c] %@", @"ADA"]
                                               sortDescriptors:nil context:reopened];
    XCTAssertEqual([equalInsensitive count], (NSUInteger)1);
}

/* A literal % in the constant is data, not a wildcard. */
- (void)testWildcardCharactersInAConstantAreEscaped
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"100%" age:1];
    [self insertPersonNamed:@"100 percent" age:2];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *people = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"name CONTAINS %@", @"0%"]
                                     sortDescriptors:nil context:reopened];

    XCTAssertEqual([people count], (NSUInteger)1);
    XCTAssertEqualObjects([[people firstObject] valueForKey:@"name"], @"100%");
}

- (void)testSortDescriptorsAndFetchLimit
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"alan" age:41];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *byAge = [self fetchPeopleWithPredicate:nil
                                    sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:NO] ]
                                            context:reopened];

    XCTAssertEqualObjects([[byAge firstObject] valueForKey:@"name"], @"Grace");

    NSArray *byName = [self fetchPeopleWithPredicate:nil
                                     sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name"
                                                                                      ascending:YES
                                                                                       selector:@selector(caseInsensitiveCompare:)] ]
                                             context:reopened];

    XCTAssertEqualObjects([[byName firstObject] valueForKey:@"name"], @"Ada");
    XCTAssertEqualObjects([[byName objectAtIndex:1] valueForKey:@"name"], @"alan");

    NSFetchRequest *limited = [[NSFetchRequest alloc] init];
    [limited setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [limited setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES] ]];
    [limited setFetchOffset:1];
    [limited setFetchLimit:1];

    NSError *error = nil;
    NSArray *page = [reopened executeFetchRequest:limited error:&error];

    XCTAssertEqual([page count], (NSUInteger)1);
    XCTAssertEqualObjects([[page firstObject] valueForKey:@"name"], @"alan");
}

- (void)testCountResultType
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"Grace" age:45];
    if (![self save]) return;

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"age > %d", 40]];

    NSError *error = nil;
    NSManagedObjectContext *reopened = [self newContext];
    NSUInteger count = [reopened countForFetchRequest:fetch error:&error];

    XCTAssertEqual(count, (NSUInteger)1, @"count failed: %@", error);
}

/* -- relationships ---------------------------------------------------- */

- (void)testToOneRelationshipRoundTripsAndFaults
{
    if (![self databaseAvailable]) return;

    NSManagedObject *company = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                            inManagedObjectContext:self.context];
    [company setValue:@"Bletchley" forKey:@"name"];

    NSManagedObject *person = [self insertPersonNamed:@"Ada" age:36];
    [person setValue:company forKey:@"employer"];

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened] firstObject];
    NSManagedObject *employer = [read valueForKey:@"employer"];

    XCTAssertNotNil(employer);
    XCTAssertEqualObjects([employer valueForKey:@"name"], @"Bletchley");
}

- (void)testToOneRelationshipIsSearchable
{
    if (![self databaseAvailable]) return;

    NSManagedObject *company = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                            inManagedObjectContext:self.context];
    [company setValue:@"Bletchley" forKey:@"name"];

    [[self insertPersonNamed:@"Ada" age:36] setValue:company forKey:@"employer"];
    [self insertPersonNamed:@"Grace" age:45];

    if (![self save]) return;

    NSArray *employed = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"employer != nil"]
                                       sortDescriptors:nil context:self.context];

    XCTAssertEqual([employed count], (NSUInteger)1);
    XCTAssertEqualObjects([[employed firstObject] valueForKey:@"name"], @"Ada");
}

- (void)testOrderedToManyKeepsItsOrder
{
    if (![self databaseAvailable]) return;

    NSManagedObject *company = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                            inManagedObjectContext:self.context];
    [company setValue:@"Bletchley" forKey:@"name"];

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    NSManagedObject *grace = [self insertPersonNamed:@"Grace" age:45];
    NSManagedObject *alan = [self insertPersonNamed:@"alan" age:41];

    [company setValue:[NSOrderedSet orderedSetWithObjects:grace, ada, alan, nil] forKey:@"employees"];

    if (![self save]) return;

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Company"]];

    NSError *error = nil;
    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [[reopened executeFetchRequest:fetch error:&error] firstObject];
    NSOrderedSet *employees = [read valueForKey:@"employees"];

    XCTAssertEqual([employees count], (NSUInteger)3);
    XCTAssertEqualObjects([[employees objectAtIndex:0] valueForKey:@"name"], @"Grace");
    XCTAssertEqualObjects([[employees objectAtIndex:1] valueForKey:@"name"], @"Ada");
    XCTAssertEqualObjects([[employees objectAtIndex:2] valueForKey:@"name"], @"alan");
}

- (void)testManyToManyUsesAJoinTableAndIsSymmetric
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    NSManagedObject *grace = [self insertPersonNamed:@"Grace" age:45];

    [ada setValue:[NSSet setWithObject:grace] forKey:@"friends"];

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *people = [self fetchPeopleWithPredicate:nil
                                     sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]
                                             context:reopened];

    NSManagedObject *readAda = [people firstObject];
    NSManagedObject *readGrace = [people lastObject];

    XCTAssertEqualObjects([[[readAda valueForKey:@"friends"] anyObject] valueForKey:@"name"], @"Grace");
    XCTAssertEqualObjects([[[readGrace valueForKey:@"friendOf"] anyObject] valueForKey:@"name"], @"Ada");
}

- (void)testDeletingAnObjectRemovesItsJoinRows
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    NSManagedObject *grace = [self insertPersonNamed:@"Grace" age:45];

    [ada setValue:[NSSet setWithObject:grace] forKey:@"friends"];
    if (![self save]) return;

    [self.context deleteObject:grace];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened] firstObject];

    XCTAssertEqualObjects([read valueForKey:@"name"], @"Ada");
    XCTAssertEqual([[read valueForKey:@"friends"] count], (NSUInteger)0);
}

/* -- object IDs ------------------------------------------------------- */

- (void)testPermanentIDsAreUniqueAndStable
{
    if (![self databaseAvailable]) return;

    NSMutableArray *people = [NSMutableArray array];

    for (int i = 0; i < 10; i++)
        [people addObject:[self insertPersonNamed:[NSString stringWithFormat:@"Person %d", i] age:i]];

    NSError *error = nil;
    XCTAssertTrue([self.context obtainPermanentIDsForObjects:people error:&error],
                  @"obtainPermanentIDs failed: %@", error);

    NSMutableSet *objectIDs = [NSMutableSet set];

    for (NSManagedObject *person in people) {
        XCTAssertFalse([[person objectID] isTemporaryID]);
        [objectIDs addObject:[person objectID]];
    }

    XCTAssertEqual([objectIDs count], (NSUInteger)10);

    if (![self save]) return;

    NSManagedObjectID *first = [[people firstObject] objectID];
    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *again = [reopened objectWithID:first];

    XCTAssertEqualObjects([again valueForKey:@"name"], @"Person 0");
}

/* -- batch requests ---------------------------------------------------- */

- (void)testBatchInsertFromDictionaries
{
    if (![self databaseAvailable]) return;

    NSBatchInsertRequest *request =
        [[NSBatchInsertRequest alloc] initWithEntityName:@"Person"
                                                 objects:@[ @{ @"name" : @"Ada", @"age" : @36 },
                                                            @{ @"name" : @"Grace", @"age" : @45 } ]];
    [request setResultType:NSBatchInsertRequestResultTypeCount];

    NSError *error = nil;
    NSBatchInsertResult *result = (NSBatchInsertResult *)[self.context executeRequest:request error:&error];

    XCTAssertNotNil(result, @"batch insert failed: %@", error);
    XCTAssertEqualObjects([result result], @2);
    XCTAssertEqual([result resultType], NSBatchInsertRequestResultTypeCount);

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *people = [self fetchPeopleWithPredicate:nil
                                     sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]
                                             context:reopened];

    XCTAssertEqual([people count], (NSUInteger)2);
    XCTAssertEqualObjects([[people firstObject] valueForKey:@"name"], @"Ada");
    XCTAssertEqualObjects([[people firstObject] valueForKey:@"age"], @36);
}

- (void)testBatchInsertWithDictionaryHandlerReturningObjectIDs
{
    if (![self databaseAvailable]) return;

    __block NSUInteger produced = 0;
    NSBatchInsertRequest *request =
        [[NSBatchInsertRequest alloc] initWithEntityName:@"Person"
                                       dictionaryHandler:^BOOL(NSMutableDictionary *row) {
            if (produced == 3)
                return YES;   /* done; this dictionary is not inserted */
            row[@"name"] = [NSString stringWithFormat:@"Person %lu", (unsigned long)produced];
            row[@"age"] = @(produced);
            produced++;
            return NO;
        }];
    [request setResultType:NSBatchInsertRequestResultTypeObjectIDs];

    NSError *error = nil;
    NSBatchInsertResult *result = (NSBatchInsertResult *)[self.context executeRequest:request error:&error];

    XCTAssertNotNil(result, @"batch insert failed: %@", error);

    NSArray *objectIDs = [result result];

    XCTAssertEqual([objectIDs count], (NSUInteger)3);

    NSManagedObjectContext *reopened = [self newContext];

    XCTAssertEqual([[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened] count],
                   (NSUInteger)3);
    XCTAssertEqualObjects([[reopened objectWithID:[objectIDs firstObject]] valueForKey:@"name"], @"Person 0");
}

- (void)testBatchUpdateAppliesOnlyToMatchingRows
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"alan" age:41];
    if (![self save]) return;

    NSBatchUpdateRequest *request = [[NSBatchUpdateRequest alloc] initWithEntityName:@"Person"];
    [request setPredicate:[NSPredicate predicateWithFormat:@"age > %d", 40]];
    [request setPropertiesToUpdate:@{ @"active" : @YES }];
    [request setResultType:NSUpdatedObjectsCountResultType];

    NSError *error = nil;
    NSBatchUpdateResult *result = (NSBatchUpdateResult *)[self.context executeRequest:request error:&error];

    XCTAssertNotNil(result, @"batch update failed: %@", error);
    XCTAssertEqualObjects([result result], @2);

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *active = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"active == YES"]
                                     sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]
                                             context:reopened];

    XCTAssertEqual([active count], (NSUInteger)2);
    XCTAssertEqualObjects([[active firstObject] valueForKey:@"name"], @"Grace");
}

- (void)testBatchUpdateCanSetAValueToNil
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    [ada setValue:[NSDate dateWithTimeIntervalSinceReferenceDate:1000] forKey:@"birthday"];
    if (![self save]) return;

    NSBatchUpdateRequest *request = [[NSBatchUpdateRequest alloc] initWithEntityName:@"Person"];
    [request setPropertiesToUpdate:@{ @"birthday" : [NSNull null] }];

    NSError *error = nil;
    XCTAssertNotNil([self.context executeRequest:request error:&error], @"batch update failed: %@", error);

    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened] firstObject];

    XCTAssertNil([read valueForKey:@"birthday"]);
}

/* A relationship cannot be batch updated.  Apple rejects it before the
   request ever reaches a store, by raising NSInvalidArgumentException, so
   both a raise and a returned error count as rejection here. */
- (void)testBatchUpdateRejectsARelationshipKey
{
    if (![self databaseAvailable]) return;

    NSBatchUpdateRequest *request = [[NSBatchUpdateRequest alloc] initWithEntityName:@"Person"];
    [request setPropertiesToUpdate:@{ @"employer" : [NSNull null] }];

    NSError *error = nil;
    id result = nil;
    BOOL raised = NO;

    @try {
        result = [self.context executeRequest:request error:&error];
    } @catch (NSException *exception) {
        raised = YES;
    }

    XCTAssertTrue(raised || (result == nil && error != nil),
                  @"batch updating a relationship should have been rejected");
}

- (void)testBatchDeleteByPredicateReturnsObjectIDs
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"alan" age:41];
    if (![self save]) return;

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"age > %d", 40]];

    NSBatchDeleteRequest *request = [[NSBatchDeleteRequest alloc] initWithFetchRequest:fetch];
    [request setResultType:NSBatchDeleteResultTypeObjectIDs];

    NSError *error = nil;
    NSBatchDeleteResult *result = (NSBatchDeleteResult *)[self.context executeRequest:request error:&error];

    XCTAssertNotNil(result, @"batch delete failed: %@", error);
    XCTAssertEqual([[result result] count], (NSUInteger)2);

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *left = [self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened];

    XCTAssertEqual([left count], (NSUInteger)1);
    XCTAssertEqualObjects([[left firstObject] valueForKey:@"name"], @"Ada");
}

/* -[NSBatchDeleteRequest initWithObjectIDs:] carries its list as a
   SELF IN <ids> predicate on its fetch request; the store translates that
   into a primary key list. */
- (void)testBatchDeleteByObjectIDs
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    NSManagedObject *grace = [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"alan" age:41];
    if (![self save]) return;

    NSBatchDeleteRequest *request =
        [[NSBatchDeleteRequest alloc] initWithObjectIDs:@[ [ada objectID], [grace objectID] ]];
    [request setResultType:NSBatchDeleteResultTypeCount];

    NSError *error = nil;
    NSBatchDeleteResult *result = (NSBatchDeleteResult *)[self.context executeRequest:request error:&error];

    XCTAssertNotNil(result, @"batch delete failed: %@", error);
    XCTAssertEqualObjects([result result], @2);

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *left = [self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened];

    XCTAssertEqual([left count], (NSUInteger)1);
    XCTAssertEqualObjects([[left firstObject] valueForKey:@"name"], @"alan");
}

/* A deleted row must not leave rows behind in a join table. */
- (void)testBatchDeleteRemovesJoinRows
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    NSManagedObject *grace = [self insertPersonNamed:@"Grace" age:45];

    [ada setValue:[NSSet setWithObject:grace] forKey:@"friends"];
    if (![self save]) return;

    NSBatchDeleteRequest *request = [[NSBatchDeleteRequest alloc] initWithObjectIDs:@[ [grace objectID] ]];

    NSError *error = nil;
    XCTAssertNotNil([self.context executeRequest:request error:&error], @"batch delete failed: %@", error);

    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened] firstObject];

    XCTAssertEqualObjects([read valueForKey:@"name"], @"Ada");
    XCTAssertEqual([[read valueForKey:@"friends"] count], (NSUInteger)0);
}

/* -- inheritance, configurations, object IDs --------------------------- */

- (void)testSubentityRowsShareTheRootTable
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    NSManagedObject *grace = [NSEntityDescription insertNewObjectForEntityForName:@"Manager"
                                                           inManagedObjectContext:self.context];
    [grace setValue:@"Grace" forKey:@"name"];
    [grace setValue:@45 forKey:@"age"];
    [grace setValue:@7 forKey:@"reports"];

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];

    /* A fetch of the parent entity includes subentities by default. */
    NSArray *people = [self fetchPeopleWithPredicate:nil
                                     sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]
                                             context:reopened];

    XCTAssertEqual([people count], (NSUInteger)2);
    XCTAssertEqualObjects([[[people lastObject] entity] name], @"Manager",
                          @"the row's own entity should come back, not the one fetched for");
    XCTAssertEqualObjects([[people lastObject] valueForKey:@"reports"], @7);

    /* ... and can be told not to. */
    NSFetchRequest *withoutSubentities = [[NSFetchRequest alloc] init];
    [withoutSubentities setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [withoutSubentities setIncludesSubentities:NO];

    NSError *error = nil;
    NSArray *plain = [reopened executeFetchRequest:withoutSubentities error:&error];

    XCTAssertEqual([plain count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[plain firstObject] valueForKey:@"name"], @"Ada");

    /* A fetch of the subentity alone finds only it. */
    NSFetchRequest *managers = [[NSFetchRequest alloc] init];
    [managers setEntity:[[self.model entitiesByName] objectForKey:@"Manager"]];

    NSArray *found = [reopened executeFetchRequest:managers error:&error];

    XCTAssertEqual([found count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[found firstObject] valueForKey:@"name"], @"Grace");
    XCTAssertEqualObjects([ada valueForKey:@"name"], @"Ada");
}

/* A relationship declared to the parent entity must fault in the row's own
   subentity - the case the Z_ENT column exists for. */
- (void)testRelationshipFaultResolvesTheConcreteSubentity
{
    if (![self databaseAvailable]) return;

    NSManagedObject *company = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                            inManagedObjectContext:self.context];
    [company setValue:@"Bletchley" forKey:@"name"];

    NSManagedObject *grace = [NSEntityDescription insertNewObjectForEntityForName:@"Manager"
                                                           inManagedObjectContext:self.context];
    [grace setValue:@"Grace" forKey:@"name"];
    [grace setValue:company forKey:@"employer"];

    if (![self save]) return;

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Company"]];

    NSError *error = nil;
    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [[reopened executeFetchRequest:fetch error:&error] firstObject];
    NSOrderedSet *employees = [read valueForKey:@"employees"];

    XCTAssertEqual([employees count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[[employees firstObject] entity] name], @"Manager");
}

- (void)testConfigurationLimitsTheStoreToItsEntities
{
    if (![self databaseAvailable]) return;

    NSPersistentStoreCoordinator *coordinator =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
    NSError *error = nil;
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:CDPostgreSQLStoreType
                                                         configuration:@"PeopleOnly"
                                                                   URL:self.storeURL
                                                               options:self.storeOptions
                                                                 error:&error];

    XCTAssertNotNil(store, @"could not open a configured store: %@", error);

    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
    [context setPersistentStoreCoordinator:coordinator];

    NSManagedObject *ada = [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                                         inManagedObjectContext:context];
    [ada setValue:@"Ada" forKey:@"name"];

    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    NSArray *people = [self fetchPeopleWithPredicate:nil sortDescriptors:nil context:context];

    XCTAssertEqual([people count], (NSUInteger)1);

    /* An entity outside the configuration has no store: Core Data either
       refuses the fetch or answers nothing, depending on the framework. */
    NSFetchRequest *companies = [[NSFetchRequest alloc] init];
    [companies setEntity:[[self.model entitiesByName] objectForKey:@"Company"]];

    NSArray *found = nil;

    @try {
        found = [context executeFetchRequest:companies error:&error];
    } @catch (NSException *exception) {
        found = nil;
    }

    XCTAssertEqual([found count], (NSUInteger)0);
}

- (void)testObjectIDSurvivesAURIRoundTrip
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    if (![self save]) return;

    NSURL *uri = [[ada objectID] URIRepresentation];

    XCTAssertNotNil(uri);

    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObjectID *recovered =
        [[reopened persistentStoreCoordinator] managedObjectIDForURIRepresentation:uri];

    XCTAssertNotNil(recovered, @"the coordinator could not read back %@", uri);
    XCTAssertEqualObjects([[recovered entity] name], @"Person");
    XCTAssertEqualObjects([[reopened objectWithID:recovered] valueForKey:@"name"], @"Ada");
}

/* Two processes opening the same new store race to create it; a server
   database has no file lock to hide that, so the store serializes creation
   with an advisory lock.  Threads stand in for the processes here. */
- (void)testConcurrentOpensCreateTheSchemaOnce
{
    if (![self databaseAvailable]) return;

    /* -setUp already created the schema, so this runs against one of its
       own that starts out empty. */
    NSString *schema = [NSString stringWithFormat:@"%@_race", self.storeOptions[CDPostgreSQLSchemaNameOption]];
    NSDictionary *options = @{ CDPostgreSQLSchemaNameOption : schema };

    NSUInteger const threadCount = 4;
    NSMutableArray *stores = [NSMutableArray array];
    NSMutableArray *failures = [NSMutableArray array];
    NSLock *lock = [[NSLock alloc] init];
    NSCondition *done = [[NSCondition alloc] init];
    __block NSUInteger finished = 0;

    for (NSUInteger i = 0; i < threadCount; i++) {
        [NSThread detachNewThreadWithBlock:^{
            @autoreleasepool {
                NSPersistentStoreCoordinator *coordinator =
                    [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
                NSError *error = nil;
                NSPersistentStore *store = [coordinator addPersistentStoreWithType:CDPostgreSQLStoreType
                                                                     configuration:nil
                                                                               URL:self.storeURL
                                                                           options:options
                                                                             error:&error];
                [lock lock];
                if (store != nil)
                    [stores addObject:store];
                else
                    [failures addObject:(error != nil ? error : (id)[NSNull null])];
                [lock unlock];

                [done lock];
                finished++;
                [done signal];
                [done unlock];
            }
        }];
    }

    [done lock];
    while (finished < threadCount)
        [done waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:30.0]];
    [done unlock];

    XCTAssertEqual([failures count], (NSUInteger)0, @"a concurrent open failed: %@", [failures firstObject]);
    XCTAssertEqual([stores count], threadCount);

    /* Every one of them agrees on the same store, which is only true if the
       schema was created once. */
    NSString *uuid = [[[stores firstObject] metadata] objectForKey:NSStoreUUIDKey];

    XCTAssertNotNil(uuid);
    for (NSPersistentStore *store in stores)
        XCTAssertEqualObjects([[store metadata] objectForKey:NSStoreUUIDKey], uuid);

    NSError *error = nil;
    [CDPostgreSQLStore destroyStoreAtURL:self.storeURL options:options error:&error];
}

/* -- schema migration -------------------------------------------------- */

/* A deliberately small model, built in two versions so that a migration has
   something to do.  v2 adds an attribute and an entity, renames an
   attribute (keeping its data), drops one, and widens another. */
static NSManagedObjectModel *CDMigrationModel(BOOL second)
{
    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"NSManagedObject"];

    NSMutableArray *properties = [NSMutableArray array];

    NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
    [text setName:@"text"];
    [text setAttributeType:NSStringAttributeType];
    [text setOptional:YES];
    [properties addObject:text];

    NSAttributeDescription *count = [[NSAttributeDescription alloc] init];
    [count setName:second ? @"tally" : @"count"];       /* renamed in v2 */
    if (second)
        [count setRenamingIdentifier:@"count"];
    [count setAttributeType:second ? NSInteger64AttributeType   /* widened */
                                   : NSInteger16AttributeType];
    [count setOptional:YES];
    [properties addObject:count];

    if (!second) {
        NSAttributeDescription *scratch = [[NSAttributeDescription alloc] init];
        [scratch setName:@"scratch"];                    /* dropped in v2 */
        [scratch setAttributeType:NSStringAttributeType];
        [scratch setOptional:YES];
        [properties addObject:scratch];
    }
    else {
        NSAttributeDescription *added = [[NSAttributeDescription alloc] init];
        [added setName:@"added"];                        /* new in v2 */
        [added setAttributeType:NSStringAttributeType];
        [added setOptional:YES];
        [properties addObject:added];
    }

    [note setProperties:properties];

    NSMutableArray *entities = [NSMutableArray arrayWithObject:note];

    if (second) {
        NSEntityDescription *tag = [[NSEntityDescription alloc] init];   /* new entity */
        [tag setName:@"Tag"];
        [tag setManagedObjectClassName:@"NSManagedObject"];

        NSAttributeDescription *label = [[NSAttributeDescription alloc] init];
        [label setName:@"label"];
        [label setAttributeType:NSStringAttributeType];
        [label setOptional:YES];

        [tag setProperties:@[ label ]];
        [entities addObject:tag];
    }

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:entities];

    return model;
}

- (NSManagedObjectContext *)contextForMigrationModel:(NSManagedObjectModel *)model
                                             options:(NSDictionary *)options
                                               error:(NSError **)error
{
    NSPersistentStoreCoordinator *coordinator =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSMutableDictionary *storeOptions = [options mutableCopy];

    storeOptions[CDPostgreSQLSchemaNameOption] =
        [NSString stringWithFormat:@"%@_mig", self.storeOptions[CDPostgreSQLSchemaNameOption]];

    if ([coordinator addPersistentStoreWithType:CDPostgreSQLStoreType
                                  configuration:nil
                                            URL:self.storeURL
                                        options:storeOptions
                                          error:error] == nil)
        return nil;

    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
    [context setPersistentStoreCoordinator:coordinator];

    return context;
}

- (void)destroyMigrationSchema
{
    NSString *schema = [NSString stringWithFormat:@"%@_mig", self.storeOptions[CDPostgreSQLSchemaNameOption]];
    NSError *error = nil;

    [CDPostgreSQLStore destroyStoreAtURL:self.storeURL
                                 options:@{ CDPostgreSQLSchemaNameOption : schema }
                                   error:&error];
}

- (void)testSchemaMigrationKeepsDataAndFollowsTheModel
{
    if (![self databaseAvailable]) return;

    NSError *error = nil;
    NSManagedObjectContext *first = [self contextForMigrationModel:CDMigrationModel(NO) options:@{} error:&error];

    XCTAssertNotNil(first, @"could not create the v1 store: %@", error);

    NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                                                          inManagedObjectContext:first];
    [note setValue:@"remember" forKey:@"text"];
    [note setValue:@7 forKey:@"count"];
    [note setValue:@"junk" forKey:@"scratch"];

    XCTAssertTrue([first save:&error], @"save failed: %@", error);

    /* Reopening with the newer model, asking for the schema to follow. */
    NSManagedObjectContext *second =
        [self contextForMigrationModel:CDMigrationModel(YES)
                               options:@{ CDPostgreSQLMigrateSchemaOption : @YES,
                                          NSIgnorePersistentStoreVersioningOption : @YES }
                                 error:&error];

    XCTAssertNotNil(second, @"migration failed: %@", error);

    NSFetchRequest *notes = [[NSFetchRequest alloc] init];
    [notes setEntity:[[[second persistentStoreCoordinator] managedObjectModel] entitiesByName][@"Note"]];

    NSArray *found = [second executeFetchRequest:notes error:&error];

    XCTAssertEqual([found count], (NSUInteger)1, @"fetch after migration failed: %@", error);

    NSManagedObject *migrated = [found firstObject];

    XCTAssertEqualObjects([migrated valueForKey:@"text"], @"remember", @"an untouched attribute should survive");
    XCTAssertEqualObjects([migrated valueForKey:@"tally"], @7, @"a renamed attribute should keep its value");
    XCTAssertNil([migrated valueForKey:@"added"], @"a new attribute starts empty");

    /* The new entity works, which means its table and bookkeeping row are
       both there. */
    NSManagedObject *tag = [NSEntityDescription insertNewObjectForEntityForName:@"Tag"
                                                         inManagedObjectContext:second];
    [tag setValue:@"urgent" forKey:@"label"];

    XCTAssertTrue([second save:&error], @"saving the new entity failed: %@", error);

    /* Writing the widened attribute with a value the old type could not
       hold proves the column really changed. */
    [migrated setValue:@70000 forKey:@"tally"];
    XCTAssertTrue([second save:&error], @"saving a widened value failed: %@", error);

    NSManagedObjectContext *third =
        [self contextForMigrationModel:CDMigrationModel(YES) options:@{} error:&error];

    XCTAssertNotNil(third, @"reopening the migrated store failed: %@", error);

    found = [third executeFetchRequest:notes error:&error];
    XCTAssertEqualObjects([[found firstObject] valueForKey:@"tally"], @70000);

    [self destroyMigrationSchema];
}

- (void)testIncompatibleModelIsRefusedWithoutTheOption
{
    if (![self databaseAvailable]) return;

    NSError *error = nil;

    XCTAssertNotNil([self contextForMigrationModel:CDMigrationModel(NO) options:@{} error:&error],
                    @"could not create the v1 store: %@", error);

    error = nil;
    NSManagedObjectContext *second =
        [self contextForMigrationModel:CDMigrationModel(YES)
                               options:@{ NSIgnorePersistentStoreVersioningOption : @YES }
                                 error:&error];

    XCTAssertNil(second, @"an incompatible model should not have opened the store");
    XCTAssertEqual([error code], (NSInteger)NSPersistentStoreIncompatibleVersionHashError);

    [self destroyMigrationSchema];
}

/* Reopening with the same model must not decide anything needs doing. */
- (void)testUnchangedModelIsNotMigrated
{
    if (![self databaseAvailable]) return;

    NSError *error = nil;

    XCTAssertNotNil([self contextForMigrationModel:CDMigrationModel(NO) options:@{} error:&error],
                    @"could not create the v1 store: %@", error);

    error = nil;
    XCTAssertNotNil([self contextForMigrationModel:CDMigrationModel(NO) options:@{} error:&error],
                    @"reopening with the same model should just work: %@", error);

    [self destroyMigrationSchema];
}

/* -- connection robustness --------------------------------------------- */

/* Terminates every other backend on this database, which is what a server
   restart or an idle-session timeout looks like to a client.  Answers how
   many were cut off. */
- (int)terminateOtherConnections
{
    PGconn *connection = PQconnectdb([[self.storeURL absoluteString] UTF8String]);

    if (PQstatus(connection) != CONNECTION_OK) {
        XCTFail(@"the test could not open its own connection: %s", PQerrorMessage(connection));
        PQfinish(connection);
        return 0;
    }

    PGresult *result = PQexec(connection,
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
        "WHERE datname = current_database() AND pid <> pg_backend_pid()");
    int terminated = (PQresultStatus(result) == PGRES_TUPLES_OK) ? PQntuples(result) : 0;

    PQclear(result);
    PQfinish(connection);

    return terminated;
}

- (void)testStoreRecoversFromADroppedConnection
{
    if (![self databaseAvailable]) return;

    NSManagedObjectContext *context = [self newContext];
    NSManagedObject *ada = [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                                         inManagedObjectContext:context];
    [ada setValue:@"Ada" forKey:@"name"];
    [ada setValue:@36 forKey:@"age"];

    NSError *error = nil;
    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    XCTAssertGreaterThan([self terminateOtherConnections], 0, @"nothing was disconnected");

    /* The store's connection is dead; the next statement finds out, and the
       store reconnects rather than failing. */
    NSArray *people = [self fetchPeopleWithPredicate:nil sortDescriptors:nil context:context];

    XCTAssertEqual([people count], (NSUInteger)1, @"the fetch after the drop should have succeeded");
    XCTAssertEqualObjects([[people firstObject] valueForKey:@"name"], @"Ada");

    /* And writing works again, on the new connection. */
    [[people firstObject] setValue:@37 forKey:@"age"];
    error = nil;
    XCTAssertTrue([context save:&error], @"the save after the drop failed: %@", error);

    NSManagedObjectContext *reopened = [self newContext];
    XCTAssertEqualObjects([[self personNamed:@"Ada" inContext:reopened] valueForKey:@"age"], @37);
}

/* The schema a store was confined to is session state, and does not survive
   a reset: if the store forgot to restore it, it would silently start
   reading the wrong tables. */
- (void)testSchemaSurvivesAReconnect
{
    if (![self databaseAvailable]) return;

    NSManagedObjectContext *context = [self newContext];

    [[NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context]
        setValue:@"Ada" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    [self terminateOtherConnections];

    NSArray *people = [self fetchPeopleWithPredicate:nil sortDescriptors:nil context:context];

    XCTAssertEqual([people count], (NSUInteger)1);
    XCTAssertEqualObjects([[people firstObject] valueForKey:@"name"], @"Ada",
                          @"after reconnecting the store should still be reading its own schema");
}

/* A connection lost mid-transaction must not be papered over: replaying one
   statement of a save on a fresh connection would write a fragment of it. */
- (void)testWorkLostMidTransactionIsReportedRatherThanPartlyApplied
{
    if (![self databaseAvailable]) return;

    NSManagedObjectContext *context = [self newContext];

    for (int i = 0; i < 20; i++) {
        NSManagedObject *person = [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                                                inManagedObjectContext:context];
        [person setValue:[NSString stringWithFormat:@"Person %d", i] forKey:@"name"];
    }

    /* Cut the connection while the save is in flight.  The save either
       completes (it beat the axe) or fails - but it must not leave half of
       the objects behind. */
    [NSThread detachNewThreadWithBlock:^{
        @autoreleasepool {
            [NSThread sleepForTimeInterval:0.002];
            [self terminateOtherConnections];
        }
    }];

    NSError *error = nil;
    BOOL saved = [context save:&error];

    NSManagedObjectContext *reopened = [self newContext];
    NSUInteger count = [[self fetchPeopleWithPredicate:nil sortDescriptors:nil context:reopened] count];

    if (saved)
        XCTAssertEqual(count, (NSUInteger)20, @"a save that reported success must be all there");
    else
        XCTAssertEqual(count, (NSUInteger)0, @"a save that failed must not have left a fragment behind");
}

/* -- predicates across relationships ----------------------------------- */

/* Builds: Bletchley employs Ada and alan; Hut8 employs Grace. */
- (void)seedCompaniesAndStaff
{
    NSManagedObject *bletchley = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                               inManagedObjectContext:self.context];
    [bletchley setValue:@"Bletchley" forKey:@"name"];

    NSManagedObject *hut8 = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                          inManagedObjectContext:self.context];
    [hut8 setValue:@"Hut8" forKey:@"name"];

    [[self insertPersonNamed:@"Ada" age:36] setValue:bletchley forKey:@"employer"];
    [[self insertPersonNamed:@"alan" age:41] setValue:bletchley forKey:@"employer"];
    [[self insertPersonNamed:@"Grace" age:45] setValue:hut8 forKey:@"employer"];
}

- (void)testPredicateAcrossAToOneRelationship
{
    if (![self databaseAvailable]) return;

    [self seedCompaniesAndStaff];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];

    NSArray *atBletchley = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"employer.name == %@", @"Bletchley"]
                                          sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]
                                                  context:reopened];

    XCTAssertEqual([atBletchley count], (NSUInteger)2);
    XCTAssertEqualObjects([[atBletchley firstObject] valueForKey:@"name"], @"Ada");

    NSArray *beginning = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"employer.name BEGINSWITH %@", @"H"]
                                        sortDescriptors:nil context:reopened];

    XCTAssertEqual([beginning count], (NSUInteger)1);
    XCTAssertEqualObjects([[beginning firstObject] valueForKey:@"name"], @"Grace");
}

/* The limit is pushed into SQL only when the predicate is; if this fetch
   fell back to in-memory filtering the offset would be applied to a
   different set, so it doubles as a check that the clause really ran in the
   database. */
- (void)testCrossRelationshipPredicateIsCombinedWithLimitAndOffset
{
    if (![self databaseAvailable]) return;

    [self seedCompaniesAndStaff];
    if (![self save]) return;

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"employer.name == %@", @"Bletchley"]];
    [fetch setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
    [fetch setFetchLimit:1];
    [fetch setFetchOffset:1];

    NSError *error = nil;
    NSManagedObjectContext *reopened = [self newContext];
    NSArray *page = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([page count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[page firstObject] valueForKey:@"name"], @"alan");
}

- (void)testAnyAcrossAToManyRelationship
{
    if (![self databaseAvailable]) return;

    NSManagedObject *company = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                            inManagedObjectContext:self.context];
    [company setValue:@"Bletchley" forKey:@"name"];

    NSManagedObject *empty = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                          inManagedObjectContext:self.context];
    [empty setValue:@"Empty" forKey:@"name"];

    [[self insertPersonNamed:@"Ada" age:36] setValue:company forKey:@"employer"];
    [[self insertPersonNamed:@"alan" age:41] setValue:company forKey:@"employer"];

    if (![self save]) return;

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Company"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"ANY employees.name == %@", @"Ada"]];

    NSError *error = nil;
    NSManagedObjectContext *reopened = [self newContext];
    NSArray *found = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([found count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[found firstObject] valueForKey:@"name"], @"Bletchley");

    /* A company with nobody in it matches no ANY. */
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"ANY employees.age > %d", 100]];
    XCTAssertEqual([[reopened executeFetchRequest:fetch error:&error] count], (NSUInteger)0);
}

- (void)testAllAcrossAToManyRelationship
{
    if (![self databaseAvailable]) return;

    NSManagedObject *seniors = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                            inManagedObjectContext:self.context];
    [seniors setValue:@"Seniors" forKey:@"name"];

    NSManagedObject *mixed = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                          inManagedObjectContext:self.context];
    [mixed setValue:@"Mixed" forKey:@"name"];

    [[self insertPersonNamed:@"Grace" age:45] setValue:seniors forKey:@"employer"];
    [[self insertPersonNamed:@"alan" age:41] setValue:seniors forKey:@"employer"];
    [[self insertPersonNamed:@"Ada" age:36] setValue:mixed forKey:@"employer"];
    [[self insertPersonNamed:@"Joan" age:44] setValue:mixed forKey:@"employer"];

    if (![self save]) return;

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Company"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"ALL employees.age > %d", 40]];
    [fetch setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];

    NSError *error = nil;
    NSManagedObjectContext *reopened = [self newContext];
    NSArray *found = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([found count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[found firstObject] valueForKey:@"name"], @"Seniors");
}

/* A row whose value is NULL fails the comparison, so ALL must not hold. */
- (void)testAllTreatsANullValueAsAFailure
{
    if (![self databaseAvailable]) return;

    NSManagedObject *company = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                            inManagedObjectContext:self.context];
    [company setValue:@"Bletchley" forKey:@"name"];

    [[self insertPersonNamed:@"Grace" age:45] setValue:company forKey:@"employer"];

    NSManagedObject *nameless = [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                                             inManagedObjectContext:self.context];
    [nameless setValue:company forKey:@"employer"];   /* age stays nil */

    if (![self save]) return;

    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Company"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"ALL employees.age > %d", 40]];

    NSError *error = nil;
    NSManagedObjectContext *reopened = [self newContext];

    XCTAssertEqual([[reopened executeFetchRequest:fetch error:&error] count], (NSUInteger)0,
                   @"fetch failed: %@", error);
}

- (void)testAnyAcrossAJoinTableRelationship
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    NSManagedObject *grace = [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"alan" age:41];

    [ada setValue:[NSSet setWithObject:grace] forKey:@"friends"];

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *found = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"ANY friends.name == %@", @"Grace"]
                                    sortDescriptors:nil
                                            context:reopened];

    XCTAssertEqual([found count], (NSUInteger)1);
    XCTAssertEqualObjects([[found firstObject] valueForKey:@"name"], @"Ada");
}

/* Two hops, and a predicate mixing a local column with one reached across a
   relationship. */
- (void)testPredicateAcrossTwoHopsAndCombinedWithALocalClause
{
    if (![self databaseAvailable]) return;

    [self seedCompaniesAndStaff];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *found = [self fetchPeopleWithPredicate:
                          [NSPredicate predicateWithFormat:@"employer.name == %@ AND age > %d", @"Bletchley", 40]
                                    sortDescriptors:nil
                                            context:reopened];

    XCTAssertEqual([found count], (NSUInteger)1);
    XCTAssertEqualObjects([[found firstObject] valueForKey:@"name"], @"alan");

    /* employer.employees walks a to-one and then a to-many. */
    NSArray *colleagues = [self fetchPeopleWithPredicate:
                               [NSPredicate predicateWithFormat:@"ANY employer.employees.name == %@", @"Grace"]
                                         sortDescriptors:nil
                                                 context:reopened];

    XCTAssertEqual([colleagues count], (NSUInteger)1);
    XCTAssertEqualObjects([[colleagues firstObject] valueForKey:@"name"], @"Grace");
}


/* -- query translation -------------------------------------------------- */

/* A predicate whose halves are not equally translatable used to translate
   as nothing at all: the fetch read the whole table and filtered in memory.
   What matters to a caller is that the answer is the same either way, which
   is what these pin down; the SQL itself is checked by hand against the
   server's statement log. */
- (void)testMixedPredicateAnswersTheSameAsItsParts
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    [ada setValue:[@"portrait" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"picture"];
    [self insertPersonNamed:@"Grace" age:45];            /* no picture */
    [[self insertPersonNamed:@"alan" age:41] setValue:[@"snap" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"picture"];

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];

    /* One half translates (age), the other is a binary column. */
    NSArray *both = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"age > %d AND picture != nil", 40]
                                   sortDescriptors:nil context:reopened];

    XCTAssertEqual([both count], (NSUInteger)1);
    XCTAssertEqualObjects([[both firstObject] valueForKey:@"name"], @"alan");

    /* And with a half that no store could translate - a block, which only
       the in-memory evaluator can run - the answer must still be right. */
    NSPredicate *mixedPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
        [NSPredicate predicateWithFormat:@"age > %d", 30],
        [self namedPredicate:@"Ada"] ]];
    NSArray *mixed = [self fetchPeopleWithPredicate:mixedPredicate sortDescriptors:nil context:reopened];

    XCTAssertEqual([mixed count], (NSUInteger)1);
    XCTAssertEqualObjects([[mixed firstObject] valueForKey:@"name"], @"Ada");
}

/* OR cannot be split: dropping a disjunct would narrow the result. */
- (void)testOrWithAnUntranslatableHalfStillAnswersCorrectly
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"alan" age:41];
    if (![self save]) return;

    NSPredicate *either = [NSCompoundPredicate orPredicateWithSubpredicates:@[
        [NSPredicate predicateWithFormat:@"age > %d", 44],
        [self namedPredicate:@"Ada"] ]];
    NSManagedObjectContext *reopened = [self newContext];
    NSArray *found = [self fetchPeopleWithPredicate:either
                                    sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]
                                            context:reopened];

    XCTAssertEqual([found count], (NSUInteger)2, @"both disjuncts must count");
}

/* "is it set" is exact for every column type, including the ones whose
   values cannot be compared in SQL at all. */
- (void)testIsNullWorksForEveryType
{
    if (![self databaseAvailable]) return;

    NSManagedObject *full = [self insertPersonNamed:@"Ada" age:36];
    [full setValue:[@"portrait" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"picture"];
    [full setValue:[NSUUID UUID] forKey:@"identifier"];
    [full setValue:@[ @"dark" ] forKey:@"settings"];

    [self insertPersonNamed:@"Grace" age:45];            /* all of them nil */

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];

    for (NSString *key in @[ @"picture", @"identifier", @"settings" ]) {
        NSArray *unset = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"%K == nil", key]
                                        sortDescriptors:nil context:reopened];
        NSArray *set = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"%K != nil", key]
                                      sortDescriptors:nil context:reopened];

        XCTAssertEqual([unset count], (NSUInteger)1, @"%@ == nil", key);
        XCTAssertEqualObjects([[unset firstObject] valueForKey:@"name"], @"Grace", @"%@ == nil", key);
        XCTAssertEqual([set count], (NSUInteger)1, @"%@ != nil", key);
        XCTAssertEqualObjects([[set firstObject] valueForKey:@"name"], @"Ada", @"%@ != nil", key);
    }
}

/* A UUID and a byte string are stored as themselves, so equality is exact
   even though ordering them would mean nothing. */
- (void)testEqualityOnUUIDAndBinaryColumns
{
    if (![self databaseAvailable]) return;

    NSUUID *wanted = [NSUUID UUID];
    NSData *picture = [@"portrait" dataUsingEncoding:NSUTF8StringEncoding];

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    [ada setValue:wanted forKey:@"identifier"];
    [ada setValue:picture forKey:@"picture"];

    NSManagedObject *grace = [self insertPersonNamed:@"Grace" age:45];
    [grace setValue:[NSUUID UUID] forKey:@"identifier"];
    [grace setValue:[@"other" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"picture"];

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];

    NSArray *byUUID = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"identifier == %@", wanted]
                                     sortDescriptors:nil context:reopened];

    XCTAssertEqual([byUUID count], (NSUInteger)1);
    XCTAssertEqualObjects([[byUUID firstObject] valueForKey:@"name"], @"Ada");

    NSArray *byBytes = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"picture == %@", picture]
                                      sortDescriptors:nil context:reopened];

    XCTAssertEqual([byBytes count], (NSUInteger)1);
    XCTAssertEqualObjects([[byBytes firstObject] valueForKey:@"name"], @"Ada");

    NSArray *inList = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"identifier IN %@", @[ wanted ]]
                                     sortDescriptors:nil context:reopened];

    XCTAssertEqual([inList count], (NSUInteger)1);
}

/* Counting asks the database for a count; the answer must not change. */
- (void)testCountMatchesTheFetchItCounts
{
    if (![self databaseAvailable]) return;

    for (int i = 0; i < 10; i++)
        [self insertPersonNamed:[NSString stringWithFormat:@"Person %d", i] age:i];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];

    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"age >= %d", 4]];

    NSError *error = nil;
    NSUInteger counted = [reopened countForFetchRequest:fetch error:&error];
    NSUInteger fetched = [[reopened executeFetchRequest:fetch error:&error] count];

    XCTAssertEqual(counted, (NSUInteger)6, @"count failed: %@", error);
    XCTAssertEqual(counted, fetched);

    /* A count whose predicate does not translate must still be right. */
    [fetch setPredicate:[self namedPredicate:@"Person 3"]];
    XCTAssertEqual([reopened countForFetchRequest:fetch error:&error], (NSUInteger)1);

    /* And a count with a limit keeps Apple's meaning. */
    [fetch setPredicate:nil];
    [fetch setFetchLimit:3];
    XCTAssertEqual([reopened countForFetchRequest:fetch error:&error], (NSUInteger)3);
}


/* Counting related rows is a question SQL answers directly. */
- (void)testCountOfARelationshipInAPredicate
{
    if (![self databaseAvailable]) return;

    NSManagedObject *big = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                        inManagedObjectContext:self.context];
    [big setValue:@"Bletchley" forKey:@"name"];

    NSManagedObject *small = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                          inManagedObjectContext:self.context];
    [small setValue:@"Hut8" forKey:@"name"];

    NSManagedObject *empty = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                          inManagedObjectContext:self.context];
    [empty setValue:@"Empty" forKey:@"name"];

    [[self insertPersonNamed:@"Ada" age:36] setValue:big forKey:@"employer"];
    [[self insertPersonNamed:@"alan" age:41] setValue:big forKey:@"employer"];
    [[self insertPersonNamed:@"Joan" age:44] setValue:big forKey:@"employer"];
    [[self insertPersonNamed:@"Grace" age:45] setValue:small forKey:@"employer"];

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Company"]];
    [fetch setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];

    NSError *error = nil;

    [fetch setPredicate:[NSPredicate predicateWithFormat:@"employees.@count > %d", 2]];
    NSArray *crowded = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([crowded count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[crowded firstObject] valueForKey:@"name"], @"Bletchley");

    /* Zero has to work too, which is the case a join would get wrong. */
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"employees.@count == %d", 0]];
    NSArray *deserted = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([deserted count], (NSUInteger)1);
    XCTAssertEqualObjects([[deserted firstObject] valueForKey:@"name"], @"Empty");

    /* And counting across a join table. */
    NSManagedObject *ada = [self personNamed:@"Ada" inContext:self.context];
    [ada setValue:[NSSet setWithObject:[self personNamed:@"Grace" inContext:self.context]] forKey:@"friends"];
    if (![self save]) return;

    NSManagedObjectContext *third = [self newContext];
    NSArray *sociable = [self fetchPeopleWithPredicate:[NSPredicate predicateWithFormat:@"friends.@count > %d", 0]
                                       sortDescriptors:nil context:third];

    XCTAssertEqual([sociable count], (NSUInteger)1);
    XCTAssertEqualObjects([[sociable firstObject] valueForKey:@"name"], @"Ada");
}

/* SUBQUERY narrows the rows before counting them.  gnustep-base cannot
   parse SUBQUERY at all, so this checks the translation where the framework
   can express it, and skips where it cannot. */
- (void)testFilteredCountOfARelationship
{
    if (![self databaseAvailable]) return;

    NSPredicate *predicate = nil;

    @try {
        predicate = [NSPredicate predicateWithFormat:@"SUBQUERY(employees, $e, $e.age > %d).@count > %d", 40, 1];
    } @catch (NSException *exception) {
        return;   /* this Foundation does not do SUBQUERY */
    }

    NSManagedObject *seniors = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                            inManagedObjectContext:self.context];
    [seniors setValue:@"Seniors" forKey:@"name"];

    NSManagedObject *mixed = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                          inManagedObjectContext:self.context];
    [mixed setValue:@"Mixed" forKey:@"name"];

    [[self insertPersonNamed:@"Grace" age:45] setValue:seniors forKey:@"employer"];
    [[self insertPersonNamed:@"alan" age:41] setValue:seniors forKey:@"employer"];
    [[self insertPersonNamed:@"Ada" age:36] setValue:mixed forKey:@"employer"];
    [[self insertPersonNamed:@"Joan" age:44] setValue:mixed forKey:@"employer"];

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Company"]];
    [fetch setPredicate:predicate];

    NSError *error = nil;
    NSArray *found = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([found count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[found firstObject] valueForKey:@"name"], @"Seniors");

    /* A filter that no row satisfies counts to zero everywhere. */
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"SUBQUERY(employees, $e, $e.age > %d).@count > %d", 100, 0]];
    XCTAssertEqual([[reopened executeFetchRequest:fetch error:&error] count], (NSUInteger)0);
}


/* Sorting on a value that lives in another table: the store joins it in
   rather than sorting in memory, and a row with nothing related still
   sorts - which is why the join is a LEFT one. */
- (void)testSortingAcrossAToOneRelationship
{
    if (![self databaseAvailable]) return;

    NSManagedObject *acme = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                         inManagedObjectContext:self.context];
    [acme setValue:@"Acme" forKey:@"name"];

    NSManagedObject *zenith = [NSEntityDescription insertNewObjectForEntityForName:@"Company"
                                                           inManagedObjectContext:self.context];
    [zenith setValue:@"Zenith" forKey:@"name"];

    [[self insertPersonNamed:@"Worker at Zenith" age:30] setValue:zenith forKey:@"employer"];
    [[self insertPersonNamed:@"Worker at Acme" age:31] setValue:acme forKey:@"employer"];
    [self insertPersonNamed:@"Unemployed" age:32];      /* no employer at all */

    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSArray *byEmployer = [self fetchPeopleWithPredicate:nil
                                         sortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"employer.name" ascending:YES],
                                                            [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]
                                                 context:reopened];

    XCTAssertEqual([byEmployer count], (NSUInteger)3, @"the employer-less row must not be dropped");

    NSMutableArray *names = [NSMutableArray array];

    for (NSManagedObject *person in byEmployer)
        [names addObject:[person valueForKey:@"name"]];

    /* Whether a missing value sorts first or last is the database's
       business; what matters is that all three came back and the two with
       employers are in employer order. */
    NSUInteger acmeIndex = [names indexOfObject:@"Worker at Acme"];
    NSUInteger zenithIndex = [names indexOfObject:@"Worker at Zenith"];

    XCTAssertNotEqual(acmeIndex, (NSUInteger)NSNotFound);
    XCTAssertNotEqual(zenithIndex, (NSUInteger)NSNotFound);
    XCTAssertLessThan(acmeIndex, zenithIndex, @"Acme sorts before Zenith");

    /* Descending, and combined with a predicate and a limit - which are
       only pushed into SQL when the sort is. */
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"employer != nil"]];
    [fetch setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"employer.name" ascending:NO] ]];
    [fetch setFetchLimit:1];

    NSError *error = nil;
    NSArray *top = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([top count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[top firstObject] valueForKey:@"name"], @"Worker at Zenith");
}

/* Sorting on a to-many has no single value to sort by, so it stays in
   memory - and must still answer correctly. */
- (void)testSortingAcrossAToManyStillAnswers
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"Grace" age:45];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Company"]];
    [fetch setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"employees.name" ascending:YES] ]];

    NSError *error = nil;
    NSArray *found = nil;

    @try {
        found = [reopened executeFetchRequest:fetch error:&error];
    } @catch (NSException *exception) {
        return;   /* the framework may refuse the descriptor outright */
    }

    XCTAssertNotNil(found, @"fetch failed: %@", error);
}


/* A dictionary result asks for values, so the store reads columns instead
   of building objects - and lets the database do DISTINCT, GROUP BY and the
   aggregate. */
- (void)testDictionaryResultsAreReadAsColumns
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"alan" age:41];
    [self insertPersonNamed:@"Joan" age:41];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];

    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setResultType:NSDictionaryResultType];
    [fetch setPropertiesToFetch:@[ @"name", @"age" ]];
    [fetch setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES] ]];

    NSError *error = nil;
    NSArray *rows = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([rows count], (NSUInteger)4, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[rows firstObject] objectForKey:@"name"], @"Ada");
    XCTAssertEqualObjects([[rows firstObject] objectForKey:@"age"], @36);
    XCTAssertNil([[rows firstObject] objectForKey:@"score"], @"only what was asked for");

    /* DISTINCT over one column. */
    [fetch setPropertiesToFetch:@[ @"age" ]];
    [fetch setReturnsDistinctResults:YES];

    NSArray *ages = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([ages count], (NSUInteger)3, @"41 appears twice but distinctly once");
}

- (void)testAggregateInADictionaryResult
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:36];
    [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"alan" age:41];
    if (![self save]) return;

    NSExpressionDescription *oldest = [[NSExpressionDescription alloc] init];
    [oldest setName:@"oldest"];
    [oldest setExpression:[NSExpression expressionForFunction:@"max:"
                                                    arguments:@[ [NSExpression expressionForKeyPath:@"age"] ]]];
    [oldest setExpressionResultType:NSInteger64AttributeType];

    NSManagedObjectContext *reopened = [self newContext];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];

    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setResultType:NSDictionaryResultType];
    [fetch setPropertiesToFetch:@[ oldest ]];

    NSError *error = nil;
    NSArray *rows = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([rows count], (NSUInteger)1, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[rows firstObject] objectForKey:@"oldest"], @45);
}


/* Grouped reports: the database groups, counts and filters the groups. */
- (void)testGroupByWithAnAggregate
{
    if (![self databaseAvailable]) return;

    /* Three at Bletchley, one at Hut8, told apart by the employer's name
       through a plain attribute so the grouping stays on one table. */
    [self insertPersonNamed:@"Ada" age:41];
    [self insertPersonNamed:@"alan" age:41];
    [self insertPersonNamed:@"Joan" age:41];
    [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"Mary" age:36];
    if (![self save]) return;

    NSExpressionDescription *headcount = [[NSExpressionDescription alloc] init];
    [headcount setName:@"headcount"];
    [headcount setExpression:[NSExpression expressionForFunction:@"count:"
                                                       arguments:@[ [NSExpression expressionForKeyPath:@"name"] ]]];
    [headcount setExpressionResultType:NSInteger64AttributeType];

    NSManagedObjectContext *reopened = [self newContext];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];

    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setResultType:NSDictionaryResultType];
    [fetch setPropertiesToFetch:@[ @"age", headcount ]];
    [fetch setPropertiesToGroupBy:@[ @"age" ]];
    [fetch setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES] ]];

    NSError *error = nil;
    NSArray *rows = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([rows count], (NSUInteger)3, @"one row per age: %@", error);
    XCTAssertEqualObjects([[rows firstObject] objectForKey:@"age"], @36);
    XCTAssertEqualObjects([[rows firstObject] objectForKey:@"headcount"], @1);
    XCTAssertEqualObjects([[rows objectAtIndex:1] objectForKey:@"age"], @41);
    XCTAssertEqualObjects([[rows objectAtIndex:1] objectForKey:@"headcount"], @3);
}

/* HAVING names what the query selects, and keeps only the groups that
   pass. */
- (void)testGroupByWithHaving
{
    if (![self databaseAvailable]) return;

    [self insertPersonNamed:@"Ada" age:41];
    [self insertPersonNamed:@"alan" age:41];
    [self insertPersonNamed:@"Joan" age:41];
    [self insertPersonNamed:@"Grace" age:45];
    [self insertPersonNamed:@"Mary" age:36];
    if (![self save]) return;

    NSExpressionDescription *headcount = [[NSExpressionDescription alloc] init];
    [headcount setName:@"headcount"];
    [headcount setExpression:[NSExpression expressionForFunction:@"count:"
                                                       arguments:@[ [NSExpression expressionForKeyPath:@"name"] ]]];
    [headcount setExpressionResultType:NSInteger64AttributeType];

    NSManagedObjectContext *reopened = [self newContext];
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];

    [fetch setEntity:[[self.model entitiesByName] objectForKey:@"Person"]];
    [fetch setResultType:NSDictionaryResultType];
    [fetch setPropertiesToFetch:@[ @"age", headcount ]];
    [fetch setPropertiesToGroupBy:@[ @"age" ]];
    /* The aggregate written out, which is the form Apple documents and
       the only one this framework's in-memory grouping understands. */
    [fetch setHavingPredicate:[NSPredicate predicateWithFormat:@"count:(name) > %d", 1]];

    NSError *error = nil;
    NSArray *rows = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([rows count], (NSUInteger)1, @"only the group of three: %@", error);
    XCTAssertEqualObjects([[rows firstObject] objectForKey:@"age"], @41);
    XCTAssertEqualObjects([[rows firstObject] objectForKey:@"headcount"], @3);

    /* Sorting by the aggregate itself, which only a grouped query can do:
       the name exists on the row, not on any object, so the order has to
       be taken after the rows are built. */
    [fetch setHavingPredicate:nil];
    [fetch setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"headcount" ascending:NO] ]];

    rows = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([rows count], (NSUInteger)3, @"fetch failed: %@", error);
    XCTAssertEqualObjects([[rows firstObject] objectForKey:@"headcount"], @3);

    /* A predicate narrows the rows before they are grouped. */
    [fetch setSortDescriptors:nil];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"age > %d", 40]];

    rows = [reopened executeFetchRequest:fetch error:&error];

    XCTAssertEqual([rows count], (NSUInteger)2, @"36 is filtered out before grouping: %@", error);
}

/* -- optimistic locking ------------------------------------------------ */

/* Two clients read the same row; the second one to save is writing over a
   version it never saw, and has to be told so rather than winning silently.
   Each context here has its own coordinator and its own connection, which is
   what two processes look like from the database's side.
 
   Which layer notices is up to the framework: a context that re-reads the
   row at save time catches it before the store is ever asked (both Apple's
   CoreData and FreeCoreData do), and the store's own check is the backstop
   for what a context cannot see.  What matters here is that the save is
   refused either way - the store-level check is exercised directly by
   -testStoreRefusesAStaleUpdate below. */
- (void)testStaleUpdateIsReportedAsAConflict
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    if (![self save]) return;

    NSManagedObjectContext *first = [self newContext];
    NSManagedObjectContext *second = [self newContext];

    /* Both read the row through their own store, so both expect version 1. */
    NSManagedObject *inFirst = [self personNamed:@"Ada" inContext:first];
    NSManagedObject *inSecond = [self personNamed:@"Ada" inContext:second];

    XCTAssertEqualObjects([inFirst valueForKey:@"age"], @36);
    XCTAssertEqualObjects([inSecond valueForKey:@"age"], @36);

    NSError *error = nil;

    [inFirst setValue:@40 forKey:@"age"];
    XCTAssertTrue([first save:&error], @"the first save should succeed: %@", error);

    [inSecond setValue:@50 forKey:@"age"];

    error = nil;
    XCTAssertFalse([second save:&error], @"the second save should have been refused");
    XCTAssertNotNil(error);

    /* The row keeps what the first client wrote. */
    XCTAssertEqualObjects([[self personNamed:@"Ada" inContext:[self newContext]] valueForKey:@"age"], @40);
    XCTAssertEqualObjects([ada valueForKey:@"name"], @"Ada");
}

/* The store's own check, exercised where the context cannot mask it: the
   save request is handed to the store directly, after another client has
   moved the row on.  This is the path that protects against writers the
   framework knows nothing about. */
- (void)testStoreRefusesAStaleUpdate
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    if (![self save]) return;

    NSManagedObjectContext *reader = [self newContext];
    NSManagedObject *inReader = [self personNamed:@"Ada" inContext:reader];
    NSManagedObjectID *objectID = [inReader objectID];

    XCTAssertEqualObjects([inReader valueForKey:@"name"], @"Ada");   /* version 1 */

    /* Another client moves the row on. */
    NSManagedObjectContext *writer = [self newContext];
    NSManagedObject *inWriter = [self personNamed:@"Ada" inContext:writer];
    NSError *error = nil;

    [inWriter setValue:@"Ada Lovelace" forKey:@"name"];
    XCTAssertTrue([writer save:&error], @"the first save should succeed: %@", error);

    /* Hand the stale update straight to the store. */
    [inReader setValue:@"Ada L" forKey:@"name"];

    NSIncrementalStore *store = (NSIncrementalStore *)
        [[[reader persistentStoreCoordinator] persistentStores] firstObject];
    NSSaveChangesRequest *request =
        [[NSSaveChangesRequest alloc] initWithInsertedObjects:nil
                                              updatedObjects:[NSSet setWithObject:inReader]
                                              deletedObjects:nil
                                               lockedObjects:nil];

    error = nil;
    id result = [store executeRequest:request withContext:reader error:&error];

    XCTAssertNil(result, @"the store should have refused a stale update");
    XCTAssertEqual([error code], (NSInteger)NSPersistentStoreSaveConflictsError);

    NSArray *conflicts = [[error userInfo] objectForKey:NSPersistentStoreSaveConflictsErrorKey];

    XCTAssertEqual([conflicts count], (NSUInteger)1);

    NSMergeConflict *conflict = [conflicts firstObject];

    XCTAssertEqualObjects([[[conflict sourceObject] objectID] URIRepresentation], [objectID URIRepresentation]);
    XCTAssertEqual([conflict oldVersionNumber], (NSUInteger)1);
    XCTAssertEqual([conflict newVersionNumber], (NSUInteger)2);
    XCTAssertEqualObjects([[conflict persistedSnapshot] objectForKey:@"name"], @"Ada Lovelace",
                          @"the conflict should carry the row as it now stands");

    /* Nothing of the refused save reached the database. */
    XCTAssertEqualObjects([[self personNamed:@"Ada Lovelace" inContext:[self newContext]] valueForKey:@"name"],
                          @"Ada Lovelace");
    XCTAssertEqualObjects([ada valueForKey:@"name"], @"Ada");
}

/* A batch update bumps the rows behind every context's back, which is the
   same situation seen from one process. */
- (void)testUpdateAfterABatchUpdateConflicts
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    if (![self save]) return;

    NSManagedObjectContext *reader = [self newContext];
    NSManagedObject *inReader = [self personNamed:@"Ada" inContext:reader];

    XCTAssertEqualObjects([inReader valueForKey:@"age"], @36);

    NSBatchUpdateRequest *request = [[NSBatchUpdateRequest alloc] initWithEntityName:@"Person"];
    [request setPropertiesToUpdate:@{ @"age" : @99 }];

    NSError *error = nil;
    XCTAssertNotNil([reader executeRequest:request error:&error], @"batch update failed: %@", error);

    [inReader setValue:@50 forKey:@"age"];

    /* Straight to the store: whether a context refreshes its objects after a
       batch request is the framework's business, and this is about the
       store noticing that the row moved on. */
    NSIncrementalStore *store = (NSIncrementalStore *)
        [[[reader persistentStoreCoordinator] persistentStores] firstObject];
    NSSaveChangesRequest *save =
        [[NSSaveChangesRequest alloc] initWithInsertedObjects:nil
                                              updatedObjects:[NSSet setWithObject:inReader]
                                              deletedObjects:nil
                                               lockedObjects:nil];

    error = nil;
    XCTAssertNil([store executeRequest:save withContext:reader error:&error],
                 @"a save over a batch-updated row should be refused");
    XCTAssertEqual([error code], (NSInteger)NSPersistentStoreSaveConflictsError);
}

/* An update through the same store that read the row is not a conflict -
   the common case must not regress. */
- (void)testOrdinaryUpdateIsNotAConflict
{
    if (![self databaseAvailable]) return;

    NSManagedObject *ada = [self insertPersonNamed:@"Ada" age:36];
    if (![self save]) return;

    NSManagedObjectContext *reopened = [self newContext];
    NSManagedObject *read = [self personNamed:@"Ada" inContext:reopened];

    XCTAssertEqualObjects([read valueForKey:@"age"], @36);
    [read setValue:@37 forKey:@"age"];

    NSError *error = nil;
    XCTAssertTrue([reopened save:&error], @"save failed: %@", error);

    [read setValue:@38 forKey:@"age"];
    XCTAssertTrue([reopened save:&error], @"a second save through the same store failed: %@", error);

    XCTAssertEqualObjects([[self personNamed:@"Ada" inContext:[self newContext]] valueForKey:@"age"], @38);
    XCTAssertEqualObjects([ada valueForKey:@"name"], @"Ada");
}

/* -- persistent history ------------------------------------------------ */

/* History needs what no public API exposes - whether a request is a fetch or
   a purge, and what it is anchored to - so the store supports it against
   FreeCoreData only.  Built against Apple's CoreData these tests check that
   it is refused, rather than checking behavior that cannot be delivered
   there. */
- (BOOL)historySupported
{
    return [NSPersistentHistoryChangeRequest instancesRespondToSelector:@selector(isPurgeRequest)];
}

- (NSManagedObjectContext *)newHistoryTrackingContext
{
    NSMutableDictionary *options = [self.storeOptions mutableCopy];
    options[NSPersistentHistoryTrackingKey] = @YES;

    NSPersistentStoreCoordinator *coordinator =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
    NSError *error = nil;
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:CDPostgreSQLStoreType
                                                         configuration:nil
                                                                   URL:self.storeURL
                                                               options:options
                                                                 error:&error];

    XCTAssertNotNil(store, @"could not open a history-tracking store: %@", error);

    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
    [context setPersistentStoreCoordinator:coordinator];

    return context;
}

- (void)testHistoryIsRefusedWithoutFreeCoreData
{
    if (![self databaseAvailable]) return;
    if ([self historySupported]) return;

    NSError *error = nil;
    id result = nil;

    @try {
        result = [self.context executeRequest:[NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]]
                                        error:&error];
    } @catch (NSException *exception) {
        result = nil;
    }

    XCTAssertNil(result);
}

- (void)testHistoryRecordsATransactionPerSave
{
    if (![self databaseAvailable] || ![self historySupported]) return;

    NSManagedObjectContext *context = [self newHistoryTrackingContext];

    NSManagedObject *ada = [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                                         inManagedObjectContext:context];
    [ada setValue:@"Ada" forKey:@"name"];

    NSError *error = nil;
    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    [ada setValue:@37 forKey:@"age"];
    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]];
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[context executeRequest:request error:&error];

    XCTAssertNotNil(result, @"history fetch failed: %@", error);

    NSArray *transactions = [result result];

    XCTAssertEqual([transactions count], (NSUInteger)2);

    NSPersistentHistoryTransaction *first = [transactions firstObject];
    NSPersistentHistoryTransaction *second = [transactions lastObject];

    XCTAssertEqual([[first changes] count], (NSUInteger)1);
    XCTAssertEqual([(NSPersistentHistoryChange *)[[first changes] firstObject] changeType],
                   NSPersistentHistoryChangeTypeInsert);
    XCTAssertEqual([(NSPersistentHistoryChange *)[[second changes] firstObject] changeType],
                   NSPersistentHistoryChangeTypeUpdate);
    XCTAssertEqualObjects([[[second changes] firstObject] changedObjectID], [ada objectID]);

    /* The update records which properties changed. */
    NSSet *updated = [(NSPersistentHistoryChange *)[[second changes] firstObject] updatedProperties];
    XCTAssertEqualObjects([[updated anyObject] name], @"age");
}

- (void)testHistoryFetchAfterTokenReturnsOnlyWhatIsNew
{
    if (![self databaseAvailable] || ![self historySupported]) return;

    NSManagedObjectContext *context = [self newHistoryTrackingContext];
    NSError *error = nil;

    [[NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context]
        setValue:@"Ada" forKey:@"name"];
    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    /* The coordinator collects this from the store itself. */
    NSPersistentHistoryToken *token =
        [[context persistentStoreCoordinator] currentPersistentHistoryTokenFromStores:nil];

    XCTAssertNotNil(token, @"the store did not report a history position");

    [[NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context]
        setValue:@"Grace" forKey:@"name"];
    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    NSPersistentHistoryResult *result = (NSPersistentHistoryResult *)
        [context executeRequest:[NSPersistentHistoryChangeRequest fetchHistoryAfterToken:token]
                          error:&error];

    XCTAssertNotNil(result, @"history fetch failed: %@", error);

    NSArray *transactions = [result result];

    XCTAssertEqual([transactions count], (NSUInteger)1, @"only the save after the token should come back");
    XCTAssertEqual([[[transactions firstObject] changes] count], (NSUInteger)1);
}

- (void)testHistoryPurgeRemovesOlderTransactions
{
    if (![self databaseAvailable] || ![self historySupported]) return;

    NSManagedObjectContext *context = [self newHistoryTrackingContext];
    NSError *error = nil;

    [[NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context]
        setValue:@"Ada" forKey:@"name"];
    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    NSPersistentHistoryToken *token =
        [[context persistentStoreCoordinator] currentPersistentHistoryTokenFromStores:nil];

    [[NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context]
        setValue:@"Grace" forKey:@"name"];
    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    /* A purge is a different request from a fetch, which is the whole
       reason this feature needs FreeCoreData. */
    id purged = [context executeRequest:[NSPersistentHistoryChangeRequest deleteHistoryBeforeToken:token]
                                  error:&error];

    XCTAssertNotNil(purged, @"history purge failed: %@", error);

    NSPersistentHistoryResult *remaining = (NSPersistentHistoryResult *)
        [context executeRequest:[NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]]
                          error:&error];

    /* "Before" is exclusive: the anchor's own transaction survives. */
    XCTAssertEqual([[remaining result] count], (NSUInteger)2);

    NSPersistentHistoryToken *later =
        [[context persistentStoreCoordinator] currentPersistentHistoryTokenFromStores:nil];

    XCTAssertNotNil([context executeRequest:[NSPersistentHistoryChangeRequest deleteHistoryBeforeToken:later]
                                      error:&error]);

    remaining = (NSPersistentHistoryResult *)
        [context executeRequest:[NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]]
                          error:&error];

    XCTAssertEqual([[remaining result] count], (NSUInteger)1, @"only the last transaction should be left");
}

- (void)testHistoryRecordsBatchOperations
{
    if (![self databaseAvailable] || ![self historySupported]) return;

    NSManagedObjectContext *context = [self newHistoryTrackingContext];
    NSError *error = nil;

    NSBatchInsertRequest *insert =
        [[NSBatchInsertRequest alloc] initWithEntityName:@"Person"
                                                 objects:@[ @{ @"name" : @"Ada" }, @{ @"name" : @"Grace" } ]];

    XCTAssertNotNil([context executeRequest:insert error:&error], @"batch insert failed: %@", error);

    NSPersistentHistoryResult *result = (NSPersistentHistoryResult *)
        [context executeRequest:[NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]]
                          error:&error];

    XCTAssertNotNil(result, @"history fetch failed: %@", error);

    NSArray *transactions = [result result];

    XCTAssertEqual([transactions count], (NSUInteger)1, @"a batch insert is one transaction");
    XCTAssertEqual([[[transactions firstObject] changes] count], (NSUInteger)2);
}

- (void)testHistoryResultTypes
{
    if (![self databaseAvailable] || ![self historySupported]) return;

    NSManagedObjectContext *context = [self newHistoryTrackingContext];
    NSError *error = nil;

    NSManagedObject *ada = [NSEntityDescription insertNewObjectForEntityForName:@"Person"
                                                         inManagedObjectContext:context];
    [ada setValue:@"Ada" forKey:@"name"];
    XCTAssertTrue([context save:&error], @"save failed: %@", error);

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]];

    [request setResultType:NSPersistentHistoryResultTypeCount];
    XCTAssertEqualObjects([(NSPersistentHistoryResult *)[context executeRequest:request error:&error] result], @1);

    [request setResultType:NSPersistentHistoryResultTypeObjectIDs];
    NSArray *objectIDs = [(NSPersistentHistoryResult *)[context executeRequest:request error:&error] result];
    XCTAssertEqualObjects([objectIDs firstObject], [ada objectID]);

    [request setResultType:NSPersistentHistoryResultTypeChangesOnly];
    NSArray *changes = [(NSPersistentHistoryResult *)[context executeRequest:request error:&error] result];
    XCTAssertEqual([changes count], (NSUInteger)1);
    XCTAssertEqual([(NSPersistentHistoryChange *)[changes firstObject] changeType],
                   NSPersistentHistoryChangeTypeInsert);
}

- (void)testHistoryIsRefusedWhenTrackingIsOff
{
    if (![self databaseAvailable] || ![self historySupported]) return;

    /* self.context is the plain store from -setUp, with no tracking. */
    NSError *error = nil;
    id result = [self.context executeRequest:[NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]]
                                       error:&error];

    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

@end
