/*
 * This file is part of Bulletin, the FreeCoreData persistent-history
 * example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class BLBoardWindowController;
@class BLHistoryWindowController;

/* Bulletin is a message board with a twist: it runs TWO complete Core
 * Data stacks in one process - two NSPersistentContainers, two
 * coordinators, two view contexts - on the SAME store file.  Each
 * stack gets its own window and its own transactionAuthor ("alice",
 * "bob"), which makes one process behave like the app-plus-extension
 * or app-plus-daemon setups persistent history was designed for: a
 * save by one stack is invisible to the other's contexts until the
 * other stack notices it and merges it.
 *
 * Noticing and merging is the whole demo:
 *
 *   NSPersistentHistoryTrackingKey                each save/batch is
 *                                                 recorded in the store
 *   NSPersistentStoreRemoteChangeNotification...  ...and announced
 *   fetchHistoryWithFetchRequest: + author != me  each board fetches
 *                                                 only the OTHER
 *                                                 writer's transactions
 *   transaction.objectIDNotification              ...and replays them
 *                                                 into its own context
 *   NSPersistentHistoryToken (NSSecureCoding)     where a board stopped
 *                                                 merging, archived in
 *                                                 user defaults
 *   tombstones (preserveValueOnDeletion)          the history window
 *                                                 shows deleted posts'
 *                                                 last text
 *   deleteHistoryBeforeTransaction:               Compact History
 *                                                 purges what every
 *                                                 board has merged
 *
 * The board windows are in BLBoardWindowController, the transaction
 * log and the purge in BLHistoryWindowController. */
@interface BLAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong, readonly) BLBoardWindowController *aliceWindowController;
@property (nonatomic, strong, readonly) BLBoardWindowController *bobWindowController;
@property (nonatomic, strong, readonly) BLHistoryWindowController *historyWindowController;

@end
