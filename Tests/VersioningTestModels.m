/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* VersioningTestModels - two versions of an Employee/Department model
   shared by the versioning, mapping model, and store migration tests. */

#import "VersioningTestModels.h"

NSManagedObjectModel *VersioningTestModelV1(void)
{
    return XMLStoreTestModel();
}

/* Version 2 model: adds Employee.title, drops Employee.hireDate. */
NSManagedObjectModel *VersioningTestModelV2(void)
{
    NSAttributeDescription *employeeName = [[NSAttributeDescription alloc] init];
    [employeeName setName:@"name"];
    [employeeName setAttributeType:NSStringAttributeType];
    [employeeName setOptional:YES];

    NSAttributeDescription *salary = [[NSAttributeDescription alloc] init];
    [salary setName:@"salary"];
    [salary setAttributeType:NSInteger32AttributeType];
    [salary setOptional:YES];

    NSAttributeDescription *title = [[NSAttributeDescription alloc] init];
    [title setName:@"title"];
    [title setAttributeType:NSStringAttributeType];
    [title setOptional:YES];

    NSAttributeDescription *departmentName = [[NSAttributeDescription alloc] init];
    [departmentName setName:@"name"];
    [departmentName setAttributeType:NSStringAttributeType];
    [departmentName setOptional:YES];

    NSRelationshipDescription *department = [[NSRelationshipDescription alloc] init];
    [department setName:@"department"];
    [department setMinCount:1];
    [department setMaxCount:1];
    [department setOptional:YES];

    NSRelationshipDescription *employees = [[NSRelationshipDescription alloc] init];
    [employees setName:@"employees"];
    [employees setMinCount:0];
    [employees setMaxCount:0];
    [employees setOptional:YES];

    NSEntityDescription *employeeEntity = [[NSEntityDescription alloc] init];
    [employeeEntity setName:@"Employee"];
    [employeeEntity setManagedObjectClassName:@"NSManagedObject"];
    [employeeEntity setProperties:
        [NSArray arrayWithObjects:employeeName, salary, title, department, nil]];

    NSEntityDescription *departmentEntity = [[NSEntityDescription alloc] init];
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
