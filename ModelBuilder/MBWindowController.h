/* ModelBuilder document window — Xcode's three panes, each a part with a
   XIB of its own, assembled in MBDocumentWindow.xib's split views: the
   source list (MBSourceListViewController), the centre
   (MBDetailViewController) over the button bar's "+/− Entity" and
   "+/− Attribute", and the inspector (MBInspectorViewController).  They
   work through the document's model editor, its selection and its change
   notices; this controller only puts them in place, and has what is the
   window's: the Model menu's versions, validation, compilation and class
   generation, the title, the undo manager, the split views' rule.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@class MBModelEditor, MBSourceListViewController, MBDetailViewController, MBInspectorViewController;

@interface MBWindowController : NSWindowController <NSSplitViewDelegate, NSWindowDelegate>

/* The panes the parts' views go in. */
@property (nonatomic, strong) IBOutlet NSView *sourceListHost;
@property (nonatomic, strong) IBOutlet NSView *detailHost;
@property (nonatomic, strong) IBOutlet NSView *inspectorHost;

/* Bottom bar */
@property (nonatomic, strong) IBOutlet NSSegmentedControl *entitySegmentedControl;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *propertySegmentedControl;

@property (nonatomic, strong, readonly) MBSourceListViewController *sourceListController;
@property (nonatomic, strong, readonly) MBDetailViewController *detailController;
@property (nonatomic, strong, readonly) MBInspectorViewController *inspectorController;

/* The edited version's editor (the document's). */
@property (nonatomic, readonly) MBModelEditor *modelEditor;

/* The bar's +/−: an entity, fetch request or configuration; an attribute
   or relationship. */
- (IBAction)sourceSegmentClicked:(id)sender;
- (IBAction)propertySegmentClicked:(id)sender;

@end
