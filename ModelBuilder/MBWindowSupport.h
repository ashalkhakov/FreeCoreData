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

/* A part's view put in its pane, filling it. */
void MBPlacePart(NSViewController *part, NSView *host);

@class MBModelEditor;

/* Editor > Validate: momc's checks on the model, and what they found, in an
   alert. */
void MBValidateModel(MBModelEditor *modelEditor);

/* Xcode's Editor > Create NSManagedObject Subclass..., for the selected
   entity - or, with none selected, for every entity marked Class
   Definition / Category/Extension (falling back to every entity with a
   custom class when none is marked): a folder asked for, the files
   written there, and what was written in an alert. */
void MBCreateManagedObjectSubclasses(MBModelEditor *modelEditor);

/* An alert for an edit the model refused. */
void MBPresentModelError(NSError *error, NSString *title);
