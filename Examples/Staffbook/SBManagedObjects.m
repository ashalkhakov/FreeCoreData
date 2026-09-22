/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import "SBManagedObjects.h"

NSArray *SBDepartments(void)
{
    return @[@"Engineering", @"Design", @"Sales", @"Support", @"Operations"];
}

@implementation SBEmployee

@dynamic name;
@dynamic department;
@dynamic salary;
@dynamic hireDate;
@dynamic reviews;

- (NSNumber *)reviewCount
{
    return [NSNumber numberWithUnsignedInteger:[self.reviews count]];
}

@end

@implementation SBReview

@dynamic date;
@dynamic rating;
@dynamic summary;
@dynamic employee;

@end
