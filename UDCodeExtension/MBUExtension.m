/* UDCode's Core Data extension (see MBUExtension.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBUExtension.h"
#import <UDCodeKit/UDCodeDocument.h>
#import <UDCodeKit/UDLanguageMode.h>
#import <UDPieceTable/UDTextModel.h>
#import "MBUModelEditorViewController.h"
#import "MBUMappingEditorViewController.h"

@implementation MBUExtension

+ (NSArray<NSMenuItem *> *)editorMenuItems
{
  NSNib *nib = [[NSNib alloc] initWithNibNamed:@"MBUEditorMenus"
                                        bundle:[NSBundle bundleForClass:[MBUExtension class]]];
  NSArray *objects = nil;
  /* An owner the XIB has no use for: gnustep-gui's NSNib takes no nil one. */
  if (![nib instantiateWithOwner:[[NSObject alloc] init] topLevelObjects:&objects]) return @[];
  for (id object in objects) {
    if ([object isKindOfClass:[NSMenu class]]) {
      NSArray *items = [[(NSMenu *)object itemArray] copy];
      [(NSMenu *)object removeAllItems];
      return items;
    }
  }
  return @[];
}

+ (BOOL)textIsAModel:(NSString *)text
{
  return [text rangeOfString:@"com.apple.IDECoreDataModeler.DataModel"].location != NSNotFound;
}

+ (BOOL)textIsAMappingModel:(NSString *)text
{
  return [text rangeOfString:@"XDDEVMAPPINGMODEL"].location != NSNotFound;
}

- (void)extensionDidLoad:(NSBundle *)bundle
{
  (void)bundle;
}

- (void)extensionWillUnload:(NSBundle *)bundle
{
  (void)bundle;
}

/* The modes' grammar is the XML mode's (LanguageInfo.plist's grammarOf). */
- (const void *)languageFuncForIdentifier:(NSString *)identifier
{
  (void)identifier;
  return NULL;
}

/* A model in ModelBuilder's model editor, a mapping model in its mapping
   editor; anything else in either file as text, in the XML grammar. */
- (NSViewController *)workbench:(id<UDWorkbench>)workbench editorForDocument:(UDCodeDocument *)document
{
  NSString *mode = document.languageMode.identifier;
  NSString *text = [document.textModel getValue];
  if ([mode isEqualToString:@"coredata-model"] && [MBUExtension textIsAModel:text])
    return [[MBUModelEditorViewController alloc] initWithDocument:document workbench:workbench];
  if ([mode isEqualToString:@"coredata-mapping"] && [MBUExtension textIsAMappingModel:text])
    return [[MBUMappingEditorViewController alloc] initWithDocument:document workbench:workbench];
  return nil;
}

/* The editors' items go to the first responder, which in a model's or a
   mapping's tab is its editor; elsewhere nothing takes them, and they are
   dimmed. */
- (NSArray<NSMenuItem *> *)editorMenuItemsForWorkbench:(id<UDWorkbench>)workbench
{
  (void)workbench;
  return [MBUExtension editorMenuItems];
}

@end
