/* ModelBuilder — what the model window's parts and the mapping window
   share: the conveniences their xibs need on both toolkits, the badges,
   the alert for a model error.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

/* The first split view among a view's immediate subviews. */
NSSplitView *MBFirstSplitViewIn(NSView *view);

/* The first of these names that resolves to an image. */
NSImage *MBFirstImageNamed(NSArray *names);

/* A round badge with a letter or two, for an inspector tab or a row. */
NSImage *MBBadgeImage(NSString *letters, CGFloat red, CGFloat green, CGFloat blue);

/* The badges of Xcode's model editor: an attribute's type letters, an
   entity, relationship, fetch request, configuration. */
NSImage *MBAttributeBadge(NSString *letters);
NSImage *MBEntityBadge(void);
NSImage *MBRelationshipBadge(void);
NSImage *MBFetchBadge(void);
NSImage *MBConfigurationBadge(void);
NSString *MBAttributeBadgeLetters(NSAttributeDescription *attribute);

/* An alert for an edit the model refused. */
void MBPresentModelError(NSError *error, NSString *title);
