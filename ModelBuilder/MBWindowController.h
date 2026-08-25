/* ModelBuilder document window — Xcode-style three-pane editor, built
   entirely in code (cell-based tables, springs and struts) so one
   construction path behaves identically on GNUstep and macOS.

   Left: source list (ENTITIES / FETCH REQUESTS / CONFIGURATIONS) with
   add/remove under it.  Center: the selected item's editor - attribute
   and relationship tables for an entity, predicate editor for a fetch
   request, membership checklist for a configuration.  Right: data
   model inspector for the current selection.  Bottom: status text and
   the version bar (version popup, Add Version, Make Current, Validate).

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@interface MBWindowController : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate, NSSplitViewDelegate>

/* Left pane */
@property (nonatomic, strong) NSOutlineView *sourceList;
@property (nonatomic, strong) NSButton *sourceAddButton;
@property (nonatomic, strong) NSButton *sourceRemoveButton;

/* Center pane: entity editor */
@property (nonatomic, strong) NSView *entityEditor;
@property (nonatomic, strong) NSTableView *attributeTable;
@property (nonatomic, strong) NSTableView *relationshipTable;

/* Center pane: fetch request editor */
@property (nonatomic, strong) NSView *fetchEditor;
@property (nonatomic, strong) NSPopUpButton *fetchEntityPopup;
@property (nonatomic, strong) NSTextView *predicateView;

/* Center pane: configuration editor */
@property (nonatomic, strong) NSView *configurationEditor;
@property (nonatomic, strong) NSTableView *memberTable;

/* Inspector */
@property (nonatomic, strong) NSTextField *inspectorTitle;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSTextField *classField;
@property (nonatomic, strong) NSPopUpButton *parentPopup;
@property (nonatomic, strong) NSButton *abstractButton;
@property (nonatomic, strong) NSPopUpButton *typePopup;
@property (nonatomic, strong) NSButton *optionalButton;
@property (nonatomic, strong) NSButton *transientButton;
@property (nonatomic, strong) NSTextField *defaultField;
@property (nonatomic, strong) NSTextField *derivationField;
@property (nonatomic, strong) NSPopUpButton *destinationPopup;
@property (nonatomic, strong) NSPopUpButton *inversePopup;
@property (nonatomic, strong) NSButton *toManyButton;
@property (nonatomic, strong) NSButton *orderedButton;
@property (nonatomic, strong) NSPopUpButton *deleteRulePopup;
@property (nonatomic, strong) NSTextField *minField;
@property (nonatomic, strong) NSTextField *maxField;
@property (nonatomic, strong) NSTableView *userInfoTable;

/* Bottom bar */
@property (nonatomic, strong) NSTextField *statusField;
@property (nonatomic, strong) NSPopUpButton *versionPopup;
@property (nonatomic, strong) NSButton *addVersionButton;
@property (nonatomic, strong) NSButton *makeCurrentButton;
@property (nonatomic, strong) NSButton *validateButton;

- (IBAction)addSourceItem:(id)sender;
- (IBAction)removeSourceItem:(id)sender;
- (IBAction)addEntity:(id)sender;
- (IBAction)addFetchRequest:(id)sender;
- (IBAction)addConfiguration:(id)sender;
- (IBAction)addAttribute:(id)sender;
- (IBAction)removeAttribute:(id)sender;
- (IBAction)addRelationship:(id)sender;
- (IBAction)removeRelationship:(id)sender;
- (IBAction)addUserInfo:(id)sender;
- (IBAction)removeUserInfo:(id)sender;
- (IBAction)inspectorChanged:(id)sender;
- (IBAction)versionSelected:(id)sender;
- (IBAction)addModelVersion:(id)sender;
- (IBAction)makeCurrentVersion:(id)sender;
- (IBAction)validateModel:(id)sender;

@end
