/*
 * This file is part of Bulletin, the FreeCoreData persistent-history
 * example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

/* The one entity of Bulletin.xcdatamodeld.  Written by hand rather than
 * generated so one set of files serves Apple's CoreData and FreeCoreData
 * alike (codegen is off in the model).
 *
 * "text" is marked Preserve After Deletion in the model
 * (preserveValueOnDeletion), so when a post is deleted, the history
 * change for the deletion carries its last text in the tombstone - the
 * history window shows it. */
@interface BLPost : NSManagedObject

@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, strong) NSDate *createdAt;

@end
