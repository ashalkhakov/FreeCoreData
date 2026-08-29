//
//  DMTabBar.h
//  DMTabBar - XCode like Segmented Control
//
//  Created by Daniele Margutti on 6/18/12.
//  Copyright (c) 2012 Daniele Margutti (http://www.danielemargutti.com - daniele.margutti@gmail.com). All rights reserved.
//  Licensed under MIT License
//

#import <Cocoa/Cocoa.h>
#import "DMTabBarItem.h"

@interface DMTabBar : NSView {
    
}

// set an NSArray of DMTabBarItem elements to populate the DMTabBar
@property (nonatomic,strong) NSArray*           tabBarItems;

// change selected item by passing a DMTabBarItem object (ignored if selectedTabBarItem is not contained inside tabBarItems)
@property (nonatomic,assign) DMTabBarItem*      selectedTabBarItem;

// change selected item by passing a new index { 0 < index < tabBarItems.count }
@property (nonatomic,assign) NSUInteger         selectedIndex;

@property (nonatomic,strong) NSColor *gradientColorStart;
@property (nonatomic,strong) NSColor *gradientColorEnd;
@property (nonatomic,strong) NSColor *borderColor;

// Traditional target-action properties
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;

// Replace the block method with a standard action setter (or keep it if you want both)
- (void)setTarget:(id)target action:(SEL)action;

@property (nonatomic, assign) BOOL centerTabs; // should the tabs be drawn centered in the view or offset?
@property (nonatomic, assign) CGFloat leftOffset; // offset value from left if tabs are not centered in view (default 10)

@end
