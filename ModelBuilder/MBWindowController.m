/* ModelBuilder document window — Xcode-style three-pane editor built
   entirely in code.  See MBWindowController.h for the layout map.
   Editing semantics: the tables and inspector mutate NSEntityDescription /
   NSAttributeDescription / NSRelationshipDescription directly; structural
   surgery (delete entity, reparent, configuration changes) goes through
   MBDocument's XML mutation path so momc renormalizes the graph.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBWindowController.h"
#import "MBDocument.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"

typedef NS_ENUM(NSInteger, MBSourceKind) {
  MBSourceGroupEntities = 0,
  MBSourceGroupFetches,
  MBSourceGroupConfigurations,
  MBSourceEntity,
  MBSourceFetch,
  MBSourceConfiguration
};

/* One row of the source list. */
@interface MBSourceItem : NSObject
@property (nonatomic, assign) MBSourceKind kind;
@property (nonatomic, copy) NSString *name;
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

static const CGFloat kLeftWidth = 210.0;
static const CGFloat kRightWidth = 280.0;
static const CGFloat kBottomBarHeight = 32.0;
static const CGFloat kButtonRowHeight = 24.0;

@implementation MBWindowController {
  MBInspectKind _kind;
  BOOL _updating;

  MBSourceItem *_entitiesGroup, *_fetchesGroup, *_configurationsGroup;
  NSArray *_entityItems, *_fetchItems, *_configurationItems;

  NSArray *_attributeNames;
  NSArray *_relationshipNames;
  NSArray *_userInfoKeys;
  NSArray *_memberEntityNames;   /* all entities, for the membership checklist */

  NSSplitView *_split;
  NSView *_centerContainer;
  NSView *_inspectorContainer;
  NSView *_entityForm, *_attributeForm, *_relationshipForm, *_fetchForm, *_configurationForm, *_emptyForm;
  NSView *_userInfoSection;      /* shared: reparented into the visible form */
  CGFloat _leftWidth, _rightWidth;
}

static NSWindow *MBMakeDocumentWindow(void)
{
  NSRect contentRect = NSMakeRect(120, 120, 1120, 700);
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:contentRect
                styleMask:(NSTitledWindowMask | NSClosableWindowMask |
                           NSMiniaturizableWindowMask | NSResizableWindowMask)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.minSize = NSMakeSize(960, 560);
  return window;
}

- (instancetype)init
{
  /* Nib-less window controllers must hand the window to
     -initWithWindow: up front: on macOS a controller initialized with
     initWithWindow: (even with nil) never calls -loadWindow, so a
     window built there silently never appears. */
  NSWindow *window = MBMakeDocumentWindow();
  self = [super initWithWindow:window];
  if (self) {
    _leftWidth = kLeftWidth;
    _rightWidth = kRightWidth;
    [self buildContentInWindow:window];
  }
  return self;
}

- (MBDocument *)modelDocument
{
  return (MBDocument *)self.document;
}

- (NSManagedObjectModel *)model
{
  return self.modelDocument.model;
}

#pragma mark - Small construction helpers

static NSTextField *MBLabel(NSString *text, NSRect frame)
{
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
  label.stringValue = text;
  label.bezeled = NO;
  label.bordered = NO;
  label.editable = NO;
  label.selectable = NO;
  label.drawsBackground = NO;
  label.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  return label;
}

static NSTextField *MBHeader(NSString *text, NSRect frame)
{
  NSTextField *label = MBLabel(text, frame);
  label.font = [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];
  return label;
}

- (NSTextField *)makeFieldAt:(NSRect)frame
{
  NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
  field.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  field.delegate = self;
  field.target = self;
  field.action = @selector(inspectorChanged:);
  return field;
}

- (NSPopUpButton *)makePopupAt:(NSRect)frame
{
  NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
  popup.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  popup.target = self;
  popup.action = @selector(inspectorChanged:);
  return popup;
}

- (NSButton *)makeCheckbox:(NSString *)title at:(NSRect)frame
{
  NSButton *button = [[NSButton alloc] initWithFrame:frame];
  [button setButtonType:NSSwitchButton];
  button.title = title;
  button.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  button.target = self;
  button.action = @selector(inspectorChanged:);
  return button;
}

- (NSButton *)makeBarButton:(NSString *)title action:(SEL)action frame:(NSRect)frame
{
  NSButton *button = [[NSButton alloc] initWithFrame:frame];
  button.title = title;
  button.bezelStyle = NSRoundedBezelStyle;
  button.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  button.target = self;
  button.action = action;
  return button;
}

/* The HIG-style +/- pair that sits under a table. */
- (NSButton *)makeSquareButton:(NSString *)title action:(SEL)action x:(CGFloat)x
{
  NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, 0, 26, kButtonRowHeight)];
  button.title = title;
  button.bezelStyle = NSSmallSquareBezelStyle;
  button.target = self;
  button.action = action;
  button.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
  return button;
}

- (NSScrollView *)wrapInScroll:(NSView *)view frame:(NSRect)frame
{
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
  scroll.hasVerticalScroller = YES;
  scroll.hasHorizontalScroller = NO;
  scroll.borderType = NSBezelBorder;
  scroll.documentView = view;
  scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  return scroll;
}

- (NSTableColumn *)addColumn:(NSString *)identifier title:(NSString *)title width:(CGFloat)width to:(NSTableView *)table editable:(BOOL)editable
{
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
  [[column headerCell] setStringValue:title];
  column.width = width;
  column.editable = editable;
  NSTextFieldCell *cell = [[NSTextFieldCell alloc] init];
  cell.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  cell.editable = editable;
  cell.drawsBackground = NO;
  cell.lineBreakMode = NSLineBreakByTruncatingTail;
  column.dataCell = cell;
  [table addTableColumn:column];
  return column;
}

- (NSTableColumn *)addCheckboxColumn:(NSString *)identifier title:(NSString *)title width:(CGFloat)width to:(NSTableView *)table
{
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
  [[column headerCell] setStringValue:title];
  column.width = width;
  column.editable = YES;
  NSButtonCell *cell = [[NSButtonCell alloc] init];
  [cell setButtonType:NSSwitchButton];
  cell.title = @"";
  column.dataCell = cell;
  [table addTableColumn:column];
  return column;
}

- (NSTableView *)makeTableWithFrame:(NSRect)frame
{
  NSTableView *table = [[NSTableView alloc] initWithFrame:frame];
  table.dataSource = self;
  table.delegate = self;
  table.rowHeight = 18.0;
  table.usesAlternatingRowBackgroundColors = YES;
  table.allowsEmptySelection = YES;
  table.allowsMultipleSelection = NO;
  return table;
}

#pragma mark - Window construction

- (void)buildContentInWindow:(NSWindow *)window
{
  NSView *content = window.contentView;
  NSRect bounds = content.bounds;

  [self buildBottomBarIn:content bounds:bounds];

  _split = [[NSSplitView alloc] initWithFrame:
      NSMakeRect(0, kBottomBarHeight, bounds.size.width,
                 bounds.size.height - kBottomBarHeight)];
  [_split setVertical:YES];
  _split.delegate = self;
  _split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [content addSubview:_split];

  [_split addSubview:[self buildSourcePane]];
  [_split addSubview:[self buildCenterPane]];
  [_split addSubview:[self buildInspectorPane]];
  [_split adjustSubviews];
}

- (void)buildBottomBarIn:(NSView *)content bounds:(NSRect)bounds
{
  NSView *bar = [[NSView alloc] initWithFrame:
      NSMakeRect(0, 0, bounds.size.width, kBottomBarHeight)];
  bar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;

  CGFloat y = (kBottomBarHeight - 22) / 2.0;
  CGFloat rightEdge = bounds.size.width - 8;

  self.validateButton = [self makeBarButton:@"Validate" action:@selector(validateModel:)
                                      frame:NSMakeRect(rightEdge - 80, y, 80, 22)];
  self.validateButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  [bar addSubview:self.validateButton];
  rightEdge -= 84;

  self.makeCurrentButton = [self makeBarButton:@"Make Current" action:@selector(makeCurrentVersion:)
                                         frame:NSMakeRect(rightEdge - 108, y, 108, 22)];
  self.makeCurrentButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  [bar addSubview:self.makeCurrentButton];
  rightEdge -= 112;

  self.addVersionButton = [self makeBarButton:@"+ Version" action:@selector(addModelVersion:)
                                        frame:NSMakeRect(rightEdge - 84, y, 84, 22)];
  self.addVersionButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  [bar addSubview:self.addVersionButton];
  rightEdge -= 88;

  self.versionPopup = [[NSPopUpButton alloc]
      initWithFrame:NSMakeRect(rightEdge - 190, y, 190, 22) pullsDown:NO];
  self.versionPopup.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  self.versionPopup.target = self;
  self.versionPopup.action = @selector(versionSelected:);
  self.versionPopup.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  [bar addSubview:self.versionPopup];
  rightEdge -= 194;

  self.statusField = MBLabel(@"", NSMakeRect(10, y + 2, rightEdge - 18, 18));
  self.statusField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
  [bar addSubview:self.statusField];

  [content addSubview:bar];
}

- (NSView *)buildSourcePane
{
  NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kLeftWidth, 640)];

  self.sourceList = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, kLeftWidth, 600)];
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"item"];
  column.width = kLeftWidth - 24;
  column.editable = YES;
  NSTextFieldCell *cell = [[NSTextFieldCell alloc] init];
  cell.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  cell.editable = YES;
  cell.drawsBackground = NO;
  cell.lineBreakMode = NSLineBreakByTruncatingTail;
  column.dataCell = cell;
  [self.sourceList addTableColumn:column];
  [self.sourceList setOutlineTableColumn:column];
  self.sourceList.headerView = nil;
  self.sourceList.rowHeight = 18.0;
  self.sourceList.dataSource = self;
  self.sourceList.delegate = self;
  self.sourceList.indentationPerLevel = 12.0;

  NSScrollView *scroll = [self wrapInScroll:self.sourceList
                                      frame:NSMakeRect(0, kButtonRowHeight,
                                                       kLeftWidth,
                                                       640 - kButtonRowHeight)];
  [pane addSubview:scroll];

  self.sourceAddButton = [self makeSquareButton:@"+" action:@selector(addSourceItem:) x:0];
  [pane addSubview:self.sourceAddButton];
  self.sourceRemoveButton = [self makeSquareButton:@"−" action:@selector(removeSourceItem:) x:25];
  [pane addSubview:self.sourceRemoveButton];

  return pane;
}

/* A titled table section with +/- under it (the HIG placement). */
- (NSView *)makeSectionTitled:(NSString *)title
                        table:(NSTableView *)table
                    addAction:(SEL)addAction
                 removeAction:(SEL)removeAction
                        frame:(NSRect)frame
{
  NSView *section = [[NSView alloc] initWithFrame:frame];
  section.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  CGFloat h = frame.size.height;

  NSTextField *header = MBHeader(title, NSMakeRect(2, h - 18, frame.size.width - 4, 16));
  header.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
  [section addSubview:header];

  CGFloat tableBottom = removeAction ? kButtonRowHeight : 0;
  NSScrollView *scroll = [self wrapInScroll:table
                                      frame:NSMakeRect(0, tableBottom,
                                                       frame.size.width,
                                                       h - tableBottom - 22)];
  [section addSubview:scroll];

  if (addAction) {
    [section addSubview:[self makeSquareButton:@"+" action:addAction x:0]];
    [section addSubview:[self makeSquareButton:@"−" action:removeAction x:25]];
  }
  return section;
}

- (NSView *)buildCenterPane
{
  _centerContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 640)];
  NSRect bounds = _centerContainer.bounds;

  /* Entity editor: attributes over relationships in a horizontal split. */
  self.attributeTable = [self makeTableWithFrame:NSMakeRect(0, 0, 580, 200)];
  [self addColumn:@"name" title:@"Attribute" width:220 to:self.attributeTable editable:YES];
  [self addColumn:@"type" title:@"Type" width:120 to:self.attributeTable editable:NO];
  [self addCheckboxColumn:@"optional" title:@"Optional" width:60 to:self.attributeTable];

  self.relationshipTable = [self makeTableWithFrame:NSMakeRect(0, 0, 580, 200)];
  [self addColumn:@"name" title:@"Relationship" width:180 to:self.relationshipTable editable:YES];
  [self addColumn:@"destination" title:@"Destination" width:150 to:self.relationshipTable editable:NO];
  [self addColumn:@"toMany" title:@"Kind" width:80 to:self.relationshipTable editable:NO];

  NSSplitView *entitySplit = [[NSSplitView alloc] initWithFrame:bounds];
  [entitySplit setVertical:NO];
  entitySplit.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  CGFloat half = bounds.size.height / 2.0;
  [entitySplit addSubview:
      [self makeSectionTitled:@"Attributes"
                        table:self.attributeTable
                    addAction:@selector(addAttribute:)
                 removeAction:@selector(removeAttribute:)
                        frame:NSMakeRect(0, 0, bounds.size.width, half)]];
  [entitySplit addSubview:
      [self makeSectionTitled:@"Relationships"
                        table:self.relationshipTable
                    addAction:@selector(addRelationship:)
                 removeAction:@selector(removeRelationship:)
                        frame:NSMakeRect(0, 0, bounds.size.width, half)]];
  self.entityEditor = entitySplit;
  [_centerContainer addSubview:self.entityEditor];

  /* Fetch request editor. */
  self.fetchEditor = [[NSView alloc] initWithFrame:bounds];
  self.fetchEditor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  CGFloat top = bounds.size.height;
  NSTextField *entityLabel = MBLabel(@"Fetch all:", NSMakeRect(4, top - 26, 70, 18));
  entityLabel.autoresizingMask = NSViewMinYMargin;
  [self.fetchEditor addSubview:entityLabel];
  self.fetchEntityPopup = [self makePopupAt:NSMakeRect(78, top - 30, 220, 24)];
  self.fetchEntityPopup.autoresizingMask = NSViewMinYMargin;
  [self.fetchEditor addSubview:self.fetchEntityPopup];
  NSTextField *predicateLabel = MBLabel(@"Where:", NSMakeRect(4, top - 52, 100, 18));
  predicateLabel.autoresizingMask = NSViewMinYMargin;
  [self.fetchEditor addSubview:predicateLabel];

  self.predicateView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, bounds.size.width, top - 60)];
  self.predicateView.font = [NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]];
  self.predicateView.delegate = self;
  self.predicateView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  NSScrollView *predicateScroll = [self wrapInScroll:self.predicateView
                                               frame:NSMakeRect(0, 0, bounds.size.width, top - 60)];
  [self.fetchEditor addSubview:predicateScroll];
  [_centerContainer addSubview:self.fetchEditor];

  /* Configuration editor: membership checklist. */
  self.memberTable = [self makeTableWithFrame:NSMakeRect(0, 0, 580, 400)];
  [self addCheckboxColumn:@"member" title:@"Member" width:60 to:self.memberTable];
  [self addColumn:@"entity" title:@"Entity" width:260 to:self.memberTable editable:NO];
  self.configurationEditor = [self makeSectionTitled:@"Member Entities"
                                               table:self.memberTable
                                           addAction:NULL
                                        removeAction:NULL
                                               frame:bounds];
  [_centerContainer addSubview:self.configurationEditor];

  return _centerContainer;
}

#pragma mark - Inspector construction

/* Rows are laid out top-down inside a fixed-height form view that is
   anchored to the top of the inspector. */
- (NSView *)beginForm
{
  NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kRightWidth, 560)];
  form.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
  return form;
}

- (NSRect)rowIn:(NSView *)form at:(CGFloat *)y label:(NSString *)label
{
  *y -= 26;
  if (label) {
    NSTextField *l = MBLabel(label, NSMakeRect(4, *y + 3, 86, 16));
    [(NSTextFieldCell *)l.cell setAlignment:NSRightTextAlignment];
    [form addSubview:l];
  }
  return NSMakeRect(96, *y, kRightWidth - 104, 22);
}

- (NSView *)buildAttributeForm
{
  NSView *form = [self beginForm];
  CGFloat y = 560;
  self.typePopup = [self makePopupAt:[self rowIn:form at:&y label:@"Type"]];
  [self.typePopup addItemsWithTitles:[CDModelCompiler attributeTypeNames]];
  [form addSubview:self.typePopup];
  self.optionalButton = [self makeCheckbox:@"Optional" at:[self rowIn:form at:&y label:nil]];
  [form addSubview:self.optionalButton];
  self.transientButton = [self makeCheckbox:@"Transient" at:[self rowIn:form at:&y label:nil]];
  [form addSubview:self.transientButton];
  self.defaultField = [self makeFieldAt:[self rowIn:form at:&y label:@"Default"]];
  [form addSubview:self.defaultField];
  self.derivationField = [self makeFieldAt:[self rowIn:form at:&y label:@"Derivation"]];
  [form addSubview:self.derivationField];
  return form;
}

- (NSView *)buildRelationshipForm
{
  NSView *form = [self beginForm];
  CGFloat y = 560;
  self.destinationPopup = [self makePopupAt:[self rowIn:form at:&y label:@"Destination"]];
  [form addSubview:self.destinationPopup];
  self.inversePopup = [self makePopupAt:[self rowIn:form at:&y label:@"Inverse"]];
  [form addSubview:self.inversePopup];
  self.toManyButton = [self makeCheckbox:@"To-many" at:[self rowIn:form at:&y label:nil]];
  [form addSubview:self.toManyButton];
  self.orderedButton = [self makeCheckbox:@"Ordered" at:[self rowIn:form at:&y label:nil]];
  [form addSubview:self.orderedButton];
  self.deleteRulePopup = [self makePopupAt:[self rowIn:form at:&y label:@"Delete rule"]];
  [self.deleteRulePopup addItemsWithTitles:[CDModelCompiler deleteRuleNames]];
  [form addSubview:self.deleteRulePopup];
  self.minField = [self makeFieldAt:[self rowIn:form at:&y label:@"Min count"]];
  [form addSubview:self.minField];
  self.maxField = [self makeFieldAt:[self rowIn:form at:&y label:@"Max count"]];
  [form addSubview:self.maxField];
  return form;
}

- (NSView *)buildFetchForm
{
  return [self beginForm];   /* the fetch editor lives in the center pane */
}

- (NSView *)buildConfigurationForm
{
  return [self beginForm];   /* only the shared name field applies */
}

- (NSView *)buildUserInfoSection
{
  NSView *section = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kRightWidth, 190)];
  section.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;

  NSTextField *header = MBHeader(@"User Info", NSMakeRect(4, 168, kRightWidth - 8, 16));
  [section addSubview:header];

  self.userInfoTable = [self makeTableWithFrame:NSMakeRect(0, 0, kRightWidth, 130)];
  [self addColumn:@"key" title:@"Key" width:110 to:self.userInfoTable editable:YES];
  [self addColumn:@"value" title:@"Value" width:130 to:self.userInfoTable editable:YES];
  NSScrollView *scroll = [self wrapInScroll:self.userInfoTable
                                      frame:NSMakeRect(0, kButtonRowHeight, kRightWidth, 164 - kButtonRowHeight)];
  scroll.autoresizingMask = NSViewWidthSizable;
  [section addSubview:scroll];

  [section addSubview:[self makeSquareButton:@"+" action:@selector(addUserInfo:) x:0]];
  [section addSubview:[self makeSquareButton:@"−" action:@selector(removeUserInfo:) x:25]];
  return section;
}

- (NSView *)buildInspectorPane
{
  _inspectorContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kRightWidth, 640)];
  NSRect bounds = _inspectorContainer.bounds;

  self.inspectorTitle = MBHeader(@"Inspector", NSMakeRect(6, bounds.size.height - 20, kRightWidth - 12, 16));
  self.inspectorTitle.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
  [_inspectorContainer addSubview:self.inspectorTitle];

  /* Shared name row directly under the title. */
  NSTextField *nameLabel = MBLabel(@"Name", NSMakeRect(4, bounds.size.height - 44, 86, 16));
  [(NSTextFieldCell *)nameLabel.cell setAlignment:NSRightTextAlignment];
  nameLabel.autoresizingMask = NSViewMinYMargin;
  [_inspectorContainer addSubview:nameLabel];
  self.nameField = [self makeFieldAt:NSMakeRect(96, bounds.size.height - 47, kRightWidth - 104, 22)];
  self.nameField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
  [_inspectorContainer addSubview:self.nameField];

  /* Entity-only rows. */
  _entityForm = [self beginForm];
  CGFloat y = 560;
  self.classField = [self makeFieldAt:[self rowIn:_entityForm at:&y label:@"Class"]];
  [_entityForm addSubview:self.classField];
  self.parentPopup = [self makePopupAt:[self rowIn:_entityForm at:&y label:@"Parent"]];
  [_entityForm addSubview:self.parentPopup];
  self.abstractButton = [self makeCheckbox:@"Abstract entity" at:[self rowIn:_entityForm at:&y label:nil]];
  [_entityForm addSubview:self.abstractButton];

  _attributeForm = [self buildAttributeForm];
  _relationshipForm = [self buildRelationshipForm];
  _fetchForm = [self buildFetchForm];
  _configurationForm = [self buildConfigurationForm];
  _emptyForm = [self beginForm];
  _userInfoSection = [self buildUserInfoSection];

  for (NSView *form in @[ _entityForm, _attributeForm, _relationshipForm, _fetchForm, _configurationForm, _emptyForm ]) {
    form.frame = NSMakeRect(0, bounds.size.height - 52 - 560, kRightWidth, 560);
    form.hidden = YES;
    [_inspectorContainer addSubview:form];
  }
  _userInfoSection.frame = NSMakeRect(0, 4, kRightWidth, 190);
  [_inspectorContainer addSubview:_userInfoSection];

  return _inspectorContainer;
}

#pragma mark - Window lifecycle

/* With a nib-less controller -windowDidLoad never fires; the document
   attach is the population point on both toolkits. */
- (void)setDocument:(NSDocument *)document
{
  [super setDocument:document];
  if (!document) return;
  [self synchronizeWindowTitleWithDocumentName];
  [self reloadEverything];
  if (_entityItems.count)
    [self selectSourceItem:_entityItems.firstObject];
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
  for (NSString *name in [self.modelDocument configurationNames])
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

- (NSString *)selectedConfigurationName
{
  MBSourceItem *item = [self selectedSourceItem];
  return item.kind == MBSourceConfiguration ? item.name : nil;
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

#pragma mark - Row caches / reload

- (void)rebuildPropertyRows
{
  NSEntityDescription *entity = [self selectedEntity];
  NSMutableArray *attributes = [NSMutableArray array];
  NSMutableArray *relationships = [NSMutableArray array];
  for (NSPropertyDescription *property in entity.properties) {
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
  if (_kind == MBInspectEntity) [[self selectedEntity] setUserInfo:userInfo];
  else if (_kind == MBInspectAttribute) [[self selectedAttribute] setUserInfo:userInfo];
  else if (_kind == MBInspectRelationship) [[self selectedRelationship] setUserInfo:userInfo];
  [self rebuildUserInfoRows];
}

- (void)rebuildUserInfoRows
{
  _userInfoKeys = [[[self currentUserInfo] allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
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
  [self updateVersionBar];
}

/* Recomputes the center pane, inspector kind and status for the
   current selection. */
- (void)refreshSelectionUI
{
  MBSourceItem *item = [self selectedSourceItem];

  self.entityEditor.hidden = (item.kind != MBSourceEntity);
  self.fetchEditor.hidden = (item.kind != MBSourceFetch);
  self.configurationEditor.hidden = (item.kind != MBSourceConfiguration);

  if (item.kind == MBSourceEntity) {
    if (self.attributeTable.selectedRow >= 0) _kind = MBInspectAttribute;
    else if (self.relationshipTable.selectedRow >= 0) _kind = MBInspectRelationship;
    else _kind = MBInspectEntity;
  } else if (item.kind == MBSourceFetch) {
    _kind = MBInspectFetch;
  } else if (item.kind == MBSourceConfiguration) {
    _kind = MBInspectConfiguration;
  } else {
    _kind = MBInspectNone;
  }

  [self rebuildUserInfoRows];
  [self.userInfoTable reloadData];
  [self fillInspector];
  [self updateStatus];
}

- (void)updateStatus
{
  MBDocument *doc = self.modelDocument;
  self.statusField.stringValue = [NSString stringWithFormat:@"%@%@  —  %lu entities, %lu fetch requests, %lu configurations",
      doc.editedVersionName ?: @"untitled",
      [doc.editedVersionName isEqualToString:doc.currentVersionName] ? @" (current)" : @"",
      (unsigned long)self.model.entities.count,
      (unsigned long)[self.model fetchRequestTemplatesByName].count,
      (unsigned long)[self.modelDocument configurationNames].count];
}

- (void)updateVersionBar
{
  MBDocument *doc = self.modelDocument;
  [self.versionPopup removeAllItems];
  for (NSString *name in [doc versionNames]) {
    NSString *title = [name isEqualToString:doc.currentVersionName]
        ? [name stringByAppendingString:@"  ✓"] : name;
    [self.versionPopup addItemWithTitle:title];
    [[self.versionPopup lastItem] setRepresentedObject:name];
  }
  for (NSMenuItem *item in [[self.versionPopup menu] itemArray]) {
    if ([[item representedObject] isEqualToString:doc.editedVersionName]) {
      [self.versionPopup selectItem:item];
      break;
    }
  }
  self.makeCurrentButton.enabled =
      ![doc.editedVersionName isEqualToString:doc.currentVersionName];
}

#pragma mark - Inspector fill

- (void)showForm:(NSView *)form
{
  for (NSView *candidate in @[ _entityForm, _attributeForm, _relationshipForm,
                               _fetchForm, _configurationForm, _emptyForm ])
    candidate.hidden = (candidate != form);
  _userInfoSection.hidden = !(form == _entityForm || form == _attributeForm ||
                              form == _relationshipForm);
}

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

- (void)rebuildDestinationPopupInto:(NSPopUpButton *)popup
{
  [popup removeAllItems];
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

- (NSString *)stringForDefaultValue:(id)value type:(NSAttributeType)type
{
  switch (type) {
    case NSBooleanAttributeType: return [value boolValue] ? @"YES" : @"NO";
    case NSDateAttributeType:
      return [@([value timeIntervalSinceReferenceDate]) stringValue];
    case NSUUIDAttributeType: return [value UUIDString];
    case NSURIAttributeType: return [value absoluteString];
    default: return [value description];
  }
}

- (NSString *)stringForDerivation:(NSExpression *)expression
{
  switch (expression.expressionType) {
    case NSKeyPathExpressionType: return expression.keyPath;
    case NSFunctionExpressionType: {
      NSString *name = expression.function;
      if ([name hasSuffix:@":"]) name = [name substringToIndex:name.length - 1];
      if (expression.arguments.count == 0) return [name stringByAppendingString:@"()"];
      NSExpression *arg = expression.arguments.firstObject;
      NSString *argString = (arg.expressionType == NSKeyPathExpressionType)
          ? arg.keyPath : [arg description];
      return [NSString stringWithFormat:@"%@:(%@)", name, argString];
    }
    default: return [expression description];
  }
}

- (void)fillInspector
{
  _updating = YES;
  NSEntityDescription *entity = [self selectedEntity];
  NSAttributeDescription *attr = [self selectedAttribute];
  NSRelationshipDescription *rel = [self selectedRelationship];
  NSFetchRequest *fetch = [self selectedTemplate];
  NSString *configuration = [self selectedConfigurationName];

  self.nameField.stringValue = @"";
  self.nameField.enabled = YES;

  switch (_kind) {
    case MBInspectEntity: {
      self.inspectorTitle.stringValue = @"Entity";
      [self showForm:_entityForm];
      self.nameField.stringValue = entity.name ?: @"";
      self.classField.stringValue = entity.managedObjectClassName ?: @"";
      self.abstractButton.state = entity.isAbstract ? NSOnState : NSOffState;
      [self rebuildParentPopup];
      NSString *parent = entity.superentity.name;
      if (parent.length && [self.parentPopup itemWithTitle:parent])
        [self.parentPopup selectItemWithTitle:parent];
      else
        [self.parentPopup selectItemAtIndex:0];
      break;
    }
    case MBInspectAttribute: {
      self.inspectorTitle.stringValue = @"Attribute";
      [self showForm:_attributeForm];
      self.nameField.stringValue = attr.name ?: @"";
      NSString *typeName = [CDModelCompiler nameForAttributeType:attr.attributeType];
      if (typeName.length && [self.typePopup itemWithTitle:typeName])
        [self.typePopup selectItemWithTitle:typeName];
      self.optionalButton.state = attr.isOptional ? NSOnState : NSOffState;
      self.transientButton.state = attr.isTransient ? NSOnState : NSOffState;
      self.defaultField.stringValue = attr.defaultValue
          ? [self stringForDefaultValue:attr.defaultValue type:attr.attributeType] : @"";
      self.derivationField.stringValue = @"";
      if ([attr isKindOfClass:[NSDerivedAttributeDescription class]]) {
        NSExpression *expr = [(NSDerivedAttributeDescription *)attr derivationExpression];
        if (expr) self.derivationField.stringValue = [self stringForDerivation:expr];
      }
      break;
    }
    case MBInspectRelationship: {
      self.inspectorTitle.stringValue = @"Relationship";
      [self showForm:_relationshipForm];
      self.nameField.stringValue = rel.name ?: @"";
      [self rebuildDestinationPopupInto:self.destinationPopup];
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
      self.toManyButton.state = rel.isToMany ? NSOnState : NSOffState;
      self.orderedButton.state = (rel.isToMany && rel.isOrdered) ? NSOnState : NSOffState;
      NSArray *ruleNames = [CDModelCompiler deleteRuleNames];
      NSUInteger ruleIndex;
      switch (rel.deleteRule) {
        case NSCascadeDeleteRule:  ruleIndex = 1; break;
        case NSDenyDeleteRule:     ruleIndex = 2; break;
        case NSNoActionDeleteRule: ruleIndex = 3; break;
        default:                   ruleIndex = 0; break;
      }
      [self.deleteRulePopup selectItemWithTitle:ruleNames[ruleIndex]];
      self.minField.stringValue = rel.minCount
          ? [NSString stringWithFormat:@"%ld", (long)rel.minCount] : @"";
      self.maxField.stringValue = (rel.isToMany && rel.maxCount)
          ? [NSString stringWithFormat:@"%ld", (long)rel.maxCount] : @"";
      break;
    }
    case MBInspectFetch: {
      self.inspectorTitle.stringValue = @"Fetch Request";
      [self showForm:_fetchForm];
      self.nameField.stringValue = [self selectedTemplateName] ?: @"";
      [self rebuildDestinationPopupInto:self.fetchEntityPopup];
      if (fetch.entity.name.length && [self.fetchEntityPopup itemWithTitle:fetch.entity.name])
        [self.fetchEntityPopup selectItemWithTitle:fetch.entity.name];
      self.predicateView.string = fetch.predicate ? [fetch.predicate predicateFormat] : @"";
      break;
    }
    case MBInspectConfiguration: {
      self.inspectorTitle.stringValue = @"Configuration";
      [self showForm:_configurationForm];
      self.nameField.stringValue = configuration ?: @"";
      break;
    }
    default: {
      self.inspectorTitle.stringValue = @"Inspector";
      [self showForm:_emptyForm];
      self.nameField.enabled = NO;
      break;
    }
  }
  [self.userInfoTable reloadData];
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
    case MBSourceEntity: [self removeEntityNamed:selected.name]; break;
    case MBSourceFetch:
      [self.model setFetchRequestTemplate:nil forName:selected.name];
      [self.modelDocument noteModelChanged];
      [self reloadEverything];
      break;
    case MBSourceConfiguration: {
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
  NSString *name = [self uniqueName:@"Entity"
                              among:[self.model.entities valueForKey:@"name"]];
  NSEntityDescription *entity = [[NSEntityDescription alloc] init];
  entity.name = name;
  entity.managedObjectClassName = @"NSManagedObject";
  self.model.entities = [self.model.entities arrayByAddingObject:entity];
  [self.modelDocument noteModelChanged];
  [self reloadEverything];
  [self selectSourceKind:MBSourceEntity name:name];
}

- (IBAction)addFetchRequest:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity]
      ?: [self.modelDocument sortedEntities].firstObject;
  if (!entity) return;
  NSString *name = [self uniqueName:@"FetchRequest"
                              among:[[self.model fetchRequestTemplatesByName] allKeys]];
  NSFetchRequest *request = [[NSFetchRequest alloc] init];
  request.entity = entity;
  [self.model setFetchRequestTemplate:request forName:name];
  [self.modelDocument noteModelChanged];
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

/* Entity deletion ripples through relationships, configurations, fetch
   templates and subentity wiring: XML surgery, renormalized by momc. */
- (void)removeEntityNamed:(NSString *)doomed
{
  [self.modelDocument.entityLayouts removeObjectForKey:doomed];
  NSError *error = nil;
  BOOL ok = [self.modelDocument performXMLMutation:^(NSXMLElement *root) {
    NSMutableArray *goners = [NSMutableArray array];
    for (NSXMLElement *el in [root elementsForName:@"entity"]) {
      NSString *name = [[el attributeForName:@"name"] stringValue];
      if ([name isEqualToString:doomed]) { [goners addObject:el]; continue; }
      if ([[[el attributeForName:@"parentEntity"] stringValue] isEqualToString:doomed])
        [el removeAttributeForName:@"parentEntity"];
      NSMutableArray *deadRels = [NSMutableArray array];
      for (NSXMLElement *rel in [el elementsForName:@"relationship"]) {
        if ([[[rel attributeForName:@"destinationEntity"] stringValue] isEqualToString:doomed])
          [deadRels addObject:rel];
        else if ([[[rel attributeForName:@"inverseEntity"] stringValue] isEqualToString:doomed]) {
          [rel removeAttributeForName:@"inverseName"];
          [rel removeAttributeForName:@"inverseEntity"];
        }
      }
      for (NSXMLElement *rel in deadRels)
        [el removeChildAtIndex:[[el children] indexOfObjectIdenticalTo:rel]];
    }
    for (NSXMLElement *el in [root elementsForName:@"configuration"]) {
      NSMutableArray *deadMembers = [NSMutableArray array];
      for (NSXMLElement *member in [el elementsForName:@"memberEntity"])
        if ([[[member attributeForName:@"name"] stringValue] isEqualToString:doomed])
          [deadMembers addObject:member];
      for (NSXMLElement *member in deadMembers)
        [el removeChildAtIndex:[[el children] indexOfObjectIdenticalTo:member]];
    }
    for (NSXMLElement *fetch in [root elementsForName:@"fetchRequest"])
      if ([[[fetch attributeForName:@"entity"] stringValue] isEqualToString:doomed])
        [goners addObject:fetch];
    for (NSXMLElement *wrap in [root elementsForName:@"elements"])
      for (NSXMLElement *el in [wrap elementsForName:@"element"])
        if ([[[el attributeForName:@"name"] stringValue] isEqualToString:doomed])
          [goners addObject:el];
    for (NSXMLElement *el in goners)
      [(NSXMLElement *)[el parent] removeChildAtIndex:
          [[[el parent] children] indexOfObjectIdenticalTo:el]];
  } error:&error];
  if (!ok) {
    [self presentModelError:error title:@"Cannot delete entity"];
    return;
  }
  [self reloadEverything];
}

#pragma mark - Property actions

- (void)replaceProperty:(NSPropertyDescription *)old
                   with:(NSPropertyDescription *)replacement
               ofEntity:(NSEntityDescription *)entity
{
  NSMutableArray *properties = [entity.properties mutableCopy];
  NSUInteger idx = [properties indexOfObjectIdenticalTo:old];
  if (idx == NSNotFound) return;
  if (replacement) [properties replaceObjectAtIndex:idx withObject:replacement];
  else [properties removeObjectAtIndex:idx];
  entity.properties = properties;
}

- (void)selectPropertyRow:(NSString *)name inTable:(NSTableView *)table names:(NSArray *)names
{
  NSUInteger idx = [names indexOfObject:name];
  if (idx != NSNotFound)
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
}

- (IBAction)addAttribute:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  if (!entity) return;
  NSString *name = [self uniqueName:@"attribute" among:entity.propertiesByName.allKeys];
  NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
  attribute.name = name;
  attribute.attributeType = NSStringAttributeType;
  attribute.optional = YES;
  entity.properties = [entity.properties arrayByAddingObject:attribute];
  [self.modelDocument noteModelChanged];
  [self rebuildPropertyRows];
  [self.attributeTable reloadData];
  [self.relationshipTable deselectAll:nil];
  [self selectPropertyRow:name inTable:self.attributeTable names:_attributeNames];
  [self refreshSelectionUI];
}

- (IBAction)removeAttribute:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  NSAttributeDescription *attribute = [self selectedAttribute];
  if (!entity || !attribute) return;
  [self replaceProperty:attribute with:nil ofEntity:entity];
  [self.modelDocument noteModelChanged];
  [self rebuildPropertyRows];
  [self.attributeTable reloadData];
  [self refreshSelectionUI];
}

- (IBAction)addRelationship:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  if (!entity) return;
  NSString *name = [self uniqueName:@"relationship" among:entity.propertiesByName.allKeys];
  NSRelationshipDescription *relationship = [[NSRelationshipDescription alloc] init];
  relationship.name = name;
  relationship.optional = YES;
  relationship.minCount = 0;
  relationship.maxCount = 1;
  relationship.deleteRule = NSNullifyDeleteRule;
  NSEntityDescription *destination = entity;
  for (NSEntityDescription *other in [self.modelDocument sortedEntities])
    if (other != entity) { destination = other; break; }
  relationship.destinationEntity = destination;
  entity.properties = [entity.properties arrayByAddingObject:relationship];
  [self.modelDocument noteModelChanged];
  [self rebuildPropertyRows];
  [self.relationshipTable reloadData];
  [self.attributeTable deselectAll:nil];
  [self selectPropertyRow:name inTable:self.relationshipTable names:_relationshipNames];
  [self refreshSelectionUI];
}

- (IBAction)removeRelationship:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  NSRelationshipDescription *relationship = [self selectedRelationship];
  if (!entity || !relationship) return;
  NSRelationshipDescription *inverse = relationship.inverseRelationship;
  if (inverse.inverseRelationship == relationship)
    inverse.inverseRelationship = nil;
  [self replaceProperty:relationship with:nil ofEntity:entity];
  [self.modelDocument noteModelChanged];
  [self rebuildPropertyRows];
  [self.relationshipTable reloadData];
  [self refreshSelectionUI];
}

- (IBAction)addUserInfo:(id)sender
{
  (void)sender;
  if (_kind != MBInspectEntity && _kind != MBInspectAttribute && _kind != MBInspectRelationship)
    return;
  NSMutableDictionary *info = [([self currentUserInfo] ?: @{}) mutableCopy];
  NSString *key = [self uniqueName:@"key" among:info.allKeys];
  info[key] = @"";
  [self setCurrentUserInfo:info];
  [self.userInfoTable reloadData];
  [self.modelDocument noteModelChanged];
}

- (IBAction)removeUserInfo:(id)sender
{
  (void)sender;
  NSInteger row = self.userInfoTable.selectedRow;
  if (row < 0 || (NSUInteger)row >= _userInfoKeys.count) return;
  NSMutableDictionary *info = [([self currentUserInfo] ?: @{}) mutableCopy];
  [info removeObjectForKey:_userInfoKeys[(NSUInteger)row]];
  [self setCurrentUserInfo:info.count ? info : nil];
  [self.userInfoTable reloadData];
  [self.modelDocument noteModelChanged];
}

#pragma mark - Inspector writes

- (void)applyDerivationString:(NSString *)string toAttribute:(NSAttributeDescription *)attribute
                     ofEntity:(NSEntityDescription *)entity
{
  BOOL isDerived = [attribute isKindOfClass:[NSDerivedAttributeDescription class]];
  if (!string.length) {
    if (!isDerived) return;
    NSAttributeDescription *plain = [[NSAttributeDescription alloc] init];
    plain.name = attribute.name;
    plain.attributeType = attribute.attributeType;
    plain.optional = attribute.isOptional;
    plain.transient = attribute.isTransient;
    plain.defaultValue = attribute.defaultValue;
    plain.userInfo = attribute.userInfo;
    [self replaceProperty:attribute with:plain ofEntity:entity];
    return;
  }
  NSError *error = nil;
  NSExpression *expression = [CDModelCompiler derivationExpressionFromString:string error:&error];
  if (!expression) {
    [self presentModelError:error title:@"Invalid derivation expression"];
    return;
  }
  if (isDerived) {
    [(NSDerivedAttributeDescription *)attribute setDerivationExpression:expression];
    return;
  }
  NSDerivedAttributeDescription *derived = [[NSDerivedAttributeDescription alloc] init];
  derived.name = attribute.name;
  derived.attributeType = attribute.attributeType;
  derived.optional = attribute.isOptional;
  derived.transient = attribute.isTransient;
  derived.userInfo = attribute.userInfo;
  derived.derivationExpression = expression;
  [self replaceProperty:attribute with:derived ofEntity:entity];
}

- (void)applyDefaultString:(NSString *)string toAttribute:(NSAttributeDescription *)attribute
{
  if (!string.length) {
    attribute.defaultValue = nil;
    return;
  }
  switch (attribute.attributeType) {
    case NSStringAttributeType: attribute.defaultValue = string; break;
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
      attribute.defaultValue = @([string longLongValue]); break;
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
      attribute.defaultValue = @([string doubleValue]); break;
    case NSDecimalAttributeType:
      attribute.defaultValue = [NSDecimalNumber decimalNumberWithString:string]; break;
    case NSBooleanAttributeType:
      attribute.defaultValue = @([string isEqualToString:@"YES"] || [string isEqualToString:@"1"]);
      break;
    case NSDateAttributeType:
      attribute.defaultValue =
          [NSDate dateWithTimeIntervalSinceReferenceDate:[string doubleValue]];
      break;
    case NSUUIDAttributeType:
      attribute.defaultValue = [[NSUUID alloc] initWithUUIDString:string]; break;
    case NSURIAttributeType:
      attribute.defaultValue = [NSURL URLWithString:string]; break;
    default: break;
  }
}

- (void)renameEntity:(NSEntityDescription *)entity to:(NSString *)newName
{
  if ([entity.name isEqualToString:newName]) return;
  if ([[self.model.entities valueForKey:@"name"] containsObject:newName]) return;
  NSMutableDictionary *layouts = self.modelDocument.entityLayouts;
  if (layouts[entity.name]) {
    layouts[newName] = layouts[entity.name];
    [layouts removeObjectForKey:entity.name];
  }
  entity.name = newName;
}

- (void)setParentOfEntityNamed:(NSString *)entityName to:(NSString *)parentName
{
  NSError *error = nil;
  BOOL ok = [self.modelDocument performXMLMutation:^(NSXMLElement *root) {
    for (NSXMLElement *el in [root elementsForName:@"entity"]) {
      if (![[[el attributeForName:@"name"] stringValue] isEqualToString:entityName])
        continue;
      [el removeAttributeForName:@"parentEntity"];
      if (parentName.length)
        [el addAttribute:[NSXMLNode attributeWithName:@"parentEntity"
                                          stringValue:parentName]];
    }
  } error:&error];
  if (!ok)
    [self presentModelError:error title:@"Cannot change parent entity"];
  [self reloadEverything];
  [self selectSourceKind:MBSourceEntity name:entityName];
}

- (IBAction)inspectorChanged:(id)sender
{
  (void)sender;
  if (_updating) return;
  NSEntityDescription *entity = [self selectedEntity];
  NSAttributeDescription *attr = [self selectedAttribute];
  NSRelationshipDescription *rel = [self selectedRelationship];
  NSString *templateName = [self selectedTemplateName];
  NSString *configuration = [self selectedConfigurationName];

  if (_kind == MBInspectEntity && entity) {
    NSString *newName = self.nameField.stringValue;
    if (newName.length) [self renameEntity:entity to:newName];
    entity.managedObjectClassName = self.classField.stringValue.length
        ? self.classField.stringValue : @"NSManagedObject";
    entity.abstract = (self.abstractButton.state == NSOnState);

    NSString *parent = self.parentPopup.titleOfSelectedItem;
    NSString *wantedParent = ([parent isEqualToString:@"(none)"] || !parent.length) ? @"" : parent;
    NSString *haveParent = entity.superentity.name ?: @"";
    if (![wantedParent isEqualToString:haveParent]) {
      [self.modelDocument noteModelChanged];
      [self setParentOfEntityNamed:entity.name to:wantedParent];
      return;
    }
    [self rebuildSourceItems];
    [self.sourceList reloadData];
    [self selectSourceKind:MBSourceEntity name:entity.name];
  } else if (_kind == MBInspectAttribute && attr && entity) {
    if (self.nameField.stringValue.length &&
        !entity.propertiesByName[self.nameField.stringValue])
      attr.name = self.nameField.stringValue;
    NSInteger type = [CDModelCompiler attributeTypeNamed:self.typePopup.titleOfSelectedItem];
    if (type >= 0) attr.attributeType = (NSAttributeType)type;
    attr.optional = (self.optionalButton.state == NSOnState);
    attr.transient = (self.transientButton.state == NSOnState);
    [self applyDefaultString:self.defaultField.stringValue toAttribute:attr];
    [self applyDerivationString:self.derivationField.stringValue
                    toAttribute:attr
                       ofEntity:entity];
    [self rebuildPropertyRows];
    [self.attributeTable reloadData];
  } else if (_kind == MBInspectRelationship && rel && entity) {
    if (self.nameField.stringValue.length &&
        !entity.propertiesByName[self.nameField.stringValue])
      rel.name = self.nameField.stringValue;
    BOOL toMany = (self.toManyButton.state == NSOnState);
    rel.optional = YES; /* min/max drive optionality in the XML */
    if (toMany) {
      rel.minCount = self.minField.stringValue.integerValue;
      rel.maxCount = self.maxField.stringValue.integerValue;
      rel.ordered = (self.orderedButton.state == NSOnState);
      if (!rel.isToMany) rel.maxCount = rel.maxCount ?: 0;
      if (rel.maxCount == 1) rel.maxCount = 0;
    } else {
      rel.minCount = 0;
      rel.maxCount = 1;
      rel.ordered = NO;
    }
    NSString *dest = self.destinationPopup.titleOfSelectedItem;
    if ([dest isEqualToString:@"(none)"] || !dest.length)
      rel.destinationEntity = nil;
    else
      rel.destinationEntity = self.model.entitiesByName[dest];
    NSString *inverseName = self.inversePopup.titleOfSelectedItem;
    NSRelationshipDescription *previousInverse = rel.inverseRelationship;
    if ([inverseName isEqualToString:@"(none)"] || !inverseName.length) {
      if (previousInverse.inverseRelationship == rel)
        previousInverse.inverseRelationship = nil;
      rel.inverseRelationship = nil;
    } else {
      NSRelationshipDescription *inverse =
          rel.destinationEntity.relationshipsByName[inverseName];
      if (inverse && inverse != previousInverse) {
        if (previousInverse.inverseRelationship == rel)
          previousInverse.inverseRelationship = nil;
        rel.inverseRelationship = inverse;
        inverse.inverseRelationship = rel;
      }
    }
    NSArray *ruleNames = [CDModelCompiler deleteRuleNames];
    NSUInteger ruleIndex = [ruleNames indexOfObject:self.deleteRulePopup.titleOfSelectedItem];
    switch (ruleIndex) {
      case 1: rel.deleteRule = NSCascadeDeleteRule; break;
      case 2: rel.deleteRule = NSDenyDeleteRule; break;
      case 3: rel.deleteRule = NSNoActionDeleteRule; break;
      default: rel.deleteRule = NSNullifyDeleteRule; break;
    }
    [self rebuildPropertyRows];
    [self.relationshipTable reloadData];
  } else if (_kind == MBInspectFetch && templateName) {
    NSFetchRequest *request = [self selectedTemplate];
    NSString *newName = self.nameField.stringValue;
    if (newName.length && ![newName isEqualToString:templateName] &&
        ![self.model fetchRequestTemplateForName:newName]) {
      [self.model setFetchRequestTemplate:nil forName:templateName];
      [self.model setFetchRequestTemplate:request forName:newName];
      [self rebuildSourceItems];
      [self.sourceList reloadData];
      [self selectSourceKind:MBSourceFetch name:newName];
    }
    NSString *entityName = self.fetchEntityPopup.titleOfSelectedItem;
    if (entityName.length && ![entityName isEqualToString:@"(none)"] &&
        self.model.entitiesByName[entityName])
      request.entity = self.model.entitiesByName[entityName];
    NSString *predicateString = self.predicateView.string;
    if (predicateString.length) {
      @try {
        request.predicate = [NSPredicate predicateWithFormat:predicateString];
      } @catch (NSException *exception) {
        /* keep the old predicate; the text stays visible for fixing */
      }
    } else {
      request.predicate = nil;
    }
  } else if (_kind == MBInspectConfiguration && configuration) {
    NSString *newName = self.nameField.stringValue;
    if (newName.length && ![newName isEqualToString:configuration]) {
      NSError *error = nil;
      if (![self.modelDocument renameConfiguration:configuration to:newName error:&error])
        [self presentModelError:error title:@"Cannot rename configuration"];
      [self reloadEverything];
      [self selectSourceKind:MBSourceConfiguration name:newName];
      return;
    }
  }
  [self.modelDocument noteModelChanged];
  [self updateStatus];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
  (void)notification;
  [self inspectorChanged:nil];
}

- (void)textDidEndEditing:(NSNotification *)notification
{
  (void)notification;
  [self inspectorChanged:nil];
}

#pragma mark - Version bar actions

- (IBAction)versionSelected:(id)sender
{
  (void)sender;
  NSString *name = [[self.versionPopup selectedItem] representedObject];
  if (!name.length) return;
  NSError *error = nil;
  if (![self.modelDocument switchToVersion:name error:&error]) {
    [self presentModelError:error title:@"Cannot switch versions"];
    [self updateVersionBar];
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
  [self updateStatus];
  [self updateVersionBar];
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

#pragma mark - Source list data source / delegate

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item
{
  (void)outline;
  if (item == nil) return 3;
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
  (void)outline; (void)column;
  return [item isKindOfClass:[MBSourceItem class]] ? [item name] : @"";
}

- (void)outlineView:(NSOutlineView *)outline setObjectValue:(id)value forTableColumn:(NSTableColumn *)column byItem:(id)item
{
  (void)outline; (void)column;
  if (![item isKindOfClass:[MBSourceItem class]] || [item isGroup]) return;
  NSString *text = [value description];
  if (!text.length) return;
  MBSourceItem *source = item;
  if (source.kind == MBSourceEntity) {
    NSEntityDescription *entity = self.model.entitiesByName[source.name];
    if (entity) [self renameEntity:entity to:text];
  } else if (source.kind == MBSourceFetch) {
    NSFetchRequest *request = [self.model fetchRequestTemplateForName:source.name];
    if (request && ![self.model fetchRequestTemplateForName:text]) {
      [self.model setFetchRequestTemplate:nil forName:source.name];
      [self.model setFetchRequestTemplate:request forName:text];
    }
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
  (void)outline; (void)column;
  return [item isKindOfClass:[MBSourceItem class]] && ![item isGroup];
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
  if (table == self.userInfoTable) return (NSInteger)_userInfoKeys.count;
  if (table == self.memberTable) return (NSInteger)_memberEntityNames.count;
  return 0;
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *ident = column.identifier ?: @"";
  NSEntityDescription *entity = [self selectedEntity];

  if (table == self.attributeTable && entity && row >= 0 &&
      (NSUInteger)row < _attributeNames.count) {
    NSAttributeDescription *attr = entity.attributesByName[_attributeNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"type"])
      return [CDModelCompiler nameForAttributeType:attr.attributeType] ?: @"";
    if ([ident isEqualToString:@"optional"]) return @(attr.isOptional);
    return attr.name ?: @"";
  }
  if (table == self.relationshipTable && entity && row >= 0 &&
      (NSUInteger)row < _relationshipNames.count) {
    NSRelationshipDescription *rel = entity.relationshipsByName[_relationshipNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"destination"]) return rel.destinationEntity.name ?: @"";
    if ([ident isEqualToString:@"toMany"]) {
      if (!rel.isToMany) return @"to-one";
      return rel.isOrdered ? @"ordered" : @"to-many";
    }
    return rel.name ?: @"";
  }
  if (table == self.userInfoTable && row >= 0 && (NSUInteger)row < _userInfoKeys.count) {
    NSString *key = _userInfoKeys[(NSUInteger)row];
    if ([ident isEqualToString:@"value"])
      return [[self currentUserInfo][key] description] ?: @"";
    return key;
  }
  if (table == self.memberTable && row >= 0 && (NSUInteger)row < _memberEntityNames.count) {
    NSString *name = _memberEntityNames[(NSUInteger)row];
    if ([ident isEqualToString:@"member"]) {
      NSString *configuration = [self selectedConfigurationName];
      if (!configuration) return @NO;
      NSArray *members = [self.model entitiesForConfiguration:configuration];
      for (NSEntityDescription *member in members)
        if ([member.name isEqualToString:name]) return @YES;
      return @NO;
    }
    return name;
  }
  return @"";
}

- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *ident = column.identifier;
  NSEntityDescription *entity = [self selectedEntity];

  if (table == self.userInfoTable) {
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
    [self.userInfoTable reloadData];
    [self.modelDocument noteModelChanged];
    return;
  }
  if (table == self.attributeTable && entity && (NSUInteger)row < _attributeNames.count) {
    NSAttributeDescription *attr = entity.attributesByName[_attributeNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"optional"]) {
      attr.optional = [value boolValue];
    } else if ([ident isEqualToString:@"name"]) {
      NSString *text = [value description];
      if (text.length && !entity.propertiesByName[text]) attr.name = text;
    }
    [self rebuildPropertyRows];
    [self.attributeTable reloadData];
    [self fillInspector];
    [self.modelDocument noteModelChanged];
    return;
  }
  if (table == self.relationshipTable && entity && (NSUInteger)row < _relationshipNames.count) {
    NSRelationshipDescription *rel = entity.relationshipsByName[_relationshipNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"name"]) {
      NSString *text = [value description];
      if (text.length && !entity.propertiesByName[text]) rel.name = text;
    }
    [self rebuildPropertyRows];
    [self.relationshipTable reloadData];
    [self fillInspector];
    [self.modelDocument noteModelChanged];
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
    [self updateStatus];
  }
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
  } else if (table == self.userInfoTable || table == self.memberTable) {
    return;
  }
  [self refreshSelectionUI];
}

#pragma mark - Split view delegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  if (splitView != _split) return proposed;
  return dividerIndex == 0 ? 150.0 : NSWidth(splitView.bounds) - 420.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  if (splitView != _split) return proposed;
  return dividerIndex == 0 ? 320.0 : NSWidth(splitView.bounds) - 220.0;
}

/* Window resizes stretch only the center pane. */
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
  (void)oldSize;
  if (splitView != _split || splitView.subviews.count != 3) {
    [splitView adjustSubviews];
    return;
  }
  NSArray *subviews = splitView.subviews;
  CGFloat divider = splitView.dividerThickness;
  NSRect bounds = splitView.bounds;
  NSView *left = subviews[0], *center = subviews[1], *right = subviews[2];

  CGFloat leftWidth = MIN(_leftWidth, bounds.size.width / 3.0);
  CGFloat rightWidth = MIN(_rightWidth, bounds.size.width / 3.0);
  CGFloat centerWidth = bounds.size.width - leftWidth - rightWidth - 2.0 * divider;

  left.frame = NSMakeRect(0, 0, leftWidth, bounds.size.height);
  center.frame = NSMakeRect(leftWidth + divider, 0, centerWidth, bounds.size.height);
  right.frame = NSMakeRect(leftWidth + divider + centerWidth + divider, 0,
                           rightWidth, bounds.size.height);
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
  if (notification.object != _split || _split.subviews.count != 3) return;
  _leftWidth = NSWidth([_split.subviews[0] frame]);
  _rightWidth = NSWidth([_split.subviews[2] frame]);
}

@end
