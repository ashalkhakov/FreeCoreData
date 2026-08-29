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

    SCENARIO("Renaming, scalar, validation and fetch-template controls are live");
    /* GIVEN the serializer now round-trips renaming identifiers,
            usesScalarValueType, validation bounds and the fetch
            template features (result type, batch size, the flags)
       WHEN the inspector controls for them are used as a user would
       THEN they are enabled, prefill from the model, and each edit
            reaches the description objects */
    CHECK(wc.attributeRenamingField.isEnabled && wc.entityRenamingField.isEnabled &&
          wc.relationshipRenamingField.isEnabled, "renaming fields enabled");
    CHECK(wc.fetchResultTypePopup.isEnabled && wc.fetchBatchField.isEnabled &&
          wc.fetchDistinctCheckbox.isEnabled, "fetch feature controls enabled");
    CHECK(wc.numberMinField.isEnabled && wc.stringRegexField.isEnabled &&
          wc.dateMinPicker.isEnabled, "validation controls enabled");
    CHECK(wc.dateScalarCheckbox.isEnabled, "scalar checkboxes enabled");

    /* cDate (row 2) kept its Date type through the earlier scenarios. */
    selectAttributeRow(wc, 2);
    NSAttributeDescription *cDate = thing.attributesByName[@"cDate"];
    CHECK([wc.attributeRenamingField.stringValue isEqualToString:@"cDate"],
          "renaming field shows the name while defaulted");
    wc.attributeRenamingField.stringValue = @"createdAt";
    [wc inspectorChanged:wc.attributeRenamingField];
    CHECK([[cDate renamingIdentifier] isEqualToString:@"createdAt"],
          "renaming edit reaches the model");
    [wc.dateScalarCheckbox setState:NSOnState];
    [wc inspectorChanged:wc.dateScalarCheckbox];
    CHECK([CDModelCompiler attributeUsesScalarValueType:cDate],
          "scalar checkbox sets the codegen flag");
    [wc.dateMinCheckbox setState:NSOnState];
    wc.dateMinPicker.dateValue = [NSDate dateWithTimeIntervalSinceReferenceDate:100];
    [wc inspectorChanged:wc.dateMinCheckbox];
    NSDictionary *dateInfo = [CDModelCompiler validationInfoForAttribute:cDate];
    CHECK([dateInfo[@"minDate"] timeIntervalSinceReferenceDate] == 100,
          "date lower bound applied as a validation predicate");

    /* bInt became a String attribute in the combo-column scenario. */
    selectAttributeRow(wc, 1);
    wc.stringMinField.stringValue = @"2";
    wc.stringMaxField.stringValue = @"10";
    wc.stringRegexField.stringValue = @"[a-z]+";
    [wc inspectorChanged:wc.stringMaxField];
    NSDictionary *strInfo = [CDModelCompiler validationInfoForAttribute:bInt];
    CHECK([strInfo[@"minLength"] isEqualToString:@"2"] &&
          [strInfo[@"maxLength"] isEqualToString:@"10"] &&
          [strInfo[@"regex"] isEqualToString:@"[a-z]+"],
          "string length bounds and regex applied");

    [wc addFetchRequest:nil];   /* adds for Thing, selects it */
    NSString *templateName = wc.fetchNameField.stringValue;
    CHECK(templateName.length > 0, "fetch request added and selected");
    CHECK(wc.fetchSubentitiesCheckbox.state == NSOnState &&
          wc.fetchDistinctCheckbox.state == NSOffState,
          "checkboxes prefill with the runtime defaults");
    [wc.fetchResultTypePopup selectItemAtIndex:2];   /* Dictionaries */
    wc.fetchBatchField.stringValue = @"25";
    [wc.fetchDistinctCheckbox setState:NSOnState];
    [wc.fetchSubentitiesCheckbox setState:NSOffState];
    [wc inspectorChanged:wc.fetchResultTypePopup];
    NSFetchRequest *template = [doc.model fetchRequestTemplateForName:templateName];
    CHECK(template != nil, "template stored under its name");
    CHECK([template resultType] == NSDictionaryResultType,
          "result-type popup applied (Dictionaries)");
    CHECK([template fetchBatchSize] == 25, "batch size applied");
    CHECK([template returnsDistinctResults] && ![template includesSubentities],
          "flag flips applied in both directions");

    SCENARIO("The Codegen popup is live and round-trips codeGenerationType");
    /* GIVEN codegen metadata now rides through the momc layer
       WHEN an entity's Codegen popup is switched to Class Definition
       THEN the compiler metadata and the serialized XML both carry it,
            and the refill maps it back to the same popup item */
    CHECK(([[NSSet setWithArray:[wc.codegenPopup itemTitles]] isEqualToSet:
            [NSSet setWithArray:@[ @"Manual/None", @"Class Definition",
                                   @"Category/Extension" ]]]),
          "xib codegen items match the known modes");
    for (NSInteger i = 0; i < [wc.sourceList numberOfRows]; i++) {
      id item = [wc.sourceList itemAtRow:i];
      if ([item respondsToSelector:@selector(name)] &&
          [[item performSelector:@selector(name)] isEqualToString:@"Thing"]) {
        [wc.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)i]
                   byExtendingSelection:NO];
        break;
      }
    }
    CHECK(wc.codegenPopup.isEnabled, "codegen popup enabled");
    [wc.codegenPopup selectItemAtIndex:1];   /* Class Definition */
    [wc inspectorChanged:wc.codegenPopup];
    CHECK([[CDModelCompiler entityCodeGenerationType:thing]
              isEqualToString:@"class"], "popup writes the compiler metadata");
    CHECK([wc.codegenPopup indexOfSelectedItem] == 1,
          "refill maps the metadata back to the item");
    xml = [CDModelSerializer contentsXMLForModel:doc.model
                                   entityLayouts:nil error:&error];
    CHECK(xml != nil &&
          [xml rangeOfString:@"codeGenerationType=\"class\""].location != NSNotFound,
          "codeGenerationType serialized");

    SCENARIO("Stepper text fields own and drive their steppers");
    /* GIVEN the numeric inspector fields are MBStepperTextFields in
            the xib, each creating its own stepper on nib load
       WHEN a stepper click is simulated (value +1, action fired, as a
            real click leaves it)
       THEN the field increments, the edit applies through the field's
            own action (inspectorChanged:), the stepper returns to
            rest, and it mirrors the field's enabled state */
    int owned = 0;
    for (MBStepperTextField *field in @[ wc.numberDefaultField, wc.numberMinField,
                                         wc.numberMaxField, wc.stringMinField,
                                         wc.stringMaxField, wc.minCountField,
                                         wc.maxCountField, wc.fetchLimitField,
                                         wc.fetchBatchField ]) {
      if ([field isKindOfClass:[MBStepperTextField class]] &&
          field.stepper != nil && field.stepper.target == field &&
          field.stepper.superview == field.superview) owned++;
    }
    CHECK(owned == 9, "all 9 fields are MBStepperTextFields with a live stepper");
    CHECK(wc.numberMinField.allowsNegative && !wc.stringMinField.allowsNegative,
          "number bounds signed, lengths clamped at zero");

    selectAttributeRow(wc, 1);   /* bInt (String type), minLength "2" */
    CHECK([wc.stringMinField.stringValue isEqualToString:@"2"],
          "string min length prefilled");
    NSStepper *minStepper = wc.stringMinField.stepper;
    minStepper.doubleValue = 1;   /* an up-click leaves +1 behind */
    [minStepper sendAction:minStepper.action to:minStepper.target];
    CHECK([wc.stringMinField.stringValue isEqualToString:@"3"],
          "up-click increments the field");
    CHECK([[CDModelCompiler validationInfoForAttribute:bInt][@"minLength"]
              isEqualToString:@"3"], "stepped value applied to the model");
    CHECK(minStepper.doubleValue == 0, "stepper back at rest");
    minStepper.doubleValue = -1;  /* a down-click */
    [minStepper sendAction:minStepper.action to:minStepper.target];
    CHECK([wc.stringMinField.stringValue isEqualToString:@"2"],
          "down-click decrements the field");
    wc.minCountField.enabled = NO;
    CHECK(!wc.minCountField.stepper.isEnabled, "stepper follows field enablement");
    wc.minCountField.enabled = YES;

    printf("---\n%d passed, %d failed\n", passed, failed);
    exit(failed ? 1 : 0);   /* skip pool teardown */
  }
}
