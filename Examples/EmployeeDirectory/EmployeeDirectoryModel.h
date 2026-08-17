/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

/* The demo model, built in code so that the very same model is used by
   GNUstep and by Apple's CoreData (no compiled .momd needed):

     Person (abstract)                     <- inheritance
       firstName    string, mandatory
       lastName     string, mandatory
       birthDate    date, optional
       fullName     string, transient      <- transient property
     Employee : Person
       salary       integer, mandatory, validated by -validateSalary:error:
       department   to-one    -> Department (inverse: employees)
       projects     to-many  <-> Project.members (many-to-many)
     Contractor : Person
       agency       string, optional
     Department
       name         string, mandatory
       employees    to-many   -> Employee (inverse: department)
     Project
       name         string, mandatory
       members      to-many  <-> Employee.projects (many-to-many)
*/

@interface EDPerson : NSManagedObject
/* Transient, computed property.  It is declared in the model as a
   transient attribute so it is never written to the store. */
- (NSString *)fullName;
- (NSString *)shortDescription;
@end

@interface EDEmployee : EDPerson
- (BOOL)validateSalary:(id *)value error:(NSError **)error;
@end

@interface EDContractor : EDPerson
@end

@interface EDDepartment : NSManagedObject
@end

@interface EDProject : NSManagedObject
@end

NSManagedObjectModel *EmployeeDirectoryModel(void);
