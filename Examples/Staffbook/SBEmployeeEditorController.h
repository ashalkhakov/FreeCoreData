/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

/* The editor is an application transaction, built on a parent/child
 * context pair: everything in the panel - the employee's fields AND any
 * reviews added or removed underneath it - happens in a child context
 * whose parent is the viewContext.  Save pushes the whole edit up in one
 * child save and to disk in one parent save; Cancel throws the child away
 * and the viewContext never learns any of it happened.
 *
 * The bindings live in EmployeeEditor.xib: the fields bind to the object
 * controller's selection, the reviews table to an array controller whose
 * contentSet is the selection's reviews set.  Code only puts the child
 * context's employee into the object controller - from there every
 * keystroke edits the transaction, with no copy-in/copy-out at all. */
@interface SBEmployeeEditorController : NSWindowController <NSTableViewDelegate>

@property (nonatomic, strong) IBOutlet NSObjectController *employeeController;
@property (nonatomic, strong) IBOutlet NSArrayController *reviewsController;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSComboBox *departmentBox;
@property (nonatomic, strong) IBOutlet NSTextField *salaryField;

/* Dates are edited with NSDatePickers - GNUstep's text-cell date
 * editing is not dependable, its picker is.  Both pickers are BOUND:
 * the hire date through the object controller's selection.hireDate,
 * the review date through the reviews array controller's
 * selection.date, following the table selection.  On GNUstep the
 * array-controller half (and the canRemove enabled bindings) needs
 * the carried selection-KVO patch - see
 * patches/gnustep/gnustep-gui-arraycontroller-selection-kvo.patch and
 * the repro beside it. */
@property (nonatomic, strong) IBOutlet NSDatePicker *hireDatePicker;
@property (nonatomic, strong) IBOutlet NSDatePicker *reviewDatePicker;
@property (nonatomic, strong) IBOutlet NSTableView *reviewsTable;
@property (nonatomic, strong) IBOutlet NSButton *addReviewButton;
@property (nonatomic, strong) IBOutlet NSButton *removeReviewButton;
@property (nonatomic, strong) IBOutlet NSButton *saveButton;
@property (nonatomic, strong) IBOutlet NSButton *cancelButton;

/* employeeID nil means "add": the child context inserts the employee, and
 * nothing exists anywhere until Save. */
- (instancetype)initWithParentContext:(NSManagedObjectContext *)parentContext
                           employeeID:(NSManagedObjectID *)employeeID;

/* Shows the panel modally; YES when saved. */
- (BOOL)runModal;

- (IBAction)addReview:(id)sender;
- (IBAction)removeReview:(id)sender;
- (IBAction)reviewDateChanged:(id)sender;
- (IBAction)save:(id)sender;
- (IBAction)cancel:(id)sender;

@end
