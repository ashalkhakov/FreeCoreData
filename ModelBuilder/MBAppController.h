/* ModelBuilder's application delegate (MainMenu.xib): the updater, and
   ModelBuilder > Check for Updates….

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

/* The Check for Updates… item's tag in MainMenu.xib. */
enum { MBCheckForUpdatesMenuItemTag = 7100 };

@interface MBAppController : NSObject <NSApplicationDelegate>

- (IBAction)checkForUpdates:(id)sender;

@end
