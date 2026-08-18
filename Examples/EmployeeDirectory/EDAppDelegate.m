/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "EDAppDelegate.h"
#import "EmployeeDirectoryModel.h"

static NSString *describeIndexPath(NSIndexPath *indexPath)
{
    if (indexPath == nil)
        return @"-";

    /* Index paths of a fetched results controller carry the section at
       position 0 and the row inside the section at position 1. */
    return [NSString stringWithFormat:@"%lu.%lu",
        (unsigned long)[indexPath indexAtPosition:0],
        (unsigned long)[indexPath indexAtPosition:1]];
}

static NSString *describeChangeType(NSFetchedResultsChangeType type)
{
    switch (type) {
        case NSFetchedResultsChangeInsert: return @"insert";
        case NSFetchedResultsChangeDelete: return @"delete";
        case NSFetchedResultsChangeMove: return @"move";
        case NSFetchedResultsChangeUpdate: return @"update";
    }
    return @"?";
}

@implementation EDAppDelegate

- (void)dealloc
{
    [_model release];
    [_context release];
    [_controller release];
    [_storePath release];
    [_window release];
    [_rows release];
    [super dealloc];
}

/* ------------------------------------------------------------------
   Logging
   ------------------------------------------------------------------ */
- (void)log:(NSString *)format, ...
{
    va_list arguments;

    va_start(arguments, format);
    NSString *line = [[[NSString alloc] initWithFormat:format arguments:arguments] autorelease];
    va_end(arguments);

    NSTextStorage *storage = [_logView textStorage];

    [storage replaceCharactersInRange:NSMakeRange([storage length], 0)
             withString:[line stringByAppendingString:@"\n"]];
    [_logView scrollRangeToVisible:NSMakeRange([storage length], 0)];
}

/* ------------------------------------------------------------------
   CoreData stack
   ------------------------------------------------------------------ */
- (NSManagedObjectContext *)makeContext
{
    NSPersistentStoreCoordinator *coordinator =
        [[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:_model] autorelease];
    NSError *error = nil;

    if ([coordinator addPersistentStoreWithType:NSSQLiteStoreType
                     configuration:nil
                     URL:[NSURL fileURLWithPath:_storePath]
                     options:nil
                     error:&error] == nil) {
        NSLog(@"unable to open the store: %@", error);
        [NSApp terminate:nil];
        return nil;
    }

    NSManagedObjectContext *context = [[[NSManagedObjectContext alloc] init] autorelease];

    [context setPersistentStoreCoordinator:coordinator];

    return context;
}

- (NSManagedObject *)insert:(NSString *)entityName
{
    return [NSEntityDescription insertNewObjectForEntityForName:entityName
                                inManagedObjectContext:_context];
}

- (NSArray *)fetch:(NSString *)entityName
         predicate:(NSPredicate *)predicate
   sortDescriptors:(NSArray *)sortDescriptors
         inContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];

    [request setEntity:[NSEntityDescription entityForName:entityName
                                            inManagedObjectContext:context]];
    [request setPredicate:predicate];
    [request setSortDescriptors:sortDescriptors];

    NSError *error = nil;
    NSArray *result = [context executeFetchRequest:request error:&error];

    if (result == nil)
        [self log:@"fetch of %@ failed: %@", entityName, error];

    return result;
}

- (NSArray *)employeeSortDescriptors
{
    return [NSArray arrayWithObjects:
        [[[NSSortDescriptor alloc] initWithKey:@"department.name" ascending:YES] autorelease],
        [[[NSSortDescriptor alloc] initWithKey:@"lastName" ascending:YES] autorelease], nil];
}

- (NSManagedObject *)departmentNamed:(NSString *)name
{
    NSArray *matches = [self fetch:@"Department"
                        predicate:[NSPredicate predicateWithFormat:@"name == %@", name]
                        sortDescriptors:nil
                        inContext:_context];

    return [matches count] > 0 ? [matches objectAtIndex:0] : nil;
}

- (void)seedStore
{
    NSManagedObject *engineering = [self insert:@"Department"];
    [engineering setValue:@"Engineering" forKey:@"name"];

    NSManagedObject *sales = [self insert:@"Department"];
    [sales setValue:@"Sales" forKey:@"name"];

    NSManagedObject *alice = [self insert:@"Employee"];
    [alice setValue:@"Alice" forKey:@"firstName"];
    [alice setValue:@"Anderson" forKey:@"lastName"];
    [alice setValue:[NSNumber numberWithInt:5000] forKey:@"salary"];
    [alice setValue:engineering forKey:@"department"];

    NSManagedObject *bob = [self insert:@"Employee"];
    [bob setValue:@"Bob" forKey:@"firstName"];
    [bob setValue:@"Brown" forKey:@"lastName"];
    [bob setValue:[NSNumber numberWithInt:4000] forKey:@"salary"];
    [bob setValue:engineering forKey:@"department"];

    NSManagedObject *carol = [self insert:@"Employee"];
    [carol setValue:@"Carol" forKey:@"firstName"];
    [carol setValue:@"Clarke" forKey:@"lastName"];
    [carol setValue:[NSNumber numberWithInt:4500] forKey:@"salary"];
    [carol setValue:sales forKey:@"department"];

    /* Contractor is a second subentity of the abstract Person entity. */
    NSManagedObject *dave = [self insert:@"Contractor"];
    [dave setValue:@"Dave" forKey:@"firstName"];
    [dave setValue:@"Doyle" forKey:@"lastName"];
    [dave setValue:@"Consulting Inc." forKey:@"agency"];

    /* Many-to-many: employees take part in several projects. */
    NSManagedObject *apollo = [self insert:@"Project"];
    [apollo setValue:@"Apollo" forKey:@"name"];

    NSManagedObject *gemini = [self insert:@"Project"];
    [gemini setValue:@"Gemini" forKey:@"name"];

    [[alice mutableSetValueForKey:@"projects"] addObject:apollo];
    [[alice mutableSetValueForKey:@"projects"] addObject:gemini];
    [[bob mutableSetValueForKey:@"projects"] addObject:apollo];
    [[carol mutableSetValueForKey:@"projects"] addObject:gemini];

    NSError *error = nil;

    if (![_context save:&error])
        [self log:@"seeding the store failed: %@", error];
}

- (void)makeFetchedResultsController
{
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];

    [request setEntity:[NSEntityDescription entityForName:@"Employee"
                                            inManagedObjectContext:_context]];
    [request setSortDescriptors:[self employeeSortDescriptors]];

    [_controller setDelegate:nil];
    [_controller release];
    _controller = [[NSFetchedResultsController alloc] initWithFetchRequest:request
                                                      managedObjectContext:_context
                                                      sectionNameKeyPath:@"department.name"
                                                      cacheName:nil];
    [_controller setDelegate:self];

    NSError *error = nil;

    if (![_controller performFetch:&error])
        [self log:@"performFetch failed: %@", error];
}

/* ------------------------------------------------------------------
   Table rows: sections and employees flattened into one list
   ------------------------------------------------------------------ */
- (void)rebuildRows
{
    [_rows removeAllObjects];

    for (id <NSFetchedResultsSectionInfo> section in [_controller sections]) {
        [_rows addObject:[NSString stringWithFormat:@"%@ (%lu)",
            [section name], (unsigned long)[section numberOfObjects]]];
        [_rows addObjectsFromArray:[section objects]];
    }

    [_tableView reloadData];
}

- (NSManagedObject *)selectedEmployee
{
    NSInteger row = [_tableView selectedRow];

    if (row < 0 || row >= (NSInteger)[_rows count])
        return nil;

    id entry = [_rows objectAtIndex:row];

    return [entry isKindOfClass:[NSManagedObject class]] ? entry : nil;
}

/* ------------------------------------------------------------------
   NSTableViewDataSource / NSTableViewDelegate
   ------------------------------------------------------------------ */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_rows count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
    row:(NSInteger)row
{
    id entry = [_rows objectAtIndex:row];
    NSString *identifier = [column identifier];

    if ([entry isKindOfClass:[NSString class]])
        return [identifier isEqualToString:@"name"] ? entry : @"";

    NSManagedObject *employee = entry;

    if ([identifier isEqualToString:@"name"]) {
        /* The transient fullName attribute is computed by the custom
           accessor -[EDPerson fullName]; -valueForKey: dispatches to it. */
        return [NSString stringWithFormat:@"    %@", [employee valueForKey:@"fullName"]];
    }
    if ([identifier isEqualToString:@"salary"])
        return [employee valueForKey:@"salary"];
    if ([identifier isEqualToString:@"projects"]) {
        NSMutableArray *names = [NSMutableArray array];

        for (NSManagedObject *project in [employee valueForKey:@"projects"])
            [names addObject:[project valueForKey:@"name"]];

        [names sortUsingSelector:@selector(compare:)];
        return [names componentsJoinedByString:@", "];
    }
    return @"";
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    /* Section header rows are not selectable. */
    return [[_rows objectAtIndex:row] isKindOfClass:[NSManagedObject class]];
}

/* ------------------------------------------------------------------
   NSFetchedResultsControllerDelegate
   ------------------------------------------------------------------ */
- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller
{
    [self log:@"[delegate] will change content"];
}

- (void)controller:(NSFetchedResultsController *)controller
  didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex
     forChangeType:(NSFetchedResultsChangeType)type
{
    [self log:@"[delegate] section '%@' %@ at %lu", [sectionInfo name],
        describeChangeType(type), (unsigned long)sectionIndex];
}

- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath
{
    [self log:@"[delegate] object %@ %@ (%@ -> %@)",
        [anObject valueForKey:@"lastName"], describeChangeType(type),
        describeIndexPath(indexPath), describeIndexPath(newIndexPath)];
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    [self log:@"[delegate] did change content"];
    [self rebuildRows];
}

/* ------------------------------------------------------------------
   Actions, one per usage scenario
   ------------------------------------------------------------------ */
- (void)addEmployee:(id)sender
{
    static const char *names[][2] = {
        {"Frank", "Fisher"}, {"Grace", "Green"}, {"Henry", "Hill"},
        {"Irene", "Irwin"}, {"Jack", "Jones"}, {"Karen", "Kent"},
    };
    NSUInteger index = _employeeCounter++ % (sizeof(names) / sizeof(names[0]));
    NSString *firstName = [NSString stringWithUTF8String:names[index][0]];
    NSString *lastName = [NSString stringWithFormat:@"%s%@",
        names[index][1],
        _employeeCounter > 6 ? [NSString stringWithFormat:@" %lu", (unsigned long)_employeeCounter] : @""];

    [self log:@"\n-- %@ %@ joins Engineering --", firstName, lastName];

    NSManagedObject *employee = [self insert:@"Employee"];

    [employee setValue:firstName forKey:@"firstName"];
    [employee setValue:lastName forKey:@"lastName"];
    [employee setValue:[NSNumber numberWithInt:3900] forKey:@"salary"];
    [employee setValue:[self departmentNamed:@"Engineering"] forKey:@"department"];
    [_context processPendingChanges];
}

- (void)moveDepartment:(id)sender
{
    NSManagedObject *employee = [self selectedEmployee];

    if (employee == nil) {
        [self log:@"\nselect an employee first"];
        return;
    }

    /* To-one relationship: reassign the employee's department. */
    NSString *currentName = [employee valueForKeyPath:@"department.name"];
    NSString *newName = [currentName isEqualToString:@"Engineering"] ? @"Sales" : @"Engineering";

    [self log:@"\n-- %@ moves to %@ --", [employee valueForKey:@"fullName"], newName];
    [employee setValue:[self departmentNamed:newName] forKey:@"department"];
    [_context processPendingChanges];
}

- (void)giveRaise:(id)sender
{
    NSManagedObject *employee = [self selectedEmployee];

    if (employee == nil) {
        [self log:@"\nselect an employee first"];
        return;
    }

    NSNumber *salary = [employee valueForKey:@"salary"];

    [self log:@"\n-- %@ gets a raise --", [employee valueForKey:@"fullName"]];
    [employee setValue:[NSNumber numberWithInt:[salary intValue] + 100] forKey:@"salary"];
    [_context processPendingChanges];
}

- (void)deleteEmployee:(id)sender
{
    NSManagedObject *employee = [self selectedEmployee];

    if (employee == nil) {
        [self log:@"\nselect an employee first"];
        return;
    }

    [self log:@"\n-- %@ leaves the company --", [employee valueForKey:@"fullName"]];
    [_context deleteObject:employee];
    [_context processPendingChanges];
}

- (void)runValidationDemo:(id)sender
{
    NSError *error = nil;

    [self log:@"\n== validation =="];

    NSManagedObject *invalid = [self insert:@"Employee"];

    [invalid setValue:@"Eve" forKey:@"firstName"];
    [invalid setValue:[NSNumber numberWithInt:-1] forKey:@"salary"];

    if (![_context save:&error])
        [self log:@"rejected (missing lastName, negative salary): %@",
            [error localizedDescription]];

    [invalid setValue:@"Evans" forKey:@"lastName"];
    [invalid setValue:[NSNumber numberWithInt:4321] forKey:@"salary"];
    error = nil;

    if (![_context save:&error])
        [self log:@"rejected (custom -validateSalary:error:): %@",
            [error localizedDescription]];

    [invalid setValue:[NSNumber numberWithInt:4300] forKey:@"salary"];
    [invalid setValue:[self departmentNamed:@"Sales"] forKey:@"department"];
    error = nil;

    if ([_context save:&error])
        [self log:@"accepted after fixing the values"];
    else
        [self log:@"unexpected save failure: %@", error];
}

- (void)saveContext:(id)sender
{
    NSError *error = nil;

    if ([_context save:&error])
        [self log:@"\nsaved to %@", _storePath];
    else
        [self log:@"\nsave failed: %@", error];
}

- (void)reloadFromStore:(id)sender
{
    [self log:@"\n== reopening the store =="];

    NSManagedObjectContext *reopened = [[self makeContext] retain];

    if (reopened == nil)
        return;

    [_context release];
    _context = reopened;

    [self makeFetchedResultsController];
    [self rebuildRows];
    [self showPeople:nil];
}

- (void)showPeople:(id)sender
{
    [self log:@"\n== every Person (inheritance) =="];

    NSArray *sort = [NSArray arrayWithObject:
        [[[NSSortDescriptor alloc] initWithKey:@"lastName" ascending:YES] autorelease]];

    for (EDPerson *person in [self fetch:@"Person" predicate:nil
                              sortDescriptors:sort inContext:_context])
        [self log:@"  %@", [person shortDescription]];
}

- (void)showProjects:(id)sender
{
    [self log:@"\n== many-to-many =="];

    for (NSManagedObject *project in [self fetch:@"Project" predicate:nil
                                      sortDescriptors:nil inContext:_context]) {
        NSMutableArray *names = [NSMutableArray array];

        for (EDPerson *member in [project valueForKey:@"members"])
            [names addObject:[member valueForKey:@"fullName"]];

        [names sortUsingSelector:@selector(compare:)];
        [self log:@"  %@: %@", [project valueForKey:@"name"],
            [names componentsJoinedByString:@", "]];
    }
}

/* ------------------------------------------------------------------
   User interface
   ------------------------------------------------------------------ */
- (NSTableColumn *)columnWithIdentifier:(NSString *)identifier
                                  title:(NSString *)title
                                  width:(CGFloat)width
{
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:identifier] autorelease];

    [[column headerCell] setStringValue:title];
    [column setWidth:width];
    [column setEditable:NO];

    return column;
}

- (NSButton *)buttonWithTitle:(NSString *)title
                       action:(SEL)action
                        frame:(NSRect)frame
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];

    [button setTitle:title];
    /* The pre-10.14 constant name works on GNUstep and on macOS alike. */
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:self];
    [button setAction:action];
    [button setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];

    return button;
}

- (void)buildWindow
{
    NSRect contentRect = NSMakeRect(120, 120, 980, 620);

    _window = [[NSWindow alloc] initWithContentRect:contentRect
                                styleMask:NSWindowStyleMaskTitled |
                                          NSWindowStyleMaskClosable |
                                          NSWindowStyleMaskMiniaturizable |
                                          NSWindowStyleMaskResizable
                                backing:NSBackingStoreBuffered
                                defer:NO];
    [_window setTitle:@"Employee Directory — GNUstep CoreData example"];
    [_window setReleasedWhenClosed:NO];

    NSView *content = [_window contentView];
    NSRect bounds = [content bounds];
    CGFloat buttonRowHeight = 76;
    CGFloat tableWidth = bounds.size.width * 0.55;

    /* Employee table, driven by the fetched results controller. */
    _tableView = [[[NSTableView alloc] initWithFrame:NSZeroRect] autorelease];
    [_tableView addTableColumn:[self columnWithIdentifier:@"name" title:@"Employee" width:220]];
    [_tableView addTableColumn:[self columnWithIdentifier:@"salary" title:@"Salary" width:80]];
    [_tableView addTableColumn:[self columnWithIdentifier:@"projects" title:@"Projects" width:160]];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setAllowsEmptySelection:YES];

    NSScrollView *tableScroll = [[[NSScrollView alloc] initWithFrame:
        NSMakeRect(10, buttonRowHeight,
                   tableWidth - 15, bounds.size.height - buttonRowHeight - 10)] autorelease];

    [tableScroll setDocumentView:_tableView];
    [tableScroll setHasVerticalScroller:YES];
    [tableScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview:tableScroll];

    /* Log of fetched results controller callbacks and scenario output. */
    NSRect logFrame = NSMakeRect(tableWidth + 5, buttonRowHeight,
        bounds.size.width - tableWidth - 15, bounds.size.height - buttonRowHeight - 10);

    _logView = [[[NSTextView alloc] initWithFrame:logFrame] autorelease];
    [_logView setEditable:NO];
    [_logView setFont:[NSFont userFixedPitchFontOfSize:11]];
    [_logView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    NSScrollView *logScroll = [[[NSScrollView alloc] initWithFrame:logFrame] autorelease];

    [logScroll setDocumentView:_logView];
    [logScroll setHasVerticalScroller:YES];
    [logScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_logView setFrame:[[logScroll contentView] bounds]];
    [content addSubview:logScroll];

    /* Two rows of scenario buttons. */
    struct { NSString *title; SEL action; } buttons[] = {
        { @"Add Employee", @selector(addEmployee:) },
        { @"Move Department", @selector(moveDepartment:) },
        { @"Give Raise", @selector(giveRaise:) },
        { @"Delete Employee", @selector(deleteEmployee:) },
        { @"Validation Demo", @selector(runValidationDemo:) },
        { @"Save", @selector(saveContext:) },
        { @"Reload From Store", @selector(reloadFromStore:) },
        { @"List People", @selector(showPeople:) },
        { @"List Projects", @selector(showProjects:) },
    };
    NSUInteger count = sizeof(buttons) / sizeof(buttons[0]);
    NSUInteger perRow = 5;
    CGFloat buttonWidth = 140, buttonHeight = 28;

    for (NSUInteger i = 0; i < count; i++) {
        NSRect frame = NSMakeRect(10 + (i % perRow) * (buttonWidth + 6),
                                  (i / perRow) ? 8 : 8 + buttonHeight + 4,
                                  buttonWidth, buttonHeight);

        [content addSubview:[self buttonWithTitle:buttons[i].title
                                  action:buttons[i].action
                                  frame:frame]];
    }
}

/* ------------------------------------------------------------------
   NSApplicationDelegate
   ------------------------------------------------------------------ */
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    _rows = [[NSMutableArray alloc] init];
    _storePath = [[NSTemporaryDirectory()
        stringByAppendingPathComponent:@"EmployeeDirectory.sqlite"] copy];

    /* Always start from an empty store so the demo is repeatable. */
    NSFileManager *fileManager = [NSFileManager defaultManager];

    [fileManager removeItemAtPath:_storePath error:NULL];
    [fileManager removeItemAtPath:[_storePath stringByAppendingString:@"-wal"] error:NULL];
    [fileManager removeItemAtPath:[_storePath stringByAppendingString:@"-shm"] error:NULL];

    _model = [EmployeeDirectoryModel() retain];
    _context = [[self makeContext] retain];

    [self buildWindow];
    [self log:@"Employee directory stored at %@", _storePath];

    [self seedStore];
    [self makeFetchedResultsController];
    [self rebuildRows];
    [self showPeople:nil];
    [self showProjects:nil];

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application
{
    return YES;
}

@end
