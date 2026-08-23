/* ModelBuilder document — a .xcdatamodeld wrapper (current version).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import "MBModel.h"

@interface MBDocument : NSDocument
@property (nonatomic, strong) MBModel *model;
- (void)noteModelChanged;
@end
