/* ModelBuilder — the inspector (see MBInspectorViewController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBInspectorViewController.h"
#import "MBModelEditor.h"
#import "MBEditors.h"
#import "MBWindowSupport.h"
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
  MBSelection *_shownSelection;
  BOOL _showing;     /* the selection being shown: what it sets off is not shown again */
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
  _shownSelection = nil;
  [self showSelection];
}

- (void)modelDidChange:(NSNotification *)notification
{
  (void)notification;
  [self showSelection];
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
      return [self fetchIndexEditor] ? MBInspectFetchIndex : MBInspectNone;
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

- (MBFetchIndexEditor *)fetchIndexEditor
{
  MBSelection *selection = _modelEditor.selection;
  NSEntityDescription *entity = [_modelEditor selectedEntity];
  return (selection.kind == MBSelectionFetchIndex && entity)
      ? [MBFetchIndexEditor editorForFetchIndexNamed:selection.name entity:entity modelEditor:_modelEditor]
      : nil;
}

/* `editor` in `controller`: the one there told to reload when it edits
   the same, else what its fields show given to it first. */
- (void)showEditor:(MBEditor *)editor inController:(NSObjectController *)controller
{
  MBEditor *current = [controller content];
  if (editor && [current editsSameAs:editor]) {
    [current reload];
    return;
  }
  [controller commitEditing];
  [controller setContent:editor];
}

/* The selected entity's attributes, by name: a new constraint's first. */
- (NSArray *)attributeNamesOfSelectedEntity
{
  return [[[_modelEditor selectedEntity].attributesByName allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Showing the selection

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

- (void)showSelection
{
  if (_showing) return;
  _showing = YES;
  _kind = [self kindOfSelection];
  /* The Identity page describes the model version, whatever is selected:
     the tab bar can show it at any time. */
  [self showEditor:[MBVersionEditor editorForModelEditor:_modelEditor] inController:self.versionController];
  [self showEditor:_kind == MBInspectEntity ? [self entityEditor] : nil inController:self.entityController];
  [self showEditor:_kind == MBInspectAttribute ? [self attributeEditor] : nil inController:self.attributeController];
  [self showEditor:_kind == MBInspectRelationship ? [self relationshipEditor] : nil
      inController:self.relationshipController];
  [self showEditor:_kind == MBInspectFetch ? [self fetchRequestEditor] : nil inController:self.fetchController];
  [self showEditor:_kind == MBInspectFetchIndex ? [self fetchIndexEditor] : nil
      inController:self.fetchIndexController];

  /* A new selection brings its page forward; an edit of the one shown
     leaves the page the author is on. */
  MBSelection *selection = _modelEditor.selection;
  if (!_shownSelection || ![selection isEqual:_shownSelection]) {
    _shownSelection = [selection copy];
    switch (_kind) {
      case MBInspectEntity:
        [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageEntity]; break;
      case MBInspectAttribute:
        [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageAttribute]; break;
      case MBInspectRelationship:
        [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageRelationship]; break;
      case MBInspectFetch:
        [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageFetch]; break;
      case MBInspectFetchIndex:
        [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageFetchIndex]; break;
      default:
        /* configurations and empty selections have no data-model page */
        [self selectInspectorPage:MBInspectorPageIdentity kindPage:-1];
        break;
    }
  }

  /* An attribute's type has a page of its own; Derived asks before it
     changes (see -derivedToggled:). */
  MBAttributeEditor *attributeEditor = [self.attributeController content];
  if (attributeEditor) {
    [self.attributeDetailTabView
        selectTabViewItemAtIndex:MBDetailTabIndexForType(attributeEditor.attribute.attributeType)];
    self.derivedCheckbox.state = attributeEditor.isDerived ? NSOnState : NSOffState;
  }

  [self rebuildUserInfoRows];
  [self rebuildConstraintRows];
  [self.constraintsTable reloadData];
  [self reloadUserInfoTables];
  _showing = NO;
}

#pragma mark - What is not bound

- (IBAction)inspectorTabSelected:(id)sender
{
  (void)sender;
  NSUInteger index = self.inspectorTabBar.selectedIndex;
  if (index < (NSUInteger)[self.inspectorTabView numberOfTabViewItems])
    [self.inspectorTabView selectTabViewItemAtIndex:(NSInteger)index];
}

/* A prompt for a line of text: an alert, the field its accessory view
   (MBInspector.xib's).  Returns nil on Cancel. */
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
  MBAttributeEditor *editor = [self.attributeController content];
  if (!editor) return;

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

#pragma mark - userInfo / constraints segments

- (IBAction)userInfoSegmentClicked:(id)sender
{
  if (_kind != MBInspectEntity && _kind != MBInspectAttribute && _kind != MBInspectRelationship)
    return;
  NSTableView *table = [self activeUserInfoTable];
  NSMutableDictionary *info = [([self currentUserInfo] ?: @{}) mutableCopy];
  if ([sender selectedSegment] == 0) {
    info[MBUniqueName(@"key", info.allKeys)] = @"";
    [_modelEditor beginEdit:@"Add User Info"];
  } else {
    NSInteger row = table.selectedRow;
    if (row < 0 || (NSUInteger)row >= _userInfoKeys.count) return;
    [info removeObjectForKey:_userInfoKeys[(NSUInteger)row]];
    [_modelEditor beginEdit:@"Remove User Info"];
  }
  [self setCurrentUserInfo:info.count ? info : nil];
  [_modelEditor endEdit];
}

- (IBAction)constraintsSegmentClicked:(id)sender
{
  NSEntityDescription *entity = [self.modelEditor selectedEntity];
  if (!entity) return;
  if ([sender selectedSegment] == 0) {
    NSString *seed = [self attributeNamesOfSelectedEntity].firstObject ?: @"attribute";
    [_constraintRows addObject:seed];
    [_modelEditor beginEdit:@"Add Constraint"];
  } else {
    NSInteger row = self.constraintsTable.selectedRow;
    if (row < 0 || (NSUInteger)row >= _constraintRows.count) return;
    [_constraintRows removeObjectAtIndex:(NSUInteger)row];
    [_modelEditor beginEdit:@"Remove Constraint"];
  }
  [self applyConstraintRows];
  [_modelEditor endEdit];
}

/* The editor whose user info the page shows: an entity's, an
   attribute's or a relationship's. */
- (id)userInfoEditor
{
  if (_kind == MBInspectEntity) return [self.entityController content];
  if (_kind == MBInspectAttribute) return [self.attributeController content];
  if (_kind == MBInspectRelationship) return [self.relationshipController content];
  return nil;
}

- (NSDictionary *)currentUserInfo
{
  return [[self userInfoEditor] userInfo];
}

- (void)setCurrentUserInfo:(NSDictionary *)userInfo
{
  [[self userInfoEditor] setUserInfo:userInfo];
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
  _constraintRows = [[[self.entityController content] constraintRows] mutableCopy]
      ?: [NSMutableArray array];
}

- (void)applyConstraintRows
{
  [[self.entityController content] setConstraintRows:_constraintRows];
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
    [_modelEditor beginEdit:@"Edit Constraint"];
    [self applyConstraintRows];
    [_modelEditor endEdit];
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
  [_modelEditor beginEdit:@"Edit User Info"];
  [self setCurrentUserInfo:info];
  [_modelEditor endEdit];
}

@end
