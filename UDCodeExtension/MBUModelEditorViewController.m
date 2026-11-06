/* UDCode's Core Data extension — a model version's tab (see
   MBUModelEditorViewController.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBUModelEditorViewController.h"
#import <objc/runtime.h>
#import <UDCodeKit/UDCodeDocument.h>
#import <UDPieceTable/UDTextModel.h>
#import "MBModelEditor.h"
#import "MBSourceListViewController.h"
#import "MBDetailViewController.h"
#import "MBInspectorViewController.h"
#import "MBWindowSupport.h"
#import "MBUEditorView.h"
#import "MBUTextEdits.h"

/* The source list's width when the tab opens, and its narrowest. */
static const CGFloat MBUSourceListWidth = 220;
static const CGFloat MBUSourceListMinimum = 160;

@interface MBUModelEditorViewController ()
@property (nonatomic, weak) IBOutlet NSView *problemView;
@property (nonatomic, weak) IBOutlet NSTextField *problemLabel;
@property (nonatomic, weak) IBOutlet NSSplitView *split;
@property (nonatomic, weak) IBOutlet NSView *sourceListHost;
@property (nonatomic, weak) IBOutlet NSView *detailHost;
@property (nonatomic, readwrite, strong) MBModelEditor *modelEditor;
@property (nonatomic, readwrite, copy) NSString *problem;
@property (nonatomic, readwrite, strong) MBSourceListViewController *sourceListController;
@property (nonatomic, readwrite, strong) MBDetailViewController *detailController;
@property (nonatomic, readwrite, strong) MBInspectorViewController *modelInspector;
@property (nonatomic, readwrite, strong) MBInspectorViewController *inspectorController;
@end

@implementation MBUModelEditorViewController {
  __weak id<UDWorkbench> _workbench;
  /* The text being read (what the model editor reports then is no change of
     the user's), or written (what the text model reports then is the
     parts' own). */
  BOOL _reading;
  BOOL _writing;
}

- (instancetype)initWithDocument:(UDCodeDocument *)document workbench:(id<UDWorkbench>)workbench
{
  if ((self = [super initWithNibName:@"MBUModelEditor"
                              bundle:[NSBundle bundleForClass:[MBUModelEditorViewController class]]])) {
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
  [_split setPosition:MBUSourceListWidth ofDividerAtIndex:0];
  [self show];
}

#pragma mark Reading

/* The parts, over the first text that is a model: the model editor has no
   undo manager (the text's undo is the undo). */
- (void)makePartsWithXMLString:(NSString *)xml error:(NSError **)error
{
  MBModelEditor *editor = [[MBModelEditor alloc] initWithContentsXML:xml undoManager:nil error:error];
  if (editor == nil) return;
  NSEntityDescription *first = [editor sortedEntities].firstObject;
  if (first) editor.selection = [MBSelection entityNamed:first.name];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(modelDidChange:)
                                               name:MBModelEditorDidChangeNotification object:editor];
  self.modelEditor = editor;
  self.sourceListController = [[MBSourceListViewController alloc] init];
  self.detailController = [[MBDetailViewController alloc] init];
  self.modelInspector = [[MBInspectorViewController alloc] init];
  self.modelInspector.title = @"Model";
  self.inspectorController = [[MBInspectorViewController alloc] init];
  self.inspectorController.title = @"Data Model";
  self.sourceListController.modelEditor = editor;
  self.detailController.modelEditor = editor;
  self.modelInspector.modelEditor = editor;
  self.inspectorController.modelEditor = editor;
  [self.modelInspector showOnlyPage:MBInspectorPageIdentity];
  [self.inspectorController showOnlyPage:MBInspectorPageDataModel];
}

/* The text read into the model editor; or, when it is no model, why. */
- (void)read
{
  NSString *xml = [_document.textModel getValue] ?: @"";
  NSError *error = nil;
  _reading = YES;
  BOOL read;
  if (self.modelEditor == nil) {
    [self makePartsWithXMLString:xml error:&error];
    read = self.modelEditor != nil;
  } else {
    read = [self.modelEditor readContentsXML:xml error:&error];
  }
  _reading = NO;
  self.problem = read ? nil
                      : [NSString stringWithFormat:@"This is not a Core Data model that can be shown: %@",
                                                   [error localizedDescription] ?: @"it cannot be read."];
  [self show];
}

/* The text changed, not by the parts: read again, at once while the tab
   shows (an undo), a moment later while it does not (typed in a tab of its
   text, each key would be a read of the whole model). */
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

/* The model changed: written once the change is done, so one action is one
   edit of the text, one undo. */
- (void)modelDidChange:(NSNotification *)notification
{
  (void)notification;
  if (_reading) return;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
  [self performSelector:@selector(write) withObject:nil afterDelay:0];
}

- (void)write
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(write) object:nil];
  if (self.modelEditor == nil || self.problem != nil) return;
  NSError *error = nil;
  NSString *text = [self.modelEditor contentsXML:&error];
  if (text == nil) return;
  _writing = YES;
  MBUWriteText(_document.textModel, text);
  _writing = NO;
}

#pragma mark Showing

/* The source list and the selection's page in the tab; or why there are none. */
- (void)show
{
  if (![self isViewLoaded]) return;
  if (self.problem == nil && self.modelEditor != nil) {
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

/* The source list keeps its width as the tab is resized, the page taking
   the difference. */
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
  (void)splitView;
  return subview != _sourceListHost;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
  (void)splitView;
  (void)index;
  return MAX(proposed, MBUSourceListMinimum);
}

#pragma mark The window's panes (UDEditorPanes)

- (NSArray<NSViewController *> *)inspectorViewControllers
{
  if (self.modelEditor == nil || self.problem != nil) return @[];
  return @[ self.modelInspector, self.inspectorController ];
}

/* As the model window's tab bar has them: an SF Symbol on macOS; on
   GNUstep, which has none, the window's own badge. */
- (NSImage *)imageForInspectorViewController:(NSViewController *)viewController
{
  BOOL model = viewController == self.modelInspector;
#ifndef GNUSTEP
  if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)])
    return [NSImage imageWithSystemSymbolName:model ? @"info.circle" : @"cylinder.split.1x2"
                     accessibilityDescription:viewController.title];
#endif
  return model ? MBUTabImage(MBBadgeImage(@"i", 0.47, 0.53, 0.64))
               : MBUTabImage(MBBadgeImage(@"D", 0.36, 0.49, 0.72));
}

#pragma mark Actions

- (IBAction)addEntity:(id)sender { [self.sourceListController addEntity:sender]; }
- (IBAction)addFetchRequest:(id)sender { [self.sourceListController addFetchRequest:sender]; }
- (IBAction)addConfiguration:(id)sender { [self.sourceListController addConfiguration:sender]; }
- (IBAction)addFetchIndex:(id)sender { [self.sourceListController addFetchIndex:sender]; }
- (IBAction)removeEntity:(id)sender { [self.sourceListController removeEntity:sender]; }
- (IBAction)addAttribute:(id)sender { [self.detailController addAttribute:sender]; }
- (IBAction)addRelationship:(id)sender { [self.detailController addRelationship:sender]; }

- (IBAction)validateModel:(id)sender
{
  (void)sender;
  MBValidateModel(self.modelEditor);
}

- (IBAction)createManagedObjectSubclass:(id)sender
{
  (void)sender;
  MBCreateManagedObjectSubclasses(self.modelEditor);
}

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
  if (self.modelEditor == nil || self.problem != nil) return NO;
  if (sel_isEqual(action, @selector(createManagedObjectSubclass:))) return self.modelEditor.model.entities.count > 0;
  if (sel_isEqual(action, @selector(validateModel:))) return YES;
  if ([self.sourceListController respondsToSelector:action]) return [self.sourceListController validateMenuItem:item];
  if ([self.detailController respondsToSelector:action]) return [self.detailController validateMenuItem:item];
  return YES;
}

@end
