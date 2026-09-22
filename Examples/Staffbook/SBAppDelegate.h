/*
 * This file is part of Staffbook, the FreeCoreData example application.
 * Copyright (c) 2026 the GNUstep CoreData port contributors.
 * Released under the MIT license; see the repository's LICENSE.
 */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class SBEmployeeWindowController;

/* Staffbook is a small employee roster whose entire point is to exercise
 * FreeCoreData's modern API surface, one feature per place:
 *
 *   NSPersistentContainer      here, standing up the whole stack
 *   list + filter + sort       SBEmployeeWindowController, Cocoa bindings
 *                              through an NSArrayController
 *   parent/child contexts      SBEmployeeEditorController: the editor is a
 *                              child context saved into the viewContext in
 *                              one go (an application transaction)
 *   batch requests             the Data menu / toolbar actions: sample data
 *                              by batch insert, department moves by batch
 *                              update, "delete shown" by batch delete, each
 *                              followed by mergeChangesFromRemoteContextSave:
 *   asynchronous fetches       the department chart refreshes through an
 *                              NSAsynchronousFetchRequest
 */
@interface SBAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong, readonly) NSPersistentContainer *container;
@property (nonatomic, strong, readonly) SBEmployeeWindowController *employeeWindowController;

@end
