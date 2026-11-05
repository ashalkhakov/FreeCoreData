/* ModelBuilder — the centre (see MBDetailViewController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBDetailViewController.h"
#import "MBModelEditor.h"
#import "MBEditors.h"
#import "MBWindowSupport.h"
#import "CDModelCompiler.h"
#import "JUInspectorView.h"
#import "JUInspectorViewContainer.h"

/* centerTabView pages */
enum { MBCenterPageEntity = 0, MBCenterPageFetch = 1, MBCenterPageConfiguration = 2, MBCenterPageFetchIndex = 3 };
/* predicateTabView pages */
enum { MBPredicatePageEditor = 0, MBPredicatePageSource = 1 };

/* What a fetch request's predicate editor has a row for: an attribute of
   a type with operators (a binary or transformable one has none). */
static BOOL MBAttributeTypeHasOperators(NSAttributeType type)
{
  switch (type) {
    case NSInteger16AttributeType: case NSInteger32AttributeType:
    case NSInteger64AttributeType: case NSDecimalAttributeType:
    case NSDoubleAttributeType: case NSFloatAttributeType:
    case NSStringAttributeType: case NSBooleanAttributeType:
    case NSDateAttributeType:
      return YES;
    default:
      return NO;
  }
}

@implementation MBDetailViewController {
  NSArray *_attributeNames;
  NSArray *_relationshipNames;
  NSArray *_memberEntityNames;      /* all entities, for the membership checklist */
  NSArray *_fetchIndexElementRows;  /* the selected index's elements */
  BOOL _showing;                    /* the selection being shown, not made */
}

- (instancetype)init
{
  return [super initWithNibName:@"MBDetail" bundle:[NSBundle bundleForClass:[self class]]];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
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

- (void)modelDidChange:(NSNotification *)notification
{
  (void)notification;
  [self reload];
}

- (void)selectionDidChange:(NSNotification *)notification
{
  (void)notification;
  [self reload];
}

#pragma mark - The page

- (NSEntityDescription *)selectedEntity
{
  return [_modelEditor selectedEntity];
}

- (void)rebuildPropertyRows
{
  NSEntityDescription *entity = [self selectedEntity];
  NSMutableArray *attributes = [NSMutableArray array];
  NSMutableArray *relationships = [NSMutableArray array];
  /* The entity's own, as Xcode lists them; -properties includes inherited ones. */
  for (NSPropertyDescription *property in [CDModelCompiler declaredPropertiesOfEntity:entity]) {
    if ([property isKindOfClass:[NSAttributeDescription class]])
      [attributes addObject:property.name];
    else if ([property isKindOfClass:[NSRelationshipDescription class]])
      [relationships addObject:property.name];
  }
  _attributeNames = [attributes sortedArrayUsingSelector:@selector(compare:)];
  _relationshipNames = [relationships sortedArrayUsingSelector:@selector(compare:)];
}

static void MBSelectRowNamed(NSTableView *table, NSArray *names, NSString *name)
{
  NSUInteger row = name ? [names indexOfObject:name] : NSNotFound;
  if (row != NSNotFound)
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
  else
    [table deselectAll:nil];
}

- (void)reload
{
  MBSelection *selection = _modelEditor.selection;
  _showing = YES;
  [self rebuildPropertyRows];
  _memberEntityNames = [[self.model.entitiesByName allKeys]
      sortedArrayUsingSelector:@selector(compare:)];
  [self.attributeTable reloadData];
  [self.relationshipTable reloadData];
  [self.memberTable reloadData];
  switch (selection.kind) {
    case MBSelectionEntity:
      if (selection.configurationName) {
        [self.centerTabView selectTabViewItemAtIndex:MBCenterPageConfiguration];
        MBSelectRowNamed(self.memberTable, _memberEntityNames, selection.entityName);
        break;
      }
      /* fall through: an entity's page, no property selected */
    case MBSelectionAttribute:
    case MBSelectionRelationship:
      [self.centerTabView selectTabViewItemAtIndex:MBCenterPageEntity];
      MBSelectRowNamed(self.attributeTable, _attributeNames,
                       selection.kind == MBSelectionAttribute ? selection.name : nil);
      MBSelectRowNamed(self.relationshipTable, _relationshipNames,
                       selection.kind == MBSelectionRelationship ? selection.name : nil);
      break;
    case MBSelectionFetchRequest:
      [self.centerTabView selectTabViewItemAtIndex:MBCenterPageFetch];
      [self showFetchRequest:[_modelEditor selectedFetchRequest]];
      break;
    case MBSelectionConfiguration:
      [self.centerTabView selectTabViewItemAtIndex:MBCenterPageConfiguration];
      [self.memberTable deselectAll:nil];
      break;
    case MBSelectionFetchIndex:
      [self.centerTabView selectTabViewItemAtIndex:MBCenterPageFetchIndex];
      _fetchIndexElementRows = [self selectedFetchIndexRow][@"elements"] ?: @[];
      [self.fetchIndexElementTable reloadData];
      break;
    default:
      [self.centerTabView selectTabViewItemAtIndex:MBCenterPageEntity];
      break;
  }
  _showing = NO;
}

/* A row picked in a table is the selection; none picked, the entity's or
   the configuration's own. */
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  if (_showing) return;
  NSTableView *table = notification.object;
  MBSelection *selection = _modelEditor.selection;
  NSString *entityName = selection.entityName;
  if (table == self.attributeTable || table == self.relationshipTable) {
    BOOL attributes = (table == self.attributeTable);
    NSInteger row = table.selectedRow;
    NSArray *names = attributes ? _attributeNames : _relationshipNames;
    if (row >= 0 && (NSUInteger)row < names.count) {
      _modelEditor.selection =
          [MBSelection selectionOfKind:attributes ? MBSelectionAttribute : MBSelectionRelationship
                            entityName:entityName
                                  name:names[(NSUInteger)row]
                     configurationName:nil];
    } else if ((attributes ? selection.kind == MBSelectionAttribute
                           : selection.kind == MBSelectionRelationship)) {
      _modelEditor.selection = [MBSelection entityNamed:entityName];
    }
  } else if (table == self.memberTable) {
    NSString *configuration = selection.configurationName;
    NSInteger row = table.selectedRow;
    if (row >= 0 && (NSUInteger)row < _memberEntityNames.count)
      _modelEditor.selection = [MBSelection selectionOfKind:MBSelectionEntity
                                                 entityName:_memberEntityNames[(NSUInteger)row]
                                                       name:nil
                                          configurationName:configuration];
    else
      _modelEditor.selection = [MBSelection configurationNamed:configuration];
  }
}

#pragma mark - Properties

- (MBEntityEditor *)entityEditor
{
  NSString *name = [self selectedEntity].name;
  return name ? [MBEntityEditor editorForEntityNamed:name modelEditor:_modelEditor] : nil;
}

- (void)selectProperty:(NSString *)name ofKind:(MBSelectionKind)kind
{
  _modelEditor.selection = [MBSelection selectionOfKind:kind entityName:[self selectedEntity].name
                                                   name:name configurationName:nil];
}

- (IBAction)addAttribute:(id)sender
{
  (void)sender;
  NSString *name = [[self entityEditor] addAttribute];
  if (name) [self selectProperty:name ofKind:MBSelectionAttribute];
}

- (IBAction)removeAttribute:(id)sender
{
  (void)sender;
  MBSelection *selection = _modelEditor.selection;
  if (selection.kind != MBSelectionAttribute) return;
  [[self entityEditor] removeAttributeNamed:selection.name];
  _modelEditor.selection = [MBSelection entityNamed:selection.entityName];
}

- (IBAction)addRelationship:(id)sender
{
  (void)sender;
  NSString *name = [[self entityEditor] addRelationship];
  if (name) [self selectProperty:name ofKind:MBSelectionRelationship];
}

- (IBAction)removeRelationship:(id)sender
{
  (void)sender;
  MBSelection *selection = _modelEditor.selection;
  if (selection.kind != MBSelectionRelationship) return;
  [[self entityEditor] removeRelationshipNamed:selection.name];
  _modelEditor.selection = [MBSelection entityNamed:selection.entityName];
}

- (IBAction)propertySegmentClicked:(id)sender
{
  BOOL relationships = (_modelEditor.selection.kind == MBSelectionRelationship);
  if ([sender selectedSegment] == 0) {
    if (relationships) [self addRelationship:sender];
    else [self addAttribute:sender];
  } else {
    if (relationships) [self removeRelationship:sender];
    else [self removeAttribute:sender];
  }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  if (item.action == @selector(addAttribute:) || item.action == @selector(addRelationship:))
    return [self selectedEntity] != nil;
  return YES;
}

#pragma mark - A fetch request's page

- (void)showFetchRequest:(NSFetchRequest *)fetch
{
  [self.fetchEntityPopup removeAllItems];
  for (NSEntityDescription *entity in [_modelEditor sortedEntities])
    [self.fetchEntityPopup addItemWithTitle:entity.name ?: @""];
  NSString *entityName = fetch.entity.name;
  if (entityName.length && [self.fetchEntityPopup itemWithTitle:entityName])
    [self.fetchEntityPopup selectItemWithTitle:entityName];
  self.predicateSourceView.stringValue = fetch.predicate ? [fetch.predicate predicateFormat] : @"";
  [self showPredicateInEditor:fetch];
}

/* The editor's rows: All, Any or None, and a row for each of the fetch's
   entity's attributes that has operators.  It shows the predicate when it
   can show all of it, reading the same predicate back; otherwise the
   predicate is edited as source, and the editor's segment is off. */
- (void)showPredicateInEditor:(NSFetchRequest *)fetch
{
  NSPredicateEditor *predicateEditor = self.fetchPredicateEditor;
  NSPredicate *predicate = fetch.predicate;
  BOOL shown = NO;
  @try {
    NSMutableArray *templates = [NSMutableArray arrayWithObject:
        [[NSPredicateEditorRowTemplate alloc]
            initWithCompoundTypes:@[ @(NSAndPredicateType), @(NSOrPredicateType),
                                     @(NSNotPredicateType) ]]];
    NSMutableArray *keyPaths = [NSMutableArray array];
    for (NSString *name in [[fetch.entity.attributesByName allKeys]
             sortedArrayUsingSelector:@selector(compare:)]) {
      NSAttributeDescription *attribute = fetch.entity.attributesByName[name];
      if (MBAttributeTypeHasOperators(attribute.attributeType)) [keyPaths addObject:name];
    }
    if (keyPaths.count)
      [templates addObjectsFromArray:[NSPredicateEditorRowTemplate
          templatesWithAttributeKeyPaths:keyPaths inEntityDescription:fetch.entity]];
    predicateEditor.rowTemplates = templates;
    if (!predicate) {
      /* All, with no rows under it yet */
      predicateEditor.objectValue = nil;
      [predicateEditor insertRowAtIndex:0 withType:NSRuleEditorRowTypeCompound
                          asSubrowOfRow:-1 animate:NO];
    } else {
      /* a comparison alone goes under All, so a row added beside it joins it */
      predicateEditor.objectValue = [predicate isKindOfClass:[NSCompoundPredicate class]]
          ? predicate : [NSCompoundPredicate andPredicateWithSubpredicates:@[ predicate ]];
    }
    shown = [[self editorPredicateFormat] isEqualToString:predicate ? predicate.predicateFormat : @""];
  } @catch (NSException *exception) {
    shown = NO;
  }
  [self.predicateSourceSegmentedControl setEnabled:shown forSegment:MBPredicatePageEditor];
  if (!shown) {
    [self.predicateTabView selectTabViewItemAtIndex:MBPredicatePageSource];
    [self.predicateSourceSegmentedControl setSelectedSegment:MBPredicatePageSource];
  }
}

/* The editor's predicate as text: none for All with no rows. */
- (NSString *)editorPredicateFormat
{
  NSString *format = self.fetchPredicateEditor.predicate.predicateFormat;
  return !format || [format isEqualToString:@"TRUEPREDICATE"] ? @"" : format;
}

- (IBAction)predicateSourceToggled:(id)sender
{
  NSInteger segment = [sender selectedSegment];
  [self.predicateTabView selectTabViewItemAtIndex:
      segment == 0 ? MBPredicatePageEditor : MBPredicatePageSource];
}

/* The fetch request's entity, or its predicate: from whichever editor
   the user is on. */
- (IBAction)inspectorChanged:(id)sender
{
  if (_showing || _modelEditor.selection.kind != MBSelectionFetchRequest) return;
  MBFetchEditor *editor = [MBFetchEditor editorForFetchRequestNamed:_modelEditor.selection.name
                                                        modelEditor:_modelEditor];
  if (!editor) return;
  [_modelEditor beginEdit:@"Edit Fetch Request"];
  if (sender == self.fetchEntityPopup) {
    editor.entityName = self.fetchEntityPopup.titleOfSelectedItem;
  } else if (sender == self.fetchPredicateEditor) {
    NSString *format = [self editorPredicateFormat];
    editor.predicate = format.length ? [NSPredicate predicateWithFormat:format] : nil;
  } else if (sender == self.predicateSourceView) {
    /* an unparseable string keeps the old predicate; the text stays
       visible for fixing */
    editor.predicateFormat = self.predicateSourceView.stringValue;
  }
  [_modelEditor endEdit];
}

#pragma mark - A fetch index's page

- (NSDictionary *)selectedFetchIndexRow
{
  MBSelection *selection = _modelEditor.selection;
  if (selection.kind != MBSelectionFetchIndex) return nil;
  for (NSDictionary *row in [self entityEditor].fetchIndexRows)
    if ([row[@"name"] isEqualToString:selection.name]) return row;
  return nil;
}

/* The selected index with one of its rows changed - its elements - as
   one undo step. */
- (void)changeSelectedFetchIndex:(void (^)(NSMutableDictionary *row))change action:(NSString *)action
{
  NSString *name = _modelEditor.selection.name;
  MBEntityEditor *editor = [self entityEditor];
  NSMutableArray *rows = [NSMutableArray array];
  for (NSDictionary *row in editor.fetchIndexRows) {
    NSMutableDictionary *copy = [row mutableCopy];
    if ([row[@"name"] isEqualToString:name]) change(copy);
    [rows addObject:copy];
  }
  [_modelEditor beginEdit:action];
  editor.fetchIndexRows = rows;
  [_modelEditor endEdit];
  if (editor.lastError)
    MBPresentModelError(editor.lastError, @"Cannot change the fetch index");
}

/* What an element can index: the entity's stored attributes and to-ones,
   its own and inherited, by name. */
- (NSArray *)fetchIndexPropertyChoices
{
  NSMutableArray *names = [NSMutableArray array];
  NSDictionary *properties = [self selectedEntity].propertiesByName;
  for (NSString *name in properties) {
    NSPropertyDescription *property = properties[name];
    if (property.isTransient) continue;
    if ([property isKindOfClass:[NSAttributeDescription class]] ||
        ([property isKindOfClass:[NSRelationshipDescription class]] && ![(NSRelationshipDescription *)property isToMany]))
      [names addObject:name];
  }
  return [names sortedArrayUsingSelector:@selector(compare:)];
}

- (NSString *)fetchIndexElementTitle:(NSDictionary *)element
{
  NSExpressionDescription *expression = element[@"expression"];
  if (expression) return [NSString stringWithFormat:@"expression: %@", [expression.expression description]];
  return element[@"property"] ?: @"";
}

/* + adds an element (the first property the index does not have yet),
   − removes the selected one. */
- (IBAction)fetchIndexElementSegmentClicked:(id)sender
{
  if (![self selectedFetchIndexRow]) return;
  NSInteger selected = self.fetchIndexElementTable.selectedRow;
  if ([sender selectedSegment] == 0) {
    NSArray *choices = [self fetchIndexPropertyChoices];
    NSArray *used = [_fetchIndexElementRows valueForKey:@"property"];
    NSString *next = nil;
    for (NSString *choice in choices)
      if (![used containsObject:choice]) { next = choice; break; }
    if (!next) next = choices.firstObject;
    if (!next) return;
    [self changeSelectedFetchIndex:^(NSMutableDictionary *row) {
              row[@"elements"] = [row[@"elements"] arrayByAddingObject:@{ @"property" : next }];
            }
                            action:@"Add Fetch Index Element"];
  } else {
    if (selected < 0 || (NSUInteger)selected >= _fetchIndexElementRows.count) return;
    [self changeSelectedFetchIndex:^(NSMutableDictionary *row) {
              NSMutableArray *elements = [row[@"elements"] mutableCopy];
              [elements removeObjectAtIndex:(NSUInteger)selected];
              row[@"elements"] = elements;
            }
                            action:@"Remove Fetch Index Element"];
  }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if (table == self.attributeTable) return (NSInteger)_attributeNames.count;
  if (table == self.relationshipTable) return (NSInteger)_relationshipNames.count;
  if (table == self.memberTable) return (NSInteger)_memberEntityNames.count;
  if (table == self.fetchIndexElementTable) return (NSInteger)_fetchIndexElementRows.count;
  return 0;
}

/* The Type / Destination / Inverse columns are popups, as in Xcode's
   model editor.  Their choices: the momc type names; every entity; and
   (none) plus the relationships of that row's destination -- the one
   list that differs by row. */
- (NSArray *)choicesForTable:(NSTableView *)table column:(NSString *)ident row:(NSInteger)row
{
  if (table == self.fetchIndexElementTable) {
    if ([ident isEqualToString:@"type"]) return @[ @"Binary", @"R-Tree" ];
    if ([ident isEqualToString:@"order"]) return @[ @"Ascending", @"Descending" ];
    /* An expression element offers itself besides the properties. */
    NSMutableArray *choices = [[self fetchIndexPropertyChoices] mutableCopy];
    if (row >= 0 && (NSUInteger)row < _fetchIndexElementRows.count &&
        _fetchIndexElementRows[(NSUInteger)row][@"expression"])
      [choices addObject:[self fetchIndexElementTitle:_fetchIndexElementRows[(NSUInteger)row]]];
    return choices;
  }
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

static NSNumber *MBIndexOf(NSString *name, NSArray *choices)
{
  NSUInteger index = name ? [choices indexOfObject:name] : NSNotFound;
  return @(index == NSNotFound ? -1 : (NSInteger)index);
}

/* A declared configuration's name; nil for the implicit Default, which
   the file does not have. */
- (NSString *)selectedConfigurationName
{
  NSString *name = _modelEditor.selection.configurationName;
  if (!name) return nil;
  if ([name isEqualToString:@"Default"] && ![[_modelEditor configurationNames] containsObject:name])
    return nil;
  return name;
}

- (BOOL)selectedConfigurationIsImplicitDefault
{
  NSString *name = _modelEditor.selection.configurationName;
  return [name isEqualToString:@"Default"] && ![[_modelEditor configurationNames] containsObject:name];
}

/* Badge for a table's leading NSImageCell column; nil draws blank. */
- (NSImage *)iconForTable:(NSTableView *)table row:(NSInteger)row
{
  if (row < 0) return nil;
  NSEntityDescription *entity = [self selectedEntity];
  if (table == self.attributeTable && entity && (NSUInteger)row < _attributeNames.count) {
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

  if (table == self.fetchIndexElementTable && row >= 0 && (NSUInteger)row < _fetchIndexElementRows.count) {
    NSDictionary *element = _fetchIndexElementRows[(NSUInteger)row];
    NSString *current = [ident isEqualToString:@"type"] ? ([element[@"rtree"] boolValue] ? @"R-Tree" : @"Binary")
                      : [ident isEqualToString:@"order"] ? (element[@"ascending"] && ![element[@"ascending"] boolValue] ? @"Descending" : @"Ascending")
                      : [self fetchIndexElementTitle:element];
    return MBIndexOf(current, [self choicesForTable:table column:ident row:row]);
  }
  if (table == self.attributeTable && entity && row >= 0 &&
      (NSUInteger)row < _attributeNames.count) {
    NSAttributeDescription *attr = entity.attributesByName[_attributeNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"type"])
      return MBIndexOf([CDModelCompiler nameForAttributeType:attr.attributeType],
                       [self choicesForTable:table column:ident row:row]);
    return attr.name ?: @"";
  }
  if (table == self.relationshipTable && entity && row >= 0 &&
      (NSUInteger)row < _relationshipNames.count) {
    NSRelationshipDescription *rel = entity.relationshipsByName[_relationshipNames[(NSUInteger)row]];
    if ([ident isEqualToString:@"destination"] || [ident isEqualToString:@"inverse"]) {
      NSString *current = [ident isEqualToString:@"destination"]
          ? rel.destinationEntity.name : (rel.inverseRelationship.name ?: @"(none)");
      return MBIndexOf(current, [self choicesForTable:table column:ident row:row]);
    }
    return rel.name ?: @"";
  }
  if (table == self.memberTable && row >= 0 && (NSUInteger)row < _memberEntityNames.count) {
    NSString *name = _memberEntityNames[(NSUInteger)row];
    NSEntityDescription *rowEntity = self.model.entitiesByName[name];
    if ([ident isEqualToString:@"member"]) {
      if ([self selectedConfigurationIsImplicitDefault]) return @YES;
      NSString *configuration = [self selectedConfigurationName];
      if (!configuration) return @NO;
      for (NSEntityDescription *member in [self.model entitiesForConfiguration:configuration])
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
  NSString *ident = column.identifier;
  NSEntityDescription *entity = [self selectedEntity];

  /* A popup column hands back the index of the item chosen. */
  NSArray *choices = [self choicesForTable:table column:ident row:row];
  if (choices && [value isKindOfClass:[NSNumber class]]) {
    NSInteger index = [value integerValue];
    if (index < 0 || (NSUInteger)index >= choices.count) return;
    value = choices[(NSUInteger)index];
  }

  if (table == self.fetchIndexElementTable) {
    if (row < 0 || (NSUInteger)row >= _fetchIndexElementRows.count) return;
    NSString *choice = [value description];
    NSUInteger position = (NSUInteger)row;
    if ([ident isEqualToString:@"property"] &&
        [choice isEqualToString:[self fetchIndexElementTitle:_fetchIndexElementRows[position]]])
      return;
    [self changeSelectedFetchIndex:^(NSMutableDictionary *edited) {
              NSMutableArray *elements = [edited[@"elements"] mutableCopy];
              NSMutableDictionary *element = [elements[position] mutableCopy];
              if ([ident isEqualToString:@"type"]) {
                if ([choice isEqualToString:@"R-Tree"]) element[@"rtree"] = @YES;
                else [element removeObjectForKey:@"rtree"];
              } else if ([ident isEqualToString:@"order"]) {
                if ([choice isEqualToString:@"Descending"]) element[@"ascending"] = @NO;
                else [element removeObjectForKey:@"ascending"];
              } else {
                [element removeObjectForKey:@"expression"];
                element[@"property"] = choice;
              }
              elements[position] = element;
              edited[@"elements"] = elements;
            }
                            action:@"Edit Fetch Index Element"];
    return;
  }
  [_modelEditor beginEdit:@"Edit"];
  if (table == self.attributeTable && entity && (NSUInteger)row < _attributeNames.count) {
    MBAttributeEditor *editor = [MBAttributeEditor
        editorForAttributeNamed:_attributeNames[(NSUInteger)row]
                         entity:entity
                    modelEditor:_modelEditor];
    if ([ident isEqualToString:@"name"]) editor.name = [value description];
    else if ([ident isEqualToString:@"type"]) editor.typeName = [value description];
  } else if (table == self.relationshipTable && entity && (NSUInteger)row < _relationshipNames.count) {
    MBRelationshipEditor *editor = [MBRelationshipEditor
        editorForRelationshipNamed:_relationshipNames[(NSUInteger)row]
                            entity:entity
                       modelEditor:_modelEditor];
    if ([ident isEqualToString:@"name"]) editor.name = [value description];
    else if ([ident isEqualToString:@"destination"]) editor.destinationName = [value description];
    else if ([ident isEqualToString:@"inverse"]) editor.inverseName = [value description];
  } else if (table == self.memberTable && (NSUInteger)row < _memberEntityNames.count &&
             [ident isEqualToString:@"member"]) {
    NSString *configuration = [self selectedConfigurationName];
    NSError *error = nil;
    if (configuration &&
        ![_modelEditor setEntityNamed:_memberEntityNames[(NSUInteger)row]
                       inConfiguration:configuration
                                member:[value boolValue]
                                 error:&error])
      MBPresentModelError(error, @"Cannot change membership");
  }
  [_modelEditor endEdit];
  [_modelEditor noteModelChanged];
}

#pragma mark - NSTableViewDelegate

- (void)tableView:(NSTableView *)table willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  if (table == self.memberTable && [column.identifier isEqualToString:@"member"]) {
    /* Default is every entity; there is nothing to tick or untick. */
    [cell setEnabled:![self selectedConfigurationIsImplicitDefault]];
    return;
  }
  if (![cell isKindOfClass:[NSPopUpButtonCell class]]) return;
  NSArray *choices = [self choicesForTable:table column:column.identifier row:row];
  if (!choices) return;
  NSPopUpButtonCell *popup = cell;
  [popup removeAllItems];
  [popup addItemsWithTitles:choices];
  [popup selectItemAtIndex:[[self tableView:table objectValueForTableColumn:column row:row] integerValue]];
}

@end
