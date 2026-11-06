/* The model window, loaded from its XIBs and driven as a user would:
   the source list, the centre's pages and tables, the inspector's bound
   fields.  An edit is made by changing a control and sending its action,
   which is what gives a bound control's value to what it is bound to.
   Each test opens a fresh copy of a package holding Thing (aString = hi,
   bInt = 7, cDate, dBool = YES, others <-> Other.thing, the fetch index
   byString) and Other (tag, thing, sibling), with Thing selected.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBDocument.h"
#import "MBModelEditor.h"
#import "MBEditors.h"
#import "MBWindowController.h"
#import "MBSourceListViewController.h"
#import "MBDetailViewController.h"
#import "MBInspectorViewController.h"
#import "MBStepperTextField.h"
#import "DMTabBar.h"
#import "JUInspectorView.h"
#import "JUInspectorViewContainer.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"

static NSString *const MBWindowTestModelXML =
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

/* A control's edit given to what it is bound to, as a click does: by
   sending its action. */
static void MBCommit(NSControl *control)
{
  [control sendAction:control.action to:control.target];
}

/* What a user does to a text field: click into it, type, and leave it -
   which is when a bound field gives what it holds to its binding,
   validated first when the binding asks.  NO when it would not edit. */
BOOL MBTypeInto(NSTextField *field, NSString *text)
{
  NSWindow *window = field.window;
  if (![window makeFirstResponder:field]) return NO;
  NSText *editor = [field currentEditor];
  if (!editor) return NO;
  [editor selectAll:nil];
  [editor insertText:text];
  return [window makeFirstResponder:nil];
}

/* A segment of a bar's control clicked: momentary controls (as the bars'
   are) keep no selected segment, so it is made one that does. */
void MBClickSegment(NSSegmentedControl *control, NSInteger segment)
{
  control.trackingMode = NSSegmentSwitchTrackingSelectOne;
  control.selectedSegment = segment;
  [control sendAction:control.action to:control.target];
}

@interface MBModelWindowTests : XCTestCase
@end

@implementation MBModelWindowTests {
  NSString *_directory;
  MBDocument *_document;
  MBWindowController *_window;
}

- (void)setUp
{
  [super setUp];
  [NSApplication sharedApplication];
  _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat:@"MBModelWindowTests-%@", [[NSUUID UUID] UUIDString]]];
  NSString *package = [_directory stringByAppendingPathComponent:@"MBProbe.xcdatamodeld"];
  NSString *version = [package stringByAppendingPathComponent:@"MBProbe.xcdatamodel"];
  [[NSFileManager defaultManager] createDirectoryAtPath:version withIntermediateDirectories:YES
                                             attributes:nil error:NULL];
  [MBWindowTestModelXML writeToFile:[version stringByAppendingPathComponent:@"contents"]
                         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  _document = [[MBDocument alloc] init];
  NSError *error = nil;
  XCTAssertTrue([_document readFromURL:[NSURL fileURLWithPath:package] ofType:@"xcdatamodeld" error:&error],
                @"%@", error);
  [_document makeWindowControllers];
  _window = _document.windowControllers.firstObject;
  XCTAssertNotNil([_window window], @"the window loads from its XIB");
  [[_window window] orderFront:nil];
  [self selectSourceItemNamed:@"Thing"];
}

- (void)tearDown
{
  [[_window window] orderOut:nil];
  [_document close];
  [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
  [super tearDown];
}

#pragma mark - Helpers

- (MBModelEditor *)editor { return _document.modelEditor; }
- (MBInspectorViewController *)inspector { return _window.inspectorController; }
- (MBDetailViewController *)detail { return _window.detailController; }
- (NSOutlineView *)sourceList { return _window.sourceListController.sourceList; }
- (NSEntityDescription *)entity:(NSString *)name { return self.editor.model.entitiesByName[name]; }

- (NSInteger)rowOfSourceItemNamed:(NSString *)name
{
  for (NSInteger row = 0; row < self.sourceList.numberOfRows; row++) {
    id item = [self.sourceList itemAtRow:row];
    if ([item respondsToSelector:@selector(name)] && [[item valueForKey:@"name"] isEqual:name]) return row;
  }
  return -1;
}

- (void)selectSourceItemNamed:(NSString *)name
{
  NSInteger row = [self rowOfSourceItemNamed:name];
  XCTAssertTrue(row >= 0, @"%@ is listed", name);
  [self.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

/* Thing's attributes, as the table sorts them: aString, bInt, cDate, dBool. */
- (void)selectAttributeRow:(NSUInteger)row
{
  [self.detail.attributeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

- (NSInteger)detailPage
{
  NSTabView *pages = self.inspector.attributeDetailTabView;
  return [pages indexOfTabViewItem:[pages selectedTabViewItem]];
}

- (void)choose:(NSString *)title in:(NSPopUpButton *)popup
{
  [popup selectItemWithTitle:title];
  MBCommit(popup);
}

- (void)type:(NSString *)text in:(NSTextField *)field
{
  XCTAssertTrue(MBTypeInto(field, text), @"%@ takes typing", field);
}

- (void)tick:(NSButton *)checkbox on:(BOOL)on
{
  checkbox.state = on ? NSOnState : NSOffState;
  MBCommit(checkbox);
}

#pragma mark - Loading

- (void)testEveryPartsOutletsAreConnected
{
  MBInspectorViewController *inspector = self.inspector;
  NSArray *outlets = @[
    self.sourceList ?: [NSNull null], self.detail.attributeTable ?: [NSNull null],
    self.detail.relationshipTable ?: [NSNull null], self.detail.fetchIndexElementTable ?: [NSNull null],
    inspector.attributeTypePopup ?: [NSNull null], inspector.attributeDetailTabView ?: [NSNull null],
    inspector.modelIdentifierField ?: [NSNull null], inspector.fetchIndexNameField ?: [NSNull null],
    inspector.fetchIndexPredicateField ?: [NSNull null], inspector.entityController ?: [NSNull null],
    inspector.attributeController ?: [NSNull null], inspector.relationshipController ?: [NSNull null],
    inspector.fetchController ?: [NSNull null], inspector.fetchIndexController ?: [NSNull null],
    inspector.versionController ?: [NSNull null]
  ];
  XCTAssertFalse([outlets containsObject:[NSNull null]]);
  XCTAssertEqual([inspector.attributeDetailTabView numberOfTabViewItems], 9);
}

- (void)testAnAttributesTypePopupOffersMomcsTypes
{
  [self selectAttributeRow:0];
  XCTAssertEqualObjects([self.inspector.attributeTypePopup itemTitles], [CDModelCompiler attributeTypeNames]);
}

- (void)testTheDeleteRuleItemsAreMomcsSpellings
{
  XCTAssertEqualObjects([NSSet setWithArray:[self.inspector.deleteRulePopup itemTitles]],
                        [NSSet setWithArray:[CDModelCompiler deleteRuleNames]]);
}

- (void)testARelationshipsDeleteRuleIsChosenFromThePopupsOwnItems
{
  [self.detail.relationshipTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  XCTAssertEqualObjects([self.inspector.deleteRulePopup titleOfSelectedItem], @"Nullify");
  [self choose:@"Cascade" in:self.inspector.deleteRulePopup];
  XCTAssertEqual([[self entity:@"Thing"].relationshipsByName[@"others"] deleteRule], NSCascadeDeleteRule);
  XCTAssertEqual([self.inspector.deleteRulePopup numberOfItems], 4, @"no item but its own");
}

- (void)testTheDatePickersShowDateAndTimeAndToday
{
  for (NSDatePicker *picker in @[ self.inspector.dateDefaultPicker, self.inspector.dateMinPicker,
                                  self.inspector.dateMaxPicker ]) {
    XCTAssertEqual(picker.datePickerElements,
                   (NSDatePickerElementFlags)(NSYearMonthDayDatePickerElementFlag | NSHourMinuteSecondDatePickerElementFlag));
    XCTAssertTrue(fabs([picker.dateValue timeIntervalSinceNow]) < 24 * 3600);
    XCTAssertEqual(picker.datePickerStyle, NSTextFieldAndStepperDatePickerStyle);
    XCTAssertEqual(picker.datePickerMode, NSSingleDateMode);
  }
}

- (void)testTheCentresSectionsAreAdoptedByTheirContainersExpanded
{
  MBDetailViewController *detail = self.detail;
  XCTAssertEqual(detail.attributesInspector.superview, detail.entityInspectorContainer);
  XCTAssertEqual(detail.attributesInspector.container, detail.entityInspectorContainer);
  XCTAssertNotNil(detail.attributesInspector.header);
  XCTAssertEqualObjects(detail.attributesInspector.name, @"Attribute Inspector");
  XCTAssertTrue(detail.attributesInspector.expanded && detail.relationshipsInspector.expanded);
  XCTAssertTrue(detail.attributesInspector.index < detail.relationshipsInspector.index ||
                (detail.attributesInspector.index == 0 && detail.relationshipsInspector.index == 1));
  XCTAssertEqual(detail.fetchRequestInspector.container, detail.fetchRequestInspectorContainer);
  XCTAssertEqual(detail.entitiesInspector.container, detail.configurationInspectorContainer);
}

#pragma mark - An attribute's page

- (void)testSelectingAnAttributeShowsItsTypesPageAndDefault
{
  XCTAssertEqual([self.detail.attributeTable numberOfRows], 4);
  [self selectAttributeRow:0];
  XCTAssertEqual(self.detailPage, 2, @"a String's page");
  XCTAssertEqualObjects([self.inspector.attributeTypePopup titleOfSelectedItem], @"String");
  XCTAssertEqual(self.inspector.stringDefaultCheckbox.state, NSOnState);
  XCTAssertEqualObjects(self.inspector.stringDefaultField.stringValue, @"hi");
  [self selectAttributeRow:1];
  XCTAssertEqual(self.detailPage, 1, @"a number's page");
  XCTAssertEqualObjects(self.inspector.numberDefaultField.stringValue, @"7");
  [self selectAttributeRow:2];
  XCTAssertEqual(self.detailPage, 4, @"a Date's page");
  [self selectAttributeRow:3];
  XCTAssertEqual(self.detailPage, 3, @"a Boolean's page");
  XCTAssertEqualObjects([self.inspector.boolDefaultPopup titleOfSelectedItem], @"YES");
}

- (void)testTheTypePopupIsBoundAndRetypesTheAttribute
{
  [self selectAttributeRow:0];
  XCTAssertNotNil([self.inspector.attributeTypePopup infoForBinding:NSSelectedValueBinding]);
  NSAttributeDescription *aString = [self entity:@"Thing"].attributesByName[@"aString"];
  [self choose:@"Date" in:self.inspector.attributeTypePopup];
  XCTAssertEqual(aString.attributeType, NSDateAttributeType);
  XCTAssertNil(aString.defaultValue, @"the old default is dropped");
  XCTAssertEqual(self.detailPage, 4, @"and the page follows");
  [self choose:@"UUID" in:self.inspector.attributeTypePopup];
  XCTAssertEqual(aString.attributeType, NSUUIDAttributeType);
  XCTAssertEqual(self.detailPage, 6);
}

- (void)testATypeFlipThroughTransformableLeavesNoTransformerInTheFile
{
  [self selectAttributeRow:3];
  [self choose:@"Transformable" in:self.inspector.attributeTypePopup];
  [self type:@"NSSecureUnarchiveFromData" in:self.inspector.transformerField];
  NSAttributeDescription *dBool = [self entity:@"Thing"].attributesByName[@"dBool"];
  XCTAssertEqualObjects([dBool valueTransformerName], @"NSSecureUnarchiveFromData");
  [self choose:@"Boolean" in:self.inspector.attributeTypePopup];
  XCTAssertEqual(dBool.attributeType, NSBooleanAttributeType);
  NSString *xml = [CDModelSerializer contentsXMLForModel:self.editor.model entityLayouts:nil error:NULL];
  XCTAssertTrue([xml rangeOfString:@"valueTransformerName"].location == NSNotFound);
}

- (void)testTheRenamingFieldShowsTheNameWhileDefaultedAndSetsTheIdentifier
{
  [self selectAttributeRow:2];
  XCTAssertTrue(self.inspector.attributeRenamingField.isEnabled && self.inspector.entityRenamingField.isEnabled &&
                self.inspector.relationshipRenamingField.isEnabled);
  XCTAssertEqualObjects(self.inspector.attributeRenamingField.stringValue, @"cDate");
  [self type:@"createdAt" in:self.inspector.attributeRenamingField];
  XCTAssertEqualObjects([[self entity:@"Thing"].attributesByName[@"cDate"] renamingIdentifier], @"createdAt");
}

- (void)testTheScalarCheckboxSetsTheCodegenFlag
{
  [self selectAttributeRow:2];
  [self tick:self.inspector.dateScalarCheckbox on:YES];
  XCTAssertTrue([CDModelCompiler attributeUsesScalarValueType:[self entity:@"Thing"].attributesByName[@"cDate"]]);
}

- (void)testTickingALowerDateBoundTurnsItsPickerOnAndSetsTheBound
{
  [self selectAttributeRow:2];
  XCTAssertFalse(self.inspector.dateMinPicker.isEnabled, @"no lower bound: the picker is off");
  [self tick:self.inspector.dateMinCheckbox on:YES];
  XCTAssertTrue(self.inspector.dateMinPicker.isEnabled);
  self.inspector.dateMinPicker.dateValue = [NSDate dateWithTimeIntervalSinceReferenceDate:100];
  MBCommit(self.inspector.dateMinPicker);
  NSDictionary *info = [CDModelCompiler validationInfoForAttribute:[self entity:@"Thing"].attributesByName[@"cDate"]];
  XCTAssertEqual([info[@"minDate"] timeIntervalSinceReferenceDate], 100.0);
}

- (void)testAStringsLengthsAndPatternAreApplied
{
  [self selectAttributeRow:0];
  [self type:@"2" in:self.inspector.stringMinField];
  [self type:@"10" in:self.inspector.stringMaxField];
  [self type:@"[a-z]+" in:self.inspector.stringRegexField];
  NSDictionary *info = [CDModelCompiler validationInfoForAttribute:[self entity:@"Thing"].attributesByName[@"aString"]];
  XCTAssertEqualObjects(info[@"minLength"], @"2");
  XCTAssertEqualObjects(info[@"maxLength"], @"10");
  XCTAssertEqualObjects(info[@"regex"], @"[a-z]+");
}

- (void)testAllowsExternalStorageIsOfferedForBinaryDataAloneAndGoesWithTheType
{
  [self selectSourceItemNamed:@"Other"];
  [self selectAttributeRow:0];
  XCTAssertEqualObjects(self.inspector.attributeNameField.stringValue, @"tag");
  XCTAssertFalse(self.inspector.externalStorageCheckbox.isEnabled, @"not offered for a String");
  [self choose:@"Binary" in:self.inspector.attributeTypePopup];
  NSAttributeDescription *tag = [self entity:@"Other"].attributesByName[@"tag"];
  XCTAssertEqual(tag.attributeType, NSBinaryDataAttributeType);
  XCTAssertTrue(self.inspector.externalStorageCheckbox.isEnabled);
  XCTAssertEqual(self.inspector.externalStorageCheckbox.state, NSOffState);
  [self tick:self.inspector.externalStorageCheckbox on:YES];
  XCTAssertTrue(tag.allowsExternalBinaryDataStorage);
  NSString *xml = [CDModelSerializer contentsXMLForModel:self.editor.model entityLayouts:nil error:NULL];
  XCTAssertTrue([xml rangeOfString:@"name=\"tag\" optional=\"YES\" attributeType=\"Binary\" "
                                   @"allowsExternalBinaryDataStorage=\"YES\""].location != NSNotFound);
  [_document.undoManager undo];
  XCTAssertFalse(tag.allowsExternalBinaryDataStorage);
  XCTAssertEqual(tag.attributeType, NSBinaryDataAttributeType, @"one undo takes the option back, not the type");
  [self tick:self.inspector.externalStorageCheckbox on:YES];
  [self choose:@"String" in:self.inspector.attributeTypePopup];
  XCTAssertEqual(tag.attributeType, NSStringAttributeType);
  XCTAssertFalse(tag.allowsExternalBinaryDataStorage);
  XCTAssertFalse(self.inspector.externalStorageCheckbox.isEnabled);
}

#pragma mark - Stepper fields

- (void)testTheNumericFieldsOwnTheirSteppers
{
  MBInspectorViewController *inspector = self.inspector;
  for (MBStepperTextField *field in @[ inspector.numberDefaultField, inspector.numberMinField, inspector.numberMaxField,
                                       inspector.stringMinField, inspector.stringMaxField, inspector.minCountField,
                                       inspector.maxCountField, inspector.fetchLimitField, inspector.fetchBatchField ]) {
    XCTAssertTrue([field isKindOfClass:[MBStepperTextField class]]);
    XCTAssertTrue(field.stepper != nil && field.stepper.target == field && field.stepper.superview == field.superview);
  }
  XCTAssertTrue(inspector.numberMinField.allowsNegative && !inspector.stringMinField.allowsNegative,
                @"number bounds are signed, lengths clamped at zero");
}

- (void)testAStepGoesThroughTheFieldsBindingToTheModel
{
  [self selectAttributeRow:0];
  [self type:@"2" in:self.inspector.stringMinField];
  NSStepper *stepper = self.inspector.stringMinField.stepper;
  stepper.doubleValue = 1;   /* an up-click leaves +1 behind */
  [stepper sendAction:stepper.action to:stepper.target];
  XCTAssertEqualObjects(self.inspector.stringMinField.stringValue, @"3");
  XCTAssertEqualObjects([CDModelCompiler validationInfoForAttribute:
                            [self entity:@"Thing"].attributesByName[@"aString"]][@"minLength"], @"3");
  XCTAssertEqual(stepper.doubleValue, 0.0, @"the stepper is back at rest");
  stepper.doubleValue = -1;
  [stepper sendAction:stepper.action to:stepper.target];
  XCTAssertEqualObjects(self.inspector.stringMinField.stringValue, @"2");
}

- (void)testAStepperFollowsItsFieldsEnabling
{
  self.inspector.minCountField.enabled = NO;
  XCTAssertFalse(self.inspector.minCountField.stepper.isEnabled);
  self.inspector.minCountField.enabled = YES;
  XCTAssertTrue(self.inspector.minCountField.stepper.isEnabled);
}

#pragma mark - The centre's popup columns

- (void)testTheTypeColumnRetypesAnAttribute
{
  NSTableColumn *column = [self.detail.attributeTable tableColumnWithIdentifier:@"type"];
  NSPopUpButtonCell *cell = (NSPopUpButtonCell *)column.dataCell;
  XCTAssertTrue([cell isKindOfClass:[NSPopUpButtonCell class]]);
  [self.detail tableView:self.detail.attributeTable willDisplayCell:cell forTableColumn:column row:1];
  NSArray *names = [CDModelCompiler attributeTypeNames];
  XCTAssertEqual([cell numberOfItems], (NSInteger)names.count);
  XCTAssertEqualObjects([cell titleOfSelectedItem], @"Integer 32");
  [self.detail tableView:self.detail.attributeTable setObjectValue:@([names indexOfObject:@"String"])
          forTableColumn:column row:1];
  XCTAssertEqual([[self entity:@"Thing"].attributesByName[@"bInt"] attributeType], NSStringAttributeType);
  [self selectAttributeRow:1];
  XCTAssertEqual(self.detailPage, 2, @"and the inspector shows the new type's page");
}

- (void)testTheRelationshipColumnsListTheirChoicesAndRewire
{
  NSTableView *table = self.detail.relationshipTable;
  XCTAssertEqual([table numberOfRows], 1);
  NSTableColumn *destinationColumn = [table tableColumnWithIdentifier:@"destination"];
  NSTableColumn *inverseColumn = [table tableColumnWithIdentifier:@"inverse"];
  NSPopUpButtonCell *destinationCell = (NSPopUpButtonCell *)destinationColumn.dataCell;
  NSPopUpButtonCell *inverseCell = (NSPopUpButtonCell *)inverseColumn.dataCell;
  [self.detail tableView:table willDisplayCell:destinationCell forTableColumn:destinationColumn row:0];
  XCTAssertEqual([destinationCell numberOfItems], 2, @"both entities");
  [self.detail tableView:table willDisplayCell:inverseCell forTableColumn:inverseColumn row:0];
  XCTAssertEqual([inverseCell numberOfItems], 3, @"(none) and the destination's relationships");
  XCTAssertEqualObjects([inverseCell titleOfSelectedItem], @"thing");

  NSEntityDescription *thing = [self entity:@"Thing"], *other = [self entity:@"Other"];
  NSRelationshipDescription *others = thing.relationshipsByName[@"others"];
  [self.detail tableView:table setObjectValue:@0 forTableColumn:inverseColumn row:0];   /* (none) */
  XCTAssertNil(others.inverseRelationship);
  XCTAssertNil([other.relationshipsByName[@"thing"] inverseRelationship], @"unwired both ways");
  [self.detail tableView:table setObjectValue:@"thing" forTableColumn:inverseColumn row:0];
  XCTAssertEqual(others.inverseRelationship, other.relationshipsByName[@"thing"]);
  [self.detail tableView:table setObjectValue:@"Thing" forTableColumn:destinationColumn row:0];
  XCTAssertEqual(others.destinationEntity, thing);
  XCTAssertNil(others.inverseRelationship, @"a stale inverse is dropped on a retarget");
}

#pragma mark - An entity's and a fetch request's pages

- (void)testTheCodegenPopupWritesCodeGenerationType
{
  XCTAssertEqualObjects([NSSet setWithArray:[self.inspector.codegenPopup itemTitles]],
                        ([NSSet setWithArray:@[ @"Manual/None", @"Class Definition", @"Category/Extension" ]]));
  XCTAssertTrue(self.inspector.codegenPopup.isEnabled);
  [self.inspector.codegenPopup selectItemAtIndex:1];
  MBCommit(self.inspector.codegenPopup);
  XCTAssertEqualObjects([CDModelCompiler entityCodeGenerationType:[self entity:@"Thing"]], @"class");
  XCTAssertEqual([self.inspector.codegenPopup indexOfSelectedItem], 1);
  NSString *xml = [CDModelSerializer contentsXMLForModel:self.editor.model entityLayouts:nil error:NULL];
  XCTAssertTrue([xml rangeOfString:@"codeGenerationType=\"class\""].location != NSNotFound);
}

- (void)testAFetchTemplatesShapeAndFlagsAreSetFromItsPage
{
  [_window.sourceListController addFetchRequest:nil];   /* for Thing, selected */
  NSString *name = self.inspector.fetchNameField.stringValue;
  XCTAssertTrue(name.length > 0);
  XCTAssertEqual(self.inspector.fetchSubentitiesCheckbox.state, NSOnState, @"the runtime's defaults");
  XCTAssertEqual(self.inspector.fetchDistinctCheckbox.state, NSOffState);
  [self.inspector.fetchResultTypePopup selectItemAtIndex:2];   /* Dictionaries */
  MBCommit(self.inspector.fetchResultTypePopup);
  [self type:@"25" in:self.inspector.fetchBatchField];
  [self tick:self.inspector.fetchDistinctCheckbox on:YES];
  [self tick:self.inspector.fetchSubentitiesCheckbox on:NO];
  NSFetchRequest *template = [self.editor.model fetchRequestTemplateForName:name];
  XCTAssertEqual(template.resultType, NSDictionaryResultType);
  XCTAssertEqual(template.fetchBatchSize, 25u);
  XCTAssertTrue(template.returnsDistinctResults);
  XCTAssertFalse(template.includesSubentities);
}

#pragma mark - Configurations

- (void)testTheImplicitDefaultConfigurationHoldsEveryEntityAndCannotBeEdited
{
  NSInteger row = -1;
  for (NSInteger r = 0; r < self.sourceList.numberOfRows; r++)
    if ([[[self.sourceList itemAtRow:r] valueForKey:@"implicitDefault"] boolValue]) row = r;
  XCTAssertTrue(row >= 0, @"Default is listed");
  [self.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  NSTableView *members = self.detail.memberTable;
  NSTableColumn *memberColumn = [members tableColumnWithIdentifier:@"member"];
  XCTAssertEqual([members numberOfRows], 2);
  for (NSInteger r = 0; r < [members numberOfRows]; r++)
    XCTAssertTrue([[self.detail tableView:members objectValueForTableColumn:memberColumn row:r] boolValue]);
  NSCell *cell = [memberColumn dataCellForRow:0];
  [self.detail tableView:members willDisplayCell:cell forTableColumn:memberColumn row:0];
  XCTAssertFalse([cell isEnabled]);
  XCTAssertFalse([_window.sourceListController outlineView:self.sourceList shouldEditTableColumn:nil
                                                       item:[self.sourceList itemAtRow:row]]);

  NSString *entity = [self.detail tableView:members
                  objectValueForTableColumn:[members tableColumnWithIdentifier:@"entity"] row:0];
  [members selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  XCTAssertEqualObjects(self.inspector.entityNameField.stringValue, entity,
                        @"an entity row selected is inspected");
}

#pragma mark - The Identity page

- (void)testTheIdentifierFieldIsBoundSetsTheIdentifierAndUndoes
{
  NSTextField *field = self.inspector.modelIdentifierField;
  XCTAssertNotNil([field infoForBinding:NSValueBinding]);
  self.inspector.inspectorTabBar.selectedIndex = 0;   /* the Identity page */
  [self.inspector inspectorTabSelected:self.inspector.inspectorTabBar];
  XCTAssertEqualObjects(field.stringValue, @"");
  [self type:@"probe-2" in:field];
  XCTAssertEqualObjects(self.editor.model.versionIdentifiers, [NSSet setWithObject:@"probe-2"]);
  [_document.undoManager undo];
  XCTAssertEqual(self.editor.model.versionIdentifiers.count, 0u);
  XCTAssertEqualObjects(field.stringValue, @"", @"and the field shows the model's value again");
}

#pragma mark - Fetch indexes

- (id)fetchIndexItem
{
  id thing = [self.sourceList itemAtRow:[self rowOfSourceItemNamed:@"Thing"]];
  [self.sourceList expandItem:thing];
  return [_window.sourceListController outlineView:self.sourceList child:0 ofItem:thing];
}

- (void)selectFetchIndex
{
  id item = [self fetchIndexItem];
  [self.sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self.sourceList rowForItem:item]]
               byExtendingSelection:NO];
}

- (NSFetchIndexDescription *)thingsIndex { return [[self entity:@"Thing"] indexes].firstObject; }

- (void)testAFetchIndexIsListedUnderItsEntityAndInspected
{
  id thing = [self.sourceList itemAtRow:[self rowOfSourceItemNamed:@"Thing"]];
  XCTAssertTrue([_window.sourceListController outlineView:self.sourceList isItemExpandable:thing]);
  XCTAssertEqual([_window.sourceListController outlineView:self.sourceList numberOfChildrenOfItem:thing], 1);
  [self selectFetchIndex];
  XCTAssertEqualObjects([[self.detail.centerTabView selectedTabViewItem] label], @"Fetch Index");
  XCTAssertEqualObjects([[self.inspector.inspectorKindTabView selectedTabViewItem] label], @"Fetch Index Inspector");
  XCTAssertEqualObjects(self.inspector.fetchIndexNameField.stringValue, @"byString");
  XCTAssertEqual([self.detail.fetchIndexElementTable numberOfRows], 1);
}

- (void)testAFetchIndexsElementIsAddedAndOrderedEachUndoable
{
  [self selectFetchIndex];
  MBClickSegment(self.detail.fetchIndexElementSegmentedControl, 0);
  XCTAssertEqual([self.detail.fetchIndexElementTable numberOfRows], 2);
  XCTAssertEqualObjects([self.thingsIndex.elements.lastObject propertyName], @"bInt", @"+ adds the next property");
  NSTableView *table = self.detail.fetchIndexElementTable;
  [self.detail tableView:table setObjectValue:@1 forTableColumn:[table tableColumnWithIdentifier:@"order"] row:1];
  XCTAssertFalse([self.thingsIndex.elements.lastObject isAscending]);
  [_document.undoManager undo];
  XCTAssertTrue([self.thingsIndex.elements.lastObject isAscending]);
}

/* An index is a B-tree or an R-tree, never both (Apple's Core Data
   refuses the mix): the String element goes before the number's index
   is made an R-tree. */
- (void)testAnIndexOfANumberAloneIsMadeAnRTree
{
  [self selectFetchIndex];
  MBClickSegment(self.detail.fetchIndexElementSegmentedControl, 0);
  NSTableView *table = self.detail.fetchIndexElementTable;
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
  MBClickSegment(self.detail.fetchIndexElementSegmentedControl, 1);
  XCTAssertEqual(self.thingsIndex.elements.count, 1u);
  XCTAssertEqualObjects([self.thingsIndex.elements.firstObject propertyName], @"bInt");
  [self.detail tableView:table setObjectValue:@1 forTableColumn:[table tableColumnWithIdentifier:@"type"] row:0];
  XCTAssertEqual([self.thingsIndex.elements.firstObject collationType], NSFetchIndexElementTypeRTree);
  NSString *xml = [CDModelSerializer contentsXMLForModel:self.editor.model entityLayouts:nil error:NULL];
  XCTAssertTrue([xml rangeOfString:@"property=\"bInt\" type=\"RTree\""].location != NSNotFound,
                @"written as Xcode writes it");
}

- (void)testAFetchIndexIsNarrowedAndRenamedFromItsPage
{
  [self selectFetchIndex];
  [self type:@"aString != nil" in:self.inspector.fetchIndexPredicateField];
  XCTAssertEqualObjects([self.thingsIndex.partialIndexPredicate predicateFormat], @"aString != nil");
  [self type:@"byStringAndCount" in:self.inspector.fetchIndexNameField];
  XCTAssertEqualObjects(self.thingsIndex.name, @"byStringAndCount");
  XCTAssertEqualObjects([[self.sourceList itemAtRow:self.sourceList.selectedRow] valueForKey:@"name"],
                        @"byStringAndCount", @"renamed in the list, still selected");
  NSString *xml = [CDModelSerializer contentsXMLForModel:self.editor.model entityLayouts:nil error:NULL];
  XCTAssertTrue([xml rangeOfString:@"<fetchIndex name=\"byStringAndCount\" partialIndexPredicate=\"aString != nil\">"]
                    .location != NSNotFound, @"written as Xcode writes it");
}

- (void)testRemovingAnAttributeTakesItOutOfAnIndexAndUndoPutsBothBack
{
  [self selectFetchIndex];
  MBClickSegment(self.detail.fetchIndexElementSegmentedControl, 0);
  [self.editor beginEdit:@"Remove"];
  [[MBEntityEditor editorForEntityNamed:@"Thing" modelEditor:self.editor] removeAttributeNamed:@"bInt"];
  [self.editor endEdit];
  XCTAssertEqual(self.thingsIndex.elements.count, 1u);
  [_document.undoManager undo];
  XCTAssertEqual(self.thingsIndex.elements.count, 2u);
  XCTAssertNotNil([self entity:@"Thing"].attributesByName[@"bInt"]);
}

- (void)testAFetchIndexIsAddedSelectedAndRemovedFromTheSourceList
{
  [self selectSourceItemNamed:@"Other"];
  [_window.sourceListController addFetchIndex:nil];
  XCTAssertEqual([[self entity:@"Other"] indexes].count, 1u);
  XCTAssertEqualObjects([[self.sourceList itemAtRow:self.sourceList.selectedRow] valueForKey:@"name"], @"index");
  [_window.sourceListController removeSourceItem:nil];
  XCTAssertEqual([[self entity:@"Other"] indexes].count, 0u);
}

@end
