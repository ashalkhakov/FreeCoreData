/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import <AppKit/AppKit.h>

/* A very simple horizontal bar chart: one bar per dictionary of
 * @{@"label", @"value" (NSNumber), @"detail" (shown after the value)}.
 * Bars scale to the largest value; an empty array draws a hint instead. */
@interface SBChartView : NSView

@property (nonatomic, copy) NSArray *bars;

@end
