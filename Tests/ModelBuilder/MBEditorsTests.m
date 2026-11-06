/* The inspector's view models (MBEditors) and what the model editor
   tells about their edits: key-value validation, -reload, the editors'
   staying valid when the model is replaced, and the change notices, one
   per edit, with the selection's after it.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBModelEditor.h"
#import "MBEditors.h"

static NSString *const MBEditorsTestModelXML =
@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
@"<model type=\"com.apple.IDECoreDataModeler.DataModel\" documentVersion=\"1.0\" sourceLanguage=\"Objective-C\">\n"
@"  <entity name=\"Person\" representedClassName=\"NSManagedObject\" syncable=\"YES\">\n"
@"    <attribute name=\"name\" optional=\"YES\" attributeType=\"String\"/>\n"
@"    <attribute name=\"age\" optional=\"YES\" attributeType=\"Integer 16\" defaultValueString=\"7\"/>\n"
@"    <attribute name=\"born\" optional=\"YES\" attributeType=\"Date\"/>\n"
@"    <fetchIndex name=\"byName\">\n"
@"      <fetchIndexElement property=\"name\" type=\"Binary\" order=\"ascending\"/>\n"
@"    </fetchIndex>\n"
@"  </entity>\n"
@"  <entity name=\"Pet\" representedClassName=\"NSManagedObject\" syncable=\"YES\">\n"
@"    <attribute name=\"nickname\" optional=\"YES\" attributeType=\"String\"/>\n"
@"  </entity>\n"
@"</model>\n";

/* What a binding with NSValidatesImmediately asks before it sets. */
static BOOL MBValid(id object, NSString *key, id value)
{
  id validated = value;
  NSError *error = nil;
  return [object validateValue:&validated forKey:key error:&error];
}

@interface MBEditorsTests : XCTestCase
@end

@implementation MBEditorsTests {
  NSUndoManager *_undo;
  MBModelEditor *_editor;
  NSMutableArray *_notices;
  NSMutableArray *_observed;
}

- (void)setUp
{
  [super setUp];
  _undo = [[NSUndoManager alloc] init];
  [_undo setGroupsByEvent:NO];
  NSError *error = nil;
  _editor = [[MBModelEditor alloc] initWithContentsXML:MBEditorsTestModelXML undoManager:_undo error:&error];
  XCTAssertNotNil(_editor, @"%@", error);
  _notices = [NSMutableArray array];
  _observed = [NSMutableArray array];
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self selector:@selector(notice:) name:MBModelEditorDidChangeNotification object:_editor];
  [center addObserver:self selector:@selector(notice:) name:MBModelEditorSelectionDidChangeNotification object:_editor];
}

- (void)tearDown
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super tearDown];
}

- (void)notice:(NSNotification *)notification
{
  [_notices addObject:notification.name];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  (void)object;
  (void)change;
  (void)context;
  [_observed addObject:keyPath];
}

- (NSEntityDescription *)person { return _editor.model.entitiesByName[@"Person"]; }

- (NSAttributeDescription *)attributeNamed:(NSString *)name { return self.person.attributesByName[name]; }

- (MBAttributeEditor *)attribute:(NSString *)name
{
  return [MBAttributeEditor editorForAttributeNamed:name entity:self.person modelEditor:_editor];
}

#pragma mark - Validation

- (void)testAnEntityNameMustBeGivenAndNew
{
  MBEntityEditor *person = [MBEntityEditor editorForEntityNamed:@"Person" modelEditor:_editor];
  XCTAssertFalse(MBValid(person, @"name", @""));
  XCTAssertFalse(MBValid(person, @"name", @"Pet"), @"another entity has it");
  XCTAssertTrue(MBValid(person, @"name", @"Person"), @"its own name");
  XCTAssertTrue(MBValid(person, @"name", @"Human"));
}

- (void)testAPropertyNameMustBeNewInItsEntity
{
  XCTAssertFalse(MBValid([self attribute:@"name"], @"name", @"age"));
  XCTAssertTrue(MBValid([self attribute:@"name"], @"name", @"fullName"));
}

- (void)testValidationGivesBackTheNameTrimmed
{
  id value = @"  Human ";
  XCTAssertTrue([[MBEntityEditor editorForEntityNamed:@"Person" modelEditor:_editor]
      validateValue:&value forKey:@"name" error:NULL]);
  XCTAssertEqualObjects(value, @"Human");
}

- (void)testAParentThatMakesACycleIsRefused
{
  XCTAssertTrue([_editor setParentOfEntityNamed:@"Pet" to:@"Person" error:NULL]);
  MBEntityEditor *person = [MBEntityEditor editorForEntityNamed:@"Person" modelEditor:_editor];
  XCTAssertFalse(MBValid(person, @"parentTitle", @"Pet"), @"Pet is Person's subentity");
  XCTAssertTrue(MBValid(person, @"parentTitle", @"(none)"));
}

- (void)testAnIntegerDefaultMustFitItsType
{
  MBAttributeEditor *age = [self attribute:@"age"];   /* Integer 16 */
  XCTAssertTrue(MBValid(age, @"defaultNumber", @7));
  XCTAssertTrue(MBValid(age, @"defaultNumber", nil), @"none");
  XCTAssertFalse(MBValid(age, @"defaultNumber", @40000));
  XCTAssertFalse(MBValid(age, @"defaultNumber", @"seven"));
}

- (void)testAUUIDOrURIDefaultMustParse
{
  MBAttributeEditor *name = [self attribute:@"name"];
  name.typeName = @"UUID";
  XCTAssertFalse(MBValid(name, @"defaultString", @"not-a-uuid"));
  XCTAssertTrue(MBValid(name, @"defaultString", @"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"));
}

- (void)testAPatternAndAPredicateMustParse
{
  XCTAssertFalse(MBValid([self attribute:@"name"], @"regexString", @"["));
  XCTAssertTrue(MBValid([self attribute:@"name"], @"regexString", @"[a-z]+"));
  NSString *fetch = [_editor addFetchRequestForEntityNamed:@"Person"];
  MBFetchEditor *editor = [MBFetchEditor editorForFetchRequestNamed:fetch modelEditor:_editor];
  XCTAssertFalse(MBValid(editor, @"predicateFormat", @"name ==="));
  XCTAssertTrue(MBValid(editor, @"predicateFormat", @"name == 'x'"));
}

- (void)testCountsAndLimitsAreWholeNumbersNotBelowZero
{
  NSString *fetch = [_editor addFetchRequestForEntityNamed:@"Person"];
  MBFetchEditor *editor = [MBFetchEditor editorForFetchRequestNamed:fetch modelEditor:_editor];
  XCTAssertFalse(MBValid(editor, @"fetchLimitNumber", @-1));
  XCTAssertFalse(MBValid(editor, @"fetchLimitNumber", @"2.5"));
  XCTAssertTrue(MBValid(editor, @"fetchLimitNumber", @25));
  XCTAssertTrue(MBValid(editor, @"fetchLimitNumber", nil));
}

#pragma mark - The editors as bound objects

- (void)testReloadTellsEveryPropertysObservers
{
  MBAttributeEditor *name = [self attribute:@"name"];
  for (NSString *key in @[ @"name", @"typeName", @"defaultString", @"hasDefaultDate" ])
    [name addObserver:self forKeyPath:key options:0 context:NULL];
  [name reload];
  for (NSString *key in @[ @"name", @"typeName", @"defaultString", @"hasDefaultDate" ]) {
    XCTAssertTrue([_observed containsObject:key], @"%@", key);
    [name removeObserver:self forKeyPath:key];
  }
}

- (void)testAnEditorStaysValidWhenTheModelIsReplaced
{
  MBAttributeEditor *name = [self attribute:@"name"];
  NSManagedObjectModel *before = _editor.model;
  XCTAssertTrue([_editor setParentOfEntityNamed:@"Pet" to:@"Person" error:NULL]);
  XCTAssertNotEqual(_editor.model, before, @"reparenting replaces the model");
  XCTAssertEqual(name.attribute, self.person.attributesByName[@"name"]);
  XCTAssertTrue([name editsSameAs:[self attribute:@"name"]]);
}

- (void)testTickingADateGivesItThePickersDateAndUntickingKeepsItShown
{
  MBAttributeEditor *born = [self attribute:@"born"];
  NSDate *shown = born.shownDefaultDate;
  XCTAssertFalse(born.hasDefaultDate);
  XCTAssertNotNil(shown);
  born.hasDefaultDate = YES;
  XCTAssertEqualObjects(born.defaultDate, shown);
  born.shownDefaultDate = [NSDate dateWithTimeIntervalSinceReferenceDate:1000];
  born.hasDefaultDate = NO;
  XCTAssertNil(born.defaultDate);
  XCTAssertEqualObjects(born.shownDefaultDate, [NSDate dateWithTimeIntervalSinceReferenceDate:1000]);
}

- (void)testAStringsDefaultTickedIsAnEmptyDefaultThatStays
{
  MBAttributeEditor *name = [self attribute:@"name"];
  name.hasDefaultString = YES;
  XCTAssertEqualObjects([self attributeNamed:@"name"].defaultValue, @"");
  name.defaultString = @"";
  XCTAssertTrue(name.hasDefaultString, @"emptied, it is still a default");
  name.hasDefaultString = NO;
  XCTAssertNil([self attributeNamed:@"name"].defaultValue);
}

- (void)testABoundEditIsOneNamedUndoStep
{
  [self attribute:@"name"].transient = YES;
  XCTAssertEqualObjects([_undo undoActionName], @"Edit Attribute");
  [_undo undo];
  XCTAssertFalse([self attributeNamed:@"name"].isTransient);
}

#pragma mark - The notices

- (void)testAnEditIsToldOnceWhenItEnds
{
  MBAttributeEditor *name = [self attribute:@"name"];
  [_editor beginEdit:@"Edit Attribute"];
  name.transient = YES;
  name.optional = NO;
  name.hashModifier = @"v2";
  XCTAssertEqual(_notices.count, 0u, @"nothing is told while the edit is open");
  [_editor endEdit];
  XCTAssertEqualObjects(_notices, @[ MBModelEditorDidChangeNotification ]);
}

- (void)testASelectionChangedInAnEditIsToldAfterTheChange
{
  _editor.selection = [MBSelection entityNamed:@"Person"];
  [_notices removeAllObjects];
  [[MBEntityEditor editorForEntityNamed:@"Person" modelEditor:_editor] setName:@"Human"];
  XCTAssertEqualObjects(_notices, (@[ MBModelEditorDidChangeNotification, MBModelEditorSelectionDidChangeNotification ]));
  XCTAssertEqualObjects(_editor.selection.entityName, @"Human", @"the selection follows the rename");
}

- (void)testAFetchIndexRenamedFromItsEditorStaysSelected
{
  _editor.selection = [MBSelection selectionOfKind:MBSelectionFetchIndex entityName:@"Person"
                                              name:@"byName" configurationName:nil];
  MBFetchIndexEditor *index = [MBFetchIndexEditor editorForFetchIndexNamed:@"byName" entity:self.person
                                                               modelEditor:_editor];
  index.name = @"byFullName";
  XCTAssertEqualObjects([[self.person indexes].firstObject name], @"byFullName");
  XCTAssertEqualObjects(_editor.selection.name, @"byFullName");
  XCTAssertEqualObjects(index.name, @"byFullName");
  XCTAssertNotNil(index.row);
}

@end
