/* ModelBuilder — the source list (MBSourceList.xib): the model's
   entities, each opening to its fetch indexes, its fetch requests and its
   configurations, the implicit Default first.  What is picked here is the
   model editor's selection; what is added, removed or renamed here is
   changed through it.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>

@class MBModelEditor;

@interface MBSourceListViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

- (instancetype)init;

/* The version shown; set again when it is another one. */
@property (nonatomic, strong) MBModelEditor *modelEditor;

@property (nonatomic, strong) IBOutlet NSOutlineView *sourceList;

/* + adds an entity, fetch request or configuration, after what is
   selected; − removes what is selected. */
- (IBAction)addSourceItem:(id)sender;
- (IBAction)removeSourceItem:(id)sender;
- (IBAction)addEntity:(id)sender;
- (IBAction)addFetchRequest:(id)sender;
- (IBAction)addConfiguration:(id)sender;
- (IBAction)addFetchIndex:(id)sender;
- (IBAction)removeEntity:(id)sender;

@end
