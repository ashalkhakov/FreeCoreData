/* ModelBuilder document window — behavior for MBDocumentWindow.xib.
   The layout lives in the xib; this controller wires outlets to the
   live NSManagedObjectModel.  Editing semantics: the tables and
   inspector mutate NSEntityDescription / NSAttributeDescription /
   NSRelationshipDescription directly; structural surgery (delete
   entity, reparent, configuration changes) goes through MBDocument's
   XML mutation path so momc renormalizes the graph.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBWindowController.h"
#import "MBDocument.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"
#import "CDCodeGenerator.h"
#import "MBEditors.h"
#import "JUInspectorView.h"
#import "JUInspectorViewContainer.h"
#import "DMTabBar.h"
#import "DMTabBarItem.h"

typedef NS_ENUM(NSInteger, MBSourceKind) {
  MBSourceGroupEntities = 0,
  MBSourceGroupFetches,
  MBSourceGroupConfigurations,
  MBSourceEntity,
  MBSourceFetch,
  MBSourceConfiguration
};

/* One row of the source list. */
/* The inspector's document view.  Flipped, so its pages hang from the top
   and it grows downwards: taller than the inspector and it scrolls from
   the top, shorter and the space is left below it.  (NSTabView cannot be
   flipped from a xib, hence a view to hold it.) */
@interface MBFlippedView : NSView
@end

@implementation MBFlippedView
- (BOOL)isFlipped { return YES; }
@end

/* The field editor's undo manager.  Typing is recorded here, never in the
   document's (which groups explicitly, and refuses AppKit's ungrouped
   typing registrations -- taking the keystroke with it).  Once a field's
   edit is committed its typing is cleared, and with nothing of its own
   this manager passes Ctrl+Z on to the document's.  It is the only one the
   field editor ever sees: GNUstep's text view clears ALL actions of its
   undo manager when it resigns, which on the document's would wipe the
   whole history. */
@interface MBTypingUndoManager : NSUndoManager
@property (nonatomic, weak) NSUndoManager *fallback;
@end

@implementation MBTypingUndoManager
- (BOOL)canUndo { return [super canUndo] || [self.fallback canUndo]; }
- (BOOL)canRedo { return [super canRedo] || [self.fallback canRedo]; }
- (void)undo
{
  if ([super canUndo]) [super undo];
  else [self.fallback undo];
}
- (void)redo
{
  if ([super canRedo]) [super redo];
  else [self.fallback redo];
}
- (NSString *)undoMenuItemTitle
{
  return [super canUndo] ? [super undoMenuItemTitle] : [self.fallback undoMenuItemTitle];
}
- (NSString *)redoMenuItemTitle
{
  return [super canRedo] ? [super redoMenuItemTitle] : [self.fallback redoMenuItemTitle];
}
- (NSString *)undoActionName
{
  return [super canUndo] ? [super undoActionName] : [self.fallback undoActionName];
}
- (NSString *)redoActionName
{
  return [super canRedo] ? [super redoActionName] : [self.fallback redoActionName];
}
@end

@interface MBSourceItem : NSObject
@property (nonatomic, assign) MBSourceKind kind;
@property (nonatomic, copy) NSString *name;
/* The implicit Default configuration: every entity, not in the file, and
   not editable -- what Xcode lists when a model declares none. */
@property (nonatomic, assign) BOOL implicitDefault;
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

typedef NS_ENUM(NSInteger, MBInspectKind) {
  MBInspectNone = 0,
  MBInspectEntity,
  MBInspectAttribute,
  MBInspectRelationship,
  MBInspectFetch,
  MBInspectConfiguration
};

/* inspectorTabView pages */
enum { MBInspectorPageIdentity = 0, MBInspectorPageDataModel = 1 };
/* inspectorKindTabView pages */
enum { MBKindPageEntity = 0, MBKindPageFetch = 1, MBKindPageAttribute = 2, MBKindPageRelationship = 3 };
/* centerTabView pages */
enum { MBCenterPageEntity = 0, MBCenterPageFetch = 1, MBCenterPageConfiguration = 2 };
/* predicateTabView pages */
enum { MBPredicatePageEditor = 0, MBPredicatePageSource = 1 };

#pragma mark - Small portable helpers

static NSString *const MBNotSerializedTip =
    @"Not serialized by FreeCoreData's model format yet; the value would be lost on save.";

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

static NSImage *MBBadgeImage(NSString *letters, CGFloat red, CGFloat green, CGFloat blue);

static NSImage *MBFirstImageNamed(NSArray *names)
{
  for (NSString *name in names) {
    NSImage *image = [NSImage imageNamed:name];
    if (image) return image;
  }
  return nil;
}

/* Segment images named in the xib (NSAddTemplate, NSRemoveTemplate) are
   Apple system images.  Where the name resolves to nothing, GSXib5 hands
   the segment the bare name string instead of nil, and the first draw
   sends it -size.  Swap any such segment to a text label. */
static void MBRepairSegmentImages(NSView *view)
{
  if ([view isKindOfClass:[NSSegmentedControl class]]) {
    NSSegmentedControl *control = (NSSegmentedControl *)view;
    for (NSInteger i = 0; i < control.segmentCount; i++) {
      id image = [control imageForSegment:i];
      if (image == nil || [image isKindOfClass:[NSImage class]]) continue;
      NSString *name = [image description];
      NSString *label = name;
      if ([name rangeOfString:@"Add"].location != NSNotFound) label = @"+";
      else if ([name rangeOfString:@"Remove"].location != NSNotFound) label = @"−";
      [control setImage:nil forSegment:i];
      [control setLabel:label forSegment:i];
    }
  }
  for (NSView *subview in view.subviews)
    MBRepairSegmentImages(subview);
  /* A tab view's subviews hold only the selected page. */
  if ([view isKindOfClass:[NSTabView class]])
    for (NSTabViewItem *item in [(NSTabView *)view tabViewItems])
      if (item.view.superview == nil)
        MBRepairSegmentImages(item.view);
}

/* Typing undo for every editable text cell -- fields and table columns,
   on every tab page.  The field editor takes the setting from the cell it
   edits; Cocoa's text cells default to on, GNUstep's to off (and a xib
   does not say), so Ctrl+Z while typing did nothing there. */
static void MBEnableTypingUndoIn(NSView *view)
{
  if ([view isKindOfClass:[NSTextField class]]) {
    [[(NSTextField *)view cell] setAllowsUndo:YES];
    return;
  }
  if ([view isKindOfClass:[NSTableView class]]) {
    for (NSTableColumn *column in [(NSTableView *)view tableColumns])
      if ([column.dataCell isKindOfClass:[NSTextFieldCell class]])
        [(NSCell *)column.dataCell setAllowsUndo:YES];
  }
  for (NSView *subview in view.subviews)
    MBEnableTypingUndoIn(subview);
  if ([view isKindOfClass:[NSTabView class]])
    for (NSTabViewItem *item in [(NSTabView *)view tabViewItems])
      if (item.view.superview == nil)
        MBEnableTypingUndoIn(item.view);
}

/* The first split view among a view's immediate subviews. */
static NSSplitView *MBFirstSplitViewIn(NSView *view)
{
  for (NSView *subview in view.subviews)
    if ([subview isKindOfClass:[NSSplitView class]]) return (NSSplitView *)subview;
  return nil;
}

/* The narrowest the window may get: both side panes at their minimum
   plus a usable center. */
static const CGFloat MBSidePaneMinimum = 160.0;
static const CGFloat MBCenterPaneMinimum = 320.0;
static const CGFloat MBInspectorMinimum = 260.0;

@implementation MBWindowController {
  MBInspectKind _kind;
  BOOL _updating;

  /* The window's three split views: the outer one (main area | inspector),
     the main area's (editor over the button bar), and the editor's
     (source list | center pane).  -splitView:shouldAdjustSizeOfSubview:
     holds the three side panes at their size. */
  NSSplitView *_outerSplit, *_barSplit, *_sourceSplit;

  MBTypingUndoManager *_typingUndoManager;   /* for the field editor (see Undo) */
  NSDictionary *_replaySelection;      /* selection across an undo or redo */

  MBSourceItem *_entitiesGroup, *_fetchesGroup, *_configurationsGroup;
  NSArray *_entityItems, *_fetchItems, *_configurationItems;

  NSArray *_attributeNames;
  NSArray *_relationshipNames;
  NSArray *_userInfoKeys;
  NSArray *_memberEntityNames;   /* all entities, for the membership checklist */
  NSMutableArray *_constraintRows; /* mirror of the entity's uniquenessConstraints */

}

- (MBDocument *)modelDocument
{
  return (MBDocument *)self.document;
}

- (NSManagedObjectModel *)model
{
  return self.modelDocument.model;
}

#pragma mark - Nib assembly

- (void)windowDidLoad
{
  [super windowDidLoad];

  MBRepairSegmentImages(self.window.contentView);
  MBEnableTypingUndoIn(self.window.contentView);
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(fieldDidEndEditing:)
                 name:NSControlTextDidEndEditingNotification object:nil];
  /* The window asks its delegate for an undo manager (see Undo). */
  if (!self.window.delegate) self.window.delegate = (id<NSWindowDelegate>)self;

  /* Resizing: only the innermost split had a delegate in the xib. */
  _outerSplit = MBFirstSplitViewIn(self.window.contentView);
  _barSplit = MBFirstSplitViewIn(_outerSplit.subviews.firstObject);
  _sourceSplit = MBFirstSplitViewIn(_barSplit.subviews.firstObject);
  for (NSSplitView *split in @[ _outerSplit ?: (id)[NSNull null],
                                _barSplit ?: (id)[NSNull null],
                                _sourceSplit ?: (id)[NSNull null] ])
    if ([split isKindOfClass:[NSSplitView class]]) split.delegate = self;
  self.window.minSize = NSMakeSize(MBSidePaneMinimum + MBCenterPaneMinimum +
                                       MBInspectorMinimum + 2.0,
                                   480.0);

  /* The section names and stacking indexes are IB runtime attributes
     on the JUInspectorViews.  GNUstep's GSXib5 does not (yet) apply
     runtime attributes to nested subviews, so backfill them when they
     did not arrive; on macOS these are no-ops. */
  if (!self.attributesInspector.name.length)
    self.attributesInspector.name = @"Attribute Inspector";
  if (!self.relationshipsInspector.name.length)
    self.relationshipsInspector.name = @"Relationships Inspector";
  if (!self.fetchRequestInspector.name.length)
    self.fetchRequestInspector.name = @"FetchRequest";
  if (!self.entitiesInspector.name.length)
    self.entitiesInspector.name = @"Entities";
  if (self.relationshipsInspector.index == self.attributesInspector.index) {
    self.relationshipsInspector.index = 1;
    [self.entityInspectorContainer arrangeViews];
  }

  /* --- Inspector chrome: DMTabBar over the inspector tab view. --- */
  /* Xcode's own icons on macOS; elsewhere drawn letter badges, as the
     XForms and RDL designers' bars have.  (GNUstep ships images under
     some of these names -- NSAdvanced is a gear -- so it is the platform,
     not the lookup, that decides.) */
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

  /* The number page's bounds may be negative (numeric attributes);
     set in code because GNUstep's xib loader does not apply IB
     runtime attributes to nested subviews.  Every other stepper
     field (counts, lengths, limits) keeps the clamp at zero. */
  self.numberDefaultField.allowsNegative = YES;
  self.numberMinField.allowsNegative = YES;
  self.numberMaxField.allowsNegative = YES;

  /* Right-click menu on the source list, so a first fetch request or
     configuration can be added even when the "+" segment's context is
     the entity group. */
  NSMenu *addMenu = [[NSMenu alloc] initWithTitle:@"Add"];
  struct { NSString *title; SEL action; } addItems[] = {
    { @"Add Entity", @selector(addEntity:) },
    { @"Add Fetch Request", @selector(addFetchRequest:) },
    { @"Add Configuration", @selector(addConfiguration:) },
  };
  for (unsigned i = 0; i < sizeof(addItems) / sizeof(addItems[0]); i++) {
    NSMenuItem *item = [addMenu addItemWithTitle:addItems[i].title
                                          action:addItems[i].action
                                   keyEquivalent:@""];
    item.target = self;
  }
  [addMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *subclassItem =
      [addMenu addItemWithTitle:@"Create NSManagedObject Subclass…"
                         action:@selector(createManagedObjectSubclass:)
                  keyEquivalent:@""];
  subclassItem.target = self;
  self.sourceList.menu = addMenu;

  /* Default to the textual predicate editor off-Apple: GNUstep's
     NSPredicateEditor is a stub.  Its action is wired here rather than
     in the xib for the same reason: GNUstep's NSRuleEditor is backed by
     a plain NSCell, whose -setTarget: raises, and a raise while the xib
     loader establishes connections abandons the load before any object
     is sent -awakeFromNib. */
#if defined(__APPLE__)
  self.fetchPredicateEditor.target = self;
  self.fetchPredicateEditor.action = @selector(inspectorChanged:);
#else
  [self.predicateTabView selectTabViewItemAtIndex:MBPredicatePageSource];
  [self.predicateSourceSegmentedControl setSelectedSegment:MBPredicatePageSource];
#endif

  [self populateFromDocument];
}

#pragma mark - Window lifecycle

- (void)setDocument:(NSDocument *)document
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  NSUndoManager *previous = [self.document undoManager];
  if (previous) {
    [center removeObserver:self name:NSUndoManagerWillUndoChangeNotification object:previous];
    [center removeObserver:self name:NSUndoManagerWillRedoChangeNotification object:previous];
    [center removeObserver:self name:NSUndoManagerDidUndoChangeNotification object:previous];
    [center removeObserver:self name:NSUndoManagerDidRedoChangeNotification object:previous];
  }
  [super setDocument:document];
  if (!document) return;
  NSUndoManager *undo = [document undoManager];
  [center addObserver:self selector:@selector(undoManagerWillReplay:)
                 name:NSUndoManagerWillUndoChangeNotification object:undo];
  [center addObserver:self selector:@selector(undoManagerWillReplay:)
                 name:NSUndoManagerWillRedoChangeNotification object:undo];
  [center addObserver:self selector:@selector(undoManagerDidReplay:)
                 name:NSUndoManagerDidUndoChangeNotification object:undo];
  [center addObserver:self selector:@selector(undoManagerDidReplay:)
                 name:NSUndoManagerDidRedoChangeNotification object:undo];
  if ([self isWindowLoaded])
    [self populateFromDocument];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Undo

/* Typing in a field has its own undo manager, never the document's: the
   field editor registers typing without opening a group of its own, which
   the document's (grouping explicitly) refuses -- and the refusal takes
   the keystroke with it.  A committed field arrives as one edit. */
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
  NSUndoManager *document = [(NSDocument *)self.document undoManager];
  NSResponder *responder = window.firstResponder;
  if ([responder isKindOfClass:[NSText class]] && [(NSText *)responder isFieldEditor]) {
    if (!_typingUndoManager) _typingUndoManager = [[MBTypingUndoManager alloc] init];
    _typingUndoManager.fallback = document;
    return _typingUndoManager;
  }
  return document;
}

/* Typing undo lasts until the field's edit is committed, as on Cocoa:
   after Return (or leaving the field) Ctrl+Z is the document's again,
   though the field editor keeps the focus on GNUstep -- its typing would
   otherwise undo text the model no longer agrees with. */
- (void)fieldDidEndEditing:(NSNotification *)notification
{
  if ([notification.object window] != self.window) return;
  [_typingUndoManager removeAllActions];
}

/* An undo or redo changes the model under the window: note what is
   selected -- as objects, which outlive a rename -- and put the selection
   back once it has run. */
- (void)undoManagerWillReplay:(NSNotification *)notification
{
  (void)notification;
  MBSourceItem *source = [self selectedSourceItem];
  NSMutableDictionary *selection = [NSMutableDictionary dictionary];
  selection[@"kind"] = @(source ? source.kind : MBSourceEntity);
  if (source.name) selection[@"name"] = source.name;
  if (source.implicitDefault) selection[@"default"] = @YES;
  id entity = [self selectedEntity], attribute = [self selectedAttribute],
     relationship = [self selectedRelationship];
  if (entity) selection[@"entity"] = entity;
  if (attribute) selection[@"attribute"] = attribute;
  if (relationship) selection[@"relationship"] = relationship;
  NSFetchRequest *fetch = [self selectedTemplate];
  if (fetch) selection[@"fetch"] = fetch;
  _replaySelection = selection;
}

- (void)undoManagerDidReplay:(NSNotification *)notification
{
  (void)notification;
  NSDictionary *selection = _replaySelection;
  _replaySelection = nil;
  MBSourceKind kind = (MBSourceKind)[selection[@"kind"] integerValue];
  NSEntityDescription *entity = selection[@"entity"];
  NSPropertyDescription *attribute = selection[@"attribute"];
  NSPropertyDescription *relationship = selection[@"relationship"];

  [self reloadEverything];

  /* The source item: by the selected object's current name where it
     still belongs to the model, else by the name it had. */
  NSString *name = selection[@"name"];
  if (kind == MBSourceEntity && entity && self.model.entitiesByName[entity.name] == entity)
    name = entity.name;
  if (kind == MBSourceFetch && selection[@"fetch"]) {
    NSDictionary *templates = [self.model fetchRequestTemplatesByName];
    for (NSString *key in templates)
      if (templates[key] == selection[@"fetch"]) name = key;
  }
  if (name) [self selectSourceKind:kind name:name];
  if (![self selectedSourceItem] && _entityItems.count)
    [self selectSourceItem:_entityItems.firstObject];

  if (kind == MBSourceConfiguration && entity) {
    NSUInteger row = [_memberEntityNames indexOfObject:entity.name];
    if (row != NSNotFound)
      [self.memberTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                    byExtendingSelection:NO];
  } else if (attribute && attribute.entity == [self selectedEntity]) {
    [self reloadPropertyTable:self.attributeTable selecting:attribute.name];
  } else if (relationship && relationship.entity == [self selectedEntity]) {
    [self reloadPropertyTable:self.relationshipTable selecting:relationship.name];
  }
  [self refreshSelectionUI];
}

- (void)populateFromDocument
{
  if (!self.document) return;
  [self synchronizeWindowTitleWithDocumentName];
  [self reloadEverything];
  if (_entityItems.count)
    [self selectSourceItem:_entityItems.firstObject];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
  MBDocument *doc = self.modelDocument;
  NSString *version = [doc.editedVersionName stringByDeletingPathExtension];
  if (!version.length) return displayName;
  BOOL current = [doc.editedVersionName isEqualToString:doc.currentVersionName];
  return [NSString stringWithFormat:@"%@ — %@%@", displayName, version,
          current ? @" (current)" : @""];
}

#pragma mark - Source list model

- (void)rebuildSourceItems
{
  if (!_entitiesGroup) {
    _entitiesGroup = [MBSourceItem itemWithKind:MBSourceGroupEntities name:@"ENTITIES"];
    _fetchesGroup = [MBSourceItem itemWithKind:MBSourceGroupFetches name:@"FETCH REQUESTS"];
    _configurationsGroup = [MBSourceItem itemWithKind:MBSourceGroupConfigurations name:@"CONFIGURATIONS"];
  }
  NSMutableArray *entities = [NSMutableArray array];
  for (NSEntityDescription *entity in [self.modelDocument sortedEntities])
    [entities addObject:[MBSourceItem itemWithKind:MBSourceEntity name:entity.name]];
  _entityItems = entities;

  NSMutableArray *fetches = [NSMutableArray array];
  for (NSString *name in [[[self.model fetchRequestTemplatesByName] allKeys]
           sortedArrayUsingSelector:@selector(compare:)])
    [fetches addObject:[MBSourceItem itemWithKind:MBSourceFetch name:name]];
  _fetchItems = fetches;

  NSMutableArray *configurations = [NSMutableArray array];
  NSArray *declared = [self.modelDocument configurationNames];
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

- (MBSourceItem *)selectedSourceItem
{
  NSInteger row = self.sourceList.selectedRow;
  if (row < 0) return nil;
  id item = [self.sourceList itemAtRow:row];
  return ([item isKindOfClass:[MBSourceItem class]] && ![item isGroup]) ? item : nil;
}

- (void)selectSourceItem:(MBSourceItem *)item
{
  NSInteger row = [self.sourceList rowForItem:item];
  if (row >= 0)
    [self.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                 byExtendingSelection:NO];
}

- (void)selectSourceKind:(MBSourceKind)kind name:(NSString *)name
{
  NSArray *pool = kind == MBSourceEntity ? _entityItems
                : kind == MBSourceFetch ? _fetchItems : _configurationItems;
  for (MBSourceItem *item in pool) {
    if ([item.name isEqualToString:name]) {
      [self selectSourceItem:item];
      return;
    }
  }
}

#pragma mark - Selection resolution

- (NSEntityDescription *)selectedEntity
{
  MBSourceItem *item = [self selectedSourceItem];
  if (item.kind == MBSourceConfiguration) {
    /* A configuration's page lists entities; the one selected there is
       the entity the inspector shows and edits. */
    NSInteger row = self.memberTable.selectedRow;
    if (row < 0 || (NSUInteger)row >= _memberEntityNames.count) return nil;
    return self.model.entitiesByName[_memberEntityNames[(NSUInteger)row]];
  }
  if (item.kind != MBSourceEntity) return nil;
  return self.model.entitiesByName[item.name];
}

- (NSString *)selectedTemplateName
{
  MBSourceItem *item = [self selectedSourceItem];
  return item.kind == MBSourceFetch ? item.name : nil;
}

- (NSFetchRequest *)selectedTemplate
{
  NSString *name = [self selectedTemplateName];
  return name ? [self.model fetchRequestTemplateForName:name] : nil;
}

/* A declared configuration's name; nil for the implicit Default, which
   the file does not have. */
- (NSString *)selectedConfigurationName
{
  MBSourceItem *item = [self selectedSourceItem];
  return (item.kind == MBSourceConfiguration && !item.implicitDefault) ? item.name : nil;
}

- (BOOL)selectedConfigurationIsImplicitDefault
{
  MBSourceItem *item = [self selectedSourceItem];
  return item.kind == MBSourceConfiguration && item.implicitDefault;
}

- (NSAttributeDescription *)selectedAttribute
{
  NSEntityDescription *entity = [self selectedEntity];
  NSInteger row = self.attributeTable.selectedRow;
  if (!entity || row < 0 || (NSUInteger)row >= _attributeNames.count) return nil;
  return entity.attributesByName[_attributeNames[(NSUInteger)row]];
}

- (NSRelationshipDescription *)selectedRelationship
{
  NSEntityDescription *entity = [self selectedEntity];
  NSInteger row = self.relationshipTable.selectedRow;
  if (!entity || row < 0 || (NSUInteger)row >= _relationshipNames.count) return nil;
  return entity.relationshipsByName[_relationshipNames[(NSUInteger)row]];
}

#pragma mark - Editors for the current selection

- (MBEntityEditor *)entityEditor
{
  NSString *name = [self selectedEntity].name;
  return name ? [MBEntityEditor editorForEntityNamed:name document:self.modelDocument] : nil;
}

- (MBAttributeEditor *)attributeEditor
{
  NSEntityDescription *entity = [self selectedEntity];
  NSString *name = [self selectedAttribute].name;
  return (entity && name)
      ? [MBAttributeEditor editorForAttributeNamed:name entity:entity document:self.modelDocument]
      : nil;
}

- (MBRelationshipEditor *)relationshipEditor
{
  NSEntityDescription *entity = [self selectedEntity];
  NSString *name = [self selectedRelationship].name;
  return (entity && name)
      ? [MBRelationshipEditor editorForRelationshipNamed:name entity:entity document:self.modelDocument]
      : nil;
}

- (MBFetchEditor *)fetchRequestEditor
{
  NSString *name = [self selectedTemplateName];
  return name ? [MBFetchEditor editorForFetchRequestNamed:name document:self.modelDocument] : nil;
}

#pragma mark - Row caches / reload

- (void)rebuildPropertyRows
{
  NSEntityDescription *entity = [self selectedEntity];
  NSMutableArray *attributes = [NSMutableArray array];
  NSMutableArray *relationships = [NSMutableArray array];
  // The entity's own, as Xcode lists them; -properties includes inherited ones.
  for (NSPropertyDescription *property in [CDModelCompiler declaredPropertiesOfEntity:entity]) {
    if ([property isKindOfClass:[NSAttributeDescription class]])
      [attributes addObject:property.name];
    else if ([property isKindOfClass:[NSRelationshipDescription class]])
      [relationships addObject:property.name];
  }
  _attributeNames = [attributes sortedArrayUsingSelector:@selector(compare:)];
  _relationshipNames = [relationships sortedArrayUsingSelector:@selector(compare:)];
}

- (NSDictionary *)currentUserInfo
{
  if (_kind == MBInspectEntity) return [[self selectedEntity] userInfo];
  if (_kind == MBInspectAttribute) return [[self selectedAttribute] userInfo];
  if (_kind == MBInspectRelationship) return [[self selectedRelationship] userInfo];
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

- (void)reloadEverything
{
  [self rebuildSourceItems];
  [self.sourceList reloadData];
  [self.sourceList expandItem:_entitiesGroup];
  [self.sourceList expandItem:_fetchesGroup];
  [self.sourceList expandItem:_configurationsGroup];
  [self rebuildPropertyRows];
  _memberEntityNames = [[self.model.entitiesByName allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
  [self.attributeTable reloadData];
  [self.relationshipTable reloadData];
  [self.memberTable reloadData];
  [self refreshSelectionUI];
  [self synchronizeWindowTitleWithDocumentName];
}

/* Recomputes the center pane and inspector for the current selection. */
- (void)refreshSelectionUI
{
  MBSourceItem *item = [self selectedSourceItem];

  if (item.kind == MBSourceEntity) {
    [self.centerTabView selectTabViewItemAtIndex:MBCenterPageEntity];
    if (self.attributeTable.selectedRow >= 0) _kind = MBInspectAttribute;
    else if (self.relationshipTable.selectedRow >= 0) _kind = MBInspectRelationship;
    else _kind = MBInspectEntity;
  } else if (item.kind == MBSourceFetch) {
    [self.centerTabView selectTabViewItemAtIndex:MBCenterPageFetch];
    _kind = MBInspectFetch;
  } else if (item.kind == MBSourceConfiguration) {
    [self.centerTabView selectTabViewItemAtIndex:MBCenterPageConfiguration];
    _kind = self.memberTable.selectedRow >= 0 ? MBInspectEntity : MBInspectConfiguration;
  } else {
    [self.centerTabView selectTabViewItemAtIndex:MBCenterPageEntity];
    _kind = MBInspectNone;
  }

  [self rebuildUserInfoRows];
  [self rebuildConstraintRows];
  [self.constraintsTable reloadData];
  [self reloadUserInfoTables];
  [self fillInspector];
}

#pragma mark - Inspector fill

- (void)rebuildParentPopup
{
  [self.parentPopup removeAllItems];
  [self.parentPopup addItemWithTitle:@"(none)"];
  NSEntityDescription *current = [self selectedEntity];
  for (NSEntityDescription *entity in [self.modelDocument sortedEntities]) {
    if (entity == current) continue;
    [self.parentPopup addItemWithTitle:entity.name ?: @""];
  }
}

- (void)rebuildEntityListInto:(NSPopUpButton *)popup includeNone:(BOOL)includeNone
{
  [popup removeAllItems];
  if (includeNone)
    [popup addItemWithTitle:@"(none)"];
  for (NSEntityDescription *entity in [self.modelDocument sortedEntities])
    [popup addItemWithTitle:entity.name ?: @""];
}

- (void)rebuildInversePopup
{
  [self.inversePopup removeAllItems];
  [self.inversePopup addItemWithTitle:@"(none)"];
  NSRelationshipDescription *rel = [self selectedRelationship];
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

  MBAttributeEditor *editor = [MBAttributeEditor
      editorForAttributeNamed:attr.name
                       entity:[self selectedEntity]
                     document:self.modelDocument];
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
  self.fetchNameField.stringValue = [self selectedTemplateName] ?: @"";
  [self rebuildEntityListInto:self.fetchInspectorEntityPopup includeNone:NO];
  [self rebuildEntityListInto:self.fetchEntityPopup includeNone:NO];
  NSString *entityName = fetch.entity.name;
  if (entityName.length) {
    if ([self.fetchInspectorEntityPopup itemWithTitle:entityName])
      [self.fetchInspectorEntityPopup selectItemWithTitle:entityName];
    if ([self.fetchEntityPopup itemWithTitle:entityName])
      [self.fetchEntityPopup selectItemWithTitle:entityName];
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

  NSString *format = fetch.predicate ? [fetch.predicate predicateFormat] : @"";
  self.predicateSourceView.stringValue = format;
#if defined(__APPLE__)
  @try {
    NSMutableArray *templates = [NSMutableArray array];
    [templates addObject:[[NSPredicateEditorRowTemplate alloc]
        initWithCompoundTypes:@[ @(NSAndPredicateType), @(NSOrPredicateType),
                                 @(NSNotPredicateType) ]]];
    if (fetch.entity) {
      NSMutableArray *keyPaths = [NSMutableArray array];
      for (NSString *name in [[fetch.entity.attributesByName allKeys]
               sortedArrayUsingSelector:@selector(compare:)])
        [keyPaths addObject:name];
      if (keyPaths.count)
        [templates addObjectsFromArray:[NSPredicateEditorRowTemplate
            templatesWithAttributeKeyPaths:keyPaths
                       inEntityDescription:fetch.entity]];
    }
    if (templates.count > 1)
      self.fetchPredicateEditor.rowTemplates = templates;
    self.fetchPredicateEditor.objectValue = fetch.predicate;
  } @catch (NSException *exception) {
    /* a predicate the templates cannot represent: fall back to source */
    [self.predicateTabView selectTabViewItemAtIndex:MBPredicatePageSource];
    [self.predicateSourceSegmentedControl setSelectedSegment:MBPredicatePageSource];
  }
#endif
}

- (void)fillInspector
{
  _updating = YES;
  /* The Identity page describes the model version, whatever is selected:
     the tab bar can show it at any time. */
  self.modelIdentifierField.stringValue = [MBModelEditor editorForDocument:self.modelDocument].versionIdentifier ?: @"";
  switch (_kind) {
    case MBInspectEntity:
      [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageEntity];
      [self fillEntityInspector:[self selectedEntity]];
      break;
    case MBInspectAttribute:
      [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageAttribute];
      [self fillAttributeInspector:[self selectedAttribute]];
      break;
    case MBInspectRelationship:
      [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageRelationship];
      [self fillRelationshipInspector:[self selectedRelationship]];
      break;
    case MBInspectFetch:
      [self selectInspectorPage:MBInspectorPageDataModel kindPage:MBKindPageFetch];
      [self fillFetchInspector:[self selectedTemplate]];
      break;
    default:
      /* configurations and empty selections have no data-model page */
      [self selectInspectorPage:MBInspectorPageIdentity kindPage:-1];
      break;
  }
  [self reloadUserInfoTables];
  _updating = NO;
}

#pragma mark - Errors

- (void)presentModelError:(NSError *)error title:(NSString *)title
{
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = title;
  alert.informativeText = error.localizedDescription ?: @"Unknown error.";
  [alert runModal];
}

#pragma mark - Source actions

- (NSString *)uniqueName:(NSString *)base among:(NSArray *)names
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

- (IBAction)sourceSegmentClicked:(id)sender
{
  if ([sender selectedSegment] == 0) [self addSourceItem:sender];
  else [self removeSourceItem:sender];
}

- (IBAction)propertySegmentClicked:(id)sender
{
  BOOL relationships = self.relationshipTable.selectedRow >= 0;
  if ([sender selectedSegment] == 0) {
    if (relationships) [self addRelationship:sender];
    else [self addAttribute:sender];
  } else {
    if (relationships) [self removeRelationship:sender];
    else [self removeAttribute:sender];
  }
}

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
  switch (selected.kind) {
    case MBSourceEntity: {
      NSError *error = nil;
      if (![self.modelDocument removeEntityNamed:selected.name error:&error])
        [self presentModelError:error title:@"Cannot delete entity"];
      [self reloadEverything];
      break;
    }
    case MBSourceFetch:
      [self.modelDocument removeFetchRequestNamed:selected.name];
      [self reloadEverything];
      break;
    case MBSourceConfiguration: {
      if (selected.implicitDefault) break;   /* not in the file to remove */
      NSError *error = nil;
      if (![self.modelDocument removeConfigurationNamed:selected.name error:&error])
        [self presentModelError:error title:@"Cannot remove configuration"];
      [self reloadEverything];
      break;
    }
    default: break;
  }
}

- (IBAction)addEntity:(id)sender
{
  (void)sender;
  NSString *name = [self.modelDocument addEntity];
  [self reloadEverything];
  [self selectSourceKind:MBSourceEntity name:name];
}

- (IBAction)addFetchRequest:(id)sender
{
  (void)sender;
  NSString *name = [self.modelDocument
      addFetchRequestForEntityNamed:[self selectedEntity].name];
  if (!name) return;
  [self reloadEverything];
  [self selectSourceKind:MBSourceFetch name:name];
}

- (IBAction)addConfiguration:(id)sender
{
  (void)sender;
  NSString *name = [self.modelDocument addConfiguration];
  if (!name) return;
  [self reloadEverything];
  [self selectSourceKind:MBSourceConfiguration name:name];
}

/* MainMenu.xib's Model > Remove Entity. */
- (IBAction)removeEntity:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  if (!entity.name.length) return;
  NSError *error = nil;
  if (![self.modelDocument removeEntityNamed:entity.name error:&error])
    [self presentModelError:error title:@"Cannot delete entity"];
  [self reloadEverything];
}

#pragma mark - Property actions

- (void)selectPropertyRow:(NSString *)name inTable:(NSTableView *)table names:(NSArray *)names
{
  NSUInteger idx = [names indexOfObject:name];
  if (idx != NSNotFound)
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
}

/* Rebuild a property table after an edit and keep the edited property
   selected by NAME.  The rows are sorted by name, so a rename moves the
   row; leaving the selection at its old index selected a different
   property, and the next inspector edit went to that one. */
- (void)reloadPropertyTable:(NSTableView *)table selecting:(NSString *)name
{
  [self rebuildPropertyRows];
  [table reloadData];
  NSArray *names = table == self.attributeTable ? _attributeNames : _relationshipNames;
  NSUInteger row = name ? [names indexOfObject:name] : NSNotFound;
  if (row != NSNotFound && (NSInteger)row != table.selectedRow)
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

- (IBAction)addAttribute:(id)sender
{
  (void)sender;
  NSString *name = [[self entityEditor] addAttribute];
  if (!name) return;
  [self rebuildPropertyRows];
  [self.attributeTable reloadData];
  [self.relationshipTable deselectAll:nil];
  [self selectPropertyRow:name inTable:self.attributeTable names:_attributeNames];
  [self refreshSelectionUI];
}

- (IBAction)removeAttribute:(id)sender
{
  (void)sender;
  NSString *name = [self selectedAttribute].name;
  if (!name) return;
  [[self entityEditor] removeAttributeNamed:name];
  [self rebuildPropertyRows];
  [self.attributeTable reloadData];
  [self refreshSelectionUI];
}

- (IBAction)addRelationship:(id)sender
{
  (void)sender;
  NSString *name = [[self entityEditor] addRelationship];
  if (!name) return;
  [self rebuildPropertyRows];
  [self.relationshipTable reloadData];
  [self.attributeTable deselectAll:nil];
  [self selectPropertyRow:name inTable:self.relationshipTable names:_relationshipNames];
  [self refreshSelectionUI];
}

- (IBAction)removeRelationship:(id)sender
{
  (void)sender;
  NSString *name = [self selectedRelationship].name;
  if (!name) return;
  [[self entityEditor] removeRelationshipNamed:name];
  [self rebuildPropertyRows];
  [self.relationshipTable reloadData];
  [self refreshSelectionUI];
}

#pragma mark - userInfo / constraints segments

- (IBAction)userInfoSegmentClicked:(id)sender
{
  if (_kind != MBInspectEntity && _kind != MBInspectAttribute && _kind != MBInspectRelationship)
    return;
  NSTableView *table = [self activeUserInfoTable];
  if ([sender selectedSegment] == 0) {
    NSMutableDictionary *info = [([self currentUserInfo] ?: @{}) mutableCopy];
    NSString *key = [self uniqueName:@"key" among:info.allKeys];
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
  [self.modelDocument noteModelChanged];
}

- (IBAction)constraintsSegmentClicked:(id)sender
{
  NSEntityDescription *entity = [self selectedEntity];
  if (!entity) return;
  if ([sender selectedSegment] == 0) {
    NSString *seed = _attributeNames.firstObject ?: @"attribute";
    [_constraintRows addObject:seed];
  } else {
    NSInteger row = self.constraintsTable.selectedRow;
    if (row < 0 || (NSUInteger)row >= _constraintRows.count) return;
    [_constraintRows removeObjectAtIndex:(NSUInteger)row];
  }
  [self applyConstraintRows];
  [self.constraintsTable reloadData];
}

#pragma mark - Inspector writes

- (IBAction)inspectorTabSelected:(id)sender
{
  (void)sender;
  NSUInteger index = self.inspectorTabBar.selectedIndex;
  if (index < (NSUInteger)[self.inspectorTabView numberOfTabViewItems])
    [self.inspectorTabView selectTabViewItemAtIndex:(NSInteger)index];
}

- (IBAction)predicateSourceToggled:(id)sender
{
  NSInteger segment = [sender selectedSegment];
  [self.predicateTabView selectTabViewItemAtIndex:
      segment == 0 ? MBPredicatePageEditor : MBPredicatePageSource];
}

/* A small modal text prompt, built by hand because GNUstep's NSAlert
   has no accessory-view support.  Returns nil on Cancel. */
- (void)textPromptOK:(id)sender
{
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)textPromptCancel:(id)sender
{
  (void)sender;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

- (NSString *)runTextPromptWithTitle:(NSString *)title
                             message:(NSString *)message
                        initialValue:(NSString *)initialValue
{
  NSWindow *panel = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 380, 118)
                styleMask:NSTitledWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  panel.title = title;
  NSView *content = panel.contentView;

  NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 84, 348, 18)];
  label.stringValue = message ?: @"";
  label.bezeled = NO;
  label.bordered = NO;
  label.editable = NO;
  label.selectable = NO;
  label.drawsBackground = NO;
  label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  [content addSubview:label];

  NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 52, 348, 24)];
  field.stringValue = initialValue ?: @"";
  [content addSubview:field];

  NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(284, 12, 80, 28)];
  ok.title = @"OK";
  ok.bezelStyle = NSRoundedBezelStyle;
  ok.keyEquivalent = @"\r";
  ok.target = self;
  ok.action = @selector(textPromptOK:);
  [content addSubview:ok];

  NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(198, 12, 80, 28)];
  cancel.title = @"Cancel";
  cancel.bezelStyle = NSRoundedBezelStyle;
  cancel.keyEquivalent = @"\033";
  cancel.target = self;
  cancel.action = @selector(textPromptCancel:);
  [content addSubview:cancel];

  [panel center];
  [panel makeFirstResponder:field];
  NSInteger response = [NSApp runModalForWindow:panel];
  [panel orderOut:nil];
  return response == NSModalResponseOK ? field.stringValue : nil;
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
    [self presentModelError:editor.lastError title:@"Invalid derivation expression"];
    [sender setState:NSOffState];
    return;
  }
  [self rebuildPropertyRows];
  [self fillInspector];
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

/* After an entity edit, select it again where it was being edited: in the
   source list, or -- when it was picked on a configuration's page -- as
   that configuration's row, found by its (perhaps new) name. */
- (void)reselectEntityNamed:(NSString *)name inConfiguration:(MBSourceItem *)configuration
{
  if (!configuration) {
    [self selectSourceKind:MBSourceEntity name:name];
    return;
  }
  [self selectSourceKind:MBSourceConfiguration name:configuration.name];
  _memberEntityNames = [[self.model.entitiesByName allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
  [self.memberTable reloadData];
  NSUInteger row = [_memberEntityNames indexOfObject:name];
  if (row != NSNotFound)
    [self.memberTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                  byExtendingSelection:NO];
}

- (void)applyEntityInspector
{
  MBEntityEditor *editor = [self entityEditor];
  if (!editor) return;
  MBSourceItem *source = [self selectedSourceItem];
  MBSourceItem *configuration = source.kind == MBSourceConfiguration ? source : nil;
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
  BOOL reparent = ![wanted isEqualToString:editor.parentName];
  editor.parentName = wanted;   /* graph surgery: recompiles the model */
  if (editor.lastError)
    [self presentModelError:editor.lastError title:@"Cannot change parent entity"];
  if (reparent) {
    [self reloadEverything];
    [self reselectEntityNamed:editor.name inConfiguration:configuration];
    return;
  }
  [self rebuildSourceItems];
  [self.sourceList reloadData];
  [self reselectEntityNamed:editor.name inConfiguration:configuration];
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
  if (typeChanged) {
    /* the default-value UI belongs to the old type: switch the detail
       page and refill instead of applying stale controls */
    [self reloadPropertyTable:self.attributeTable selecting:editor.name];
    _updating = YES;
    [self fillAttributeInspector:editor.attribute];
    _updating = NO;
    return;
  }
  [self applyDefaultFromUIToEditor:editor];
  [self reloadPropertyTable:self.attributeTable selecting:editor.name];
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

  [self reloadPropertyTable:self.relationshipTable selecting:editor.name];
  _updating = YES;
  [self fillRelationshipInspector:editor.relationship];
  _updating = NO;
}

- (void)applyFetchInspector:(id)sender
{
  MBFetchEditor *editor = [self fetchRequestEditor];
  if (!editor) return;

  NSString *newName = self.fetchNameField.stringValue;
  if (![newName isEqualToString:editor.name]) {
    editor.name = newName;   /* re-keys the template map; refuses clashes */
    [self rebuildSourceItems];
    [self.sourceList reloadData];
    [self selectSourceKind:MBSourceFetch name:editor.name];
  }

  NSPopUpButton *entitySender =
      (sender == self.fetchEntityPopup) ? self.fetchEntityPopup : self.fetchInspectorEntityPopup;
  editor.entityName = entitySender.titleOfSelectedItem;
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

  /* The predicate comes from whichever editor the user is on. */
  BOOL fromEditor = NO;
#if defined(__APPLE__)
  fromEditor = (sender == self.fetchPredicateEditor);
#endif
  if (fromEditor) {
#if defined(__APPLE__)
    @try {
      editor.predicate = [self.fetchPredicateEditor objectValue];
      self.predicateSourceView.stringValue = editor.predicateFormat;
    } @catch (NSException *exception) { /* leave the old predicate */ }
#endif
  } else if (sender == self.predicateSourceView) {
    /* an unparseable string keeps the old predicate; the text stays
       visible for fixing */
    editor.predicateFormat = self.predicateSourceView.stringValue;
  }
}

- (IBAction)inspectorChanged:(id)sender
{
  if (_updating) return;
  /* An apply sets every field of the page; the ones that changed are one
     undo step. */
  MBDocument *document = self.modelDocument;
  if (sender == self.modelIdentifierField) {
    [document beginEdit:@"Edit Model Identifier"];
    [MBModelEditor editorForDocument:document].versionIdentifier = self.modelIdentifierField.stringValue;
    [document endEdit];
    return;
  }
  switch (_kind) {
    case MBInspectEntity:
      [document beginEdit:@"Edit Entity"]; [self applyEntityInspector]; break;
    case MBInspectAttribute:
      [document beginEdit:@"Edit Attribute"]; [self applyAttributeInspector]; break;
    case MBInspectRelationship:
      [document beginEdit:@"Edit Relationship"]; [self applyRelationshipInspector]; break;
    case MBInspectFetch:
      [document beginEdit:@"Edit Fetch Request"]; [self applyFetchInspector:sender]; break;
    default: return;
  }
  [document endEdit];
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

#pragma mark - Version / Editor menu actions

- (IBAction)selectVersionMenuItem:(id)sender
{
  NSString *name = [sender representedObject];
  if (!name.length) return;
  NSError *error = nil;
  if (![self.modelDocument switchToVersion:name error:&error]) {
    [self presentModelError:error title:@"Cannot switch versions"];
    return;
  }
  [self reloadEverything];
}

- (IBAction)addModelVersion:(id)sender
{
  (void)sender;
  if (![self.modelDocument addModelVersion]) return;
  [self reloadEverything];
}

- (IBAction)makeCurrentVersion:(id)sender
{
  (void)sender;
  [self.modelDocument makeEditedVersionCurrent];
  [self reloadEverything];
}

- (IBAction)validateModel:(id)sender
{
  (void)sender;
  NSError *error = nil;
  NSArray *warnings = nil;
  BOOL ok = [self.modelDocument validateModel:&error warnings:&warnings];

  NSAlert *alert = [[NSAlert alloc] init];
  if (!ok) {
    alert.messageText = @"Model does not compile";
    alert.informativeText = error.localizedDescription ?: @"Unknown error.";
  } else if (warnings.count) {
    alert.messageText = [NSString stringWithFormat:@"Model compiles with %lu warning%@",
                         (unsigned long)warnings.count, warnings.count == 1 ? @"" : @"s"];
    alert.informativeText = [warnings componentsJoinedByString:@"\n"];
  } else {
    alert.messageText = @"Model compiles cleanly";
    alert.informativeText = @"momc found no problems.";
  }
  [alert runModal];
}

- (IBAction)compileModel:(id)sender
{
  (void)sender;
  NSError *error = nil;
  NSString *momdPath = nil;
  NSAlert *alert = [[NSAlert alloc] init];
  if ([self.modelDocument compileToMomd:&error momdPath:&momdPath]) {
    alert.messageText = @"Model compiled";
    alert.informativeText = [NSString stringWithFormat:@"Wrote %@", momdPath];
  } else {
    alert.messageText = @"Cannot compile model";
    alert.informativeText = error.localizedDescription ?: @"Unknown error.";
  }
  [alert runModal];
}

/* Xcode's Editor > Create NSManagedObject Subclass..., for the
   selected entity - or, with no entity selection, for every entity
   marked Class Definition / Category/Extension (falling back to every
   entity with a custom class when none is marked). */
- (IBAction)createManagedObjectSubclass:(id)sender
{
  (void)sender;
  NSArray *entities = nil;
  NSEntityDescription *selected = [self selectedEntity];
  if (selected != nil && selected.managedObjectClassName.length &&
      ![selected.managedObjectClassName isEqualToString:@"NSManagedObject"]) {
    entities = @[ selected ];
  } else {
    entities = [CDCodeGenerator generatableEntitiesInModel:self.model onlyMarked:YES];
    if (!entities.count)
      entities = [CDCodeGenerator generatableEntitiesInModel:self.model onlyMarked:NO];
  }
  if (!entities.count) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Nothing to generate";
    alert.informativeText =
        @"Give an entity a class other than NSManagedObject first (the Class field in the inspector).";
    [alert runModal];
    return;
  }

  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.canCreateDirectories = YES;
  panel.allowsMultipleSelection = NO;
  panel.prompt = @"Generate";
  panel.message = entities.count == 1
      ? [NSString stringWithFormat:@"Generate class files for %@ into:",
         [(NSEntityDescription *)entities.firstObject name]]
      : [NSString stringWithFormat:@"Generate class files for %lu entities into:",
         (unsigned long)entities.count];
  if ([panel runModal] != NSModalResponseOK) return;

  NSError *error = nil;
  NSArray *written = [CDCodeGenerator writeSourcesForEntities:entities
                                                  toDirectory:panel.URL.path
                                                        error:&error];
  if (!written) {
    [self presentModelError:error title:@"Cannot generate class files"];
    return;
  }
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Class files generated";
  alert.informativeText = [NSString stringWithFormat:@"Wrote %lu files to %@.",
      (unsigned long)written.count, panel.URL.path];
  [alert runModal];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = item.action;
  if (action == @selector(createManagedObjectSubclass:))
    return self.model.entities.count > 0;
  if (action == @selector(makeCurrentVersion:))
    return ![self.modelDocument.editedVersionName
        isEqualToString:self.modelDocument.currentVersionName];
  if (action == @selector(selectVersionMenuItem:)) {
    item.state = [[item representedObject]
        isEqualToString:self.modelDocument.editedVersionName] ? NSOnState : NSOffState;
    return YES;
  }
  if (action == @selector(compileModel:))
    return self.modelDocument.fileURL != nil;
  if (action == @selector(addFetchRequest:))
    return self.model.entities.count > 0;   /* a fetch needs an entity */
  if (action == @selector(removeEntity:) ||
      action == @selector(addAttribute:) ||
      action == @selector(addRelationship:))
    return [self selectedEntity] != nil;
  return YES;
}

#pragma mark - Source list data source / delegate

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item
{
  (void)outline;
  /* The nib connects the data source -- and GNUstep reloads on that --
     before -rebuildSourceItems has made the groups. */
  if (item == nil) return _entitiesGroup ? 3 : 0;
  if (item == _entitiesGroup) return (NSInteger)_entityItems.count;
  if (item == _fetchesGroup) return (NSInteger)_fetchItems.count;
  if (item == _configurationsGroup) return (NSInteger)_configurationItems.count;
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
  return _configurationItems[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item
{
  (void)outline;
  return [item isKindOfClass:[MBSourceItem class]] && [item isGroup];
}

- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
  (void)outline;
  if ([column.identifier isEqualToString:@"sourceIcon"]) {
    /* NSImageCell column: an NSImage or nil, never a string. */
    if (![item isKindOfClass:[MBSourceItem class]] || [item isGroup]) return nil;
    switch ([(MBSourceItem *)item kind]) {
      case MBSourceEntity:        return MBEntityBadge();
      case MBSourceFetch:         return MBFetchBadge();
      case MBSourceConfiguration: return MBConfigurationBadge();
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
  [self.modelDocument beginEdit:@"Rename"];
  [self applySourceListValue:value forTableColumn:column item:item outline:outline];
  [self.modelDocument endEdit];
}

- (void)applySourceListValue:(id)value forTableColumn:(NSTableColumn *)column item:(id)item outline:(NSOutlineView *)outline
{
  (void)outline;
  if (column && ![column.identifier isEqualToString:@"item"] &&
      column != outline.outlineTableColumn)
    return;
  if (![item isKindOfClass:[MBSourceItem class]] || [item isGroup] ||
      [(MBSourceItem *)item implicitDefault]) return;
  NSString *text = [value description];
  if (!text.length) return;
  MBSourceItem *source = item;
  if (source.kind == MBSourceEntity) {
    [self.modelDocument renameEntityNamed:source.name to:text];
  } else if (source.kind == MBSourceFetch) {
    [self.modelDocument renameFetchRequestNamed:source.name to:text];
  } else if (source.kind == MBSourceConfiguration) {
    [self.modelDocument renameConfiguration:source.name to:text error:NULL];
  }
  [self.modelDocument noteModelChanged];
  [self reloadEverything];
}

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

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  if (notification.object != self.sourceList) return;
  [self.attributeTable deselectAll:nil];
  [self.relationshipTable deselectAll:nil];
  [self.memberTable deselectAll:nil];
  [self rebuildPropertyRows];
  [self.attributeTable reloadData];
  [self.relationshipTable reloadData];
  [self.memberTable reloadData];
  [self refreshSelectionUI];
}

#pragma mark - Table data source / delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if (table == self.attributeTable) return (NSInteger)_attributeNames.count;
  if (table == self.relationshipTable) return (NSInteger)_relationshipNames.count;
  if (table == self.memberTable) return (NSInteger)_memberEntityNames.count;
  if (table == self.constraintsTable) return (NSInteger)_constraintRows.count;
  if (table == [self activeUserInfoTable]) return (NSInteger)_userInfoKeys.count;
  return 0;
}

#pragma mark - Badges

/* Xcode-style circular letter badges, drawn once and cached.  The
   cache key carries the color, so the same letter can appear in
   different tints (Float "F" vs Fetch Request "F"). */
static NSImage *MBBadgeImage(NSString *letters, CGFloat red, CGFloat green, CGFloat blue)
{
  static NSMutableDictionary *cache;
  if (!cache) cache = [NSMutableDictionary dictionary];
  NSString *key = [NSString stringWithFormat:@"%@|%.2f%.2f%.2f", letters, red, green, blue];
  NSImage *image = cache[key];
  if (image) return image;

  NSSize size = NSMakeSize(15, 15);
  image = [[NSImage alloc] initWithSize:size];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [image lockFocus];
  [[NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0] set];
  [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 14, 14)] fill];
  NSDictionary *attributes = @{
    NSFontAttributeName : [NSFont boldSystemFontOfSize:letters.length > 1 ? 7.0 : 9.0],
    NSForegroundColorAttributeName : [NSColor whiteColor],
  };
  NSSize textSize = [letters sizeWithAttributes:attributes];
  [letters drawAtPoint:NSMakePoint((size.width - textSize.width) / 2.0,
                                   (size.height - textSize.height) / 2.0)
        withAttributes:attributes];
  [image unlockFocus];
#pragma clang diagnostic pop
  cache[key] = image;
  return image;
}

/* Badge tints (muted, roughly Xcode's palette). */
static NSImage *MBAttributeBadge(NSString *letters) { return MBBadgeImage(letters, 0.47, 0.53, 0.64); }
static NSImage *MBEntityBadge(void)        { return MBBadgeImage(@"E", 0.36, 0.49, 0.72); }
static NSImage *MBRelationshipBadge(void)  { return MBBadgeImage(@"R", 0.32, 0.60, 0.53); }
static NSImage *MBFetchBadge(void)         { return MBBadgeImage(@"F", 0.58, 0.44, 0.72); }
static NSImage *MBConfigurationBadge(void) { return MBBadgeImage(@"C", 0.78, 0.57, 0.31); }

static NSString *MBAttributeBadgeLetters(NSAttributeDescription *attribute)
{
  switch (attribute.attributeType) {
    case NSStringAttributeType:        return @"S";
    case NSBooleanAttributeType:       return @"B";
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:     return @"I";
    case NSFloatAttributeType:         return @"F";
    case NSDoubleAttributeType:        return @"D";
    case NSDecimalAttributeType:       return @"Dc";
    case NSDateAttributeType:          return @"Dt";
    case NSBinaryDataAttributeType:    return @"Bn";
    case NSUUIDAttributeType:          return @"U";
    case NSURIAttributeType:           return @"Ur";
    case NSTransformableAttributeType: return @"T";
    default:                           return @"?";
  }
}

/* Badge for a table's leading NSImageCell column; nil draws blank. */
- (NSImage *)iconForTable:(NSTableView *)table row:(NSInteger)row
{
  if (row < 0) return nil;
  NSEntityDescription *entity = [self selectedEntity];
  if (table == self.attributeTable && entity &&
      (NSUInteger)row < _attributeNames.count) {
    NSAttributeDescription *attr = entity.attributesByName[_attributeNames[(NSUInteger)row]];
    return attr ? MBAttributeBadge(MBAttributeBadgeLetters(attr)) : nil;
  }
  if (table == self.relationshipTable && (NSUInteger)row < _relationshipNames.count)
    return MBRelationshipBadge();
  if (table == self.memberTable && (NSUInteger)row < _memberEntityNames.count)
    return MBEntityBadge();
  return nil;
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *ident = column.identifier ?: @"";
  NSEntityDescription *entity = [self selectedEntity];

  /* The narrow leading columns hold NSImageCells: hand them nil (an
     NSString would make NSImageCell throw on macOS), or a real badge
     when we have one. */
  if ([ident isEqualToString:@"icon"])
    return [self iconForTable:table row:row];

  if (table == self.attributeTable && entity && row >= 0 &&
      (NSUInteger)row < _attributeNames.count) {
    NSAttributeDescription *attr = entity.attributesByName[_attributeNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"type"])
      return [self mbIndexOf:[CDModelCompiler nameForAttributeType:attr.attributeType]
                   inChoices:[self mbChoicesForTable:table column:ident row:row]];
    return attr.name ?: @"";
  }
  if (table == self.relationshipTable && entity && row >= 0 &&
      (NSUInteger)row < _relationshipNames.count) {
    NSRelationshipDescription *rel = entity.relationshipsByName[_relationshipNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"destination"] || [ident isEqualToString:@"inverse"]) {
      NSString *current = [ident isEqualToString:@"destination"]
          ? rel.destinationEntity.name : (rel.inverseRelationship.name ?: @"(none)");
      return [self mbIndexOf:current
                   inChoices:[self mbChoicesForTable:table column:ident row:row]];
    }
    return rel.name ?: @"";
  }
  if (table == self.constraintsTable && row >= 0 &&
      (NSUInteger)row < _constraintRows.count) {
    return _constraintRows[(NSUInteger)row];
  }
  if (table == [self activeUserInfoTable] && row >= 0 &&
      (NSUInteger)row < _userInfoKeys.count) {
    NSString *key = _userInfoKeys[(NSUInteger)row];
    if ([ident isEqualToString:@"value"])
      return [[self currentUserInfo][key] description] ?: @"";
    return key;
  }
  if (table == self.memberTable && row >= 0 && (NSUInteger)row < _memberEntityNames.count) {
    NSString *name = _memberEntityNames[(NSUInteger)row];
    NSEntityDescription *rowEntity = self.model.entitiesByName[name];
    if ([ident isEqualToString:@"member"]) {
      if ([self selectedConfigurationIsImplicitDefault]) return @YES;
      NSString *configuration = [self selectedConfigurationName];
      if (!configuration) return @NO;
      NSArray *members = [self.model entitiesForConfiguration:configuration];
      for (NSEntityDescription *member in members)
        if ([member.name isEqualToString:name]) return @YES;
      return @NO;
    }
    if ([ident isEqualToString:@"isAbstract"]) return rowEntity.isAbstract ? @"YES" : @"";
    if ([ident isEqualToString:@"class"]) return rowEntity.managedObjectClassName ?: @"";
    return name;
  }
  return @"";
}

- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  [self.modelDocument beginEdit:@"Edit"];
  [self applyTableValue:value table:table forTableColumn:column row:row];
  [self.modelDocument endEdit];
}

- (void)applyTableValue:(id)value table:(NSTableView *)table forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *ident = column.identifier;
  NSEntityDescription *entity = [self selectedEntity];

  /* A popup column hands back the index of the item chosen. */
  NSArray *choices = [self mbChoicesForTable:table column:ident row:row];
  if (choices && [value isKindOfClass:[NSNumber class]]) {
    NSInteger index = [value integerValue];
    if (index < 0 || (NSUInteger)index >= choices.count) return;
    value = choices[(NSUInteger)index];
  }

  if (table == [self activeUserInfoTable] &&
      table != self.memberTable && table != self.constraintsTable) {
    if (row < 0 || (NSUInteger)row >= _userInfoKeys.count) return;
    NSString *key = _userInfoKeys[(NSUInteger)row];
    NSString *text = [value description];
    NSMutableDictionary *info = [([self currentUserInfo] ?: @{}) mutableCopy];
    if ([ident isEqualToString:@"value"]) {
      info[key] = text;
    } else if (text.length && !info[text]) {
      info[text] = info[key] ?: @"";
      [info removeObjectForKey:key];
    }
    [self setCurrentUserInfo:info];
    [self reloadUserInfoTables];
    [self.modelDocument noteModelChanged];
    return;
  }
  if (table == self.constraintsTable) {
    if (row < 0 || (NSUInteger)row >= _constraintRows.count) return;
    _constraintRows[(NSUInteger)row] = [value description] ?: @"";
    [self applyConstraintRows];
    [self rebuildConstraintRows];
    [self.constraintsTable reloadData];
    return;
  }
  if (table == self.attributeTable && entity && (NSUInteger)row < _attributeNames.count) {
    MBAttributeEditor *editor = [MBAttributeEditor
        editorForAttributeNamed:_attributeNames[(NSUInteger)row]
                         entity:entity
                       document:self.modelDocument];
    if ([ident isEqualToString:@"name"]) editor.name = [value description];
    else if ([ident isEqualToString:@"type"]) editor.typeName = [value description];
    [self reloadPropertyTable:self.attributeTable selecting:editor.name];
    [self fillInspector];
    return;
  }
  if (table == self.relationshipTable && entity && (NSUInteger)row < _relationshipNames.count) {
    MBRelationshipEditor *editor = [MBRelationshipEditor
        editorForRelationshipNamed:_relationshipNames[(NSUInteger)row]
                            entity:entity
                          document:self.modelDocument];
    if ([ident isEqualToString:@"name"]) editor.name = [value description];
    else if ([ident isEqualToString:@"destination"]) editor.destinationName = [value description];
    else if ([ident isEqualToString:@"inverse"]) editor.inverseName = [value description];
    [self reloadPropertyTable:self.relationshipTable selecting:editor.name];
    [self fillInspector];
    return;
  }
  if (table == self.memberTable && (NSUInteger)row < _memberEntityNames.count &&
      [ident isEqualToString:@"member"]) {
    NSString *configuration = [self selectedConfigurationName];
    if (!configuration) return;
    NSError *error = nil;
    if (![self.modelDocument setEntityNamed:_memberEntityNames[(NSUInteger)row]
                            inConfiguration:configuration
                                     member:[value boolValue]
                                      error:&error])
      [self presentModelError:error title:@"Cannot change membership"];
    [self.memberTable reloadData];
  }
}

/* The Type / Destination / Inverse columns are popups, as in Xcode's
   model editor.  Their choices: the momc type names; every entity; and
   (none) plus the relationships of that row's destination -- the one
   list that differs by row. */
- (NSArray *)mbChoicesForTable:(NSTableView *)table column:(NSString *)ident row:(NSInteger)row
{
  if (table == self.attributeTable && [ident isEqualToString:@"type"])
    return [CDModelCompiler attributeTypeNames];
  if (table == self.relationshipTable && [ident isEqualToString:@"destination"])
    return [[self.model.entitiesByName allKeys] sortedArrayUsingSelector:@selector(compare:)];
  if (table == self.relationshipTable && [ident isEqualToString:@"inverse"]) {
    NSMutableArray *names = [NSMutableArray arrayWithObject:@"(none)"];
    NSEntityDescription *entity = [self selectedEntity];
    if (entity && row >= 0 && (NSUInteger)row < _relationshipNames.count) {
      NSRelationshipDescription *rel =
          entity.relationshipsByName[_relationshipNames[(NSUInteger)row]];
      [names addObjectsFromArray:[[rel.destinationEntity.relationshipsByName allKeys]
          sortedArrayUsingSelector:@selector(compare:)]];
    }
    return names;
  }
  return nil;
}

- (NSNumber *)mbIndexOf:(NSString *)name inChoices:(NSArray *)choices
{
  NSUInteger index = name ? [choices indexOfObject:name] : NSNotFound;
  return @(index == NSNotFound ? -1 : (NSInteger)index);
}

- (void)tableView:(NSTableView *)table willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  if (table == self.memberTable && [column.identifier isEqualToString:@"member"]) {
    /* Default is every entity; there is nothing to tick or untick. */
    [cell setEnabled:![self selectedConfigurationIsImplicitDefault]];
    return;
  }
  if (![cell isKindOfClass:[NSPopUpButtonCell class]]) return;
  NSArray *choices = [self mbChoicesForTable:table column:column.identifier row:row];
  if (!choices) return;
  NSPopUpButtonCell *popup = cell;
  [popup removeAllItems];
  [popup addItemsWithTitles:choices];
  [popup selectItemAtIndex:[[self tableView:table objectValueForTableColumn:column row:row] integerValue]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  NSTableView *table = notification.object;
  if (table == self.attributeTable) {
    if (self.attributeTable.selectedRow >= 0)
      [self.relationshipTable deselectAll:nil];
  } else if (table == self.relationshipTable) {
    if (self.relationshipTable.selectedRow >= 0)
      [self.attributeTable deselectAll:nil];
  } else if (table != self.memberTable) {
    return;   /* userInfo / constraints selection is not an inspector change */
  }
  [self refreshSelectionUI];
}

#pragma mark - Split view delegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  (void)dividerIndex;
  if (splitView == _barSplit) return proposed;
  return MAX(proposed, splitView == _outerSplit ? MBSidePaneMinimum + MBCenterPaneMinimum
                                                : MBSidePaneMinimum);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  (void)dividerIndex;
  if (splitView == _outerSplit)
    return MIN(proposed, NSWidth(splitView.bounds) - MBInspectorMinimum - splitView.dividerThickness);
  if (splitView == _sourceSplit)
    return MIN(proposed, NSWidth(splitView.bounds) - MBCenterPaneMinimum - splitView.dividerThickness);
  return proposed;
}

/* A wider window is for a wider editor: the source list, the inspector and
   the button bar keep the size they were dragged to, and the center takes
   the difference -- as Xcode's model editor does, and the XForms and RDL
   designers.  Once the window is narrower than all the minimums together,
   holding the sides would squeeze the center to nothing, so everyone gives
   way. */
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
  NSArray *panes = splitView.subviews;
  if (splitView == _barSplit) return subview != panes.lastObject;
  if (splitView == _outerSplit) {
    if (NSWidth(splitView.bounds) < self.window.minSize.width) return YES;
    return subview != panes.lastObject;
  }
  if (splitView == _sourceSplit) {
    if (NSWidth(splitView.bounds) < MBSidePaneMinimum + MBCenterPaneMinimum) return YES;
    return subview != panes.firstObject;
  }
  return YES;
}

#if !defined(__APPLE__)
/* Ported from RDL Designer.  GNUstep's -adjustSubviews always sizes the
   last subview to whatever space is left and never asks
   -splitView:shouldAdjustSizeOfSubview: about it, so a trailing pane (the
   inspector, the button bar) cannot hold its size there.  Distribute by
   hand to the rule above: the subviews that should not adjust keep their
   span, and those that should share what is left in proportion to the
   spans they had. */
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
  (void)oldSize;
  NSArray *subviews = splitView.subviews;
  NSUInteger count = subviews.count;
  if (count == 0) return;
  BOOL vertical = splitView.isVertical;
  NSRect bounds = splitView.bounds;
  CGFloat divider = splitView.dividerThickness;
  CGFloat total = (vertical ? NSWidth(bounds) : NSHeight(bounds)) - divider * (CGFloat)(count - 1);
  CGFloat spans[count];
  BOOL adjust[count];
  CGFloat oldAdjustable = 0, fixed = 0;
  NSUInteger adjustableCount = 0;
  for (NSUInteger i = 0; i < count; i++) {
    NSRect frame = [subviews[i] frame];
    spans[i] = vertical ? NSWidth(frame) : NSHeight(frame);
    adjust[i] = ![splitView isSubviewCollapsed:subviews[i]] &&
                [self splitView:splitView shouldAdjustSizeOfSubview:subviews[i]];
    if (adjust[i]) { oldAdjustable += spans[i]; adjustableCount++; }
    else fixed += spans[i];
  }
  if (adjustableCount == 0) {
    /* nothing may give: let the last pane take the difference */
    adjust[count - 1] = YES;
    oldAdjustable = spans[count - 1];
    fixed -= spans[count - 1];
    adjustableCount = 1;
  }
  CGFloat forAdjustable = MAX(0, total - fixed);
  CGFloat running = 0;
  for (NSUInteger i = 0; i < count; i++) {
    CGFloat span = spans[i];
    if (adjust[i])
      span = oldAdjustable > 0.5 ? forAdjustable * (spans[i] / oldAdjustable)
                                 : forAdjustable / (CGFloat)adjustableCount;
    NSRect rect = vertical ? NSMakeRect(running, 0, span, NSHeight(bounds))
                           : NSMakeRect(0, running, NSWidth(bounds), span);
    [subviews[i] setFrame:[splitView centerScanRect:rect]];
    running += span + divider;
  }
}
#endif

@end
