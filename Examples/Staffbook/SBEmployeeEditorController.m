/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import "SBEmployeeEditorController.h"
#import "SBManagedObjects.h"

@implementation SBEmployeeEditorController
{
    NSManagedObjectContext *_parentContext;
    NSManagedObjectContext *_childContext;
    NSManagedObjectID *_employeeID;
    SBEmployee *_employee;          /* lives in _childContext */
    BOOL _saved;
}

- (instancetype)initWithParentContext:(NSManagedObjectContext *)parentContext
                           employeeID:(NSManagedObjectID *)employeeID
{
    if ((self = [super initWithWindowNibName:@"EmployeeEditor"])) {
        _parentContext = parentContext;
        _employeeID = employeeID;
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    /* The transaction: a main-queue child of the viewContext.  Its saves
     * land in the parent as pending changes; only the parent's own save
     * touches the store. */
    _childContext = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [_childContext setParentContext:_parentContext];

    if (_employeeID != nil) {
        _employee = (SBEmployee *)[_childContext objectWithID:_employeeID];
        [[self window] setTitle:@"Edit Employee"];
    }
    else {
        _employee = [NSEntityDescription insertNewObjectForEntityForName:@"Employee"
                                                  inManagedObjectContext:_childContext];
        _employee.hireDate = [NSDate date];
        [[self window] setTitle:@"New Employee"];
    }

    /* The bindings live in the XIB; the code's whole job is to point the
     * object controller at the child context's employee.  From here on
     * every keystroke edits the transaction, never the viewContext, and
     * the reviews array controller follows through its contentSet
     * binding to selection.reviews. */
    NSNumberFormatter *money = [[NSNumberFormatter alloc] init];
    [money setNumberStyle:NSNumberFormatterDecimalStyle];
    [money setMaximumFractionDigits:0];
    [self.salaryField setFormatter:money];

    NSDateFormatter *day = [[NSDateFormatter alloc] init];
    [day setDateFormat:@"yyyy-MM-dd"];
    [self.hireDateField setFormatter:day];
    [[[self.reviewsTable tableColumnWithIdentifier:@"date"] dataCell] setFormatter:day];

    [self.departmentBox removeAllItems];
    [self.departmentBox addItemsWithObjectValues:SBDepartments()];

    [self.reviewsController setSortDescriptors:
        @[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO]]];

    [self.employeeController setContent:_employee];
}

- (BOOL)runModal
{
    _saved = NO;
    [NSApp runModalForWindow:[self window]];
    [[self window] orderOut:self];
    return _saved;
}

- (IBAction)addReview:(id)sender
{
    SBReview *review = [NSEntityDescription insertNewObjectForEntityForName:@"Review"
                                                     inManagedObjectContext:_childContext];

    review.date = [NSDate date];
    review.rating = @3;
    review.summary = @"";
    [[_employee mutableSetValueForKey:@"reviews"] addObject:review];
    [self.reviewsController rearrangeObjects];
}

- (IBAction)removeReview:(id)sender
{
    for (SBReview *review in [self.reviewsController selectedObjects]) {
        [[_employee mutableSetValueForKey:@"reviews"] removeObject:review];
        [_childContext deleteObject:review];
    }
    [self.reviewsController rearrangeObjects];
}

- (IBAction)save:(id)sender
{
    /* Commit pending field editing so the last keystroke is in the
     * transaction before it is pushed. */
    [[self window] makeFirstResponder:nil];
    [self.employeeController commitEditing];
    [self.reviewsController commitEditing];

    if ([[_employee.name stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]] length] == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"An employee needs a name."];
        [alert runModal];
        return;
    }

    /* The application transaction commits: one child save moves the
     * employee and every review into the viewContext, one parent save
     * writes it all to the store together. */
    NSError *error = nil;

    if (![_childContext save:&error]) {
        NSLog(@"Staffbook: child save failed: %@", error);
        [NSApp stopModal];
        return;
    }
    if (![_parentContext save:&error]) {
        NSLog(@"Staffbook: parent save failed: %@", error);
        [NSApp stopModal];
        return;
    }

    _saved = YES;
    [NSApp stopModal];
}

- (IBAction)cancel:(id)sender
{
    /* Nothing to undo anywhere: the child context simply goes away. */
    [NSApp stopModal];
}

@end
