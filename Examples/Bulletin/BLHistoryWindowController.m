/*
 * This file is part of Bulletin, the FreeCoreData persistent-history
 * example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import "BLHistoryWindowController.h"
#import "BLBoardWindowController.h"

@implementation BLHistoryWindowController
{
    NSPersistentContainer *_container;
    NSArray *_boards;   /* BLBoardWindowController */
    id _remoteChangeObserver;
}

- (instancetype)initWithContainer:(NSPersistentContainer *)container
                           boards:(NSArray *)boards
{
    if ((self = [super initWithWindowNibName:@"HistoryWindow"])) {
        _container = container;
        _boards = [boards copy];
    }
    return self;
}

- (void)dealloc
{
    if (_remoteChangeObserver != nil)
        [[NSNotificationCenter defaultCenter] removeObserver:_remoteChangeObserver];
}

- (NSManagedObjectContext *)viewContext
{
    return [_container viewContext];
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    [[self window] setTitle:@"Bulletin — History"];

    [self.transactions setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"number"
                                                                          ascending:YES]]];

    NSDateFormatter *clock = [[NSDateFormatter alloc] init];
    [clock setFormatterBehavior:NSDateFormatterBehavior10_4];
    NSString *pattern = [NSDateFormatter dateFormatFromTemplate:@"jms" options:0
                                                         locale:[NSLocale currentLocale]];
    [clock setDateFormat:([pattern length] > 0) ? pattern : @"HH:mm:ss"];
    [[[self.tableView tableColumnWithIdentifier:@"when"] dataCell] setFormatter:clock];

    /* Same doorbell as the boards, same rule: schedule, never touch a
     * context synchronously in the handler. */
    __weak BLHistoryWindowController *weakSelf = self;
    _remoteChangeObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSPersistentStoreRemoteChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        NSManagedObjectContext *context = [weakSelf viewContext];
        [context performBlock:^{
            [weakSelf reloadHistory];
        }];
    }];

    [self reloadHistory];
}

/* One line per change, tombstones included. */
- (NSString *)summaryOfChange:(NSPersistentHistoryChange *)change
{
    NSString *entityName = [[[change changedObjectID] entity] name];

    switch ([change changeType]) {
        case NSPersistentHistoryChangeTypeInsert:
            return [NSString stringWithFormat:@"+%@", entityName];
        case NSPersistentHistoryChangeTypeUpdate: {
            NSMutableArray *names = [NSMutableArray array];
            for (NSPropertyDescription *property in [change updatedProperties])
                [names addObject:[property name]];
            [names sortUsingSelector:@selector(compare:)];
            if ([names count] == 0)
                return [NSString stringWithFormat:@"~%@", entityName];
            return [NSString stringWithFormat:@"~%@(%@)", entityName,
                                              [names componentsJoinedByString:@","]];
        }
        case NSPersistentHistoryChangeTypeDelete: {
            /* The model marks Post.text Preserve After Deletion, so the
             * deletion's tombstone still has the words. */
            NSString *lastText = [[change tombstone] objectForKey:@"text"];
            if (lastText != nil)
                return [NSString stringWithFormat:@"−%@ (was “%@”)",
                                                  entityName, lastText];
            return [NSString stringWithFormat:@"−%@", entityName];
        }
    }
    return @"?";
}

- (void)reloadHistory
{
    /* The date-anchored fetch, from the beginning of time: the log
     * window wants everything that is still in the store.  The result
     * is transactions with their changes (the default result type). */
    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]];

    NSError *error = nil;
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[[self viewContext] executeRequest:request error:&error];

    if (result == nil) {
        NSLog(@"Bulletin[history]: history fetch failed: %@", error);
        return;
    }

    NSMutableArray *rows = [NSMutableArray array];

    for (NSPersistentHistoryTransaction *transaction in [result result]) {
        NSMutableArray *summaries = [NSMutableArray array];

        for (NSPersistentHistoryChange *change in [transaction changes])
            [summaries addObject:[self summaryOfChange:change]];

        [rows addObject:@{
            @"number": [NSNumber numberWithLongLong:[transaction transactionNumber]],
            @"author": ([transaction author] != nil) ? [transaction author] : @"?",
            @"when": [transaction timestamp],
            @"changes": [summaries componentsJoinedByString:@"  "],
        }];
    }

    [self.transactions setContent:rows];

    [self.statusField setStringValue:
        [NSString stringWithFormat:@"%lu transaction%s in the log",
                                   (unsigned long)[rows count],
                                   ([rows count] == 1) ? "" : "s"]];
}

- (IBAction)refresh:(id)sender
{
    [self reloadHistory];
}

/* How many transactions the store still holds, through the Count
 * result type. */
- (NSUInteger)transactionCount
{
    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterDate:[NSDate distantPast]];
    [request setResultType:NSPersistentHistoryResultTypeCount];

    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[[self viewContext] executeRequest:request error:NULL];

    return [(NSNumber *)[result result] unsignedIntegerValue];
}

- (IBAction)compactHistory:(id)sender
{
    /* The purge floor: the oldest moment any board has merged through.
     * Deleting below it is safe - every consumer has already replayed
     * those transactions; deleting above it would lose changes for the
     * consumer that is behind.  (A real multi-process setup persists
     * each consumer's position where every process can read it; the
     * boards here just answer directly.) */
    NSDate *floor = nil;

    for (BLBoardWindowController *board in _boards) {
        NSDate *through = [board mergedThroughDate];
        if (floor == nil || [through compare:floor] == NSOrderedAscending)
            floor = through;
    }

    if (floor == nil)
        return;

    NSUInteger before = [self transactionCount];

    NSPersistentHistoryChangeRequest *purge =
        [NSPersistentHistoryChangeRequest deleteHistoryBeforeDate:floor];

    NSError *error = nil;
    if ([[self viewContext] executeRequest:purge error:&error] == nil) {
        NSLog(@"Bulletin[history]: purge failed: %@", error);
        return;
    }

    NSUInteger after = [self transactionCount];

    [self reloadHistory];
    [self.statusField setStringValue:
        [NSString stringWithFormat:@"Compacted: %lu purged, %lu kept",
                                   (unsigned long)(before - after),
                                   (unsigned long)after]];
}

@end
