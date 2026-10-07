/* ModelBuilder mapping window — the editor for an .xcmappingmodel, laid
   out as the model window is and as Xcode's mapping editor is, with its
   layout in MBMappingWindow.xib (one xib serving both toolkits; GNUstep
   loads it through GSXib5).

   Left: ENTITY MAPPINGS, with "+/− Mapping" underneath.  Center: the
   selected entity mapping — its attribute mappings and its relationship
   mappings, each a collapsible section holding a table of destination
   property against the expression that fills it.  Right: DMTabBar over
   the inspector — Identity and Type (the two models), and the mapping
   inspector, whose page follows the selection: the entity mapping when a
   mapping is selected in the list, an attribute or relationship mapping
   when a row is selected in the center.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class MBMappingDocument, JUInspectorView, JUInspectorViewContainer, DMTabBar;

/* The pages of the two inspector tab views, in xib order. */
typedef NS_ENUM(NSInteger, MBMappingInspectorPage) {
  MBMappingInspectorPageIdentity = 0,
  MBMappingInspectorPageMapping = 1,
};
typedef NS_ENUM(NSInteger, MBMappingInspectorKind) {
  MBMappingInspectorKindEntity = 0,
  MBMappingInspectorKindAttribute = 1,
  MBMappingInspectorKindRelationship = 2,
};

@interface MBMappingWindowController : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSplitViewDelegate, NSWindowDelegate>

/* Left pane: the ENTITY MAPPINGS group and a row per mapping, column
   "name" (a mapping is renamed in place). */
@property (nonatomic, strong) IBOutlet NSOutlineView *sourceList;

/* Bottom bar: segment 0 adds a mapping, segment 1 removes the selected one. */
@property (nonatomic, strong) IBOutlet NSSegmentedControl *entityMappingSegmentedControl;

/* Center pane.  The two tables have the columns "property" (the
   destination property) and "expression" (what fills it; editable). */
@property (nonatomic, strong) IBOutlet JUInspectorViewContainer *mappingInspectorContainer;
@property (nonatomic, strong) IBOutlet JUInspectorView *attributesInspector;
@property (nonatomic, strong) IBOutlet JUInspectorView *relationshipsInspector;
@property (nonatomic, strong) IBOutlet NSTableView *attributeMappingTable;
@property (nonatomic, strong) IBOutlet NSTableView *relationshipMappingTable;

/* Inspector chrome. */
@property (nonatomic, strong) IBOutlet DMTabBar *inspectorTabBar;
@property (nonatomic, strong) IBOutlet NSTabView *inspectorTabView;      /* Identity | Mapping */
@property (nonatomic, strong) IBOutlet NSTabView *inspectorKindTabView;  /* Entity | Attribute | Relationship */

/* Identity and Type: the models, by the paths the file records. */
@property (nonatomic, strong) IBOutlet NSTextField *sourceModelLabel;
@property (nonatomic, strong) IBOutlet NSTextField *destinationModelLabel;

/* Entity mapping inspector. */
@property (nonatomic, strong) IBOutlet NSTextField *entityMappingNameField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *sourceEntityPopup;
@property (nonatomic, strong) IBOutlet NSPopUpButton *destinationEntityPopup;
@property (nonatomic, strong) IBOutlet NSTextField *mappingTypeLabel;
@property (nonatomic, strong) IBOutlet NSTextField *customPolicyField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *sourceFetchPopup;          /* Default | Custom */
@property (nonatomic, strong) IBOutlet NSTextField *filterPredicateField;
@property (nonatomic, strong) IBOutlet NSTableView *entityUserInfoTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *entityUserInfoSegmentedControl;

/* Attribute mapping inspector. */
@property (nonatomic, strong) IBOutlet NSPopUpButton *attributeNamePopup;
@property (nonatomic, strong) IBOutlet NSTextField *attributeExpressionField;
@property (nonatomic, strong) IBOutlet NSTableView *attributeUserInfoTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *attributeUserInfoSegmentedControl;

/* Relationship mapping inspector. */
@property (nonatomic, strong) IBOutlet NSPopUpButton *relationshipNamePopup;
@property (nonatomic, strong) IBOutlet NSPopUpButton *relationshipSourceFetchPopup; /* Auto Generate | Custom */
@property (nonatomic, strong) IBOutlet NSTextField *relationshipKeyPathField;
@property (nonatomic, strong) IBOutlet NSTextField *relationshipMappingNameField;
@property (nonatomic, strong) IBOutlet NSTextField *relationshipExpressionField;
@property (nonatomic, strong) IBOutlet NSTableView *relationshipUserInfoTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *relationshipUserInfoSegmentedControl;

/* What is selected: an entity mapping, and within it perhaps one of its
   property mappings (nil while the entity mapping itself is inspected). */
@property (nonatomic, readonly) NSEntityMapping *selectedEntityMapping;
@property (nonatomic, readonly) NSPropertyMapping *selectedPropertyMapping;

- (MBMappingDocument *)mappingDocument;
- (void)reload;
- (void)selectEntityMapping:(NSEntityMapping *)mapping;

- (IBAction)entityMappingSegmentClicked:(id)sender;
- (IBAction)addEntityMapping:(id)sender;
- (IBAction)removeEntityMapping:(id)sender;
- (IBAction)inspectorChanged:(id)sender;
- (IBAction)inspectorTabSelected:(id)sender;
- (IBAction)userInfoSegmentClicked:(id)sender;

@end
