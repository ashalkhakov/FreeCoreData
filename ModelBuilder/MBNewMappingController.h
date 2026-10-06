/* ModelBuilder's New Mapping Model panel (MBNewMappingPanel.xib), as
   Xcode's File > New > Mapping Model asks it: which model to map from,
   which to map to, and where to put the mapping model.  The mapping model
   starts as Xcode's does - see +[CDMappingCompiler
   startingMappingModelFromSourceModel:toDestinationModel:] - and is
   written out and opened like any other.

   A model is chosen as an .xcdatamodeld, whose versions fill the popup
   (the source starts at the version before the current one, the
   destination at the current one), or as a single .xcdatamodel.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@interface MBNewMappingController : NSWindowController <NSWindowDelegate>

@property (nonatomic, strong) IBOutlet NSTextField *sourcePathLabel;
@property (nonatomic, strong) IBOutlet NSPopUpButton *sourceVersionPopup;
@property (nonatomic, strong) IBOutlet NSTextField *destinationPathLabel;
@property (nonatomic, strong) IBOutlet NSPopUpButton *destinationVersionPopup;
@property (nonatomic, strong) IBOutlet NSButton *createButton;

/* Shows a new panel, kept until it closes. */
+ (instancetype)showPanel;

/* What a Choose… button does once a path is picked: an .xcdatamodeld or
   an .xcdatamodel.  NO if it is neither. */
- (BOOL)chooseSourceModelAtPath:(NSString *)path;
- (BOOL)chooseDestinationModelAtPath:(NSString *)path;

/* The .xcdatamodel versions chosen, nil until one is. */
- (NSString *)sourceVersionPath;
- (NSString *)destinationVersionPath;

/* The name and directory Create… offers to save under. */
- (NSString *)suggestedFileName;
- (NSString *)suggestedDirectory;

/* Writes the starting mapping model there (replacing whatever is there). */
- (BOOL)createMappingModelAtPath:(NSString *)path error:(NSError **)error;

- (IBAction)chooseSourceModel:(id)sender;
- (IBAction)chooseDestinationModel:(id)sender;
- (IBAction)versionChosen:(id)sender;
- (IBAction)create:(id)sender;
- (IBAction)cancel:(id)sender;

@end

/* File > New Mapping Model… (nil-targeted, so it reaches the document
   controller through the responder chain). */
@interface NSDocumentController (MBNewMapping)
- (IBAction)newMappingModel:(id)sender;
@end
