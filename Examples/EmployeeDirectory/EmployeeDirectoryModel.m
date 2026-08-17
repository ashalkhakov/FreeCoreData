/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "EmployeeDirectoryModel.h"

@implementation EDPerson

/* Transient attributes hold no value in the store; this one is computed
   from the two persisted name attributes. */
- (NSString *)fullName
{
    NSString *first = [self valueForKey:@"firstName"];
    NSString *last = [self valueForKey:@"lastName"];

    if (first == nil)
        return last;
    if (last == nil)
        return first;

    return [NSString stringWithFormat:@"%@ %@", first, last];
}

- (NSString *)shortDescription
{
    return [NSString stringWithFormat:@"%@ (%@)", [self fullName], [[self entity] name]];
}

@end

@implementation EDEmployee

/* Property level validation: mandatory-ness and the minimum value come from
   the model, this method adds a rule that can not be expressed there. */
- (BOOL)validateSalary:(id *)value error:(NSError **)error
{
    if (*value == nil)
        return YES;

    if ([*value integerValue] % 100 != 0) {
        if (error != NULL) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                @"salaries must be a multiple of 100", NSLocalizedDescriptionKey, nil];

            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                              code:NSManagedObjectValidationError
                              userInfo:userInfo];
        }
        return NO;
    }

    return YES;
}

@end

@implementation EDContractor
@end

@implementation EDDepartment
@end

@implementation EDProject
@end

static NSAttributeDescription *EDAttribute(NSString *name, NSAttributeType type, BOOL optional)
{
    NSAttributeDescription *result = [[[NSAttributeDescription alloc] init] autorelease];

    [result setName:name];
    [result setAttributeType:type];
    [result setOptional:optional];

    return result;
}

static NSRelationshipDescription *EDRelationship(NSString *name, BOOL toMany, BOOL optional)
{
    NSRelationshipDescription *result = [[[NSRelationshipDescription alloc] init] autorelease];

    [result setName:name];
    /* A to-one relationship is described by min and max count of one. */
    [result setMinCount:toMany ? 0 : 1];
    [result setMaxCount:toMany ? 0 : 1];
    [result setOptional:optional];
    [result setDeleteRule:NSNullifyDeleteRule];

    return result;
}

static NSEntityDescription *EDEntity(NSString *name, NSString *className, NSArray *properties)
{
    NSEntityDescription *result = [[[NSEntityDescription alloc] init] autorelease];

    [result setName:name];
    [result setManagedObjectClassName:className];
    [result setProperties:properties];

    return result;
}

NSManagedObjectModel *EmployeeDirectoryModel(void)
{
    /* Person, the abstract root entity of the inheritance hierarchy. */
    NSAttributeDescription *firstName = EDAttribute(@"firstName", NSStringAttributeType, NO);
    NSAttributeDescription *lastName = EDAttribute(@"lastName", NSStringAttributeType, NO);
    NSAttributeDescription *birthDate = EDAttribute(@"birthDate", NSDateAttributeType, YES);
    NSAttributeDescription *fullName = EDAttribute(@"fullName", NSStringAttributeType, YES);

    /* Transient attributes are computed, never persisted. */
    [fullName setTransient:YES];

    NSEntityDescription *personEntity = EDEntity(@"Person", @"EDPerson",
        [NSArray arrayWithObjects:firstName, lastName, birthDate, fullName, nil]);
    [personEntity setAbstract:YES];

    /* Employee, a concrete subentity of Person. */
    NSAttributeDescription *salary = EDAttribute(@"salary", NSInteger32AttributeType, NO);

    [salary setValidationPredicates:
        [NSArray arrayWithObject:[NSPredicate predicateWithFormat:@"SELF >= 0"]]
        withValidationWarnings:
        [NSArray arrayWithObject:@"salary must not be negative"]];

    NSRelationshipDescription *department = EDRelationship(@"department", NO, YES);
    NSRelationshipDescription *projects = EDRelationship(@"projects", YES, YES);

    NSEntityDescription *employeeEntity = EDEntity(@"Employee", @"EDEmployee",
        [NSArray arrayWithObjects:salary, department, projects, nil]);

    /* Contractor, a second concrete subentity of Person. */
    NSAttributeDescription *agency = EDAttribute(@"agency", NSStringAttributeType, YES);

    NSEntityDescription *contractorEntity = EDEntity(@"Contractor", @"EDContractor",
        [NSArray arrayWithObject:agency]);

    [personEntity setSubentities:
        [NSArray arrayWithObjects:employeeEntity, contractorEntity, nil]];

    /* Department, the to-one/to-many counterpart of Employee.department. */
    NSAttributeDescription *departmentName = EDAttribute(@"name", NSStringAttributeType, NO);
    NSRelationshipDescription *employees = EDRelationship(@"employees", YES, YES);

    NSEntityDescription *departmentEntity = EDEntity(@"Department", @"EDDepartment",
        [NSArray arrayWithObjects:departmentName, employees, nil]);

    [department setDestinationEntity:departmentEntity];
    [employees setDestinationEntity:employeeEntity];
    [department setInverseRelationship:employees];
    [employees setInverseRelationship:department];

    /* Project, in a many-to-many relationship with Employee. */
    NSAttributeDescription *projectName = EDAttribute(@"name", NSStringAttributeType, NO);
    NSRelationshipDescription *members = EDRelationship(@"members", YES, YES);

    NSEntityDescription *projectEntity = EDEntity(@"Project", @"EDProject",
        [NSArray arrayWithObjects:projectName, members, nil]);

    [projects setDestinationEntity:projectEntity];
    [members setDestinationEntity:employeeEntity];
    [projects setInverseRelationship:members];
    [members setInverseRelationship:projects];

    NSManagedObjectModel *model = [[[NSManagedObjectModel alloc] init] autorelease];

    [model setEntities:[NSArray arrayWithObjects:personEntity, employeeEntity,
        contractorEntity, departmentEntity, projectEntity, nil]];

    return model;
}
