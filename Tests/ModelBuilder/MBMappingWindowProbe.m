/* Window probe for ModelBuilder's mapping editor: the mapping model Xcode
   made, opened in a real window loaded from MBMappingWindow.xib and driven
   through its tables and fields as a user would.  Needs a display (run
   under xvfb-run); scenario framing as in MBWindowProbe.m.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBMappingDocument.h"
#import "MBMappingWindowController.h"

static int passed = 0, failed = 0;
#define CHECK(cond, name) do { \
  if (cond) { passed++; printf("  ok   %s\n", name); } \
  else { failed++; printf("  FAIL %s\n", name); } \
} while (0)
#define SCENARIO(title) printf("\nScenario: %s\n", title)

static NSString *fixturePath(void)
{
  NSString *directory = [[NSFileManager defaultManager] currentDirectoryPath];

  for (int i = 0; i < 8; i++) {
    NSString *candidate = [directory stringByAppendingPathComponent:
        @"Tests/MappingFixture.xcmappingmodel"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    directory = [directory stringByDeletingLastPathComponent];
  }
  return nil;
}

static id cell(NSTableView *table, NSString *column, NSInteger row)
{
  NSTableColumn *tc = [table tableColumnWithIdentifier:column];

  return [[table dataSource] tableView:table objectValueForTableColumn:tc row:row];
}

static NSInteger rowNamed(NSTableView *table, NSString *column, NSString *name)
{
  NSInteger rows = [[table dataSource] numberOfRowsInTableView:table];

  for (NSInteger row = 0; row < rows; row++)
    if ([cell(table, column, row) isEqual:name]) return row;
  return -1;
}

static void selectRow(NSTableView *table, NSInteger row)
{
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

int main(void)
{
  @autoreleasepool {
    [NSApplication sharedApplication];

    NSString *fixture = fixturePath();
    MBMappingDocument *doc = [[MBMappingDocument alloc] init];
    NSError *error = nil;

    SCENARIO("Opening a mapping model loads its window from the nib");
    /* GIVEN the mapping model made in Xcode's editor
       WHEN it opens and makes its window controller
       THEN the window loads from MBMappingWindow.xib with every outlet
            connected and the three mappings listed */
    BOOL ok = fixture && [doc readFromURL:[NSURL fileURLWithPath:fixture]
                                   ofType:@"Core Data Mapping Model"
                                    error:&error];
    CHECK(ok, "open the fixture");
    if (!ok) {
      printf("  (%s)\n", [[error description] UTF8String]);
      return 1;
    }

    [doc makeWindowControllers];
    MBMappingWindowController *wc = doc.windowControllers.firstObject;
    NSWindow *window = [wc window];

    CHECK(window != nil, "window loads from nib");
    CHECK(wc.entityMappingTable != nil, "entityMappingTable outlet");
    CHECK(wc.entityMappingSegmentedControl != nil, "entityMappingSegmentedControl outlet");
    CHECK(wc.filterPredicateField != nil, "filterPredicateField outlet");
    CHECK(wc.attributeMappingTable != nil, "attributeMappingTable outlet");
    CHECK(wc.relationshipMappingTable != nil, "relationshipMappingTable outlet");
    CHECK(wc.sourceModelLabel != nil, "sourceModelLabel outlet");
    CHECK(wc.destinationModelLabel != nil, "destinationModelLabel outlet");
    CHECK([[wc.entityMappingTable dataSource] numberOfRowsInTableView:wc.entityMappingTable] == 3,
          "three entity mappings listed");
    CHECK([[wc.sourceModelLabel stringValue] isEqualToString:@"MappingFixture.xcdatamodel"],
          "the source model is named at the bottom");
    CHECK([[wc.destinationModelLabel stringValue] isEqualToString:@"MappingFixture 2.xcdatamodel"],
          "and the destination model");

    SCENARIO("A mapping's properties and the predicate that narrows it");
    /* WHEN NoteToNote is selected
       THEN its predicate is in the field, every destination attribute
            has a row, and only the expression written by hand shows */
    NSInteger notes = rowNamed(wc.entityMappingTable, @"name", @"NoteToNote");
    CHECK(notes >= 0, "NoteToNote is in the list");
    selectRow(wc.entityMappingTable, notes);

    CHECK([[wc.filterPredicateField stringValue] isEqualToString:@"text BEGINSWITH \"keep\""],
          "its predicate fills the field");
    CHECK([wc.filterPredicateField isEnabled], "and the field can be edited");
    CHECK([[wc.attributeMappingTable dataSource] numberOfRowsInTableView:wc.attributeMappingTable] == 2,
          "both destination attributes have a row");

    NSInteger writer = rowNamed(wc.attributeMappingTable, @"property", @"writer");
    NSInteger text = rowNamed(wc.attributeMappingTable, @"property", @"text");
    CHECK(writer >= 0 && [cell(wc.attributeMappingTable, @"expression", writer)
                              isEqualToString:@"$source.author"],
          "the rename written by hand shows");
    CHECK(text >= 0 && [cell(wc.attributeMappingTable, @"expression", text) isEqual:@""],
          "the derived one is a blank cell");
    CHECK([[wc.relationshipMappingTable dataSource] numberOfRowsInTableView:wc.relationshipMappingTable] == 1,
          "the relationship has a row");

    SCENARIO("Typing an expression into a cell, and undoing it");
    NSTableColumn *expression = [wc.attributeMappingTable tableColumnWithIdentifier:@"expression"];
    CHECK([[wc.attributeMappingTable delegate] tableView:wc.attributeMappingTable
                                   shouldEditTableColumn:expression row:text],
          "the expression column is editable");
    CHECK(![[wc.attributeMappingTable delegate] tableView:wc.attributeMappingTable
                                    shouldEditTableColumn:[wc.attributeMappingTable tableColumnWithIdentifier:@"property"]
                                                      row:text],
          "the property column is not");

    [[wc.attributeMappingTable dataSource] tableView:wc.attributeMappingTable
                                      setObjectValue:@"$source.author"
                                      forTableColumn:expression
                                                 row:text];
    CHECK([cell(wc.attributeMappingTable, @"expression", text) isEqualToString:@"$source.author"],
          "the typed expression is kept");
    CHECK([doc isDocumentEdited], "and the document is edited");

    [[doc undoManager] undo];
    [wc reload];
    CHECK([cell(wc.attributeMappingTable, @"expression", text) isEqual:@""],
          "undo gives the blank back");

    SCENARIO("Narrowing a mapping from the predicate field");
    [wc.filterPredicateField setStringValue:@"text BEGINSWITH \"drop\""];
    [wc takeFilterPredicateFrom:wc.filterPredicateField];
    CHECK([[doc filterPredicateOfEntityMapping:wc.selectedEntityMapping]
              isEqualToString:@"text BEGINSWITH \"drop\""],
          "the document takes the new predicate");

    [[doc undoManager] undo];
    [wc reload];
    CHECK([[wc.filterPredicateField stringValue] isEqualToString:@"text BEGINSWITH \"keep\""],
          "undo puts the old one back in the field");

    SCENARIO("An added entity has nothing to narrow");
    NSInteger fresh = rowNamed(wc.entityMappingTable, @"name", @"Fresh");
    CHECK(fresh >= 0, "Fresh is in the list");
    selectRow(wc.entityMappingTable, fresh);
    CHECK(![wc.filterPredicateField isEnabled], "and its predicate field is disabled");

    SCENARIO("A mapping added and removed from the bottom bar");
    NSInteger before = [[wc.entityMappingTable dataSource] numberOfRowsInTableView:wc.entityMappingTable];

    [wc.entityMappingSegmentedControl setSelectedSegment:0];
    [wc entityMappingSegmentClicked:wc.entityMappingSegmentedControl];
    CHECK([[wc.entityMappingTable dataSource] numberOfRowsInTableView:wc.entityMappingTable] == before + 1,
          "+ adds a mapping");

    [wc.entityMappingSegmentedControl setSelectedSegment:1];
    [wc entityMappingSegmentClicked:wc.entityMappingSegmentedControl];
    CHECK([[wc.entityMappingTable dataSource] numberOfRowsInTableView:wc.entityMappingTable] == before,
          "− removes the selected one");

    printf("\n---\n%d passed, %d failed\n", passed, failed);
    return failed == 0 ? 0 : 1;
  }
}
