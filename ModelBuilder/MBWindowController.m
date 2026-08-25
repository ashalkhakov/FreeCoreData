/* ModelBuilder three-pane editor over FreeCoreData's own description
   classes: the tables and inspector read and mutate NSEntityDescription /
   NSAttributeDescription / NSRelationshipDescription directly; structural
   surgery (reparent, delete entity) goes through the document's XML
   mutation path so momc's compiler renormalizes the graph.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBWindowController.h"
#import "MBDocument.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"

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
  NSArray *_entities;          /* sorted NSEntityDescription rows */
  NSArray *_templateNames;     /* sorted fetch template names */
  NSArray *_attributeNames;    /* selected entity's own attributes, sorted */
  NSArray *_relationshipNames; /* selected entity's own relationships, sorted */
  NSArray *_userInfoKeys;      /* sorted keys of the inspected userInfo */
}

- (MBDocument *)modelDocument
{
  return (MBDocument *)self.document;
}

- (NSManagedObjectModel *)model
{
  return self.modelDocument.model;
}

#pragma mark - Row caches

- (void)rebuildEntityRows
{
  _entities = [self.modelDocument sortedEntities];
  _templateNames = [[[self.model fetchRequestTemplatesByName] allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
}

/* Xcode lists an entity's OWN properties; inherited ones live on the
   parent. */
- (void)rebuildPropertyRowsForEntity:(NSEntityDescription *)entity
{
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

- (void)rebuildUserInfoRows
{
  _userInfoKeys = [[[self currentUserInfo] allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Setup

- (void)configureTable:(NSTableView *)table
{
  if (!table) return;
  table.dataSource = self;
  table.delegate = self;
  table.rowHeight = 18.0;
  table.usesAlternatingRowBackgroundColors = YES;
  table.allowsEmptySelection = YES;
  table.allowsMultipleSelection = NO;
  for (NSTableColumn *col in table.tableColumns) {
    id cell = col.dataCell;
    if ([cell isKindOfClass:[NSTextFieldCell class]]) {
      NSTextFieldCell *tf = (NSTextFieldCell *)cell;
      tf.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeRegular]];
      tf.textColor = [NSColor labelColor];
      tf.drawsBackground = NO;
      tf.editable = YES;
      tf.selectable = YES;
    }
    id header = col.headerCell;
    if ([header isKindOfClass:[NSCell class]]) {
      [(NSCell *)header setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    }
  }
}

/* The version bar lives in the status row: the status field is
   shortened and the controls take the reclaimed width.  Created in
   code so the xib stays loadable by both GSXib5 and Xcode. */
- (void)installVersionBar
{
  NSView *host = self.statusField.superview;
  if (!host) return;

  NSRect status = self.statusField.frame;
  CGFloat barWidth = 470.0;
  if (status.size.width <= barWidth + 120.0) barWidth = status.size.width / 2.0;
  NSRect carved = status;
  carved.size.width -= barWidth;
  self.statusField.frame = carved;
  self.statusField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;

  CGFloat x = NSMaxX(carved);
  NSRect rowFrame = NSMakeRect(x, status.origin.y, 190, status.size.height);

  self.versionPopup = [[NSPopUpButton alloc] initWithFrame:rowFrame pullsDown:NO];
  self.versionPopup.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
  self.versionPopup.target = self;
  self.versionPopup.action = @selector(versionSelected:);
  [host addSubview:self.versionPopup];
  x += 190;

  NSButton *(^makeButton)(NSString *, SEL, CGFloat) = ^(NSString *title, SEL action, CGFloat width) {
    NSButton *button = [[NSButton alloc]
        initWithFrame:NSMakeRect(x, status.origin.y, width, status.size.height)];
    button.title = title;
    button.bezelStyle = NSRoundedBezelStyle;
    button.target = self;
    button.action = action;
    button.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [host addSubview:button];
    return button;
  };
  self.addVersionButton = makeButton(@"+ Version", @selector(addModelVersion:), 90);
  x += 90;
  self.makeCurrentButton = makeButton(@"Make Current", @selector(makeCurrentVersion:), 110);
  x += 110;
  self.validateButton = makeButton(@"Validate", @selector(validateModel:), 80);
}

/* Derivation editor, shown for attributes: a labelled text field
   dropped below the max field. */
- (void)installDerivationField
{
  NSView *host = self.maxField.superview;
  if (!host) return;

  NSRect anchor = self.maxField.frame;
  NSRect labelFrame = anchor;
  labelFrame.origin.y -= (anchor.size.height + 8.0);
  labelFrame.size.width = 70.0;
  labelFrame.origin.x = anchor.origin.x - 74.0;
  if (labelFrame.origin.x < 4.0) labelFrame.origin.x = 4.0;

  self.derivationLabel = [[NSTextField alloc] initWithFrame:labelFrame];
  self.derivationLabel.stringValue = @"Derivation";
  self.derivationLabel.bezeled = NO;
  self.derivationLabel.bordered = NO;
  self.derivationLabel.editable = NO;
  self.derivationLabel.selectable = NO;
  self.derivationLabel.drawsBackground = NO;
  self.derivationLabel.autoresizingMask = self.maxField.autoresizingMask;
  [host addSubview:self.derivationLabel];

  NSRect fieldFrame = anchor;
  fieldFrame.origin.y = labelFrame.origin.y;
  self.derivationField = [[NSTextField alloc] initWithFrame:fieldFrame];
  self.derivationField.autoresizingMask = self.maxField.autoresizingMask;
  self.derivationField.delegate = self;
  [host addSubview:self.derivationField];
}

- (void)windowDidLoad
{
  [super windowDidLoad];
  [self configureTable:self.entityTable];
  [self configureTable:self.fetchTable];
  [self configureTable:self.attributeTable];
  [self configureTable:self.relationshipTable];
  [self configureTable:self.userInfoTable];
  self.predicateView.delegate = self;

  [self.typePopup removeAllItems];
  [self.typePopup addItemsWithTitles:[CDModelCompiler attributeTypeNames]];
  [self.deleteRulePopup removeAllItems];
  [self.deleteRulePopup addItemsWithTitles:[CDModelCompiler deleteRuleNames]];

  [self installVersionBar];
  [self installDerivationField];

  [self reloadAll];
  if (_entities.count)
    [self.entityTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  [self inspectEntity];
}

- (void)reloadAll
{
  [self rebuildEntityRows];
  [self rebuildPropertyRowsForEntity:[self selectedEntity]];
  [self rebuildUserInfoRows];
  [self.entityTable reloadData];
  [self.fetchTable reloadData];
  [self.attributeTable reloadData];
  [self.relationshipTable reloadData];
  [self.userInfoTable reloadData];
  [self updateStatus];
  [self updateVersionBar];
}

- (void)noteChanged
{
  [self.modelDocument noteModelChanged];
  [self updateStatus];
}

- (void)updateStatus
{
  MBDocument *doc = self.modelDocument;
  self.statusField.stringValue = [NSString stringWithFormat:@"%@%@  —  %lu entities, %lu fetch requests",
                                  doc.editedVersionName ?: @"untitled",
                                  [doc.editedVersionName isEqualToString:doc.currentVersionName]
                                      ? @" (current)" : @"",
                                  (unsigned long)self.model.entities.count,
                                  (unsigned long)_templateNames.count];
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

#pragma mark - Selection

- (NSEntityDescription *)selectedEntity
{
  NSInteger row = self.entityTable.selectedRow;
  if (row < 0 || (NSUInteger)row >= _entities.count) return nil;
  return _entities[(NSUInteger)row];
}

- (NSString *)selectedTemplateName
{
  NSInteger row = self.fetchTable.selectedRow;
  if (row < 0 || (NSUInteger)row >= _templateNames.count) return nil;
  return _templateNames[(NSUInteger)row];
}

- (NSFetchRequest *)selectedTemplate
{
  NSString *name = [self selectedTemplateName];
  return name ? [self.model fetchRequestTemplateForName:name] : nil;
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

- (void)showEntityPane:(BOOL)entityNotFetch
{
  self.entityPane.hidden = !entityNotFetch;
  self.fetchPane.hidden = entityNotFetch;
}

- (void)showDerivation:(BOOL)visible
{
  self.derivationLabel.hidden = !visible;
  self.derivationField.hidden = !visible;
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
  NSEntityDescription *current = [self selectedEntity];
  for (NSEntityDescription *entity in _entities) {
    if (entity == current) continue;
    [self.parentPopup addItemWithTitle:entity.name ?: @""];
  }
}

- (void)rebuildDestinationPopup
{
  [self.destinationPopup removeAllItems];
  [self.destinationPopup addItemWithTitle:@"(none)"];
  for (NSEntityDescription *entity in _entities)
    [self.destinationPopup addItemWithTitle:entity.name ?: @""];
}

- (void)rebuildInversePopup
{
  [self.inversePopup removeAllItems];
  [self.inversePopup addItemWithTitle:@"(none)"];
  NSRelationshipDescription *rel = [self selectedRelationship];
  NSEntityDescription *dest = rel.destinationEntity;
  if (!dest) return;
  for (NSRelationshipDescription *other in dest.relationshipsByName.allValues)
    [self.inversePopup addItemWithTitle:other.name ?: @""];
}

- (void)fillInspector
{
  _updating = YES;
  NSEntityDescription *entity = [self selectedEntity];
  NSAttributeDescription *attr = [self selectedAttribute];
  NSRelationshipDescription *rel = [self selectedRelationship];
  NSFetchRequest *fetch = [self selectedTemplate];

  [self rebuildParentPopup];
  [self rebuildDestinationPopup];
  [self rebuildInversePopup];
  [self rebuildUserInfoRows];

  self.nameField.stringValue = @"";
  self.classField.stringValue = @"";
  self.defaultField.stringValue = @"";
  self.minField.stringValue = @"";
  self.maxField.stringValue = @"";
  self.derivationField.stringValue = @"";
  self.abstractButton.state = NSOffState;
  self.optionalButton.state = NSOffState;
  self.transientButton.state = NSOffState;
  self.toManyButton.state = NSOffState;
  if (self.orderedButton) self.orderedButton.state = NSOffState;
  self.predicateView.string = @"";
  [self showDerivation:NO];

  if (_kind == MBInspectEntity && entity) {
    self.nameField.stringValue = entity.name ?: @"";
    self.classField.stringValue = entity.managedObjectClassName ?: @"";
    self.abstractButton.state = entity.isAbstract ? NSOnState : NSOffState;
    NSString *parent = entity.superentity.name;
    if (parent.length && [self.parentPopup itemWithTitle:parent])
      [self.parentPopup selectItemWithTitle:parent];
    else
      [self.parentPopup selectItemAtIndex:0];
  } else if (_kind == MBInspectAttribute && attr) {
    [self showDerivation:YES];
    self.nameField.stringValue = attr.name ?: @"";
    NSString *typeName = [CDModelCompiler nameForAttributeType:attr.attributeType];
    if (typeName.length && [self.typePopup itemWithTitle:typeName])
      [self.typePopup selectItemWithTitle:typeName];
    self.optionalButton.state = attr.isOptional ? NSOnState : NSOffState;
    self.transientButton.state = attr.isTransient ? NSOnState : NSOffState;
    self.defaultField.stringValue = attr.defaultValue
        ? [self stringForDefaultValue:attr.defaultValue type:attr.attributeType] : @"";
    if ([attr isKindOfClass:[NSDerivedAttributeDescription class]]) {
      NSExpression *expr = [(NSDerivedAttributeDescription *)attr derivationExpression];
      self.derivationField.stringValue = expr ? [self stringForDerivation:expr] : @"";
    }
  } else if (_kind == MBInspectRelationship && rel) {
    self.nameField.stringValue = rel.name ?: @"";
    self.optionalButton.state = rel.isOptional ? NSOnState : NSOffState;
    self.transientButton.state = rel.isTransient ? NSOnState : NSOffState;
    self.toManyButton.state = rel.isToMany ? NSOnState : NSOffState;
    if (self.orderedButton) self.orderedButton.state = (rel.isToMany && rel.isOrdered) ? NSOnState : NSOffState;
    NSString *dest = rel.destinationEntity.name;
    if (dest.length && [self.destinationPopup itemWithTitle:dest])
      [self.destinationPopup selectItemWithTitle:dest];
    else
      [self.destinationPopup selectItemAtIndex:0];
    NSString *inverse = rel.inverseRelationship.name;
    if (inverse.length && [self.inversePopup itemWithTitle:inverse])
      [self.inversePopup selectItemWithTitle:inverse];
    else
      [self.inversePopup selectItemAtIndex:0];
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
  } else if (_kind == MBInspectFetch && fetch) {
    self.nameField.stringValue = [self selectedTemplateName] ?: @"";
    self.predicateView.string = fetch.predicate ? [fetch.predicate predicateFormat] : @"";
    if (fetch.entity.name.length && [self.destinationPopup itemWithTitle:fetch.entity.name])
      [self.destinationPopup selectItemWithTitle:fetch.entity.name];
  }
  [self.userInfoTable reloadData];
  _updating = NO;
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

#pragma mark - Version bar actions

- (void)presentError:(NSError *)error title:(NSString *)title
{
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = title;
  alert.informativeText = error.localizedDescription ?: @"Unknown error.";
  [alert runModal];
}

- (IBAction)versionSelected:(id)sender
{
  (void)sender;
  NSString *name = [[self.versionPopup selectedItem] representedObject];
  if (!name.length) return;
  NSError *error = nil;
  if (![self.modelDocument switchToVersion:name error:&error]) {
    [self presentError:error title:@"Cannot switch versions"];
    [self updateVersionBar];
    return;
  }
  [self reloadAll];
  [self inspectNone];
}

- (IBAction)addModelVersion:(id)sender
{
  (void)sender;
  if (![self.modelDocument addModelVersion]) return;
  [self reloadAll];
  [self inspectNone];
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

#pragma mark - Editing actions

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

- (void)selectEntityNamed:(NSString *)name
{
  [self rebuildEntityRows];
  [self.entityTable reloadData];
  for (NSUInteger i = 0; i < _entities.count; i++) {
    if ([[_entities[i] name] isEqualToString:name]) {
      [self.entityTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i]
                    byExtendingSelection:NO];
      break;
    }
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
  [self selectEntityNamed:name];
  [self.fetchTable deselectAll:nil];
  [self rebuildPropertyRowsForEntity:entity];
  [self.attributeTable reloadData];
  [self.relationshipTable reloadData];
  [self inspectEntity];
  [self noteChanged];
}

/* Deleting an entity ripples: relationships targeting it, fetch
   templates on it, configuration membership, subentity links.  The XML
   mutation path lets momc's compiler renormalize all of it. */
- (IBAction)removeEntity:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  if (!entity) return;
  NSString *doomed = entity.name;
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
    [self presentError:error title:@"Cannot delete entity"];
    return;
  }
  [self reloadAll];
  [self inspectNone];
}

- (IBAction)addFetchRequest:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity] ?: _entities.firstObject;
  if (!entity) return;
  NSString *name = [self uniqueName:@"FetchRequest" among:_templateNames];
  NSFetchRequest *request = [[NSFetchRequest alloc] init];
  request.entity = entity;
  [self.model setFetchRequestTemplate:request forName:name];
  [self rebuildEntityRows];
  [self.fetchTable reloadData];
  NSUInteger idx = [_templateNames indexOfObject:name];
  if (idx != NSNotFound)
    [self.fetchTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx]
                 byExtendingSelection:NO];
  [self.entityTable deselectAll:nil];
  [self inspectFetch];
  [self noteChanged];
}

- (IBAction)removeFetchRequest:(id)sender
{
  (void)sender;
  NSString *name = [self selectedTemplateName];
  if (!name) return;
  [self.model setFetchRequestTemplate:nil forName:name];
  [self rebuildEntityRows];
  [self.fetchTable reloadData];
  [self inspectNone];
  [self noteChanged];
}

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

- (IBAction)addAttribute:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  if (!entity) return;
  NSString *name = [self uniqueName:@"attribute"
                              among:entity.propertiesByName.allKeys];
  NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
  attribute.name = name;
  attribute.attributeType = NSStringAttributeType;
  attribute.optional = YES;
  entity.properties = [entity.properties arrayByAddingObject:attribute];
  [self rebuildPropertyRowsForEntity:entity];
  [self.attributeTable reloadData];
  NSUInteger idx = [_attributeNames indexOfObject:name];
  if (idx != NSNotFound)
    [self.attributeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx]
                     byExtendingSelection:NO];
  [self inspectAttribute];
  [self noteChanged];
}

- (IBAction)removeAttribute:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  NSAttributeDescription *attribute = [self selectedAttribute];
  if (!entity || !attribute) return;
  [self replaceProperty:attribute with:nil ofEntity:entity];
  [self rebuildPropertyRowsForEntity:entity];
  [self.attributeTable reloadData];
  [self inspectEntity];
  [self noteChanged];
}

- (IBAction)addRelationship:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  if (!entity) return;
  NSString *name = [self uniqueName:@"relationship"
                              among:entity.propertiesByName.allKeys];
  NSRelationshipDescription *relationship = [[NSRelationshipDescription alloc] init];
  relationship.name = name;
  relationship.optional = YES;
  relationship.minCount = 0;
  relationship.maxCount = 1;
  relationship.deleteRule = NSNullifyDeleteRule;
  NSEntityDescription *destination = entity;
  for (NSEntityDescription *other in _entities)
    if (other != entity) { destination = other; break; }
  relationship.destinationEntity = destination;
  entity.properties = [entity.properties arrayByAddingObject:relationship];
  [self rebuildPropertyRowsForEntity:entity];
  [self.relationshipTable reloadData];
  NSUInteger idx = [_relationshipNames indexOfObject:name];
  if (idx != NSNotFound)
    [self.relationshipTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx]
                        byExtendingSelection:NO];
  [self inspectRelationship];
  [self noteChanged];
}

- (IBAction)removeRelationship:(id)sender
{
  (void)sender;
  NSEntityDescription *entity = [self selectedEntity];
  NSRelationshipDescription *relationship = [self selectedRelationship];
  if (!entity || !relationship) return;
  /* Clear the back-pointer on the inverse, if any. */
  NSRelationshipDescription *inverse = relationship.inverseRelationship;
  if (inverse.inverseRelationship == relationship)
    inverse.inverseRelationship = nil;
  [self replaceProperty:relationship with:nil ofEntity:entity];
  [self rebuildPropertyRowsForEntity:entity];
  [self.relationshipTable reloadData];
  [self inspectEntity];
  [self noteChanged];
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
  [self noteChanged];
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
  [self noteChanged];
}

#pragma mark - Inspector writes

- (void)applyDerivationString:(NSString *)string toAttribute:(NSAttributeDescription *)attribute
                     ofEntity:(NSEntityDescription *)entity
{
  BOOL isDerived = [attribute isKindOfClass:[NSDerivedAttributeDescription class]];
  if (!string.length) {
    if (!isDerived) return;
    /* Derived -> plain: replace the object, keep the shared fields. */
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
  NSExpression *expression = [CDModelCompiler derivationExpressionFromString:string
                                                                      error:&error];
  if (!expression) {
    [self presentError:error title:@"Invalid derivation expression"];
    return;
  }
  if (isDerived) {
    [(NSDerivedAttributeDescription *)attribute setDerivationExpression:expression];
    return;
  }
  /* Plain -> derived: replace the object. */
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

/* Reparenting rewrites the XML so the compiler renormalizes subentity
   wiring - the description classes cannot detach a child. */
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
    [self presentError:error title:@"Cannot change parent entity"];
  [self reloadAll];
  [self selectEntityNamed:entityName];
  [self inspectEntity];
}

- (IBAction)inspectorChanged:(id)sender
{
  (void)sender;
  if (_updating) return;
  NSEntityDescription *entity = [self selectedEntity];
  NSAttributeDescription *attr = [self selectedAttribute];
  NSRelationshipDescription *rel = [self selectedRelationship];
  NSString *templateName = [self selectedTemplateName];

  if (_kind == MBInspectEntity && entity) {
    NSString *newName = self.nameField.stringValue;
    if (newName.length) [self renameEntity:entity to:newName];
    entity.managedObjectClassName = self.classField.stringValue.length
        ? self.classField.stringValue : @"NSManagedObject";
    entity.abstract = (self.abstractButton.state == NSOnState);

    NSString *parent = self.parentPopup.titleOfSelectedItem;
    NSString *wantedParent = ([parent isEqualToString:@"(none)"] || !parent.length) ? @"" : parent;
    NSString *haveParent = entity.superentity.name ?: @"";
    [self rebuildEntityRows];
    [self.entityTable reloadData];
    if (![wantedParent isEqualToString:haveParent]) {
      [self setParentOfEntityNamed:entity.name to:wantedParent];
      return; /* reload/selection handled by the XML path */
    }
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
    [self rebuildPropertyRowsForEntity:entity];
    [self.attributeTable reloadData];
  } else if (_kind == MBInspectRelationship && rel && entity) {
    if (self.nameField.stringValue.length &&
        !entity.propertiesByName[self.nameField.stringValue])
      rel.name = self.nameField.stringValue;
    rel.optional = (self.optionalButton.state == NSOnState);
    rel.transient = (self.transientButton.state == NSOnState);
    BOOL toMany = (self.toManyButton.state == NSOnState);
    if (toMany) {
      rel.minCount = self.minField.stringValue.integerValue;
      rel.maxCount = self.maxField.stringValue.integerValue;
      if (self.orderedButton) rel.ordered = (self.orderedButton.state == NSOnState);
    } else {
      rel.minCount = rel.isOptional ? 0 : 1;
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
    [self rebuildPropertyRowsForEntity:entity];
    [self.relationshipTable reloadData];
  } else if (_kind == MBInspectFetch && templateName) {
    NSFetchRequest *request = [self selectedTemplate];
    NSString *newName = self.nameField.stringValue;
    if (newName.length && ![newName isEqualToString:templateName] &&
        ![self.model fetchRequestTemplateForName:newName]) {
      [self.model setFetchRequestTemplate:nil forName:templateName];
      [self.model setFetchRequestTemplate:request forName:newName];
      templateName = newName;
    }
    NSString *entityName = self.destinationPopup.titleOfSelectedItem;
    if (entityName.length && ![entityName isEqualToString:@"(none)"] &&
        self.model.entitiesByName[entityName])
      request.entity = self.model.entitiesByName[entityName];
    NSString *predicateString = self.predicateView.string;
    if (predicateString.length) {
      @try {
        request.predicate = [NSPredicate predicateWithFormat:predicateString];
      } @catch (NSException *exception) {
        /* keep the old predicate; the string stays visible for fixing */
      }
    } else {
      request.predicate = nil;
    }
    [self rebuildEntityRows];
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
  if (table == self.entityTable) return (NSInteger)_entities.count;
  if (table == self.fetchTable) return (NSInteger)_templateNames.count;
  if (table == self.attributeTable) return (NSInteger)_attributeNames.count;
  if (table == self.relationshipTable) return (NSInteger)_relationshipNames.count;
  if (table == self.userInfoTable) return (NSInteger)_userInfoKeys.count;
  return 0;
}

- (NSString *)stringValueForTable:(NSTableView *)table column:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *ident = column.identifier ?: @"";
  if (table == self.entityTable) {
    if (row < 0 || (NSUInteger)row >= _entities.count) return @"";
    NSEntityDescription *entity = _entities[(NSUInteger)row];
    if ([ident isEqualToString:@"class"]) return entity.managedObjectClassName ?: @"";
    return entity.name ?: @"";
  }
  if (table == self.fetchTable) {
    if (row < 0 || (NSUInteger)row >= _templateNames.count) return @"";
    NSString *name = _templateNames[(NSUInteger)row];
    if ([ident isEqualToString:@"entity"])
      return [[self.model fetchRequestTemplateForName:name] entity].name ?: @"";
    return name;
  }
  NSEntityDescription *entity = [self selectedEntity];
  if (table == self.attributeTable && entity && row >= 0 && (NSUInteger)row < _attributeNames.count) {
    NSAttributeDescription *attr = entity.attributesByName[_attributeNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"type"])
      return [CDModelCompiler nameForAttributeType:attr.attributeType] ?: @"";
    if ([ident isEqualToString:@"optional"]) return attr.isOptional ? @"○" : @"●";
    return attr.name ?: @"";
  }
  if (table == self.relationshipTable && entity && row >= 0 && (NSUInteger)row < _relationshipNames.count) {
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
  return @"";
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  return [self stringValueForTable:table column:column row:row];
}

/* View-based path (modern AppKit / Xcode-opened XIBs). Cell-based still uses objectValue. */
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *ident = column.identifier ?: @"cell";
  NSTextField *field = [table makeViewWithIdentifier:ident owner:self];
  if (!field) {
    field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, column.width, table.rowHeight)];
    field.identifier = ident;
    field.bezeled = NO;
    field.bordered = NO;
    field.drawsBackground = NO;
    field.editable = YES;
    field.selectable = YES;
    field.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeRegular]];
    field.textColor = [NSColor labelColor];
    [(NSCell *)field.cell setLineBreakMode:NSLineBreakByTruncatingTail];
  }
  field.stringValue = [self stringValueForTable:table column:column row:row];
  field.target = self;
  field.action = @selector(tableCellEdited:);
  field.tag = row; /* row index; column via identifier */
  return field;
}

- (IBAction)tableCellEdited:(id)sender
{
  if (![sender isKindOfClass:[NSTextField class]]) return;
  NSTextField *field = (NSTextField *)sender;
  NSTableView *table = (NSTableView *)field.enclosingScrollView.documentView;
  if (![table isKindOfClass:[NSTableView class]]) {
    NSView *v = field.superview;
    while (v && ![v isKindOfClass:[NSTableView class]]) v = v.superview;
    table = (NSTableView *)v;
  }
  if (![table isKindOfClass:[NSTableView class]]) return;
  NSInteger row = [table rowForView:field];
  if (row < 0) row = field.tag;
  NSTableColumn *col = nil;
  for (NSTableColumn *c in table.tableColumns) {
    if ([c.identifier isEqualToString:field.identifier]) { col = c; break; }
  }
  if (!col && table.tableColumns.count) col = table.tableColumns[0];
  if (row < 0 || !col) return;
  [self tableView:table setObjectValue:field.stringValue forTableColumn:col row:row];
}

- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *ident = column.identifier;
  NSString *text = [value isKindOfClass:[NSString class]] ? value : [value description];

  if (table == self.userInfoTable) {
    if (row < 0 || (NSUInteger)row >= _userInfoKeys.count) return;
    NSString *key = _userInfoKeys[(NSUInteger)row];
    NSMutableDictionary *info = [([self currentUserInfo] ?: @{}) mutableCopy];
    if ([ident isEqualToString:@"value"]) {
      info[key] = text;
    } else if (text.length && !info[text]) {
      info[text] = info[key] ?: @"";
      [info removeObjectForKey:key];
    }
    [self setCurrentUserInfo:info];
    [self.userInfoTable reloadData];
    [self noteChanged];
    return;
  }
  if (table == self.entityTable && (NSUInteger)row < _entities.count) {
    NSEntityDescription *entity = _entities[(NSUInteger)row];
    if ([ident isEqualToString:@"class"]) entity.managedObjectClassName = text;
    else if (text.length) [self renameEntity:entity to:text];
    [self rebuildEntityRows];
    [self.entityTable reloadData];
    [self fillInspector];
    [self noteChanged];
    return;
  }
  if (table == self.fetchTable && (NSUInteger)row < _templateNames.count) {
    NSString *name = _templateNames[(NSUInteger)row];
    NSFetchRequest *request = [self.model fetchRequestTemplateForName:name];
    if ([ident isEqualToString:@"entity"]) {
      if (self.model.entitiesByName[text]) request.entity = self.model.entitiesByName[text];
    } else if (text.length && ![self.model fetchRequestTemplateForName:text]) {
      [self.model setFetchRequestTemplate:nil forName:name];
      [self.model setFetchRequestTemplate:request forName:text];
    }
    [self rebuildEntityRows];
    [self.fetchTable reloadData];
    [self fillInspector];
    [self noteChanged];
    return;
  }
  NSEntityDescription *entity = [self selectedEntity];
  if (table == self.attributeTable && entity && (NSUInteger)row < _attributeNames.count) {
    NSAttributeDescription *attr = entity.attributesByName[_attributeNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"type"]) {
      NSInteger type = [CDModelCompiler attributeTypeNamed:text];
      if (type >= 0) attr.attributeType = (NSAttributeType)type;
    } else if (text.length && !entity.propertiesByName[text]) {
      attr.name = text;
    }
    [self rebuildPropertyRowsForEntity:entity];
    [self.attributeTable reloadData];
    [self fillInspector];
    [self noteChanged];
    return;
  }
  if (table == self.relationshipTable && entity && (NSUInteger)row < _relationshipNames.count) {
    NSRelationshipDescription *rel = entity.relationshipsByName[_relationshipNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"destination"]) {
      if (self.model.entitiesByName[text]) rel.destinationEntity = self.model.entitiesByName[text];
    } else if (text.length && !entity.propertiesByName[text]) {
      rel.name = text;
    }
    [self rebuildPropertyRowsForEntity:entity];
    [self.relationshipTable reloadData];
    [self fillInspector];
    [self noteChanged];
  }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  NSTableView *table = notification.object;
  if (table == self.entityTable) {
    [self.fetchTable deselectAll:nil];
    [self rebuildPropertyRowsForEntity:[self selectedEntity]];
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
