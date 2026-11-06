/* UDCode's Core Data extension — an editor tab's view (see MBUEditorView.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBUEditorView.h"

@implementation MBUEditorView

- (void)setNextResponder:(NSResponder *)responder
{
  NSResponder *controller = self.controller;
  if (controller == nil || responder == controller) {
    [super setNextResponder:responder];
    return;
  }
  [controller setNextResponder:responder];
  [super setNextResponder:controller];
}

@end

void MBUPutView(NSView *view, NSView *host)
{
  if ([view superview] == host) return;
  [view setFrame:[host bounds]];
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [host addSubview:view];
}

NSImage *MBUTabImage(NSImage *badge)
{
  if (badge == nil) return nil;
  NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [image lockFocus];
  [badge drawInRect:NSMakeRect(0.5, 0.5, 15, 15) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
  [image unlockFocus];
#pragma clang diagnostic pop
  return image;
}
