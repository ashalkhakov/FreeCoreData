/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSManagedObjectContextTests - basic context tests. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

@interface NSManagedObjectContextTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSManagedObjectContext *ctx;

@end

@implementation NSManagedObjectContextTests

- (void)setUp
{
    self.model = [[NSManagedObjectModel alloc] init];
    self.psc   = [[NSPersistentStoreCoordinator alloc]
                     initWithManagedObjectModel:self.model];
    NSError *err = nil;
    [self.psc addPersistentStoreWithType:NSInMemoryStoreType
                           configuration:nil URL:nil options:nil error:&err];
    self.ctx = [[NSManagedObjectContext alloc] init];
    [self.ctx setPersistentStoreCoordinator:self.psc];
}

- (void)tearDown
{
    self.ctx   = nil;
    self.psc   = nil;
    self.model = nil;
}

- (void)testContextCreation
{
    XCTAssertNotNil(self.ctx);
    XCTAssertNotNil([self.ctx persistentStoreCoordinator]);
    XCTAssertFalse([self.ctx hasChanges]);
}

- (void)testRegisteredObjects
{
    XCTAssertNotNil([self.ctx registeredObjects]);
    XCTAssertEqual([[self.ctx registeredObjects] count], (NSUInteger)0);
}

- (void)testSaveWithNoChanges
{
    NSError *err = nil;
    BOOL ok = [self.ctx save:&err];
    XCTAssertTrue(ok);
    XCTAssertNil(err);
}

/* A context with a one entity model, used by the change notification
   tests below. */
- (NSManagedObjectContext *)contextWithNoteEntity
{
    NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
    [text setName:@"text"];
    [text setAttributeType:NSStringAttributeType];
    [text setOptional:YES];

    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    [note setName:@"Note"];
    [note setManagedObjectClassName:@"NSManagedObject"];
    [note setProperties:[NSArray arrayWithObject:text]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:note]];

    NSPersistentStoreCoordinator *psc =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *err = nil;
    XCTAssertNotNil([psc addPersistentStoreWithType:NSInMemoryStoreType
                         configuration:nil URL:nil options:nil error:&err],
        @"unable to add the store: %@", err);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];

    /* The receiver keeps the whole stack alive for the test. */
    self.model = model;
    self.psc = psc;

    return ctx;
}

- (void)testProcessPendingChangesPostsObjectsDidChangeNotification
{
    NSManagedObjectContext *ctx = [self contextWithNoteEntity];
    __block NSDictionary *userInfo = nil;
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSManagedObjectContextObjectsDidChangeNotification
        object:ctx queue:nil usingBlock:^(NSNotification *note) {
            userInfo = [note userInfo];
        }];

    NSManagedObject *inserted =
        [NSEntityDescription insertNewObjectForEntityForName:@"Note"
                             inManagedObjectContext:ctx];
    [inserted setValue:@"hello" forKey:@"text"];

    [ctx processPendingChanges];

    XCTAssertNotNil(userInfo);
    XCTAssertTrue([[userInfo objectForKey:NSInsertedObjectsKey] containsObject:inserted]);

    /* Changes are reported only once. */
    userInfo = nil;
    [ctx processPendingChanges];
    XCTAssertNil(userInfo);

    /* Updating a registered object reports it as updated. */
    [inserted setValue:@"goodbye" forKey:@"text"];
    [ctx processPendingChanges];
    XCTAssertNotNil(userInfo);
    XCTAssertTrue([[userInfo objectForKey:NSUpdatedObjectsKey] containsObject:inserted]);

    /* Deleting it reports it as deleted. */
    userInfo = nil;
    [ctx deleteObject:inserted];
    [ctx processPendingChanges];
    XCTAssertNotNil(userInfo);
    XCTAssertTrue([[userInfo objectForKey:NSDeletedObjectsKey] containsObject:inserted]);

    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

/* Category <-> products (one-to-many), person <-> partner (one-to-one). */
static NSManagedObjectContext *InverseTestContext(void)
{
    NSEntityDescription *category = [[NSEntityDescription alloc] init];
    [category setName:@"InverseCategory"];
    [category setManagedObjectClassName:@"NSManagedObject"];
    NSEntityDescription *product = [[NSEntityDescription alloc] init];
    [product setName:@"InverseProduct"];
    [product setManagedObjectClassName:@"NSManagedObject"];
    NSEntityDescription *person = [[NSEntityDescription alloc] init];
    [person setName:@"InversePerson"];
    [person setManagedObjectClassName:@"NSManagedObject"];
    NSMutableArray *names = [NSMutableArray array];
    for (int i = 0; i < 3; i++) {
        NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
        [name setName:@"name"];
        [name setAttributeType:NSStringAttributeType];
        [name setOptional:YES];
        [names addObject:name];
    }
    NSRelationshipDescription *products = [[NSRelationshipDescription alloc] init];
    [products setName:@"products"];
    [products setDestinationEntity:product];
    [products setMaxCount:0];
    [products setOptional:YES];
    NSRelationshipDescription *owner = [[NSRelationshipDescription alloc] init];
    [owner setName:@"category"];
    [owner setDestinationEntity:category];
    [owner setMaxCount:1];
    [owner setOptional:YES];
    [products setInverseRelationship:owner];
    [owner setInverseRelationship:products];
    NSRelationshipDescription *partner = [[NSRelationshipDescription alloc] init];
    [partner setName:@"partner"];
    [partner setDestinationEntity:person];
    [partner setMaxCount:1];
    [partner setOptional:YES];
    [partner setInverseRelationship:partner];
    [category setProperties:@[ names[0], products ]];
    [product setProperties:@[ names[1], owner ]];
    [person setProperties:@[ names[2], partner ]];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:@[ category, product, person ]];
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL];
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [context setPersistentStoreCoordinator:psc];
    return context;
}

static NSManagedObject *InverseTestObject(NSManagedObjectContext *context, NSString *entity, NSString *name)
{
    NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:context];
    [object setValue:name forKey:@"name"];
    return object;
}

static NSArray *InverseTestNames(id objects)
{
    return [[[objects valueForKey:@"name"] allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

- (void)testAnObjectAddedToAToManyLeavesItsOldOwner
{
    /* Apple: a product added to a category's products, by setting the set
       or through -mutableSetValueForKey:, is no longer among the products
       of the category it had, before a save and after it. */
    for (NSString *how in @[ @"set", @"mutable" ]) {
        NSManagedObjectContext *context = InverseTestContext();
        NSManagedObject *drinks = InverseTestObject(context, @"InverseCategory", @"drinks");
        NSManagedObject *sauces = InverseTestObject(context, @"InverseCategory", @"sauces");
        NSManagedObject *chai = InverseTestObject(context, @"InverseProduct", @"chai");
        NSManagedObject *syrup = InverseTestObject(context, @"InverseProduct", @"syrup");
        [chai setValue:drinks forKey:@"category"];
        [syrup setValue:sauces forKey:@"category"];
        NSError *error = nil;
        XCTAssertTrue([context save:&error], @"%@", error);

        if ([how isEqualToString:@"set"])
            [drinks setValue:[NSSet setWithObjects:chai, syrup, nil] forKey:@"products"];
        else
            [[drinks mutableSetValueForKey:@"products"] addObject:syrup];
        XCTAssertEqualObjects([syrup valueForKey:@"category"], drinks, @"%@", how);
        XCTAssertEqualObjects(InverseTestNames([sauces valueForKey:@"products"]), @[], @"%@", how);
        XCTAssertTrue([[context updatedObjects] containsObject:sauces], @"%@: the old owner changed", how);

        XCTAssertTrue([context save:&error], @"%@", error);
        [context reset];
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"InverseCategory"];
        [request setPredicate:[NSPredicate predicateWithFormat:@"name == 'sauces'"]];
        NSManagedObject *saved = [[context executeFetchRequest:request error:NULL] firstObject];
        XCTAssertEqualObjects(InverseTestNames([saved valueForKey:@"products"]), @[], @"%@: after a save", how);
    }
}

- (void)testAOneToOnePartnersOldPartnerHasNone
{
    NSManagedObjectContext *context = InverseTestContext();
    NSManagedObject *ann = InverseTestObject(context, @"InversePerson", @"ann");
    NSManagedObject *bob = InverseTestObject(context, @"InversePerson", @"bob");
    NSManagedObject *cy = InverseTestObject(context, @"InversePerson", @"cy");
    [ann setValue:bob forKey:@"partner"];
    [cy setValue:bob forKey:@"partner"];
    XCTAssertEqualObjects([bob valueForKey:@"partner"], cy);
    XCTAssertNil([ann valueForKey:@"partner"]);
}

@end
