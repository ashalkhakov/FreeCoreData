/* ModelBuilder — the mapping window's centre (MBMappingDetail.xib): the
   selected entity mapping's attribute mappings and relationship mappings,
   each a collapsible section holding a table of destination property
   against the expression that fills it (columns "property" and
   "expression", the second editable).  A row for each property of the
   destination entity, whether anything fills it yet or not.  A row picked
   is the mapping editor's selection.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@class MBMappingEditor, JUInspectorView, JUInspectorViewContainer;

@interface MBMappingDetailViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)init;

@property (nonatomic, strong) MBMappingEditor *mappingEditor;

@property (nonatomic, strong) IBOutlet JUInspectorViewContainer *mappingInspectorContainer;
@property (nonatomic, strong) IBOutlet JUInspectorView *attributesInspector;
@property (nonatomic, strong) IBOutlet JUInspectorView *relationshipsInspector;
@property (nonatomic, strong) IBOutlet NSTableView *attributeMappingTable;
@property (nonatomic, strong) IBOutlet NSTableView *relationshipMappingTable;

/* What the tables show, as it is now. */
- (void)reload;

@end
