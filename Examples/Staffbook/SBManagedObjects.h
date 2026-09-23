/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

/* Classes for Staffbook.xcdatamodeld.  Written by hand rather than
 * generated: codegen is off for both entities so that one set of files
 * serves Apple's CoreData and FreeCoreData alike.  Numeric attributes are
 * NSNumber (usesScalarValueType = NO) for the same reason. */

@class SBReview;

@interface SBEmployee : NSManagedObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *department;
@property (nonatomic, strong) NSNumber *salary;
@property (nonatomic, strong) NSDate *hireDate;
@property (nonatomic, strong) NSSet *reviews;

/* For the roster's Reviews column: a column binding applies its key
 * path per row, so it cannot carry a collection operator like
 * reviews.@count - this plain accessor stands in. */
- (NSNumber *)reviewCount;

@end

@interface SBReview : NSManagedObject

@property (nonatomic, strong) NSDate *date;
@property (nonatomic, strong) NSNumber *rating;   /* 1..5 */
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, strong) SBEmployee *employee;

@end

/* The one list every department popup and chart bucket works from. */
NSArray *SBDepartments(void);
