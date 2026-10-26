/* ModelBuilder — document-based .xcdatamodeld editor.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <AppKit/AppKit.h>
#import "MBDocument.h"
#if !defined(__APPLE__)
#import <AppKit/GSDisplayServer.h>
#endif

/* The nib's top-level objects are kept for the life of the app: the
   application delegate is one, and NSApp holds its delegate weakly.
   (GNUstep's loader keeps them itself.) */
static BOOL MBLoadNib(NSString *name, id owner)
{
#if defined(__APPLE__)
  static NSMutableArray *kept;
  NSArray *top = nil;
  if (![[NSBundle mainBundle] loadNibNamed:name owner:owner topLevelObjects:&top])
    return NO;
  if (!kept)
    kept = [NSMutableArray array];
  [kept addObjectsFromArray:top];
  return YES;
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
{
  /* Being filled: GNUstep's -[NSMenu update] asks its delegate again for
     each item changed (through -itemChanged:, as a menu in the window, a
     Windows theme's, redraws it), without end. */
  BOOL filling;
}
@end

@implementation MBVersionMenuDelegate

/* What the submenu shows: each item's title and version name (NSNull for
   the disabled "No Model Open"). */
static NSArray *MBVersionMenuItems(void)
{
  MBDocument *document = (MBDocument *)
      [[NSDocumentController sharedDocumentController] currentDocument];
  if (![document isKindOfClass:[MBDocument class]])
    return @[ @[ @"No Model Open", [NSNull null] ] ];
  NSMutableArray *items = [NSMutableArray array];
  for (NSString *name in [document versionNames]) {
    NSString *title = [name stringByDeletingPathExtension];
    if ([name isEqualToString:document.currentVersionName])
      title = [title stringByAppendingString:@" (current)"];
    [items addObject:@[ title, name ]];
  }
  return items;
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
  if (filling)
    return;
  NSArray *items = MBVersionMenuItems();
  /* An update that would change nothing changes nothing. */
  BOOL same = [menu numberOfItems] == (NSInteger)[items count];
  for (NSUInteger i = 0; same && i < [items count]; i++) {
    NSMenuItem *have = [menu itemAtIndex:(NSInteger)i];
    id name = items[i][1];
    same = [have.title isEqualToString:items[i][0]]
        && ((name == [NSNull null]) ? have.representedObject == nil : [have.representedObject isEqual:name]);
  }
  if (same)
    return;
  filling = YES;
  while ([menu numberOfItems] > 0)
    [menu removeItemAtIndex:0];
  for (NSArray *entry in items) {
    if (entry[1] == [NSNull null]) {
      NSMenuItem *none = [menu addItemWithTitle:entry[0] action:NULL keyEquivalent:@""];
      none.enabled = NO;
      continue;
    }
    NSMenuItem *item = [menu addItemWithTitle:entry[0]
                                       action:@selector(selectVersionMenuItem:)
                                keyEquivalent:@""];
    item.representedObject = entry[1];   /* nil target: responder chain */
  }
  filling = NO;
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
#else
    /* The X11 backend reads its mouse settings on the first button press,
       and doing so registers with the distributed notification center: a
       synchronous round trip to gdnc, during which the run loop reads the
       button RELEASE and queues it ahead of the press being processed.
       The app then sees mouse-up before mouse-down, and a table's first
       click waits in cell tracking for a mouse-up that already went by --
       the next click is swallowed finishing it, which is how a click on
       another attribute failed to update the inspector.  Settle it now,
       while no click is in flight. */
    {
      id server = GSCurrentServer();
      SEL initializeMouse = NSSelectorFromString(@"initializeMouse");
      if ([server respondsToSelector:initializeMouse])
        [server performSelector:initializeMouse];
    }
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
