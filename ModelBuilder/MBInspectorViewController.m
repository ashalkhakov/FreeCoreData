/* ModelBuilder — the inspector (see MBInspectorViewController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBInspectorViewController.h"
#import "MBModelEditor.h"
#import "MBEditors.h"
#import "MBWindowSupport.h"
#import "CDModelCompiler.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"

typedef NS_ENUM(NSInteger, MBInspectKind) {
  MBInspectNone = 0,
  MBInspectEntity,
  MBInspectAttribute,
  MBInspectRelationship,
  MBInspectFetch,
  MBInspectConfiguration,
  MBInspectFetchIndex
};

/* inspectorTabView pages */
enum { MBInspectorPageIdentity = 0, MBInspectorPageDataModel = 1 };
/* inspectorKindTabView pages */
enum { MBKindPageEntity = 0, MBKindPageFetch = 1, MBKindPageAttribute = 2, MBKindPageRelationship = 3, MBKindPageFetchIndex = 4 };

/* The inspector's document view.  Flipped, so its pages hang from the top
   and it grows downwards: taller than the inspector and it scrolls from
   the top, shorter and the space is left below it.  (NSTabView cannot be
   flipped from a xib, hence a view to hold it.) */
@interface MBFlippedView : NSView
@end

@implementation MBFlippedView
- (BOOL)isFlipped { return YES; }
@end

static void MBDisable(id control, NSString *tooltip)
{
  [control setEnabled:NO];
  if (tooltip && [control respondsToSelector:@selector(setToolTip:)])
    [control setToolTip:tooltip];
}

/* Recursively disable every control of a class, descending into tab
   view pages (whose views are detached until selected). */
static void MBDisableControlsOfClass(NSView *root, Class cls, NSString *tooltip)
{
  if ([root isKindOfClass:[NSTabView class]]) {
    for (NSTabViewItem *item in [(NSTabView *)root tabViewItems])
      if (item.view)
        MBDisableControlsOfClass(item.view, cls, tooltip);
  }
  for (NSView *sub in root.subviews) {
    if ([sub isKindOfClass:cls])
      MBDisable(sub, tooltip);
    MBDisableControlsOfClass(sub, cls, tooltip);
  }
}

static NSString *MBUniqueName(NSString *base, NSArray *names)
{
  if (![names containsObject:base]) return base;
  NSUInteger counter = 2;
  NSString *candidate;
  do {
    candidate = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)counter];
    counter++;
  } while ([names containsObject:candidate]);
  return candidate;
}

@implementation MBInspectorViewController {
  MBInspectKind _kind;
  BOOL _updating;    /* the page being filled: its controls' actions are not edits */
  BOOL _applying;    /* an edit being made: the page is filled once, after it */
  NSArray *_userInfoKeys;
  NSMutableArray *_constraintRows; /* mirror of the entity's uniquenessConstraints */
}

- (instancetype)init
{
  return [super initWithNibName:@"MBInspector" bundle:[NSBundle bundleForClass:[self class]]];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* gnustep-gui has no -viewDidLoad: what the xib cannot say, as the view
   loads. */
- (void)loadView
{
  [super loadView];

  /* DMTabBar over the inspector tab view.  Xcode's own icons on macOS;
     elsewhere drawn letter badges, as the XForms and RDL designers' bars
     have.  (GNUstep ships images under some of these names -- NSAdvanced
     is a gear -- so it is the platform, not the lookup, that decides.) */
  NSImage *identityIcon = nil, *dataModelIcon = nil;
#if defined(__APPLE__)
  identityIcon = MBFirstImageNamed(@[ @"NSInfo", @"NSTouchBarGetInfoTemplate" ]);
  dataModelIcon = MBFirstImageNamed(@[ @"NSActionTemplate", @"NSSmartBadgeTemplate", @"NSAdvanced" ]);
#endif
  DMTabBarItem *identityItem = [DMTabBarItem
      tabBarItemWithIcon:identityIcon ?: MBBadgeImage(@"i", 0.47, 0.53, 0.64)
                     tag:MBInspectorPageIdentity];
  identityItem.toolTip = @"Identity and Type";
  DMTabBarItem *dataModelItem = [DMTabBarItem
      tabBarItemWithIcon:dataModelIcon ?: MBBadgeImage(@"D", 0.36, 0.49, 0.72)
                     tag:MBInspectorPageDataModel];
  dataModelItem.toolTip = @"Data Model Inspector";
  self.inspectorTabBar.tabBarItems = @[ identityItem, dataModelItem ];
  [self.inspectorTabBar setTarget:self action:@selector(inspectorTabSelected:)];
  self.inspectorTabBar.selectedIndex = MBInspectorPageDataModel;
  [self.inspectorTabView selectTabViewItemAtIndex:MBInspectorPageDataModel];

  /* The attribute-type popup is populated from CDModelCompiler so the
     menu can never drift from what momc accepts (its xib items are
     design-time placeholders).  The delete-rule items live in the xib;
     they are matched by title against the compiler's spellings, and
     the GUI probe pins the two sets against each other. */
  [self.attributeTypePopup removeAllItems];
  [self.attributeTypePopup addItemsWithTitles:[CDModelCompiler attributeTypeNames]];

  /* --- Features the serializer does not round-trip yet.  Kept in code
     (not disabled in the xib) DELIBERATELY: each line below is the
     to-do list for a schema feature, and enabling one should happen
     next to the serializer change that supports it. --- */
  self.preserveCheckbox.toolTip =
      @"With persistent history tracking, a deleted object's last value "
      @"for this attribute is kept in the history change's tombstone.";
  MBDisable(self.undefinedClassField,
      @"Custom value classes apply to Transformable attributes.");
  MBDisableControlsOfClass(self.inspectorTabView, [NSComboBox class],
      @"Modules are an Xcode/Swift concept; not used by FreeCoreData.");
}

- (void)setModelEditor:(MBModelEditor *)modelEditor
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  if (_modelEditor) {
    [center removeObserver:self name:MBModelEditorDidChangeNotification object:_modelEditor];
    [center removeObserver:self name:MBModelEditorSelectionDidChangeNotification object:_modelEditor];
  }
  _modelEditor = modelEditor;
  if (_modelEditor) {
    [center addObserver:self selector:@selector(modelDidChange:)
                   name:MBModelEditorDidChangeNotification object:_modelEditor];
    [center addObserver:self selector:@selector(modelDidChange:)
                   name:MBModelEditorSelectionDidChangeNotification object:_modelEditor];
  }
  (void)self.view;
  [self fillInspector];
}

- (void)modelDidChange:(NSNotification *)notification
{
  (void)notification;
  if (!_applying) [self fillInspector];
}

#pragma mark - The selection's editors

/* What the Data Model page shows for the selection. */
- (MBInspectKind)kindOfSelection
{
  MBSelection *selection = _modelEditor.selection;
  switch (selection.kind) {
    case MBSelectionEntity:
      return [_modelEditor selectedEntity] ? MBInspectEntity : MBInspectNone;
    case MBSelectionAttribute:
      return [_modelEditor selectedProperty] ? MBInspectAttribute : MBInspectEntity;
    case MBSelectionRelationship:
      return [_modelEditor selectedProperty] ? MBInspectRelationship : MBInspectEntity;
    case MBSelectionFetchRequest:
      return [_modelEditor selectedFetchRequest] ? MBInspectFetch : MBInspectNone;
    case MBSelectionConfiguration:
      return MBInspectConfiguration;
    case MBSelectionFetchIndex:
      return [self selectedFetchIndexRow] ? MBInspectFetchIndex : MBInspectNone;
    default:
      return MBInspectNone;
  }
}

- (MBEntityEditor *)entityEditor
{
  NSString *name = [_modelEditor selectedEntity].name;
  return name ? [MBEntityEditor editorForEntityNamed:name modelEditor:_modelEditor] : nil;
}

- (MBAttributeEditor *)attributeEditor
{
  NSEntityDescription *entity = [_modelEditor selectedEntity];
  NSPropertyDescription *property = [_modelEditor selectedProperty];
  return (entity && [property isKindOfClass:[NSAttributeDescription class]])
      ? [MBAttributeEditor editorForAttributeNamed:property.name entity:entity modelEditor:_modelEditor]
      : nil;
}

- (MBRelationshipEditor *)relationshipEditor
{
  NSEntityDescription *entity = [_modelEditor selectedEntity];
  NSPropertyDescription *property = [_modelEditor selectedProperty];
  return (entity && [property isKindOfClass:[NSRelationshipDescription class]])
      ? [MBRelationshipEditor editorForRelationshipNamed:property.name entity:entity modelEditor:_modelEditor]
      : nil;
}

- (MBFetchEditor *)fetchRequestEditor
{
  NSString *name = [_modelEditor selectedFetchRequest] ? _modelEditor.selection.name : nil;
  return name ? [MBFetchEditor editorForFetchRequestNamed:name modelEditor:_modelEditor] : nil;
}

/* The selected index as the entity editor has it (see fetchIndexRows). */
- (NSDictionary *)selectedFetchIndexRow
{
  MBSelection *selection = _modelEditor.selection;
  if (selection.kind != MBSelectionFetchIndex) return nil;
  for (NSDictionary *row in [self entityEditor].fetchIndexRows)
    if ([row[@"name"] isEqualToString:selection.name]) return row;
  return nil;
}

/* The selected index with one of its rows changed - name or predicate -
   as one undo step; a renamed index stays selected. */
- (void)changeSelectedFetchIndex:(void (^)(NSMutableDictionary *row))change action:(NSString *)action
{
  MBSelection *selection = _modelEditor.selection;
  MBEntityEditor *editor = [self entityEditor];
  NSMutableArray *rows = [NSMutableArray array];
  NSString *renamed = selection.name;
  for (NSDictionary *row in editor.fetchIndexRows) {
    NSMutableDictionary *copy = [row mutableCopy];
    if ([row[@"name"] isEqualToString:selection.name]) {
      change(copy);
      renamed = copy[@"name"];
    }
    [rows addObject:copy];
  }
  _applying = YES;
  [_modelEditor beginEdit:action];
  editor.fetchIndexRows = rows;
  [_modelEditor endEdit];
  _applying = NO;
  if (editor.lastError)
    MBPresentModelError(editor.lastError, @"Cannot change the fetch index");
  else if (![renamed isEqualToString:selection.name])
    _modelEditor.selection = [MBSelection selectionOfKind:MBSelectionFetchIndex
                                               entityName:selection.entityName
                                                     name:renamed configurationName:nil];
  [self fillInspector];
}

/* The selected entity's attributes, by name: a new constraint's first. */
- (NSArray *)attributeNamesOfSelectedEntity
{
  return [[[_modelEditor selectedEntity].attributesByName allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Filling the page

- (void)rebuildParentPopup
{
  [self.parentPopup removeAllItems];
  [self.parentPopup addItemWithTitle:@"(none)"];
  NSEntityDescription *current = [self.modelEditor selectedEntity];
  for (NSEntityDescription *entity in [self.modelEditor sortedEntities]) {
    if (entity == current) continue;
    [self.parentPopup addItemWithTitle:entity.name ?: @""];
  }
}

- (void)rebuildEntityListInto:(NSPopUpButton *)popup includeNone:(BOOL)includeNone
{
  [popup removeAllItems];
  if (includeNone)
    [popup addItemWithTitle:@"(none)"];
  for (NSEntityDescription *entity in [self.modelEditor sortedEntities])
    [popup addItemWithTitle:entity.name ?: @""];
}

- (void)rebuildInversePopup
{
  [self.inversePopup removeAllItems];
  [self.inversePopup addItemWithTitle:@"(none)"];
  NSRelationshipDescription *rel = ((NSRelationshipDescription *)[self.modelEditor selectedProperty]);
  NSEntityDescription *dest = rel.destinationEntity;
  if (!dest) return;
  for (NSString *name in [[dest.relationshipsByName allKeys]
           sortedArrayUsingSelector:@selector(compare:)])
    [self.inversePopup addItemWithTitle:name];
}

static NSInteger MBDetailTabIndexForType(NSAttributeType type)
{
  switch (type) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSDecimalAttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:        return 1;
    case NSStringAttributeType:       return 2;
    case NSBooleanAttributeType:      return 3;
    case NSDateAttributeType:         return 4;
    case NSBinaryDataAttributeType:   return 5;
    case NSUUIDAttributeType:         return 6;
    case NSURIAttributeType:          return 7;
    case NSTransformableAttributeType: return 8;
    default:                          return 0;
  }
}

- (void)selectInspectorPage:(NSInteger)page kindPage:(NSInteger)kindPage
{
  self.inspectorTabBar.selectedIndex = (NSUInteger)page;
  [self.inspectorTabView selectTabViewItemAtIndex:page];
  if (page == MBInspectorPageDataModel && kindPage >= 0)
    [self.inspectorKindTabView selectTabViewItemAtIndex:kindPage];
}

- (void)fillEntityInspector:(NSEntityDescription *)entity
{
  self.entityNameField.stringValue = entity.name ?: @"";
  self.classField.stringValue = entity.managedObjectClassName ?: @"";
  self.abstractCheckbox.state = entity.isAbstract ? NSOnState : NSOffState;
  [self rebuildParentPopup];
  NSString *parent = entity.superentity.name;
  if (parent.length && [self.parentPopup itemWithTitle:parent])
    [self.parentPopup selectItemWithTitle:parent];
  else
    [self.parentPopup selectItemAtIndex:0];
  self.entityHashModifierField.stringValue = [entity versionHashModifier] ?: @"";
  /* shows the entity name while defaulted (Xcode does the same) */
  self.entityRenamingField.stringValue = [entity renamingIdentifier] ?: @"";
  /* popup order: Manual/None, Class Definition, Category/Extension */
  NSString *codegen = [CDModelCompiler entityCodeGenerationType:entity];
  NSInteger codegenIndex = 0;
  if ([codegen isEqualToString:@"class"]) codegenIndex = 1;
  else if ([codegen isEqualToString:@"category"]) codegenIndex = 2;
  [self.codegenPopup selectItemAtIndex:codegenIndex];
}

- (void)fillAttributeInspector:(NSAttributeDescription *)attr
{
  self.attributeNameField.stringValue = attr.name ?: @"";
  NSString *typeName = [CDModelCompiler nameForAttributeType:attr.attributeType];
  if (typeName.length && [self.attributeTypePopup itemWithTitle:typeName])
    [self.attributeTypePopup selectItemWithTitle:typeName];
  self.optionalCheckbox.state = attr.isOptional ? NSOnState : NSOffState;
  self.transientCheckbox.state = attr.isTransient ? NSOnState : NSOffState;
  self.preserveCheckbox.state =
      attr.preservesValueInHistoryOnDeletion ? NSOnState : NSOffState;
  /* As Xcode's: an option of Binary Data alone. */
  BOOL binary = (attr.attributeType == NSBinaryDataAttributeType);
  self.externalStorageCheckbox.enabled = binary;
  self.externalStorageCheckbox.state =
      (binary && attr.allowsExternalBinaryDataStorage) ? NSOnState : NSOffState;

  MBAttributeEditor *editor = [MBAttributeEditor
      editorForAttributeNamed:attr.name
                       entity:[self.modelEditor selectedEntity]
                     modelEditor:self.modelEditor];
  BOOL derived = editor.isDerived;
  self.derivedCheckbox.state = derived ? NSOnState : NSOffState;
  self.derivedCheckbox.toolTip = derived
      ? [NSString stringWithFormat:@"Derivation: %@ — uncheck and re-check to edit.",
         editor.derivationString]
      : @"Turns the attribute into a derived attribute (you will be asked for the derivation expression).";

  [self.attributeDetailTabView
      selectTabViewItemAtIndex:MBDetailTabIndexForType(attr.attributeType)];

  id value = attr.defaultValue;
  switch (attr.attributeType) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSDecimalAttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
      self.numberDefaultField.stringValue = value ? [value description] : @"";
      self.numberScalarCheckbox.state = editor.scalarType ? NSOnState : NSOffState;
      self.numberMinField.stringValue = editor.validationMin ?: @"";
      self.numberMaxField.stringValue = editor.validationMax ?: @"";
      break;
    case NSStringAttributeType:
      self.stringDefaultCheckbox.state = value ? NSOnState : NSOffState;
      self.stringDefaultField.stringValue = value ? [value description] : @"";
      self.stringMinField.stringValue = editor.minLengthString ?: @"";
      self.stringMaxField.stringValue = editor.maxLengthString ?: @"";
      self.stringRegexField.stringValue = editor.regexString ?: @"";
      break;
    case NSBooleanAttributeType:
      if (!value) [self.boolDefaultPopup selectItemAtIndex:0];
      else [self.boolDefaultPopup selectItemWithTitle:[value boolValue] ? @"YES" : @"NO"];
      self.boolScalarCheckbox.state = editor.scalarType ? NSOnState : NSOffState;
      break;
    case NSDateAttributeType: {
      self.dateDefaultCheckbox.state = value ? NSOnState : NSOffState;
      if (value) self.dateDefaultPicker.dateValue = value;
      self.dateScalarCheckbox.state = editor.scalarType ? NSOnState : NSOffState;
      NSDate *minDate = editor.validationMinDate, *maxDate = editor.validationMaxDate;
      self.dateMinCheckbox.state = minDate ? NSOnState : NSOffState;
      if (minDate) self.dateMinPicker.dateValue = minDate;
      self.dateMaxCheckbox.state = maxDate ? NSOnState : NSOffState;
      if (maxDate) self.dateMaxPicker.dateValue = maxDate;
      break;
    }
    case NSUUIDAttributeType:
      self.uuidDefaultField.stringValue = value ? [value UUIDString] : @"";
      self.uuidScalarCheckbox.state = editor.scalarType ? NSOnState : NSOffState;
      break;
    case NSURIAttributeType:
      self.uriDefaultField.stringValue = value ? [value absoluteString] : @"";
      break;
    case NSTransformableAttributeType:
      self.transformerField.stringValue = [attr valueTransformerName] ?: @"";
      self.transformableClassField.stringValue = [attr attributeValueClassName] ?: @"";
      break;
    default:
      break;
  }
  self.attributeHashModifierField.stringValue = [attr versionHashModifier] ?: @"";
  self.attributeRenamingField.stringValue = editor.renamingIdentifier ?: @"";
}

- (void)fillRelationshipInspector:(NSRelationshipDescription *)rel
{
  self.relationshipNameField.stringValue = rel.name ?: @"";
  self.relationshipTransientCheckbox.state = rel.isTransient ? NSOnState : NSOffState;
  self.relationshipOptionalCheckbox.state = rel.isOptional ? NSOnState : NSOffState;
  [self rebuildEntityListInto:self.destinationPopup includeNone:YES];
  NSString *dest = rel.destinationEntity.name;
  if (dest.length && [self.destinationPopup itemWithTitle:dest])
    [self.destinationPopup selectItemWithTitle:dest];
  else
    [self.destinationPopup selectItemAtIndex:0];
  [self rebuildInversePopup];
  NSString *inverse = rel.inverseRelationship.name;
  if (inverse.length && [self.inversePopup itemWithTitle:inverse])
    [self.inversePopup selectItemWithTitle:inverse];
  else
    [self.inversePopup selectItemAtIndex:0];
  [self.relationshipTypePopup selectItemWithTitle:rel.isToMany ? @"To Many" : @"To One"];
  self.orderedCheckbox.enabled = rel.isToMany;
  self.orderedCheckbox.state = (rel.isToMany && rel.isOrdered) ? NSOnState : NSOffState;
  NSArray *ruleNames = [CDModelCompiler deleteRuleNames];
  NSUInteger ruleIndex;
  switch (rel.deleteRule) {
    case NSCascadeDeleteRule:  ruleIndex = 1; break;
    case NSDenyDeleteRule:     ruleIndex = 2; break;
    case NSNoActionDeleteRule: ruleIndex = 3; break;
    default:                   ruleIndex = 0; break;
  }
  [self.deleteRulePopup selectItemWithTitle:ruleNames[ruleIndex]];
  self.minCountField.enabled = rel.isToMany;
  self.maxCountField.enabled = rel.isToMany;
  self.minCountField.stringValue = (rel.isToMany && rel.minCount)
      ? [NSString stringWithFormat:@"%ld", (long)rel.minCount] : @"";
  self.maxCountField.stringValue = (rel.isToMany && rel.maxCount)
      ? [NSString stringWithFormat:@"%ld", (long)rel.maxCount] : @"";
  self.relationshipHashModifierField.stringValue = [rel versionHashModifier] ?: @"";
  self.relationshipRenamingField.stringValue = [rel renamingIdentifier] ?: @"";
}

- (void)fillFetchInspector:(NSFetchRequest *)fetch
{
  self.fetchNameField.stringValue = self.modelEditor.selection.name ?: @"";
  [self rebuildEntityListInto:self.fetchInspectorEntityPopup includeNone:NO];
  NSString *entityName = fetch.entity.name;
  if (entityName.length) {
    if ([self.fetchInspectorEntityPopup itemWithTitle:entityName])
      [self.fetchInspectorEntityPopup selectItemWithTitle:entityName];
  }
  self.fetchLimitField.stringValue = fetch.fetchLimit
      ? [NSString stringWithFormat:@"%lu", (unsigned long)fetch.fetchLimit] : @"";

  /* Result shape and paging.  The popup's item order (Objects /
     Object IDs / Dictionaries) matches the .xcdatamodel resultType
     integers, so index == XML value. */
  NSInteger resultIndex;
  switch (fetch.resultType) {
    case NSManagedObjectIDResultType: resultIndex = 1; break;
    case NSDictionaryResultType:      resultIndex = 2; break;
    default:                          resultIndex = 0; break;
  }
  [self.fetchResultTypePopup selectItemAtIndex:resultIndex];
  self.fetchBatchField.stringValue = fetch.fetchBatchSize
      ? [NSString stringWithFormat:@"%lu", (unsigned long)fetch.fetchBatchSize] : @"";
  self.fetchSubentitiesCheckbox.state = fetch.includesSubentities ? NSOnState : NSOffState;
  self.fetchPropertyValuesCheckbox.state = fetch.includesPropertyValues ? NSOnState : NSOffState;
  self.fetchFaultsCheckbox.state = fetch.returnsObjectsAsFaults ? NSOnState : NSOffState;
  self.fetchPendingChangesCheckbox.state = fetch.includesPendingChanges ? NSOnState : NSOffState;
  self.fetchDistinctCheckbox.state = fetch.returnsDistinctResults ? NSOnState : NSOffState;
}

- (void)fillInspector
{
  _kind = [self kindOfSelection];
  [self rebuildUserInfoRows];
  [self rebuildConstraintRows];
  [self.constraintsTable reloadData];
  _updating = YES;
  /* The Identity page describes the model version, whatever is selected:
     the tab bar can show it at any time. */
  self.modelIdentifierField.stringValue = [MBVersionEditor editorForModelEditor:self.modelEditor].versionIdentifier ?: @"";
  switch (_kind) {
    case MBInspectEntity:
      [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageEntity];
      [self fillEntityInspector:[self.modelEditor selectedEntity]];
      break;
    case MBInspectAttribute:
      [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageAttribute];
      [self fillAttributeInspector:(NSAttributeDescription *)[self.modelEditor selectedProperty]];
      break;
    case MBInspectRelationship:
      [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageRelationship];
      [self fillRelationshipInspector:(NSRelationshipDescription *)[self.modelEditor selectedProperty]];
      break;
    case MBInspectFetch:
      [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageFetch];
      [self fillFetchInspector:[self.modelEditor selectedFetchRequest]];
      break;
    case MBInspectFetchIndex: {
      NSDictionary *row = [self selectedFetchIndexRow];
      [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageFetchIndex];
      self.fetchIndexNameField.stringValue = row[@"name"] ?: @"";
      self.fetchIndexPredicateField.stringValue = row[@"predicate"] ?: @"";
      break;
    }
    default:
      /* configurations and empty selections have no data-model page */
      [self selectInspectorPage:MBInspectorPageIdentity kindPage:-1];
      break;
  }
  [self reloadUserInfoTables];
  _updating = NO;
}

#pragma mark - Inspector writes

- (IBAction)inspectorTabSelected:(id)sender
{
  (void)sender;
  NSUInteger index = self.inspectorTabBar.selectedIndex;
  if (index < (NSUInteger)[self.inspectorTabView numberOfTabViewItems])
    [self.inspectorTabView selectTabViewItemAtIndex:(NSInteger)index];
}

/* A prompt for a line of text: an alert, the field its accessory view
   (MBDocumentWindow.xib's).  Returns nil on Cancel. */
- (NSString *)runTextPromptWithTitle:(NSString *)title
                             message:(NSString *)message
                        initialValue:(NSString *)initialValue
{
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = title;
  alert.informativeText = message ?: @"";
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  self.textPromptField.stringValue = initialValue ?: @"";
  alert.accessoryView = self.textPromptView;
  [alert layout];
  [alert.window setInitialFirstResponder:self.textPromptField];
  NSModalResponse response = [alert runModal];
  return response == NSAlertFirstButtonReturn ? self.textPromptField.stringValue : nil;
}

/* Turning "Derived" on asks for the derivation expression; turning it
   off converts back to a plain attribute. */
- (IBAction)derivedToggled:(id)sender
{
  if (_updating) return;
  MBAttributeEditor *editor = [self attributeEditor];
  if (!editor) { [self fillInspector]; return; }

  /* Typed: sent to an id, -state resolves to AppKit's NSUInteger
     declaration (NSSwitch's) rather than NSButton's NSInteger one, and
     the runtime reports the mismatch on every -state call afterwards. */
  BOOL wantDerived = ([(NSButton *)sender state] == NSOnState);
  if (wantDerived == editor.isDerived) return;

  NSString *string = @"";
  if (wantDerived) {
    string = [self
        runTextPromptWithTitle:@"Derivation Expression"
                       message:@"e.g. a key path (department.name), now(), or uppercase:(title)"
                  initialValue:@""];
    if (string == nil || !string.length) {
      [sender setState:NSOffState];
      return;
    }
  }
  editor.derivationString = string;
  if (editor.lastError) {
    MBPresentModelError(editor.lastError, @"Invalid derivation expression");
    [sender setState:NSOffState];
    return;
  }
}

- (void)applyDefaultFromUIToEditor:(MBAttributeEditor *)editor
{
  switch (editor.attribute.attributeType) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
    case NSDecimalAttributeType:
      editor.defaultString = self.numberDefaultField.stringValue;
      editor.scalarType = (self.numberScalarCheckbox.state == NSOnState);
      editor.validationMin = self.numberMinField.stringValue;
      editor.validationMax = self.numberMaxField.stringValue;
      break;
    case NSStringAttributeType:
      editor.defaultString = (self.stringDefaultCheckbox.state == NSOnState)
          ? self.stringDefaultField.stringValue : @"";
      editor.minLengthString = self.stringMinField.stringValue;
      editor.maxLengthString = self.stringMaxField.stringValue;
      editor.regexString = self.stringRegexField.stringValue;
      break;
    case NSBooleanAttributeType: {
      /* Only YES/NO are values; the first item ("No Value") clears. */
      NSString *title = self.boolDefaultPopup.titleOfSelectedItem;
      BOOL isValue = [title isEqualToString:@"YES"] || [title isEqualToString:@"NO"];
      editor.defaultString = isValue ? title : @"";
      editor.scalarType = (self.boolScalarCheckbox.state == NSOnState);
      break;
    }
    case NSDateAttributeType:
      editor.defaultDate = (self.dateDefaultCheckbox.state == NSOnState)
          ? self.dateDefaultPicker.dateValue : nil;
      editor.scalarType = (self.dateScalarCheckbox.state == NSOnState);
      editor.validationMinDate = (self.dateMinCheckbox.state == NSOnState)
          ? self.dateMinPicker.dateValue : nil;
      editor.validationMaxDate = (self.dateMaxCheckbox.state == NSOnState)
          ? self.dateMaxPicker.dateValue : nil;
      break;
    case NSUUIDAttributeType:
      editor.defaultString = self.uuidDefaultField.stringValue;
      editor.scalarType = (self.uuidScalarCheckbox.state == NSOnState);
      break;
    case NSURIAttributeType:
      editor.defaultString = self.uriDefaultField.stringValue;
      break;
    case NSTransformableAttributeType:
      editor.transformerName = self.transformerField.stringValue;
      editor.customClassName = self.transformableClassField.stringValue;
      break;
    default:
      break;
  }
}

- (void)applyEntityInspector
{
  MBEntityEditor *editor = [self entityEditor];
  if (!editor) return;
  editor.name = self.entityNameField.stringValue;   /* validated; keeps old on clash */
  editor.className = self.classField.stringValue;
  editor.abstract = (self.abstractCheckbox.state == NSOnState);
  editor.hashModifier = self.entityHashModifierField.stringValue;
  editor.renamingIdentifier = self.entityRenamingField.stringValue;
  switch (self.codegenPopup.indexOfSelectedItem) {
    case 1:  editor.codegenType = @"class"; break;
    case 2:  editor.codegenType = @"category"; break;
    default: editor.codegenType = @""; break;
  }

  NSString *parent = self.parentPopup.titleOfSelectedItem;
  NSString *wanted = ([parent isEqualToString:@"(none)"] || !parent.length) ? @"" : parent;
  editor.parentName = wanted;   /* graph surgery: recompiles the model */
  if (editor.lastError)
    MBPresentModelError(editor.lastError, @"Cannot change parent entity");
}

- (void)applyAttributeInspector
{
  MBAttributeEditor *editor = [self attributeEditor];
  if (!editor) return;
  editor.name = self.attributeNameField.stringValue;
  editor.optional = (self.optionalCheckbox.state == NSOnState);
  editor.transient = (self.transientCheckbox.state == NSOnState);
  editor.preservesValueInHistoryOnDeletion =
      (self.preserveCheckbox.state == NSOnState);
  editor.hashModifier = self.attributeHashModifierField.stringValue;
  editor.renamingIdentifier = self.attributeRenamingField.stringValue;

  NSString *wantedType = self.attributeTypePopup.titleOfSelectedItem;
  BOOL typeChanged = ![wantedType isEqualToString:editor.typeName];
  editor.typeName = wantedType;   /* drops the stale default on change */
  /* Binary Data alone may be kept outside the store: the option goes
     when the type does. */
  BOOL allowsExternal = (editor.attribute.attributeType == NSBinaryDataAttributeType &&
                         self.externalStorageCheckbox.state == NSOnState);
  if (allowsExternal != editor.allowsExternalBinaryDataStorage)
    editor.allowsExternalBinaryDataStorage = allowsExternal;
  /* the default-value UI belongs to the old type: the page is filled
     again for the new one instead of applying stale controls */
  if (!typeChanged) [self applyDefaultFromUIToEditor:editor];
}

- (void)applyRelationshipInspector
{
  MBRelationshipEditor *editor = [self relationshipEditor];
  if (!editor) return;
  editor.name = self.relationshipNameField.stringValue;
  editor.transient = (self.relationshipTransientCheckbox.state == NSOnState);
  editor.optional = (self.relationshipOptionalCheckbox.state == NSOnState);
  editor.hashModifier = self.relationshipHashModifierField.stringValue;
  editor.renamingIdentifier = self.relationshipRenamingField.stringValue;

  editor.toMany = [self.relationshipTypePopup.titleOfSelectedItem isEqualToString:@"To Many"];
  if (editor.isToMany) {
    editor.minCount = self.minCountField.stringValue.integerValue;
    editor.maxCount = self.maxCountField.stringValue.integerValue;
    editor.ordered = (self.orderedCheckbox.state == NSOnState);
  }
  editor.destinationName = self.destinationPopup.titleOfSelectedItem;
  editor.inverseName = self.inversePopup.titleOfSelectedItem;
  editor.deleteRuleName = self.deleteRulePopup.titleOfSelectedItem;
}

- (void)applyFetchInspector:(id)sender
{
  (void)sender;
  MBFetchEditor *editor = [self fetchRequestEditor];
  if (!editor) return;

  NSString *newName = self.fetchNameField.stringValue;
  if (![newName isEqualToString:editor.name])
    editor.name = newName;   /* re-keys the template map; refuses clashes */
  editor.entityName = self.fetchInspectorEntityPopup.titleOfSelectedItem;
  editor.fetchLimit = (NSUInteger)MAX(0, self.fetchLimitField.stringValue.integerValue);

  /* popup index == resultType integer in the model XML (0/1/2) */
  switch (self.fetchResultTypePopup.indexOfSelectedItem) {
    case 1:  editor.resultType = NSManagedObjectIDResultType; break;
    case 2:  editor.resultType = NSDictionaryResultType; break;
    default: editor.resultType = NSManagedObjectResultType; break;
  }
  editor.fetchBatchSize = (NSUInteger)MAX(0, self.fetchBatchField.stringValue.integerValue);
  editor.includesSubentities = (self.fetchSubentitiesCheckbox.state == NSOnState);
  editor.includesPropertyValues = (self.fetchPropertyValuesCheckbox.state == NSOnState);
  editor.returnsObjectsAsFaults = (self.fetchFaultsCheckbox.state == NSOnState);
  editor.includesPendingChanges = (self.fetchPendingChangesCheckbox.state == NSOnState);
  editor.returnsDistinctResults = (self.fetchDistinctCheckbox.state == NSOnState);
}

- (IBAction)inspectorChanged:(id)sender
{
  if (_updating) return;
  /* An apply sets every field of the page; the ones that changed are one
     undo step. */
  if (sender == self.modelIdentifierField) {
    [self.modelEditor beginEdit:@"Edit Model Identifier"];
    [MBVersionEditor editorForModelEditor:self.modelEditor].versionIdentifier = self.modelIdentifierField.stringValue;
    [self.modelEditor endEdit];
    return;
  }
  _applying = YES;
  switch (_kind) {
    case MBInspectEntity:
      [self.modelEditor beginEdit:@"Edit Entity"]; [self applyEntityInspector]; break;
    case MBInspectAttribute:
      [self.modelEditor beginEdit:@"Edit Attribute"]; [self applyAttributeInspector]; break;
    case MBInspectRelationship:
      [self.modelEditor beginEdit:@"Edit Relationship"]; [self applyRelationshipInspector]; break;
    case MBInspectFetch:
      [self.modelEditor beginEdit:@"Edit Fetch Request"]; [self applyFetchInspector:sender]; break;
    case MBInspectFetchIndex:
      _applying = NO;
      [self applyFetchIndexInspector:sender];
      return;
    default:
      _applying = NO;
      return;
  }
  [self.modelEditor endEdit];
  _applying = NO;
  [self fillInspector];
}

- (void)applyFetchIndexInspector:(id)sender
{
  NSDictionary *row = [self selectedFetchIndexRow];
  if (!row) return;
  if (sender == self.fetchIndexNameField) {
    NSString *name = [self.fetchIndexNameField.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];
    if (!name.length || [name isEqualToString:row[@"name"]]) return;
    if ([[[self entityEditor].fetchIndexRows valueForKey:@"name"] containsObject:name]) {
      self.fetchIndexNameField.stringValue = row[@"name"];
      return;   /* names are unique within an entity */
    }
    [self changeSelectedFetchIndex:^(NSMutableDictionary *edited) { edited[@"name"] = name; }
                            action:@"Rename Fetch Index"];
  } else if (sender == self.fetchIndexPredicateField) {
    NSString *format = [self.fetchIndexPredicateField.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];
    if ([format isEqualToString:row[@"predicate"] ?: @""]) return;
    [self changeSelectedFetchIndex:^(NSMutableDictionary *edited) {
              if (format.length) edited[@"predicate"] = format;
              else [edited removeObjectForKey:@"predicate"];
            }
                            action:@"Edit Partial Predicate"];
  }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
  /* Table cell edits arrive here too; those are routed by the table's
     setObjectValue path, so only forward field editors of inspector
     text fields. */
  id control = notification.object;
  if ([control isKindOfClass:[NSTableView class]] ||
      [control isKindOfClass:[NSOutlineView class]])
    return;
  if ([control respondsToSelector:@selector(action)] && [control action] != NULL)
    return;   /* the action already fired */
  [self inspectorChanged:control];
}

#pragma mark - userInfo / constraints segments

- (IBAction)userInfoSegmentClicked:(id)sender
{
  if (_kind != MBInspectEntity && _kind != MBInspectAttribute && _kind != MBInspectRelationship)
    return;
  NSTableView *table = [self activeUserInfoTable];
  if ([sender selectedSegment] == 0) {
    NSMutableDictionary *info = [([self currentUserInfo] ?: @{}) mutableCopy];
    NSString *key = MBUniqueName(@"key", info.allKeys);
    info[key] = @"";
    [self setCurrentUserInfo:info];
  } else {
    NSInteger row = table.selectedRow;
    if (row < 0 || (NSUInteger)row >= _userInfoKeys.count) return;
    NSMutableDictionary *info = [([self currentUserInfo] ?: @{}) mutableCopy];
    [info removeObjectForKey:_userInfoKeys[(NSUInteger)row]];
    [self setCurrentUserInfo:info.count ? info : nil];
  }
  [self reloadUserInfoTables];
  [self.modelEditor noteModelChanged];
}

- (IBAction)constraintsSegmentClicked:(id)sender
{
  NSEntityDescription *entity = [self.modelEditor selectedEntity];
  if (!entity) return;
  if ([sender selectedSegment] == 0) {
    NSString *seed = [self attributeNamesOfSelectedEntity].firstObject ?: @"attribute";
    [_constraintRows addObject:seed];
  } else {
    NSInteger row = self.constraintsTable.selectedRow;
    if (row < 0 || (NSUInteger)row >= _constraintRows.count) return;
    [_constraintRows removeObjectAtIndex:(NSUInteger)row];
  }
  [self applyConstraintRows];
  [self.constraintsTable reloadData];
}

- (NSDictionary *)currentUserInfo
{
  if (_kind == MBInspectEntity) return [[self.modelEditor selectedEntity] userInfo];
  if (_kind == MBInspectAttribute) return [((NSAttributeDescription *)[self.modelEditor selectedProperty]) userInfo];
  if (_kind == MBInspectRelationship) return [((NSRelationshipDescription *)[self.modelEditor selectedProperty]) userInfo];
  return nil;
}

- (void)setCurrentUserInfo:(NSDictionary *)userInfo
{
  if (_kind == MBInspectEntity) [self entityEditor].userInfo = userInfo;
  else if (_kind == MBInspectAttribute) [self attributeEditor].userInfo = userInfo;
  else if (_kind == MBInspectRelationship) [self relationshipEditor].userInfo = userInfo;
  [self rebuildUserInfoRows];
}

- (void)rebuildUserInfoRows
{
  _userInfoKeys = [[[self currentUserInfo] allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
}

- (NSTableView *)activeUserInfoTable
{
  if (_kind == MBInspectEntity) return self.entityUserInfoTable;
  if (_kind == MBInspectAttribute) return self.attributeUserInfoTable;
  if (_kind == MBInspectRelationship) return self.relationshipUserInfoTable;
  return nil;
}

- (void)reloadUserInfoTables
{
  [self.entityUserInfoTable reloadData];
  [self.attributeUserInfoTable reloadData];
  [self.relationshipUserInfoTable reloadData];
}

- (void)rebuildConstraintRows
{
  _constraintRows = [[[self entityEditor] constraintRows] mutableCopy]
      ?: [NSMutableArray array];
}

- (void)applyConstraintRows
{
  [self entityEditor].constraintRows = _constraintRows;
}


#pragma mark - NSTableViewDataSource (user info, constraints)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if (table == self.constraintsTable) return (NSInteger)_constraintRows.count;
  if (table == [self activeUserInfoTable]) return (NSInteger)_userInfoKeys.count;
  return 0;
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  if (table == self.constraintsTable && row >= 0 && (NSUInteger)row < _constraintRows.count)
    return _constraintRows[(NSUInteger)row];
  if (table == [self activeUserInfoTable] && row >= 0 && (NSUInteger)row < _userInfoKeys.count) {
    NSString *key = _userInfoKeys[(NSUInteger)row];
    if ([column.identifier isEqualToString:@"value"])
      return [[self currentUserInfo][key] description] ?: @"";
    return key;
  }
  return @"";
}

- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  if (table == self.constraintsTable) {
    if (row < 0 || (NSUInteger)row >= _constraintRows.count) return;
    _constraintRows[(NSUInteger)row] = [value description] ?: @"";
    _applying = YES;
    [_modelEditor beginEdit:@"Edit Constraint"];
    [self applyConstraintRows];
    [_modelEditor endEdit];
    _applying = NO;
    [self rebuildConstraintRows];
    [self.constraintsTable reloadData];
    return;
  }
  if (table != [self activeUserInfoTable]) return;
  if (row < 0 || (NSUInteger)row >= _userInfoKeys.count) return;
  NSString *key = _userInfoKeys[(NSUInteger)row];
  NSString *text = [value description];
  NSMutableDictionary *info = [([self currentUserInfo] ?: @{}) mutableCopy];
  if ([column.identifier isEqualToString:@"value"]) {
    info[key] = text;
  } else if (text.length && !info[text]) {
    info[text] = info[key] ?: @"";
    [info removeObjectForKey:key];
  }
  _applying = YES;
  [_modelEditor beginEdit:@"Edit User Info"];
  [self setCurrentUserInfo:info];
  [_modelEditor endEdit];
  _applying = NO;
  [self reloadUserInfoTables];
}

@end
