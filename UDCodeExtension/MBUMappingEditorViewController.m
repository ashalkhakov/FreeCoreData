/* UDCode's Core Data extension — a mapping model's tab (see
   MBUMappingEditorViewController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBUMappingEditorViewController.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDPieceTable/UDTextModel.h>
#import "MBMappingEditor.h"
#import "MBMappingSourceListViewController.h"
#import "MBMappingDetailViewController.h"
#import "MBMappingInspectorViewController.h"
#import "MBWindowSupport.h"
#import "MBUEditorView.h"
#import "MBUTextEdits.h"

static const CGFloat MBUMappingListWidth = 200;
static const CGFloat MBUMappingListMinimum = 160;

@interface MBUMappingEditorViewController ()
@property (nonatomic, weak) IBOutlet NSView *problemView;
@property (nonatomic, weak) IBOutlet NSTextField *problemLabel;
@property (nonatomic, weak) IBOutlet NSSplitView *split;
@property (nonatomic, weak) IBOutlet NSView *sourceListHost;
@property (nonatomic, weak) IBOutlet NSView *detailHost;
@property (nonatomic, readwrite, strong) MBMappingEditor *mappingEditor;
@property (nonatomic, readwrite, copy) NSString *problem;
@property (nonatomic, readwrite, strong) MBMappingSourceListViewController *sourceListController;
@property (nonatomic, readwrite, strong) MBMappingDetailViewController *detailController;
@property (nonatomic, readwrite, strong) MBMappingInspectorViewController *identityInspector;
@property (nonatomic, readwrite, strong) MBMappingInspectorViewController *inspectorController;
@end

@implementation MBUMappingEditorViewController {
  __weak id<UDWorkbench> _workbench;
  BOOL _reading;
  BOOL _writing;
}

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench
{
  if ((self = [super initWithNibName:@"MBUMappingEditor"
                              bundle:[NSBundle bundleForClass:[MBUMappingEditorViewController class]]])) {
    _document = document;
    _workbench = workbench;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textDidChange:)
                                                 name:UDTextModelDidChangeNotification
                                               object:document.textModel];
    [self read];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)loadView
{
  [super loadView];
  [_split setPosition:MBUMappingListWidth ofDividerAtIndex:0];
  [self show];
}

#pragma mark Reading

/* The .xcmappingmodel the text is in: where the models it names are
   looked for from. */
- (NSString *)mappingModelPath
{
  return [[_document.fileURL URLByDeletingLastPathComponent] path] ?: @"";
}

- (void)makePartsWithXMLString:(NSString *)xml error:(NSError **)error
{
  MBMappingEditor *editor = [[MBMappingEditor alloc] initWithXMLString:xml atPath:[self mappingModelPath]
                                                           undoManager:nil error:error];
  if (editor == nil) return;
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mappingDidChange:)
                                               name:MBMappingEditorDidChangeNotification object:editor];
  self.mappingEditor = editor;
  self.sourceListController = [[MBMappingSourceListViewController alloc] init];
  self.detailController = [[MBMappingDetailViewController alloc] init];
  self.identityInspector = [[MBMappingInspectorViewController alloc] init];
  self.identityInspector.title = @"Identity and Type";
  self.inspectorController = [[MBMappingInspectorViewController alloc] init];
  self.inspectorController.title = @"Mapping";
  self.sourceListController.mappingEditor = editor;
  self.detailController.mappingEditor = editor;
  self.identityInspector.mappingEditor = editor;
  self.inspectorController.mappingEditor = editor;
  [self.identityInspector showOnlyPage:MBMappingInspectorPageIdentity];
  [self.inspectorController showOnlyPage:MBMappingInspectorPageMapping];
}

- (void)read
{
  NSString *xml = [_document.textModel getValue] ?: @"";
  NSError *error = nil;
  _reading = YES;
  BOOL read;
  if (self.mappingEditor == nil) {
    [self makePartsWithXMLString:xml error:&error];
    read = self.mappingEditor != nil;
  } else {
    read = [self.mappingEditor readXMLString:xml atPath:[self mappingModelPath] error:&error];
  }
  _reading = NO;
  self.problem = read ? nil
                      : [NSString stringWithFormat:@"This mapping model cannot be shown: %@",
                                                   [error localizedDescription] ?: @"it cannot be read."];
  [self show];
}

- (void)textDidChange:(NSNotification *)notification
{
  (void)notification;
  if (_writing) return;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(read) object:nil];
  if ([self isViewLoaded] && [[self view] window] != nil)
    [self read];
  else
    [self performSelector:@selector(read) withObject:nil afterDelay:0.3];
}

#pragma mark Writing

- (void)mappingDidChange:(NSNotification *)notification
{
  (void)notification;
  if (_reading) return;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
  [self performSelector:@selector(write) withObject:nil afterDelay:0];
}

- (void)write
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
  if (self.mappingEditor == nil || self.problem != nil) return;
  NSString *text = [self.mappingEditor XMLString:NULL];
  if (text == nil) return;
  _writing = YES;
  MBUWriteText(_document.textModel, text);
  _writing = NO;
}

#pragma mark Showing

- (void)show
{
  if (![self isViewLoaded]) return;
  if (self.problem == nil && self.mappingEditor != nil) {
    MBUPutView([self.sourceListController view], _sourceListHost);
    MBUPutView([self.detailController view], _detailHost);
    [_split setHidden:NO];
    [self.problemView setHidden:YES];
  } else {
    [_split setHidden:YES];
    [self.problemLabel setStringValue:self.problem ?: @""];
    [self.problemView setHidden:NO];
  }
}

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
  (void)splitView;
  return subview != _sourceListHost;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
  (void)splitView;
  (void)index;
  return MAX(proposed, MBUMappingListMinimum);
}

#pragma mark The window's panes (UDEditorPanes)

- (NSArray<NSViewController *> *)inspectorViewControllers
{
  if (self.mappingEditor == nil || self.problem != nil) return @[];
  return @[ self.identityInspector, self.inspectorController ];
}

- (NSImage *)imageForInspectorViewController:(NSViewController *)viewController
{
  BOOL identity = viewController == self.identityInspector;
#ifndef GNUSTEP
  if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)])
    return [NSImage imageWithSystemSymbolName:identity ? @"info.circle" : @"arrow.triangle.branch"
                     accessibilityDescription:viewController.title];
#endif
  return identity ? MBUTabImage(MBBadgeImage(@"i", 0.47, 0.53, 0.64))
                  : MBUTabImage(MBBadgeImage(@"M", 0.36, 0.49, 0.72));
}

#pragma mark Actions

- (IBAction)addEntityMapping:(id)sender { [self.sourceListController addEntityMapping:sender]; }
- (IBAction)removeEntityMapping:(id)sender { [self.sourceListController removeEntityMapping:sender]; }

- (IBAction)undo:(id)sender
{
  (void)sender;
  [self write];
  [_document.textModel.undoManager undo];
}

- (IBAction)redo:(id)sender
{
  (void)sender;
  [_document.textModel.undoManager redo];
}

- (IBAction)showAsText:(id)sender
{
  (void)sender;
  [_workbench showDocumentAsText:_document];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  SEL action = [item action];
  if (sel_isEqual(action, @selector(undo:))) return _document.textModel.undoManager.canUndo;
  if (sel_isEqual(action, @selector(redo:))) return _document.textModel.undoManager.canRedo;
  if (sel_isEqual(action, @selector(showAsText:))) return YES;
  if (self.mappingEditor == nil || self.problem != nil) return NO;
  if (sel_isEqual(action, @selector(removeEntityMapping:))) return [self.mappingEditor selectedEntityMapping] != nil;
  return YES;
}

@end
