/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class SBChartView;

/* The roster: a table of every employee, filtered by the search field and
 * sorted by its column headers, all through one NSArrayController and
 * Cocoa bindings declared in EmployeeWindow.xib - the columns bind to
 * arrangedObjects, the table's content, selection and sort descriptors
 * to the controller, the buttons' enabling to canRemove.  Code only
 * feeds the controller content and reacts to actions.
 *
 * The batch actions operate on "what the table shows" - the controller's
 * filter predicate IS the batch request's predicate - and tell the
 * viewContext what happened with mergeChangesFromRemoteContextSave:.
 * The department chart below the table reloads through an asynchronous
 * fetch: the fetch runs as its own event on the viewContext's queue and
 * the completion block updates the chart, so a slow or large fetch never
 * wedges the UI mid-eventloop. */
@interface SBEmployeeWindowController : NSWindowController <NSTableViewDelegate>

@property (nonatomic, strong) IBOutlet NSArrayController *employees;
@property (nonatomic, strong) IBOutlet NSTableView *tableView;
@property (nonatomic, strong) IBOutlet NSSearchField *searchField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *departmentPopUp;
@property (nonatomic, strong) IBOutlet NSButton *addButton;
@property (nonatomic, strong) IBOutlet NSButton *editButton;
@property (nonatomic, strong) IBOutlet NSButton *deleteButton;
@property (nonatomic, strong) IBOutlet SBChartView *chartView;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;

- (instancetype)initWithContainer:(NSPersistentContainer *)container;

/* Reads the store again and hands the array controller fresh content. */
- (void)reloadEmployees;
/* Recomputes the chart through an NSAsynchronousFetchRequest. */
- (void)reloadChart;

- (IBAction)filterChanged:(id)sender;
- (IBAction)addEmployee:(id)sender;
- (IBAction)editEmployee:(id)sender;
- (IBAction)deleteEmployee:(id)sender;

/* The batch three; see each for the request it demonstrates. */
- (IBAction)insertSampleData:(id)sender;
- (IBAction)moveShownToDepartment:(id)sender;
- (IBAction)deleteShown:(id)sender;

/* -reloadChart, menu-shaped. */
- (IBAction)refreshChart:(id)sender;

@end
