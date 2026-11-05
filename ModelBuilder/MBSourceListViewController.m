/* ModelBuilder — the source list (see MBSourceListViewController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBSourceListViewController.h"
#import "MBModelEditor.h"
#import "MBEditors.h"
#import "MBWindowSupport.h"

typedef NS_ENUM(NSInteger, MBSourceKind) {
  MBSourceGroupEntities = 0,
  MBSourceGroupFetches,
  MBSourceGroupConfigurations,
  MBSourceEntity,
  MBSourceFetch,
  MBSourceConfiguration,
  MBSourceFetchIndex        /* under its entity */
};

/* One row of the source list. */
@interface MBSourceItem : NSObject
@property (nonatomic, assign) MBSourceKind kind;
@property (nonatomic, copy) NSString *name;
/* The implicit Default configuration: every entity, not in the file, and
   not editable -- what Xcode lists when a model declares none. */
@property (nonatomic, assign) BOOL implicitDefault;
/* A fetch index's entity: index names are only unique within one. */
@property (nonatomic, copy) NSString *entityName;
+ (instancetype)itemWithKind:(MBSourceKind)kind name:(NSString *)name;
- (BOOL)isGroup;
@end

@implementation MBSourceItem

+ (instancetype)itemWithKind:(MBSourceKind)kind name:(NSString *)name
{
  MBSourceItem *item = [[MBSourceItem alloc] init];
  item.kind = kind;
  item.name = name;
  return item;
}

- (BOOL)isGroup
{
  return _kind <= MBSourceGroupConfigurations;
}

@end

@implementation MBSourceListViewController {
  MBSourceItem *_entitiesGroup, *_fetchesGroup, *_configurationsGroup;
  NSArray *_entityItems, *_fetchItems, *_configurationItems;
  NSDictionary *_fetchIndexItemsByEntity;   /* entity name -> its index items */
  BOOL _showing;                            /* the selection being shown, not made */
}

- (instancetype)init
{
  return [super initWithNibName:@"MBSourceList" bundle:[NSBundle bundleForClass:[self class]]];
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
  /* Right-click menu on the source list, so a first fetch request or
     configuration can be added even when the "+" segment's context is
     the entity group. */
  NSMenu *addMenu = [[NSMenu alloc] initWithTitle:@"Add"];
  struct { NSString *title; SEL action; } addItems[] = {
    { @"Add Entity", @selector(addEntity:) },
    { @"Add Fetch Request", @selector(addFetchRequest:) },
    { @"Add Configuration", @selector(addConfiguration:) },
    { @"Add Fetch Index", @selector(addFetchIndex:) },
  };
  for (unsigned i = 0; i < sizeof(addItems) / sizeof(addItems[0]); i++) {
    NSMenuItem *item = [addMenu addItemWithTitle:addItems[i].title
                                          action:addItems[i].action
                                   keyEquivalent:@""];
    item.target = self;
  }
  [addMenu addItem:[NSMenuItem separatorItem]];
  /* To the first responder: the window's controller writes the classes. */
  [addMenu addItemWithTitle:@"Create NSManagedObject Subclass…"
                     action:NSSelectorFromString(@"createManagedObjectSubclass:")
              keyEquivalent:@""];
  self.sourceList.menu = addMenu;
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
    [center addObserver:self selector:@selector(selectionDidChange:)
                   name:MBModelEditorSelectionDidChangeNotification object:_modelEditor];
  }
  (void)self.view;
  [self reload];
}

- (NSManagedObjectModel *)model
{
  return _modelEditor.model;
}

#pragma mark - The model's items

- (void)rebuildSourceItems
{
  if (!_entitiesGroup) {
    _entitiesGroup = [MBSourceItem itemWithKind:MBSourceGroupEntities name:@"ENTITIES"];
    _fetchesGroup = [MBSourceItem itemWithKind:MBSourceGroupFetches name:@"FETCH REQUESTS"];
    _configurationsGroup = [MBSourceItem itemWithKind:MBSourceGroupConfigurations name:@"CONFIGURATIONS"];
  }
  NSMutableArray *entities = [NSMutableArray array];
  NSMutableDictionary *indexItems = [NSMutableDictionary dictionary];
  for (NSEntityDescription *entity in [_modelEditor sortedEntities]) {
    [entities addObject:[MBSourceItem itemWithKind:MBSourceEntity name:entity.name]];
    NSMutableArray *items = [NSMutableArray array];
    for (NSFetchIndexDescription *index in [entity indexes]) {
      MBSourceItem *item = [MBSourceItem itemWithKind:MBSourceFetchIndex name:index.name];
      item.entityName = entity.name;
      [items addObject:item];
    }
    if (items.count) indexItems[entity.name] = items;
  }
  _entityItems = entities;
  _fetchIndexItemsByEntity = indexItems;

  NSMutableArray *fetches = [NSMutableArray array];
  for (NSString *name in [[[self.model fetchRequestTemplatesByName] allKeys]
           sortedArrayUsingSelector:@selector(compare:)])
    [fetches addObject:[MBSourceItem itemWithKind:MBSourceFetch name:name]];
  _fetchItems = fetches;

  NSMutableArray *configurations = [NSMutableArray array];
  NSArray *declared = [_modelEditor configurationNames];
  /* Every model has the Default configuration -- all its entities, which
     is what a store added with no configuration name holds -- whether it
     declares others or not.  Xcode lists it first; so do we, unless the
     model declares a configuration of that name itself. */
  if (![declared containsObject:@"Default"]) {
    MBSourceItem *standard = [MBSourceItem itemWithKind:MBSourceConfiguration name:@"Default"];
    standard.implicitDefault = YES;
    [configurations addObject:standard];
  }
  for (NSString *name in declared)
    [configurations addObject:[MBSourceItem itemWithKind:MBSourceConfiguration name:name]];
  _configurationItems = configurations;
}

- (void)reload
{
  [self rebuildSourceItems];
  _showing = YES;
  [self.sourceList reloadData];
  [self.sourceList expandItem:_entitiesGroup];
  [self.sourceList expandItem:_fetchesGroup];
  [self.sourceList expandItem:_configurationsGroup];
  _showing = NO;
  [self showSelection];
}

- (void)modelDidChange:(NSNotification *)notification
{
  (void)notification;
  [self reload];
}

- (void)selectionDidChange:(NSNotification *)notification
{
  (void)notification;
  [self showSelection];
}

#pragma mark - The selection

- (MBSourceItem *)selectedSourceItem
{
  NSInteger row = self.sourceList.selectedRow;
  if (row < 0) return nil;
  id item = [self.sourceList itemAtRow:row];
  return ([item isKindOfClass:[MBSourceItem class]] && ![item isGroup]) ? item : nil;
}

- (MBSourceItem *)itemOfKind:(MBSourceKind)kind name:(NSString *)name entity:(NSString *)entityName
{
  if (kind == MBSourceFetchIndex) {
    for (MBSourceItem *item in _fetchIndexItemsByEntity[entityName])
      if ([item.name isEqualToString:name]) return item;
    return nil;
  }
  NSArray *pool = kind == MBSourceEntity ? _entityItems
                : kind == MBSourceFetch ? _fetchItems : _configurationItems;
  for (MBSourceItem *item in pool)
    if ([item.name isEqualToString:name]) return item;
  return nil;
}

/* The row of what the model editor has selected: an entity (also for one
   of its properties), a fetch request, a configuration (also for an entity
   picked on its page), a fetch index under its entity. */
- (MBSourceItem *)itemForSelection:(MBSelection *)selection
{
  switch (selection.kind) {
    case MBSelectionEntity:
      if (selection.configurationName)
        return [self itemOfKind:MBSourceConfiguration name:selection.configurationName entity:nil];
      return [self itemOfKind:MBSourceEntity name:selection.entityName entity:nil];
    case MBSelectionAttribute:
    case MBSelectionRelationship:
      return [self itemOfKind:MBSourceEntity name:selection.entityName entity:nil];
    case MBSelectionFetchRequest:
      return [self itemOfKind:MBSourceFetch name:selection.name entity:nil];
    case MBSelectionConfiguration:
      return [self itemOfKind:MBSourceConfiguration name:selection.configurationName entity:nil];
    case MBSelectionFetchIndex:
      return [self itemOfKind:MBSourceFetchIndex name:selection.name entity:selection.entityName];
    default:
      return nil;
  }
}

- (MBSelection *)selectionForItem:(MBSourceItem *)item
{
  switch (item.kind) {
    case MBSourceEntity:        return [MBSelection entityNamed:item.name];
    case MBSourceFetch:         return [MBSelection fetchRequestNamed:item.name];
    case MBSourceConfiguration: return [MBSelection configurationNamed:item.name];
    case MBSourceFetchIndex:
      return [MBSelection selectionOfKind:MBSelectionFetchIndex entityName:item.entityName
                                     name:item.name configurationName:nil];
    default: return nil;
  }
}

/* Shows the model editor's selection; where it names nothing that is
   there, the first entity is selected instead (after a removal). */
- (void)showSelection
{
  MBSourceItem *item = [self itemForSelection:_modelEditor.selection];
  if (!item) {
    MBSelection *selection = _modelEditor.selection;
    /* a fetch index that went: its entity */
    if (selection.kind == MBSelectionFetchIndex)
      item = [self itemOfKind:MBSourceEntity name:selection.entityName entity:nil];
    if (!item) item = _entityItems.firstObject;
    if (item) {
      _modelEditor.selection = [self selectionForItem:item];   /* shown when it is posted */
      return;
    }
  }
  if (item.kind == MBSourceFetchIndex) {
    for (MBSourceItem *entityItem in _entityItems)
      if ([entityItem.name isEqualToString:item.entityName])
        [self.sourceList expandItem:entityItem];
  }
  NSInteger row = item ? [self.sourceList rowForItem:item] : -1;
  _showing = YES;
  if (row >= 0)
    [self.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                 byExtendingSelection:NO];
  else
    [self.sourceList deselectAll:nil];
  _showing = NO;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  if (notification.object != self.sourceList || _showing) return;
  MBSourceItem *item = [self selectedSourceItem];
  if (!item) return;
  /* The same row picked again keeps what is selected within it. */
  if ([self itemForSelection:_modelEditor.selection] == item) return;
  _modelEditor.selection = [self selectionForItem:item];
}

- (NSString *)selectedEntityName
{
  return [_modelEditor selectedEntity].name;
}

#pragma mark - Adding and removing

- (IBAction)addSourceItem:(id)sender
{
  MBSourceItem *selected = [self selectedSourceItem];
  NSInteger row = self.sourceList.selectedRow;
  id rowItem = row >= 0 ? [self.sourceList itemAtRow:row] : nil;
  MBSourceKind context = MBSourceEntity;
  if (selected) context = selected.kind;
  else if (rowItem == _fetchesGroup) context = MBSourceFetch;
  else if (rowItem == _configurationsGroup) context = MBSourceConfiguration;

  if (context == MBSourceFetch) [self addFetchRequest:sender];
  else if (context == MBSourceConfiguration) [self addConfiguration:sender];
  else [self addEntity:sender];
}

- (IBAction)removeSourceItem:(id)sender
{
  (void)sender;
  MBSourceItem *selected = [self selectedSourceItem];
  if (!selected) return;
  NSError *error = nil;
  switch (selected.kind) {
    case MBSourceEntity:
      if (![_modelEditor removeEntityNamed:selected.name error:&error])
        MBPresentModelError(error, @"Cannot delete entity");
      break;
    case MBSourceFetch:
      [_modelEditor removeFetchRequestNamed:selected.name];
      break;
    case MBSourceFetchIndex: {
      NSString *entityName = selected.entityName;
      [_modelEditor beginEdit:@"Remove Fetch Index"];
      [[MBEntityEditor editorForEntityNamed:entityName modelEditor:_modelEditor]
          removeFetchIndexNamed:selected.name];
      [_modelEditor endEdit];
      _modelEditor.selection = [MBSelection entityNamed:entityName];
      break;
    }
    case MBSourceConfiguration:
      if (selected.implicitDefault) break;   /* not in the file to remove */
      if (![_modelEditor removeConfigurationNamed:selected.name error:&error])
        MBPresentModelError(error, @"Cannot remove configuration");
      break;
    default:
      break;
  }
}

- (IBAction)addEntity:(id)sender
{
  (void)sender;
  NSString *name = [_modelEditor addEntity];
  if (name) _modelEditor.selection = [MBSelection entityNamed:name];
}

- (IBAction)addFetchRequest:(id)sender
{
  (void)sender;
  NSString *name = [_modelEditor addFetchRequestForEntityNamed:[self selectedEntityName]];
  if (name) _modelEditor.selection = [MBSelection fetchRequestNamed:name];
}

- (IBAction)addConfiguration:(id)sender
{
  (void)sender;
  NSString *name = [_modelEditor addConfiguration];
  if (name) _modelEditor.selection = [MBSelection configurationNamed:name];
}

/* A new fetch index on the selected entity, shown for editing. */
- (IBAction)addFetchIndex:(id)sender
{
  (void)sender;
  NSString *entityName = [self selectedEntityName];
  if (!entityName) return;
  [_modelEditor beginEdit:@"Add Fetch Index"];
  NSString *name = [[MBEntityEditor editorForEntityNamed:entityName modelEditor:_modelEditor] addFetchIndex];
  [_modelEditor endEdit];
  if (name)
    _modelEditor.selection = [MBSelection selectionOfKind:MBSelectionFetchIndex entityName:entityName
                                                     name:name configurationName:nil];
}

/* MainMenu.xib's Model > Remove Entity. */
- (IBAction)removeEntity:(id)sender
{
  (void)sender;
  NSString *name = [self selectedEntityName];
  if (!name.length) return;
  NSError *error = nil;
  if (![_modelEditor removeEntityNamed:name error:&error])
    MBPresentModelError(error, @"Cannot delete entity");
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = item.action;
  if (action == @selector(addFetchRequest:))
    return self.model.entities.count > 0;   /* a fetch needs an entity */
  if (action == @selector(removeEntity:) || action == @selector(addFetchIndex:))
    return [self selectedEntityName] != nil;
  return YES;
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item
{
  (void)outline;
  /* The nib connects the data source -- and AppKit reloads on that --
     before -rebuildSourceItems has made the groups. */
  if (item == nil) return _entitiesGroup ? 3 : 0;
  if (item == _entitiesGroup) return (NSInteger)_entityItems.count;
  if (item == _fetchesGroup) return (NSInteger)_fetchItems.count;
  if (item == _configurationsGroup) return (NSInteger)_configurationItems.count;
  if ([item isKindOfClass:[MBSourceItem class]] && [(MBSourceItem *)item kind] == MBSourceEntity)
    return (NSInteger)[_fetchIndexItemsByEntity[[(MBSourceItem *)item name]] count];
  return 0;
}

- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item
{
  (void)outline;
  if (item == nil) {
    if (index == 0) return _entitiesGroup;
    if (index == 1) return _fetchesGroup;
    return _configurationsGroup;
  }
  if (item == _entitiesGroup) return _entityItems[(NSUInteger)index];
  if (item == _fetchesGroup) return _fetchItems[(NSUInteger)index];
  if (item == _configurationsGroup) return _configurationItems[(NSUInteger)index];
  return _fetchIndexItemsByEntity[[(MBSourceItem *)item name]][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item
{
  (void)outline;
  if (![item isKindOfClass:[MBSourceItem class]]) return NO;
  if ([item isGroup]) return YES;
  /* An entity opens to its fetch indexes, as in Xcode. */
  return [(MBSourceItem *)item kind] == MBSourceEntity &&
         [_fetchIndexItemsByEntity[[(MBSourceItem *)item name]] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
  if ([column.identifier isEqualToString:@"sourceIcon"]) {
    /* NSImageCell column: an NSImage or nil, never a string. */
    if (![item isKindOfClass:[MBSourceItem class]] || [item isGroup]) return nil;
    switch ([(MBSourceItem *)item kind]) {
      case MBSourceEntity:        return MBEntityBadge();
      case MBSourceFetch:         return MBFetchBadge();
      case MBSourceConfiguration: return MBConfigurationBadge();
      case MBSourceFetchIndex:    return MBBadgeImage(@"I", 0.52, 0.52, 0.56);
      default:                    return nil;
    }
  }
  if (column && ![column.identifier isEqualToString:@"item"] &&
      column != outline.outlineTableColumn)
    return @"";
  return [item isKindOfClass:[MBSourceItem class]] ? [item name] : @"";
}

- (void)outlineView:(NSOutlineView *)outline setObjectValue:(id)value forTableColumn:(NSTableColumn *)column byItem:(id)item
{
  if (column && ![column.identifier isEqualToString:@"item"] &&
      column != outline.outlineTableColumn)
    return;
  if (![item isKindOfClass:[MBSourceItem class]] || [item isGroup] ||
      [(MBSourceItem *)item implicitDefault]) return;
  NSString *text = [value description];
  if (!text.length) return;
  MBSourceItem *source = item;
  [_modelEditor beginEdit:@"Rename"];
  switch (source.kind) {
    case MBSourceEntity:
      [_modelEditor renameEntityNamed:source.name to:text];
      break;
    case MBSourceFetch:
      [_modelEditor renameFetchRequestNamed:source.name to:text];
      break;
    case MBSourceConfiguration:
      [_modelEditor renameConfiguration:source.name to:text error:NULL];
      break;
    case MBSourceFetchIndex: {
      MBEntityEditor *editor = [MBEntityEditor editorForEntityNamed:source.entityName
                                                        modelEditor:_modelEditor];
      NSArray *rows = editor.fetchIndexRows;
      if ([[rows valueForKey:@"name"] containsObject:text]) break;   /* unique within an entity */
      NSMutableArray *renamed = [NSMutableArray array];
      for (NSDictionary *row in rows) {
        NSMutableDictionary *copy = [row mutableCopy];
        if ([row[@"name"] isEqualToString:source.name]) copy[@"name"] = text;
        [renamed addObject:copy];
      }
      NSString *entityName = source.entityName;
      editor.fetchIndexRows = renamed;
      _modelEditor.selection = [MBSelection selectionOfKind:MBSelectionFetchIndex entityName:entityName
                                                       name:text configurationName:nil];
      break;
    }
    default:
      break;
  }
  [_modelEditor endEdit];
  [_modelEditor noteModelChanged];
}

#pragma mark - NSOutlineViewDelegate

- (BOOL)outlineView:(NSOutlineView *)outline shouldSelectItem:(id)item
{
  (void)outline;
  return [item isKindOfClass:[MBSourceItem class]] && ![item isGroup];
}

- (BOOL)outlineView:(NSOutlineView *)outline shouldEditTableColumn:(NSTableColumn *)column item:(id)item
{
  if (column && ![column.identifier isEqualToString:@"item"] &&
      column != outline.outlineTableColumn)
    return NO;
  return [item isKindOfClass:[MBSourceItem class]] && ![item isGroup] &&
         ![(MBSourceItem *)item implicitDefault];
}

- (void)outlineView:(NSOutlineView *)outline willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column item:(id)item
{
  (void)outline; (void)column;
  if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
  BOOL group = [item isKindOfClass:[MBSourceItem class]] && [item isGroup];
  NSTextFieldCell *textCell = cell;
  textCell.font = group ? [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize] - 1]
                        : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  textCell.textColor = group ? [NSColor disabledControlTextColor]
                             : [NSColor controlTextColor];
}

@end
