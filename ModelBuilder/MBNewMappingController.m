/* ModelBuilder's New Mapping Model panel.  See MBNewMappingController.h.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBNewMappingController.h"
#import <CoreData/CoreData.h>
#import "CDModelCompiler.h"
#import "CDMappingCompiler.h"
#import "CDMappingSerializer.h"

/* Panels open now; each keeps itself until it closes. */
static NSMutableArray *MBOpenPanels;

/* The versions of a model, as paths to .xcdatamodel directories in the
   order Xcode lists them, and which one is current. */
static NSArray *MBVersionsOfModelAtPath(NSString *path, NSString **current)
{
  NSString *extension = [path pathExtension];
  NSString *bundle = path;
  NSString *chosen = nil;

  if ([extension isEqualToString:@"xcdatamodel"]) {
    bundle = [path stringByDeletingLastPathComponent];
    chosen = path;
    if (![[bundle pathExtension] isEqualToString:@"xcdatamodeld"]) {
      if (current) *current = path;
      return @[ path ];
    }
  } else if (![extension isEqualToString:@"xcdatamodeld"]) {
    return nil;
  }

  NSMutableArray *versions = [NSMutableArray array];

  for (NSString *entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundle error:NULL])
    if ([[entry pathExtension] isEqualToString:@"xcdatamodel"])
      [versions addObject:entry];
  /* By name alone: "Model 2.xcdatamodel" sorts before "Model.xcdatamodel"
     on its extension, and comes after it as a version. */
  [versions sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
    return [[a stringByDeletingPathExtension] localizedStandardCompare:[b stringByDeletingPathExtension]];
  }];

  NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
      [bundle stringByAppendingPathComponent:@".xccurrentversion"]];
  NSString *currentName = [info objectForKey:@"_XCCurrentVersionName"] ?: versions.lastObject;
  NSMutableArray *paths = [NSMutableArray array];

  for (NSString *version in versions)
    [paths addObject:[bundle stringByAppendingPathComponent:version]];
  if (current)
    *current = chosen ?: (currentName ? [bundle stringByAppendingPathComponent:currentName] : nil);
  return paths.count ? paths : nil;
}

@implementation MBNewMappingController

+ (instancetype)showPanel
{
  MBNewMappingController *panel = [[self alloc] initWithWindowNibName:@"MBNewMappingPanel"];

  if (!MBOpenPanels) MBOpenPanels = [NSMutableArray array];
  [MBOpenPanels addObject:panel];
  [panel showWindow:nil];
  [[panel window] center];
  return panel;
}

- (void)windowDidLoad
{
  [super windowDidLoad];
  if (!self.window.delegate) self.window.delegate = self;
  [self.sourceVersionPopup removeAllItems];
  [self.destinationVersionPopup removeAllItems];
  [self updateCreateButton];
}

- (void)windowWillClose:(NSNotification *)notification
{
  [MBOpenPanels removeObjectIdenticalTo:self];
}

#pragma mark - Choosing the models

static void MBFillVersions(NSPopUpButton *popup, NSArray *versions, NSString *selected)
{
  [popup removeAllItems];
  for (NSString *version in versions) {
    [popup addItemWithTitle:[[version lastPathComponent] stringByDeletingPathExtension]];
    [[popup lastItem] setRepresentedObject:version];
  }
  NSInteger index = selected ? [popup indexOfItemWithRepresentedObject:selected] : -1;
  if (index >= 0) [popup selectItemAtIndex:index];
}

- (BOOL)chooseSourceModelAtPath:(NSString *)path
{
  NSString *current = nil;
  NSArray *versions = MBVersionsOfModelAtPath(path, &current);

  if (versions == nil) return NO;

  /* A migration usually starts from the version before the current one. */
  NSUInteger index = [versions indexOfObject:current];
  NSString *selected = current;

  if (![[path pathExtension] isEqualToString:@"xcdatamodel"] && index != NSNotFound && index > 0)
    selected = versions[index - 1];

  [self window];
  MBFillVersions(self.sourceVersionPopup, versions, selected);
  [self.sourcePathLabel setStringValue:path];

  /* And ends at the current one, of the same model. */
  if ([self destinationVersionPath] == nil)
    [self chooseDestinationModelAtPath:[[path pathExtension] isEqualToString:@"xcdatamodel"]
                                           && [[[path stringByDeletingLastPathComponent] pathExtension]
                                                  isEqualToString:@"xcdatamodeld"]
                                           ? [path stringByDeletingLastPathComponent] : path];
  [self updateCreateButton];
  return YES;
}

- (BOOL)chooseDestinationModelAtPath:(NSString *)path
{
  NSString *current = nil;
  NSArray *versions = MBVersionsOfModelAtPath(path, &current);

  if (versions == nil) return NO;

  [self window];
  MBFillVersions(self.destinationVersionPopup, versions, current);
  [self.destinationPathLabel setStringValue:path];
  [self updateCreateButton];
  return YES;
}

- (NSString *)sourceVersionPath
{
  return [[self.sourceVersionPopup selectedItem] representedObject];
}

- (NSString *)destinationVersionPath
{
  return [[self.destinationVersionPopup selectedItem] representedObject];
}

- (void)updateCreateButton
{
  [self.createButton setEnabled:[self sourceVersionPath] && [self destinationVersionPath]];
}

- (void)runOpenPanelThen:(BOOL (^)(NSString *path))choose
{
  NSOpenPanel *panel = [NSOpenPanel openPanel];

  [panel setTitle:@"Choose a Data Model"];
  [panel setCanChooseFiles:YES];
  [panel setCanChooseDirectories:YES];
  [panel setAllowsMultipleSelection:NO];
  [panel setAllowedFileTypes:@[ @"xcdatamodeld", @"xcdatamodel" ]];
  if ([panel runModal] != NSModalResponseOK) return;

  NSString *path = [[panel URL] path];

  if (!choose(path)) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Not a data model"];
    [alert setInformativeText:[NSString stringWithFormat:
        @"%@ is neither an .xcdatamodeld nor an .xcdatamodel.", [path lastPathComponent]]];
    [alert runModal];
  }
}

- (IBAction)chooseSourceModel:(id)sender
{
  [self runOpenPanelThen:^BOOL(NSString *path) { return [self chooseSourceModelAtPath:path]; }];
}

- (IBAction)chooseDestinationModel:(id)sender
{
  [self runOpenPanelThen:^BOOL(NSString *path) { return [self chooseDestinationModelAtPath:path]; }];
}

- (IBAction)versionChosen:(id)sender
{
  [self updateCreateButton];
}

#pragma mark - Creating it

static NSString *MBVersionName(NSString *versionPath)
{
  return [[[versionPath lastPathComponent] stringByDeletingPathExtension]
      stringByReplacingOccurrencesOfString:@" " withString:@""];
}

- (NSString *)suggestedFileName
{
  return [NSString stringWithFormat:@"%@To%@.xcmappingmodel",
      MBVersionName([self sourceVersionPath]), MBVersionName([self destinationVersionPath])];
}

/* Beside the destination model, as Xcode suggests. */
- (NSString *)suggestedDirectory
{
  NSString *version = [self destinationVersionPath];
  NSString *container = [version stringByDeletingLastPathComponent];

  if ([[container pathExtension] isEqualToString:@"xcdatamodeld"])
    container = [container stringByDeletingLastPathComponent];
  return container;
}

- (BOOL)createMappingModelAtPath:(NSString *)path error:(NSError **)error
{
  NSString *sourcePath = [self sourceVersionPath];
  NSString *destinationPath = [self destinationVersionPath];
  NSManagedObjectModel *source = [CDModelCompiler compileModelAtPath:sourcePath error:error];
  NSManagedObjectModel *destination = source ? [CDModelCompiler compileModelAtPath:destinationPath error:error] : nil;

  if (source == nil || destination == nil) return NO;

  NSMappingModel *mapping = [CDMappingCompiler startingMappingModelFromSourceModel:source
                                                                 toDestinationModel:destination];

  /* A new mapping model, not an edit of the one it replaces: nothing of
     the old file is carried over. */
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

  return [CDMappingSerializer writeMappingModel:mapping
                                         toPath:path
                                sourceModelPath:[CDMappingSerializer recordedPathOfModelAtPath:sourcePath
                                                                         forMappingModelAtPath:path]
                           destinationModelPath:[CDMappingSerializer recordedPathOfModelAtPath:destinationPath
                                                                         forMappingModelAtPath:path]
                                          error:error];
}

- (IBAction)create:(id)sender
{
  if (![self sourceVersionPath] || ![self destinationVersionPath]) return;

  NSSavePanel *panel = [NSSavePanel savePanel];

  [panel setTitle:@"New Mapping Model"];
  [panel setAllowedFileTypes:@[ @"xcmappingmodel" ]];
  [panel setNameFieldStringValue:[self suggestedFileName]];
  [panel setDirectoryURL:[NSURL fileURLWithPath:[self suggestedDirectory] isDirectory:YES]];
  if ([panel runModal] != NSModalResponseOK) return;

  NSURL *url = [panel URL];
  NSError *error = nil;

  if (![self createMappingModelAtPath:[url path] error:&error]) {
    [self presentError:error];
    return;
  }

  [self close];
  [[NSDocumentController sharedDocumentController]
      openDocumentWithContentsOfURL:url
                            display:YES
                  completionHandler:^(NSDocument *document, BOOL wasOpen, NSError *openError) {
                    if (document == nil && openError) [NSApp presentError:openError];
                  }];
}

- (IBAction)cancel:(id)sender
{
  [self close];
}

@end

@implementation NSDocumentController (MBNewMapping)

- (IBAction)newMappingModel:(id)sender
{
  [MBNewMappingController showPanel];
}

@end
