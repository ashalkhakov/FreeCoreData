/* ModelBuilder's updates.  On macOS, Sparkle: the newest release's
   appcast (SUFeedURL in Info.plist, signed with the key SUPublicEDKey
   names) is checked once a day if the user allows it, and Check for
   Updates… checks now (MBUpdater-Apple.m).  On GNUstep, nothing
   (MBUpdater.m): the AppImage carries its own update information, for
   AppImageUpdate, Gear Lever and the like.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <Foundation/Foundation.h>

@interface MBUpdater : NSObject

- (instancetype)initStarting:(BOOL)start;

/* Whether this system has an updater at all (Check for Updates… shown). */
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) BOOL canCheckForUpdates;

- (IBAction)checkForUpdates:(id)sender;

@end
