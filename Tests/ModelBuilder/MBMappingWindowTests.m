/* The mapping window, loaded from its XIBs and driven as a user would,
   over the mapping model Xcode made (MappingFixture.xcmappingmodel:
   Fresh, NoteToNote, TagToTag); and the New Mapping Model panel.  An edit
   is made by changing a control and sending its action, which is what
   gives a bound control's value to what it is bound to.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBMappingDocument.h"
#import "MBMappingEditor.h"
#import "MBMappingWindowController.h"
#import "MBMappingSourceListViewController.h"
#import "MBMappingDetailViewController.h"
#import "MBMappingInspectorViewController.h"
#import "MBNewMappingController.h"

NSString *MBMappingFixturePath(void);   /* MBMappingEditorTests.m */
BOOL MBTypeInto(NSTextField *field, NSString *text);   /* MBModelWindowTests.m */
void MBClickSegment(NSSegmentedControl *control, NSInteger segment);

@interface MBMappingWindowTests : XCTestCase
@end

@implementation MBMappingWindowTests {
  NSString *_fixture;
  MBMappingDocument *_document;
  MBMappingWindowController *_window;
}

- (void)setUp
{
  [super setUp];
  [NSApplication sharedApplication];
  _fixture = MBMappingFixturePath();
  _document = [[MBMappingDocument alloc] init];
  NSError *error = nil;
  XCTAssertTrue([_document readFromURL:[NSURL fileURLWithPath:_fixture] ofType:@"Core Data Mapping Model"
                                 error:&error], @"%@", error);
  [_document makeWindowControllers];
  _window = _document.windowControllers.firstObject;
  XCTAssertNotNil([_window window], @"the window loads from its XIB");
  [[_window window] orderFront:nil];
}

- (void)tearDown
{
  [[_window window] orderOut:nil];
  [_document close];
  [super tearDown];
}

#pragma mark - Helpers

- (MBMappingEditor *)editor { return _document.mappingEditor; }
- (MBMappingInspectorViewController *)inspector { return _window.inspectorController; }
- (MBMappingDetailViewController *)detail { return _window.detailController; }
- (NSOutlineView *)sourceList { return _window.sourceListController.sourceList; }
- (NSUndoManager *)undo { return _document.undoManager; }

- (NSInteger)inspectorKind
{
  NSTabView *kinds = self.inspector.inspectorKindTabView;
  return [kinds indexOfTabViewItem:[kinds selectedTabViewItem]];
}

- (void)select:(NSString *)mappingName
{
  self.editor.selection = [MBMappingSelection entityMappingNamed:mappingName];
}

- (NSEntityMapping *)selectedMapping { return [self.editor selectedEntityMapping]; }

- (id)cellOf:(NSTableView *)table column:(NSString *)column row:(NSInteger)row
{
  return [[table dataSource] tableView:table objectValueForTableColumn:[table tableColumnWithIdentifier:column] row:row];
}

- (NSInteger)rowOf:(NSString *)name inTable:(NSTableView *)table
{
  NSInteger rows = [[table dataSource] numberOfRowsInTableView:table];
  for (NSInteger row = 0; row < rows; row++)
    if ([[self cellOf:table column:@"property" row:row] isEqual:name]) return row;
  return -1;
}

- (void)selectRow:(NSInteger)row inTable:(NSTableView *)table
{
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

- (NSInteger)listedMappings
{
  NSOutlineView *list = self.sourceList;
  id group = [[list dataSource] outlineView:list child:0 ofItem:nil];
  return [[list dataSource] outlineView:list numberOfChildrenOfItem:group];
}

- (void)type:(NSString *)text in:(NSTextField *)field
{
  XCTAssertTrue(MBTypeInto(field, text), @"%@ takes typing", field);
}

- (void)choose:(NSString *)title in:(NSPopUpButton *)popup
{
  [popup selectItemWithTitle:title];
  [popup sendAction:popup.action to:popup.target];
}

#pragma mark - Loading

- (void)testEveryPartsOutletsAreConnected
{
  MBMappingInspectorViewController *inspector = self.inspector;
  MBMappingDetailViewController *detail = self.detail;
  NSArray *outlets = @[
    self.sourceList ?: [NSNull null], _window.entityMappingSegmentedControl ?: [NSNull null],
    detail.mappingInspectorContainer ?: [NSNull null], detail.attributesInspector ?: [NSNull null],
    detail.relationshipsInspector ?: [NSNull null], detail.attributeMappingTable ?: [NSNull null],
    detail.relationshipMappingTable ?: [NSNull null], inspector.inspectorTabBar ?: [NSNull null],
    inspector.inspectorTabView ?: [NSNull null], inspector.inspectorKindTabView ?: [NSNull null],
    inspector.sourceModelLabel ?: [NSNull null], inspector.destinationModelLabel ?: [NSNull null],
    inspector.entityMappingNameField ?: [NSNull null], inspector.sourceEntityPopup ?: [NSNull null],
    inspector.destinationEntityPopup ?: [NSNull null], inspector.mappingTypeLabel ?: [NSNull null],
    inspector.customPolicyField ?: [NSNull null], inspector.sourceFetchPopup ?: [NSNull null],
    inspector.filterPredicateField ?: [NSNull null], inspector.entityUserInfoTable ?: [NSNull null],
    inspector.entityUserInfoSegmentedControl ?: [NSNull null], inspector.attributeNamePopup ?: [NSNull null],
    inspector.attributeExpressionField ?: [NSNull null], inspector.attributeUserInfoTable ?: [NSNull null],
    inspector.relationshipNamePopup ?: [NSNull null], inspector.relationshipSourceFetchPopup ?: [NSNull null],
    inspector.relationshipKeyPathField ?: [NSNull null], inspector.relationshipMappingNameField ?: [NSNull null],
    inspector.relationshipExpressionField ?: [NSNull null], inspector.relationshipUserInfoTable ?: [NSNull null],
    inspector.entityMappingController ?: [NSNull null], inspector.attributeMappingController ?: [NSNull null],
    inspector.relationshipMappingController ?: [NSNull null]
  ];
  XCTAssertFalse([outlets containsObject:[NSNull null]]);
  XCTAssertEqual([inspector.inspectorKindTabView numberOfTabViewItems], 3,
                 @"an entity, an attribute and a relationship page");
}

- (void)testTheMappingsAreListedAndTheModelsNamed
{
  XCTAssertEqual(self.listedMappings, 3);
  XCTAssertTrue([[self.inspector.sourceModelLabel stringValue] hasSuffix:@"MappingFixture.xcdatamodel"]);
  XCTAssertTrue([[self.inspector.destinationModelLabel stringValue] hasSuffix:@"MappingFixture 2.xcdatamodel"]);
}

#pragma mark - An entity mapping

- (void)testASelectedEntityMappingIsInspected
{
  [self select:@"NoteToNote"];
  XCTAssertEqual(self.inspectorKind, MBMappingInspectorKindEntity);
  XCTAssertEqualObjects([self.inspector.entityMappingNameField stringValue], @"NoteToNote");
  XCTAssertEqualObjects([self.inspector.sourceEntityPopup titleOfSelectedItem], @"Note");
  XCTAssertEqualObjects([self.inspector.destinationEntityPopup titleOfSelectedItem], @"Note");
  XCTAssertEqualObjects([self.inspector.mappingTypeLabel stringValue], @"Transform");
  XCTAssertEqual([self.inspector.sourceFetchPopup indexOfSelectedItem], 1, @"a custom source fetch");
  XCTAssertEqualObjects([self.inspector.filterPredicateField stringValue], @"text BEGINSWITH \"keep\"");
  XCTAssertTrue([self.inspector.filterPredicateField isEnabled]);
}

- (void)testTheCentreListsWhatFillsEachDestinationProperty
{
  [self select:@"NoteToNote"];
  NSTableView *attributes = self.detail.attributeMappingTable;
  XCTAssertEqual([[attributes dataSource] numberOfRowsInTableView:attributes], 2);
  XCTAssertEqualObjects([self cellOf:attributes column:@"expression" row:[self rowOf:@"writer" inTable:attributes]],
                        @"$source.author", @"the rename written by hand");
  XCTAssertEqualObjects([self cellOf:attributes column:@"expression" row:[self rowOf:@"text" inTable:attributes]],
                        @"$source.text", @"and the one worked out from the name");
  NSTableView *relationships = self.detail.relationshipMappingTable;
  XCTAssertEqual([[relationships dataSource] numberOfRowsInTableView:relationships], 1);
}

- (void)testNarrowingAMappingFromTheInspectorUndoes
{
  [self select:@"NoteToNote"];
  [self type:@"text BEGINSWITH \"drop\"" in:self.inspector.filterPredicateField];
  XCTAssertEqualObjects([self.editor filterPredicateOfEntityMapping:self.selectedMapping], @"text BEGINSWITH \"drop\"");
  [self.undo undo];
  XCTAssertEqualObjects([self.inspector.filterPredicateField stringValue], @"text BEGINSWITH \"keep\"");
}

- (void)testTheDefaultFetchTakesEveryObject
{
  [self select:@"NoteToNote"];
  [self choose:@"Default" in:self.inspector.sourceFetchPopup];
  XCTAssertNil([self.editor filterPredicateOfEntityMapping:self.selectedMapping]);
  XCTAssertFalse([self.inspector.filterPredicateField isEnabled]);
}

- (void)testThePolicyUserInfoAndNameAreSetAndSurviveASave
{
  [self select:@"NoteToNote"];
  [self type:@"NotePolicy" in:self.inspector.customPolicyField];
  XCTAssertEqualObjects([self.selectedMapping entityMigrationPolicyClassName], @"NotePolicy");
  MBClickSegment(self.inspector.entityUserInfoSegmentedControl, 0);
  NSTableView *info = self.inspector.entityUserInfoTable;
  XCTAssertEqual([[info dataSource] numberOfRowsInTableView:info], 1, @"+ adds an entry");
  [[info dataSource] tableView:info setObjectValue:@"kept" forTableColumn:[info tableColumnWithIdentifier:@"value"] row:0];
  XCTAssertEqualObjects([[self.selectedMapping userInfo] objectForKey:@"key"], @"kept");
  [self type:@"KeepNotes" in:self.inspector.entityMappingNameField];
  XCTAssertNotNil([self.editor entityMappingNamed:@"KeepNotes"], @"renamed from the name field");
  XCTAssertEqualObjects(self.editor.selection.entityMappingName, @"KeepNotes", @"and still selected");

  /* Beside the fixture: the models are found by the paths the file
     records, which are the project's. */
  NSString *saved = [[_fixture stringByDeletingLastPathComponent] stringByAppendingPathComponent:
      [NSString stringWithFormat:@"test-%@.xcmappingmodel", [[NSUUID UUID] UUIDString]]];
  NSError *error = nil;
  XCTAssertTrue([_document writeToURL:[NSURL fileURLWithPath:saved] ofType:@"Core Data Mapping Model" error:&error],
                @"%@", error);
  MBMappingDocument *again = [[MBMappingDocument alloc] init];
  XCTAssertTrue([again readFromURL:[NSURL fileURLWithPath:saved] ofType:@"Core Data Mapping Model" error:&error],
                @"%@", error);
  [[NSFileManager defaultManager] removeItemAtPath:saved error:NULL];
  NSEntityMapping *reread = [again.mappingEditor entityMappingNamed:@"KeepNotes"];
  XCTAssertEqualObjects([reread entityMigrationPolicyClassName], @"NotePolicy");
  XCTAssertEqualObjects([[reread userInfo] objectForKey:@"key"], @"kept");
}

- (void)testAnAddedEntityHasNothingToFetchAndListsXcodesUserInfo
{
  [self select:@"Fresh"];
  XCTAssertEqualObjects([self.inspector.mappingTypeLabel stringValue], @"Add");
  NSTableView *info = self.inspector.entityUserInfoTable;
  XCTAssertEqual([[info dataSource] numberOfRowsInTableView:info], 1);
  XCTAssertEqualObjects([self cellOf:info column:@"key" row:0], @"testkey");
  XCTAssertEqualObjects([self cellOf:info column:@"value" row:0], @"testvalue");
  XCTAssertEqualObjects([self.inspector.sourceEntityPopup titleOfSelectedItem], @"None");
  XCTAssertFalse([self.inspector.sourceFetchPopup isEnabled]);
  XCTAssertFalse([self.inspector.filterPredicateField isEnabled]);
}

- (void)testPairingASourceMakesATransformAndUndoMakesItAnAddAgain
{
  [self select:@"Fresh"];
  [self choose:@"Note" in:self.inspector.sourceEntityPopup];
  XCTAssertEqualObjects([self.selectedMapping sourceEntityName], @"Note");
  XCTAssertEqualObjects([self.inspector.mappingTypeLabel stringValue], @"Transform");
  XCTAssertTrue([self.inspector.sourceFetchPopup isEnabled]);
  [self.undo undo];
  XCTAssertEqualObjects([self.inspector.mappingTypeLabel stringValue], @"Add");
}

#pragma mark - An attribute row

- (void)testASelectedAttributeRowIsInspected
{
  [self select:@"NoteToNote"];
  [self selectRow:[self rowOf:@"writer" inTable:self.detail.attributeMappingTable] inTable:self.detail.attributeMappingTable];
  XCTAssertEqual(self.inspectorKind, MBMappingInspectorKindAttribute);
  XCTAssertEqualObjects([self.inspector.attributeNamePopup titleOfSelectedItem], @"writer");
  XCTAssertTrue([[self.inspector.attributeNamePopup itemTitles] containsObject:@"text"]);
  XCTAssertEqualObjects([self.inspector.attributeExpressionField stringValue], @"$source.author");
}

- (void)testAWorkedOutExpressionLeavesTheFieldEmptyShowingIt
{
  [self select:@"NoteToNote"];
  [self selectRow:[self rowOf:@"text" inTable:self.detail.attributeMappingTable] inTable:self.detail.attributeMappingTable];
  XCTAssertEqualObjects([self.inspector.attributeExpressionField stringValue], @"");
  XCTAssertEqualObjects([[self.inspector.attributeExpressionField cell] placeholderString], @"$source.text");
}

- (void)testTypingAnExpressionEditsTheDocumentAndUndoGivesTheWorkedOutOneBack
{
  [self select:@"NoteToNote"];
  NSTableView *attributes = self.detail.attributeMappingTable;
  NSInteger text = [self rowOf:@"text" inTable:attributes];
  [self selectRow:text inTable:attributes];
  [self type:@"$source.author" in:self.inspector.attributeExpressionField];
  XCTAssertEqualObjects([self cellOf:attributes column:@"expression" row:text], @"$source.author");
  XCTAssertTrue([_document isDocumentEdited]);
  [self.undo undo];
  XCTAssertEqualObjects([self cellOf:attributes column:@"expression" row:text], @"$source.text");
}

- (void)testTheCentresExpressionCellIsEditable
{
  [self select:@"NoteToNote"];
  NSTableView *attributes = self.detail.attributeMappingTable;
  NSInteger text = [self rowOf:@"text" inTable:attributes];
  NSTableColumn *expression = [attributes tableColumnWithIdentifier:@"expression"];
  XCTAssertTrue([[attributes delegate] tableView:attributes shouldEditTableColumn:expression row:text]);
  [[attributes dataSource] tableView:attributes setObjectValue:@"$source.author" forTableColumn:expression row:text];
  NSPropertyMapping *property = [self.editor propertyMappingNamed:@"text" inEntityMapping:self.selectedMapping
                                                     relationships:NO];
  XCTAssertEqualObjects([self.editor valueExpressionStringOfPropertyMapping:property], @"$source.author");
}

#pragma mark - A relationship row

- (void)selectTags
{
  [self select:@"NoteToNote"];
  [self selectRow:0 inTable:self.detail.relationshipMappingTable];
}

- (void)testASelectedRelationshipRowIsInspectedAsGenerated
{
  [self selectTags];
  XCTAssertEqual(self.inspectorKind, MBMappingInspectorKindRelationship);
  XCTAssertTrue(self.detail.attributeMappingTable.selectedRow < 0, @"the attribute row is let go");
  XCTAssertEqualObjects([self.inspector.relationshipNamePopup titleOfSelectedItem], @"tags");
  XCTAssertEqual([self.inspector.relationshipSourceFetchPopup indexOfSelectedItem], 0, @"auto generated");
  XCTAssertEqualObjects([self.inspector.relationshipKeyPathField stringValue], @"tags");
  XCTAssertEqualObjects([self.inspector.relationshipMappingNameField stringValue], @"TagToTag");
  XCTAssertFalse([self.inspector.relationshipExpressionField isEnabled]);
}

- (void)testAMappingNameTypedIsTheOneFilledThroughAndUndoes
{
  [self selectTags];
  [self type:@"Other" in:self.inspector.relationshipMappingNameField];
  NSString *through = nil;
  [self.editor relationshipMappingNamed:@"tags" inEntityMapping:self.selectedMapping keyPath:NULL mappingName:&through];
  XCTAssertEqualObjects(through, @"Other");
  [self.undo undo];
  XCTAssertEqualObjects([self.inspector.relationshipMappingNameField stringValue], @"TagToTag");
}

- (void)testCustomSwapsTheKeyPathForAnExpressionAndBackAgain
{
  [self selectTags];
  [self choose:@"Custom Value Expression" in:self.inspector.relationshipSourceFetchPopup];
  XCTAssertTrue([self.inspector.relationshipExpressionField isEnabled]);
  XCTAssertFalse([self.inspector.relationshipKeyPathField isEnabled]);
  [self choose:@"Auto Generate Value Expression" in:self.inspector.relationshipSourceFetchPopup];
  XCTAssertEqualObjects([self.inspector.relationshipMappingNameField stringValue], @"TagToTag");
}

- (void)testClickingTheMappingAgainInspectsTheMappingAgain
{
  [self selectTags];
  NSOutlineView *list = self.sourceList;
  NSInteger row = [list rowForItem:self.selectedMapping];
  [list selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  [self select:[self.selectedMapping name]];
  XCTAssertEqual(self.inspectorKind, MBMappingInspectorKindEntity);
  XCTAssertEqual(self.editor.selection.kind, MBMappingSelectionEntityMapping);
}

#pragma mark - The bottom bar

- (void)testAMappingIsAddedInspectedAndRemovedFromTheBottomBar
{
  NSInteger before = self.listedMappings;
  MBClickSegment(_window.entityMappingSegmentedControl, 0);
  XCTAssertEqual(self.listedMappings, before + 1);
  XCTAssertEqual(self.inspectorKind, MBMappingInspectorKindEntity);
  MBClickSegment(_window.entityMappingSegmentedControl, 1);
  XCTAssertEqual(self.listedMappings, before);
}

#pragma mark - File > New Mapping Model

- (void)testTheNewMappingPanelLoadsWithItsKeys
{
  XCTAssertTrue([[NSDocumentController sharedDocumentController] respondsToSelector:@selector(newMappingModel:)]);
  MBNewMappingController *panel = [[MBNewMappingController alloc] initWithWindowNibName:@"MBNewMappingPanel"];
  XCTAssertNotNil([panel window]);
  XCTAssertTrue(panel.sourceVersionPopup && panel.destinationVersionPopup && panel.sourcePathLabel &&
                panel.destinationPathLabel && panel.createButton);
  XCTAssertFalse([panel.createButton isEnabled], @"Create waits for the models");
  NSButton *cancel = nil, *create = nil;
  NSMutableArray *views = [NSMutableArray arrayWithObject:[[panel window] contentView]];
  while (views.count) {
    NSView *view = views.lastObject;
    [views removeLastObject];
    if ([view isKindOfClass:[NSButton class]] && [[(NSButton *)view title] isEqualToString:@"Cancel"]) cancel = (NSButton *)view;
    if ([view isKindOfClass:[NSButton class]] && [[(NSButton *)view title] isEqualToString:@"Create…"]) create = (NSButton *)view;
    [views addObjectsFromArray:[view subviews]];
  }
  XCTAssertEqualObjects([cancel keyEquivalent], @"\033", @"Escape (written in base64 in the xib)");
  XCTAssertEqualObjects([create keyEquivalent], @"\r");
}

- (void)testANewMappingModelStartsFromTheVersionBeforeTheCurrentOne
{
  MBNewMappingController *panel = [[MBNewMappingController alloc] initWithWindowNibName:@"MBNewMappingPanel"];
  (void)[panel window];
  NSString *models = [[_fixture stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"MappingFixture.xcdatamodeld"];
  XCTAssertFalse([panel chooseSourceModelAtPath:_fixture], @"a mapping model is not a model");
  XCTAssertTrue([panel chooseSourceModelAtPath:models]);
  XCTAssertEqualObjects([panel.sourceVersionPopup titleOfSelectedItem], @"MappingFixture");
  XCTAssertEqualObjects([panel.destinationVersionPopup titleOfSelectedItem], @"MappingFixture 2");
  XCTAssertTrue([panel.createButton isEnabled]);
  XCTAssertEqualObjects([panel suggestedFileName], @"MappingFixtureToMappingFixture2.xcmappingmodel");
  XCTAssertEqualObjects([panel suggestedDirectory], [_fixture stringByDeletingLastPathComponent]);

  NSString *created = [[_fixture stringByDeletingLastPathComponent] stringByAppendingPathComponent:
      [NSString stringWithFormat:@"new-%@.xcmappingmodel", [[NSUUID UUID] UUIDString]]];
  NSError *error = nil;
  XCTAssertTrue([panel createMappingModelAtPath:created error:&error], @"%@", error);
  MBMappingDocument *made = [[MBMappingDocument alloc] init];
  XCTAssertTrue([made readFromURL:[NSURL fileURLWithPath:created] ofType:@"Core Data Mapping Model" error:&error],
                @"%@", error);
  [[NSFileManager defaultManager] removeItemAtPath:created error:NULL];
  NSArray *names = [[[made.mappingEditor entityMappings] valueForKey:@"name"] sortedArrayUsingSelector:@selector(compare:)];
  XCTAssertEqualObjects(names, (@[ @"Fresh", @"NoteToNote", @"TagToTag" ]), @"the mappings Xcode starts with");
  XCTAssertTrue([made.mappingEditor.sourceModelPath hasSuffix:@"MappingFixture.xcdatamodeld/MappingFixture.xcdatamodel"]);
  XCTAssertFalse([made.mappingEditor.sourceModelPath isAbsolutePath], @"recorded by its path in the project");
}

@end
