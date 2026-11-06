/* ModelBuilder — the mapping window's centre (see
   MBMappingDetailViewController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingDetailViewController.h"
#import "MBMappingEditor.h"
#import "JUInspectorView.h"
#import "JUInspectorViewContainer.h"

@implementation MBMappingDetailViewController {
  BOOL _showing;   /* the selection being shown: the tables' selection changes are not the author's */
  NSArray *_attributeNames;      /* the rows, as shown */
  NSArray *_relationshipNames;
}

- (instancetype)init
{
  return [super initWithNibName:@"MBMappingDetail" bundle:[NSBundle bundleForClass:[self class]]];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
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
  [self reload];
}

- (void)mappingDidChange:(NSNotification *)notification
{
  (void)notification;
  [self reload];
}

- (void)reload
{
  NSEntityMapping *mapping = [_mappingEditor selectedEntityMapping];
  _attributeNames = mapping ? [_mappingEditor propertyNamesOfEntityMapping:mapping relationships:NO] : @[];
  _relationshipNames = mapping ? [_mappingEditor propertyNamesOfEntityMapping:mapping relationships:YES] : @[];

  MBMappingSelection *selection = _mappingEditor.selection;
  _showing = YES;
  [self.attributeMappingTable reloadData];
  [self.relationshipMappingTable reloadData];
  [self selectRow:selection.kind == MBMappingSelectionAttributeMapping ? selection.propertyName : nil
          inTable:self.attributeMappingTable rows:_attributeNames];
  [self selectRow:selection.kind == MBMappingSelectionRelationshipMapping ? selection.propertyName : nil
          inTable:self.relationshipMappingTable rows:_relationshipNames];
  _showing = NO;
}

- (void)selectRow:(NSString *)name inTable:(NSTableView *)table rows:(NSArray *)rows
{
  NSUInteger index = name ? [rows indexOfObject:name] : NSNotFound;
  if (index == NSNotFound)
    [table deselectAll:nil];
  else
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
}

- (NSArray *)rowsForTable:(NSTableView *)table
{
  return table == self.relationshipMappingTable ? _relationshipNames : _attributeNames;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return (NSInteger)[[self rowsForTable:table] count];
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSArray *rows = [self rowsForTable:table];
  if (row < 0 || row >= (NSInteger)rows.count) return nil;
  NSString *name = rows[(NSUInteger)row];
  if (![[column identifier] isEqualToString:@"expression"]) return name;
  /* What fills the property, written or worked out, as Xcode shows it. */
  NSPropertyMapping *property = [_mappingEditor propertyMappingNamed:name
                                                     inEntityMapping:[_mappingEditor selectedEntityMapping]
                                                       relationships:table == self.relationshipMappingTable];
  return [[property valueExpression] description] ?: @"";
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  (void)table;
  (void)row;
  return [[column identifier] isEqualToString:@"expression"];
}

- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSArray *rows = [self rowsForTable:table];
  if (row < 0 || row >= (NSInteger)rows.count || ![[column identifier] isEqualToString:@"expression"]) return;
  NSString *typed = [[value description] ?: @"" stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *name = rows[(NSUInteger)row];
  NSEntityMapping *mapping = [_mappingEditor selectedEntityMapping];
  BOOL relationships = table == self.relationshipMappingTable;
  NSPropertyMapping *property = [_mappingEditor propertyMappingNamed:name inEntityMapping:mapping
                                                       relationships:relationships];
  if ([typed isEqualToString:[[property valueExpression] description] ?: @""]) return;

  NSError *error = nil;
  [_mappingEditor beginEdit:@"Change Value Expression"];
  property = [_mappingEditor propertyMappingToEditNamed:name inEntityMapping:mapping relationships:relationships];
  BOOL set = [_mappingEditor setValueExpressionString:typed ofPropertyMapping:property error:&error];
  [_mappingEditor endEdit];
  if (!set) [self presentError:error];
}

#pragma mark - The selection

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  if (_showing) return;
  NSTableView *table = [notification object];
  if (table != self.attributeMappingTable && table != self.relationshipMappingTable) return;

  BOOL relationships = table == self.relationshipMappingTable;
  MBMappingSelection *selection = _mappingEditor.selection;
  NSString *mappingName = [[_mappingEditor selectedEntityMapping] name];
  NSInteger row = [table selectedRow];
  NSArray *rows = [self rowsForTable:table];

  if (row >= 0 && row < (NSInteger)rows.count) {
    _mappingEditor.selection = [MBMappingSelection
        selectionOfKind:relationships ? MBMappingSelectionRelationshipMapping : MBMappingSelectionAttributeMapping
      entityMappingName:mappingName
           propertyName:rows[(NSUInteger)row]];
  } else if ((selection.kind == MBMappingSelectionRelationshipMapping) == relationships &&
             selection.kind != MBMappingSelectionEntityMapping) {
    /* its own row deselected, not the other table's for this one */
    _mappingEditor.selection = mappingName ? [MBMappingSelection entityMappingNamed:mappingName] : nil;
  }
}

@end
