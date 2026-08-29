//
//  DMTabBar.m
//  DMTabBar - XCode like Segmented Control
//
//  Created by Daniele Margutti on 6/18/12.
//  Copyright (c) 2012 Daniele Margutti (http://www.danielemargutti.com - daniele.margutti@gmail.com). All rights reserved.
//  Licensed under MIT License
//

#import "DMTabBar.h"

// Gradient applied to the background of the tabBar
// (Colors and gradient from Stephan Michels Softwareentwicklung und Beratung - SMTabBar)
#define kDMTabBarGradientColor_Start                        [NSColor colorWithCalibratedRed:0.851f green:0.851f blue:0.851f alpha:1.0f]
#define kDMTabBarGradientColor_End                          [NSColor colorWithCalibratedRed:0.700f green:0.700f blue:0.700f alpha:1.0f]
#define KDMTabBarGradient                                   

// Border color of the bar
#define kDMTabBarBorderColor                                [NSColor colorWithDeviceWhite:0.2 alpha:1.0f]

// Default tabBar item width
#define kDMTabBarItemWidth                                  32.0f

@interface DMTabBar() {
    NSArray*                    tabBarItems;
    DMTabBarItem*               selectedTabBarItem_;
}

// Relayout button items
- (void) layoutSubviews;
// Remove all loaded button items
- (void) removeAllTabBarItems;
// Handle click on a single item (change selection, post event to the handler)
- (void) selectTabBarItem:(id)sender;
- (void) setDefaults;

@end

@implementation DMTabBar

@synthesize selectedIndex,selectedTabBarItem;
@synthesize tabBarItems;

- (id)initWithFrame:(NSRect)frameRect
{
    if (self = [super initWithFrame:frameRect])
    {
        [self setDefaults];
    }
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder])
    {
        [self setDefaults];
    }
    return self;
}

- (void)setDefaults
{
    /* Follow the theme: derive the bar gradient from the window
       background (the original constants assumed light Aqua).
       NSGradient needs an RGB-convertible color, so resolve the
       dynamic catalog color first and fall back to the originals. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSColor *base = [[NSColor windowBackgroundColor]
        colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
#pragma clang diagnostic pop
    if (base) {
        self.gradientColorStart = [base highlightWithLevel:0.05] ?: base;
        self.gradientColorEnd = [base shadowWithLevel:0.08] ?: base;
        self.borderColor = [NSColor gridColor];
    } else {
        self.gradientColorStart = kDMTabBarGradientColor_Start;
        self.gradientColorEnd = kDMTabBarGradientColor_End;
        self.borderColor = kDMTabBarBorderColor;
    }
	self.centerTabs = YES;
	self.leftOffset = 10.0;
}

- (void)drawRect:(NSRect)dirtyRect {
    
    // Draw bar gradient if its color is set
    if (_gradientColorStart && _gradientColorEnd)
    {
        [[[NSGradient alloc] initWithStartingColor:self.gradientColorStart endingColor:self.gradientColorEnd] drawInRect:self.bounds angle:90.0];
    }
    
    // Draw drak gray bottom border
    if (_borderColor)
    {
        [_borderColor setStroke];
        [NSBezierPath setDefaultLineWidth:0.0f];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(self.bounds), NSMaxY(self.bounds))
                                  toPoint:NSMakePoint(NSMaxX(self.bounds), NSMaxY(self.bounds))];
    }
}

- (BOOL) isFlipped {
    return YES;
}

- (void)dealloc {
    [self removeAllTabBarItems];
}

- (void) removeAllTabBarItems {
    for (DMTabBarItem *tabBarItem in self.tabBarItems) {
        [tabBarItem.tabBarItemButton removeFromSuperview];
    }
    tabBarItems = nil;
}

- (void)setTarget:(id)target action:(SEL)action {
    _target = target;
    _action = action;
}

- (void)selectTabBarItem:(id)sender {    
    NSUInteger itemIndex = NSNotFound;
    NSUInteger idx = 0;
    for (DMTabBarItem *tabBarItem in self.tabBarItems) {
        if (sender == tabBarItem.tabBarItemButton) {
            itemIndex = idx;
            break;
        }
        idx++;
    }
    if (itemIndex == NSNotFound) return;

    DMTabBarItem *tabBarItem = [self.tabBarItems objectAtIndex:itemIndex];
    
    self.selectedTabBarItem = tabBarItem;
    self.selectedIndex = itemIndex;
    
    // Fire the traditional Target-Action
    if (self.target && self.action && [self.target respondsToSelector:self.action]) {
        // Supposing your action signature is: - (IBAction)tabBarSelectionChanged:(id)sender
        // 'self' is passed as the sender, so the target can query `self.selectedTabBarItem` or `self.selectedItemIndex`.
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.target performSelector:self.action withObject:self];
        #pragma clang diagnostic pop
    }
}

#pragma mark - Layout Subviews

- (void) resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutSubviews];
}

- (void) layoutSubviews {
    NSUInteger buttonsNumber = [self.tabBarItems count];
    CGFloat totalWidth = (buttonsNumber*kDMTabBarItemWidth);
	CGFloat offset_x = (self.centerTabs) ? floorf((NSWidth(self.bounds)-totalWidth)/2.0f) : self.leftOffset;
    for (DMTabBarItem *tabBarItem in self.tabBarItems) {
        tabBarItem.tabBarItemButton.frame = NSMakeRect(offset_x, NSMinY(self.bounds), kDMTabBarItemWidth, NSHeight(self.bounds));
        offset_x += kDMTabBarItemWidth;
    }
}

- (void) setTabBarItems:(NSArray *)newTabBarItems {
    if (newTabBarItems != tabBarItems) {
        [self removeAllTabBarItems];
        tabBarItems = newTabBarItems;
        
        NSUInteger selectedItemIndex = [self.tabBarItems indexOfObject:self.selectedTabBarItem];
        NSUInteger itemIndex = 0;
        for (DMTabBarItem *tabBarItem in self.tabBarItems) {
            NSButton *itemButton = tabBarItem.tabBarItemButton;
            itemButton.frame = NSMakeRect(0.0f, 0.0f, kDMTabBarItemWidth, NSHeight(self.bounds));
            itemButton.state = (itemIndex == selectedItemIndex ? NSOnState : NSOffState);
            itemButton.action = @selector(selectTabBarItem:);
            itemButton.target = self;
            [self addSubview:itemButton];
        }
        
        [self layoutSubviews];
        
        if (![self.tabBarItems containsObject:self.selectedTabBarItem])
            self.selectedTabBarItem = ([self.tabBarItems count] > 0 ? [self.tabBarItems objectAtIndex:0] : nil);
    }
}

- (DMTabBarItem *) selectedTabBarItem {
    return selectedTabBarItem_;
}

- (void) setSelectedTabBarItem:(DMTabBarItem *)newSelectedTabBarItem {
    if ([self.tabBarItems containsObject:newSelectedTabBarItem] == NO) return;
    NSUInteger selectedItemIndex = [self.tabBarItems indexOfObject:newSelectedTabBarItem];
    selectedTabBarItem_ = newSelectedTabBarItem;
    
    NSUInteger buttonIndex = 0;
    for (DMTabBarItem *tabBarItem in self.tabBarItems) {
        tabBarItem.state = (buttonIndex == selectedItemIndex ? NSOnState : NSOffState);
        ++buttonIndex;
    }
}

- (NSUInteger) selectedIndex {
    return [self.tabBarItems indexOfObject:self.selectedTabBarItem];
}

- (void) setSelectedIndex:(NSUInteger)newSelectedIndex {
    if (newSelectedIndex != self.selectedIndex && newSelectedIndex < [self.tabBarItems count]) {
        self.selectedTabBarItem = [self.tabBarItems objectAtIndex:newSelectedIndex];
    }
}


@end
