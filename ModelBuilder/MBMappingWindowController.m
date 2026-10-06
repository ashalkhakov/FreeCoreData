/* ModelBuilder mapping window.  See MBMappingWindowController.h.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingWindowController.h"
#import "MBMappingDocument.h"

@implementation MBMappingWindowController
{
  NSArray *_attributeMappings;      /* of the selected mapping, as shown */
  NSArray *_relationshipMappings;
}

- (MBMappingDocument *)mappingDocument
{
  return (MBMappingDocument *)[self document];
}

- (void)windowDidLoad
{
  [super windowDidLoad];
  [self reload];
}

- (void)setDocument:(id)document
{
  [super setDocument:document];
  if ([self isWindowLoaded]) [self reload];
}

/* -- what is shown --------------------------------------------------- */

- (NSEntityMapping *)selectedEntityMapping
{
  NSInteger row = [self.entityMappingTable selectedRow];
  NSArray *mappings = [[self mappingDocument] entityMappings];

  return (row >= 0 && row < (NSInteger)mappings.count) ? mappings[row] : nil;
}

- (void)reload
{
  MBMappingDocument *document = [self mappingDocument];

  [self.entityMappingTable reloadData];

  NSEntityMapping *mapping = [self selectedEntityMapping];

  if (mapping == nil && [[document entityMappings] count] > 0) {
    [self.entityMappingTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                         byExtendingSelection:NO];
    mapping = [self selectedEntityMapping];
  }

  _attributeMappings = mapping ? [document attributeMappingsOfEntityMapping:mapping] : @[];
  _relationshipMappings = mapping ? [document relationshipMappingsOfEntityMapping:mapping] : @[];

  [self.attributeMappingTable reloadData];
  [self.relationshipMappingTable reloadData];

  /* An added entity is fetched from nowhere, so there is nothing to
     narrow and nothing to type into. */
  BOOL fetches = ([mapping sourceEntityName].length > 0);

  [self.filterPredicateField setEnabled:fetches];
  [self.filterPredicateField setStringValue:
      (fetches ? ([document filterPredicateOfEntityMapping:mapping] ?: @"") : @"")];
  [self.filterPredicateField setPlaceholderString:fetches ? @"every object of the entity" : @""];

  [self.sourceModelLabel setStringValue:
      [[document sourceModelPath] lastPathComponent] ?: @""];
  [self.destinationModelLabel setStringValue:
      [[document destinationModelPath] lastPathComponent] ?: @""];

  [self.entityMappingSegmentedControl setEnabled:(mapping != nil) forSegment:1];
}

/* -- the tables ------------------------------------------------------ */

- (NSArray *)rowsForTable:(NSTableView *)table
{
  if (table == self.entityMappingTable) return [[self mappingDocument] entityMappings];
  if (table == self.attributeMappingTable) return _attributeMappings ?: @[];
  if (table == self.relationshipMappingTable) return _relationshipMappings ?: @[];
  return @[];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return (NSInteger)[[self rowsForTable:table] count];
}

- (id)tableView:(NSTableView *)table
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
  NSArray *rows = [self rowsForTable:table];

  if (row < 0 || row >= (NSInteger)rows.count) return nil;

  if (table == self.entityMappingTable) {
    NSEntityMapping *mapping = rows[row];

    return [mapping name] ?: @"";
  }

  NSPropertyMapping *property = rows[row];

  if ([[column identifier] isEqualToString:@"expression"])
    return [[self mappingDocument] valueExpressionStringOfPropertyMapping:property] ?: @"";

  return [property name] ?: @"";
}

/* Only an expression can be typed; a destination property is what it is. */
- (BOOL)tableView:(NSTableView *)table
    shouldEditTableColumn:(NSTableColumn *)column
                      row:(NSInteger)row
{
  return (table != self.entityMappingTable)
      && [[column identifier] isEqualToString:@"expression"];
}

- (void)tableView:(NSTableView *)table
   setObjectValue:(id)value
   forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row
{
  NSArray *rows = [self rowsForTable:table];

  if (table == self.entityMappingTable) return;
  if (row < 0 || row >= (NSInteger)rows.count) return;
  if (![[column identifier] isEqualToString:@"expression"]) return;

  NSPropertyMapping *property = rows[row];
  NSString *typed = [value isKindOfClass:[NSString class]] ? value : nil;
  NSError *error = nil;

  if (![[self mappingDocument] setValueExpressionString:typed
                                     ofPropertyMapping:property
                                                 error:&error]) {
    [self presentError:error];
    [table reloadData];
    return;
  }

  [table reloadData];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  if ([notification object] == self.entityMappingTable) [self reload];
}

/* -- the predicate --------------------------------------------------- */

- (IBAction)takeFilterPredicateFrom:(id)sender
{
  NSEntityMapping *mapping = [self selectedEntityMapping];

  if (mapping == nil) return;

  NSString *typed = [[sender stringValue] stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];

  [[self mappingDocument] setFilterPredicate:typed.length ? typed : nil
                            forEntityMapping:mapping];
  [self reload];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
  if ([notification object] == self.filterPredicateField)
    [self takeFilterPredicateFrom:self.filterPredicateField];
}

/* -- adding and removing --------------------------------------------- */

- (IBAction)entityMappingSegmentClicked:(id)sender
{
  if ([sender selectedSegment] == 0)
    [self addEntityMapping:sender];
  else
    [self removeEntityMapping:sender];
}

/* A new mapping starts out pairing the first entity of each model, which
   is a pairing to correct rather than a question to answer. */
- (IBAction)addEntityMapping:(id)sender
{
  MBMappingDocument *document = [self mappingDocument];
  NSArray *sourceNames = [[[document sourceModel] entitiesByName] allKeys];
  NSArray *destinationNames = [[[document destinationModel] entitiesByName] allKeys];
  NSString *source = [[sourceNames sortedArrayUsingSelector:@selector(compare:)] firstObject];
  NSString *destination = [[destinationNames sortedArrayUsingSelector:@selector(compare:)] firstObject];

  if (source == nil && destination == nil) return;

  NSEntityMapping *added = [document addEntityMappingFromEntityNamed:source
                                                      toEntityNamed:destination];

  [self reload];

  NSUInteger index = [[document entityMappings] indexOfObject:added];

  if (index != NSNotFound) {
    [self.entityMappingTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index]
                         byExtendingSelection:NO];
    [self reload];
  }
}

- (IBAction)removeEntityMapping:(id)sender
{
  NSEntityMapping *mapping = [self selectedEntityMapping];

  if (mapping == nil) return;

  [[self mappingDocument] removeEntityMapping:mapping];
  [self reload];
}

@end
