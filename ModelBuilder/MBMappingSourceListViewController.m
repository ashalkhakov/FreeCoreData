/* ModelBuilder — the mapping window's source list (see
   MBMappingSourceListViewController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingSourceListViewController.h"
#import "MBMappingEditor.h"

/* The source list's one group; its children are the entity mappings. */
static NSString *const MBEntityMappingsGroup = @"ENTITY MAPPINGS";

@implementation MBMappingSourceListViewController {
  BOOL _showing;   /* the selection being shown: the outline's selection changes are not the author's */
}

- (instancetype)init
{
  return [super initWithNibName:@"MBMappingSourceList" bundle:[NSBundle bundleForClass:[self class]]];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
  [super loadView];
  /* A click on the mapping already selected brings its own inspector
     back from a property's; a selection change would not. */
  self.sourceList.target = self;
  self.sourceList.action = @selector(sourceListClicked:);
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
    [center addObserver:self selector:@selector(selectionDidChange:)
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

- (void)selectionDidChange:(NSNotification *)notification
{
  (void)notification;
  [self showSelection];
}

- (void)reload
{
  _showing = YES;
  [self.sourceList reloadData];
  [self.sourceList expandItem:MBEntityMappingsGroup];
  _showing = NO;
  [self showSelection];
}

/* The selected mapping's row; where the selection names no mapping that
   is there (after a removal, or at first), the first mapping is selected. */
- (void)showSelection
{
  NSEntityMapping *mapping = [_mappingEditor selectedEntityMapping];
  if (!mapping) {
    NSEntityMapping *first = [_mappingEditor entityMappings].firstObject;
    MBMappingSelection *wanted = first ? [MBMappingSelection entityMappingNamed:[first name]] : nil;
    if (wanted && ![wanted isEqual:_mappingEditor.selection]) {
      _mappingEditor.selection = wanted;   /* shown when it is posted */
      return;
    }
  }
  NSInteger row = mapping ? [self.sourceList rowForItem:mapping] : -1;
  _showing = YES;
  if (row >= 0)
    [self.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  else
    [self.sourceList deselectAll:nil];
  _showing = NO;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  if (notification.object != self.sourceList || _showing) return;
  id item = [self.sourceList itemAtRow:[self.sourceList selectedRow]];
  if (![item isKindOfClass:[NSEntityMapping class]]) return;
  /* The same row picked again keeps what is selected within it. */
  if (item == [_mappingEditor selectedEntityMapping]) return;
  _mappingEditor.selection = [MBMappingSelection entityMappingNamed:[item name]];
}

- (void)sourceListClicked:(id)sender
{
  (void)sender;
  id item = [self.sourceList itemAtRow:[self.sourceList clickedRow]];
  if ([item isKindOfClass:[NSEntityMapping class]] &&
      _mappingEditor.selection.kind != MBMappingSelectionEntityMapping)
    _mappingEditor.selection = [MBMappingSelection entityMappingNamed:[item name]];
}

#pragma mark - Adding and removing

- (IBAction)addEntityMapping:(id)sender
{
  (void)sender;
  NSString *source = [_mappingEditor sourceEntityNames].firstObject;
  NSString *destination = [_mappingEditor destinationEntityNames].firstObject;
  if (source == nil && destination == nil) return;
  [_mappingEditor beginEdit:@"Add Entity Mapping"];
  NSEntityMapping *mapping = [_mappingEditor addEntityMappingFromEntityNamed:source toEntityNamed:destination];
  _mappingEditor.selection = [MBMappingSelection entityMappingNamed:[mapping name]];
  [_mappingEditor endEdit];
}

- (IBAction)removeEntityMapping:(id)sender
{
  (void)sender;
  NSEntityMapping *mapping = [_mappingEditor selectedEntityMapping];
  if (mapping == nil) return;
  NSArray *mappings = [_mappingEditor entityMappings];
  NSUInteger index = [mappings indexOfObjectIdenticalTo:mapping];
  [_mappingEditor beginEdit:@"Remove Entity Mapping"];
  [_mappingEditor removeEntityMapping:mapping];
  mappings = [_mappingEditor entityMappings];
  NSEntityMapping *neighbour = mappings.count ? mappings[MIN(index, mappings.count - 1)] : nil;
  _mappingEditor.selection = neighbour ? [MBMappingSelection entityMappingNamed:[neighbour name]] : nil;
  [_mappingEditor endEdit];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
  (void)outlineView;
  if (item == nil) return 1;
  if (item == MBEntityMappingsGroup) return (NSInteger)[[_mappingEditor entityMappings] count];
  return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
  (void)outlineView;
  if (item == nil) return MBEntityMappingsGroup;
  return [_mappingEditor entityMappings][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
  (void)outlineView;
  return item == MBEntityMappingsGroup;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
  (void)outlineView;
  (void)column;
  if (item == MBEntityMappingsGroup) return item;
  return [(NSEntityMapping *)item name] ?: @"";
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
  (void)outlineView;
  return item == MBEntityMappingsGroup;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
  (void)outlineView;
  return item != MBEntityMappingsGroup;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)column item:(id)item
{
  (void)outlineView;
  (void)column;
  return item != MBEntityMappingsGroup;
}

/* A rename to a name another mapping has is refused: names are how the
   window finds a mapping again. */
- (void)outlineView:(NSOutlineView *)outlineView
     setObjectValue:(id)value
     forTableColumn:(NSTableColumn *)column
             byItem:(id)item
{
  (void)outlineView;
  (void)column;
  if (item == MBEntityMappingsGroup || ![value isKindOfClass:[NSString class]]) return;
  NSString *name = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  [_mappingEditor setName:name ofEntityMapping:item];
  if (![[item name] isEqualToString:name]) [self reload];
}

@end
