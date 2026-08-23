/* ModelBuilder three-pane editor.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBWindowController.h"
#import "MBDocument.h"

typedef NS_ENUM(NSInteger, MBInspectKind) {
  MBInspectNone = 0,
  MBInspectEntity,
  MBInspectAttribute,
  MBInspectRelationship,
  MBInspectFetch
};

@implementation MBWindowController {
  MBInspectKind _kind;
  BOOL _updating;
}

- (MBDocument *)modelDocument
{
  return (MBDocument *)self.document;
}

- (MBModel *)model
{
  return self.modelDocument.model;
}

- (void)windowDidLoad
{
  [super windowDidLoad];
  self.entityTable.dataSource = self;
  self.entityTable.delegate = self;
  self.fetchTable.dataSource = self;
  self.fetchTable.delegate = self;
  self.attributeTable.dataSource = self;
  self.attributeTable.delegate = self;
  self.relationshipTable.dataSource = self;
  self.relationshipTable.delegate = self;
  self.userInfoTable.dataSource = self;
  self.userInfoTable.delegate = self;
  self.predicateView.delegate = self;

  [self.typePopup removeAllItems];
  [self.typePopup addItemsWithTitles:[MBModel attributeTypeNames]];
  [self.deleteRulePopup removeAllItems];
  [self.deleteRulePopup addItemsWithTitles:[MBModel deletionRuleNames]];

  [self reloadAll];
  if (self.model.entities.count)
    [self.entityTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  [self inspectEntity];
}

- (void)reloadAll
{
  [self.entityTable reloadData];
  [self.fetchTable reloadData];
  [self.attributeTable reloadData];
  [self.relationshipTable reloadData];
  [self.userInfoTable reloadData];
  [self updateStatus];
}

- (void)noteChanged
{
  [self.modelDocument noteModelChanged];
  [self updateStatus];
}

- (void)updateStatus
{
  MBModel *model = self.model;
  self.statusField.stringValue = [NSString stringWithFormat:@"%@  —  %lu entities, %lu fetch requests",
                                  model.versionName ?: @"untitled",
                                  (unsigned long)model.entities.count,
                                  (unsigned long)model.fetchRequests.count];
}

#pragma mark - Selection

- (MBEntity *)selectedEntity
{
  NSInteger row = self.entityTable.selectedRow;
  if (row < 0 || (NSUInteger)row >= self.model.entities.count) return nil;
  return self.model.entities[(NSUInteger)row];
}

- (MBFetchRequest *)selectedFetch
{
  NSInteger row = self.fetchTable.selectedRow;
  if (row < 0 || (NSUInteger)row >= self.model.fetchRequests.count) return nil;
  return self.model.fetchRequests[(NSUInteger)row];
}

- (MBAttribute *)selectedAttribute
{
  MBEntity *entity = [self selectedEntity];
  NSInteger row = self.attributeTable.selectedRow;
  if (!entity || row < 0 || (NSUInteger)row >= entity.attributes.count) return nil;
  return entity.attributes[(NSUInteger)row];
}

- (MBRelationship *)selectedRelationship
{
  MBEntity *entity = [self selectedEntity];
  NSInteger row = self.relationshipTable.selectedRow;
  if (!entity || row < 0 || (NSUInteger)row >= entity.relationships.count) return nil;
  return entity.relationships[(NSUInteger)row];
}

- (NSMutableArray<MBUserInfo *> *)currentUserInfo
{
  if (_kind == MBInspectEntity) return [self selectedEntity].userInfo;
  if (_kind == MBInspectAttribute) return [self selectedAttribute].userInfo;
  if (_kind == MBInspectRelationship) return [self selectedRelationship].userInfo;
  return nil;
}

- (void)showEntityPane:(BOOL)entityNotFetch
{
  self.entityPane.hidden = !entityNotFetch;
  self.fetchPane.hidden = entityNotFetch;
}

- (void)inspectNone
{
  _kind = MBInspectNone;
  self.inspectorTitle.stringValue = @"Inspector";
  [self showEntityPane:YES];
  [self fillInspector];
}

- (void)inspectEntity
{
  _kind = MBInspectEntity;
  [self showEntityPane:YES];
  [self.attributeTable deselectAll:nil];
  [self.relationshipTable deselectAll:nil];
  self.inspectorTitle.stringValue = @"Entity";
  [self fillInspector];
}

- (void)inspectAttribute
{
  _kind = MBInspectAttribute;
  [self showEntityPane:YES];
  [self.relationshipTable deselectAll:nil];
  self.inspectorTitle.stringValue = @"Attribute";
  [self fillInspector];
}

- (void)inspectRelationship
{
  _kind = MBInspectRelationship;
  [self showEntityPane:YES];
  [self.attributeTable deselectAll:nil];
  self.inspectorTitle.stringValue = @"Relationship";
  [self fillInspector];
}

- (void)inspectFetch
{
  _kind = MBInspectFetch;
  [self showEntityPane:NO];
  self.inspectorTitle.stringValue = @"Fetch Request";
  [self fillInspector];
}

- (void)rebuildParentPopup
{
  [self.parentPopup removeAllItems];
  [self.parentPopup addItemWithTitle:@"(none)"];
  MBEntity *current = [self selectedEntity];
  for (MBEntity *entity in self.model.entities) {
    if (entity == current) continue;
    [self.parentPopup addItemWithTitle:entity.name ?: @""];
  }
}

- (void)rebuildDestinationPopup
{
  [self.destinationPopup removeAllItems];
  [self.destinationPopup addItemWithTitle:@"(none)"];
  for (MBEntity *entity in self.model.entities)
    [self.destinationPopup addItemWithTitle:entity.name ?: @""];
}

- (void)rebuildInversePopup
{
  [self.inversePopup removeAllItems];
  [self.inversePopup addItemWithTitle:@"(none)"];
  MBRelationship *rel = [self selectedRelationship];
  MBEntity *dest = rel.destinationEntity.length ? [self.model entityNamed:rel.destinationEntity] : nil;
  if (!dest) return;
  for (MBRelationship *other in dest.relationships)
    [self.inversePopup addItemWithTitle:other.name ?: @""];
}

- (void)fillInspector
{
  _updating = YES;
  MBEntity *entity = [self selectedEntity];
  MBAttribute *attr = [self selectedAttribute];
  MBRelationship *rel = [self selectedRelationship];
  MBFetchRequest *fetch = [self selectedFetch];

  [self rebuildParentPopup];
  [self rebuildDestinationPopup];
  [self rebuildInversePopup];

  self.nameField.stringValue = @"";
  self.classField.stringValue = @"";
  self.defaultField.stringValue = @"";
  self.minField.stringValue = @"";
  self.maxField.stringValue = @"";
  self.abstractButton.state = NSOffState;
  self.optionalButton.state = NSOffState;
  self.transientButton.state = NSOffState;
  self.toManyButton.state = NSOffState;
  if (self.orderedButton) self.orderedButton.state = NSOffState;
  self.predicateView.string = @"";

  if (_kind == MBInspectEntity && entity) {
    self.nameField.stringValue = entity.name ?: @"";
    self.classField.stringValue = entity.representedClassName ?: @"";
    self.abstractButton.state = entity.isAbstract ? NSOnState : NSOffState;
    if (entity.parentEntity.length && [self.parentPopup itemWithTitle:entity.parentEntity])
      [self.parentPopup selectItemWithTitle:entity.parentEntity];
    else
      [self.parentPopup selectItemAtIndex:0];
  } else if (_kind == MBInspectAttribute && attr) {
    self.nameField.stringValue = attr.name ?: @"";
    if (attr.attributeType.length && [self.typePopup itemWithTitle:attr.attributeType])
      [self.typePopup selectItemWithTitle:attr.attributeType];
    self.optionalButton.state = attr.optional ? NSOnState : NSOffState;
    self.transientButton.state = attr.transient ? NSOnState : NSOffState;
    self.defaultField.stringValue = attr.defaultValueString ?: @"";
    self.minField.stringValue = attr.minValueString ?: @"";
    self.maxField.stringValue = attr.maxValueString ?: @"";
  } else if (_kind == MBInspectRelationship && rel) {
    self.nameField.stringValue = rel.name ?: @"";
    self.optionalButton.state = rel.optional ? NSOnState : NSOffState;
    self.toManyButton.state = rel.toMany ? NSOnState : NSOffState;
    if (self.orderedButton) self.orderedButton.state = (rel.toMany && rel.ordered) ? NSOnState : NSOffState;
    if (rel.destinationEntity.length && [self.destinationPopup itemWithTitle:rel.destinationEntity])
      [self.destinationPopup selectItemWithTitle:rel.destinationEntity];
    else
      [self.destinationPopup selectItemAtIndex:0];
    if (rel.inverseName.length && [self.inversePopup itemWithTitle:rel.inverseName])
      [self.inversePopup selectItemWithTitle:rel.inverseName];
    else
      [self.inversePopup selectItemAtIndex:0];
    if (rel.deletionRule.length && [self.deleteRulePopup itemWithTitle:rel.deletionRule])
      [self.deleteRulePopup selectItemWithTitle:rel.deletionRule];
    self.minField.stringValue = rel.minCount ? [NSString stringWithFormat:@"%lu", (unsigned long)rel.minCount] : @"";
    self.maxField.stringValue = (rel.toMany && rel.maxCount) ? [NSString stringWithFormat:@"%lu", (unsigned long)rel.maxCount] : @"";
  } else if (_kind == MBInspectFetch && fetch) {
    self.nameField.stringValue = fetch.name ?: @"";
    self.predicateView.string = fetch.predicateString ?: @"";
    [self rebuildDestinationPopup];
    if (fetch.entityName.length && [self.destinationPopup itemWithTitle:fetch.entityName])
      [self.destinationPopup selectItemWithTitle:fetch.entityName];
  }
  [self.userInfoTable reloadData];
  _updating = NO;
}

#pragma mark - Actions

- (IBAction)addEntity:(id)sender
{
  (void)sender;
  MBEntity *entity = [self.model addEntityNamed:nil];
  [self.entityTable reloadData];
  NSUInteger idx = [self.model.entities indexOfObject:entity];
  [self.entityTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
  [self.fetchTable deselectAll:nil];
  [self inspectEntity];
  [self.attributeTable reloadData];
  [self.relationshipTable reloadData];
  [self noteChanged];
}

- (IBAction)removeEntity:(id)sender
{
  (void)sender;
  MBEntity *entity = [self selectedEntity];
  if (!entity) return;
  [self.model removeEntity:entity];
  [self reloadAll];
  [self inspectNone];
  [self noteChanged];
}

- (IBAction)addFetchRequest:(id)sender
{
  (void)sender;
  MBEntity *entity = [self selectedEntity] ?: self.model.entities.firstObject;
  MBFetchRequest *req = [self.model addFetchRequestNamed:nil entityName:entity.name];
  [self.fetchTable reloadData];
  NSUInteger idx = [self.model.fetchRequests indexOfObject:req];
  [self.fetchTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
  [self.entityTable deselectAll:nil];
  [self inspectFetch];
  [self noteChanged];
}

- (IBAction)removeFetchRequest:(id)sender
{
  (void)sender;
  MBFetchRequest *req = [self selectedFetch];
  if (!req) return;
  [self.model removeFetchRequest:req];
  [self.fetchTable reloadData];
  [self inspectNone];
  [self noteChanged];
}

- (IBAction)addAttribute:(id)sender
{
  (void)sender;
  MBEntity *entity = [self selectedEntity];
  if (!entity) return;
  NSMutableArray *names = [NSMutableArray array];
  for (MBAttribute *a in entity.attributes) if (a.name) [names addObject:a.name];
  MBAttribute *attr = [[MBAttribute alloc] init];
  attr.name = [self.model uniqueName:@"attribute" among:names];
  [entity.attributes addObject:attr];
  [self.attributeTable reloadData];
  NSUInteger idx = [entity.attributes indexOfObject:attr];
  [self.attributeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
  [self inspectAttribute];
  [self noteChanged];
}

- (IBAction)removeAttribute:(id)sender
{
  (void)sender;
  MBEntity *entity = [self selectedEntity];
  MBAttribute *attr = [self selectedAttribute];
  if (!entity || !attr) return;
  [entity.attributes removeObject:attr];
  [self.attributeTable reloadData];
  [self inspectEntity];
  [self noteChanged];
}

- (IBAction)addRelationship:(id)sender
{
  (void)sender;
  MBEntity *entity = [self selectedEntity];
  if (!entity) return;
  NSMutableArray *names = [NSMutableArray array];
  for (MBRelationship *r in entity.relationships) if (r.name) [names addObject:r.name];
  MBRelationship *rel = [[MBRelationship alloc] init];
  rel.name = [self.model uniqueName:@"relationship" among:names];
  MBEntity *other = nil;
  for (MBEntity *e in self.model.entities) { if (e != entity) { other = e; break; } }
  rel.destinationEntity = (other ?: entity).name;
  [entity.relationships addObject:rel];
  [self.relationshipTable reloadData];
  NSUInteger idx = [entity.relationships indexOfObject:rel];
  [self.relationshipTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
  [self inspectRelationship];
  [self noteChanged];
}

- (IBAction)removeRelationship:(id)sender
{
  (void)sender;
  MBEntity *entity = [self selectedEntity];
  MBRelationship *rel = [self selectedRelationship];
  if (!entity || !rel) return;
  [entity.relationships removeObject:rel];
  [self.relationshipTable reloadData];
  [self inspectEntity];
  [self noteChanged];
}

- (IBAction)addUserInfo:(id)sender
{
  (void)sender;
  NSMutableArray *rows = [self currentUserInfo];
  if (!rows) return;
  [rows addObject:[MBUserInfo entryWithKey:@"key" value:@""]];
  [self.userInfoTable reloadData];
  [self noteChanged];
}

- (IBAction)removeUserInfo:(id)sender
{
  (void)sender;
  NSMutableArray *rows = [self currentUserInfo];
  NSInteger row = self.userInfoTable.selectedRow;
  if (!rows || row < 0 || (NSUInteger)row >= rows.count) return;
  [rows removeObjectAtIndex:(NSUInteger)row];
  [self.userInfoTable reloadData];
  [self noteChanged];
}

- (IBAction)inspectorChanged:(id)sender
{
  (void)sender;
  if (_updating) return;
  MBEntity *entity = [self selectedEntity];
  MBAttribute *attr = [self selectedAttribute];
  MBRelationship *rel = [self selectedRelationship];
  MBFetchRequest *fetch = [self selectedFetch];

  if (_kind == MBInspectEntity && entity) {
    NSString *newName = self.nameField.stringValue;
    if (newName.length && ![newName isEqualToString:entity.name])
      [self.model renameEntity:entity to:newName];
    entity.representedClassName = self.classField.stringValue;
    entity.isAbstract = (self.abstractButton.state == NSOnState);
    NSString *parent = self.parentPopup.titleOfSelectedItem;
    entity.parentEntity = ([parent isEqualToString:@"(none)"] || !parent.length) ? nil : parent;
    [self.entityTable reloadData];
  } else if (_kind == MBInspectAttribute && attr) {
    attr.name = self.nameField.stringValue.length ? self.nameField.stringValue : attr.name;
    attr.attributeType = self.typePopup.titleOfSelectedItem;
    attr.optional = (self.optionalButton.state == NSOnState);
    attr.transient = (self.transientButton.state == NSOnState);
    attr.defaultValueString = self.defaultField.stringValue;
    attr.minValueString = self.minField.stringValue;
    attr.maxValueString = self.maxField.stringValue;
    [self.attributeTable reloadData];
  } else if (_kind == MBInspectRelationship && rel) {
    rel.name = self.nameField.stringValue.length ? self.nameField.stringValue : rel.name;
    rel.optional = (self.optionalButton.state == NSOnState);
    rel.toMany = (self.toManyButton.state == NSOnState);
    if (!rel.toMany) {
      rel.maxCount = 1;
      rel.ordered = NO;
    } else if (self.orderedButton) {
      rel.ordered = (self.orderedButton.state == NSOnState);
    }
    NSString *dest = self.destinationPopup.titleOfSelectedItem;
    rel.destinationEntity = ([dest isEqualToString:@"(none)"] || !dest.length) ? nil : dest;
    NSString *inv = self.inversePopup.titleOfSelectedItem;
    if ([inv isEqualToString:@"(none)"] || !inv.length) {
      rel.inverseName = nil;
      rel.inverseEntity = nil;
    } else {
      rel.inverseName = inv;
      rel.inverseEntity = rel.destinationEntity;
    }
    rel.deletionRule = self.deleteRulePopup.titleOfSelectedItem;
    rel.minCount = (NSUInteger)self.minField.stringValue.integerValue;
    if (rel.toMany) rel.maxCount = (NSUInteger)self.maxField.stringValue.integerValue;
    [self.relationshipTable reloadData];
  } else if (_kind == MBInspectFetch && fetch) {
    fetch.name = self.nameField.stringValue.length ? self.nameField.stringValue : fetch.name;
    NSString *ent = self.destinationPopup.titleOfSelectedItem;
    if (ent.length && ![ent isEqualToString:@"(none)"]) fetch.entityName = ent;
    fetch.predicateString = self.predicateView.string;
    [self.fetchTable reloadData];
  }
  [self noteChanged];
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

#pragma mark - Tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if (table == self.entityTable) return (NSInteger)self.model.entities.count;
  if (table == self.fetchTable) return (NSInteger)self.model.fetchRequests.count;
  if (table == self.attributeTable) return (NSInteger)[self selectedEntity].attributes.count;
  if (table == self.relationshipTable) return (NSInteger)[self selectedEntity].relationships.count;
  if (table == self.userInfoTable) return (NSInteger)[self currentUserInfo].count;
  return 0;
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *ident = column.identifier;
  if (table == self.entityTable) {
    if (row < 0 || (NSUInteger)row >= self.model.entities.count) return nil;
    MBEntity *entity = self.model.entities[(NSUInteger)row];
    if ([ident isEqualToString:@"class"]) return entity.representedClassName ?: @"";
    return entity.name;
  }
  if (table == self.fetchTable) {
    if (row < 0 || (NSUInteger)row >= self.model.fetchRequests.count) return nil;
    MBFetchRequest *req = self.model.fetchRequests[(NSUInteger)row];
    if ([ident isEqualToString:@"entity"]) return req.entityName ?: @"";
    return req.name;
  }
  MBEntity *entity = [self selectedEntity];
  if (table == self.attributeTable && entity && (NSUInteger)row < entity.attributes.count) {
    MBAttribute *attr = entity.attributes[(NSUInteger)row];
    if ([ident isEqualToString:@"type"]) return attr.attributeType;
    if ([ident isEqualToString:@"optional"]) return attr.optional ? @"○" : @"●";
    return attr.name;
  }
  if (table == self.relationshipTable && entity && (NSUInteger)row < entity.relationships.count) {
    MBRelationship *rel = entity.relationships[(NSUInteger)row];
    if ([ident isEqualToString:@"destination"]) return rel.destinationEntity ?: @"";
    if ([ident isEqualToString:@"toMany"]) {
      if (!rel.toMany) return @"to-one";
      return rel.ordered ? @"ordered" : @"to-many";
    }
    return rel.name;
  }
  NSArray *info = [self currentUserInfo];
  if (table == self.userInfoTable && info && (NSUInteger)row < info.count) {
    MBUserInfo *rowInfo = info[(NSUInteger)row];
    if ([ident isEqualToString:@"value"]) return rowInfo.value;
    return rowInfo.key;
  }
  return nil;
}

- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *ident = column.identifier;
  NSString *text = [value isKindOfClass:[NSString class]] ? value : [value description];
  if (table == self.userInfoTable) {
    NSMutableArray *info = [self currentUserInfo];
    if (!info || row < 0 || (NSUInteger)row >= info.count) return;
    MBUserInfo *rowInfo = info[(NSUInteger)row];
    if ([ident isEqualToString:@"value"]) rowInfo.value = text;
    else rowInfo.key = text;
    [self noteChanged];
    return;
  }
  if (table == self.entityTable && (NSUInteger)row < self.model.entities.count) {
    MBEntity *entity = self.model.entities[(NSUInteger)row];
    if ([ident isEqualToString:@"class"]) entity.representedClassName = text;
    else if (text.length) [self.model renameEntity:entity to:text];
    [self fillInspector];
    [self noteChanged];
    return;
  }
  if (table == self.fetchTable && (NSUInteger)row < self.model.fetchRequests.count) {
    MBFetchRequest *req = self.model.fetchRequests[(NSUInteger)row];
    if ([ident isEqualToString:@"entity"]) req.entityName = text;
    else if (text.length) req.name = text;
    [self fillInspector];
    [self noteChanged];
    return;
  }
  MBEntity *entity = [self selectedEntity];
  if (table == self.attributeTable && entity && (NSUInteger)row < entity.attributes.count) {
    MBAttribute *attr = entity.attributes[(NSUInteger)row];
    if ([ident isEqualToString:@"type"] && text.length) attr.attributeType = text;
    else if (text.length) attr.name = text;
    [self fillInspector];
    [self noteChanged];
    return;
  }
  if (table == self.relationshipTable && entity && (NSUInteger)row < entity.relationships.count) {
    MBRelationship *rel = entity.relationships[(NSUInteger)row];
    if ([ident isEqualToString:@"destination"]) rel.destinationEntity = text;
    else if (text.length) rel.name = text;
    [self fillInspector];
    [self noteChanged];
  }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  NSTableView *table = notification.object;
  if (table == self.entityTable) {
    [self.fetchTable deselectAll:nil];
    [self.attributeTable reloadData];
    [self.relationshipTable reloadData];
    [self inspectEntity];
  } else if (table == self.fetchTable) {
    [self.entityTable deselectAll:nil];
    [self inspectFetch];
  } else if (table == self.attributeTable) {
    if (self.attributeTable.selectedRow >= 0) [self inspectAttribute];
    else if ([self selectedEntity]) [self inspectEntity];
  } else if (table == self.relationshipTable) {
    if (self.relationshipTable.selectedRow >= 0) [self inspectRelationship];
    else if ([self selectedEntity]) [self inspectEntity];
  }
}

@end
