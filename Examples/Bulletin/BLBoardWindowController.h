/*
 * This file is part of Bulletin, the FreeCoreData persistent-history
 * example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

/* One writer's window: a table of every post (Cocoa bindings through
 * the NSArrayController declared in BoardWindow.xib), a compose field,
 * and a Delete button whose enabling is the controller's canRemove.
 *
 * The half that matters lives below the UI: this controller is also
 * the history consumer for its stack.  Its viewContext never sees the
 * other window's saves on its own - they happen through a different
 * coordinator - so it listens for
 * NSPersistentStoreRemoteChangeNotification and, on each ring, runs
 * the canonical merge (-mergeNewHistory): fetch history after the last
 * merged token, filtered to author != mine, replay each transaction's
 * objectIDNotification into the context, then advance and archive the
 * token. */
@interface BLBoardWindowController : NSWindowController

@property (nonatomic, strong) IBOutlet NSArrayController *posts;
@property (nonatomic, strong) IBOutlet NSTableView *tableView;
@property (nonatomic, strong) IBOutlet NSTextField *composeField;
@property (nonatomic, strong) IBOutlet NSButton *postButton;
@property (nonatomic, strong) IBOutlet NSButton *deleteButton;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;

- (instancetype)initWithContainer:(NSPersistentContainer *)container
                           author:(NSString *)author;

- (NSString *)author;

/* The wall-clock moment up to which this board has merged everything;
 * the history window purges before the oldest of these across boards
 * (history a board has not consumed yet must not be deleted). */
- (NSDate *)mergedThroughDate;

/* Archives the merge token (NSPersistentHistoryToken is NSSecureCoding)
 * and the merged-through date into user defaults, per author. */
- (void)saveMergePosition;

- (IBAction)post:(id)sender;
- (IBAction)deletePost:(id)sender;

@end
