/* Headless end-to-end probe for the ModelBuilder document window.
   Loads MBDocumentWindow.xib through MBWindowController on GNUstep's
   headless backend and drives the real controls the way a user would.

   Each SCENARIO(...) below is a textual use-case (Given/When/Then in
   comments) - deliberately gherkin-shaped so they can be ported to a
   BDD runner later; for now the binary IS the runner.  See README.md
   in this directory for the use-case catalogue and how to run.

   Requires: a gnustep-back -- the headless one (--enable-server=headless
   --enable-graphics=headless), or cairo/X11 under xvfb-run as CI runs it.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBDocument.h"
#import "MBWindowController.h"
#import "MBInspectorViewController.h"
#import "MBDetailViewController.h"
#import "MBSourceListViewController.h"
#import "MBEditors.h"
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
@"    <fetchIndex name=\"byString\">\n"
@"      <fetchIndexElement property=\"aString\" type=\"Binary\" order=\"ascending\"/>\n"
@"    </fetchIndex>\n"
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

/* A control's edit given to what it is bound to, as a click or the end
   of typing does: by sending its action. */
static void commit(NSControl *control)
{
  [control sendAction:control.action to:control.target];
}

static NSInteger selectedDetailTab(MBWindowController *wc)
{
  return [wc.inspectorController.attributeDetailTabView indexOfTabViewItem:
             [wc.inspectorController.attributeDetailTabView selectedTabViewItem]];
}

static void selectAttributeRow(MBWindowController *wc, NSUInteger row)
{
  [wc.detailController.attributeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
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
            outlet connected, and an attribute's type popup carries
            momc's attribute-type vocabulary */
    CHECK(ok, "open sample package");

    [doc makeWindowControllers];
    MBWindowController *wc = doc.windowControllers.firstObject;
    NSWindow *window = [wc window];   /* forces loadWindow + windowDidLoad */
    CHECK(window != nil, "window loads from nib");
    CHECK(wc.sourceListController.sourceList != nil, "sourceList outlet");
    CHECK(wc.detailController.attributeTable != nil, "attributeTable outlet");
    CHECK(wc.inspectorController.attributeTypePopup != nil, "attributeTypePopup outlet");
    CHECK(wc.inspectorController.attributeDetailTabView != nil, "attributeDetailTabView outlet");
    CHECK([wc.inspectorController.attributeDetailTabView numberOfTabViewItems] == 9, "9 detail pages");
    selectAttributeRow(wc, 0);   /* the popup's items are the attribute editor's */
    CHECK([wc.inspectorController.attributeTypePopup numberOfItems] ==
          (NSInteger)[[CDModelCompiler attributeTypeNames] count],
          "type popup populated");
    SCENARIO("The xib's delete-rule items match momc's vocabulary");
    /* GIVEN the Delete Rule popup items are authored in Interface
            Builder while momc defines the accepted spellings
       THEN the two sets are identical, so an IB edit or a compiler
            rename fails loudly here instead of silently */
    CHECK([[NSSet setWithArray:[wc.inspectorController.deleteRulePopup itemTitles]] isEqualToSet:
           [NSSet setWithArray:[CDModelCompiler deleteRuleNames]]],
          "xib delete-rule items match compiler spellings");

    /* Entities sort Other < Thing; make sure Thing is the selection. */
    for (NSInteger i = 0; i < [wc.sourceListController.sourceList numberOfRows]; i++) {
      id item = [wc.sourceListController.sourceList itemAtRow:i];
      if ([item respondsToSelector:@selector(name)] &&
          [[item performSelector:@selector(name)] isEqualToString:@"Thing"]) {
        [wc.sourceListController.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)i]
                   byExtendingSelection:NO];
        break;
      }
    }

    /* Rows are sorted: aString(0) bInt(1) cDate(2) dBool(3). */
    CHECK([wc.detailController.attributeTable numberOfRows] == 4, "4 attribute rows");

    SCENARIO("Date pickers load their fields and date from the nib");
    /* GIVEN the Date attribute page's three NSDatePickers, each set in
            the xib to show date and time and to use the current date
       WHEN the window loads from MBDocumentWindow.xib (checked before
            any attribute is selected: filling the Date page replaces
            the pickers' dates with the model's)
       THEN each picker has its date-and-time fields and today's date,
            not an empty field and a date in 2001 -- which is what a xib
            date picker got before the loader decoded them */
    for (NSDatePicker *picker in @[ wc.inspectorController.dateDefaultPicker, wc.inspectorController.dateMinPicker,
                                    wc.inspectorController.dateMaxPicker ]) {
      CHECK(picker.datePickerElements ==
                (NSYearMonthDayDatePickerElementFlag |
                 NSHourMinuteSecondDatePickerElementFlag),
            "date picker shows date and time fields");
      CHECK(fabs([picker.dateValue timeIntervalSinceNow]) < 24 * 3600,
            "date picker starts on the current date");
      CHECK(picker.datePickerStyle == NSTextFieldAndStepperDatePickerStyle &&
                picker.datePickerMode == NSSingleDateMode,
            "date picker style and mode as in the nib");
    }

    SCENARIO("Selecting attributes shows the matching per-type detail page");
    /* GIVEN Thing with String, Integer 32, Date and Boolean attributes
       WHEN each row of the attributes table is selected
       THEN the inspector's detail tab switches to that type's page and
            shows the stored default value */
    selectAttributeRow(wc, 0);
    CHECK(selectedDetailTab(wc) == 2, "String attribute shows String page");
    CHECK([[wc.inspectorController.attributeTypePopup titleOfSelectedItem] isEqualToString:@"String"],
          "type popup shows String");
    CHECK(wc.inspectorController.stringDefaultCheckbox.state == NSOnState, "string default checked");
    CHECK([wc.inspectorController.stringDefaultField.stringValue isEqualToString:@"hi"], "string default filled");

    selectAttributeRow(wc, 1);
    CHECK(selectedDetailTab(wc) == 1, "Integer attribute shows number page");
    CHECK([wc.inspectorController.numberDefaultField.stringValue isEqualToString:@"7"], "number default filled");

    selectAttributeRow(wc, 2);
    CHECK(selectedDetailTab(wc) == 4, "Date attribute shows Date page");

    selectAttributeRow(wc, 3);
    CHECK(selectedDetailTab(wc) == 3, "Boolean attribute shows Boolean page");
    CHECK([[wc.inspectorController.boolDefaultPopup titleOfSelectedItem] isEqualToString:@"YES"],
          "bool default YES");

    SCENARIO("Changing an attribute's type from the inspector popup");
    /* GIVEN the String attribute aString is selected
       WHEN the Type popup is changed to Date, then UUID, then Boolean
       THEN the model's attributeType follows, the stale default is
            dropped, and the detail page switches each time */
    /* Now change the TYPE through the popup, as a user would. */
    selectAttributeRow(wc, 0);
    [wc.inspectorController.attributeTypePopup selectItemWithTitle:@"Date"];
    commit(wc.inspectorController.attributeTypePopup);   /* the popup's action, as a click sends it */
    NSEntityDescription *thing = doc.modelEditor.model.entitiesByName[@"Thing"];
    NSAttributeDescription *aString = thing.attributesByName[@"aString"];
    CHECK(aString.attributeType == NSDateAttributeType, "model type changed to Date");
    CHECK(selectedDetailTab(wc) == 4, "detail page switched to Date");
    CHECK(aString.defaultValue == nil, "old default dropped on type change");

    [wc.inspectorController.attributeTypePopup selectItemWithTitle:@"UUID"];
    commit(wc.inspectorController.attributeTypePopup);
    CHECK(aString.attributeType == NSUUIDAttributeType, "model type changed to UUID");
    CHECK(selectedDetailTab(wc) == 6, "detail page switched to UUID");

    /* The binding from the xib is what is under test. */
    CHECK([wc.inspectorController.attributeTypePopup infoForBinding:NSSelectedValueBinding] != nil,
          "the popup is bound");
    [wc.inspectorController.attributeTypePopup selectItemWithTitle:@"Boolean"];
    commit(wc.inspectorController.attributeTypePopup);
    CHECK(aString.attributeType == NSBooleanAttributeType, "the binding changes the type");
    CHECK(selectedDetailTab(wc) == 3, "and switches the page");

    SCENARIO("Collapsible sections are adopted from the nib");
    /* GIVEN the xib places JUInspectorView sections inside their
            containers with name/index runtime attributes
       WHEN the nib finishes loading (container awakeFromNib)
       THEN each section is a subview of its container, has a header,
            its IB-assigned name and stacking order, and is expanded */
    /* Nib-decoded JUInspectorView sections must be adopted by their
       containers (vendored awakeFromNib support). */
    CHECK(wc.detailController.attributesInspector.superview == wc.detailController.entityInspectorContainer,
          "attributes section is a container subview");
    CHECK(wc.detailController.attributesInspector.header != nil, "section header exists");
    CHECK([wc.detailController.attributesInspector.name isEqualToString:@"Attribute Inspector"],
          "section name from IB runtime attribute");
    CHECK(wc.detailController.attributesInspector.container == wc.detailController.entityInspectorContainer,
          "section adopted by container");
    CHECK(wc.detailController.attributesInspector.expanded && wc.detailController.relationshipsInspector.expanded,
          "sections expanded after adoption");
    CHECK(wc.detailController.attributesInspector.index < wc.detailController.relationshipsInspector.index ||
          (wc.detailController.attributesInspector.index == 0 && wc.detailController.relationshipsInspector.index == 1),
          "section order from IB index attribute");
    CHECK(wc.detailController.fetchRequestInspector.container == wc.detailController.fetchRequestInspectorContainer,
          "fetch section adopted");
    CHECK(wc.detailController.entitiesInspector.container == wc.detailController.configurationInspectorContainer,
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
    [wc.inspectorController.attributeTypePopup selectItemWithTitle:@"Transformable"];
    commit(wc.inspectorController.attributeTypePopup);
    wc.inspectorController.transformerField.stringValue = @"NSSecureUnarchiveFromData";
    commit(wc.inspectorController.transformerField);
    NSAttributeDescription *dBool = thing.attributesByName[@"dBool"];
    CHECK([[dBool valueTransformerName] isEqualToString:@"NSSecureUnarchiveFromData"],
          "transformer set while Transformable");
    [wc.inspectorController.attributeTypePopup selectItemWithTitle:@"Boolean"];
    commit(wc.inspectorController.attributeTypePopup);
    CHECK(dBool.attributeType == NSBooleanAttributeType, "flip back to Boolean");
    NSString *xml = [CDModelSerializer contentsXMLForModel:doc.modelEditor.model
                                             entityLayouts:nil error:&error];
    CHECK(xml != nil &&
          [xml rangeOfString:@"valueTransformerName"].location == NSNotFound,
          "no stale transformer in serialized XML");

    SCENARIO("Center-pane popup columns list and apply their choices");
    /* GIVEN the attribute table's Type column and the relationship
            table's Destination/Inverse columns (NSPopUpButtonCells, as
            in Xcode's model editor)
       WHEN their menus are populated for a row and a choice is committed
            through the table's edit path (as an item index, which is what
            a popup cell hands back)
       THEN the menus carry the momc type names / entities / the
            destination's relationships plus (none), with the current
            value selected, and each edit is applied with its side
            effects (default dropped, stale inverse unwired, both sides
            rewired) */
    NSTableColumn *typeColumn = [wc.detailController.attributeTable tableColumnWithIdentifier:@"type"];
    NSPopUpButtonCell *typeCell = (NSPopUpButtonCell *)typeColumn.dataCell;
    CHECK([typeCell isKindOfClass:[NSPopUpButtonCell class]], "Type column is a popup cell");
    [wc.detailController tableView:wc.detailController.attributeTable willDisplayCell:typeCell forTableColumn:typeColumn row:1];
    NSArray *typeNames = [CDModelCompiler attributeTypeNames];
    CHECK([typeCell numberOfItems] == (NSInteger)typeNames.count, "Type popup populated");

    NSAttributeDescription *bInt = thing.attributesByName[@"bInt"];
    CHECK([[typeCell titleOfSelectedItem] isEqualToString:
              [CDModelCompiler nameForAttributeType:bInt.attributeType]],
          "Type popup selects the attribute's type");
    [wc.detailController tableView:wc.detailController.attributeTable setObjectValue:@([typeNames indexOfObject:@"String"])
        forTableColumn:typeColumn row:1];
    CHECK(bInt.attributeType == NSStringAttributeType, "center Type edit changes type");
    selectAttributeRow(wc, 1);
    CHECK(selectedDetailTab(wc) == 2, "center Type edit reflected in inspector");

    /* Relationships of Thing: rows sorted -> others(0). */
    CHECK([wc.detailController.relationshipTable numberOfRows] == 1, "1 relationship row");
    NSTableColumn *destColumn = [wc.detailController.relationshipTable tableColumnWithIdentifier:@"destination"];
    NSPopUpButtonCell *destCell = (NSPopUpButtonCell *)destColumn.dataCell;
    CHECK([destCell isKindOfClass:[NSPopUpButtonCell class]], "Destination column is a popup cell");
    [wc.detailController tableView:wc.detailController.relationshipTable willDisplayCell:destCell
        forTableColumn:destColumn row:0];
    CHECK([destCell numberOfItems] == 2, "Destination popup lists both entities");
    NSTableColumn *invColumn = [wc.detailController.relationshipTable tableColumnWithIdentifier:@"inverse"];
    NSPopUpButtonCell *invCell = (NSPopUpButtonCell *)invColumn.dataCell;
    CHECK([invCell isKindOfClass:[NSPopUpButtonCell class]], "Inverse column is a popup cell");
    [wc.detailController tableView:wc.detailController.relationshipTable willDisplayCell:invCell
        forTableColumn:invColumn row:0];
    CHECK([invCell numberOfItems] == 3, "Inverse popup lists (none)+destination rels");
    CHECK([[invCell titleOfSelectedItem] isEqualToString:@"thing"],
          "Inverse popup selects the current inverse");

    NSRelationshipDescription *others = thing.relationshipsByName[@"others"];
    NSEntityDescription *other = doc.modelEditor.model.entitiesByName[@"Other"];
    [wc.detailController tableView:wc.detailController.relationshipTable setObjectValue:@0   /* (none) */
        forTableColumn:invColumn row:0];
    CHECK(others.inverseRelationship == nil, "center Inverse edit unwires");
    CHECK([other.relationshipsByName[@"thing"] inverseRelationship] == nil,
          "old inverse unwired both ways");
    [wc.detailController tableView:wc.detailController.relationshipTable setObjectValue:@"thing"
        forTableColumn:invColumn row:0];
    CHECK(others.inverseRelationship == other.relationshipsByName[@"thing"],
          "center Inverse edit rewires");
    [wc.detailController tableView:wc.detailController.relationshipTable setObjectValue:@"Thing"
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
    CHECK(wc.inspectorController.attributeRenamingField.isEnabled && wc.inspectorController.entityRenamingField.isEnabled &&
          wc.inspectorController.relationshipRenamingField.isEnabled, "renaming fields enabled");
    CHECK(wc.inspectorController.fetchResultTypePopup.isEnabled && wc.inspectorController.fetchBatchField.isEnabled &&
          wc.inspectorController.fetchDistinctCheckbox.isEnabled, "fetch feature controls enabled");
    CHECK(wc.inspectorController.numberMinField.isEnabled && wc.inspectorController.stringRegexField.isEnabled &&
          wc.inspectorController.dateMinCheckbox.isEnabled, "validation controls enabled");
    CHECK(wc.inspectorController.dateScalarCheckbox.isEnabled, "scalar checkboxes enabled");

    /* cDate (row 2) kept its Date type through the earlier scenarios. */
    selectAttributeRow(wc, 2);
    NSAttributeDescription *cDate = thing.attributesByName[@"cDate"];
    CHECK([wc.inspectorController.attributeRenamingField.stringValue isEqualToString:@"cDate"],
          "renaming field shows the name while defaulted");
    wc.inspectorController.attributeRenamingField.stringValue = @"createdAt";
    commit(wc.inspectorController.attributeRenamingField);
    CHECK([[cDate renamingIdentifier] isEqualToString:@"createdAt"],
          "renaming edit reaches the model");
    [wc.inspectorController.dateScalarCheckbox setState:NSOnState];
    commit(wc.inspectorController.dateScalarCheckbox);
    CHECK([CDModelCompiler attributeUsesScalarValueType:cDate],
          "scalar checkbox sets the codegen flag");
    CHECK(!wc.inspectorController.dateMinPicker.isEnabled, "no lower bound: its picker is off");
    [wc.inspectorController.dateMinCheckbox setState:NSOnState];
    commit(wc.inspectorController.dateMinCheckbox);
    CHECK(wc.inspectorController.dateMinPicker.isEnabled, "ticked, the picker is on");
    wc.inspectorController.dateMinPicker.dateValue = [NSDate dateWithTimeIntervalSinceReferenceDate:100];
    commit(wc.inspectorController.dateMinPicker);
    NSDictionary *dateInfo = [CDModelCompiler validationInfoForAttribute:cDate];
    CHECK([dateInfo[@"minDate"] timeIntervalSinceReferenceDate] == 100,
          "date lower bound applied as a validation predicate");

    /* bInt became a String attribute in the combo-column scenario. */
    selectAttributeRow(wc, 1);
    wc.inspectorController.stringMinField.stringValue = @"2";
    commit(wc.inspectorController.stringMinField);
    wc.inspectorController.stringMaxField.stringValue = @"10";
    commit(wc.inspectorController.stringMaxField);
    wc.inspectorController.stringRegexField.stringValue = @"[a-z]+";
    commit(wc.inspectorController.stringRegexField);
    NSDictionary *strInfo = [CDModelCompiler validationInfoForAttribute:bInt];
    CHECK([strInfo[@"minLength"] isEqualToString:@"2"] &&
          [strInfo[@"maxLength"] isEqualToString:@"10"] &&
          [strInfo[@"regex"] isEqualToString:@"[a-z]+"],
          "string length bounds and regex applied");

    [wc.sourceListController addFetchRequest:nil];   /* adds for Thing, selects it */
    NSString *templateName = wc.inspectorController.fetchNameField.stringValue;
    CHECK(templateName.length > 0, "fetch request added and selected");
    CHECK(wc.inspectorController.fetchSubentitiesCheckbox.state == NSOnState &&
          wc.inspectorController.fetchDistinctCheckbox.state == NSOffState,
          "checkboxes prefill with the runtime defaults");
    [wc.inspectorController.fetchResultTypePopup selectItemAtIndex:2];   /* Dictionaries */
    commit(wc.inspectorController.fetchResultTypePopup);
    wc.inspectorController.fetchBatchField.stringValue = @"25";
    commit(wc.inspectorController.fetchBatchField);
    [wc.inspectorController.fetchDistinctCheckbox setState:NSOnState];
    commit(wc.inspectorController.fetchDistinctCheckbox);
    [wc.inspectorController.fetchSubentitiesCheckbox setState:NSOffState];
    commit(wc.inspectorController.fetchSubentitiesCheckbox);
    NSFetchRequest *template = [doc.modelEditor.model fetchRequestTemplateForName:templateName];
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
    CHECK(([[NSSet setWithArray:[wc.inspectorController.codegenPopup itemTitles]] isEqualToSet:
            [NSSet setWithArray:@[ @"Manual/None", @"Class Definition",
                                   @"Category/Extension" ]]]),
          "xib codegen items match the known modes");
    for (NSInteger i = 0; i < [wc.sourceListController.sourceList numberOfRows]; i++) {
      id item = [wc.sourceListController.sourceList itemAtRow:i];
      if ([item respondsToSelector:@selector(name)] &&
          [[item performSelector:@selector(name)] isEqualToString:@"Thing"]) {
        [wc.sourceListController.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)i]
                   byExtendingSelection:NO];
        break;
      }
    }
    CHECK(wc.inspectorController.codegenPopup.isEnabled, "codegen popup enabled");
    [wc.inspectorController.codegenPopup selectItemAtIndex:1];   /* Class Definition */
    commit(wc.inspectorController.codegenPopup);
    CHECK([[CDModelCompiler entityCodeGenerationType:thing]
              isEqualToString:@"class"], "popup writes the compiler metadata");
    CHECK([wc.inspectorController.codegenPopup indexOfSelectedItem] == 1,
          "refill maps the metadata back to the item");
    xml = [CDModelSerializer contentsXMLForModel:doc.modelEditor.model
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
            value binding, the stepper returns to rest, and it mirrors
            the field's enabled state */
    int owned = 0;
    for (MBStepperTextField *field in @[ wc.inspectorController.numberDefaultField, wc.inspectorController.numberMinField,
                                         wc.inspectorController.numberMaxField, wc.inspectorController.stringMinField,
                                         wc.inspectorController.stringMaxField, wc.inspectorController.minCountField,
                                         wc.inspectorController.maxCountField, wc.inspectorController.fetchLimitField,
                                         wc.inspectorController.fetchBatchField ]) {
      if ([field isKindOfClass:[MBStepperTextField class]] &&
          field.stepper != nil && field.stepper.target == field &&
          field.stepper.superview == field.superview) owned++;
    }
    CHECK(owned == 9, "all 9 fields are MBStepperTextFields with a live stepper");
    CHECK(wc.inspectorController.numberMinField.allowsNegative && !wc.inspectorController.stringMinField.allowsNegative,
          "number bounds signed, lengths clamped at zero");

    selectAttributeRow(wc, 1);   /* bInt (String type), minLength "2" */
    CHECK([wc.inspectorController.stringMinField.stringValue isEqualToString:@"2"],
          "string min length prefilled");
    NSStepper *minStepper = wc.inspectorController.stringMinField.stepper;
    minStepper.doubleValue = 1;   /* an up-click leaves +1 behind */
    [minStepper sendAction:minStepper.action to:minStepper.target];
    CHECK([wc.inspectorController.stringMinField.stringValue isEqualToString:@"3"],
          "up-click increments the field");
    CHECK([[CDModelCompiler validationInfoForAttribute:bInt][@"minLength"]
              isEqualToString:@"3"], "stepped value applied to the model");
    CHECK(minStepper.doubleValue == 0, "stepper back at rest");
    minStepper.doubleValue = -1;  /* a down-click */
    [minStepper sendAction:minStepper.action to:minStepper.target];
    CHECK([wc.inspectorController.stringMinField.stringValue isEqualToString:@"2"],
          "down-click decrements the field");
    wc.inspectorController.minCountField.enabled = NO;
    CHECK(!wc.inspectorController.minCountField.stepper.isEnabled, "stepper follows field enablement");
    wc.inspectorController.minCountField.enabled = YES;

    SCENARIO("Configurations list the implicit Default and inspect their entities");
    /* GIVEN a model that declares no configuration (Thing, ZOther)
       WHEN the CONFIGURATIONS group is shown and Default is selected
       THEN Default is listed, holds every entity, and can be neither
            edited nor renamed -- it is not in the file
       AND WHEN an entity row on its page is selected
       THEN the inspector shows that entity */
    NSInteger defaultRow = -1;
    for (NSInteger r = 0; r < wc.sourceListController.sourceList.numberOfRows; r++) {
      id item = [wc.sourceListController.sourceList itemAtRow:r];
      if ([[item valueForKey:@"implicitDefault"] boolValue]) { defaultRow = r; break; }
    }
    CHECK(defaultRow >= 0, "Default configuration listed");
    [wc.sourceListController.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)defaultRow]
               byExtendingSelection:NO];
    NSTableColumn *memberColumn = [wc.detailController.memberTable tableColumnWithIdentifier:@"member"];
    CHECK([wc.detailController.memberTable numberOfRows] == 2, "Default lists every entity");
    BOOL allMembers = YES;
    for (NSInteger r = 0; r < [wc.detailController.memberTable numberOfRows]; r++)
      allMembers &= [[wc.detailController tableView:wc.detailController.memberTable objectValueForTableColumn:memberColumn
                               row:r] boolValue];
    CHECK(allMembers, "every entity is a member of Default");
    NSCell *memberCell = [memberColumn dataCellForRow:0];
    [wc.detailController tableView:wc.detailController.memberTable willDisplayCell:memberCell forTableColumn:memberColumn row:0];
    CHECK(![memberCell isEnabled], "Default membership is not editable");
    CHECK(![wc.sourceListController outlineView:wc.sourceListController.sourceList shouldEditTableColumn:nil
                      item:[wc.sourceListController.sourceList itemAtRow:defaultRow]],
          "Default cannot be renamed");
    NSString *rowEntity = [wc.detailController tableView:wc.detailController.memberTable
              objectValueForTableColumn:[wc.detailController.memberTable tableColumnWithIdentifier:@"entity"]
                                    row:0];
    [wc.detailController.memberTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                byExtendingSelection:NO];
    CHECK(rowEntity.length && [wc.inspectorController.entityNameField.stringValue isEqualToString:rowEntity],
          "selecting an entity row inspects that entity");

    SCENARIO("The Identity page edits the model version's Identifier");
    /* GIVEN the window over a version with no Identifier
       WHEN the Identity page's Identifier field is set and its editing
            ends
       THEN the model's version identifier is what was typed, as one
            undo step, and the field shows what the model holds */
    CHECK(wc.inspectorController.modelIdentifierField != nil, "modelIdentifierField outlet");
    CHECK([wc.inspectorController.modelIdentifierField.stringValue isEqualToString:@""], "a blank Identifier shows blank");
    [wc.inspectorController.modelIdentifierField setStringValue:@"probe-2"];
    /* Through the xib's binding, not a direct call: the binding is what
       is under test. */
    CHECK([wc.inspectorController.modelIdentifierField infoForBinding:NSValueBinding] != nil, "the field is bound");
    commit(wc.inspectorController.modelIdentifierField);
    CHECK([doc.modelEditor.model.versionIdentifiers isEqual:[NSSet setWithObject:@"probe-2"]],
          "the field sets the model's version identifier");
    [doc.undoManager undo];
    CHECK(doc.modelEditor.model.versionIdentifiers.count == 0, "one undo takes it back");
    [wc.sourceListController.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)defaultRow]
               byExtendingSelection:NO];
    CHECK([wc.inspectorController.modelIdentifierField.stringValue isEqualToString:@""], "the field shows the model's value again");

    SCENARIO("Fetch indexes are listed under their entity and edited there");
    /* GIVEN Thing with the fetch index byString on aString
       WHEN Thing is opened in the source list and byString selected
       THEN the center shows its elements and the inspector its name
       AND an element is added, reordered, made an R-tree, renamed and
           narrowed, each as one undo step, and removing the attribute
           an element names takes it out of the index */
    id thingItem = nil;
    for (NSInteger r = 0; r < wc.sourceListController.sourceList.numberOfRows; r++)
      if ([[[wc.sourceListController.sourceList itemAtRow:r] valueForKey:@"name"] isEqual:@"Thing"]) thingItem = [wc.sourceListController.sourceList itemAtRow:r];
    CHECK(thingItem && [wc.sourceListController outlineView:wc.sourceListController.sourceList isItemExpandable:thingItem]
              && [wc.sourceListController outlineView:wc.sourceListController.sourceList numberOfChildrenOfItem:thingItem] == 1,
          "Thing opens to its one fetch index");
    CHECK(wc.detailController.fetchIndexElementTable && wc.inspectorController.fetchIndexNameField && wc.inspectorController.fetchIndexPredicateField
              && wc.detailController.fetchIndexElementSegmentedControl && wc.detailController.fetchIndexElementsInspector,
          "the fetch index outlets are connected");
    [wc.sourceListController.sourceList expandItem:thingItem];
    id indexItem = [wc.sourceListController outlineView:wc.sourceListController.sourceList child:0 ofItem:thingItem];
    [wc.sourceListController.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[wc.sourceListController.sourceList rowForItem:indexItem]]
               byExtendingSelection:NO];
    CHECK([[[wc.detailController.centerTabView selectedTabViewItem] label] isEqualToString:@"Fetch Index"], "the center shows the index");
    CHECK([[[wc.inspectorController.inspectorKindTabView selectedTabViewItem] label] isEqualToString:@"Fetch Index Inspector"]
              && [wc.inspectorController.fetchIndexNameField.stringValue isEqualToString:@"byString"],
          "and the inspector its name");
    CHECK([wc.detailController.fetchIndexElementTable numberOfRows] == 1, "one element listed");

    NSEntityDescription *indexedThing = doc.modelEditor.model.entitiesByName[@"Thing"];
    [wc.detailController.fetchIndexElementSegmentedControl setSelectedSegment:0];
    [wc.detailController fetchIndexElementSegmentClicked:wc.detailController.fetchIndexElementSegmentedControl];
    NSFetchIndexDescription *edited = [[indexedThing indexes] firstObject];
    CHECK([wc.detailController.fetchIndexElementTable numberOfRows] == 2 && [[[edited.elements lastObject] propertyName] isEqualToString:@"bInt"],
          "+ adds the next property, bInt");

    NSTableColumn *elementOrderColumn = [wc.detailController.fetchIndexElementTable tableColumnWithIdentifier:@"order"];
    NSTableColumn *elementTypeColumn = [wc.detailController.fetchIndexElementTable tableColumnWithIdentifier:@"type"];
    [wc.detailController tableView:wc.detailController.fetchIndexElementTable setObjectValue:@1 forTableColumn:elementOrderColumn row:1];
    CHECK(![[[[indexedThing indexes] firstObject] elements].lastObject isAscending], "Order makes it descending");
    [doc.undoManager undo];
    CHECK([[[[indexedThing indexes] firstObject] elements].lastObject isAscending], "and undo ascending again");
    /* An earlier scenario retyped bInt; an R-tree wants a small number. */
    [MBAttributeEditor editorForAttributeNamed:@"bInt" entity:indexedThing modelEditor:doc.modelEditor].typeName = @"Integer 32";
    [wc.detailController tableView:wc.detailController.fetchIndexElementTable setObjectValue:@1 forTableColumn:elementTypeColumn row:1];
    CHECK([[[[indexedThing indexes] firstObject] elements].lastObject collationType] == NSFetchIndexElementTypeRTree,
          "Type makes the Integer 32 an R-tree element");

    [wc.inspectorController.fetchIndexPredicateField setStringValue:@"aString != nil"];
    commit(wc.inspectorController.fetchIndexPredicateField);
    CHECK([[[[[indexedThing indexes] firstObject] partialIndexPredicate] predicateFormat] isEqualToString:@"aString != nil"],
          "the partial predicate is set, and reads back as written");
    [wc.inspectorController.fetchIndexNameField setStringValue:@"byStringAndCount"];
    commit(wc.inspectorController.fetchIndexNameField);
    CHECK([[[[indexedThing indexes] firstObject] name] isEqualToString:@"byStringAndCount"]
              && [[[wc.sourceListController.sourceList itemAtRow:wc.sourceListController.sourceList.selectedRow] valueForKey:@"name"] isEqualToString:@"byStringAndCount"],
          "renaming it renames it in the list, still selected");

    [doc.modelEditor beginEdit:@"Remove"];
    [[MBEntityEditor editorForEntityNamed:@"Thing" modelEditor:doc.modelEditor] removeAttributeNamed:@"bInt"];
    [doc.modelEditor endEdit];
    CHECK([[[[indexedThing indexes] firstObject] elements] count] == 1, "removing bInt takes it out of the index");
    [doc.undoManager undo];
    CHECK([[[[indexedThing indexes] firstObject] elements] count] == 2 && indexedThing.attributesByName[@"bInt"],
          "and undo puts both back");

    NSString *written = [CDModelSerializer contentsXMLForModel:doc.modelEditor.model entityLayouts:nil error:&error];
    CHECK([written rangeOfString:@"<fetchIndex name=\"byStringAndCount\" partialIndexPredicate=\"aString != nil\">"].location != NSNotFound
              && [written rangeOfString:@"property=\"bInt\" type=\"RTree\""].location != NSNotFound,
          "and it is written as Xcode writes it");

    id otherItem = nil;
    for (NSInteger r = 0; r < wc.sourceListController.sourceList.numberOfRows; r++)
      if ([[[wc.sourceListController.sourceList itemAtRow:r] valueForKey:@"name"] isEqual:@"Other"]) otherItem = [wc.sourceListController.sourceList itemAtRow:r];
    [wc.sourceListController.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[wc.sourceListController.sourceList rowForItem:otherItem]]
               byExtendingSelection:NO];
    [wc.sourceListController addFetchIndex:nil];
    CHECK([[doc.modelEditor.model.entitiesByName[@"Other"] indexes] count] == 1
              && [[[wc.sourceListController.sourceList itemAtRow:wc.sourceListController.sourceList.selectedRow] valueForKey:@"name"] isEqualToString:@"index"],
          "Add Fetch Index makes one on Other, selected");
    [wc.sourceListController removeSourceItem:nil];
    CHECK([[doc.modelEditor.model.entitiesByName[@"Other"] indexes] count] == 0, "and − removes it");

    SCENARIO("Allows External Storage is offered for Binary Data alone");
    /* GIVEN Other's String attribute tag is selected
       WHEN its type becomes Binary Data and Allows External Storage is
            ticked, undone, ticked again, and the type changed back
       THEN the option is offered only for Binary Data, each edit reaches
            the model as one undo step, it is written as Xcode writes it,
            and it goes when the type does */
    NSInteger otherRow = -1;
    for (NSInteger r = 0; r < wc.sourceListController.sourceList.numberOfRows; r++)
      if ([[[wc.sourceListController.sourceList itemAtRow:r] valueForKey:@"name"] isEqual:@"Other"]) otherRow = r;
    CHECK(otherRow >= 0, "Other is listed");
    [wc.sourceListController.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)otherRow] byExtendingSelection:NO];
    selectAttributeRow(wc, 0);
    NSAttributeDescription *tag = [[doc.modelEditor.model.entitiesByName[@"Other"] attributesByName] objectForKey:@"tag"];
    CHECK([wc.inspectorController.attributeNameField.stringValue isEqualToString:@"tag"], "tag is in the inspector");
    CHECK(!wc.inspectorController.externalStorageCheckbox.isEnabled, "not offered for a String");
    [wc.inspectorController.attributeTypePopup selectItemWithTitle:@"Binary"];
    commit(wc.inspectorController.attributeTypePopup);
    tag = [[doc.modelEditor.model.entitiesByName[@"Other"] attributesByName] objectForKey:@"tag"];
    CHECK(tag.attributeType == NSBinaryDataAttributeType, "tag is Binary Data");
    CHECK(wc.inspectorController.externalStorageCheckbox.isEnabled && wc.inspectorController.externalStorageCheckbox.state == NSOffState,
          "offered for Binary Data, unticked");
    [wc.inspectorController.externalStorageCheckbox setState:NSOnState];
    commit(wc.inspectorController.externalStorageCheckbox);
    CHECK(tag.allowsExternalBinaryDataStorage, "ticking it reaches the model");
    written = [CDModelSerializer contentsXMLForModel:doc.modelEditor.model entityLayouts:nil error:&error];
    CHECK([written rangeOfString:@"name=\"tag\" optional=\"YES\" attributeType=\"Binary\" allowsExternalBinaryDataStorage=\"YES\""].location != NSNotFound,
          "and it is written as Xcode writes it");
    [doc.undoManager undo];
    CHECK(!tag.allowsExternalBinaryDataStorage && tag.attributeType == NSBinaryDataAttributeType,
          "one undo takes the option back, not the type");
    [wc.inspectorController.externalStorageCheckbox setState:NSOnState];
    commit(wc.inspectorController.externalStorageCheckbox);
    [wc.inspectorController.attributeTypePopup selectItemWithTitle:@"String"];
    commit(wc.inspectorController.attributeTypePopup);
    tag = [[doc.modelEditor.model.entitiesByName[@"Other"] attributesByName] objectForKey:@"tag"];
    CHECK(tag.attributeType == NSStringAttributeType && !tag.allowsExternalBinaryDataStorage &&
          !wc.inspectorController.externalStorageCheckbox.isEnabled,
          "a String again, the option goes with the type");

    printf("---\n%d passed, %d failed\n", passed, failed);
    exit(failed ? 1 : 0);   /* skip pool teardown */
  }
}
