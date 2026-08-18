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

/* The model is designed in EmployeeDirectory.xcdatamodeld (edited with
   Xcode's model designer on a Mac) and shipped compiled as the
   EmployeeDirectory.momd resource, which both Apple's CoreData and the
   GNUstep port load at runtime. */
NSManagedObjectModel *EmployeeDirectoryModel(void)
{
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"EmployeeDirectory"
                                         withExtension:@"momd"];

    if (url == nil) {
        NSLog(@"EmployeeDirectory.momd not found in the application bundle");
        return nil;
    }

    NSManagedObjectModel *model =
        [[[NSManagedObjectModel alloc] initWithContentsOfURL:url] autorelease];

    if (model == nil)
        NSLog(@"could not load the managed object model at %@", url);

    return model;
}
