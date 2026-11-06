/* UDCode's Core Data extension — a mapping model's tab (MBUMappingEditor.xib):
   ModelBuilder's mapping parts over a mapping editor of the model's
   xcmapping.xml, spread over the window's panes as an Xcode editor's are
   (UDEditorPanes): the entity mappings and the selected one's property
   mappings in the tab; the inspector's two pages, Identity and Type and the
   selection's, tabs of the inspector pane.  The models it
   maps between are found by the paths the file records, from where the
   mapping model is, as Xcode finds them.

   The text is the mapping, as a model's tab's text is its model (see
   MBUModelEditorViewController.h): each change one edit of the text, the
   text's undo the undo, a text changed some other way read again.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDWorkbench.h>
#import <UDCodeKit/UDEditorPanes.h>

@class UDCodeDocument, MBMappingEditor, MBMappingSourceListViewController, MBMappingDetailViewController,
    MBMappingInspectorViewController;

@interface MBUMappingEditorViewController : NSViewController <UDEditorPanes, NSSplitViewDelegate>

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench;

@property (nonatomic, readonly, strong) UDCodeDocument *document;
/* The mapping editor, made for the first text that is a mapping model whose
   models are found; nil until then. */
@property (nonatomic, readonly, strong) MBMappingEditor *mappingEditor;
/* Why the text cannot be shown, while it cannot; nil while it can. */
@property (nonatomic, readonly, copy) NSString *problem;

@property (nonatomic, readonly, strong) MBMappingSourceListViewController *sourceListController;
@property (nonatomic, readonly, strong) MBMappingDetailViewController *detailController;
/* The inspector's pages: Identity and Type (the two models), and the
   selection's. */
@property (nonatomic, readonly, strong) MBMappingInspectorViewController *identityInspector;
@property (nonatomic, readonly, strong) MBMappingInspectorViewController *inspectorController;

- (void)write;

/* The Editor menu (MBUEditorMenus.xib). */
- (IBAction)addEntityMapping:(id)sender;
- (IBAction)removeEntityMapping:(id)sender;
- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;
- (IBAction)showAsText:(id)sender;

@end
