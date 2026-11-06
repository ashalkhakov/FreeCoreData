/* ModelBuilder document window — assembles the parts (see
   MBWindowController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBWindowController.h"
#import "MBDocument.h"
#import "MBModelCommands.h"
#import "MBSourceListViewController.h"
#import "MBDetailViewController.h"
#import "MBInspectorViewController.h"
#import "MBWindowSupport.h"

/* The narrowest the window may get: both side panes at their minimum
   plus a usable center. */
static const CGFloat MBSidePaneMinimum = 160.0;
static const CGFloat MBCenterPaneMinimum = 320.0;
static const CGFloat MBInspectorMinimum = 260.0;

@implementation MBWindowController {
  /* The window's three split views: the outer one (main area | inspector),
     the main area's (editor over the button bar), and the editor's
     (source list | center pane).  -splitView:shouldAdjustSizeOfSubview:
     holds the three side panes at their size. */
  NSSplitView *_outerSplit, *_barSplit, *_sourceSplit;
}

- (MBDocument *)modelDocument
{
  return (MBDocument *)self.document;
}

- (MBModelEditor *)modelEditor
{
  return self.modelDocument.modelEditor;
}

- (NSManagedObjectModel *)model
{
  return self.modelEditor.model;
}

#pragma mark - Nib assembly

- (void)windowDidLoad
{
  [super windowDidLoad];

  /* The window asks its delegate for an undo manager (see Undo). */
  if (!self.window.delegate) self.window.delegate = self;

  /* Resizing: only the innermost split had a delegate in the xib. */
  _outerSplit = MBFirstSplitViewIn(self.window.contentView);
  _barSplit = MBFirstSplitViewIn(_outerSplit.subviews.firstObject);
  _sourceSplit = MBFirstSplitViewIn(_barSplit.subviews.firstObject);
  for (NSSplitView *split in @[ _outerSplit ?: (id)[NSNull null],
                                _barSplit ?: (id)[NSNull null],
                                _sourceSplit ?: (id)[NSNull null] ])
    if ([split isKindOfClass:[NSSplitView class]]) split.delegate = self;
  self.window.minSize = NSMakeSize(MBSidePaneMinimum + MBCenterPaneMinimum +
                                       MBInspectorMinimum + 2.0,
                                   480.0);

  _sourceListController = [[MBSourceListViewController alloc] init];
  _detailController = [[MBDetailViewController alloc] init];
  _inspectorController = [[MBInspectorViewController alloc] init];
  MBPlacePart(_sourceListController, self.sourceListHost);
  MBPlacePart(_detailController, self.detailHost);
  MBPlacePart(_inspectorController, self.inspectorHost);

  [self showModelEditor];
}

#pragma mark - Window lifecycle

- (void)setDocument:(NSDocument *)document
{
  [super setDocument:document];
  if ([self isWindowLoaded]) [self showModelEditor];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* The parts, on the document's model editor; the first entity selected
   when nothing is. */
- (void)showModelEditor
{
  MBModelEditor *editor = self.modelEditor;
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center removeObserver:self name:MBModelEditorDidChangeNotification object:nil];
  if (editor)
    [center addObserver:self selector:@selector(modelDidChange:)
                   name:MBModelEditorDidChangeNotification object:editor];
  if (editor && !editor.selection) {
    NSEntityDescription *first = [editor sortedEntities].firstObject;
    if (first) editor.selection = [MBSelection entityNamed:first.name];
  }
  _sourceListController.modelEditor = editor;
  _detailController.modelEditor = editor;
  _inspectorController.modelEditor = editor;
  if (editor) [self synchronizeWindowTitleWithDocumentName];
}

/* The title names the version, which may have changed. */
- (void)modelDidChange:(NSNotification *)notification
{
  (void)notification;
  [self synchronizeWindowTitleWithDocumentName];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
  MBDocument *doc = self.modelDocument;
  NSString *version = [doc.editedVersionName stringByDeletingPathExtension];
  if (!version.length) return displayName;
  BOOL current = [doc.editedVersionName isEqualToString:doc.currentVersionName];
  return [NSString stringWithFormat:@"%@ — %@%@", displayName, version,
          current ? @" (current)" : @""];
}

#pragma mark - Undo

/* The document's undo manager is the window's.  Typing in a field is
   undone on the field's own (its cell's, as AppKit has it), never the
   document's, which groups explicitly: a committed field arrives as one
   edit. */
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
  (void)window;
  return [(NSDocument *)self.document undoManager];
}

#pragma mark - The bar, and the Model menu's items for the parts

- (IBAction)sourceSegmentClicked:(id)sender
{
  if ([sender selectedSegment] == 0) [_sourceListController addSourceItem:sender];
  else [_sourceListController removeSourceItem:sender];
}

- (IBAction)propertySegmentClicked:(id)sender
{
  [_detailController propertySegmentClicked:sender];
}

- (IBAction)addEntity:(id)sender { [_sourceListController addEntity:sender]; }
- (IBAction)addFetchRequest:(id)sender { [_sourceListController addFetchRequest:sender]; }
- (IBAction)addConfiguration:(id)sender { [_sourceListController addConfiguration:sender]; }
- (IBAction)addFetchIndex:(id)sender { [_sourceListController addFetchIndex:sender]; }
- (IBAction)removeEntity:(id)sender { [_sourceListController removeEntity:sender]; }
- (IBAction)addAttribute:(id)sender { [_detailController addAttribute:sender]; }
- (IBAction)removeAttribute:(id)sender { [_detailController removeAttribute:sender]; }
- (IBAction)addRelationship:(id)sender { [_detailController addRelationship:sender]; }
- (IBAction)removeRelationship:(id)sender { [_detailController removeRelationship:sender]; }

#pragma mark - Version / Editor menu actions

- (IBAction)selectVersionMenuItem:(id)sender
{
  NSString *name = [sender representedObject];
  if (!name.length) return;
  NSError *error = nil;
  if (![self.modelDocument switchToVersion:name error:&error]) {
    MBPresentModelError(error, @"Cannot switch versions");
    return;
  }
}

- (IBAction)addModelVersion:(id)sender
{
  (void)sender;
  if (![self.modelDocument addModelVersion]) return;
}

- (IBAction)makeCurrentVersion:(id)sender
{
  (void)sender;
  [self.modelDocument makeEditedVersionCurrent];
}

- (IBAction)validateModel:(id)sender
{
  (void)sender;
  NSError *error = nil;
  NSArray *warnings = nil;
  BOOL ok = [MBModelCommands validateModelOf:self.modelEditor warnings:&warnings error:&error];

  NSAlert *alert = [[NSAlert alloc] init];
  if (!ok) {
    alert.messageText = @"Model does not compile";
    alert.informativeText = error.localizedDescription ?: @"Unknown error.";
  } else if (warnings.count) {
    alert.messageText = [NSString stringWithFormat:@"Model compiles with %lu warning%@",
                         (unsigned long)warnings.count, warnings.count == 1 ? @"" : @"s"];
    alert.informativeText = [warnings componentsJoinedByString:@"\n"];
  } else {
    alert.messageText = @"Model compiles cleanly";
    alert.informativeText = @"momc found no problems.";
  }
  [alert runModal];
}

- (IBAction)compileModel:(id)sender
{
  (void)sender;
  NSError *error = nil;
  NSString *momdPath = nil;
  NSAlert *alert = [[NSAlert alloc] init];
  if ([MBModelCommands compileModelAtPath:self.modelDocument.fileURL.path momdPath:&momdPath error:&error]) {
    alert.messageText = @"Model compiled";
    alert.informativeText = [NSString stringWithFormat:@"Wrote %@", momdPath];
  } else {
    alert.messageText = @"Cannot compile model";
    alert.informativeText = error.localizedDescription ?: @"Unknown error.";
  }
  [alert runModal];
}

/* Xcode's Editor > Create NSManagedObject Subclass..., for the
   selected entity - or, with no entity selection, for every entity
   marked Class Definition / Category/Extension (falling back to every
   entity with a custom class when none is marked). */
- (IBAction)createManagedObjectSubclass:(id)sender
{
  (void)sender;
  NSArray *entities = [MBModelCommands entitiesToGenerateInModel:self.model
                                                         selected:[self.modelEditor selectedEntity]];
  if (!entities.count) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Nothing to generate";
    alert.informativeText =
        @"Give an entity a class other than NSManagedObject first (the Class field in the inspector).";
    [alert runModal];
    return;
  }

  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.canCreateDirectories = YES;
  panel.allowsMultipleSelection = NO;
  panel.prompt = @"Generate";
  panel.message = entities.count == 1
      ? [NSString stringWithFormat:@"Generate class files for %@ into:",
         [(NSEntityDescription *)entities.firstObject name]]
      : [NSString stringWithFormat:@"Generate class files for %lu entities into:",
         (unsigned long)entities.count];
  if ([panel runModal] != NSModalResponseOK) return;

  NSError *error = nil;
  NSArray *written = [MBModelCommands writeClassesForEntities:entities
                                                  toDirectory:panel.URL.path
                                                        error:&error];
  if (!written) {
    MBPresentModelError(error, @"Cannot generate class files");
    return;
  }
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Class files generated";
  alert.informativeText = [NSString stringWithFormat:@"Wrote %lu files to %@.",
      (unsigned long)written.count, panel.URL.path];
  [alert runModal];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = item.action;
  if (action == @selector(createManagedObjectSubclass:))
    return self.model.entities.count > 0;
  if (action == @selector(makeCurrentVersion:))
    return ![self.modelDocument.editedVersionName
        isEqualToString:self.modelDocument.currentVersionName];
  if (action == @selector(selectVersionMenuItem:)) {
    item.state = [[item representedObject]
        isEqualToString:self.modelDocument.editedVersionName] ? NSOnState : NSOffState;
    return YES;
  }
  if (action == @selector(compileModel:))
    return self.modelDocument.fileURL != nil;
  if ([_sourceListController respondsToSelector:action])
    return [_sourceListController validateMenuItem:item];
  if ([_detailController respondsToSelector:action])
    return [_detailController validateMenuItem:item];
  return YES;
}

#pragma mark - Split view delegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  (void)dividerIndex;
  if (splitView == _barSplit) return proposed;
  return MAX(proposed, splitView == _outerSplit ? MBSidePaneMinimum + MBCenterPaneMinimum
                                                : MBSidePaneMinimum);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  (void)dividerIndex;
  if (splitView == _outerSplit)
    return MIN(proposed, NSWidth(splitView.bounds) - MBInspectorMinimum - splitView.dividerThickness);
  if (splitView == _sourceSplit)
    return MIN(proposed, NSWidth(splitView.bounds) - MBCenterPaneMinimum - splitView.dividerThickness);
  return proposed;
}

/* A wider window is for a wider editor: the source list, the inspector and
   the button bar keep the size they were dragged to, and the center takes
   the difference -- as Xcode's model editor does, and the XForms and RDL
   designers.  Once the window is narrower than all the minimums together,
   holding the sides would squeeze the center to nothing, so everyone gives
   way. */
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
  NSArray *panes = splitView.subviews;
  if (splitView == _barSplit) return subview != panes.lastObject;
  if (splitView == _outerSplit) {
    if (NSWidth(splitView.bounds) < self.window.minSize.width) return YES;
    return subview != panes.lastObject;
  }
  if (splitView == _sourceSplit) {
    if (NSWidth(splitView.bounds) < MBSidePaneMinimum + MBCenterPaneMinimum) return YES;
    return subview != panes.firstObject;
  }
  return YES;
}


@end
