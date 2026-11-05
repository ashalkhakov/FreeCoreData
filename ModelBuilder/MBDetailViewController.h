/* ModelBuilder — the centre (MBDetail.xib): the selection's page, its
   sections in collapsible JUInspectorViews.  An entity's attributes and
   relationships, each with +/− underneath; a fetch request's entity and
   predicate (the predicate editor, or its text); a configuration's
   entities, ticked when they belong to it; a fetch index's elements.
   A row picked here is the model editor's selection.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@class MBModelEditor, JUInspectorView, JUInspectorViewContainer;

@interface MBDetailViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)init;

@property (nonatomic, strong) MBModelEditor *modelEditor;

@property (nonatomic, strong) IBOutlet NSTabView *centerTabView;

/* An entity's page */
@property (nonatomic, strong) IBOutlet JUInspectorViewContainer *entityInspectorContainer;
@property (nonatomic, strong) IBOutlet JUInspectorView *attributesInspector;
@property (nonatomic, strong) IBOutlet JUInspectorView *relationshipsInspector;
@property (nonatomic, strong) IBOutlet NSTableView *attributeTable;
@property (nonatomic, strong) IBOutlet NSTableView *relationshipTable;

/* A fetch request's page */
@property (nonatomic, strong) IBOutlet JUInspectorViewContainer *fetchRequestInspectorContainer;
@property (nonatomic, strong) IBOutlet JUInspectorView *fetchRequestInspector;
@property (nonatomic, strong) IBOutlet NSPopUpButton *fetchEntityPopup;
@property (nonatomic, strong) IBOutlet NSTabView *predicateTabView;
@property (nonatomic, strong) IBOutlet NSPredicateEditor *fetchPredicateEditor;
@property (nonatomic, strong) IBOutlet NSTextField *predicateSourceView;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *predicateSourceSegmentedControl;

/* A configuration's page */
@property (nonatomic, strong) IBOutlet JUInspectorViewContainer *configurationInspectorContainer;
@property (nonatomic, strong) IBOutlet JUInspectorView *entitiesInspector;
@property (nonatomic, strong) IBOutlet NSTableView *memberTable;

/* A fetch index's page */
@property (nonatomic, strong) IBOutlet JUInspectorViewContainer *fetchIndexInspectorContainer;
@property (nonatomic, strong) IBOutlet JUInspectorView *fetchIndexElementsInspector;
@property (nonatomic, strong) IBOutlet NSTableView *fetchIndexElementTable;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *fetchIndexElementSegmentedControl;

/* What the page shows, as it is now. */
- (void)reload;

- (IBAction)addAttribute:(id)sender;
- (IBAction)removeAttribute:(id)sender;
- (IBAction)addRelationship:(id)sender;
- (IBAction)removeRelationship:(id)sender;
/* The bar's +/−: an attribute, or a relationship while one is selected. */
- (IBAction)propertySegmentClicked:(id)sender;
- (IBAction)fetchIndexElementSegmentClicked:(id)sender;
/* The fetch request's entity, or its predicate (the editor's or the text's). */
- (IBAction)inspectorChanged:(id)sender;
- (IBAction)predicateSourceToggled:(id)sender;

@end
