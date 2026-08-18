/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

/* The application delegate: owns the CoreData stack, the window and the
   fetched results controller that drives the employee table.  Every
   button in the window exercises one usage scenario of the framework. */
@interface EDAppDelegate : NSObject
    <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate,
     NSFetchedResultsControllerDelegate>
{
    NSManagedObjectModel *_model;
    NSManagedObjectContext *_context;
    NSFetchedResultsController *_controller;
    NSString *_storePath;

    NSWindow *_window;
    NSTableView *_tableView;
    NSTextView *_logView;

    /* One entry per table row: an NSString for a section header row or
       the NSManagedObject shown on that row. */
    NSMutableArray *_rows;
    NSUInteger _employeeCounter;
}

- (void)addEmployee:(id)sender;
- (void)moveDepartment:(id)sender;
- (void)giveRaise:(id)sender;
- (void)deleteEmployee:(id)sender;
- (void)runValidationDemo:(id)sender;
- (void)saveContext:(id)sender;
- (void)reloadFromStore:(id)sender;
- (void)showPeople:(id)sender;
- (void)showProjects:(id)sender;

@end
