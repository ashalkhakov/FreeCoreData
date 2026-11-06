/* ModelBuilder mapping document — an .xcmappingmodel wrapper: the
   directory and the xcmapping.xml in it, read into an MBMappingEditor
   (which edits the mapping, on the document's undo manager) and written
   back from it.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class MBMappingEditor;

@interface MBMappingDocument : NSDocument

/* The mapping, as it is edited. */
@property (nonatomic, strong, readonly) MBMappingEditor *mappingEditor;

@end
