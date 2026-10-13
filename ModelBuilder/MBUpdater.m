/* ModelBuilder's updates on GNUstep: none here, the AppImage is updated
   from outside it.  See MBUpdater.h.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBUpdater.h"

@implementation MBUpdater

- (instancetype)initStarting:(BOOL)start
{
  (void)start;
  return [super init];
}

- (BOOL)available
{
  return NO;
}

- (BOOL)canCheckForUpdates
{
  return NO;
}

- (IBAction)checkForUpdates:(id)sender
{
  (void)sender;
}

@end
