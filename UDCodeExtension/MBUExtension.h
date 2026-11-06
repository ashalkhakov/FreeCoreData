/* UDCode's Core Data extension (docs/UDCODE.md): Core Data models and
   mapping models edited in UDCode with ModelBuilder's editors, in a tab of
   their own, as part of a project.  A model version is its `contents` file
   (in an .xcdatamodel, in an .xcdatamodeld), a mapping model its
   xcmapping.xml (in an .xcmappingmodel): the file's text is what is
   edited, each change written into it, so undo, saving, the tab's dot and
   source control are UDCode's, and a tab of its text shows it as XML (its
   grammar is the XML mode's).  A file of either name that is no model
   opens as text.  The editors' menus are in UDCode's Editor menu.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDExtension.h>

@interface MBUExtension : NSObject <UDExtension>
/* The Editor menu's items, from MBUEditorMenus.xib. */
+ (NSArray<NSMenuItem *> *)editorMenuItems;
/* Whether the text is a Core Data model's contents, or a mapping model's. */
+ (BOOL)textIsAModel:(NSString *)text;
+ (BOOL)textIsAMappingModel:(NSString *)text;
@end
