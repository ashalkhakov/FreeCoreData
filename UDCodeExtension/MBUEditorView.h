/* UDCode's Core Data extension — an editor tab's view (MBUModelEditor.xib,
   MBUMappingEditor.xib): its controller after it in the responder chain,
   wherever UDCode puts it, so the Editor menu's items and Undo reach the
   tab.  AppKit puts a view controller there by itself (since 10.10);
   gnustep-gui does not; and a view put in another is given its superview
   as the next responder again.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@interface MBUEditorView : NSView
@property (nonatomic, weak) IBOutlet NSResponder *controller;
@end

/* What a tab's controller does with the parts' views: one put in its host,
   filling it. */
void MBUPutView(NSView *view, NSView *host);

/* A badge at a pane tab's size (16 points square), drawn afresh: a copy of
   a badge drawn with -lockFocus is blank on GNUstep, whose image keeps what
   was drawn in a cache the copy does not take. */
NSImage *MBUTabImage(NSImage *badge);
