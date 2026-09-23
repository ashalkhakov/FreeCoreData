/*
 * This file is part of Bulletin, the FreeCoreData persistent-history
 * example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import "BLBoardWindowController.h"
#import "BLManagedObjects.h"

static NSString *BLTokenDefaultsKey(NSString *author)
{
    return [@"BLMergedToken." stringByAppendingString:author];
}

static NSString *BLDateDefaultsKey(NSString *author)
{
    return [@"BLMergedThrough." stringByAppendingString:author];
}

@implementation BLBoardWindowController
{
    NSPersistentContainer *_container;
    NSString *_author;
    NSPersistentHistoryToken *_lastToken;   /* merged everything up to here */
    NSDate *_mergedThroughDate;
    id _remoteChangeObserver;
}

- (instancetype)initWithContainer:(NSPersistentContainer *)container
                           author:(NSString *)author
{
    if ((self = [super initWithWindowNibName:@"BoardWindow"])) {
        _container = container;
        _author = [author copy];
        _mergedThroughDate = [NSDate distantPast];

        /* The author every save of this stack is recorded under; it is
         * what the other board's merge predicate excludes, and it is
         * this stack's identity in the history log. */
        [[_container viewContext] setTransactionAuthor:_author];
        [[_container viewContext] setName:[@"board-" stringByAppendingString:author]];

        /* Essential for a shared store file (macOS-arbitrated): Apple
         * caches fetched rows per coordinator and a refresh refetches
         * through that cache, so with the default (infinite) staleness
         * interval the other stack's writes would stay invisible even
         * after a merge.  Zero sends every refresh back to the store. */
        [[_container viewContext] setStalenessInterval:0];
    }
    return self;
}

- (void)dealloc
{
    if (_remoteChangeObserver != nil)
        [[NSNotificationCenter defaultCenter] removeObserver:_remoteChangeObserver];
}

- (NSString *)author
{
    return _author;
}

- (NSDate *)mergedThroughDate
{
    return _mergedThroughDate;
}

- (NSManagedObjectContext *)viewContext
{
    return [_container viewContext];
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    [[self window] setTitle:[NSString stringWithFormat:@"Bulletin — %@", _author]];

    [self.posts setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt"
                                                                   ascending:YES]]];

    /* Time-of-day column formatter; the 10.4 behavior is a no-op on
     * macOS but still opt-in on GNUstep. */
    NSDateFormatter *clock = [[NSDateFormatter alloc] init];
    [clock setFormatterBehavior:NSDateFormatterBehavior10_4];
    NSString *pattern = [NSDateFormatter dateFormatFromTemplate:@"jms" options:0
                                                         locale:[NSLocale currentLocale]];
    [clock setDateFormat:([pattern length] > 0) ? pattern : @"HH:mm:ss"];
    [[[self.tableView tableColumnWithIdentifier:@"createdAt"] dataCell] setFormatter:clock];

    /* The doorbell.  Every save or batch operation against the
     * history-tracking store rings it - the other stack's saves
     * included, which is the point.  Two rules bought by experience:
     * do not assume which object or thread it arrives with (Apple can
     * deliver it away from the main queue; FreeCoreData posts it while
     * the SAVING stack's coordinator is still locked), and therefore
     * never touch a context synchronously here - only schedule. */
    __weak BLBoardWindowController *weakSelf = self;
    _remoteChangeObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSPersistentStoreRemoteChangeNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        NSManagedObjectContext *context = [weakSelf viewContext];
        [context performBlock:^{
            [weakSelf mergeNewHistory];
        }];
    }];

    /* Where this author stopped merging last time, restored from the
     * archived token - the same catch-up a launching app extension or
     * daemon performs before it starts listening. */
    [self restoreMergePosition];
    [self mergeNewHistory];

    [self reloadPosts];
}

/* ---- the merge: the heart of the demo -------------------------------- */

/* The canonical persistent-history consumer, in one method:
 *
 *   1. anchor the request at the last merged token ("only what is new"),
 *   2. attach a Transaction-entity fetch request whose predicate is
 *      author != me ("only the other writers"),
 *   3. replay each transaction's objectIDNotification into the context,
 *   4. advance the token to the store's current position and remember
 *      the moment - everything at or before it is now either merged or
 *      our own.
 *
 * Build the inner fetch request from entityDescriptionWithContext:.
 * (Apple's context-less +fetchRequest / +entityDescription answer nil
 * unless a loaded container lets CoreData find "the" model; the
 * context-taking form works everywhere.)  Sort descriptors would raise
 * on the inner fetch request - history arrives in transaction order. */
- (void)mergeNewHistory
{
    NSManagedObjectContext *context = [self viewContext];

    NSPersistentHistoryChangeRequest *request =
        [NSPersistentHistoryChangeRequest fetchHistoryAfterToken:_lastToken];

    NSFetchRequest *othersOnly = [[NSFetchRequest alloc] init];
    [othersOnly setEntity:[NSPersistentHistoryTransaction entityDescriptionWithContext:context]];
    [othersOnly setPredicate:[NSPredicate predicateWithFormat:@"author != %@", _author]];
    [request setFetchRequest:othersOnly];

    NSError *error = nil;
    NSPersistentHistoryResult *result =
        (NSPersistentHistoryResult *)[context executeRequest:request error:&error];

    if (result == nil) {
        NSLog(@"Bulletin[%@]: history fetch failed: %@", _author, error);
        return;
    }

    NSArray *transactions = [result result];

    for (NSPersistentHistoryTransaction *transaction in transactions)
        [context mergeChangesFromContextDidSaveNotification:
            [transaction objectIDNotification]];

    /* Advance even when nothing merged: transactions the predicate
     * excluded are this author's own saves, which the context has by
     * definition. */
    _lastToken = [[_container persistentStoreCoordinator]
        currentPersistentHistoryTokenFromStores:nil];
    _mergedThroughDate = [NSDate date];

    if ([transactions count] > 0)
        [self reloadPosts];
}

/* ---- token persistence ----------------------------------------------- */

- (void)restoreMergePosition
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *data = [defaults dataForKey:BLTokenDefaultsKey(_author)];

    if (data != nil) {
        NSError *error = nil;
        _lastToken = [NSKeyedUnarchiver
            unarchivedObjectOfClass:[NSPersistentHistoryToken class]
                           fromData:data
                              error:&error];
        if (_lastToken == nil)
            NSLog(@"Bulletin[%@]: could not restore the merge token: %@", _author, error);
    }

    NSDate *through = [defaults objectForKey:BLDateDefaultsKey(_author)];
    if ([through isKindOfClass:[NSDate class]])
        _mergedThroughDate = through;
}

- (void)saveMergePosition
{
    if (_lastToken == nil)
        return;

    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_lastToken
                                         requiringSecureCoding:YES
                                                         error:&error];

    if (data == nil) {
        NSLog(@"Bulletin[%@]: could not archive the merge token: %@", _author, error);
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:data forKey:BLTokenDefaultsKey(_author)];
    [defaults setObject:_mergedThroughDate forKey:BLDateDefaultsKey(_author)];
}

/* ---- the board itself ------------------------------------------------ */

- (void)reloadPosts
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Post"];
    NSError *error = nil;
    NSArray *found = [[self viewContext] executeFetchRequest:fetch error:&error];

    if (found == nil) {
        NSLog(@"Bulletin[%@]: post fetch failed: %@", _author, error);
        found = @[];
    }
    [self.posts setContent:found];

    [self.statusField setStringValue:
        [NSString stringWithFormat:@"%lu post%s — you are “%@”",
                                   (unsigned long)[found count],
                                   ([found count] == 1) ? "" : "s",
                                   _author]];
}

- (IBAction)post:(id)sender
{
    NSString *text = [[self.composeField stringValue]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    if ([text length] == 0)
        return;

    NSManagedObjectContext *context = [self viewContext];
    BLPost *post = (BLPost *)[NSEntityDescription
        insertNewObjectForEntityForName:@"Post"
                 inManagedObjectContext:context];

    post.text = text;
    post.author = _author;
    post.createdAt = [NSDate date];

    NSError *error = nil;
    if (![context save:&error]) {
        NSLog(@"Bulletin[%@]: save failed: %@", _author, error);
        [context deleteObject:post];
        return;
    }

    [self.composeField setStringValue:@""];
    [self reloadPosts];
}

- (IBAction)deletePost:(id)sender
{
    NSArray *selection = [self.posts selectedObjects];

    if ([selection count] == 0)
        return;

    NSManagedObjectContext *context = [self viewContext];

    for (BLPost *post in selection)
        [context deleteObject:post];

    NSError *error = nil;
    if (![context save:&error]) {
        NSLog(@"Bulletin[%@]: delete failed: %@", _author, error);
        [context rollback];
        return;
    }

    /* The deleted post's text lives on in the history: its attribute
     * is marked Preserve After Deletion, so the deletion's tombstone
     * carries it - switch to the History window to see it. */
    [self reloadPosts];
}

@end
