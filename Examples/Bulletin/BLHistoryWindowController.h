/*
 * This file is part of Bulletin, the FreeCoreData persistent-history
 * example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class BLBoardWindowController;

/* The transaction log, live: every save either board makes appears
 * here as a row - transaction number, author, timestamp, and a
 * summary of its changes, including the tombstoned text of deleted
 * posts.  The table is an NSArrayController of plain dictionaries
 * built from NSPersistentHistoryTransaction/Change; the log refreshes
 * on the same remote-change notification the boards merge on.
 *
 * Compact History demonstrates the safe purge: history is deleted only
 * up to the oldest merged-through moment across every board, because a
 * purge takes rows away from every future fetch - a consumer that has
 * not caught up yet would silently miss changes. */
@interface BLHistoryWindowController : NSWindowController

@property (nonatomic, strong) IBOutlet NSArrayController *transactions;
@property (nonatomic, strong) IBOutlet NSTableView *tableView;
@property (nonatomic, strong) IBOutlet NSButton *refreshButton;
@property (nonatomic, strong) IBOutlet NSButton *compactButton;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;

/* The history is store-wide; any stack's container serves.  The boards
 * are consulted for the purge floor. */
- (instancetype)initWithContainer:(NSPersistentContainer *)container
                           boards:(NSArray *)boards;

- (IBAction)refresh:(id)sender;
- (IBAction)compactHistory:(id)sender;

@end
