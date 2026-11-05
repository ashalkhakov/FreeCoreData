/* ModelBuilder — what the model window and the mapping window share: the
   conveniences their xibs need on both toolkits.  Defined in
   MBWindowController.m.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

/* The first split view among a view's immediate subviews. */
NSSplitView *MBFirstSplitViewIn(NSView *view);

/* The first of these names that resolves to an image. */
NSImage *MBFirstImageNamed(NSArray *names);

/* A round badge with a letter or two, for an inspector tab or a row. */
NSImage *MBBadgeImage(NSString *letters, CGFloat red, CGFloat green, CGFloat blue);
