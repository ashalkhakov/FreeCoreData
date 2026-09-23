/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import "SBAppDelegate.h"
#import "SBEmployeeWindowController.h"

@implementation SBAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    /* The whole stack in two calls: the container finds Staffbook.momd in
     * the app bundle, makes the coordinator and the main-queue viewContext,
     * and the default store description points at
     * <Application Support>/Staffbook.sqlite.  The default description
     * loads synchronously, so by the time the handler runs (and this method
     * returns) the store is there. */
    _container = [NSPersistentContainer persistentContainerWithName:@"Staffbook"];

    __block NSError *loadError = nil;
    [_container loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *description, NSError *error) {
        loadError = error;
    }];

    if (loadError != nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Staffbook could not open its database."];
        [alert setInformativeText:[loadError localizedDescription]];
        [alert runModal];
        [NSApp terminate:self];
        return;
    }

    _employeeWindowController = [[SBEmployeeWindowController alloc] initWithContainer:_container];
    [_employeeWindowController showWindow:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application
{
    return YES;
}

@end
