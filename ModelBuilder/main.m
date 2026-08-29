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

/* Populates the Model > Model Version submenu with one item per
   version of the front document (checkmark on the edited version —
   validateMenuItem in MBWindowController keeps the states fresh).
   The menu itself lives in MainMenu.xib; only this submenu is dynamic,
   so it is the one piece attached in code. */
@interface MBVersionMenuDelegate : NSObject <NSMenuDelegate>
@end

@implementation MBVersionMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu
{
  while ([menu numberOfItems] > 0)
    [menu removeItemAtIndex:0];
  MBDocument *document = (MBDocument *)
      [[NSDocumentController sharedDocumentController] currentDocument];
  if (![document isKindOfClass:[MBDocument class]]) {
    NSMenuItem *none = [menu addItemWithTitle:@"No Model Open" action:NULL keyEquivalent:@""];
    none.enabled = NO;
    return;
  }
  for (NSString *name in [document versionNames]) {
    NSString *title = [name stringByDeletingPathExtension];
    if ([name isEqualToString:document.currentVersionName])
      title = [title stringByAppendingString:@" (current)"];
    NSMenuItem *item = [menu addItemWithTitle:title
                                       action:@selector(selectVersionMenuItem:)
                                keyEquivalent:@""];
    item.representedObject = name;   /* nil target: responder chain */
  }
}

@end

/* Finds the "Model Version" item MainMenu.xib declares (searching by
   title, wherever it lives) and gives it its dynamic submenu. */
static void MBAttachVersionMenu(void)
{
  static MBVersionMenuDelegate *versionDelegate;

  NSMenu *main = [NSApp mainMenu];
  for (NSInteger i = 0; i < [main numberOfItems]; i++) {
    NSMenu *submenu = [[main itemAtIndex:i] submenu];
    NSMenuItem *versionItem = (NSMenuItem *)[submenu itemWithTitle:@"Model Version"];
    if (!versionItem) continue;

    versionDelegate = [[MBVersionMenuDelegate alloc] init];
    NSMenu *versionsMenu = [[NSMenu alloc] initWithTitle:@"Model Version"];
    versionsMenu.delegate = versionDelegate;
    versionItem.submenu = versionsMenu;
    return;
  }
  NSLog(@"ModelBuilder: no \"Model Version\" item in the main menu; "
        @"version switching is unavailable");
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
    MBAttachVersionMenu();
    [NSApp run];
  }
  return 0;
}
