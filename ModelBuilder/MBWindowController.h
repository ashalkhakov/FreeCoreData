/* ModelBuilder document window — Xcode-style three-pane editor whose
   layout lives entirely in MBDocumentWindow.xib (one xib serving both
   toolkits; GNUstep loads it through GSXib5).

   Left: source list (ENTITIES / FETCH REQUESTS / CONFIGURATIONS).
   Bottom bar: "+/− Entity" and "+/− Attribute" segmented controls.
   Center: a borderless tab view — the entity editor (Attributes and
   Relationships tables in collapsible JUInspectorView sections, each
   with +/− underneath), the fetch request editor ("Fetch all" popup,
   predicate editor with a T/S source toggle), and the configuration
   editor (entity membership checklist).  Right: DMTabBar over the data
   model inspector — one inspector tab per selection kind (entity /
   fetch request / attribute / relationship), each with its own
   userInfo table and versioning fields.

   Nearly all setup lives in the xib (outlets, actions, column
   identifiers, popup items, section names via runtime attributes).
   The controller keeps only what the xib cannot express: DMTabBar
   items, the compiler-vocabulary popups, the source list's context
   menu, and disabling (with tooltips) of the controls the
   FreeCoreData serializer does not round-trip yet - a deliberate
   in-code reminder list.  Version management and validation live in
   the Model menu (MainMenu.xib, routed through the responder chain).

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import "MBStepperTextField.h"

@class JUInspectorView, JUInspectorViewContainer, DMTabBar;

@interface MBWindowController : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSplitViewDelegate>

/* Left pane */
@property (nonatomic, strong) IBOutlet NSOutlineView *sourceList;

/* Bottom bar */
@property (nonatomic, strong) IBOutlet NSSegmentedControl *entitySegmentedControl;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *propertySegmentedControl;

/* Center pane */
@property (nonatomic, strong) IBOutlet NSTabView *centerTabView;

/* Center pane: entity editor */
@property (nonatomic, strong) IBOutlet JUInspectorViewContainer *entityInspectorContainer;
@property (nonatomic, strong) IBOutlet JUInspectorView *attributesInspector;
@property (nonatomic, strong) IBOutlet JUInspectorView *relationshipsInspector;
@property (nonatomic, strong) IBOutlet NSTableView *attributeTable;
@property (nonatomic, strong) IBOutlet NSTableView *relationshipTable;

/* Center pane: fetch request editor */
@property (nonatomic, strong) IBOutlet JUInspectorViewContainer *fetchRequestInspectorContainer;
@property (nonatomic, strong) IBOutlet JUInspectorView *fetchRequestInspector;
@property (nonatomic, strong) IBOutlet NSPopUpButton *fetchEntityPopup;
@property (nonatomic, strong) IBOutlet NSTabView *predicateTabView;
@property (nonatomic, strong) IBOutlet NSPredicateEditor *fetchPredicateEditor;
@property (nonatomic, strong) IBOutlet NSTextField *predicateSourceView;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *predicateSourceSegmentedControl;

/* Center pane: configuration editor */
@property (nonatomic, strong) IBOutlet JUInspectorViewContainer *configurationInspectorContainer;
@property (nonatomic, strong) IBOutlet JUInspectorView *entitiesInspector;
@property (nonatomic, strong) IBOutlet NSTableView *memberTable;

/* Inspector pane chrome */
@property (nonatomic, strong) IBOutlet DMTabBar *inspectorTabBar;
@property (nonatomic, strong) IBOutlet NSTabView *inspectorTabView;      /* Identity | Data Model */
@property (nonatomic, strong) IBOutlet NSTabView *inspectorKindTabView;  /* Entity | Fetch | Attribute | Relationship */

/* Entity inspector */
@property (nonatomic, strong) IBOutlet NSTextField *entityNameField;
@property (nonatomic, strong) IBOutlet NSButton *abstractCheckbox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *parentPopup;
@property (nonatomic, strong) IBOutlet NSTextField *classField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *codegenPopup;
@property (nonatomic, strong) IBOutlet NSTableView *constraintsTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *constraintsSegmentedControl;
@property (nonatomic, strong) IBOutlet NSTableView *entityUserInfoTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *entityUserInfoSegmentedControl;
@property (nonatomic, strong) IBOutlet NSTextField *entityHashModifierField;
@property (nonatomic, strong) IBOutlet NSTextField *entityRenamingField;

/* Fetch request inspector */
@property (nonatomic, strong) IBOutlet NSTextField *fetchNameField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *fetchInspectorEntityPopup;
@property (nonatomic, strong) IBOutlet NSPopUpButton *fetchResultTypePopup;
@property (nonatomic, strong) IBOutlet MBStepperTextField *fetchLimitField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *fetchBatchField;
@property (nonatomic, strong) IBOutlet NSButton *fetchPropertyValuesCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *fetchFaultsCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *fetchPendingChangesCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *fetchDistinctCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *fetchSubentitiesCheckbox;

/* Attribute inspector */
@property (nonatomic, strong) IBOutlet NSTextField *attributeNameField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *attributeTypePopup;
@property (nonatomic, strong) IBOutlet NSButton *optionalCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *transientCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *derivedCheckbox;
@property (nonatomic, strong) IBOutlet NSTabView *attributeDetailTabView;
@property (nonatomic, strong) IBOutlet NSTextField *undefinedClassField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *numberDefaultField;
@property (nonatomic, strong) IBOutlet NSButton *numberScalarCheckbox;
@property (nonatomic, strong) IBOutlet MBStepperTextField *numberMinField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *numberMaxField;
@property (nonatomic, strong) IBOutlet NSButton *stringDefaultCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *stringDefaultField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *stringMinField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *stringMaxField;
@property (nonatomic, strong) IBOutlet NSTextField *stringRegexField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *boolDefaultPopup;
@property (nonatomic, strong) IBOutlet NSButton *boolScalarCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *dateDefaultCheckbox;
@property (nonatomic, strong) IBOutlet NSDatePicker *dateDefaultPicker;
@property (nonatomic, strong) IBOutlet NSButton *dateScalarCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *dateMinCheckbox;
@property (nonatomic, strong) IBOutlet NSDatePicker *dateMinPicker;
@property (nonatomic, strong) IBOutlet NSButton *dateMaxCheckbox;
@property (nonatomic, strong) IBOutlet NSDatePicker *dateMaxPicker;
@property (nonatomic, strong) IBOutlet NSTextField *uuidDefaultField;
@property (nonatomic, strong) IBOutlet NSButton *uuidScalarCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *uriDefaultField;
@property (nonatomic, strong) IBOutlet NSTextField *transformerField;
@property (nonatomic, strong) IBOutlet NSTextField *transformableClassField;
@property (nonatomic, strong) IBOutlet NSButton *preserveCheckbox;
@property (nonatomic, strong) IBOutlet NSTableView *attributeUserInfoTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *attributeUserInfoSegmentedControl;
@property (nonatomic, strong) IBOutlet NSTextField *attributeHashModifierField;
@property (nonatomic, strong) IBOutlet NSTextField *attributeRenamingField;

/* Relationship inspector */
@property (nonatomic, strong) IBOutlet NSTextField *relationshipNameField;
@property (nonatomic, strong) IBOutlet NSButton *relationshipTransientCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *relationshipOptionalCheckbox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *destinationPopup;
@property (nonatomic, strong) IBOutlet NSPopUpButton *inversePopup;
@property (nonatomic, strong) IBOutlet NSPopUpButton *deleteRulePopup;
@property (nonatomic, strong) IBOutlet NSPopUpButton *relationshipTypePopup;
@property (nonatomic, strong) IBOutlet NSButton *orderedCheckbox;
@property (nonatomic, strong) IBOutlet MBStepperTextField *minCountField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *maxCountField;
@property (nonatomic, strong) IBOutlet NSTableView *relationshipUserInfoTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *relationshipUserInfoSegmentedControl;
@property (nonatomic, strong) IBOutlet NSTextField *relationshipHashModifierField;
@property (nonatomic, strong) IBOutlet NSTextField *relationshipRenamingField;

/* Source list / bottom bar */
- (IBAction)sourceSegmentClicked:(id)sender;
- (IBAction)propertySegmentClicked:(id)sender;
- (IBAction)addSourceItem:(id)sender;
- (IBAction)removeSourceItem:(id)sender;
- (IBAction)addEntity:(id)sender;
- (IBAction)addFetchRequest:(id)sender;
- (IBAction)addConfiguration:(id)sender;
- (IBAction)removeEntity:(id)sender;
- (IBAction)addAttribute:(id)sender;
- (IBAction)removeAttribute:(id)sender;
- (IBAction)addRelationship:(id)sender;
- (IBAction)removeRelationship:(id)sender;

/* Inspector */
- (IBAction)inspectorChanged:(id)sender;
- (IBAction)inspectorTabSelected:(id)sender;
- (IBAction)userInfoSegmentClicked:(id)sender;
- (IBAction)constraintsSegmentClicked:(id)sender;
- (IBAction)predicateSourceToggled:(id)sender;

/* Editor menu (nil-target, routed through the responder chain) */
- (IBAction)selectVersionMenuItem:(id)sender;
- (IBAction)addModelVersion:(id)sender;
- (IBAction)makeCurrentVersion:(id)sender;
- (IBAction)validateModel:(id)sender;
- (IBAction)compileModel:(id)sender;
/* Xcode's Editor > Create NSManagedObject Subclass... (also on the
   source list's context menu); wire an Editor-menu item to it in
   MainMenu.xib when convenient. */
- (IBAction)createManagedObjectSubclass:(id)sender;

@end
