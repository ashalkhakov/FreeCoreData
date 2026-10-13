/* ModelBuilder's application delegate.  See MBAppController.h.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBAppController.h"
#import "MBUpdater.h"

@implementation MBAppController {
  MBUpdater *_updater;
}

/* Updates, set up before the app finishes launching (as Sparkle asks).
   Where there is no updater, no menu item. */
- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
  (void)notification;
  _updater = [[MBUpdater alloc] initStarting:YES];
  if (!_updater.available) {
    NSMenu *appMenu = [[[NSApp mainMenu] itemAtIndex:0] submenu];
    NSMenuItem *check = [appMenu itemWithTag:MBCheckForUpdatesMenuItemTag];
    if (check)
      [appMenu removeItem:check];
  }
}

- (IBAction)checkForUpdates:(id)sender
{
  [_updater checkForUpdates:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  if ([item action] == @selector(checkForUpdates:))
    return _updater.canCheckForUpdates;
  return YES;
}

@end
