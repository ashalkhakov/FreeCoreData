/* The mapping editor and its view models, with no window: the mapping
   model Xcode made (Tests/MappingFixture.xcmappingmodel, between the two
   versions of MappingFixture.xcdatamodeld) read from its text, edited,
   undone, and written back.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBMappingDocument.h"
#import "MBMappingEditor.h"
#import "MBMappingEditors.h"
#import "CDMappingCompiler.h"

/* The fixture, found from the working directory up (the tests run in
   Tests/ModelBuilder on GNUstep, the project's directory in Xcode). */
NSString *MBMappingFixturePath(void)
{
  NSString *directory = [[NSFileManager defaultManager] currentDirectoryPath];
  for (int i = 0; i < 8; i++) {
    NSString *candidate = [directory stringByAppendingPathComponent:@"Tests/MappingFixture.xcmappingmodel"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    directory = [directory stringByDeletingLastPathComponent];
  }
  NSString *here = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
  return [[here stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"MappingFixture.xcmappingmodel"];
}

static BOOL MBValid(id object, NSString *key, id value)
{
  id validated = value;
  NSError *error = nil;
  return [object validateValue:&validated forKey:key error:&error];
}

@interface MBMappingEditorTests : XCTestCase
@end

@implementation MBMappingEditorTests {
  NSString *_fixture;
  NSUndoManager *_undo;
  MBMappingEditor *_editor;
}

- (void)setUp
{
  [super setUp];
  _fixture = MBMappingFixturePath();
  NSString *xml = [NSString stringWithContentsOfFile:[_fixture stringByAppendingPathComponent:@"xcmapping.xml"]
                                            encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertNotNil(xml, @"the fixture is at %@", _fixture);
  _undo = [[NSUndoManager alloc] init];
  [_undo setGroupsByEvent:NO];
  NSError *error = nil;
  _editor = [[MBMappingEditor alloc] initWithXMLString:xml atPath:_fixture undoManager:_undo error:&error];
  XCTAssertNotNil(_editor, @"%@", error);
}

- (NSEntityMapping *)notes { return [_editor entityMappingNamed:@"NoteToNote"]; }

#pragma mark - Reading

- (void)testTheMappingAndTheModelsItNamesAreRead
{
  XCTAssertEqual([_editor entityMappings].count, 3u);
  XCTAssertNotNil(_editor.sourceModel);
  XCTAssertNotNil(_editor.destinationModel);
  XCTAssertTrue([_editor.sourceModelPath hasSuffix:@"MappingFixture.xcdatamodel"]);
}

- (void)testTheNarrowingPredicateIsReadBack
{
  XCTAssertEqualObjects([_editor filterPredicateOfEntityMapping:self.notes], @"text BEGINSWITH \"keep\"");
}

- (void)testTheDocumentReadsThePackageIntoItsEditor
{
  MBMappingDocument *document = [[MBMappingDocument alloc] init];
  NSError *error = nil;
  XCTAssertTrue([document readFromURL:[NSURL fileURLWithPath:_fixture] ofType:@"Core Data Mapping Model"
                                error:&error], @"%@", error);
  XCTAssertEqual([document.mappingEditor entityMappings].count, 3u);
  XCTAssertFalse(document.undoManager.canUndo, @"reading is not an edit");
}

#pragma mark - The rows

- (void)testEveryDestinationAttributeHasARow
{
  NSArray *names = [[_editor propertyNamesOfEntityMapping:self.notes relationships:NO]
      sortedArrayUsingSelector:@selector(compare:)];
  XCTAssertEqualObjects(names, (@[ @"text", @"writer" ]));
}

/* A mapping added here has no property mappings: its rows are the
   destination's properties, with nothing filling them yet. */
- (NSEntityMapping *)addedMapping
{
  NSEntityMapping *mapping = [_editor addEntityMappingFromEntityNamed:@"Note" toEntityNamed:@"Note"];
  XCTAssertEqual([mapping attributeMappings].count, 0u);
  return mapping;
}

- (void)testReadingTheRowsChangesNothing
{
  NSEntityMapping *added = [self addedMapping];
  [_undo removeAllActions];
  XCTAssertEqual([_editor propertyNamesOfEntityMapping:added relationships:NO].count, 2u);
  XCTAssertNil([_editor propertyMappingNamed:@"text" inEntityMapping:added relationships:NO]);
  XCTAssertEqual([added attributeMappings].count, 0u);
  XCTAssertFalse(_undo.canUndo);
}

- (void)testEditingARowWithoutAMappingMakesOneAndUndoTakesItAway
{
  NSEntityMapping *fresh = [self addedMapping];
  NSUInteger before = [fresh attributeMappings].count;
  MBPropertyMappingEditor *row = [MBPropertyMappingEditor editorForPropertyNamed:@"text" inEntityMapping:fresh
                                                                   relationships:NO mappingEditor:_editor];
  row.valueExpressionString = @"\"made\"";
  XCTAssertNotNil(row.propertyMapping);
  XCTAssertEqualObjects(row.valueExpressionString, @"\"made\"");
  [_undo undo];
  XCTAssertEqual([fresh attributeMappings].count, before, @"one undo takes the mapping and its expression");
}

- (void)testAWrittenExpressionIsShownAndAWorkedOutOneIsNot
{
  NSPropertyMapping *writer = [_editor propertyMappingNamed:@"writer" inEntityMapping:self.notes relationships:NO];
  NSPropertyMapping *text = [_editor propertyMappingNamed:@"text" inEntityMapping:self.notes relationships:NO];
  XCTAssertTrue([[_editor valueExpressionStringOfPropertyMapping:writer] length] > 0);
  XCTAssertNil([_editor valueExpressionStringOfPropertyMapping:text]);
}

#pragma mark - Edits and undo

- (void)testThePredicateChangesUndoesAndRedoes
{
  [_editor setFilterPredicate:@"text BEGINSWITH \"drop\"" forEntityMapping:self.notes];
  XCTAssertEqualObjects([_editor filterPredicateOfEntityMapping:self.notes], @"text BEGINSWITH \"drop\"");
  [_undo undo];
  XCTAssertEqualObjects([_editor filterPredicateOfEntityMapping:self.notes], @"text BEGINSWITH \"keep\"");
  [_undo redo];
  XCTAssertEqualObjects([_editor filterPredicateOfEntityMapping:self.notes], @"text BEGINSWITH \"drop\"");
}

- (void)testAnExpressionIsWrittenRefusedWhenItDoesNotParseAndUndone
{
  NSPropertyMapping *text = [_editor propertyMappingToEditNamed:@"text" inEntityMapping:self.notes relationships:NO];
  NSError *error = nil;
  XCTAssertTrue([_editor setValueExpressionString:@"$source.author" ofPropertyMapping:text error:&error]);
  XCTAssertEqualObjects([_editor valueExpressionStringOfPropertyMapping:text], @"$source.author");
  XCTAssertFalse([_editor setValueExpressionString:@"$source." ofPropertyMapping:text error:&error]);
  [_undo undo];
  XCTAssertNil([_editor valueExpressionStringOfPropertyMapping:text]);
}

- (void)testAnEntityWithNowhereToGoIsARemovalAndUndoTakesItAway
{
  NSUInteger before = [_editor entityMappings].count;
  NSEntityMapping *added = [_editor addEntityMappingFromEntityNamed:@"Obsolete" toEntityNamed:nil];
  XCTAssertEqual([_editor entityMappings].count, before + 1);
  XCTAssertEqual([added mappingType], NSRemoveEntityMappingType);
  [_undo undo];
  XCTAssertEqual([_editor entityMappings].count, before);
}

- (void)testAnAddedMappingTakesANameOfItsOwn
{
  NSEntityMapping *first = [_editor addEntityMappingFromEntityNamed:@"Note" toEntityNamed:@"Note"];
  NSEntityMapping *second = [_editor addEntityMappingFromEntityNamed:@"Note" toEntityNamed:@"Note"];
  XCTAssertNotEqualObjects([first name], [second name]);
}

- (void)testASelectedMappingRenamedStaysSelected
{
  _editor.selection = [MBMappingSelection entityMappingNamed:@"NoteToNote"];
  [_editor setName:@"KeepNotes" ofEntityMapping:self.notes];
  XCTAssertEqualObjects(_editor.selection.entityMappingName, @"KeepNotes");
  [_undo undo];
  XCTAssertEqualObjects(_editor.selection.entityMappingName, @"NoteToNote", @"and follows the undo too");
}

#pragma mark - The view models

- (void)testAnEntityMappingsNameMustBeGivenAndNew
{
  MBEntityMappingEditor *notes = [MBEntityMappingEditor editorForEntityMapping:self.notes mappingEditor:_editor];
  XCTAssertFalse(MBValid(notes, @"name", @""));
  XCTAssertFalse(MBValid(notes, @"name", @"TagToTag"));
  XCTAssertTrue(MBValid(notes, @"name", @"NoteToNote"));
  XCTAssertTrue(MBValid(notes, @"name", @"KeepNotes"));
}

- (void)testAFilterPredicateAndAnExpressionMustParse
{
  MBEntityMappingEditor *notes = [MBEntityMappingEditor editorForEntityMapping:self.notes mappingEditor:_editor];
  XCTAssertFalse(MBValid(notes, @"filterPredicate", @"text ==="));
  XCTAssertTrue(MBValid(notes, @"filterPredicate", @"text != nil"));
  MBPropertyMappingEditor *text = [MBPropertyMappingEditor editorForPropertyNamed:@"text" inEntityMapping:self.notes
                                                                    relationships:NO mappingEditor:_editor];
  XCTAssertFalse(MBValid(text, @"valueExpressionString", @"$source."));
  XCTAssertTrue(MBValid(text, @"valueExpressionString", @"$source.text"));
}

- (void)testPairingAnotherSourceChangesTheTypeAndADefaultNameFollows
{
  NSEntityMapping *fresh = [_editor entityMappingNamed:@"Fresh"];
  MBEntityMappingEditor *editor = [MBEntityMappingEditor editorForEntityMapping:fresh mappingEditor:_editor];
  XCTAssertEqualObjects(editor.mappingTypeName, @"Add");
  XCTAssertFalse(editor.fetchesSource, @"an added entity is fetched from nowhere");
  editor.sourceEntityTitle = @"Note";
  XCTAssertEqualObjects(editor.mappingTypeName, @"Transform");
  XCTAssertTrue(editor.fetchesSource);
  XCTAssertEqual(editor.entityMapping, fresh, @"the editor holds the mapping, whatever it is called");
}

- (void)testChoosingCustomFetchBeforeAnyPredicateIsRemembered
{
  MBEntityMappingEditor *tags = [MBEntityMappingEditor editorForEntityMapping:[_editor entityMappingNamed:@"TagToTag"]
                                                                mappingEditor:_editor];
  XCTAssertEqual(tags.sourceFetchIndex, 0);
  tags.sourceFetchIndex = 1;
  XCTAssertTrue(tags.filtersSource, @"the predicate field is for typing in");
  MBEntityMappingEditor *again = [MBEntityMappingEditor editorForEntityMapping:[_editor entityMappingNamed:@"TagToTag"]
                                                                 mappingEditor:_editor];
  XCTAssertEqual(again.sourceFetchIndex, 1, @"a new editor of it knows too");
}

- (void)testARelationshipRowIsGeneratedThroughItsKeyPathAndMapping
{
  MBPropertyMappingEditor *tags = [MBPropertyMappingEditor editorForPropertyNamed:@"tags" inEntityMapping:self.notes
                                                                    relationships:YES mappingEditor:_editor];
  XCTAssertTrue(tags.generatesExpression);
  XCTAssertEqualObjects(tags.keyPath, @"tags");
  XCTAssertEqualObjects(tags.mappingName, @"TagToTag");
  tags.mappingName = @"Other";
  NSString *through = nil;
  [_editor relationshipMappingNamed:@"tags" inEntityMapping:self.notes keyPath:NULL mappingName:&through];
  XCTAssertEqualObjects(through, @"Other");
  [_undo undo];
  XCTAssertEqualObjects(tags.mappingName, @"TagToTag");
}

#pragma mark - Writing

- (void)testTheTextWrittenCompilesWithItsMappingsAndNarrowing
{
  NSError *error = nil;
  NSString *xml = [_editor XMLString:&error];
  XCTAssertNotNil(xml, @"%@", error);
  NSMappingModel *compiled = [CDMappingCompiler mappingModelFromXMLString:xml atPath:_fixture
                                                              sourceModel:_editor.sourceModel
                                                         destinationModel:_editor.destinationModel
                                                                    error:&error];
  XCTAssertNotNil(compiled, @"%@", error);
  XCTAssertEqual([compiled entityMappings].count, 3u);
  NSEntityMapping *notes = nil;
  for (NSEntityMapping *mapping in [compiled entityMappings])
    if ([[mapping name] isEqualToString:@"NoteToNote"]) notes = mapping;
  XCTAssertNotNil([notes sourceExpression]);
}

- (void)testTheTextWrittenKeepsWhatOnlyXcodePutsThere
{
  NSString *read = [NSString stringWithContentsOfFile:[_fixture stringByAppendingPathComponent:@"xcmapping.xml"]
                                             encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertTrue([read rangeOfString:@"name=\"sourcemodeldata\""].location != NSNotFound,
                @"Xcode wrote an archive of each model");
  NSString *written = [_editor XMLString:NULL];
  XCTAssertTrue([written rangeOfString:@"sourcemodeldata"].location != NSNotFound);
  XCTAssertTrue([written rangeOfString:@"destinationmodeldata"].location != NSNotFound);
}

@end
