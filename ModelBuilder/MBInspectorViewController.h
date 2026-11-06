/* ModelBuilder — the inspector (MBInspector.xib): a DMTabBar over the
   Identity page (the model version's identifier) and the Data Model page,
   one page of it for each kind of selection (an entity, an attribute, a
   relationship, a fetch request, a fetch index), each with its own user
   info table and versioning fields.  It shows the model editor's
   selection: each page's fields are bound in the XIB to its editor
   controller (an NSObjectController there), whose content is the
   selection's editor (MBEditors), and edit through it.  What is left
   to code: which page shows, the user info and constraint tables, and
   the Derived tick's prompt.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import "MBStepperTextField.h"

@class MBModelEditor, DMTabBar;

/* The pages of the inspector tab view, in xib order. */
typedef NS_ENUM(NSInteger, MBInspectorPage) {
  MBInspectorPageIdentity = 0,
  MBInspectorPageDataModel = 1,
};

@interface MBInspectorViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)init;

@property (nonatomic, strong) MBModelEditor *modelEditor;

/* The selection shown: a new editor for a new selection, the same one
   told to reload for the same selection (it changed). */
- (void)showSelection;

/* One page alone, without the tab bar: for a host whose pane has tabs of
   its own (UDCode's inspector), which gives each page one. */
- (void)showOnlyPage:(MBInspectorPage)page;

/* What the pages' fields are bound to: `content.<key>` of the editor. */
@property (nonatomic, strong) IBOutlet NSObjectController *versionController;
@property (nonatomic, strong) IBOutlet NSObjectController *entityController;
@property (nonatomic, strong) IBOutlet NSObjectController *attributeController;
@property (nonatomic, strong) IBOutlet NSObjectController *relationshipController;
@property (nonatomic, strong) IBOutlet NSObjectController *fetchController;
@property (nonatomic, strong) IBOutlet NSObjectController *fetchIndexController;

@property (nonatomic, strong) IBOutlet NSButton *abstractCheckbox;
@property (nonatomic, strong) IBOutlet NSView *textPromptView;
@property (nonatomic, strong) IBOutlet NSTextField *textPromptField;
@property (nonatomic, strong) IBOutlet NSTabView *attributeDetailTabView;
@property (nonatomic, strong) IBOutlet NSTextField *attributeHashModifierField;
@property (nonatomic, strong) IBOutlet NSTextField *attributeNameField;
@property (nonatomic, strong) IBOutlet NSTextField *attributeRenamingField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *attributeTypePopup;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *attributeUserInfoSegmentedControl;
@property (nonatomic, strong) IBOutlet NSTableView *attributeUserInfoTable;
@property (nonatomic, strong) IBOutlet NSPopUpButton *boolDefaultPopup;
@property (nonatomic, strong) IBOutlet NSButton *boolScalarCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *classField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *codegenPopup;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *constraintsSegmentedControl;
@property (nonatomic, strong) IBOutlet NSTableView *constraintsTable;
@property (nonatomic, strong) IBOutlet NSButton *dateDefaultCheckbox;
@property (nonatomic, strong) IBOutlet NSDatePicker *dateDefaultPicker;
@property (nonatomic, strong) IBOutlet NSButton *dateMaxCheckbox;
@property (nonatomic, strong) IBOutlet NSDatePicker *dateMaxPicker;
@property (nonatomic, strong) IBOutlet NSButton *dateMinCheckbox;
@property (nonatomic, strong) IBOutlet NSDatePicker *dateMinPicker;
@property (nonatomic, strong) IBOutlet NSButton *dateScalarCheckbox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *deleteRulePopup;
@property (nonatomic, strong) IBOutlet NSButton *derivedCheckbox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *destinationPopup;
@property (nonatomic, strong) IBOutlet NSTextField *entityHashModifierField;
@property (nonatomic, strong) IBOutlet NSTextField *entityNameField;
@property (nonatomic, strong) IBOutlet NSTextField *entityRenamingField;
@property (nonatomic, strong) IBOutlet NSTextField *modelIdentifierField;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *entityUserInfoSegmentedControl;
@property (nonatomic, strong) IBOutlet NSTableView *entityUserInfoTable;
@property (nonatomic, strong) IBOutlet MBStepperTextField *fetchBatchField;
@property (nonatomic, strong) IBOutlet NSButton *fetchDistinctCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *fetchFaultsCheckbox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *fetchInspectorEntityPopup;
@property (nonatomic, strong) IBOutlet MBStepperTextField *fetchLimitField;
@property (nonatomic, strong) IBOutlet NSTextField *fetchNameField;
@property (nonatomic, strong) IBOutlet NSButton *fetchPendingChangesCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *fetchPropertyValuesCheckbox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *fetchResultTypePopup;
@property (nonatomic, strong) IBOutlet NSButton *fetchSubentitiesCheckbox;
@property (nonatomic, strong) IBOutlet NSTabView *inspectorKindTabView;  /* Entity | Fetch | Attribute | Relationship */
@property (nonatomic, strong) IBOutlet DMTabBar *inspectorTabBar;
@property (nonatomic, strong) IBOutlet NSTabView *inspectorTabView;      /* Identity | Data Model */
@property (nonatomic, strong) IBOutlet NSPopUpButton *inversePopup;
@property (nonatomic, strong) IBOutlet MBStepperTextField *maxCountField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *minCountField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *numberDefaultField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *numberMaxField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *numberMinField;
@property (nonatomic, strong) IBOutlet NSButton *numberScalarCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *optionalCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *orderedCheckbox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *parentPopup;
@property (nonatomic, strong) IBOutlet NSButton *externalStorageCheckbox;
@property (nonatomic, strong) IBOutlet NSButton *preserveCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *relationshipHashModifierField;
@property (nonatomic, strong) IBOutlet NSTextField *relationshipNameField;
@property (nonatomic, strong) IBOutlet NSButton *relationshipOptionalCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *relationshipRenamingField;
@property (nonatomic, strong) IBOutlet NSButton *relationshipTransientCheckbox;
@property (nonatomic, strong) IBOutlet NSPopUpButton *relationshipTypePopup;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *relationshipUserInfoSegmentedControl;
@property (nonatomic, strong) IBOutlet NSTableView *relationshipUserInfoTable;
@property (nonatomic, strong) IBOutlet NSButton *stringDefaultCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *stringDefaultField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *stringMaxField;
@property (nonatomic, strong) IBOutlet MBStepperTextField *stringMinField;
@property (nonatomic, strong) IBOutlet NSTextField *stringRegexField;
@property (nonatomic, strong) IBOutlet NSTextField *transformableClassField;
@property (nonatomic, strong) IBOutlet NSTextField *transformerField;
@property (nonatomic, strong) IBOutlet NSButton *transientCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *undefinedClassField;
@property (nonatomic, strong) IBOutlet NSTextField *uriDefaultField;
@property (nonatomic, strong) IBOutlet NSTextField *uuidDefaultField;
@property (nonatomic, strong) IBOutlet NSButton *uuidScalarCheckbox;
@property (nonatomic, strong) IBOutlet NSTextField *fetchIndexNameField;
@property (nonatomic, strong) IBOutlet NSTextField *fetchIndexPredicateField;

- (IBAction)inspectorTabSelected:(id)sender;
- (IBAction)derivedToggled:(id)sender;
- (IBAction)userInfoSegmentClicked:(id)sender;
- (IBAction)constraintsSegmentClicked:(id)sender;

@end
