/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import "SBChartView.h"

static const CGFloat SBChartInset = 8.0;
static const CGFloat SBChartLabelWidth = 100.0;
static const CGFloat SBChartBarGap = 6.0;

@implementation SBChartView

- (void)setBars:(NSArray *)bars
{
    _bars = [bars copy];
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor controlBackgroundColor] set];
    NSRectFill([self bounds]);

    NSDictionary *labelAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0],
        NSForegroundColorAttributeName: [NSColor controlTextColor]};
    NSDictionary *detailAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0],
        NSForegroundColorAttributeName: [NSColor disabledControlTextColor]};

    if ([self.bars count] == 0) {
        [@"No data yet - add employees, or insert sample data."
            drawAtPoint:NSMakePoint(SBChartInset, SBChartInset)
         withAttributes:detailAttributes];
        return;
    }

    double largest = 1.0;
    for (NSDictionary *bar in self.bars)
        largest = MAX(largest, [bar[@"value"] doubleValue]);

    CGFloat rowHeight = MIN(24.0,
        (NSHeight([self bounds]) - 2.0 * SBChartInset) / [self.bars count]);
    CGFloat barRoom = NSWidth([self bounds]) - SBChartLabelWidth - 90.0 - 2.0 * SBChartInset;
    CGFloat y = SBChartInset;

    for (NSDictionary *bar in self.bars) {
        CGFloat width = MAX(2.0, barRoom * [bar[@"value"] doubleValue] / largest);
        NSRect barRect = NSMakeRect(SBChartInset + SBChartLabelWidth,
                                    y + 3.0, width, rowHeight - SBChartBarGap);

        [bar[@"label"] drawAtPoint:NSMakePoint(SBChartInset, y + 4.0)
                    withAttributes:labelAttributes];

        [[NSColor systemBlueColor] set];
        NSRectFill(barRect);

        NSString *caption = [NSString stringWithFormat:@"%.0f  (%@)",
            [bar[@"value"] doubleValue], bar[@"detail"] ?: @""];
        [caption drawAtPoint:NSMakePoint(NSMaxX(barRect) + 6.0, y + 4.0)
              withAttributes:detailAttributes];

        y += rowHeight;
    }
}

@end
