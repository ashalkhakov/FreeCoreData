/* ModelBuilder — the mapping window's left pane (MBMappingSourceList.xib):
   ENTITY MAPPINGS, a row per mapping, renamed in place.  It shows the
   mapping editor's selection and sets it: a row picked is that mapping
   selected, and picked again while one of its property rows is, the
   mapping itself again.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@class MBMappingEditor;

@interface MBMappingSourceListViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

- (instancetype)init;

@property (nonatomic, strong) MBMappingEditor *mappingEditor;
@property (nonatomic, strong) IBOutlet NSOutlineView *sourceList;

/* What the list shows, as it is now. */
- (void)reload;

/* A mapping pairing the first entity of each model (a pairing to correct
   in the inspector, rather than a question to answer first), selected;
   the selected one removed, its neighbour selected. */
- (IBAction)addEntityMapping:(id)sender;
- (IBAction)removeEntityMapping:(id)sender;

@end
