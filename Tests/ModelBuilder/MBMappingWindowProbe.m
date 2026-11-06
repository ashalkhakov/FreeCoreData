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
#import "MBMappingEditor.h"
#import "MBMappingSourceListViewController.h"
#import "MBMappingDetailViewController.h"
#import "MBMappingInspectorViewController.h"
#import "MBNewMappingController.h"

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
  return [doc.mappingEditor entityMappingNamed:name];
}

static NSInteger inspectorKind(MBMappingWindowController *wc)
{
  NSTabView *kinds = wc.inspectorController.inspectorKindTabView;
  return [kinds indexOfTabViewItem:[kinds selectedTabViewItem]];
}

/* What a user does to a text field: type, then leave it - the field's
   value given to what it is bound to, as its action does. */
static void type(MBMappingWindowController *wc, NSTextField *field, NSString *text)
{
  (void)wc;
  [field setStringValue:text];
  [field sendAction:field.action to:field.target];
}

static void choose(MBMappingWindowController *wc, NSPopUpButton *popup, NSString *title)
{
  (void)wc;
  [popup selectItemWithTitle:title];
  [popup sendAction:popup.action to:popup.target];
}

static void selectMapping(MBMappingWindowController *wc, NSEntityMapping *mapping)
{
  wc.mappingEditor.selection = [MBMappingSelection entityMappingNamed:[mapping name]];
}

static NSEntityMapping *selectedMapping(MBMappingWindowController *wc)
{
  return [wc.mappingEditor selectedEntityMapping];
}

/* The selected row's property mapping (nil while nothing fills it). */
static NSPropertyMapping *selectedProperty(MBMappingWindowController *wc)
{
  MBMappingSelection *selection = wc.mappingEditor.selection;
  if (selection.kind != MBMappingSelectionAttributeMapping && selection.kind != MBMappingSelectionRelationshipMapping)
    return nil;
  return [wc.mappingEditor propertyMappingNamed:selection.propertyName inEntityMapping:selectedMapping(wc)
                                  relationships:selection.kind == MBMappingSelectionRelationshipMapping];
}

static NSButton *buttonTitled(NSView *view, NSString *title)
{
  if ([view isKindOfClass:[NSButton class]] && [[(NSButton *)view title] isEqualToString:title])
    return (NSButton *)view;
  for (NSView *subview in [view subviews]) {
    NSButton *found = buttonTitled(subview, title);
    if (found) return found;
  }
  return nil;
}

static NSInteger listedMappings(MBMappingWindowController *wc)
{
  NSOutlineView *list = wc.sourceListController.sourceList;
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
      { "sourceList", wc.sourceListController.sourceList },
      { "entityMappingSegmentedControl", wc.entityMappingSegmentedControl },
      { "mappingInspectorContainer", wc.detailController.mappingInspectorContainer },
      { "attributesInspector", wc.detailController.attributesInspector },
      { "relationshipsInspector", wc.detailController.relationshipsInspector },
      { "attributeMappingTable", wc.detailController.attributeMappingTable },
      { "relationshipMappingTable", wc.detailController.relationshipMappingTable },
      { "inspectorTabBar", wc.inspectorController.inspectorTabBar },
      { "inspectorTabView", wc.inspectorController.inspectorTabView },
      { "inspectorKindTabView", wc.inspectorController.inspectorKindTabView },
      { "sourceModelLabel", wc.inspectorController.sourceModelLabel },
      { "destinationModelLabel", wc.inspectorController.destinationModelLabel },
      { "entityMappingNameField", wc.inspectorController.entityMappingNameField },
      { "sourceEntityPopup", wc.inspectorController.sourceEntityPopup },
      { "destinationEntityPopup", wc.inspectorController.destinationEntityPopup },
      { "mappingTypeLabel", wc.inspectorController.mappingTypeLabel },
      { "customPolicyField", wc.inspectorController.customPolicyField },
      { "sourceFetchPopup", wc.inspectorController.sourceFetchPopup },
      { "filterPredicateField", wc.inspectorController.filterPredicateField },
      { "entityUserInfoTable", wc.inspectorController.entityUserInfoTable },
      { "entityUserInfoSegmentedControl", wc.inspectorController.entityUserInfoSegmentedControl },
      { "attributeNamePopup", wc.inspectorController.attributeNamePopup },
      { "attributeExpressionField", wc.inspectorController.attributeExpressionField },
      { "attributeUserInfoTable", wc.inspectorController.attributeUserInfoTable },
      { "attributeUserInfoSegmentedControl", wc.inspectorController.attributeUserInfoSegmentedControl },
      { "relationshipNamePopup", wc.inspectorController.relationshipNamePopup },
      { "relationshipSourceFetchPopup", wc.inspectorController.relationshipSourceFetchPopup },
      { "relationshipKeyPathField", wc.inspectorController.relationshipKeyPathField },
      { "relationshipMappingNameField", wc.inspectorController.relationshipMappingNameField },
      { "relationshipExpressionField", wc.inspectorController.relationshipExpressionField },
      { "relationshipUserInfoTable", wc.inspectorController.relationshipUserInfoTable },
      { "relationshipUserInfoSegmentedControl", wc.inspectorController.relationshipUserInfoSegmentedControl },
    };
    int missing = 0;
    for (unsigned i = 0; i < sizeof(outlets) / sizeof(outlets[0]); i++)
      if (outlets[i].outlet == nil) {
        missing++;
        printf("  (outlet %s is not connected)\n", outlets[i].name);
      }
    CHECK(missing == 0, "every outlet is connected");
    CHECK([wc.inspectorController.inspectorKindTabView numberOfTabViewItems] == 3,
          "the inspector has an entity, an attribute and a relationship page");
    CHECK(listedMappings(wc) == 3, "three entity mappings listed");
    CHECK([[wc.inspectorController.sourceModelLabel stringValue] hasSuffix:@"MappingFixture.xcdatamodel"],
          "Identity names the source model");
    CHECK([[wc.inspectorController.destinationModelLabel stringValue] hasSuffix:@"MappingFixture 2.xcdatamodel"],
          "and the destination model");

    SCENARIO("Selecting an entity mapping inspects it");
    /* WHEN NoteToNote is selected in the list
       THEN the inspector's entity page shows its name, its two entities,
            its type, and the predicate that narrows it, and the center
            lists what fills each destination property */
    selectMapping(wc, mappingNamed(doc, @"NoteToNote"));
    CHECK(inspectorKind(wc) == MBMappingInspectorKindEntity, "the entity mapping page shows");
    CHECK([[wc.inspectorController.entityMappingNameField stringValue] isEqualToString:@"NoteToNote"], "its name");
    CHECK([[wc.inspectorController.sourceEntityPopup titleOfSelectedItem] isEqualToString:@"Note"], "its source entity");
    CHECK([[wc.inspectorController.destinationEntityPopup titleOfSelectedItem] isEqualToString:@"Note"], "its destination entity");
    CHECK([[wc.inspectorController.mappingTypeLabel stringValue] isEqualToString:@"Transform"], "its type, Transform");
    CHECK([wc.inspectorController.sourceFetchPopup indexOfSelectedItem] == 1, "a custom source fetch");
    CHECK([[wc.inspectorController.filterPredicateField stringValue] isEqualToString:@"text BEGINSWITH \"keep\""]
              && [wc.inspectorController.filterPredicateField isEnabled],
          "whose predicate is in the field, to edit");
    CHECK([[wc.detailController.attributeMappingTable dataSource] numberOfRowsInTableView:wc.detailController.attributeMappingTable] == 2,
          "both destination attributes have a row");

    NSInteger writer = rowNamed(wc.detailController.attributeMappingTable, @"property", @"writer");
    NSInteger text = rowNamed(wc.detailController.attributeMappingTable, @"property", @"text");
    CHECK(writer >= 0 && [cell(wc.detailController.attributeMappingTable, @"expression", writer)
                              isEqualToString:@"$source.author"],
          "the rename written by hand shows");
    CHECK(text >= 0 && [cell(wc.detailController.attributeMappingTable, @"expression", text)
                            isEqualToString:@"$source.text"],
          "and the one worked out from the name");
    CHECK([[wc.detailController.relationshipMappingTable dataSource] numberOfRowsInTableView:wc.detailController.relationshipMappingTable] == 1,
          "the relationship has a row");

    SCENARIO("Selecting an attribute mapping inspects it");
    selectRow(wc.detailController.attributeMappingTable, writer);
    CHECK(inspectorKind(wc) == MBMappingInspectorKindAttribute, "the attribute mapping page shows");
    CHECK([[wc.inspectorController.attributeNamePopup titleOfSelectedItem] isEqualToString:@"writer"],
          "the destination attribute is chosen in its popup");
    CHECK([[wc.inspectorController.attributeNamePopup itemTitles] containsObject:@"text"],
          "which offers the entity's other attributes");
    CHECK([[wc.inspectorController.attributeExpressionField stringValue] isEqualToString:@"$source.author"],
          "its value expression is in the field");

    selectRow(wc.detailController.attributeMappingTable, text);
    CHECK([[wc.inspectorController.attributeExpressionField stringValue] isEqualToString:@""]
              && [[[wc.inspectorController.attributeExpressionField cell] placeholderString] isEqualToString:@"$source.text"],
          "one worked out leaves the field empty, showing what it works out to");

    SCENARIO("Typing a value expression, and undoing it");
    type(wc, wc.inspectorController.attributeExpressionField, @"$source.author");
    CHECK([cell(wc.detailController.attributeMappingTable, @"expression", text) isEqualToString:@"$source.author"],
          "the center shows what was typed");
    CHECK([doc isDocumentEdited], "and the document is edited");
    [[doc undoManager] undo];
    CHECK([cell(wc.detailController.attributeMappingTable, @"expression", text) isEqualToString:@"$source.text"],
          "undo gives back the one worked out");

    NSTableColumn *expression = [wc.detailController.attributeMappingTable tableColumnWithIdentifier:@"expression"];
    CHECK([[wc.detailController.attributeMappingTable delegate] tableView:wc.detailController.attributeMappingTable
                                   shouldEditTableColumn:expression row:text],
          "the center's expression column is editable");
    [[wc.detailController.attributeMappingTable dataSource] tableView:wc.detailController.attributeMappingTable
                                      setObjectValue:@"$source.author"
                                      forTableColumn:expression
                                                 row:text];
    CHECK([[doc.mappingEditor valueExpressionStringOfPropertyMapping:selectedProperty(wc)]
              isEqualToString:@"$source.author"],
          "typing into its cell sets the expression too");
    [[doc undoManager] undo];

    SCENARIO("Selecting a relationship mapping inspects it");
    /* THEN the relationship's expression is shown as Xcode's inspector
       shows it: generated, through a key path and an entity mapping */
    selectRow(wc.detailController.relationshipMappingTable, 0);
    CHECK(inspectorKind(wc) == MBMappingInspectorKindRelationship, "the relationship mapping page shows");
    CHECK(wc.detailController.attributeMappingTable.selectedRow < 0, "and the attribute row is let go");
    CHECK([[wc.inspectorController.relationshipNamePopup titleOfSelectedItem] isEqualToString:@"tags"], "its relationship");
    CHECK([wc.inspectorController.relationshipSourceFetchPopup indexOfSelectedItem] == 0, "auto generated");
    CHECK([[wc.inspectorController.relationshipKeyPathField stringValue] isEqualToString:@"tags"], "through the key path tags");
    CHECK([[wc.inspectorController.relationshipMappingNameField stringValue] isEqualToString:@"TagToTag"], "and TagToTag");
    CHECK(![wc.inspectorController.relationshipExpressionField isEnabled], "with no expression to type");

    type(wc, wc.inspectorController.relationshipMappingNameField, @"Other");
    NSString *through = nil;
    [doc.mappingEditor relationshipMappingNamed:[selectedProperty(wc) name]
                                inEntityMapping:selectedMapping(wc)
                                        keyPath:NULL
                                    mappingName:&through];
    CHECK([through isEqualToString:@"Other"], "a mapping name typed is the one filled through");
    [[doc undoManager] undo];
    CHECK([[wc.inspectorController.relationshipMappingNameField stringValue] isEqualToString:@"TagToTag"],
          "undo puts TagToTag back in the field");

    choose(wc, wc.inspectorController.relationshipSourceFetchPopup, @"Custom Value Expression");
    CHECK([wc.inspectorController.relationshipExpressionField isEnabled] && ![wc.inspectorController.relationshipKeyPathField isEnabled],
          "Custom swaps the key path for an expression to type");
    choose(wc, wc.inspectorController.relationshipSourceFetchPopup, @"Auto Generate Value Expression");
    CHECK([[wc.inspectorController.relationshipMappingNameField stringValue] isEqualToString:@"TagToTag"],
          "and back again, it is generated as before");

    SCENARIO("Clicking the entity mapping again inspects it again");
    selectMapping(wc, selectedMapping(wc));
    CHECK(inspectorKind(wc) == MBMappingInspectorKindEntity && wc.mappingEditor.selection.kind == MBMappingSelectionEntityMapping,
          "the entity mapping page is back");

    SCENARIO("Narrowing a mapping from the inspector");
    type(wc, wc.inspectorController.filterPredicateField, @"text BEGINSWITH \"drop\"");
    CHECK([[doc.mappingEditor filterPredicateOfEntityMapping:selectedMapping(wc)]
              isEqualToString:@"text BEGINSWITH \"drop\""],
          "the document takes the new predicate");
    [[doc undoManager] undo];
    CHECK([[wc.inspectorController.filterPredicateField stringValue] isEqualToString:@"text BEGINSWITH \"keep\""],
          "undo puts the old one back in the field");
    choose(wc, wc.inspectorController.sourceFetchPopup, @"Default");
    CHECK([doc.mappingEditor filterPredicateOfEntityMapping:selectedMapping(wc)] == nil
              && ![wc.inspectorController.filterPredicateField isEnabled],
          "the default fetch takes every object");
    [[doc undoManager] undo];

    SCENARIO("The policy, the name and user info");
    type(wc, wc.inspectorController.customPolicyField, @"NotePolicy");
    CHECK([[selectedMapping(wc) entityMigrationPolicyClassName] isEqualToString:@"NotePolicy"],
          "a custom policy is set");
    [wc.inspectorController.entityUserInfoSegmentedControl setSelectedSegment:0];
    [wc.inspectorController userInfoSegmentClicked:wc.inspectorController.entityUserInfoSegmentedControl];
    CHECK([[wc.inspectorController.entityUserInfoTable dataSource] numberOfRowsInTableView:wc.inspectorController.entityUserInfoTable] == 1,
          "+ adds a user info entry");
    [[wc.inspectorController.entityUserInfoTable dataSource] tableView:wc.inspectorController.entityUserInfoTable
                                    setObjectValue:@"kept"
                                    forTableColumn:[wc.inspectorController.entityUserInfoTable tableColumnWithIdentifier:@"value"]
                                               row:0];
    CHECK([[[selectedMapping(wc) userInfo] objectForKey:@"key"] isEqual:@"kept"],
          "whose value is typed in its row");
    type(wc, wc.inspectorController.entityMappingNameField, @"KeepNotes");
    CHECK(mappingNamed(doc, @"KeepNotes") != nil, "the mapping is renamed from the name field");

    /* Beside the fixture: the models are found by the paths the file
       records, which are the project's. */
    NSString *saved = [[fixture stringByDeletingLastPathComponent] stringByAppendingPathComponent:
        [NSString stringWithFormat:@"probe-%d.xcmappingmodel", [[NSProcessInfo processInfo] processIdentifier]]];
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
    selectMapping(wc, mappingNamed(doc, @"Fresh"));
    CHECK([[wc.inspectorController.mappingTypeLabel stringValue] isEqualToString:@"Add"], "its type is Add");
    CHECK([[wc.inspectorController.entityUserInfoTable dataSource] numberOfRowsInTableView:wc.inspectorController.entityUserInfoTable] == 1
              && [cell(wc.inspectorController.entityUserInfoTable, @"key", 0) isEqual:@"testkey"]
              && [cell(wc.inspectorController.entityUserInfoTable, @"value", 0) isEqual:@"testvalue"],
          "the user info Xcode wrote is listed");
    CHECK([[wc.inspectorController.sourceEntityPopup titleOfSelectedItem] isEqualToString:@"None"], "it has no source");
    CHECK(![wc.inspectorController.sourceFetchPopup isEnabled] && ![wc.inspectorController.filterPredicateField isEnabled],
          "so nothing to fetch and nothing to narrow");

    SCENARIO("Pairing other entities changes the type");
    choose(wc, wc.inspectorController.sourceEntityPopup, @"Note");
    CHECK([[selectedMapping(wc) sourceEntityName] isEqualToString:@"Note"]
              && [[wc.inspectorController.mappingTypeLabel stringValue] isEqualToString:@"Transform"],
          "a source chosen makes it a transform");
    CHECK([wc.inspectorController.sourceFetchPopup isEnabled], "and now there is something to fetch");
    [[doc undoManager] undo];
    CHECK([[wc.inspectorController.mappingTypeLabel stringValue] isEqualToString:@"Add"], "undo makes it an add again");

    SCENARIO("A mapping added and removed from the bottom bar");
    NSInteger before = listedMappings(wc);

    [wc.entityMappingSegmentedControl setSelectedSegment:0];
    [wc entityMappingSegmentClicked:wc.entityMappingSegmentedControl];
    CHECK(listedMappings(wc) == before + 1, "+ adds a mapping");
    CHECK(inspectorKind(wc) == MBMappingInspectorKindEntity, "and inspects it");

    [wc.entityMappingSegmentedControl setSelectedSegment:1];
    [wc entityMappingSegmentClicked:wc.entityMappingSegmentedControl];
    CHECK(listedMappings(wc) == before, "− removes the selected one");

    SCENARIO("File > New Mapping Model");
    /* GIVEN the fixture's two-version model
       WHEN it is chosen as the source in the New Mapping Model panel
       THEN the source starts at the version before the current one, the
            destination at the current one, and Create writes a mapping
            model that opens with Xcode's three mappings */
    CHECK([[NSDocumentController sharedDocumentController] respondsToSelector:@selector(newMappingModel:)],
          "the document controller answers New Mapping Model");
    MBNewMappingController *panel = [[MBNewMappingController alloc] initWithWindowNibName:@"MBNewMappingPanel"];
    CHECK([panel window] != nil && panel.sourceVersionPopup && panel.destinationVersionPopup
              && panel.sourcePathLabel && panel.destinationPathLabel && panel.createButton,
          "the panel loads from its nib, every outlet connected");
    CHECK(![panel.createButton isEnabled], "Create waits for the models");
    CHECK([[buttonTitled([[panel window] contentView], @"Cancel") keyEquivalent] isEqualToString:@"\033"],
          "Cancel answers Escape (written in base64 in the xib)");
    CHECK([[buttonTitled([[panel window] contentView], @"Create…") keyEquivalent] isEqualToString:@"\r"],
          "Create answers Return");

    NSString *modelBundle = [[fixture stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"MappingFixture.xcdatamodeld"];
    CHECK(![panel chooseSourceModelAtPath:fixture], "a mapping model is not a model to choose");
    CHECK([panel chooseSourceModelAtPath:modelBundle], "the model is chosen as the source");
    CHECK([[panel.sourceVersionPopup titleOfSelectedItem] isEqualToString:@"MappingFixture"],
          "starting from the version before the current one");
    CHECK([[panel.destinationVersionPopup titleOfSelectedItem] isEqualToString:@"MappingFixture 2"],
          "to the current one, of the same model");
    CHECK([panel.createButton isEnabled], "and Create can go ahead");
    CHECK([[panel suggestedFileName] isEqualToString:@"MappingFixtureToMappingFixture2.xcmappingmodel"]
              && [[panel suggestedDirectory] isEqualToString:[fixture stringByDeletingLastPathComponent]],
          "beside the model, named for the two versions");

    NSString *created = [[fixture stringByDeletingLastPathComponent] stringByAppendingPathComponent:
        [NSString stringWithFormat:@"new-%d.xcmappingmodel", [[NSProcessInfo processInfo] processIdentifier]]];
    ok = [panel createMappingModelAtPath:created error:&error];
    CHECK(ok, "Create writes the mapping model");
    MBMappingDocument *made = [[MBMappingDocument alloc] init];
    ok = ok && [made readFromURL:[NSURL fileURLWithPath:created] ofType:@"Core Data Mapping Model" error:&error];
    if (!ok) printf("  (%s)\n", [[error description] UTF8String]);
    NSArray *names = [[[made.mappingEditor entityMappings] valueForKey:@"name"] sortedArrayUsingSelector:@selector(compare:)];
    BOOL xcodesThree = [names isEqualToArray:@[ @"Fresh", @"NoteToNote", @"TagToTag" ]];
    CHECK(xcodesThree,
          "which opens with the mappings Xcode starts with");
    CHECK([made.mappingEditor.sourceModelPath hasSuffix:@"MappingFixture.xcdatamodeld/MappingFixture.xcdatamodel"]
              && ![made.mappingEditor.sourceModelPath isAbsolutePath],
          "and records the model by its path in the project");
    [[NSFileManager defaultManager] removeItemAtPath:created error:NULL];

    printf("\n---\n%d passed, %d failed\n", passed, failed);
    return failed == 0 ? 0 : 1;
  }
}
