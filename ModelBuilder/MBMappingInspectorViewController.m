/* ModelBuilder — the mapping window's inspector (see
   MBMappingInspectorViewController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingInspectorViewController.h"
#import "MBMappingEditor.h"
#import "MBMappingEditors.h"
#import "MBWindowSupport.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"

@implementation MBMappingInspectorViewController {
  BOOL _showing;          /* what the selection sets off is not shown again */
  MBMappingSelection *_shownSelection;
  NSArray *_userInfoKeys; /* of whatever the inspector shows */
}

- (instancetype)init
{
  return [super initWithNibName:@"MBMappingInspector" bundle:[NSBundle bundleForClass:[self class]]];
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

  /* Inspector chrome, as the model window has it. */
  NSImage *identityIcon = nil, *mappingIcon = nil;
#if defined(__APPLE__)
  identityIcon = MBFirstImageNamed(@[ @"NSInfo", @"NSTouchBarGetInfoTemplate" ]);
  mappingIcon = MBFirstImageNamed(@[ @"NSActionTemplate", @"NSSmartBadgeTemplate", @"NSAdvanced" ]);
#endif
  DMTabBarItem *identityItem = [DMTabBarItem
      tabBarItemWithIcon:identityIcon ?: MBBadgeImage(@"i", 0.47, 0.53, 0.64)
                     tag:MBMappingInspectorPageIdentity];
  identityItem.toolTip = @"Identity and Type";
  DMTabBarItem *mappingItem = [DMTabBarItem
      tabBarItemWithIcon:mappingIcon ?: MBBadgeImage(@"M", 0.36, 0.49, 0.72)
                     tag:MBMappingInspectorPageMapping];
  mappingItem.toolTip = @"Mapping Model Inspector";
  self.inspectorTabBar.tabBarItems = @[ identityItem, mappingItem ];
  [self.inspectorTabBar setTarget:self action:@selector(inspectorTabSelected:)];
  self.inspectorTabBar.selectedIndex = MBMappingInspectorPageMapping;
  [self.inspectorTabView selectTabViewItemAtIndex:MBMappingInspectorPageMapping];
}

- (void)setMappingEditor:(MBMappingEditor *)mappingEditor
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  if (_mappingEditor) {
    [center removeObserver:self name:MBMappingEditorDidChangeNotification object:_mappingEditor];
    [center removeObserver:self name:MBMappingEditorSelectionDidChangeNotification object:_mappingEditor];
  }
  _mappingEditor = mappingEditor;
  if (_mappingEditor) {
    [center addObserver:self selector:@selector(mappingDidChange:)
                   name:MBMappingEditorDidChangeNotification object:_mappingEditor];
    [center addObserver:self selector:@selector(mappingDidChange:)
                   name:MBMappingEditorSelectionDidChangeNotification object:_mappingEditor];
  }
  (void)self.view;
  _shownSelection = nil;
  [self showSelection];
}

- (void)mappingDidChange:(NSNotification *)notification
{
  (void)notification;
  [self showSelection];
}

#pragma mark - Showing the selection

/* `editor` in `controller`: the one there told to reload when it edits
   the same, else what its fields show given to it first. */
- (void)showEditor:(MBMappingObjectEditor *)editor inController:(NSObjectController *)controller
{
  MBMappingObjectEditor *current = [controller content];
  if (editor && [current editsSameAs:editor]) {
    [current reload];
    return;
  }
  [controller commitEditing];
  [controller setContent:editor];
}

- (MBMappingInspectorKind)kindOfSelection
{
  switch (_mappingEditor.selection.kind) {
    case MBMappingSelectionAttributeMapping:    return MBMappingInspectorKindAttribute;
    case MBMappingSelectionRelationshipMapping: return MBMappingInspectorKindRelationship;
    default:                                    return MBMappingInspectorKindEntity;
  }
}

- (void)showSelection
{
  if (_showing) return;
  _showing = YES;
  MBMappingEditor *editor = _mappingEditor;
  MBMappingSelection *selection = editor.selection;
  NSEntityMapping *mapping = [editor selectedEntityMapping];
  MBMappingInspectorKind kind = mapping ? [self kindOfSelection] : MBMappingInspectorKindEntity;

  [self.sourceModelLabel setStringValue:editor.sourceModelPath ?: @""];
  [self.destinationModelLabel setStringValue:editor.destinationModelPath ?: @""];

  [self showEditor:[MBEntityMappingEditor editorForEntityMapping:mapping mappingEditor:editor]
      inController:self.entityMappingController];
  [self showEditor:kind == MBMappingInspectorKindAttribute
                       ? [MBPropertyMappingEditor editorForPropertyNamed:selection.propertyName inEntityMapping:mapping
                                                           relationships:NO mappingEditor:editor]
                       : nil
      inController:self.attributeMappingController];
  [self showEditor:kind == MBMappingInspectorKindRelationship
                       ? [MBPropertyMappingEditor editorForPropertyNamed:selection.propertyName inEntityMapping:mapping
                                                           relationships:YES mappingEditor:editor]
                       : nil
      inController:self.relationshipMappingController];

  /* A new selection brings its page forward; an edit of the one shown
     leaves the page the author is on. */
  if (!_shownSelection || ![selection isEqual:_shownSelection]) {
    _shownSelection = [selection copy];
    [self.inspectorKindTabView selectTabViewItemAtIndex:kind];
  }

  /* What fills the row when nothing is written, where the typing goes. */
  MBPropertyMappingEditor *attributeEditor = [self.attributeMappingController content];
  [[self.attributeExpressionField cell] setPlaceholderString:
      attributeEditor ? attributeEditor.generatedExpressionString : @"Value Expression"];

  [self reloadUserInfo];
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

/* The editor whose user info the page shows. */
- (MBMappingObjectEditor *)userInfoEditor
{
  switch ([self.inspectorKindTabView indexOfTabViewItem:[self.inspectorKindTabView selectedTabViewItem]]) {
    case MBMappingInspectorKindAttribute:    return [self.attributeMappingController content];
    case MBMappingInspectorKindRelationship: return [self.relationshipMappingController content];
    default:                                 return [self.entityMappingController content];
  }
}

- (NSTableView *)activeUserInfoTable
{
  switch ([self.inspectorKindTabView indexOfTabViewItem:[self.inspectorKindTabView selectedTabViewItem]]) {
    case MBMappingInspectorKindAttribute:    return self.attributeUserInfoTable;
    case MBMappingInspectorKindRelationship: return self.relationshipUserInfoTable;
    default:                                 return self.entityUserInfoTable;
  }
}

- (void)reloadUserInfo
{
  _userInfoKeys = [[[[self userInfoEditor] userInfo] allKeys] sortedArrayUsingSelector:@selector(compare:)] ?: @[];
  [self.entityUserInfoTable reloadData];
  [self.attributeUserInfoTable reloadData];
  [self.relationshipUserInfoTable reloadData];
}

- (IBAction)userInfoSegmentClicked:(id)sender
{
  MBMappingObjectEditor *editor = [self userInfoEditor];
  if (editor == nil) return;
  NSMutableDictionary *info = [(editor.userInfo ?: @{}) mutableCopy];
  if ([sender selectedSegment] == 0) {
    NSString *key = @"key";
    for (NSUInteger n = 2; info[key]; n++) key = [NSString stringWithFormat:@"key%lu", (unsigned long)n];
    info[key] = @"";
  } else {
    NSInteger row = [[self activeUserInfoTable] selectedRow];
    if (row < 0 || (NSUInteger)row >= _userInfoKeys.count) return;
    [info removeObjectForKey:_userInfoKeys[(NSUInteger)row]];
  }
  editor.userInfo = info;
}

#pragma mark - NSTableViewDataSource (user info)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return table == [self activeUserInfoTable] ? (NSInteger)_userInfoKeys.count : 0;
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  if (table != [self activeUserInfoTable] || row < 0 || row >= (NSInteger)_userInfoKeys.count) return nil;
  NSString *key = _userInfoKeys[(NSUInteger)row];
  if ([[column identifier] isEqualToString:@"key"]) return key;
  return [[[self userInfoEditor].userInfo objectForKey:key] description] ?: @"";
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  (void)column;
  (void)row;
  return table == [self activeUserInfoTable];
}

- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  if (table != [self activeUserInfoTable] || row < 0 || row >= (NSInteger)_userInfoKeys.count) return;
  MBMappingObjectEditor *editor = [self userInfoEditor];
  NSString *typed = [value isKindOfClass:[NSString class]] ? value : [value description];
  NSString *key = _userInfoKeys[(NSUInteger)row];
  NSMutableDictionary *info = [(editor.userInfo ?: @{}) mutableCopy];
  if ([[column identifier] isEqualToString:@"key"]) {
    if (typed.length == 0 || info[typed]) {
      [table reloadData];
      return;
    }
    id kept = info[key];
    [info removeObjectForKey:key];
    info[typed] = kept ?: @"";
  } else {
    info[key] = typed ?: @"";
  }
  editor.userInfo = info;
}

@end
