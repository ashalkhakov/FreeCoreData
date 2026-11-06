/* The ModelBuilder document and its model editor, with no window: open,
   edit, versions, configurations, structural surgery, save, compile, and
   undo.  Each test opens a fresh copy of a small package (Person: name,
   age = 7, pets <-> Pet.owner).

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBDocument.h"
#import "MBModelEditor.h"
#import "MBModelCommands.h"
#import "MBEditors.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"

static NSString *const MBTestModelXML =
@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
@"<model type=\"com.apple.IDECoreDataModeler.DataModel\" documentVersion=\"1.0\" minimumToolsVersion=\"Automatic\" sourceLanguage=\"Objective-C\" userDefinedModelVersionIdentifier=\"\">\n"
@"  <entity name=\"Person\" representedClassName=\"NSManagedObject\" syncable=\"YES\">\n"
@"    <attribute name=\"name\" optional=\"YES\" attributeType=\"String\"/>\n"
@"    <attribute name=\"age\" optional=\"YES\" attributeType=\"Integer 32\" defaultValueString=\"7\" usesScalarValueType=\"NO\"/>\n"
@"    <relationship name=\"pets\" optional=\"YES\" toMany=\"YES\" deletionRule=\"Nullify\" destinationEntity=\"Pet\" inverseName=\"owner\" inverseEntity=\"Pet\"/>\n"
@"  </entity>\n"
@"  <entity name=\"Pet\" representedClassName=\"NSManagedObject\" syncable=\"YES\">\n"
@"    <attribute name=\"nickname\" optional=\"YES\" attributeType=\"String\"/>\n"
@"    <relationship name=\"owner\" optional=\"YES\" maxCount=\"1\" deletionRule=\"Nullify\" destinationEntity=\"Person\" inverseName=\"pets\" inverseEntity=\"Person\"/>\n"
@"  </entity>\n"
@"</model>\n";

@interface MBDocumentTests : XCTestCase
@end

@implementation MBDocumentTests {
  NSString *_directory;
  NSString *_package;
  MBDocument *_document;
}

- (void)setUp
{
  [super setUp];
  _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat:@"MBDocumentTests-%@", [[NSUUID UUID] UUIDString]]];
  _package = [_directory stringByAppendingPathComponent:@"MBTest.xcdatamodeld"];
  NSString *version = [_package stringByAppendingPathComponent:@"MBTest.xcdatamodel"];
  [[NSFileManager defaultManager] createDirectoryAtPath:version withIntermediateDirectories:YES
                                             attributes:nil error:NULL];
  [MBTestModelXML writeToFile:[version stringByAppendingPathComponent:@"contents"]
                   atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  _document = [self openPackageAtPath:_package];
}

- (void)tearDown
{
  [[NSFileManager defaultManager] removeItemAtPath:_directory error:NULL];
  [super tearDown];
}

- (MBDocument *)openPackageAtPath:(NSString *)path
{
  MBDocument *document = [[MBDocument alloc] init];
  NSError *error = nil;
  XCTAssertTrue([document readFromURL:[NSURL fileURLWithPath:path] ofType:@"xcdatamodeld" error:&error],
                @"%@", error);
  return document;
}

- (MBModelEditor *)editor { return _document.modelEditor; }
- (NSEntityDescription *)person { return self.editor.model.entitiesByName[@"Person"]; }
- (NSEntityDescription *)pet { return self.editor.model.entitiesByName[@"Pet"]; }
- (NSUndoManager *)undo { return _document.undoManager; }

- (NSString *)serialized
{
  NSError *error = nil;
  NSString *xml = [CDModelSerializer contentsXMLForModel:self.editor.model entityLayouts:nil error:&error];
  XCTAssertNotNil(xml, @"%@", error);
  return xml;
}

- (NSManagedObjectModel *)recompiled
{
  NSError *error = nil;
  NSManagedObjectModel *model = [CDModelCompiler compileModelContentsXML:[self serialized] error:&error];
  XCTAssertNotNil(model, @"%@", error);
  return model;
}

- (NSString *)saveAs:(NSString *)name
{
  NSString *path = [_directory stringByAppendingPathComponent:name];
  NSError *error = nil;
  XCTAssertTrue([_document writeToURL:[NSURL fileURLWithPath:path] ofType:@"xcdatamodeld"
                     forSaveOperation:NSSaveAsOperation originalContentsURL:nil error:&error], @"%@", error);
  return path;
}

#pragma mark - Opening

- (void)testOpeningAPackageLoadsItsModelVersionsAndConfigurations
{
  XCTAssertEqual(self.editor.model.entities.count, 2u);
  XCTAssertEqual([_document versionNames].count, 1u);
  XCTAssertEqual([self.editor configurationNames].count, 0u);
  XCTAssertNotNil([self.person.attributesByName[@"age"] defaultValue], @"age's default is read");
}

#pragma mark - What round-trips through the serializer and momc

- (void)testHashModifiersOfPropertiesAndAConstraintRoundTrip
{
  [self.person.attributesByName[@"name"] setVersionHashModifier:@"v2"];
  [self.person.relationshipsByName[@"pets"] setVersionHashModifier:@"r2"];
  [self.person setUniquenessConstraints:@[ @[ @"name" ] ]];
  NSString *xml = [self serialized];
  XCTAssertTrue([xml rangeOfString:@"versionHashModifier=\"v2\""].location != NSNotFound);
  XCTAssertTrue([xml rangeOfString:@"versionHashModifier=\"r2\""].location != NSNotFound);
  NSEntityDescription *person = [self recompiled].entitiesByName[@"Person"];
  XCTAssertEqualObjects([person.attributesByName[@"name"] versionHashModifier], @"v2");
  XCTAssertEqualObjects([person.relationshipsByName[@"pets"] versionHashModifier], @"r2");
  XCTAssertEqual([person uniquenessConstraints].count, 1u);
}

- (void)testRenamingIdentifiersAreWrittenAsElementIDsAndRead
{
  [self.person setRenamingIdentifier:@"OldPerson"];
  [self.person.attributesByName[@"age"] setRenamingIdentifier:@"years"];
  [self.person.relationshipsByName[@"pets"] setRenamingIdentifier:@"animals"];
  NSString *xml = [self serialized];
  for (NSString *element in @[ @"elementID=\"OldPerson\"", @"elementID=\"years\"", @"elementID=\"animals\"" ])
    XCTAssertTrue([xml rangeOfString:element].location != NSNotFound, @"%@", element);
  NSEntityDescription *person = [self recompiled].entitiesByName[@"Person"];
  XCTAssertEqualObjects([person renamingIdentifier], @"OldPerson");
  XCTAssertEqualObjects([person.attributesByName[@"age"] renamingIdentifier], @"years");
  XCTAssertEqualObjects([person.relationshipsByName[@"pets"] renamingIdentifier], @"animals");
}

- (void)testADefaultedRenamingIdentifierIsTheNameAndIsNotWritten
{
  XCTAssertEqualObjects([self.person.attributesByName[@"name"] renamingIdentifier], @"name");
  XCTAssertTrue([[self serialized] rangeOfString:@"elementID=\"name\""].location == NSNotFound);
}

- (void)testTheScalarFlagAndNumberAndStringValidationRoundTrip
{
  NSAttributeDescription *age = self.person.attributesByName[@"age"];
  [CDModelCompiler setAttribute:age usesScalarValueType:YES];
  [CDModelCompiler applyValidationInfo:@{ @"min" : @"0", @"max" : @"150" } toAttribute:age];
  [CDModelCompiler applyValidationInfo:@{ @"minLength" : @"1", @"maxLength" : @"64", @"regex" : @"[A-Za-z ]+" }
                           toAttribute:self.person.attributesByName[@"name"]];
  NSString *xml = [self serialized];
  XCTAssertTrue([xml rangeOfString:@"usesScalarValueType=\"YES\""].location != NSNotFound);
  XCTAssertTrue([xml rangeOfString:@"maxValueString=\"150\""].location != NSNotFound);
  XCTAssertTrue([xml rangeOfString:@"maxValueString=\"64\""].location != NSNotFound,
                @"string lengths are written as min/maxValueString");
  XCTAssertTrue([xml rangeOfString:@"regularExpressionString="].location != NSNotFound);

  NSEntityDescription *person = [self recompiled].entitiesByName[@"Person"];
  XCTAssertTrue([CDModelCompiler attributeUsesScalarValueType:person.attributesByName[@"age"]]);
  NSDictionary *ageInfo = [CDModelCompiler validationInfoForAttribute:person.attributesByName[@"age"]];
  XCTAssertEqualObjects(ageInfo[@"min"], @"0");
  XCTAssertEqualObjects(ageInfo[@"max"], @"150");
  NSDictionary *nameInfo = [CDModelCompiler validationInfoForAttribute:person.attributesByName[@"name"]];
  XCTAssertEqualObjects(nameInfo[@"minLength"], @"1");
  XCTAssertEqualObjects(nameInfo[@"maxLength"], @"64");
  XCTAssertEqualObjects(nameInfo[@"regex"], @"[A-Za-z ]+");
}

- (void)testDateValidationIsWrittenAsTimeIntervalsAndRead
{
  NSAttributeDescription *born = [[NSAttributeDescription alloc] init];
  born.name = @"born";
  born.attributeType = NSDateAttributeType;
  born.optional = YES;
  [self.person setProperties:[self.person.properties arrayByAddingObject:born]];
  /* not 0: GNUstep's NSDate does not round-trip interval 0 exactly */
  [CDModelCompiler applyValidationInfo:@{ @"minDate" : [NSDate dateWithTimeIntervalSinceReferenceDate:100],
                                          @"maxDate" : [NSDate dateWithTimeIntervalSinceReferenceDate:86400] }
                           toAttribute:born];
  NSString *xml = [self serialized];
  XCTAssertTrue([xml rangeOfString:@"minDateTimeInterval=\"100\""].location != NSNotFound);
  XCTAssertTrue([xml rangeOfString:@"maxDateTimeInterval=\"86400\""].location != NSNotFound);
  NSDictionary *info = [CDModelCompiler validationInfoForAttribute:
      [(NSEntityDescription *)[self recompiled].entitiesByName[@"Person"] attributesByName][@"born"]];
  XCTAssertEqual([info[@"minDate"] timeIntervalSinceReferenceDate], 100.0);
  XCTAssertEqual([info[@"maxDate"] timeIntervalSinceReferenceDate], 86400.0);
}

- (void)testAFetchTemplatesResultShapeAndFlagsAreWrittenAsXcodeSpellsThem
{
  NSFetchRequest *adults = [[NSFetchRequest alloc] init];
  adults.entity = self.person;
  adults.predicate = [NSPredicate predicateWithFormat:@"age >= 18"];
  adults.resultType = NSDictionaryResultType;
  adults.fetchBatchSize = 50;
  adults.includesSubentities = YES;
  adults.includesPropertyValues = YES;
  adults.returnsObjectsAsFaults = NO;   /* NO = absent from the XML */
  adults.includesPendingChanges = YES;  /* clamped: Apple refuses it with dictionary results */
  adults.returnsDistinctResults = YES;
  [self.editor.model setFetchRequestTemplate:adults forName:@"Adults"];
  NSString *xml = [self serialized];
  XCTAssertTrue([xml rangeOfString:@"resultType=\"2\""].location != NSNotFound);
  XCTAssertTrue([xml rangeOfString:@"fetchBatchSize=\"50\""].location != NSNotFound);
  for (NSString *flag in @[ @"includeSubentities=\"YES\"", @"includePropertyValues=\"YES\"",
                            @"returnDistinctResults=\"YES\"" ])
    XCTAssertTrue([xml rangeOfString:flag].location != NSNotFound, @"%@ (Xcode's inconsistent spelling)", flag);
  XCTAssertTrue([xml rangeOfString:@"returnObjectsAsFaults"].location == NSNotFound, @"NO is left out, as momc does");
  XCTAssertTrue([xml rangeOfString:@"includesPendingChanges"].location == NSNotFound);

  NSFetchRequest *read = [[self recompiled] fetchRequestTemplateForName:@"Adults"];
  XCTAssertEqual(read.resultType, NSDictionaryResultType);
  XCTAssertEqual(read.fetchBatchSize, 50u);
  XCTAssertTrue(read.includesSubentities && read.includesPropertyValues && read.returnsDistinctResults);
  XCTAssertFalse(read.includesPendingChanges || read.returnsObjectsAsFaults);
}

#pragma mark - Commands, versions, configurations, surgery

- (void)testValidationRunsMomcsChecks
{
  NSArray *warnings = nil;
  NSError *error = nil;
  XCTAssertTrue([MBModelCommands validateModelOf:self.editor warnings:&warnings error:&error], @"%@", error);
}

- (void)testAVersionIsAddedEditedMadeCurrentAndSwitchedTo
{
  NSString *first = _document.editedVersionName;
  NSString *added = [_document addModelVersion];
  XCTAssertNotNil(added);
  XCTAssertEqual([_document versionNames].count, 2u);
  XCTAssertEqualObjects(_document.editedVersionName, added, @"the new version is the one edited");
  XCTAssertNotEqualObjects(_document.currentVersionName, added, @"the current pointer does not move");
  [_document makeEditedVersionCurrent];
  XCTAssertEqualObjects(_document.currentVersionName, added);
  NSError *error = nil;
  XCTAssertTrue([_document switchToVersion:first error:&error], @"%@", error);
  XCTAssertTrue([_document switchToVersion:added error:&error], @"%@", error);
}

- (void)testAConfigurationIsAddedGivenAMemberRenamedAndRemoved
{
  NSError *error = nil;
  NSString *configuration = [self.editor addConfiguration];
  XCTAssertNotNil(configuration);
  XCTAssertTrue([self.editor setEntityNamed:@"Person" inConfiguration:configuration member:YES error:&error], @"%@", error);
  XCTAssertEqual([[self.editor.model entitiesForConfiguration:configuration] count], 1u);
  XCTAssertTrue([self.editor renameConfiguration:configuration to:@"Lite" error:&error], @"%@", error);
  XCTAssertTrue([self.editor removeConfigurationNamed:@"Lite" error:&error], @"%@", error);
}

- (void)testReparentingAnEntityWiresItAsASubentity
{
  NSError *error = nil;
  XCTAssertTrue([self.editor setParentOfEntityNamed:@"Pet" to:@"Person" error:&error], @"%@", error);
  XCTAssertEqual(self.pet.superentity, self.person);
}

- (void)testSavingKeepsVersionsReparentingAndHashModifiers
{
  [_document addModelVersion];
  [_document makeEditedVersionCurrent];   /* what is reopened */
  [self.editor setParentOfEntityNamed:@"Pet" to:@"Person" error:NULL];
  [self.person.attributesByName[@"name"] setVersionHashModifier:@"v2"];
  MBDocument *reopened = [self openPackageAtPath:[self saveAs:@"Saved.xcdatamodeld"]];
  XCTAssertEqual([reopened versionNames].count, 2u);
  XCTAssertNotNil([reopened.modelEditor.model.entitiesByName[@"Pet"] superentity]);
  XCTAssertEqualObjects([[(NSEntityDescription *)reopened.modelEditor.model.entitiesByName[@"Person"] attributesByName][@"name"]
                            versionHashModifier], @"v2");
}

- (void)testCompilingASavedPackageWritesAMomd
{
  NSString *path = [self saveAs:@"Compiled.xcdatamodeld"];
  NSString *momd = nil;
  NSError *error = nil;
  XCTAssertTrue([MBModelCommands compileModelAtPath:path momdPath:&momd error:&error], @"%@", error);
  XCTAssertTrue(momd && [[NSFileManager defaultManager] fileExistsAtPath:momd]);
  XCTAssertNotNil([[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:momd]]);
}

#pragma mark - Undo

- (MBAttributeEditor *)ageEditor
{
  return [MBAttributeEditor editorForAttributeNamed:@"age" entity:self.person modelEditor:self.editor];
}

- (void)testNothingIsToUndoAfterOpening
{
  XCTAssertFalse(self.undo.canUndo);
  XCTAssertFalse(_document.isDocumentEdited);
}

- (void)testARenameUndoesToTheSameAttributeAndTheDocumentIsUneditedAgain
{
  NSAttributeDescription *age = self.person.attributesByName[@"age"];
  self.ageEditor.name = @"years";
  XCTAssertEqual(self.person.attributesByName[@"years"], age);
  XCTAssertTrue(self.undo.canUndo && _document.isDocumentEdited);
  [self.undo undo];
  XCTAssertEqual(self.person.attributesByName[@"age"], age);
  XCTAssertNil(self.person.attributesByName[@"years"]);
  XCTAssertFalse(_document.isDocumentEdited);
  [self.undo redo];
  XCTAssertEqual(self.person.attributesByName[@"years"], age);
}

- (void)testUndoingATypeChangeRestoresTheTypeAndItsDefault
{
  NSAttributeDescription *age = self.person.attributesByName[@"age"];
  id seven = age.defaultValue;
  self.ageEditor.typeName = @"String";
  XCTAssertEqual(age.attributeType, NSStringAttributeType);
  XCTAssertNil(age.defaultValue, @"the old default belongs to the old type");
  [self.undo undo];
  XCTAssertEqual(age.attributeType, NSInteger32AttributeType);
  XCTAssertEqualObjects(age.defaultValue, seven);
}

- (void)testSeveralFieldsInOneEditUndoAsOneNamedStep
{
  NSAttributeDescription *age = self.person.attributesByName[@"age"];
  MBAttributeEditor *editor = self.ageEditor;
  [self.editor beginEdit:@"Edit Attribute"];
  editor.optional = NO;
  editor.transient = YES;
  editor.hashModifier = @"v2";
  [self.editor endEdit];
  XCTAssertEqualObjects([self.undo undoActionName], @"Edit Attribute");
  [self.undo undo];
  XCTAssertTrue(age.isOptional);
  XCTAssertFalse(age.isTransient);
  XCTAssertNil(age.versionHashModifier);
}

- (void)testAnAddedAttributeIsUndoneAndRedone
{
  NSString *added = [[MBEntityEditor editorForEntityNamed:@"Person" modelEditor:self.editor] addAttribute];
  XCTAssertNotNil(self.person.attributesByName[added]);
  [self.undo undo];
  XCTAssertNil(self.person.attributesByName[added]);
  [self.undo redo];
  XCTAssertNotNil(self.person.attributesByName[added]);
}

- (void)testARemovedRelationshipComesBackWhereItWasWiredBothWays
{
  NSRelationshipDescription *pets = self.person.relationshipsByName[@"pets"];
  NSRelationshipDescription *owner = self.pet.relationshipsByName[@"owner"];
  NSUInteger index = [self.person.properties indexOfObjectIdenticalTo:pets];
  [[MBEntityEditor editorForEntityNamed:@"Person" modelEditor:self.editor] removeRelationshipNamed:@"pets"];
  XCTAssertNil(self.person.relationshipsByName[@"pets"]);
  XCTAssertNil(owner.inverseRelationship, @"its inverse is unwired");
  [self.undo undo];
  XCTAssertEqual(self.person.relationshipsByName[@"pets"], pets);
  XCTAssertEqual([self.person.properties indexOfObjectIdenticalTo:pets], index);
  XCTAssertEqual(owner.inverseRelationship, pets);
  XCTAssertEqual(pets.inverseRelationship, owner);
}

- (void)testRetargetingARelationshipDropsItsInverseAndUndoRewiresIt
{
  NSRelationshipDescription *pets = self.person.relationshipsByName[@"pets"];
  NSRelationshipDescription *owner = self.pet.relationshipsByName[@"owner"];
  [MBRelationshipEditor editorForRelationshipNamed:@"pets" entity:self.person modelEditor:self.editor]
      .destinationName = @"Person";
  XCTAssertEqual(pets.destinationEntity, self.person);
  XCTAssertNil(pets.inverseRelationship);
  [self.undo undo];
  XCTAssertEqual(pets.destinationEntity, self.pet);
  XCTAssertEqual(pets.inverseRelationship, owner);
  XCTAssertEqual(owner.inverseRelationship, pets);
}

- (void)testUndoingToOneMakesARelationshipToManyWithItsCounts
{
  NSRelationshipDescription *pets = self.person.relationshipsByName[@"pets"];
  [MBRelationshipEditor editorForRelationshipNamed:@"pets" entity:self.person modelEditor:self.editor].toMany = NO;
  XCTAssertFalse(pets.isToMany);
  [self.undo undo];
  XCTAssertTrue(pets.isToMany);
  XCTAssertEqual(pets.maxCount, 0u);
}

- (void)testUndoingAnEntitysDeletionPutsTheSameModelBack
{
  NSManagedObjectModel *before = self.editor.model;
  NSEntityDescription *pet = self.pet;
  XCTAssertTrue([self.editor removeEntityNamed:@"Pet" error:NULL]);
  XCTAssertNil(self.pet);
  [self.undo undo];
  XCTAssertEqual(self.editor.model, before);
  XCTAssertEqual(self.pet, pet);
  [self.undo redo];
  XCTAssertNil(self.pet);
}

- (void)testAnAddedEntityAndARenamedOneAreUndone
{
  NSString *added = [self.editor addEntity];
  XCTAssertNotNil(self.editor.model.entitiesByName[added]);
  [self.undo undo];
  XCTAssertNil(self.editor.model.entitiesByName[added]);
  NSEntityDescription *pet = self.pet;
  [self.editor renameEntityNamed:@"Pet" to:@"Animal"];
  [self.undo undo];
  XCTAssertEqual(self.pet, pet);
  XCTAssertNil(self.editor.model.entitiesByName[@"Animal"]);
}

- (void)testAFetchRequestsRenameAndAdditionAreUndoneInTurn
{
  NSString *fetch = [self.editor addFetchRequestForEntityNamed:@"Person"];
  NSFetchRequest *request = [self.editor.model fetchRequestTemplateForName:fetch];
  [self.editor renameFetchRequestNamed:fetch to:@"Everyone"];
  [self.undo undo];
  XCTAssertEqual([self.editor.model fetchRequestTemplateForName:fetch], request);
  XCTAssertNil([self.editor.model fetchRequestTemplateForName:@"Everyone"]);
  [self.undo undo];
  XCTAssertNil([self.editor.model fetchRequestTemplateForName:fetch]);
}

- (void)testAnAddedConfigurationIsUndone
{
  NSString *configuration = [self.editor addConfiguration];
  XCTAssertTrue([[self.editor configurationNames] containsObject:configuration]);
  [self.undo undo];
  XCTAssertFalse([[self.editor configurationNames] containsObject:configuration]);
}

- (void)testUndoingAnAddedVersionEditsTheOldOneAgain
{
  NSString *edited = _document.editedVersionName;
  NSString *version = [_document addModelVersion];
  XCTAssertTrue([[_document versionNames] containsObject:version]);
  [self.undo undo];
  XCTAssertFalse([[_document versionNames] containsObject:version]);
  XCTAssertEqualObjects(_document.editedVersionName, edited);
}

- (void)testUndoingEveryEditLeavesTheDocumentUnedited
{
  self.ageEditor.name = @"years";
  [self.editor addEntity];
  [self.editor addConfiguration];
  [_document addModelVersion];
  while (self.undo.canUndo) [self.undo undo];
  XCTAssertFalse(_document.isDocumentEdited);
}

- (void)testAnEditThatChangesNothingLeavesNothingToUndo
{
  MBAttributeEditor *editor = [MBAttributeEditor editorForAttributeNamed:@"name" entity:self.person
                                                            modelEditor:self.editor];
  [self.editor beginEdit:@"Edit Attribute"];
  editor.optional = editor.isOptional;
  editor.name = @"name";
  editor.typeName = editor.typeName;
  [self.editor endEdit];
  XCTAssertFalse(self.undo.canUndo);
  XCTAssertFalse(_document.isDocumentEdited);
}

#pragma mark - The version's Identifier

- (void)testTheIdentifierTrimmedIsTheModelsVersionIdentifierAndUndoes
{
  MBVersionEditor *editor = [MBVersionEditor editorForModelEditor:self.editor];
  XCTAssertEqualObjects(editor.versionIdentifier, @"");
  XCTAssertEqual(self.editor.model.versionIdentifiers.count, 0u, @"a blank Identifier is none");
  editor.versionIdentifier = @" odata:0123456789abcdef ";
  XCTAssertEqualObjects(self.editor.model.versionIdentifiers, [NSSet setWithObject:@"odata:0123456789abcdef"]);
  XCTAssertTrue(_document.isDocumentEdited);
  [self.undo undo];
  XCTAssertEqual(self.editor.model.versionIdentifiers.count, 0u);
  [self.undo redo];
  XCTAssertEqualObjects([MBVersionEditor editorForModelEditor:self.editor].versionIdentifier,
                        @"odata:0123456789abcdef");
}

- (void)testTheIdentifierIsSavedAsXcodeWritesItAndCompiled
{
  [MBVersionEditor editorForModelEditor:self.editor].versionIdentifier = @"odata:0123456789abcdef";
  NSString *path = [self saveAs:@"Identified.xcdatamodeld"];
  NSString *contents = [NSString stringWithContentsOfFile:[path stringByAppendingPathComponent:@"MBTest.xcdatamodel/contents"]
                                                 encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertTrue([contents rangeOfString:@"userDefinedModelVersionIdentifier=\"odata:0123456789abcdef\""].location
                != NSNotFound);
  NSString *momd = nil;
  NSError *error = nil;
  XCTAssertTrue([MBModelCommands compileModelAtPath:path momdPath:&momd error:&error], @"%@", error);
  NSManagedObjectModel *compiled = [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:momd]];
  XCTAssertEqualObjects(compiled.versionIdentifiers, [NSSet setWithObject:@"odata:0123456789abcdef"]);
}

@end
