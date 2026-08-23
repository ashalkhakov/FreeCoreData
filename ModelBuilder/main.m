/* ModelBuilder — document-based .xcdatamodeld editor.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <AppKit/AppKit.h>
#import "MBDocument.h"

static BOOL MBLoadNib(NSString *name, id owner)
{
#if defined(__APPLE__)
  NSArray *top = nil;
  return [[NSBundle mainBundle] loadNibNamed:name owner:owner topLevelObjects:&top];
#else
  return [NSBundle loadNibNamed:name owner:owner];
#endif
}

int main(int argc, const char *argv[])
{
  (void)argc;
  (void)argv;
  @autoreleasepool {
    [NSApplication sharedApplication];
#ifdef __APPLE__
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
#endif
    (void)[NSDocumentController sharedDocumentController];
    if (!MBLoadNib(@"MainMenu", NSApp)) {
      NSLog(@"ModelBuilder: failed to load MainMenu.xib");
    }
    [NSApp run];
  }
  return 0;
}
