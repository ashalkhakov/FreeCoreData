/* ModelBuilder mapping window — the editor for an .xcmappingmodel, whose
   layout lives in MBMappingWindow.xib (one xib serving both toolkits;
   GNUstep loads it through GSXib5), as the model window's lives in
   MBDocumentWindow.xib.

   Left: ENTITY MAPPINGS, with +/− underneath.  Right: the predicate that
   narrows the selected mapping, then its attribute mappings and its
   relationship mappings — each a table of destination property against
   the expression that fills it, an empty cell meaning the one the
   compiler works out.  Bottom: the two models being mapped between.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class MBMappingDocument;

@interface MBMappingWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>

/* Left pane: one row per entity mapping, column "name". */
@property (nonatomic, strong) IBOutlet NSTableView *entityMappingTable;

/* Bottom bar: segment 0 adds a mapping, segment 1 removes the selected
   one (as the model window's entity control does). */
@property (nonatomic, strong) IBOutlet NSSegmentedControl *entityMappingSegmentedControl;

/* Right pane.  The two tables have the columns "property" (the
   destination property, not editable) and "expression" (editable). */
@property (nonatomic, strong) IBOutlet NSTextField *filterPredicateField;
@property (nonatomic, strong) IBOutlet NSTableView *attributeMappingTable;
@property (nonatomic, strong) IBOutlet NSTableView *relationshipMappingTable;

/* Bottom bar: the models, by the names the file records. */
@property (nonatomic, strong) IBOutlet NSTextField *sourceModelLabel;
@property (nonatomic, strong) IBOutlet NSTextField *destinationModelLabel;

@property (nonatomic, readonly) NSEntityMapping *selectedEntityMapping;

- (MBMappingDocument *)mappingDocument;
- (void)reload;

- (IBAction)entityMappingSegmentClicked:(id)sender;
- (IBAction)addEntityMapping:(id)sender;
- (IBAction)removeEntityMapping:(id)sender;
- (IBAction)takeFilterPredicateFrom:(id)sender;

@end
