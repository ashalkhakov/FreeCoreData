/* ModelBuilder — the mapping window's inspector (MBMappingInspector.xib):
   a DMTabBar over Identity and Type (the two models, by the paths the file
   records) and the mapping inspector, whose page follows the selection:
   the entity mapping's, or an attribute or relationship row's.  Each page's
   fields are bound in the XIB to its editor controller (an
   NSObjectController there), whose content is the selection's editor
   (MBMappingEditors).  What is left to code: which page shows, the user
   info tables, the expression field's placeholder.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@class MBMappingEditor, DMTabBar;

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

@interface MBMappingInspectorViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)init;

@property (nonatomic, strong) MBMappingEditor *mappingEditor;

/* The selection shown: a new editor for a new selection, the same one
   told to reload for the same selection (it changed). */
- (void)showSelection;

/* What the pages' fields are bound to: `content.<key>` of the editor. */
@property (nonatomic, strong) IBOutlet NSObjectController *entityMappingController;
@property (nonatomic, strong) IBOutlet NSObjectController *attributeMappingController;
@property (nonatomic, strong) IBOutlet NSObjectController *relationshipMappingController;

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

- (IBAction)inspectorTabSelected:(id)sender;
- (IBAction)userInfoSegmentClicked:(id)sender;

@end
