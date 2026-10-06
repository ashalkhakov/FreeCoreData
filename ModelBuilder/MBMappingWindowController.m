/* ModelBuilder mapping window.  See MBMappingWindowController.h.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingWindowController.h"
#import "MBMappingDocument.h"
#import "MBWindowSupport.h"
#import "JUInspectorView.h"
#import "JUInspectorViewContainer.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"

/* The source list's one group; its children are the entity mappings. */
static NSString *const MBEntityMappingsGroup = @"ENTITY MAPPINGS";

/* The narrowest the panes may get, as in the model window. */
static const CGFloat MBMappingListMinimum = 160.0;
static const CGFloat MBMappingCenterMinimum = 320.0;
static const CGFloat MBMappingInspectorMinimum = 260.0;

/* Identity, not equality: two mappings can say the same things. */
static NSHashTable *MBIdentitySet(void)
{
  return [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory
                                           | NSPointerFunctionsObjectPointerPersonality];
}

@implementation MBMappingWindowController
{
  BOOL _updating;
  NSSplitView *_outerSplit, *_barSplit, *_sourceSplit;

  NSEntityMapping *_selectedEntityMapping;
  NSPropertyMapping *_selectedPropertyMapping;
  BOOL _selectedIsRelationship;

  NSArray *_attributeMappings;      /* of the selected mapping, as shown */
  NSArray *_relationshipMappings;
  NSArray *_userInfoKeys;           /* of whatever the inspector shows */

  /* "Custom" chosen in a Source Fetch popup before anything custom has
     been written: there is nothing in the mapping yet to say so. */
  NSHashTable *_customFetches;
  NSHashTable *_customRelationships;
}

- (MBMappingDocument *)mappingDocument
{
  return (MBMappingDocument *)[self document];
}

- (NSEntityMapping *)selectedEntityMapping
{
  return _selectedEntityMapping;
}

- (NSPropertyMapping *)selectedPropertyMapping
{
  return _selectedPropertyMapping;
}

#pragma mark - Nib assembly

- (void)windowDidLoad
{
  [super windowDidLoad];

  _customFetches = MBIdentitySet();
  _customRelationships = MBIdentitySet();

  MBRepairSegmentImages(self.window.contentView);
  MBEnableTypingUndoIn(self.window.contentView);
  if (!self.window.delegate) self.window.delegate = self;

  _outerSplit = MBFirstSplitViewIn(self.window.contentView);
  _barSplit = MBFirstSplitViewIn(_outerSplit.subviews.firstObject);
  _sourceSplit = MBFirstSplitViewIn(_barSplit.subviews.firstObject);
  for (NSSplitView *split in @[ _outerSplit ?: (id)[NSNull null],
                                _barSplit ?: (id)[NSNull null],
                                _sourceSplit ?: (id)[NSNull null] ])
    if ([split isKindOfClass:[NSSplitView class]]) split.delegate = self;
  self.window.minSize = NSMakeSize(MBMappingListMinimum + MBMappingCenterMinimum +
                                       MBMappingInspectorMinimum + 2.0,
                                   480.0);

  /* GNUstep's GSXib5 does not apply runtime attributes to nested
     subviews; backfill the section names and order (no-ops on macOS). */
  if (!self.attributesInspector.name.length)
    self.attributesInspector.name = @"Attribute Mappings";
  if (!self.relationshipsInspector.name.length)
    self.relationshipsInspector.name = @"Relationship Mappings";
  if (self.relationshipsInspector.index == self.attributesInspector.index) {
    self.relationshipsInspector.index = 1;
    [self.mappingInspectorContainer arrangeViews];
  }

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

  /* A click on the mapping already selected brings its own inspector
     back from a property's; a selection change would not. */
  self.sourceList.target = self;
  self.sourceList.action = @selector(sourceListClicked:);

  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(undoManagerDidReplay:)
                 name:NSUndoManagerDidUndoChangeNotification object:nil];
  [center addObserver:self selector:@selector(undoManagerDidReplay:)
                 name:NSUndoManagerDidRedoChangeNotification object:nil];

  [self reload];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setDocument:(id)document
{
  [super setDocument:document];
  if ([self isWindowLoaded]) [self reload];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
  (void)window;
  return [[self mappingDocument] undoManager];
}

/* An undo or redo changes the mapping under the window; show it. */
- (void)undoManagerDidReplay:(NSNotification *)notification
{
  if ([notification object] == [[self mappingDocument] undoManager]) [self reload];
}

#pragma mark - What is shown

- (void)selectEntityMapping:(NSEntityMapping *)mapping
{
  _selectedEntityMapping = mapping;
  _selectedPropertyMapping = nil;
  [self reload];
}

- (void)reload
{
  MBMappingDocument *document = [self mappingDocument];
  NSArray *mappings = [document entityMappings];

  _updating = YES;

  if (![mappings containsObject:_selectedEntityMapping]) {
    _selectedEntityMapping = mappings.firstObject;
    _selectedPropertyMapping = nil;
  }

  [self.sourceList reloadData];
  [self.sourceList expandItem:MBEntityMappingsGroup];
  NSInteger row = _selectedEntityMapping ? [self.sourceList rowForItem:_selectedEntityMapping] : -1;
  if (row >= 0)
    [self.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                 byExtendingSelection:NO];
  else
    [self.sourceList deselectAll:nil];

  NSEntityMapping *mapping = _selectedEntityMapping;

  _attributeMappings = mapping ? [document attributeMappingsOfEntityMapping:mapping] : @[];
  _relationshipMappings = mapping ? [document relationshipMappingsOfEntityMapping:mapping] : @[];
  if (_selectedPropertyMapping
      && ![_attributeMappings containsObject:_selectedPropertyMapping]
      && ![_relationshipMappings containsObject:_selectedPropertyMapping])
    _selectedPropertyMapping = nil;

  [self.attributeMappingTable reloadData];
  [self.relationshipMappingTable reloadData];
  [self selectRowOf:(_selectedIsRelationship ? nil : _selectedPropertyMapping)
            inTable:self.attributeMappingTable rows:_attributeMappings];
  [self selectRowOf:(_selectedIsRelationship ? _selectedPropertyMapping : nil)
            inTable:self.relationshipMappingTable rows:_relationshipMappings];

  [self.entityMappingSegmentedControl setEnabled:(mapping != nil) forSegment:1];

  [self fillInspector];

  _updating = NO;
}

- (void)selectRowOf:(id)object inTable:(NSTableView *)table rows:(NSArray *)rows
{
  NSUInteger index = object ? [rows indexOfObjectIdenticalTo:object] : NSNotFound;

  if (index == NSNotFound)
    [table deselectAll:nil];
  else
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
}

#pragma mark - The inspector

/* The popups' items carry the name they stand for; the first, "None",
   stands for no entity. */
static void MBFillPopup(NSPopUpButton *popup, NSString *noneTitle, NSArray *names, NSString *selected)
{
  [popup removeAllItems];
  if (noneTitle) {
    [popup addItemWithTitle:noneTitle];
    [[popup lastItem] setRepresentedObject:nil];
  }
  for (NSString *name in names) {
    [popup addItemWithTitle:name];
    [[popup lastItem] setRepresentedObject:name];
  }
  NSInteger index = selected ? [popup indexOfItemWithRepresentedObject:selected] : -1;
  if (index < 0 && selected.length) {
    /* A name the model no longer has is still what the file says. */
    [popup addItemWithTitle:selected];
    [[popup lastItem] setRepresentedObject:selected];
    index = [popup numberOfItems] - 1;
  }
  [popup selectItemAtIndex:index >= 0 ? index : 0];
}

static NSArray *MBPropertyNames(NSEntityDescription *entity, BOOL relationships)
{
  NSMutableArray *names = [NSMutableArray array];

  for (NSPropertyDescription *property in [entity properties])
    if ([property isKindOfClass:[NSRelationshipDescription class]] == relationships)
      [names addObject:[property name]];
  return names;
}

static NSArray *MBSortedEntityNames(NSManagedObjectModel *model)
{
  return [[[model entitiesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (id)inspectedObject
{
  return _selectedPropertyMapping ?: _selectedEntityMapping;
}

- (NSTableView *)activeUserInfoTable
{
  if (_selectedPropertyMapping == nil) return self.entityUserInfoTable;
  return _selectedIsRelationship ? self.relationshipUserInfoTable : self.attributeUserInfoTable;
}

- (void)fillInspector
{
  MBMappingDocument *document = [self mappingDocument];
  NSEntityMapping *mapping = _selectedEntityMapping;

  [self.sourceModelLabel setStringValue:[document sourceModelPath] ?: @""];
  [self.destinationModelLabel setStringValue:[document destinationModelPath] ?: @""];

  MBMappingInspectorKind kind = (_selectedPropertyMapping == nil) ? MBMappingInspectorKindEntity
      : (_selectedIsRelationship ? MBMappingInspectorKindRelationship : MBMappingInspectorKindAttribute);
  [self.inspectorKindTabView selectTabViewItemAtIndex:kind];

  _userInfoKeys = [[[[self inspectedObject] userInfo] allKeys]
      sortedArrayUsingSelector:@selector(compare:)] ?: @[];

  switch (kind) {
    case MBMappingInspectorKindEntity:
      [self fillEntityInspector:mapping];
      break;
    case MBMappingInspectorKindAttribute:
      [self fillAttributeInspector:_selectedPropertyMapping];
      break;
    case MBMappingInspectorKindRelationship:
      [self fillRelationshipInspector:_selectedPropertyMapping];
      break;
  }
  [[self activeUserInfoTable] reloadData];
}

- (void)fillEntityInspector:(NSEntityMapping *)mapping
{
  MBMappingDocument *document = [self mappingDocument];
  BOOL present = (mapping != nil);
  BOOL fetches = present && [mapping sourceEntityName].length > 0;
  NSString *predicate = present ? [document filterPredicateOfEntityMapping:mapping] : nil;
  BOOL custom = fetches && (predicate != nil || [_customFetches containsObject:mapping]);

  [self.entityMappingNameField setStringValue:[mapping name] ?: @""];
  MBFillPopup(self.sourceEntityPopup, @"None", MBSortedEntityNames([document sourceModel]),
              [mapping sourceEntityName]);
  MBFillPopup(self.destinationEntityPopup, @"None", MBSortedEntityNames([document destinationModel]),
              [mapping destinationEntityName]);
  [self.mappingTypeLabel setStringValue:present ? [document mappingTypeNameOfEntityMapping:mapping] : @""];
  [self.customPolicyField setStringValue:[mapping entityMigrationPolicyClassName] ?: @""];
  [self.sourceFetchPopup selectItemAtIndex:custom ? 1 : 0];
  [self.filterPredicateField setStringValue:predicate ?: @""];

  for (NSControl *control in @[ self.entityMappingNameField, self.sourceEntityPopup,
                                self.destinationEntityPopup, self.customPolicyField,
                                self.entityUserInfoSegmentedControl ])
    [control setEnabled:present];
  /* An added entity is fetched from nowhere: nothing to choose, nothing
     to narrow. */
  [self.sourceFetchPopup setEnabled:fetches];
  [self.filterPredicateField setEnabled:custom];
}

- (void)fillAttributeInspector:(NSPropertyMapping *)property
{
  MBMappingDocument *document = [self mappingDocument];
  NSEntityDescription *destination = [[[document destinationModel] entitiesByName]
      objectForKey:[_selectedEntityMapping destinationEntityName]];
  NSString *written = [document valueExpressionStringOfPropertyMapping:property];

  MBFillPopup(self.attributeNamePopup, nil, MBPropertyNames(destination, NO), [property name]);
  [self.attributeExpressionField setStringValue:written ?: @""];
  /* What fills it when nothing is written, shown where the typing goes. */
  [[self.attributeExpressionField cell] setPlaceholderString:
      (written == nil && [property valueExpression]) ? [[property valueExpression] description]
                                                     : @"Value Expression"];
}

- (void)fillRelationshipInspector:(NSPropertyMapping *)property
{
  MBMappingDocument *document = [self mappingDocument];
  NSEntityDescription *destination = [[[document destinationModel] entitiesByName]
      objectForKey:[_selectedEntityMapping destinationEntityName]];
  NSString *keyPath = nil, *mappingName = nil;
  BOOL generated = [document relationshipMapping:property
                                 inEntityMapping:_selectedEntityMapping
                                         keyPath:&keyPath
                                     mappingName:&mappingName];
  BOOL automatic = generated && ![_customRelationships containsObject:property];

  MBFillPopup(self.relationshipNamePopup, nil, MBPropertyNames(destination, YES), [property name]);
  [self.relationshipSourceFetchPopup selectItemAtIndex:automatic ? 0 : 1];
  [self.relationshipKeyPathField setStringValue:automatic ? (keyPath ?: @"") : @""];
  [self.relationshipMappingNameField setStringValue:automatic ? (mappingName ?: @"") : @""];
  [self.relationshipExpressionField setStringValue:
      automatic ? @"" : ([[property valueExpression] description] ?: @"")];
  [self.relationshipKeyPathField setEnabled:automatic];
  [self.relationshipMappingNameField setEnabled:automatic];
  [self.relationshipExpressionField setEnabled:!automatic];
}

#pragma mark - Inspector writes

static NSString *MBTrimmed(id sender)
{
  return [[sender stringValue] stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (IBAction)inspectorChanged:(id)sender
{
  if (_updating) return;

  MBMappingDocument *document = [self mappingDocument];
  NSEntityMapping *mapping = _selectedEntityMapping;
  NSPropertyMapping *property = _selectedPropertyMapping;
  NSError *error = nil;

  if (mapping == nil) return;

  if (sender == self.entityMappingNameField) {
    [document setName:MBTrimmed(sender) ofEntityMapping:mapping];
  } else if (sender == self.sourceEntityPopup || sender == self.destinationEntityPopup) {
    [document setSourceEntityName:[[self.sourceEntityPopup selectedItem] representedObject]
            destinationEntityName:[[self.destinationEntityPopup selectedItem] representedObject]
                  ofEntityMapping:mapping];
  } else if (sender == self.customPolicyField) {
    [document setMigrationPolicyClassName:MBTrimmed(sender) ofEntityMapping:mapping];
  } else if (sender == self.sourceFetchPopup) {
    if ([sender indexOfSelectedItem] == 1) {
      [_customFetches addObject:mapping];
    } else {
      [_customFetches removeObject:mapping];
      [document setFilterPredicate:nil forEntityMapping:mapping];
    }
  } else if (sender == self.filterPredicateField) {
    NSString *typed = MBTrimmed(sender);
    [document setFilterPredicate:typed.length ? typed : nil forEntityMapping:mapping];
  } else if (sender == self.attributeNamePopup || sender == self.relationshipNamePopup) {
    [document setName:[[sender selectedItem] representedObject]
        ofPropertyMapping:property
          inEntityMapping:mapping];
  } else if (sender == self.attributeExpressionField || sender == self.relationshipExpressionField) {
    if (![document setValueExpressionString:MBTrimmed(sender) ofPropertyMapping:property error:&error])
      [self presentError:error];
  } else if (sender == self.relationshipSourceFetchPopup) {
    if ([sender indexOfSelectedItem] == 1) {
      [_customRelationships addObject:property];
    } else {
      /* Back to what the compiler works out from the names. */
      [_customRelationships removeObject:property];
      [document setValueExpressionString:nil ofPropertyMapping:property error:NULL];
    }
  } else if (sender == self.relationshipKeyPathField || sender == self.relationshipMappingNameField) {
    [document setKeyPath:MBTrimmed(self.relationshipKeyPathField)
             mappingName:MBTrimmed(self.relationshipMappingNameField)
   ofRelationshipMapping:property];
  }

  [self reload];
}

- (IBAction)inspectorTabSelected:(id)sender
{
  (void)sender;
  NSUInteger index = self.inspectorTabBar.selectedIndex;
  if (index < (NSUInteger)[self.inspectorTabView numberOfTabViewItems])
    [self.inspectorTabView selectTabViewItemAtIndex:(NSInteger)index];
}

- (IBAction)userInfoSegmentClicked:(id)sender
{
  id subject = [self inspectedObject];
  if (subject == nil) return;

  NSMutableDictionary *info = [([subject userInfo] ?: @{}) mutableCopy];

  if ([sender selectedSegment] == 0) {
    NSString *key = @"key";
    for (NSUInteger n = 2; info[key]; n++) key = [NSString stringWithFormat:@"key%lu", (unsigned long)n];
    info[key] = @"";
  } else {
    NSInteger row = [[self activeUserInfoTable] selectedRow];
    if (row < 0 || (NSUInteger)row >= _userInfoKeys.count) return;
    [info removeObjectForKey:_userInfoKeys[(NSUInteger)row]];
  }
  [[self mappingDocument] setUserInfo:info ofMappingObject:subject];
  [self reload];
}

#pragma mark - Adding and removing

- (IBAction)entityMappingSegmentClicked:(id)sender
{
  if ([sender selectedSegment] == 0)
    [self addEntityMapping:sender];
  else
    [self removeEntityMapping:sender];
}

/* A new mapping starts out pairing the first entity of each model, which
   is a pairing to correct in the inspector rather than a question to
   answer first. */
- (IBAction)addEntityMapping:(id)sender
{
  MBMappingDocument *document = [self mappingDocument];
  NSString *source = MBSortedEntityNames([document sourceModel]).firstObject;
  NSString *destination = MBSortedEntityNames([document destinationModel]).firstObject;

  if (source == nil && destination == nil) return;

  [self selectEntityMapping:[document addEntityMappingFromEntityNamed:source
                                                       toEntityNamed:destination]];
}

- (IBAction)removeEntityMapping:(id)sender
{
  NSEntityMapping *mapping = _selectedEntityMapping;

  if (mapping == nil) return;

  NSArray *mappings = [[self mappingDocument] entityMappings];
  NSUInteger index = [mappings indexOfObjectIdenticalTo:mapping];

  [[self mappingDocument] removeEntityMapping:mapping];

  mappings = [[self mappingDocument] entityMappings];
  [self selectEntityMapping:mappings.count ? mappings[MIN(index, mappings.count - 1)] : nil];
}

#pragma mark - The source list

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
  if (item == nil) return 1;
  if (item == MBEntityMappingsGroup) return (NSInteger)[[[self mappingDocument] entityMappings] count];
  return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
  if (item == nil) return MBEntityMappingsGroup;
  return [[self mappingDocument] entityMappings][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
  return item == MBEntityMappingsGroup;
}

- (id)outlineView:(NSOutlineView *)outlineView
    objectValueForTableColumn:(NSTableColumn *)column
                       byItem:(id)item
{
  if (item == MBEntityMappingsGroup) return item;
  return [(NSEntityMapping *)item name] ?: @"";
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
  return item == MBEntityMappingsGroup;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
  return item != MBEntityMappingsGroup;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
    shouldEditTableColumn:(NSTableColumn *)column
                     item:(id)item
{
  return item != MBEntityMappingsGroup;
}

- (void)outlineView:(NSOutlineView *)outlineView
     setObjectValue:(id)value
     forTableColumn:(NSTableColumn *)column
             byItem:(id)item
{
  if (item == MBEntityMappingsGroup || ![value isKindOfClass:[NSString class]]) return;
  [[self mappingDocument] setName:MBTrimmed(value) ofEntityMapping:item];
  [self reload];
}

- (void)sourceListClicked:(id)sender
{
  id item = [self.sourceList itemAtRow:[self.sourceList clickedRow]];

  if ([item isKindOfClass:[NSEntityMapping class]] && _selectedPropertyMapping != nil)
    [self selectEntityMapping:item];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  if (_updating) return;

  id item = [self.sourceList itemAtRow:[self.sourceList selectedRow]];

  if ([item isKindOfClass:[NSEntityMapping class]]) [self selectEntityMapping:item];
}

#pragma mark - The tables

- (NSArray *)rowsForTable:(NSTableView *)table
{
  if (table == self.attributeMappingTable) return _attributeMappings ?: @[];
  if (table == self.relationshipMappingTable) return _relationshipMappings ?: @[];
  return _userInfoKeys ?: @[];
}

- (BOOL)isUserInfoTable:(NSTableView *)table
{
  return table == self.entityUserInfoTable || table == self.attributeUserInfoTable
      || table == self.relationshipUserInfoTable;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if ([self isUserInfoTable:table] && table != [self activeUserInfoTable]) return 0;
  return (NSInteger)[[self rowsForTable:table] count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  NSArray *rows = [self rowsForTable:table];

  if (row < 0 || row >= (NSInteger)rows.count) return nil;

  if ([self isUserInfoTable:table]) {
    NSString *key = rows[(NSUInteger)row];
    if ([[column identifier] isEqualToString:@"key"]) return key;
    return [[[[self inspectedObject] userInfo] objectForKey:key] description] ?: @"";
  }

  NSPropertyMapping *property = rows[(NSUInteger)row];

  /* What fills the property, written or worked out, as Xcode shows it. */
  if ([[column identifier] isEqualToString:@"expression"])
    return [[property valueExpression] description] ?: @"";
  return [property name] ?: @"";
}

- (BOOL)tableView:(NSTableView *)table
    shouldEditTableColumn:(NSTableColumn *)column
                      row:(NSInteger)row
{
  if ([self isUserInfoTable:table]) return YES;
  return [[column identifier] isEqualToString:@"expression"];
}

- (void)tableView:(NSTableView *)table
   setObjectValue:(id)value
   forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row
{
  NSArray *rows = [self rowsForTable:table];
  NSString *typed = [value isKindOfClass:[NSString class]] ? value : [value description];

  if (row < 0 || row >= (NSInteger)rows.count) return;

  if ([self isUserInfoTable:table]) {
    id subject = [self inspectedObject];
    NSString *key = rows[(NSUInteger)row];
    NSMutableDictionary *info = [([subject userInfo] ?: @{}) mutableCopy];

    if ([[column identifier] isEqualToString:@"key"]) {
      if (typed.length == 0 || info[typed]) { [table reloadData]; return; }
      id kept = info[key];
      [info removeObjectForKey:key];
      info[typed] = kept ?: @"";
    } else {
      info[key] = typed ?: @"";
    }
    [[self mappingDocument] setUserInfo:info ofMappingObject:subject];
    [self reload];
    return;
  }

  if (![[column identifier] isEqualToString:@"expression"]) return;

  NSPropertyMapping *property = rows[(NSUInteger)row];
  NSString *was = [[property valueExpression] description] ?: @"";
  NSError *error = nil;

  if ([typed isEqualToString:was]) return;
  if (![[self mappingDocument] setValueExpressionString:typed
                                     ofPropertyMapping:property
                                                 error:&error])
    [self presentError:error];
  [self reload];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  if (_updating) return;

  NSTableView *table = [notification object];

  if (table != self.attributeMappingTable && table != self.relationshipMappingTable) return;

  NSInteger row = [table selectedRow];
  NSArray *rows = [self rowsForTable:table];

  if (row >= 0 && row < (NSInteger)rows.count) {
    _selectedPropertyMapping = rows[(NSUInteger)row];
    _selectedIsRelationship = (table == self.relationshipMappingTable);
  } else if ((table == self.relationshipMappingTable) == _selectedIsRelationship) {
    _selectedPropertyMapping = nil;
  } else {
    return;   /* the other table's row was deselected for this one */
  }
  [self reload];
}

#pragma mark - Split views

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
  NSArray *panes = splitView.subviews;
  if (splitView == _barSplit) return subview != panes.lastObject;
  if (splitView == _outerSplit) {
    if (NSWidth(splitView.bounds) < self.window.minSize.width) return YES;
    return subview != panes.lastObject;
  }
  if (splitView == _sourceSplit) {
    if (NSWidth(splitView.bounds) < MBMappingListMinimum + MBMappingCenterMinimum) return YES;
    return subview != panes.firstObject;
  }
  return YES;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  (void)dividerIndex;
  if (splitView == _barSplit) return proposed;
  return MAX(proposed, splitView == _outerSplit ? MBMappingListMinimum + MBMappingCenterMinimum
                                                : MBMappingListMinimum);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  (void)dividerIndex;
  if (splitView == _outerSplit)
    return MIN(proposed, NSWidth(splitView.bounds) - MBMappingInspectorMinimum - splitView.dividerThickness);
  if (splitView == _sourceSplit)
    return MIN(proposed, NSWidth(splitView.bounds) - MBMappingCenterMinimum - splitView.dividerThickness);
  return proposed;
}

#if !defined(__APPLE__)
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
  (void)oldSize;
  MBDistributeSplitSubviews(splitView, self);
}
#endif

@end
