/* ModelBuilder document — a .xcdatamodeld package: its versions' contents
   XML, which of them is current, and which is being edited.  The edited
   version is its model editor's (MBModelEditor), which has the document's
   undo manager; the others ride along verbatim.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "MBModelEditor.h"

@interface MBDocument : NSDocument

/* The version being edited. */
@property (nonatomic, strong, readonly) MBModelEditor *modelEditor;

/* File name of the version being edited ("Model 2.xcdatamodel"). */
@property (nonatomic, copy) NSString *editedVersionName;

/* File name of the version .xccurrentversion points at. */
@property (nonatomic, copy) NSString *currentVersionName;

- (NSArray *)versionNames;      /* sorted version file names */

/* Xcode's Editor menu: Add Model Version duplicates the edited version
   under a fresh name (and starts editing it); Set Current Version moves
   the .xccurrentversion pointer. */
- (NSString *)addModelVersion;
- (BOOL)switchToVersion:(NSString *)name error:(NSError **)error;
- (void)makeEditedVersionCurrent;

@end
