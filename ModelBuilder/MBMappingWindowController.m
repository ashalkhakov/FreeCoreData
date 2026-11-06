/* ModelBuilder mapping window.  See MBMappingWindowController.h.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingWindowController.h"
#import "MBMappingDocument.h"
#import "MBMappingEditor.h"
#import "MBMappingSourceListViewController.h"
#import "MBMappingDetailViewController.h"
#import "MBMappingInspectorViewController.h"
#import "MBWindowSupport.h"

/* The narrowest the panes may get, as in the model window. */
static const CGFloat MBMappingListMinimum = 160.0;
static const CGFloat MBMappingCenterMinimum = 320.0;
static const CGFloat MBMappingInspectorMinimum = 260.0;

@implementation MBMappingWindowController {
  NSSplitView *_outerSplit, *_barSplit, *_sourceSplit;
}

- (instancetype)init
{
  return [super initWithWindowNibName:@"MBMappingWindow"];
}

- (MBMappingDocument *)mappingDocument
{
  return (MBMappingDocument *)[self document];
}

- (MBMappingEditor *)mappingEditor
{
  return self.mappingDocument.mappingEditor;
}

#pragma mark - Nib assembly

- (void)windowDidLoad
{
  [super windowDidLoad];

  if (!self.window.delegate) self.window.delegate = self;

  _outerSplit = MBFirstSplitViewIn(self.window.contentView);
  _barSplit = MBFirstSplitViewIn(_outerSplit.subviews.firstObject);
  _sourceSplit = MBFirstSplitViewIn(_barSplit.subviews.firstObject);
  for (NSSplitView *split in @[ _outerSplit ?: (id)[NSNull null],
                                _barSplit ?: (id)[NSNull null],
                                _sourceSplit ?: (id)[NSNull null] ])
    if ([split isKindOfClass:[NSSplitView class]]) split.delegate = self;
  self.window.minSize = NSMakeSize(MBMappingListMinimum + MBMappingCenterMinimum +
                                       MBMappingInspectorMinimum + 2.0,
                                   480.0);

  _sourceListController = [[MBMappingSourceListViewController alloc] init];
  _detailController = [[MBMappingDetailViewController alloc] init];
  _inspectorController = [[MBMappingInspectorViewController alloc] init];
  MBPlacePart(_sourceListController, self.sourceListHost);
  MBPlacePart(_detailController, self.detailHost);
  MBPlacePart(_inspectorController, self.inspectorHost);

  [self showMappingEditor];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setDocument:(id)document
{
  [super setDocument:document];
  if ([self isWindowLoaded]) [self showMappingEditor];
}

/* The parts, on the document's mapping editor. */
- (void)showMappingEditor
{
  MBMappingEditor *editor = self.mappingEditor;
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center removeObserver:self name:MBMappingEditorSelectionDidChangeNotification object:nil];
  if (editor)
    [center addObserver:self selector:@selector(selectionDidChange:)
                   name:MBMappingEditorSelectionDidChangeNotification object:editor];
  _sourceListController.mappingEditor = editor;
  _detailController.mappingEditor = editor;
  _inspectorController.mappingEditor = editor;
  [self selectionDidChange:nil];
}

/* − removes the selected mapping: it is off while none is. */
- (void)selectionDidChange:(NSNotification *)notification
{
  (void)notification;
  [self.entityMappingSegmentedControl setEnabled:([self.mappingEditor selectedEntityMapping] != nil)
                                      forSegment:1];
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
  (void)window;
  return [[self mappingDocument] undoManager];
}

- (IBAction)entityMappingSegmentClicked:(id)sender
{
  if ([sender selectedSegment] == 0)
    [_sourceListController addEntityMapping:sender];
  else
    [_sourceListController removeEntityMapping:sender];
}

#pragma mark - Split views

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
  NSArray *panes = splitView.subviews;
  if (splitView == _barSplit) return subview != panes.lastObject;
  if (splitView == _outerSplit) {
    if (NSWidth(splitView.bounds) < self.window.minSize.width) return YES;
    return subview != panes.lastObject;
  }
  if (splitView == _sourceSplit) {
    if (NSWidth(splitView.bounds) < MBMappingListMinimum + MBMappingCenterMinimum) return YES;
    return subview != panes.firstObject;
  }
  return YES;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  (void)dividerIndex;
  if (splitView == _barSplit) return proposed;
  return MAX(proposed, splitView == _outerSplit ? MBMappingListMinimum + MBMappingCenterMinimum
                                                : MBMappingListMinimum);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)dividerIndex
{
  (void)dividerIndex;
  if (splitView == _outerSplit)
    return MIN(proposed, NSWidth(splitView.bounds) - MBMappingInspectorMinimum - splitView.dividerThickness);
  if (splitView == _sourceSplit)
    return MIN(proposed, NSWidth(splitView.bounds) - MBMappingCenterMinimum - splitView.dividerThickness);
  return proposed;
}

@end
