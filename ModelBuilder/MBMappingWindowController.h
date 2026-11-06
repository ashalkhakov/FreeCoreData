/* ModelBuilder mapping window — the editor for an .xcmappingmodel, laid
   out as the model window is and as Xcode's mapping editor is: the source
   list of entity mappings on the left (MBMappingSourceListViewController),
   with "+/− Mapping" underneath; the selected mapping's property mappings
   in the centre (MBMappingDetailViewController); the inspector on the
   right (MBMappingInspectorViewController).  Each part has its own xib and
   works through the document's MBMappingEditor, whose selection they
   share; this only puts them in place (MBMappingWindow.xib's hosts) and
   holds the side panes at their size.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@class MBMappingDocument, MBMappingEditor, MBMappingSourceListViewController,
    MBMappingDetailViewController, MBMappingInspectorViewController;

@interface MBMappingWindowController : NSWindowController <NSSplitViewDelegate, NSWindowDelegate>

- (instancetype)init;

- (MBMappingDocument *)mappingDocument;
- (MBMappingEditor *)mappingEditor;

/* Where the parts go, and the parts. */
@property (nonatomic, strong) IBOutlet NSView *sourceListHost;
@property (nonatomic, strong) IBOutlet NSView *detailHost;
@property (nonatomic, strong) IBOutlet NSView *inspectorHost;
@property (nonatomic, strong, readonly) MBMappingSourceListViewController *sourceListController;
@property (nonatomic, strong, readonly) MBMappingDetailViewController *detailController;
@property (nonatomic, strong, readonly) MBMappingInspectorViewController *inspectorController;

/* Bottom bar: segment 0 adds a mapping, segment 1 removes the selected one. */
@property (nonatomic, strong) IBOutlet NSSegmentedControl *entityMappingSegmentedControl;
- (IBAction)entityMappingSegmentClicked:(id)sender;

@end
