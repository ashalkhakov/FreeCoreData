/* UDCode's Core Data extension — a model version's tab (MBUModelEditor.xib):
   ModelBuilder's parts over a model editor of the version's `contents`,
   spread over the window's panes as an Xcode editor's are (UDEditorPanes):
   the source list (entities, fetch requests, configurations) and the
   selection's page in the tab; the inspector's two pages, the model's
   (its version identifier) and the selection's, tabs of the inspector pane.

   The text is the model.  Each change made in the parts is written back as
   one edit of the text (the lines it changed), so the text's undo undoes
   it; saving and the tab's dot are the document's; a diff shows what
   changed.  The model editor records no undo of its own.  When the text
   changes some other way (undone, edited as text, reverted) it is read
   again, the selection kept where it still is.  A text that is no model
   shows why, and offers it as text.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDWorkbench.h>
#import <UDCodeKit/UDEditorPanes.h>

@class UDCodeDocument, MBModelEditor, MBSourceListViewController, MBDetailViewController,
    MBInspectorViewController;

@interface MBUModelEditorViewController : NSViewController <UDEditorPanes, NSSplitViewDelegate>

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench;

@property (nonatomic, readonly, strong) UDCodeDocument *document;
/* The model editor, made for the first text that is a model; nil until then. */
@property (nonatomic, readonly, strong) MBModelEditor *modelEditor;
/* Why the text is no model, while it is not; nil while it is. */
@property (nonatomic, readonly, copy) NSString *problem;

@property (nonatomic, readonly, strong) MBSourceListViewController *sourceListController;
@property (nonatomic, readonly, strong) MBDetailViewController *detailController;
/* The inspector's pages: the model's, and the selection's. */
@property (nonatomic, readonly, strong) MBInspectorViewController *modelInspector;
@property (nonatomic, readonly, strong) MBInspectorViewController *inspectorController;

/* The text written now, if a change is waiting (it is written as the event
   that made it ends). */
- (void)write;

/* The Editor menu (MBUEditorMenus.xib). */
- (IBAction)addEntity:(id)sender;
- (IBAction)addAttribute:(id)sender;
- (IBAction)addRelationship:(id)sender;
- (IBAction)addFetchRequest:(id)sender;
- (IBAction)addConfiguration:(id)sender;
- (IBAction)addFetchIndex:(id)sender;
- (IBAction)removeEntity:(id)sender;
- (IBAction)validateModel:(id)sender;
- (IBAction)createManagedObjectSubclass:(id)sender;
/* The document's text's undo, which every change of the model is part of. */
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
/* The document in a tab of its own, as XML. */
- (IBAction)showAsText:(id)sender;

@end
