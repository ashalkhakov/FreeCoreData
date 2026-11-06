/* UDCode's Core Data extension against UDCode's own document and text
   model (its SDK): a model version, and a mapping model, is its document's
   text, each change one edit of it, the text's undo undoing it; the
   inspector is the window's pane; a text that cannot be shown says why.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDCodeKit/UDLanguageMode.h>
#import <UDCodeKit/UDLanguageConfiguration.h>
#import <UDPieceTable/UDTextModel.h>
#import "MBUExtension.h"
#import "MBUModelEditorViewController.h"
#import "MBUMappingEditorViewController.h"
#import "MBUTextEdits.h"
#import "MBModelEditor.h"
#import "MBMappingEditor.h"
#import "MBSourceListViewController.h"
#import "MBInspectorViewController.h"
#import "DMTabBar.h"

static NSString *const MBUTestModelXML =
@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
@"<model type=\"com.apple.IDECoreDataModeler.DataModel\" documentVersion=\"1.0\" sourceLanguage=\"Objective-C\">\n"
@"    <entity name=\"Person\" representedClassName=\"NSManagedObject\" syncable=\"YES\">\n"
@"        <attribute name=\"name\" optional=\"YES\" attributeType=\"String\"/>\n"
@"    </entity>\n"
@"</model>\n";

/* The window's side of what the tab asks of it: what it was asked to show. */
@interface MBUTestWorkbench : NSObject
@property (nonatomic, strong) NSMutableArray<UDCodeDocument *> *shownAsText;
@end

@implementation MBUTestWorkbench
- (instancetype)init
{
  if ((self = [super init])) _shownAsText = [NSMutableArray array];
  return self;
}
- (void)showDocumentAsText:(UDCodeDocument *)document { [_shownAsText addObject:document]; }
@end

@interface MBUTests : XCTestCase
@end

@implementation MBUTests {
  UDCodeDocument *_document;
  MBUTestWorkbench *_workbench;
  NSWindow *_window;
  NSUInteger _edits;
}

- (void)setUp
{
  [super setUp];
  [NSApplication sharedApplication];
  _workbench = [[MBUTestWorkbench alloc] init];
}

- (void)tearDown
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_window orderOut:nil];
  [super tearDown];
}

- (void)countEdit:(NSNotification *)notification
{
  (void)notification;
  _edits++;
}

- (void)spin:(NSTimeInterval)seconds
{
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

/* The repository's Tests directory, from this file's. */
- (NSString *)testsDirectory
{
  NSString *here = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
  /* gnustep-make compiles from the bundle's directory, and __FILE__ is then
     relative to it. */
  if (![here isAbsolutePath])
    here = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:here];
  return [[[here stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:@"Tests"];
}

- (UDCodeDocument *)documentOfText:(NSString *)text at:(NSURL *)url
{
  UDCodeDocument *document = [[UDCodeDocument alloc] initWithText:text fileURL:url languageMode:nil];
  if (!document.textModel.undoManager) document.textModel.undoManager = [[NSUndoManager alloc] init];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(countEdit:)
                                               name:UDTextModelDidChangeNotification object:document.textModel];
  return document;
}

/* A tab's view in a window, as UDCode's tab would have it. */
- (void)show:(NSViewController *)tab
{
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 700) styleMask:NSWindowStyleMaskTitled
                                          backing:NSBackingStoreBuffered defer:YES];
  [_window setReleasedWhenClosed:NO];
  [[tab view] setFrame:[[_window contentView] bounds]];
  [[_window contentView] addSubview:[tab view]];
}

- (MBUModelEditorViewController *)openModel:(NSString *)text
{
  _document = [self documentOfText:text at:nil];
  MBUModelEditorViewController *tab = [[MBUModelEditorViewController alloc]
      initWithDocument:_document workbench:(id<UDWorkbench>)_workbench];
  [self show:tab];
  return tab;
}

- (MBUMappingEditorViewController *)openMappingFixture
{
  NSString *path = [[self testsDirectory] stringByAppendingPathComponent:@"MappingFixture.xcmappingmodel/xcmapping.xml"];
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  XCTAssertNotNil(text, @"the fixture is at %@", path);
  _document = [self documentOfText:text at:[NSURL fileURLWithPath:path]];
  MBUMappingEditorViewController *tab = [[MBUMappingEditorViewController alloc]
      initWithDocument:_document workbench:(id<UDWorkbench>)_workbench];
  [self show:tab];
  return tab;
}

- (UDLanguageMode *)modeNamed:(NSString *)identifier
{
  return [[UDLanguageMode alloc] initWithIdentifier:identifier displayName:identifier fileExtensions:@[]
                                       languageFunc:NULL highlightsQuery:nil indentsQuery:nil lspLanguageID:nil
                              languageServerCommand:nil defaultNewDocumentText:@""
                              languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
                                         keyHandler:nil extension:nil];
}

#pragma mark - The extension

- (void)testAModelsFoldersStandForTheFileTheyHold
{
  NSFileManager *files = [NSFileManager defaultManager];
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  NSString *model = [root stringByAppendingPathComponent:@"M.xcdatamodeld"];
  for (NSString *path in @[ @"M.xcdatamodeld/M.xcdatamodel/contents", @"M.xcdatamodeld/M 2.xcdatamodel/contents",
                            @"M.xcdatamodeld/M 10.xcdatamodel/contents", @"Map.xcmappingmodel/xcmapping.xml" ]) {
    NSString *file = [root stringByAppendingPathComponent:path];
    [files createDirectoryAtPath:[file stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"x" writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:NULL];
  }
  [files createDirectoryAtPath:[root stringByAppendingPathComponent:@"Empty.xcdatamodel"] withIntermediateDirectories:YES attributes:nil error:NULL];
  [files createDirectoryAtPath:[root stringByAppendingPathComponent:@"Empty.xcdatamodeld"] withIntermediateDirectories:YES attributes:nil error:NULL];
  MBUExtension *extension = [[MBUExtension alloc] init];
  NSString *(^mainFile)(NSString *) = ^NSString *(NSString *path) {
    NSURL *file = [extension mainFileOfPackageAtURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:path] isDirectory:YES]];
    return file ? [[file path] substringFromIndex:root.length + 1] : nil;
  };

  XCTAssertEqualObjects(mainFile(@"M.xcdatamodeld/M.xcdatamodel"), @"M.xcdatamodeld/M.xcdatamodel/contents");
  XCTAssertEqualObjects(mainFile(@"Map.xcmappingmodel"), @"Map.xcmappingmodel/xcmapping.xml");
  XCTAssertEqualObjects(mainFile(@"M.xcdatamodeld"), @"M.xcdatamodeld/M 10.xcdatamodel/contents", @"no current version: the last");
  NSString *pointer = [model stringByAppendingPathComponent:@".xccurrentversion"];
  [@{ @"_XCCurrentVersionName" : @"M 2.xcdatamodel" } writeToFile:pointer atomically:NO];
  XCTAssertEqualObjects(mainFile(@"M.xcdatamodeld"), @"M.xcdatamodeld/M 2.xcdatamodel/contents", @"the current version");
  [@{ @"_XCCurrentVersionName" : @"Gone.xcdatamodel" } writeToFile:pointer atomically:NO];
  XCTAssertEqualObjects(mainFile(@"M.xcdatamodeld"), @"M.xcdatamodeld/M 10.xcdatamodel/contents", @"a version that is gone: the last");
  XCTAssertNil(mainFile(@"Empty.xcdatamodel"), @"without its file, a folder");
  XCTAssertNil(mainFile(@"Empty.xcdatamodeld"), @"without a version, a folder");
  XCTAssertNil([extension mainFileOfPackageAtURL:[NSURL fileURLWithPath:root isDirectory:YES]]);
  [files removeItemAtPath:root error:NULL];
}

- (void)testAModelOrAMappingIsKnownByItsText
{
  XCTAssertTrue([MBUExtension textIsAModel:MBUTestModelXML]);
  XCTAssertFalse([MBUExtension textIsAModel:@"<plist/>"]);
  XCTAssertTrue([MBUExtension textIsAMappingModel:@"<object type=\"XDDEVMAPPINGMODEL\" id=\"z1\"/>"]);
  XCTAssertFalse([MBUExtension textIsAMappingModel:MBUTestModelXML]);
}

- (void)testAModelsDocumentGetsTheModelEditorAndAnyOtherNone
{
  MBUExtension *extension = [[MBUExtension alloc] init];
  UDCodeDocument *model = [[UDCodeDocument alloc] initWithText:MBUTestModelXML fileURL:nil
                                                  languageMode:[self modeNamed:@"coredata-model"]];
  XCTAssertTrue([[extension workbench:(id<UDWorkbench>)_workbench editorForDocument:model]
      isKindOfClass:[MBUModelEditorViewController class]]);
  UDCodeDocument *other = [[UDCodeDocument alloc] initWithText:@"some notes" fileURL:nil
                                                  languageMode:[self modeNamed:@"coredata-model"]];
  XCTAssertNil([extension workbench:(id<UDWorkbench>)_workbench editorForDocument:other],
               @"a file named contents that is no model opens as text");
}

- (void)testTheEditorMenusItemsComeFromTheXIBEachWithAnAction
{
  NSArray *items = [MBUExtension editorMenuItems];
  XCTAssertTrue(items.count > 10);
  NSArray *actions = [[items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSeparatorItem == NO"]]
      valueForKey:@"title"];
  for (NSMenuItem *item in items)
    XCTAssertTrue([item isSeparatorItem] || [item action] != NULL, @"%@", item.title);
  XCTAssertTrue([actions containsObject:@"Add Entity"] && [actions containsObject:@"Add Entity Mapping"]);
}

#pragma mark - The text edits

- (void)testTheEditsMakeTheTextWhereverItsEndIs
{
  NSArray *cases = @[ @[ @"a\nb\n", @"a\nb" ], @[ @"a\nb", @"a\nb\n" ], @[ @"a", @"a\nb" ], @[ @"a\nb\nc", @"a" ],
                      @[ @"a\nb\n", @"x\ny" ], @[ @"", @"a\n" ], @[ @"a\n", @"" ], @[ @"a\n\n\n", @"a\n" ] ];
  for (NSArray *pair in cases) {
    UDCodeDocument *document = [self documentOfText:pair[0] at:nil];
    MBUWriteText(document.textModel, pair[1]);
    XCTAssertEqualObjects([document.textModel getValue], pair[1], @"from %@", [pair[0] description]);
  }
}

- (void)testTheEditsAreOnePerRunOfChangedLinesAndMakeTheText
{
  UDCodeDocument *document = [self documentOfText:@"a\nb\nc\nd\ne\n" at:nil];
  NSString *wanted = @"a\nB\nc\nd\nE\nf\n";
  XCTAssertEqual(MBUEditsToText(document.textModel, wanted).count, 2u);
  XCTAssertTrue(MBUWriteText(document.textModel, wanted));
  XCTAssertEqualObjects([document.textModel getValue], wanted);
  XCTAssertFalse(MBUWriteText(document.textModel, wanted), @"the same text: nothing to write");
}

#pragma mark - A model's tab

- (void)testAModelOpensInTheEditorWithItsInspectorAsAPane
{
  MBUModelEditorViewController *tab = [self openModel:MBUTestModelXML];
  XCTAssertNotNil(tab.modelEditor);
  XCTAssertNil(tab.problem);
  XCTAssertNotNil(tab.modelEditor.model.entitiesByName[@"Person"]);
  NSArray *inspectors = [tab inspectorViewControllers];
  XCTAssertEqualObjects([inspectors valueForKey:@"title"], (@[ @"Model", @"Data Model" ]));
  for (NSViewController *inspector in inspectors)
    XCTAssertNotNil([tab imageForInspectorViewController:inspector], @"%@", inspector.title);
  XCTAssertTrue([tab.inspectorController.inspectorTabBar isHidden], @"the pane's tabs choose the page");
  XCTAssertEqualObjects([_document.textModel getValue], MBUTestModelXML, @"opened, the text as it was");
  XCTAssertEqual(_edits, 0u);
}

- (void)testAChangeIsOneEditOfTheTextAndTheTextsUndoUndoesIt
{
  MBUModelEditorViewController *tab = [self openModel:MBUTestModelXML];
  _edits = 0;
  [tab addEntity:nil];
  [self spin:0.1];
  NSString *changed = [_document.textModel getValue];
  XCTAssertTrue([changed containsString:@"<entity name=\"Entity\""], @"%@", changed);
  XCTAssertEqual(_edits, 1u, @"one action, one edit of the text");
  [tab undo:nil];
  [self spin:0.1];
  XCTAssertFalse([[_document.textModel getValue] containsString:@"<entity name=\"Entity\""]);
  XCTAssertNil(tab.modelEditor.model.entitiesByName[@"Entity"], @"read again after the undo");
}

- (void)testTheTextChangedAsTextIsReadAgainTheSelectionKept
{
  MBUModelEditorViewController *tab = [self openModel:MBUTestModelXML];
  XCTAssertEqualObjects(tab.modelEditor.selection.entityName, @"Person");
  NSString *more = [MBUTestModelXML stringByReplacingOccurrencesOfString:@"<attribute name=\"name\""
                                                              withString:@"<attribute name=\"age\" optional=\"YES\" attributeType=\"Integer 16\"/>\n        <attribute name=\"name\""];
  MBUWriteText(_document.textModel, more);
  [self spin:0.5];
  XCTAssertNotNil([tab.modelEditor.model.entitiesByName[@"Person"] attributesByName][@"age"]);
  XCTAssertEqualObjects(tab.modelEditor.selection.entityName, @"Person");
}

- (void)testATextThatIsNoModelSaysWhyAndOffersItAsText
{
  MBUModelEditorViewController *tab = [self openModel:@"<model type=\"com.apple.IDECoreDataModeler.DataModel\"><entity"];
  XCTAssertNil(tab.modelEditor);
  XCTAssertTrue([tab.problem hasPrefix:@"This is not a Core Data model"], @"%@", tab.problem);
  XCTAssertEqual([tab inspectorViewControllers].count, 0u);
  [tab showAsText:nil];
  XCTAssertEqual(_workbench.shownAsText.firstObject, _document);
}

#pragma mark - A mapping's tab

- (void)testAMappingModelOpensWithTheModelsItNames
{
  MBUMappingEditorViewController *tab = [self openMappingFixture];
  XCTAssertNil(tab.problem);
  XCTAssertEqual([tab.mappingEditor entityMappings].count, 3u);
  XCTAssertNotNil(tab.mappingEditor.sourceModel);
  XCTAssertEqualObjects([[tab inspectorViewControllers] valueForKey:@"title"], (@[ @"Identity and Type", @"Mapping" ]));
}

- (void)testAMappingChangeIsOneEditAndTheTextsUndoUndoesIt
{
  MBUMappingEditorViewController *tab = [self openMappingFixture];
  NSString *before = [_document.textModel getValue];
  _edits = 0;
  [tab addEntityMapping:nil];
  [self spin:0.1];
  XCTAssertEqual([tab.mappingEditor entityMappings].count, 4u);
  XCTAssertEqual(_edits, 1u);
  XCTAssertNotEqualObjects([_document.textModel getValue], before);
  [tab undo:nil];
  [self spin:0.1];
  XCTAssertEqualObjects([_document.textModel getValue], before);
  XCTAssertEqual([tab.mappingEditor entityMappings].count, 3u, @"read again after the undo");
}

- (void)testAMappingWhoseModelsAreNotFoundSaysWhy
{
  NSString *path = [[self testsDirectory] stringByAppendingPathComponent:@"MappingFixture.xcmappingmodel/xcmapping.xml"];
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  /* Somewhere with no models above it, and the working directory there
     too: a recorded path is also tried as given. */
  NSFileManager *files = [NSFileManager defaultManager];
  NSString *empty = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  NSString *lost = [empty stringByAppendingPathComponent:@"Lost.xcmappingmodel"];
  [files createDirectoryAtPath:lost withIntermediateDirectories:YES attributes:nil error:NULL];
  NSString *here = [files currentDirectoryPath];
  [files changeCurrentDirectoryPath:empty];
  _document = [self documentOfText:text at:[NSURL fileURLWithPath:[lost stringByAppendingPathComponent:@"xcmapping.xml"]]];
  MBUMappingEditorViewController *tab = [[MBUMappingEditorViewController alloc]
      initWithDocument:_document workbench:(id<UDWorkbench>)_workbench];
  [files changeCurrentDirectoryPath:here];
  [files removeItemAtPath:empty error:NULL];
  XCTAssertNil(tab.mappingEditor);
  XCTAssertTrue([tab.problem hasPrefix:@"This mapping model cannot be shown"], @"%@", tab.problem);
}

@end
