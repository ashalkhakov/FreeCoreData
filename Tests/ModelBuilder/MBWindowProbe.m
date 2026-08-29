/* Headless end-to-end probe for the ModelBuilder document window.
   Loads MBDocumentWindow.xib through MBWindowController on GNUstep's
   headless backend and drives the real controls the way a user would.

   Each SCENARIO(...) below is a textual use-case (Given/When/Then in
   comments) - deliberately gherkin-shaped so they can be ported to a
   BDD runner later; for now the binary IS the runner.  See README.md
   in this directory for the use-case catalogue and how to run.

   Requires: gnustep-back built with --enable-server=headless
   --enable-graphics=headless, and a libs-base carrying
   patches/gnustep-base-nsxmlnode-detached-attribute-dict-strings.patch.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBDocument.h"
#import "MBWindowController.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"
#import "JUInspectorView.h"
#import "JUInspectorViewContainer.h"

static int passed = 0, failed = 0;
#define CHECK(cond, name) do { \
  if (cond) { passed++; printf("  ok   %s\n", name); } \
  else { failed++; printf("  FAIL %s\n", name); } \
} while (0)
#define SCENARIO(title) printf("\nScenario: %s\n", title)

static NSString *kModelXML =
@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
@"<model type=\"com.apple.IDECoreDataModeler.DataModel\" documentVersion=\"1.0\" sourceLanguage=\"Objective-C\">\n"
@"  <entity name=\"Thing\" representedClassName=\"NSManagedObject\" syncable=\"YES\">\n"
@"    <attribute name=\"aString\" optional=\"YES\" attributeType=\"String\" defaultValueString=\"hi\"/>\n"
@"    <attribute name=\"bInt\" optional=\"YES\" attributeType=\"Integer 32\" defaultValueString=\"7\"/>\n"
@"    <attribute name=\"cDate\" optional=\"YES\" attributeType=\"Date\"/>\n"
@"    <attribute name=\"dBool\" optional=\"YES\" attributeType=\"Boolean\" defaultValueString=\"YES\"/>\n"
@"    <relationship name=\"others\" optional=\"YES\" toMany=\"YES\" deletionRule=\"Nullify\" destinationEntity=\"Other\" inverseName=\"thing\" inverseEntity=\"Other\"/>\n"
@"  </entity>\n"
@"  <entity name=\"Other\" representedClassName=\"NSManagedObject\" syncable=\"YES\">\n"
@"    <attribute name=\"tag\" optional=\"YES\" attributeType=\"String\"/>\n"
@"    <relationship name=\"thing\" optional=\"YES\" maxCount=\"1\" deletionRule=\"Nullify\" destinationEntity=\"Thing\" inverseName=\"others\" inverseEntity=\"Thing\"/>\n"
@"    <relationship name=\"sibling\" optional=\"YES\" maxCount=\"1\" deletionRule=\"Nullify\" destinationEntity=\"Other\"/>\n"
@"  </entity>\n"
@"</model>\n";

static NSString *writeSamplePackage(void)
{
  NSString *root = [NSTemporaryDirectory()
      stringByAppendingPathComponent:@"MBProbe.xcdatamodeld"];
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm removeItemAtPath:root error:NULL];
  NSString *version = [root stringByAppendingPathComponent:@"MBProbe.xcdatamodel"];
  [fm createDirectoryAtPath:version withIntermediateDirectories:YES attributes:nil error:NULL];
  [kModelXML writeToFile:[version stringByAppendingPathComponent:@"contents"]
              atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  return root;
}

static NSInteger selectedDetailTab(MBWindowController *wc)
{
  return [wc.attributeDetailTabView indexOfTabViewItem:
             [wc.attributeDetailTabView selectedTabViewItem]];
}

static void selectAttributeRow(MBWindowController *wc, NSUInteger row)
{
  [wc.attributeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                 byExtendingSelection:NO];
}

int main(void)
{
  @autoreleasepool {
    [NSApplication sharedApplication];

    MBDocument *doc = [[MBDocument alloc] init];
    NSError *error = nil;
    BOOL ok = [doc readFromURL:[NSURL fileURLWithPath:writeSamplePackage()]
                        ofType:@"xcdatamodeld"
                         error:&error];
    SCENARIO("Opening a model document loads the window from the nib");
    /* GIVEN a saved .xcdatamodeld with entities Thing and ZOther
       WHEN the document opens and makes its window controller
       THEN the window loads from MBDocumentWindow.xib with every
            outlet connected and the type popup carrying momc's
            attribute-type vocabulary */
    CHECK(ok, "open sample package");

    [doc makeWindowControllers];
    MBWindowController *wc = doc.windowControllers.firstObject;
    NSWindow *window = [wc window];   /* forces loadWindow + windowDidLoad */
    CHECK(window != nil, "window loads from nib");
    CHECK(wc.sourceList != nil, "sourceList outlet");
    CHECK(wc.attributeTable != nil, "attributeTable outlet");
    CHECK(wc.attributeTypePopup != nil, "attributeTypePopup outlet");
    CHECK(wc.attributeDetailTabView != nil, "attributeDetailTabView outlet");
    CHECK([wc.attributeDetailTabView numberOfTabViewItems] == 9, "9 detail pages");
    CHECK([wc.attributeTypePopup numberOfItems] ==
          (NSInteger)[[CDModelCompiler attributeTypeNames] count],
          "type popup populated");
    SCENARIO("The xib's delete-rule items match momc's vocabulary");
    /* GIVEN the Delete Rule popup items are authored in Interface
            Builder while momc defines the accepted spellings
       THEN the two sets are identical, so an IB edit or a compiler
            rename fails loudly here instead of silently */
    CHECK([[NSSet setWithArray:[wc.deleteRulePopup itemTitles]] isEqualToSet:
           [NSSet setWithArray:[CDModelCompiler deleteRuleNames]]],
          "xib delete-rule items match compiler spellings");

    /* Entities sort Other < Thing; make sure Thing is the selection. */
    for (NSInteger i = 0; i < [wc.sourceList numberOfRows]; i++) {
      id item = [wc.sourceList itemAtRow:i];
      if ([item respondsToSelector:@selector(name)] &&
          [[item performSelector:@selector(name)] isEqualToString:@"Thing"]) {
        [wc.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)i]
                   byExtendingSelection:NO];
        break;
      }
    }

    /* Rows are sorted: aString(0) bInt(1) cDate(2) dBool(3). */
    CHECK([wc.attributeTable numberOfRows] == 4, "4 attribute rows");

    SCENARIO("Selecting attributes shows the matching per-type detail page");
    /* GIVEN Thing with String, Integer 32, Date and Boolean attributes
       WHEN each row of the attributes table is selected
       THEN the inspector's detail tab switches to that type's page and
            shows the stored default value */
    selectAttributeRow(wc, 0);
    CHECK(selectedDetailTab(wc) == 2, "String attribute shows String page");
    CHECK([[wc.attributeTypePopup titleOfSelectedItem] isEqualToString:@"String"],
          "type popup shows String");
    CHECK(wc.stringDefaultCheckbox.state == NSOnState, "string default checked");
    CHECK([wc.stringDefaultField.stringValue isEqualToString:@"hi"], "string default filled");

    selectAttributeRow(wc, 1);
    CHECK(selectedDetailTab(wc) == 1, "Integer attribute shows number page");
    CHECK([wc.numberDefaultField.stringValue isEqualToString:@"7"], "number default filled");

    selectAttributeRow(wc, 2);
    CHECK(selectedDetailTab(wc) == 4, "Date attribute shows Date page");

    selectAttributeRow(wc, 3);
    CHECK(selectedDetailTab(wc) == 3, "Boolean attribute shows Boolean page");
    CHECK([[wc.boolDefaultPopup titleOfSelectedItem] isEqualToString:@"YES"],
          "bool default YES");

    SCENARIO("Changing an attribute's type from the inspector popup");
    /* GIVEN the String attribute aString is selected
       WHEN the Type popup is changed to Date, then UUID, then (via a
            real target/action dispatch) Boolean
       THEN the model's attributeType follows, the stale default is
            dropped, and the detail page switches each time */
    /* Now change the TYPE through the popup, as a user would. */
    selectAttributeRow(wc, 0);
    [wc.attributeTypePopup selectItemWithTitle:@"Date"];
    [wc inspectorChanged:wc.attributeTypePopup];   /* the popup's action */
    NSEntityDescription *thing = doc.model.entitiesByName[@"Thing"];
    NSAttributeDescription *aString = thing.attributesByName[@"aString"];
    CHECK(aString.attributeType == NSDateAttributeType, "model type changed to Date");
    CHECK(selectedDetailTab(wc) == 4, "detail page switched to Date");
    CHECK(aString.defaultValue == nil, "old default dropped on type change");

    [wc.attributeTypePopup selectItemWithTitle:@"UUID"];
    [wc inspectorChanged:wc.attributeTypePopup];
    CHECK(aString.attributeType == NSUUIDAttributeType, "model type changed to UUID");
    CHECK(selectedDetailTab(wc) == 6, "detail page switched to UUID");

    /* And back through a real popup action dispatch, to prove the
       target/action wiring itself. */
    [wc.attributeTypePopup selectItemWithTitle:@"Boolean"];
    ok = [NSApp sendAction:wc.attributeTypePopup.action
                        to:wc.attributeTypePopup.target
                      from:wc.attributeTypePopup];
    CHECK(ok, "popup action dispatches");
    CHECK(aString.attributeType == NSBooleanAttributeType, "action path changes type");
    CHECK(selectedDetailTab(wc) == 3, "action path switches page");

    SCENARIO("Collapsible sections are adopted from the nib");
    /* GIVEN the xib places JUInspectorView sections inside their
            containers with name/index runtime attributes
       WHEN the nib finishes loading (container awakeFromNib)
       THEN each section is a subview of its container, has a header,
            its IB-assigned name and stacking order, and is expanded */
    /* Nib-decoded JUInspectorView sections must be adopted by their
       containers (vendored awakeFromNib support). */
    CHECK(wc.attributesInspector.superview == wc.entityInspectorContainer,
          "attributes section is a container subview");
    CHECK(wc.attributesInspector.header != nil, "section header exists");
    CHECK([wc.attributesInspector.name isEqualToString:@"Attribute Inspector"],
          "section name from IB runtime attribute");
    CHECK(wc.attributesInspector.container == wc.entityInspectorContainer,
          "section adopted by container");
    CHECK(wc.attributesInspector.expanded && wc.relationshipsInspector.expanded,
          "sections expanded after adoption");
    CHECK(wc.attributesInspector.index < wc.relationshipsInspector.index ||
          (wc.attributesInspector.index == 0 && wc.relationshipsInspector.index == 1),
          "section order from IB index attribute");
    CHECK(wc.fetchRequestInspector.container == wc.fetchRequestInspectorContainer,
          "fetch section adopted");
    CHECK(wc.entitiesInspector.container == wc.configurationInspectorContainer,
          "entities section adopted");

    SCENARIO("A type flip through Transformable leaves no transformer residue");
    /* GIVEN dBool is switched to Transformable and given a transformer
       WHEN it is switched back to Boolean
       THEN nothing throws (Apple CoreData forbids nil-ing the fields)
            and the serialized XML carries no valueTransformerName */
    /* Flip a type through Transformable and back: the transformer
       fields must survive without nil-sets (Apple throws on those) and
       must not leak into the serialized XML for the new type. */
    selectAttributeRow(wc, 3);   /* dBool */
    [wc.attributeTypePopup selectItemWithTitle:@"Transformable"];
    [wc inspectorChanged:wc.attributeTypePopup];
    wc.transformerField.stringValue = @"NSSecureUnarchiveFromData";
    [wc inspectorChanged:wc.transformerField];
    NSAttributeDescription *dBool = thing.attributesByName[@"dBool"];
    CHECK([[dBool valueTransformerName] isEqualToString:@"NSSecureUnarchiveFromData"],
          "transformer set while Transformable");
    [wc.attributeTypePopup selectItemWithTitle:@"Boolean"];
    [wc inspectorChanged:wc.attributeTypePopup];
    CHECK(dBool.attributeType == NSBooleanAttributeType, "flip back to Boolean");
    NSString *xml = [CDModelSerializer contentsXMLForModel:doc.model
                                             entityLayouts:nil error:&error];
    CHECK(xml != nil &&
          [xml rangeOfString:@"valueTransformerName"].location == NSNotFound,
          "no stale transformer in serialized XML");

    SCENARIO("Center-pane combo columns list and apply their choices");
    /* GIVEN the attribute table's Type column and the relationship
            table's Destination/Inverse columns (NSComboBoxCells)
       WHEN their drop-down lists are populated for a row and edits are
            committed through the table's edit path
       THEN the lists carry the momc type names / entities / the
            destination's relationships plus (none), and each edit is
            applied with its side effects (default dropped, stale
            inverse unwired, both sides rewired) */
    /* --- Center-pane combo columns (Type / Destination / Inverse). --- */
    NSTableColumn *typeColumn = [wc.attributeTable tableColumnWithIdentifier:@"type"];
    NSComboBoxCell *typeCell = (NSComboBoxCell *)typeColumn.dataCell;
    CHECK([typeCell isKindOfClass:[NSComboBoxCell class]], "Type column is a combo cell");
    [wc tableView:wc.attributeTable willDisplayCell:typeCell forTableColumn:typeColumn row:1];
    CHECK([typeCell numberOfItems] ==
          (NSInteger)[[CDModelCompiler attributeTypeNames] count],
          "Type combo list populated");

    NSAttributeDescription *bInt = thing.attributesByName[@"bInt"];
    [wc tableView:wc.attributeTable setObjectValue:@"String"
        forTableColumn:typeColumn row:1];
    CHECK(bInt.attributeType == NSStringAttributeType, "center Type edit changes type");
    selectAttributeRow(wc, 1);
    CHECK(selectedDetailTab(wc) == 2, "center Type edit reflected in inspector");

    /* Relationships of Thing: rows sorted -> others(0). */
    CHECK([wc.relationshipTable numberOfRows] == 1, "1 relationship row");
    NSTableColumn *destColumn = [wc.relationshipTable tableColumnWithIdentifier:@"destination"];
    NSComboBoxCell *destCell = (NSComboBoxCell *)destColumn.dataCell;
    [wc tableView:wc.relationshipTable willDisplayCell:destCell
        forTableColumn:destColumn row:0];
    CHECK([destCell numberOfItems] == 2, "Destination combo lists both entities");
    NSTableColumn *invColumn = [wc.relationshipTable tableColumnWithIdentifier:@"inverse"];
    NSComboBoxCell *invCell = (NSComboBoxCell *)invColumn.dataCell;
    [wc tableView:wc.relationshipTable willDisplayCell:invCell
        forTableColumn:invColumn row:0];
    CHECK([invCell numberOfItems] == 3, "Inverse combo lists (none)+destination rels");

    NSRelationshipDescription *others = thing.relationshipsByName[@"others"];
    NSEntityDescription *other = doc.model.entitiesByName[@"Other"];
    [wc tableView:wc.relationshipTable setObjectValue:@"(none)"
        forTableColumn:invColumn row:0];
    CHECK(others.inverseRelationship == nil, "center Inverse edit unwires");
    CHECK([other.relationshipsByName[@"thing"] inverseRelationship] == nil,
          "old inverse unwired both ways");
    [wc tableView:wc.relationshipTable setObjectValue:@"thing"
        forTableColumn:invColumn row:0];
    CHECK(others.inverseRelationship == other.relationshipsByName[@"thing"],
          "center Inverse edit rewires");
    [wc tableView:wc.relationshipTable setObjectValue:@"Thing"
        forTableColumn:destColumn row:0];
    CHECK(others.destinationEntity == thing, "center Destination edit retargets");
    CHECK(others.inverseRelationship == nil, "stale inverse dropped on retarget");

    printf("---\n%d passed, %d failed\n", passed, failed);
    exit(failed ? 1 : 0);   /* skip pool teardown */
  }
}
