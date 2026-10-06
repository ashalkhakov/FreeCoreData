/* ModelBuilder — what the model window and the mapping window share: the
   repairs and conveniences their xibs need on both toolkits.  Defined in
   MBWindowController.m.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

/* Segments whose image names resolve to nothing get a text label. */
void MBRepairSegmentImages(NSView *view);

/* Typing undo for every editable text cell under a view. */
void MBEnableTypingUndoIn(NSView *view);

/* The first split view among a view's immediate subviews. */
NSSplitView *MBFirstSplitViewIn(NSView *view);

/* The first of these names that resolves to an image. */
NSImage *MBFirstImageNamed(NSArray *names);

/* A round badge with a letter or two, for an inspector tab or a row. */
NSImage *MBBadgeImage(NSString *letters, CGFloat red, CGFloat green, CGFloat blue);

/* Lays a split view's panes out as its delegate's
   -splitView:shouldAdjustSizeOfSubview: says: the panes that should not
   adjust keep their span, and the rest share what is left.  GNUstep's own
   layout never asks about the last pane. */
void MBDistributeSplitSubviews(NSSplitView *splitView, id<NSSplitViewDelegate> delegate);
