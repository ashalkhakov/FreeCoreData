/* Headless smoke test for ModelBuilder's mapping document - no window and
   no display: open a mapping model made in Xcode, edit it the way the
   editor will, undo, save it back as its own source, and compile what was
   saved.  Scenario framing as in MBDocumentSmoke.m; see README.md.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBMappingDocument.h"
#import "CDMappingCompiler.h"

static int passed = 0, failed = 0;
#define CHECK(cond, name) do { \
  if (cond) { passed++; printf("  ok   %s\n", name); } \
  else { failed++; printf("  FAIL %s\n", name); } \
} while (0)
#define SCENARIO(title) printf("\nScenario: %s\n", title)

/* The fixture lives beside the framework's tests; it is the mapping model
   Xcode's editor made, which is the thing worth opening. */
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

static NSEntityMapping *mappingNamed(MBMappingDocument *document, NSString *name)
{
  for (NSEntityMapping *mapping in [document entityMappings])
    if ([[mapping name] isEqualToString:name]) return mapping;
  return nil;
}

int main(int argc, const char *argv[])
{
  @autoreleasepool {
    NSString *fixture = fixturePath();

    if (fixture == nil) {
      printf("  FAIL the mapping fixture is not where this expected it\n");
      return 1;
    }

    SCENARIO("a mapping model made in Xcode opens");

    MBMappingDocument *document = [[MBMappingDocument alloc] init];
    NSError *error = nil;
    BOOL opened = [document readFromURL:[NSURL fileURLWithPath:fixture]
                                 ofType:@"Core Data Mapping Model"
                                  error:&error];

    CHECK(opened, "it opens");
    if (!opened) {
      printf("  (%s)\n", [[error description] UTF8String]);
      return 1;
    }
    CHECK([[document entityMappings] count] == 3, "its three mappings are there");
    CHECK([document sourceModel] != nil && [document destinationModel] != nil,
          "the models it maps between came with it");

    NSEntityMapping *notes = mappingNamed(document, @"NoteToNote");

    CHECK(notes != nil, "the mapping that was narrowed is found by name");
    CHECK([[document filterPredicateOfEntityMapping:notes]
              isEqualToString:@"text BEGINSWITH \"keep\""],
          "and the predicate it was narrowed by is read back");

    SCENARIO("the editor's own edits, and undo");

    [document setFilterPredicate:@"text BEGINSWITH \"drop\"" forEntityMapping:notes];
    CHECK([[document filterPredicateOfEntityMapping:notes]
              isEqualToString:@"text BEGINSWITH \"drop\""], "the predicate changes");

    [[document undoManager] undo];
    CHECK([[document filterPredicateOfEntityMapping:notes]
              isEqualToString:@"text BEGINSWITH \"keep\""], "and one undo puts it back");

    [[document undoManager] redo];
    CHECK([[document filterPredicateOfEntityMapping:notes]
              isEqualToString:@"text BEGINSWITH \"drop\""], "and redo takes it forward");
    [[document undoManager] undo];

    /* Every destination property has a row, whether anything fills it or
       not - the blanks are what an author is there to fill. */
    NSArray *attributes = [document attributeMappingsOfEntityMapping:notes];
    NSMutableArray *names = [NSMutableArray array];

    for (NSPropertyMapping *property in attributes) [names addObject:[property name]];
    [names sortUsingSelector:@selector(compare:)];
    CHECK([[names componentsJoinedByString:@","] isEqualToString:@"text,writer"],
          "the destination's attributes each have a row");

    NSPropertyMapping *writer = nil, *text = nil;

    for (NSPropertyMapping *property in attributes) {
      if ([[property name] isEqualToString:@"writer"]) writer = property;
      if ([[property name] isEqualToString:@"text"]) text = property;
    }
    CHECK([[document valueExpressionStringOfPropertyMapping:writer] length] > 0,
          "the expression written by hand is shown");
    CHECK([document valueExpressionStringOfPropertyMapping:text] == nil,
          "the one the compiler works out is shown as nothing");

    /* Something other than what the compiler would work out: writing
       $source.text there would be writing the blank back. */
    CHECK([document setValueExpressionString:@"$source.author" ofPropertyMapping:text error:&error],
          "an expression can be written");
    CHECK([[document valueExpressionStringOfPropertyMapping:text] isEqualToString:@"$source.author"],
          "and is kept, being one nobody would have derived");
    CHECK(![document setValueExpressionString:@"$source." ofPropertyMapping:text error:&error],
          "and one that is not an expression is refused");
    [[document undoManager] undo];
    CHECK([document valueExpressionStringOfPropertyMapping:text] == nil,
          "undo gives the blank back");

    SCENARIO("a mapping added and taken away again");

    NSUInteger before = [[document entityMappings] count];
    NSEntityMapping *added = [document addEntityMappingFromEntityNamed:@"Obsolete"
                                                        toEntityNamed:nil];

    CHECK([[document entityMappings] count] == before + 1, "it is added");
    CHECK([added mappingType] == NSRemoveEntityMappingType,
          "an entity with nowhere to go is a removal");
    [[document undoManager] undo];
    CHECK([[document entityMappings] count] == before, "and undo takes it away");

    SCENARIO("saved as its own source, and compiled from there");

    NSString *saved = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"MBMappingSmoke.xcmappingmodel"];

    [[NSFileManager defaultManager] removeItemAtPath:saved error:NULL];
    CHECK([document writeToURL:[NSURL fileURLWithPath:saved]
                        ofType:@"Core Data Mapping Model"
                         error:&error], "it saves");

    NSMappingModel *compiled = [CDMappingCompiler mappingModelAtPath:saved
                                                        sourceModel:[document sourceModel]
                                                   destinationModel:[document destinationModel]
                                                              error:&error];

    CHECK(compiled != nil, "and compiles");
    CHECK([[compiled entityMappings] count] == 3, "with its mappings");

    NSEntityMapping *compiledNotes = nil;

    for (NSEntityMapping *mapping in [compiled entityMappings])
      if ([[mapping name] isEqualToString:@"NoteToNote"]) compiledNotes = mapping;

    CHECK(compiledNotes != nil && [compiledNotes sourceExpression] != nil,
          "and the narrowing survived the round trip");

    [[NSFileManager defaultManager] removeItemAtPath:saved error:NULL];

    printf("\n---\n%d passed, %d failed\n", passed, failed);
    return failed == 0 ? 0 : 1;
  }
}
