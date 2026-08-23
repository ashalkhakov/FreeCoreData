/* ModelBuilder three-pane editor.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@interface MBWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate>

@property (nonatomic, strong) IBOutlet NSTableView *entityTable;
@property (nonatomic, strong) IBOutlet NSTableView *fetchTable;
@property (nonatomic, strong) IBOutlet NSTableView *attributeTable;
@property (nonatomic, strong) IBOutlet NSTableView *relationshipTable;
@property (nonatomic, strong) IBOutlet NSTableView *userInfoTable;
@property (nonatomic, strong) IBOutlet NSView *entityPane;
@property (nonatomic, strong) IBOutlet NSView *fetchPane;
@property (nonatomic, strong) IBOutlet NSTextView *predicateView;
@property (nonatomic, strong) IBOutlet NSTextField *inspectorTitle;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSTextField *classField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *parentPopup;
@property (nonatomic, strong) IBOutlet NSButton *abstractButton;
@property (nonatomic, strong) IBOutlet NSButton *optionalButton;
@property (nonatomic, strong) IBOutlet NSButton *transientButton;
@property (nonatomic, strong) IBOutlet NSPopUpButton *typePopup;
@property (nonatomic, strong) IBOutlet NSTextField *defaultField;
@property (nonatomic, strong) IBOutlet NSTextField *minField;
@property (nonatomic, strong) IBOutlet NSTextField *maxField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *destinationPopup;
@property (nonatomic, strong) IBOutlet NSPopUpButton *inversePopup;
@property (nonatomic, strong) IBOutlet NSButton *toManyButton;
@property (nonatomic, strong) IBOutlet NSButton *orderedButton; /* ordered to-many (momc ordered sets) */
@property (nonatomic, strong) IBOutlet NSPopUpButton *deleteRulePopup;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;

- (IBAction)addEntity:(id)sender;
- (IBAction)removeEntity:(id)sender;
- (IBAction)addFetchRequest:(id)sender;
- (IBAction)removeFetchRequest:(id)sender;
- (IBAction)addAttribute:(id)sender;
- (IBAction)removeAttribute:(id)sender;
- (IBAction)addRelationship:(id)sender;
- (IBAction)removeRelationship:(id)sender;
- (IBAction)addUserInfo:(id)sender;
- (IBAction)removeUserInfo:(id)sender;
- (IBAction)inspectorChanged:(id)sender;

@end
