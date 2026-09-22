/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import "SBEmployeeWindowController.h"
#import "SBEmployeeEditorController.h"
#import "SBManagedObjects.h"
#import "SBChartView.h"

@implementation SBEmployeeWindowController
{
    NSPersistentContainer *_container;
}

- (instancetype)initWithContainer:(NSPersistentContainer *)container
{
    if ((self = [super initWithWindowNibName:@"EmployeeWindow"])) {
        _container = container;
    }
    return self;
}

- (NSManagedObjectContext *)viewContext
{
    return [_container viewContext];
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    /* The bindings all live in EmployeeWindow.xib; what remains here is
     * what a XIB does not carry well: the initial sort, and the cell
     * formatters.  The formatters get the 10.4 behavior explicitly - a
     * no-op on macOS, but GNUstep still defaults to the OLD formatter
     * behavior, where an ICU pattern like yyyy-MM-dd is literal text. */
    [self.employees setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
                                                                        selector:@selector(caseInsensitiveCompare:)]]];

    NSNumberFormatter *money = [[NSNumberFormatter alloc] init];
    [money setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [money setNumberStyle:NSNumberFormatterDecimalStyle];
    [money setMaximumFractionDigits:0];
    [[[self.tableView tableColumnWithIdentifier:@"salary"] dataCell] setFormatter:money];

    NSDateFormatter *day = [[NSDateFormatter alloc] init];
    [day setFormatterBehavior:NSDateFormatterBehavior10_4];
    [day setDateFormat:@"yyyy-MM-dd"];
    [[[self.tableView tableColumnWithIdentifier:@"hireDate"] dataCell] setFormatter:day];

    [self.departmentPopUp removeAllItems];
    [self.departmentPopUp addItemsWithTitles:SBDepartments()];

    /* Edit/Delete enabling is the canRemove binding in the XIB (that
     * needs the carried gnustep-gui selection-KVO patch - see
     * patches/gnustep/).  Live filtering is the one remaining delegate
     * job: GNUstep's search field does not send its action per
     * keystroke. */
    [self.searchField setDelegate:(id)self];

    [self reloadEmployees];
    [self reloadChart];
}

- (void)controlTextDidChange:(NSNotification *)note
{
    if ([note object] == self.searchField)
        [self filterChanged:self.searchField];
}

- (void)reloadEmployees
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Employee"];
    NSError *error = nil;
    NSArray *employees = [[self viewContext] executeFetchRequest:fetch error:&error];

    if (employees == nil) {
        NSLog(@"Staffbook: employee fetch failed: %@", error);
        employees = @[];
    }
    [self.employees setContent:employees];
}

/* ---- filtering ------------------------------------------------------- */

- (IBAction)filterChanged:(id)sender
{
    NSString *needle = [[self.searchField stringValue]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    if ([needle length] == 0)
        [self.employees setFilterPredicate:nil];
    else
        [self.employees setFilterPredicate:
            [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR department CONTAINS[cd] %@",
                                             needle, needle]];

    /* Explicit on purpose: a new filter predicate rearranges by itself
     * on macOS, but not on every GNUstep controller layer. */
    [self.employees rearrangeObjects];
}

/* What the batch requests act on: exactly what the table shows. */
- (NSPredicate *)shownPredicate
{
    return [self.employees filterPredicate];
}

/* ---- add / edit / delete (the ordinary, context-bound paths) --------- */

- (SBEmployee *)selectedEmployee
{
    NSArray *selection = [self.employees selectedObjects];

    return [selection count] > 0 ? selection[0] : nil;
}

- (IBAction)addEmployee:(id)sender
{
    [self runEditorForEmployeeID:nil];
}

- (IBAction)editEmployee:(id)sender
{
    SBEmployee *employee = [self selectedEmployee];

    if (employee != nil)
        [self runEditorForEmployeeID:[employee objectID]];
}

- (void)runEditorForEmployeeID:(NSManagedObjectID *)employeeID
{
    SBEmployeeEditorController *editor = [[SBEmployeeEditorController alloc]
        initWithParentContext:[self viewContext] employeeID:employeeID];

    if ([editor runModal]) {
        [self reloadEmployees];
        [self reloadChart];
    }
}

- (IBAction)deleteEmployee:(id)sender
{
    SBEmployee *employee = [self selectedEmployee];

    if (employee == nil)
        return;

    /* The classic path, for one record: delete on the viewContext, save.
     * (Compare -deleteShown:, which never materializes an object.) */
    [[self viewContext] deleteObject:employee];

    NSError *error = nil;
    if (![[self viewContext] save:&error]) {
        NSLog(@"Staffbook: delete failed: %@", error);
        return;
    }
    [self reloadEmployees];
    [self reloadChart];
}

/* ---- the batch three ------------------------------------------------- */

/* NSBatchInsertRequest, dictionary-handler flavor: rows go straight into
 * the SQLite store - no NSManagedObjects, no validation, one transaction.
 * The ObjectIDs result feeds mergeChangesFromRemoteContextSave:, which is
 * how a bypassed viewContext hears about the new rows. */
- (IBAction)insertSampleData:(id)sender
{
    NSArray *first = @[@"Ada", @"Grace", @"Edsger", @"Barbara", @"Donald",
                       @"Radia", @"Ken", @"Adele", @"Dennis", @"Frances"];
    NSArray *last = @[@"Lovelace", @"Hopper", @"Dijkstra", @"Liskov", @"Knuth",
                      @"Perlman", @"Thompson", @"Goldberg", @"Ritchie", @"Allen"];
    NSArray *departments = SBDepartments();
    NSUInteger existing = [[self.employees content] count];

    __block NSUInteger row = 0;
    NSBatchInsertRequest *insert = [[NSBatchInsertRequest alloc]
        initWithEntityName:@"Employee"
         dictionaryHandler:^BOOL(NSMutableDictionary *obj) {
             if (row == [first count])
                 return YES;   /* done; this dictionary is not inserted */

             obj[@"name"] = [NSString stringWithFormat:@"%@ %@", first[row], last[row]];
             obj[@"department"] = departments[(existing + row) % [departments count]];
             obj[@"salary"] = @(52000 + ((existing + row) * 7150) % 48000);
             obj[@"hireDate"] = [NSDate dateWithTimeIntervalSinceNow:
                 -(NSTimeInterval)((existing + row + 1) * 47.0 * 86400.0)];
             row++;
             return NO;
         }];
    [insert setResultType:NSBatchInsertRequestResultTypeObjectIDs];

    NSError *error = nil;
    NSBatchInsertResult *result =
        (NSBatchInsertResult *)[[self viewContext] executeRequest:insert error:&error];

    if (result == nil) {
        NSLog(@"Staffbook: batch insert failed: %@", error);
        return;
    }

    [NSManagedObjectContext
        mergeChangesFromRemoteContextSave:@{NSInsertedObjectsKey: [result result]}
                             intoContexts:@[[self viewContext]]];

    [self reloadEmployees];
    [self reloadChart];
    [self.statusField setStringValue:
        [NSString stringWithFormat:@"Batch insert added %lu employees.",
                                   (unsigned long)[[result result] count]]];
}

/* NSBatchUpdateRequest: one UPDATE over every row the table shows, without
 * loading any of them.  Registered objects are stale afterwards by design;
 * the merge refreshes the ones this context has loaded. */
- (IBAction)moveShownToDepartment:(id)sender
{
    NSString *department = [self.departmentPopUp titleOfSelectedItem];

    if (department == nil)
        return;

    NSBatchUpdateRequest *update = [[NSBatchUpdateRequest alloc]
        initWithEntityName:@"Employee"];
    [update setPredicate:[self shownPredicate]];
    [update setPropertiesToUpdate:
        @{@"department": [NSExpression expressionForConstantValue:department]}];
    [update setResultType:NSUpdatedObjectIDsResultType];

    NSError *error = nil;
    NSBatchUpdateResult *result =
        (NSBatchUpdateResult *)[[self viewContext] executeRequest:update error:&error];

    if (result == nil) {
        NSLog(@"Staffbook: batch update failed: %@", error);
        return;
    }

    [NSManagedObjectContext
        mergeChangesFromRemoteContextSave:@{NSUpdatedObjectsKey: [result result]}
                             intoContexts:@[[self viewContext]]];

    [self reloadEmployees];
    [self reloadChart];
    [self.statusField setStringValue:
        [NSString stringWithFormat:@"Batch update moved %lu employees to %@.",
                                   (unsigned long)[[result result] count], department]];
}

/* NSBatchDeleteRequest: the shown set is deleted in the store in one
 * statement; the merge marks any loaded instances deleted. */
- (IBAction)deleteShown:(id)sender
{
    NSUInteger shown = [[self.employees arrangedObjects] count];

    if (shown == 0)
        return;

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithFormat:@"Delete the %lu shown employees?",
                                                     (unsigned long)shown]];
    [alert setInformativeText:@"A batch delete removes them from the store directly; this cannot be undone."];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn)
        return;

    NSFetchRequest *shownFetch = [NSFetchRequest fetchRequestWithEntityName:@"Employee"];
    [shownFetch setPredicate:[self shownPredicate]];

    NSBatchDeleteRequest *delete = [[NSBatchDeleteRequest alloc]
        initWithFetchRequest:shownFetch];
    [delete setResultType:NSBatchDeleteResultTypeObjectIDs];

    NSError *error = nil;
    NSBatchDeleteResult *result =
        (NSBatchDeleteResult *)[[self viewContext] executeRequest:delete error:&error];

    if (result == nil) {
        NSLog(@"Staffbook: batch delete failed: %@", error);
        return;
    }

    [NSManagedObjectContext
        mergeChangesFromRemoteContextSave:@{NSDeletedObjectsKey: [result result]}
                             intoContexts:@[[self viewContext]]];

    [self.searchField setStringValue:@""];
    [self.employees setFilterPredicate:nil];
    [self reloadEmployees];
    [self reloadChart];
    [self.statusField setStringValue:
        [NSString stringWithFormat:@"Batch delete removed %lu employees.",
                                   (unsigned long)[[result result] count]]];
}

/* ---- the chart, by asynchronous fetch -------------------------------- */

- (IBAction)refreshChart:(id)sender
{
    [self reloadChart];
}

/* This is where an async fetch earns its keep: the chart wants every
 * (department, salary) pair, which on a big roster is the kind of fetch
 * you do not want blocking the event loop.  executeRequest: returns at
 * once, the fetch runs as its own event on the viewContext's queue, and
 * the completion block - delivered back on the main queue, because that
 * is the viewContext's queue - aggregates and redraws.  Dictionary
 * results keep it to raw rows: no objects are registered just to draw. */
- (void)reloadChart
{
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Employee"];
    [fetch setResultType:NSDictionaryResultType];
    [fetch setPropertiesToFetch:@[@"department", @"salary"]];

    SBChartView *chartView = self.chartView;
    NSTextField *statusField = self.statusField;

    NSAsynchronousFetchRequest *request = [[NSAsynchronousFetchRequest alloc]
        initWithFetchRequest:fetch
             completionBlock:^(NSAsynchronousFetchResult *result) {
                 if ([result finalResult] == nil) {
                     NSLog(@"Staffbook: chart fetch failed: %@", [result operationError]);
                     return;
                 }

                 NSMutableDictionary *totals = [NSMutableDictionary dictionary];
                 NSMutableDictionary *counts = [NSMutableDictionary dictionary];

                 for (NSDictionary *rowValues in [result finalResult]) {
                     NSString *department = rowValues[@"department"];

                     if (department == nil)
                         continue;
                     totals[department] = @([totals[department] doubleValue] +
                                            [rowValues[@"salary"] doubleValue]);
                     counts[department] = @([counts[department] unsignedIntegerValue] + 1);
                 }

                 NSMutableArray *bars = [NSMutableArray array];
                 NSUInteger total = 0;

                 for (NSString *department in SBDepartments()) {
                     NSUInteger count = [counts[department] unsignedIntegerValue];

                     if (count == 0)
                         continue;
                     total += count;
                     [bars addObject:@{@"label": department,
                                       @"value": @([totals[department] doubleValue] / count),
                                       @"detail": [NSString stringWithFormat:@"%lu", (unsigned long)count]}];
                 }

                 [chartView setBars:bars];
                 [statusField setStringValue:
                     [NSString stringWithFormat:@"%lu employees. Average salary by department:",
                                                (unsigned long)total]];
             }];

    NSError *error = nil;
    if ([[self viewContext] executeRequest:request error:&error] == nil)
        NSLog(@"Staffbook: could not start the chart fetch: %@", error);
}

@end
