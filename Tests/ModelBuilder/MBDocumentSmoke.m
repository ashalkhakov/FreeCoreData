/* Headless smoke test for the ModelBuilder document layer - no window
   and no display: everything beneath the UI (open, edit, versions,
   configurations, structural surgery, save, compile).  Scenario
   framing as in MBWindowProbe.m; see README.md.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBDocument.h"
#import "MBEditors.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"

static int passed = 0, failed = 0;
#define CHECK(cond, name) do { \
  if (cond) { passed++; printf("  ok   %s\n", name); } \
  else { failed++; printf("  FAIL %s\n", name); } \
} while (0)
#define SCENARIO(title) printf("\nScenario: %s\n", title)

static NSString *kModelXML =
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

static NSString *writeSamplePackage(void)
{
  NSString *root = [NSTemporaryDirectory()
      stringByAppendingPathComponent:@"MBSmoke.xcdatamodeld"];
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm removeItemAtPath:root error:NULL];
  NSString *version = [root stringByAppendingPathComponent:@"MBSmoke.xcdatamodel"];
  [fm createDirectoryAtPath:version withIntermediateDirectories:YES attributes:nil error:NULL];
  [kModelXML writeToFile:[version stringByAppendingPathComponent:@"contents"]
              atomically:YES encoding:NSUTF8StringEncoding error:NULL];
  return root;
}

int main(void)
{
  @autoreleasepool {
    NSString *path = writeSamplePackage();
    MBDocument *doc = [[MBDocument alloc] init];
    NSError *error = nil;
    BOOL ok = [doc readFromURL:[NSURL fileURLWithPath:path]
                        ofType:@"xcdatamodeld"
                         error:&error];
    SCENARIO("Opening a .xcdatamodeld package");
    /* GIVEN a package with one version holding Person and Pet
       WHEN the document reads it
       THEN the model, version list and (empty) configurations load */
    CHECK(ok, "open .xcdatamodeld");
    CHECK(doc.model.entities.count == 2, "two entities");
    CHECK([doc versionNames].count == 1, "one version");
    CHECK([doc configurationNames].count == 0, "no configurations");

    /* entity editing */
    NSEntityDescription *person = doc.model.entitiesByName[@"Person"];
    CHECK(person != nil, "Person present");
    CHECK([[person attributesByName][@"age"] defaultValue] != nil, "age default read");

    SCENARIO("Property-level version hash modifiers round-trip");
    /* GIVEN hash modifiers set on an attribute and a relationship,
            and a uniqueness constraint on the entity
       WHEN the model is serialized and recompiled through momc
       THEN all three survive the round trip */
    /* property-level versionHashModifier round-trips (new) */
    NSAttributeDescription *nameAttr = [person attributesByName][@"name"];
    [nameAttr setVersionHashModifier:@"v2"];
    NSRelationshipDescription *pets = [person relationshipsByName][@"pets"];
    [pets setVersionHashModifier:@"r2"];
    [person setUniquenessConstraints:@[ @[ @"name" ] ]];
    NSString *xml = [CDModelSerializer contentsXMLForModel:doc.model
                                             entityLayouts:nil
                                                     error:&error];
    CHECK(xml != nil, "serialize edited model");
    CHECK([xml rangeOfString:@"versionHashModifier=\"v2\""].location != NSNotFound,
          "attribute hash modifier serialized");
    CHECK([xml rangeOfString:@"versionHashModifier=\"r2\""].location != NSNotFound,
          "relationship hash modifier serialized");
    NSManagedObjectModel *recompiled =
        [CDModelCompiler compileModelContentsXML:xml error:&error];
    CHECK(recompiled != nil, "recompile serialized model");
    NSEntityDescription *person2 = recompiled.entitiesByName[@"Person"];
    CHECK([[[person2 attributesByName][@"name"] versionHashModifier]
              isEqualToString:@"v2"], "attribute hash modifier recompiled");
    CHECK([[[person2 relationshipsByName][@"pets"] versionHashModifier]
              isEqualToString:@"r2"], "relationship hash modifier recompiled");
    CHECK([person2 uniquenessConstraints].count == 1, "constraint recompiled");

    SCENARIO("Renaming IDs, fetch features, scalar flags and validation round-trip");
    /* GIVEN renaming identifiers on an entity, an attribute and a
            relationship, a fetch template using result type, batch
            size and the five template flags, a usesScalarValueType
            codegen flag, and numeric, string and date validation
       WHEN the model is serialized and recompiled through momc
       THEN the XML carries Xcode's spellings (including the
            inconsistent include/includes flag names, YES-only) and
            every value survives the round trip */
    NSAttributeDescription *age = [person attributesByName][@"age"];
    [person setRenamingIdentifier:@"OldPerson"];
    [age setRenamingIdentifier:@"years"];
    [pets setRenamingIdentifier:@"animals"];
    CHECK([[[person attributesByName][@"name"] renamingIdentifier]
              isEqualToString:@"name"], "renamingIdentifier defaults to the name");
    [CDModelCompiler setAttribute:age usesScalarValueType:YES];
    [CDModelCompiler applyValidationInfo:@{ @"min": @"0", @"max": @"150" }
                             toAttribute:age];
    [CDModelCompiler applyValidationInfo:@{ @"minLength": @"1", @"maxLength": @"64",
                                            @"regex": @"[A-Za-z ]+" }
                             toAttribute:nameAttr];
    NSAttributeDescription *born = [[NSAttributeDescription alloc] init];
    [born setName:@"born"];
    [born setAttributeType:NSDateAttributeType];
    [born setOptional:YES];
    [person setProperties:[[person properties] arrayByAddingObject:born]];
    [CDModelCompiler applyValidationInfo:@{
        /* not 0: GNUstep's NSDate does not round-trip interval 0 exactly */
        @"minDate": [NSDate dateWithTimeIntervalSinceReferenceDate:100],
        @"maxDate": [NSDate dateWithTimeIntervalSinceReferenceDate:86400] }
                             toAttribute:born];
    NSFetchRequest *adults = [[NSFetchRequest alloc] init];
    [adults setEntity:person];
    [adults setPredicate:[NSPredicate predicateWithFormat:@"age >= 18"]];
    [adults setResultType:NSDictionaryResultType];
    [adults setFetchBatchSize:50];
    [adults setIncludesSubentities:YES];
    [adults setIncludesPropertyValues:YES];
    [adults setReturnsObjectsAsFaults:NO];   /* NO = absent from the XML */
    /* clamped to NO: Apple does not support YES with dictionary results */
    [adults setIncludesPendingChanges:YES];
    [adults setReturnsDistinctResults:YES];
    [doc.model setFetchRequestTemplate:adults forName:@"Adults"];
    xml = [CDModelSerializer contentsXMLForModel:doc.model
                                   entityLayouts:nil
                                           error:&error];
    CHECK(xml != nil, "serialize model with the new features");
    CHECK([xml rangeOfString:@"elementID=\"OldPerson\""].location != NSNotFound,
          "entity renaming spelled elementID");
    CHECK([xml rangeOfString:@"renamingIdentifier=\"years\""].location != NSNotFound,
          "attribute renamingIdentifier serialized");
    CHECK([xml rangeOfString:@"renamingIdentifier=\"animals\""].location != NSNotFound,
          "relationship renamingIdentifier serialized");
    CHECK([xml rangeOfString:@"renamingIdentifier=\"name\""].location == NSNotFound,
          "defaulted renamingIdentifier not serialized");
    CHECK([xml rangeOfString:@"usesScalarValueType=\"YES\""].location != NSNotFound,
          "usesScalarValueType serialized");
    CHECK([xml rangeOfString:@"minValueString=\"0\""].location != NSNotFound &&
          [xml rangeOfString:@"maxValueString=\"150\""].location != NSNotFound,
          "numeric bounds serialized");
    CHECK([xml rangeOfString:@"minValueString=\"1\""].location != NSNotFound &&
          [xml rangeOfString:@"maxValueString=\"64\""].location != NSNotFound,
          "string length bounds serialized as min/maxValueString");
    CHECK([xml rangeOfString:@"regularExpressionString="].location != NSNotFound,
          "regularExpressionString serialized");
    CHECK([xml rangeOfString:@"minDateTimeInterval=\"100\""].location != NSNotFound &&
          [xml rangeOfString:@"maxDateTimeInterval=\"86400\""].location != NSNotFound,
          "date bounds serialized as timeIntervals");
    CHECK([xml rangeOfString:@"resultType=\"2\""].location != NSNotFound,
          "dictionary resultType spelled 2");
    CHECK([xml rangeOfString:@"fetchBatchSize=\"50\""].location != NSNotFound,
          "fetchBatchSize serialized");
    CHECK([xml rangeOfString:@"includeSubentities=\"YES\""].location != NSNotFound &&
          [xml rangeOfString:@"includePropertyValues=\"YES\""].location != NSNotFound &&
          [xml rangeOfString:@"returnDistinctResults=\"YES\""].location != NSNotFound,
          "YES flags use Xcode's (inconsistent) spellings");
    CHECK([xml rangeOfString:@"returnObjectsAsFaults"].location == NSNotFound,
          "NO flag left absent, like Apple momc");
    CHECK([xml rangeOfString:@"includesPendingChanges"].location == NSNotFound,
          "pendingChanges clamped off for dictionary results (Apple rule)");
    recompiled = [CDModelCompiler compileModelContentsXML:xml error:&error];
    CHECK(recompiled != nil, "recompile with the new features");
    person2 = recompiled.entitiesByName[@"Person"];
    CHECK([[person2 renamingIdentifier] isEqualToString:@"OldPerson"],
          "entity renaming recompiled");
    NSAttributeDescription *age2 = [person2 attributesByName][@"age"];
    CHECK([[age2 renamingIdentifier] isEqualToString:@"years"],
          "attribute renaming recompiled");
    CHECK([[[person2 relationshipsByName][@"pets"] renamingIdentifier]
              isEqualToString:@"animals"], "relationship renaming recompiled");
    CHECK([CDModelCompiler attributeUsesScalarValueType:age2],
          "scalar flag recompiled");
    NSDictionary *ageInfo = [CDModelCompiler validationInfoForAttribute:age2];
    CHECK([ageInfo[@"min"] isEqualToString:@"0"] &&
          [ageInfo[@"max"] isEqualToString:@"150"], "numeric validation recompiled");
    NSDictionary *nameInfo = [CDModelCompiler
        validationInfoForAttribute:[person2 attributesByName][@"name"]];
    CHECK([nameInfo[@"minLength"] isEqualToString:@"1"] &&
          [nameInfo[@"maxLength"] isEqualToString:@"64"] &&
          [nameInfo[@"regex"] isEqualToString:@"[A-Za-z ]+"],
          "string validation recompiled");
    NSDictionary *bornInfo = [CDModelCompiler
        validationInfoForAttribute:[person2 attributesByName][@"born"]];
    CHECK([bornInfo[@"minDate"] timeIntervalSinceReferenceDate] == 100 &&
          [bornInfo[@"maxDate"] timeIntervalSinceReferenceDate] == 86400,
          "date validation recompiled");
    NSFetchRequest *adults2 =
        [recompiled fetchRequestTemplateForName:@"Adults"];
    CHECK(adults2 != nil, "fetch template recompiled");
    CHECK([adults2 resultType] == NSDictionaryResultType, "resultType recompiled");
    CHECK([adults2 fetchBatchSize] == 50, "fetchBatchSize recompiled");
    CHECK([adults2 includesSubentities] && [adults2 includesPropertyValues] &&
          ![adults2 includesPendingChanges] && [adults2 returnsDistinctResults] &&
          ![adults2 returnsObjectsAsFaults], "the five flags recompiled");

    SCENARIO("Validation runs momc's checks in-process");
    /* validation */
    NSArray *warnings = nil;
    CHECK([doc validateModel:&error warnings:&warnings], "validateModel");

    SCENARIO("Model versions: add, make current, switch");
    /* GIVEN the single-version document
       WHEN a version is added, made current, and switched away/back
       THEN the edited/current pointers behave like Xcode's */
    /* versions */
    NSString *newVersion = [doc addModelVersion];
    CHECK(newVersion != nil, "addModelVersion");
    CHECK([doc versionNames].count == 2, "two versions");
    CHECK([doc.editedVersionName isEqualToString:newVersion], "editing the new version");
    CHECK(![doc.currentVersionName isEqualToString:newVersion], "current pointer unmoved");
    [doc makeEditedVersionCurrent];
    CHECK([doc.currentVersionName isEqualToString:newVersion], "makeEditedVersionCurrent");
    CHECK([doc switchToVersion:[doc versionNames].firstObject error:&error],
          "switchToVersion");
    CHECK([doc switchToVersion:newVersion error:&error], "switch back");

    SCENARIO("Configurations: add, membership, rename, remove");
    /* All four run through CDModelMutator, so momc renormalizes each
       change. */
    /* configurations */
    NSString *configuration = [doc addConfiguration];
    CHECK(configuration != nil, "addConfiguration");
    CHECK([doc setEntityNamed:@"Person" inConfiguration:configuration member:YES error:&error],
          "configuration membership add");
    CHECK([[doc.model entitiesForConfiguration:configuration] count] == 1,
          "membership visible");
    CHECK([doc renameConfiguration:configuration to:@"Lite" error:&error],
          "renameConfiguration");
    CHECK([doc removeConfigurationNamed:@"Lite" error:&error], "removeConfiguration");

    SCENARIO("Reparenting an entity is graph surgery");
    /* GIVEN Pet and Person
       WHEN Pet is reparented under Person via the document API
       THEN the recompiled model shows the subentity wiring */
    /* structural surgery */
    BOOL mutated = [doc setParentOfEntityNamed:@"Pet" to:@"Person" error:&error];
    CHECK(mutated, "reparent via document API (CDModelMutator)");
    CHECK([doc.model.entitiesByName[@"Pet"] superentity] ==
          doc.model.entitiesByName[@"Person"], "Pet reparented under Person");

    SCENARIO("Saving and reopening preserves everything");
    /* save + reopen */
    NSString *savePath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"MBSmokeSaved.xcdatamodeld"];
    [[NSFileManager defaultManager] removeItemAtPath:savePath error:NULL];
    ok = [doc writeToURL:[NSURL fileURLWithPath:savePath]
                  ofType:@"xcdatamodeld"
        forSaveOperation:NSSaveAsOperation
     originalContentsURL:nil
                   error:&error];
    CHECK(ok, "save package");
    MBDocument *doc2 = [[MBDocument alloc] init];
    ok = [doc2 readFromURL:[NSURL fileURLWithPath:savePath]
                    ofType:@"xcdatamodeld"
                     error:&error];
    CHECK(ok, "reopen saved package");
    CHECK([doc2 versionNames].count == 2, "versions survive save");
    CHECK([doc2.model.entitiesByName[@"Pet"] superentity] != nil,
          "reparenting survives save");
    CHECK([[[doc2.model.entitiesByName[@"Person"] attributesByName][@"name"]
              versionHashModifier] isEqualToString:@"v2"],
          "hash modifier survives save");

    SCENARIO("Compile to momd produces a loadable artifact");
    /* compile to momd (document must be saved: fileURL set by write) */
    [doc2 setFileURL:[NSURL fileURLWithPath:savePath]];
    NSString *momdPath = nil;
    CHECK([doc2 compileToMomd:&error momdPath:&momdPath], "compileToMomd");
    CHECK(momdPath != nil &&
          [[NSFileManager defaultManager] fileExistsAtPath:momdPath],
          "momd exists");

    {
    SCENARIO("Undo takes back each edit, and redo does it again");
    /* GIVEN a freshly opened document (Person: name, age = 7, pets <->
            Pet.owner)
       WHEN edits of every kind are made -- values, a type change that
            drops a default, several fields at once, properties added and
            removed, relationships retargeted, entities added, renamed and
            deleted, fetch requests, configurations, versions
       THEN each undoes as one step back to exactly what it was -- the
            same objects, wired as they were -- redo does it again, an edit
            that changes nothing leaves nothing to undo, and undoing every
            edit leaves the document unedited */
    MBDocument *u = [[MBDocument alloc] init];
    CHECK([u readFromURL:[NSURL fileURLWithPath:path] ofType:@"xcdatamodeld" error:NULL],
          "open a fresh copy");
    NSUndoManager *um = u.undoManager;
    CHECK(!um.canUndo && !u.isDocumentEdited, "nothing to undo after opening");
    NSEntityDescription *person = u.model.entitiesByName[@"Person"];
    NSEntityDescription *pet = u.model.entitiesByName[@"Pet"];
    NSAttributeDescription *age = person.attributesByName[@"age"];
    MBAttributeEditor *ae = [MBAttributeEditor editorForAttributeNamed:@"age"
                                                                entity:person document:u];

    ae.name = @"years";
    CHECK(person.attributesByName[@"years"] == age && um.canUndo && u.isDocumentEdited,
          "a rename is recorded and marks the document edited");
    [um undo];
    CHECK(person.attributesByName[@"age"] == age && !person.attributesByName[@"years"],
          "undo renames back, the same attribute");
    CHECK(!u.isDocumentEdited, "undone back to the saved state, the document is unedited");
    [um redo];
    CHECK(person.attributesByName[@"years"] == age, "redo renames again");
    [um undo];

    id sevenDefault = age.defaultValue;
    ae = [MBAttributeEditor editorForAttributeNamed:@"age" entity:person document:u];
    ae.typeName = @"String";
    CHECK(age.attributeType == NSStringAttributeType && age.defaultValue == nil,
          "a type change drops the default");
    [um undo];
    CHECK(age.attributeType == NSInteger32AttributeType && [age.defaultValue isEqual:sevenDefault],
          "undo restores the type and its default");

    [u beginEdit:@"Edit Attribute"];
    ae.optional = NO;
    ae.transient = YES;
    ae.hashModifier = @"v2";
    [u endEdit];
    CHECK([[um undoActionName] isEqualToString:@"Edit Attribute"], "the edit carries its name");
    [um undo];
    CHECK(age.isOptional && !age.isTransient && age.versionHashModifier == nil,
          "several fields in one edit undo as one step");

    MBEntityEditor *ee = [MBEntityEditor editorForEntityNamed:@"Person" document:u];
    NSString *added = [ee addAttribute];
    CHECK(person.attributesByName[added] != nil, "attribute added");
    [um undo];
    CHECK(person.attributesByName[added] == nil, "undo removes the added attribute");
    [um redo];
    CHECK(person.attributesByName[added] != nil, "redo adds it again");
    [um undo];

    NSRelationshipDescription *pets = person.relationshipsByName[@"pets"];
    NSRelationshipDescription *owner = pet.relationshipsByName[@"owner"];
    NSUInteger petsIndex = [person.properties indexOfObjectIdenticalTo:pets];
    [ee removeRelationshipNamed:@"pets"];
    CHECK(!person.relationshipsByName[@"pets"] && owner.inverseRelationship == nil,
          "removing a relationship unwires its inverse");
    [um undo];
    CHECK(person.relationshipsByName[@"pets"] == pets &&
              [person.properties indexOfObjectIdenticalTo:pets] == petsIndex &&
              owner.inverseRelationship == pets && pets.inverseRelationship == owner,
          "undo puts the same relationship back where it was, wired both ways");

    MBRelationshipEditor *re = [MBRelationshipEditor editorForRelationshipNamed:@"pets"
                                                                         entity:person document:u];
    re.destinationName = @"Person";
    CHECK(pets.destinationEntity == person && pets.inverseRelationship == nil,
          "retargeting drops the inverse");
    [um undo];
    CHECK(pets.destinationEntity == pet && pets.inverseRelationship == owner &&
              owner.inverseRelationship == pets,
          "undo retargets back and rewires the inverse");
    re.toMany = NO;
    CHECK(!pets.isToMany, "made to-one");
    [um undo];
    CHECK(pets.isToMany && pets.maxCount == 0, "undo makes it to-many again, counts as they were");

    NSManagedObjectModel *modelBefore = u.model;
    CHECK([u removeEntityNamed:@"Pet" error:NULL] && !u.model.entitiesByName[@"Pet"],
          "entity deleted");
    [um undo];
    CHECK(u.model == modelBefore && u.model.entitiesByName[@"Pet"] == pet,
          "undo of a deletion puts the same model back");
    [um redo];
    CHECK(!u.model.entitiesByName[@"Pet"], "redo deletes it again");
    [um undo];

    NSString *newEntity = [u addEntity];
    CHECK(u.model.entitiesByName[newEntity] != nil, "entity added");
    [um undo];
    CHECK(u.model.entitiesByName[newEntity] == nil, "undo removes the added entity");
    [u renameEntityNamed:@"Pet" to:@"Animal"];
    [um undo];
    CHECK(u.model.entitiesByName[@"Pet"] == pet && !u.model.entitiesByName[@"Animal"],
          "undo renames the entity back");

    NSString *fetch = [u addFetchRequestForEntityNamed:@"Person"];
    NSFetchRequest *request = [u.model fetchRequestTemplateForName:fetch];
    [u renameFetchRequestNamed:fetch to:@"Everyone"];
    [um undo];
    CHECK([u.model fetchRequestTemplateForName:fetch] == request &&
              ![u.model fetchRequestTemplateForName:@"Everyone"],
          "undo renames the fetch request back");
    [um undo];
    CHECK(![u.model fetchRequestTemplateForName:fetch], "undo removes the added fetch request");

    NSString *configuration = [u addConfiguration];
    CHECK([[u configurationNames] containsObject:configuration], "configuration added");
    [um undo];
    CHECK(![[u configurationNames] containsObject:configuration], "undo removes the configuration");

    NSString *editedVersion = u.editedVersionName;
    NSString *version = [u addModelVersion];
    CHECK([[u versionNames] containsObject:version], "version added");
    [um undo];
    CHECK(![[u versionNames] containsObject:version] &&
              [u.editedVersionName isEqualToString:editedVersion],
          "undo removes the version and edits the old one again");

    while (um.canUndo) [um undo];
    CHECK(!u.isDocumentEdited, "undoing every edit leaves the document unedited");

    MBDocument *quiet = [[MBDocument alloc] init];
    [quiet readFromURL:[NSURL fileURLWithPath:path] ofType:@"xcdatamodeld" error:NULL];
    NSEntityDescription *quietPerson = quiet.model.entitiesByName[@"Person"];
    MBAttributeEditor *qe = [MBAttributeEditor editorForAttributeNamed:@"name"
                                                                entity:quietPerson document:quiet];
    [quiet beginEdit:@"Edit Attribute"];
    qe.optional = qe.isOptional;
    qe.name = @"name";
    qe.typeName = qe.typeName;
    [quiet endEdit];
    CHECK(!quiet.undoManager.canUndo && !quiet.isDocumentEdited,
          "an edit that changes nothing leaves nothing to undo");

    }

    printf("---\n%d passed, %d failed\n", passed, failed);
    return failed ? 1 : 0;
  }
}
