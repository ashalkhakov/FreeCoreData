/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSManagedObjectValidationTests - object validation tests, mirroring
   Apple's "Object Validation" Core Data programming guide chapter. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>

/* Employee subclass with a custom -validate<Key>:error: method, as
   described in Apple's object validation documentation. */
@interface ValidationEmployee : NSManagedObject
@end

@implementation ValidationEmployee

- (BOOL)validateSalary:(id *)value error:(NSError **)error
{
    if (*value != nil && [*value intValue] > 1000000) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"ValidationEmployeeDomain"
                                         code:4242
                                     userInfo:nil];
        }
        return NO;
    }
    return YES;
}

@end

/* Model:
   Employee: name (string, required, length >= 2),
             salary (int32, optional, must be >= 0),
             department (to-one, optional)
   Department: name (string, optional),
               employees (to-many, max 2, delete rule Deny) */
static NSManagedObjectModel *ValidationTestModel(void)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];
    [name setOptional:NO];
    [name setValidationPredicates:
              [NSArray arrayWithObject:
                  [NSPredicate predicateWithFormat:@"length >= 2"]]
        withValidationWarnings:
              [NSArray arrayWithObject:@"Name is too short."]];

    NSAttributeDescription *salary = [[NSAttributeDescription alloc] init];
    [salary setName:@"salary"];
    [salary setAttributeType:NSInteger32AttributeType];
    [salary setOptional:YES];
    [salary setValidationPredicates:
                [NSArray arrayWithObject:
                    [NSPredicate predicateWithFormat:@"SELF >= 0"]]
        withValidationWarnings:
                [NSArray arrayWithObject:@"Salary may not be negative."]];

    NSAttributeDescription *departmentName =
        [[NSAttributeDescription alloc] init];
    [departmentName setName:@"name"];
    [departmentName setAttributeType:NSStringAttributeType];
    [departmentName setOptional:YES];

    NSRelationshipDescription *department =
        [[NSRelationshipDescription alloc] init];
    [department setName:@"department"];
    [department setMinCount:1];
    [department setMaxCount:1];
    [department setOptional:YES];

    NSRelationshipDescription *employees =
        [[NSRelationshipDescription alloc] init];
    [employees setName:@"employees"];
    [employees setMinCount:0];
    [employees setMaxCount:2];
    [employees setOptional:YES];
    [employees setDeleteRule:NSDenyDeleteRule];

    NSEntityDescription *employeeEntity = [[NSEntityDescription alloc] init];
    [employeeEntity setName:@"Employee"];
    [employeeEntity setManagedObjectClassName:@"ValidationEmployee"];
    [employeeEntity setProperties:
        [NSArray arrayWithObjects:name, salary, department, nil]];

    NSEntityDescription *departmentEntity =
        [[NSEntityDescription alloc] init];
    [departmentEntity setName:@"Department"];
    [departmentEntity setManagedObjectClassName:@"NSManagedObject"];
    [departmentEntity setProperties:
        [NSArray arrayWithObjects:departmentName, employees, nil]];

    [department setDestinationEntity:departmentEntity];
    [employees setDestinationEntity:employeeEntity];
    [department setInverseRelationship:employees];
    [employees setInverseRelationship:department];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:
        [NSArray arrayWithObjects:employeeEntity, departmentEntity, nil]];
    return model;
}

@interface NSManagedObjectValidationTests : XCTestCase

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *psc;
@property (nonatomic, strong) NSManagedObjectContext *ctx;

@end

@implementation NSManagedObjectValidationTests

- (void)setUp
{
    self.model = ValidationTestModel();
    self.psc = [[NSPersistentStoreCoordinator alloc]
                   initWithManagedObjectModel:self.model];
    NSError *error = nil;
    [self.psc addPersistentStoreWithType:NSInMemoryStoreType
                           configuration:nil URL:nil options:nil
                                   error:&error];
    self.ctx = [[NSManagedObjectContext alloc] init];
    [self.ctx setPersistentStoreCoordinator:self.psc];
}

- (void)tearDown
{
    self.ctx = nil;
    self.psc = nil;
    self.model = nil;
}

- (NSManagedObject *)insertEmployeeNamed:(NSString *)name
{
    NSManagedObject *employee =
        [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                      inManagedObjectContext:self.ctx];
    if (name != nil)
        [employee setValue:name forKey:@"name"];
    return employee;
}

/* -- property-level validation ------------------------------------------ */

- (void)testMissingMandatoryPropertyFailsValidateForInsert
{
    NSManagedObject *employee = [self insertEmployeeNamed:nil];

    NSError *error = nil;
    XCTAssertFalse([employee validateForInsert:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([error domain], NSCocoaErrorDomain);
    XCTAssertEqual([error code],
                   (NSInteger)NSValidationMissingMandatoryPropertyError);
    XCTAssertEqualObjects(
        [[error userInfo] objectForKey:NSValidationKeyErrorKey], @"name");
    XCTAssertEqual([[error userInfo] objectForKey:NSValidationObjectErrorKey],
                   employee);
}

- (void)testValidationPredicateFailureReportsPredicateAndValue
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"A"];

    NSError *error = nil;
    XCTAssertFalse([employee validateForInsert:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual([error code], (NSInteger)NSManagedObjectValidationError);
    XCTAssertEqualObjects(
        [[error userInfo] objectForKey:NSValidationKeyErrorKey], @"name");
    XCTAssertEqualObjects(
        [[error userInfo] objectForKey:NSValidationValueErrorKey], @"A");
    XCTAssertNotNil(
        [[error userInfo] objectForKey:NSValidationPredicateErrorKey]);
    XCTAssertEqualObjects([error localizedDescription], @"Name is too short.");
}

- (void)testValidateValueForKeyDirectly
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];

    id value = [NSNumber numberWithInt:-5];
    NSError *error = nil;
    XCTAssertFalse([employee validateValue:&value
                                    forKey:@"salary" error:&error]);
    XCTAssertEqual([error code], (NSInteger)NSManagedObjectValidationError);

    value = [NSNumber numberWithInt:50];
    error = nil;
    XCTAssertTrue([employee validateValue:&value
                                   forKey:@"salary" error:&error]);
    XCTAssertNil(error);
}

- (void)testMultipleValidationErrorsAreCombined
{
    NSManagedObject *employee = [self insertEmployeeNamed:nil];
    [employee setValue:[NSNumber numberWithInt:-1] forKey:@"salary"];

    NSError *error = nil;
    XCTAssertFalse([employee validateForInsert:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual([error code], (NSInteger)NSValidationMultipleErrorsError);

    NSArray *detailed = [[error userInfo] objectForKey:NSDetailedErrorsKey];
    XCTAssertEqual([detailed count], (NSUInteger)2);
}

- (void)testCustomValidationMethodIsInvoked
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [employee setValue:[NSNumber numberWithInt:2000000] forKey:@"salary"];

    NSError *error = nil;
    XCTAssertFalse([employee validateForInsert:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqualObjects([error domain], @"ValidationEmployeeDomain");
    XCTAssertEqual([error code], (NSInteger)4242);
}

- (void)testValidateForUpdateChecksProperties
{
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [employee setValue:nil forKey:@"name"];
    error = nil;
    XCTAssertFalse([employee validateForUpdate:&error]);
    XCTAssertEqual([error code],
                   (NSInteger)NSValidationMissingMandatoryPropertyError);
}

/* -- relationship count validation -------------------------------------- */

- (void)testRelationshipExceedingMaximumCountFailsValidation
{
    NSManagedObject *department =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:self.ctx];
    NSMutableSet *employees = [NSMutableSet set];
    [employees addObject:[self insertEmployeeNamed:@"Alice"]];
    [employees addObject:[self insertEmployeeNamed:@"Bob"]];
    [employees addObject:[self insertEmployeeNamed:@"Carol"]];
    [department setValue:employees forKey:@"employees"];

    NSError *error = nil;
    XCTAssertFalse([department validateForInsert:&error]);
    XCTAssertEqual([error code],
                   (NSInteger)NSValidationRelationshipExceedsMaximumCountError);
    XCTAssertEqualObjects(
        [[error userInfo] objectForKey:NSValidationKeyErrorKey], @"employees");
}

/* -- delete validation --------------------------------------------------- */

- (void)testValidateForDeleteHonorsDenyDeleteRule
{
    NSManagedObject *department =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:self.ctx];
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [employee setValue:department forKey:@"department"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [self.ctx deleteObject:department];
    error = nil;
    XCTAssertFalse([department validateForDelete:&error]);
    XCTAssertEqual([error code],
                   (NSInteger)NSValidationRelationshipDeniedDeleteError);

    /* Deleting the related employee as well lifts the denial. */
    [self.ctx deleteObject:employee];
    error = nil;
    XCTAssertTrue([department validateForDelete:&error]);
    XCTAssertNil(error);
}

/* -- validation during -save: -------------------------------------------- */

- (void)testSaveFailsAndReportsValidationError
{
    [self insertEmployeeNamed:nil];

    NSError *error = nil;
    XCTAssertFalse([self.ctx save:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual([error code],
                   (NSInteger)NSValidationMissingMandatoryPropertyError);
}

- (void)testSaveWithDeniedDeleteFails
{
    NSManagedObject *department =
        [NSEntityDescription insertNewObjectForEntityForName:@"Department"
                                      inManagedObjectContext:self.ctx];
    NSManagedObject *employee = [self insertEmployeeNamed:@"Alice"];
    [employee setValue:department forKey:@"department"];

    NSError *error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);

    [self.ctx deleteObject:department];
    error = nil;
    XCTAssertFalse([self.ctx save:&error]);
    XCTAssertEqual([error code],
                   (NSInteger)NSValidationRelationshipDeniedDeleteError);
}

- (void)testSaveSucceedsAfterFixingValidationError
{
    NSManagedObject *employee = [self insertEmployeeNamed:nil];

    NSError *error = nil;
    XCTAssertFalse([self.ctx save:&error]);

    [employee setValue:@"Alice" forKey:@"name"];
    error = nil;
    XCTAssertTrue([self.ctx save:&error], @"save failed: %@", error);
    XCTAssertNil(error);
}

@end
