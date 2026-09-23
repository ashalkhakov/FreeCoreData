/*
 * This file is part of Bulletin, the FreeCoreData persistent-history
 * example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import "BLAppDelegate.h"
#import "BLBoardWindowController.h"
#import "BLHistoryWindowController.h"

@implementation BLAppDelegate

/* One full stack on the shared store file.  Both stacks are built the
 * same way; only the author (and therefore the window) differs.
 * NSPersistentHistoryTrackingKey turns on the recording,
 * NSPersistentStoreRemoteChangeNotificationPostOptionKey the
 * announcement - without the second option there is a log but no
 * doorbell, and the boards would have to poll. */
- (NSPersistentContainer *)makeContainerForStoreURL:(NSURL *)storeURL error:(NSError **)outError
{
    NSPersistentContainer *container = [NSPersistentContainer persistentContainerWithName:@"Bulletin"];

    NSPersistentStoreDescription *description = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:storeURL];
    [description setOption:@YES forKey:NSPersistentHistoryTrackingKey];
    [description setOption:@YES forKey:NSPersistentStoreRemoteChangeNotificationPostOptionKey];
    [container setPersistentStoreDescriptions:@[description]];

    __block NSError *loadError = nil;
    [container loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *loaded, NSError *error) {
        loadError = error;
    }];

    if (outError != NULL)
        *outError = loadError;
    return (loadError == nil) ? container : nil;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSURL *storeURL = [[NSPersistentContainer defaultDirectoryURL]
        URLByAppendingPathComponent:@"Bulletin.sqlite"];

    NSError *error = nil;
    NSPersistentContainer *aliceStack = [self makeContainerForStoreURL:storeURL error:&error];
    NSPersistentContainer *bobStack = (aliceStack != nil) ? [self makeContainerForStoreURL:storeURL error:&error] : nil;

    if (bobStack == nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Bulletin could not open its database."];
        [alert setInformativeText:[error localizedDescription]];
        [alert runModal];
        [NSApp terminate:self];
        return;
    }

    _aliceWindowController = [[BLBoardWindowController alloc] initWithContainer:aliceStack author:@"alice"];
    _bobWindowController = [[BLBoardWindowController alloc] initWithContainer:bobStack author:@"bob"];

    /* The history window reads through alice's stack, but what it
     * shows is store-wide: the log is rows in the store file, the same
     * from every stack. */
    _historyWindowController = [[BLHistoryWindowController alloc]
        initWithContainer:aliceStack
                   boards:@[_aliceWindowController, _bobWindowController]];

    [[_aliceWindowController window] setFrameOrigin:NSMakePoint(80, 360)];
    [[_bobWindowController window] setFrameOrigin:NSMakePoint(560, 360)];
    [[_historyWindowController window] setFrameOrigin:NSMakePoint(320, 40)];

    [_aliceWindowController showWindow:self];
    [_bobWindowController showWindow:self];
    [_historyWindowController showWindow:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application
{
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    /* Each board archives where it stopped merging, so the next launch
     * can resume from its token instead of replaying from the top. */
    [_aliceWindowController saveMergePosition];
    [_bobWindowController saveMergePosition];
}

@end
