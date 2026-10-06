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

static NSEntityMapping *mappingNamed(MBMappingDocument *doc, NSString *name)
{
  for (NSEntityMapping *mapping in [doc entityMappings])
    if ([[mapping name] isEqualToString:name]) return mapping;
  return nil;
}

static NSInteger inspectorKind(MBMappingWindowController *wc)
{
  return [wc.inspectorKindTabView indexOfTabViewItem:[wc.inspectorKindTabView selectedTabViewItem]];
}

/* What a user does to a text field: type, then leave it. */
static void type(MBMappingWindowController *wc, NSTextField *field, NSString *text)
{
  [field setStringValue:text];
  [wc inspectorChanged:field];
}

static void choose(MBMappingWindowController *wc, NSPopUpButton *popup, NSString *title)
{
  [popup selectItemWithTitle:title];
  [wc inspectorChanged:popup];
}

static NSInteger listedMappings(MBMappingWindowController *wc)
{
  NSOutlineView *list = wc.sourceList;
  id group = [[list dataSource] outlineView:list child:0 ofItem:nil];

  return [[list dataSource] outlineView:list numberOfChildrenOfItem:group];
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
            connected, the three mappings listed, and the models named */
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
    struct { const char *name; id outlet; } outlets[] = {
      { "sourceList", wc.sourceList },
      { "entityMappingSegmentedControl", wc.entityMappingSegmentedControl },
      { "mappingInspectorContainer", wc.mappingInspectorContainer },
      { "attributesInspector", wc.attributesInspector },
      { "relationshipsInspector", wc.relationshipsInspector },
      { "attributeMappingTable", wc.attributeMappingTable },
      { "relationshipMappingTable", wc.relationshipMappingTable },
      { "inspectorTabBar", wc.inspectorTabBar },
      { "inspectorTabView", wc.inspectorTabView },
      { "inspectorKindTabView", wc.inspectorKindTabView },
      { "sourceModelLabel", wc.sourceModelLabel },
      { "destinationModelLabel", wc.destinationModelLabel },
      { "entityMappingNameField", wc.entityMappingNameField },
      { "sourceEntityPopup", wc.sourceEntityPopup },
      { "destinationEntityPopup", wc.destinationEntityPopup },
      { "mappingTypeLabel", wc.mappingTypeLabel },
      { "customPolicyField", wc.customPolicyField },
      { "sourceFetchPopup", wc.sourceFetchPopup },
      { "filterPredicateField", wc.filterPredicateField },
      { "entityUserInfoTable", wc.entityUserInfoTable },
      { "entityUserInfoSegmentedControl", wc.entityUserInfoSegmentedControl },
      { "attributeNamePopup", wc.attributeNamePopup },
      { "attributeExpressionField", wc.attributeExpressionField },
      { "attributeUserInfoTable", wc.attributeUserInfoTable },
      { "attributeUserInfoSegmentedControl", wc.attributeUserInfoSegmentedControl },
      { "relationshipNamePopup", wc.relationshipNamePopup },
      { "relationshipSourceFetchPopup", wc.relationshipSourceFetchPopup },
      { "relationshipKeyPathField", wc.relationshipKeyPathField },
      { "relationshipMappingNameField", wc.relationshipMappingNameField },
      { "relationshipExpressionField", wc.relationshipExpressionField },
      { "relationshipUserInfoTable", wc.relationshipUserInfoTable },
      { "relationshipUserInfoSegmentedControl", wc.relationshipUserInfoSegmentedControl },
    };
    int missing = 0;
    for (unsigned i = 0; i < sizeof(outlets) / sizeof(outlets[0]); i++)
      if (outlets[i].outlet == nil) {
        missing++;
        printf("  (outlet %s is not connected)\n", outlets[i].name);
      }
    CHECK(missing == 0, "every outlet is connected");
    CHECK([wc.inspectorKindTabView numberOfTabViewItems] == 3,
          "the inspector has an entity, an attribute and a relationship page");
    CHECK(listedMappings(wc) == 3, "three entity mappings listed");
    CHECK([[wc.sourceModelLabel stringValue] hasSuffix:@"MappingFixture.xcdatamodel"],
          "Identity names the source model");
    CHECK([[wc.destinationModelLabel stringValue] hasSuffix:@"MappingFixture 2.xcdatamodel"],
          "and the destination model");

    SCENARIO("Selecting an entity mapping inspects it");
    /* WHEN NoteToNote is selected in the list
       THEN the inspector's entity page shows its name, its two entities,
            its type, and the predicate that narrows it, and the center
            lists what fills each destination property */
    [wc selectEntityMapping:mappingNamed(doc, @"NoteToNote")];
    CHECK(inspectorKind(wc) == MBMappingInspectorKindEntity, "the entity mapping page shows");
    CHECK([[wc.entityMappingNameField stringValue] isEqualToString:@"NoteToNote"], "its name");
    CHECK([[wc.sourceEntityPopup titleOfSelectedItem] isEqualToString:@"Note"], "its source entity");
    CHECK([[wc.destinationEntityPopup titleOfSelectedItem] isEqualToString:@"Note"], "its destination entity");
    CHECK([[wc.mappingTypeLabel stringValue] isEqualToString:@"Transform"], "its type, Transform");
    CHECK([wc.sourceFetchPopup indexOfSelectedItem] == 1, "a custom source fetch");
    CHECK([[wc.filterPredicateField stringValue] isEqualToString:@"text BEGINSWITH \"keep\""]
              && [wc.filterPredicateField isEnabled],
          "whose predicate is in the field, to edit");
    CHECK([[wc.attributeMappingTable dataSource] numberOfRowsInTableView:wc.attributeMappingTable] == 2,
          "both destination attributes have a row");

    NSInteger writer = rowNamed(wc.attributeMappingTable, @"property", @"writer");
    NSInteger text = rowNamed(wc.attributeMappingTable, @"property", @"text");
    CHECK(writer >= 0 && [cell(wc.attributeMappingTable, @"expression", writer)
                              isEqualToString:@"$source.author"],
          "the rename written by hand shows");
    CHECK(text >= 0 && [cell(wc.attributeMappingTable, @"expression", text)
                            isEqualToString:@"$source.text"],
          "and the one worked out from the name");
    CHECK([[wc.relationshipMappingTable dataSource] numberOfRowsInTableView:wc.relationshipMappingTable] == 1,
          "the relationship has a row");

    SCENARIO("Selecting an attribute mapping inspects it");
    selectRow(wc.attributeMappingTable, writer);
    CHECK(inspectorKind(wc) == MBMappingInspectorKindAttribute, "the attribute mapping page shows");
    CHECK([[wc.attributeNamePopup titleOfSelectedItem] isEqualToString:@"writer"],
          "the destination attribute is chosen in its popup");
    CHECK([[wc.attributeNamePopup itemTitles] containsObject:@"text"],
          "which offers the entity's other attributes");
    CHECK([[wc.attributeExpressionField stringValue] isEqualToString:@"$source.author"],
          "its value expression is in the field");

    selectRow(wc.attributeMappingTable, text);
    CHECK([[wc.attributeExpressionField stringValue] isEqualToString:@""]
              && [[[wc.attributeExpressionField cell] placeholderString] isEqualToString:@"$source.text"],
          "one worked out leaves the field empty, showing what it works out to");

    SCENARIO("Typing a value expression, and undoing it");
    type(wc, wc.attributeExpressionField, @"$source.author");
    CHECK([cell(wc.attributeMappingTable, @"expression", text) isEqualToString:@"$source.author"],
          "the center shows what was typed");
    CHECK([doc isDocumentEdited], "and the document is edited");
    [[doc undoManager] undo];
    CHECK([cell(wc.attributeMappingTable, @"expression", text) isEqualToString:@"$source.text"],
          "undo gives back the one worked out");

    NSTableColumn *expression = [wc.attributeMappingTable tableColumnWithIdentifier:@"expression"];
    CHECK([[wc.attributeMappingTable delegate] tableView:wc.attributeMappingTable
                                   shouldEditTableColumn:expression row:text],
          "the center's expression column is editable");
    [[wc.attributeMappingTable dataSource] tableView:wc.attributeMappingTable
                                      setObjectValue:@"$source.author"
                                      forTableColumn:expression
                                                 row:text];
    CHECK([[doc valueExpressionStringOfPropertyMapping:wc.selectedPropertyMapping]
              isEqualToString:@"$source.author"],
          "typing into its cell sets the expression too");
    [[doc undoManager] undo];

    SCENARIO("Selecting a relationship mapping inspects it");
    /* THEN the relationship's expression is shown as Xcode's inspector
       shows it: generated, through a key path and an entity mapping */
    selectRow(wc.relationshipMappingTable, 0);
    CHECK(inspectorKind(wc) == MBMappingInspectorKindRelationship, "the relationship mapping page shows");
    CHECK(wc.attributeMappingTable.selectedRow < 0, "and the attribute row is let go");
    CHECK([[wc.relationshipNamePopup titleOfSelectedItem] isEqualToString:@"tags"], "its relationship");
    CHECK([wc.relationshipSourceFetchPopup indexOfSelectedItem] == 0, "auto generated");
    CHECK([[wc.relationshipKeyPathField stringValue] isEqualToString:@"tags"], "through the key path tags");
    CHECK([[wc.relationshipMappingNameField stringValue] isEqualToString:@"TagToTag"], "and TagToTag");
    CHECK(![wc.relationshipExpressionField isEnabled], "with no expression to type");

    type(wc, wc.relationshipMappingNameField, @"Other");
    NSString *through = nil;
    [doc relationshipMapping:wc.selectedPropertyMapping
             inEntityMapping:wc.selectedEntityMapping
                     keyPath:NULL
                 mappingName:&through];
    CHECK([through isEqualToString:@"Other"], "a mapping name typed is the one filled through");
    [[doc undoManager] undo];
    CHECK([[wc.relationshipMappingNameField stringValue] isEqualToString:@"TagToTag"],
          "undo puts TagToTag back in the field");

    choose(wc, wc.relationshipSourceFetchPopup, @"Custom Value Expression");
    CHECK([wc.relationshipExpressionField isEnabled] && ![wc.relationshipKeyPathField isEnabled],
          "Custom swaps the key path for an expression to type");
    choose(wc, wc.relationshipSourceFetchPopup, @"Auto Generate Value Expression");
    CHECK([[wc.relationshipMappingNameField stringValue] isEqualToString:@"TagToTag"],
          "and back again, it is generated as before");

    SCENARIO("Clicking the entity mapping again inspects it again");
    [wc selectEntityMapping:wc.selectedEntityMapping];
    CHECK(inspectorKind(wc) == MBMappingInspectorKindEntity && wc.selectedPropertyMapping == nil,
          "the entity mapping page is back");

    SCENARIO("Narrowing a mapping from the inspector");
    type(wc, wc.filterPredicateField, @"text BEGINSWITH \"drop\"");
    CHECK([[doc filterPredicateOfEntityMapping:wc.selectedEntityMapping]
              isEqualToString:@"text BEGINSWITH \"drop\""],
          "the document takes the new predicate");
    [[doc undoManager] undo];
    CHECK([[wc.filterPredicateField stringValue] isEqualToString:@"text BEGINSWITH \"keep\""],
          "undo puts the old one back in the field");
    choose(wc, wc.sourceFetchPopup, @"Default");
    CHECK([doc filterPredicateOfEntityMapping:wc.selectedEntityMapping] == nil
              && ![wc.filterPredicateField isEnabled],
          "the default fetch takes every object");
    [[doc undoManager] undo];

    SCENARIO("The policy, the name and user info");
    type(wc, wc.customPolicyField, @"NotePolicy");
    CHECK([[wc.selectedEntityMapping entityMigrationPolicyClassName] isEqualToString:@"NotePolicy"],
          "a custom policy is set");
    [wc.entityUserInfoSegmentedControl setSelectedSegment:0];
    [wc userInfoSegmentClicked:wc.entityUserInfoSegmentedControl];
    CHECK([[wc.entityUserInfoTable dataSource] numberOfRowsInTableView:wc.entityUserInfoTable] == 1,
          "+ adds a user info entry");
    [[wc.entityUserInfoTable dataSource] tableView:wc.entityUserInfoTable
                                    setObjectValue:@"kept"
                                    forTableColumn:[wc.entityUserInfoTable tableColumnWithIdentifier:@"value"]
                                               row:0];
    CHECK([[[wc.selectedEntityMapping userInfo] objectForKey:@"key"] isEqual:@"kept"],
          "whose value is typed in its row");
    type(wc, wc.entityMappingNameField, @"KeepNotes");
    CHECK(mappingNamed(doc, @"KeepNotes") != nil, "the mapping is renamed from the name field");

    /* Beside the fixture: the models are found by the paths the file
       records, which are the project's. */
    NSString *saved = [[fixture stringByDeletingLastPathComponent] stringByAppendingPathComponent:
        [NSString stringWithFormat:@"probe-%d.xcmappingmodel", (int)getpid()]];
    [[NSFileManager defaultManager] removeItemAtPath:saved error:NULL];
    ok = [doc writeToURL:[NSURL fileURLWithPath:saved] ofType:@"Core Data Mapping Model" error:&error];
    MBMappingDocument *again = [[MBMappingDocument alloc] init];
    ok = ok && [again readFromURL:[NSURL fileURLWithPath:saved] ofType:@"Core Data Mapping Model" error:&error];
    NSEntityMapping *reread = ok ? mappingNamed(again, @"KeepNotes") : nil;
    if (reread == nil || ![[reread entityMigrationPolicyClassName] isEqualToString:@"NotePolicy"]
        || ![[[reread userInfo] objectForKey:@"key"] isEqual:@"kept"])
      printf("  (saved: %s; read back %s, policy %s, user info %s)\n", ok ? "yes" : [[error description] UTF8String],
             [[reread name] UTF8String] ?: "nothing", [[reread entityMigrationPolicyClassName] UTF8String] ?: "none",
             [[[reread userInfo] description] UTF8String] ?: "none");
    CHECK(reread != nil
              && [[reread entityMigrationPolicyClassName] isEqualToString:@"NotePolicy"]
              && [[[reread userInfo] objectForKey:@"key"] isEqual:@"kept"],
          "and the name, the policy and the user info survive a save");
    [[NSFileManager defaultManager] removeItemAtPath:saved error:NULL];

    SCENARIO("An added entity has nothing to fetch");
    [wc selectEntityMapping:mappingNamed(doc, @"Fresh")];
    CHECK([[wc.mappingTypeLabel stringValue] isEqualToString:@"Add"], "its type is Add");
    CHECK([[wc.sourceEntityPopup titleOfSelectedItem] isEqualToString:@"None"], "it has no source");
    CHECK(![wc.sourceFetchPopup isEnabled] && ![wc.filterPredicateField isEnabled],
          "so nothing to fetch and nothing to narrow");

    SCENARIO("Pairing other entities changes the type");
    choose(wc, wc.sourceEntityPopup, @"Note");
    CHECK([[wc.selectedEntityMapping sourceEntityName] isEqualToString:@"Note"]
              && [[wc.mappingTypeLabel stringValue] isEqualToString:@"Transform"],
          "a source chosen makes it a transform");
    CHECK([wc.sourceFetchPopup isEnabled], "and now there is something to fetch");
    [[doc undoManager] undo];
    CHECK([[wc.mappingTypeLabel stringValue] isEqualToString:@"Add"], "undo makes it an add again");

    SCENARIO("A mapping added and removed from the bottom bar");
    NSInteger before = listedMappings(wc);

    [wc.entityMappingSegmentedControl setSelectedSegment:0];
    [wc entityMappingSegmentClicked:wc.entityMappingSegmentedControl];
    CHECK(listedMappings(wc) == before + 1, "+ adds a mapping");
    CHECK(inspectorKind(wc) == MBMappingInspectorKindEntity, "and inspects it");

    [wc.entityMappingSegmentedControl setSelectedSegment:1];
    [wc entityMappingSegmentClicked:wc.entityMappingSegmentedControl];
    CHECK(listedMappings(wc) == before, "− removes the selected one");

    printf("\n---\n%d passed, %d failed\n", passed, failed);
    return failed == 0 ? 0 : 1;
  }
}
