/* Editing view-models for the mapping inspector, as MBEditors are the
   model inspector's: one for an entity mapping, one for a property
   mapping's row.  KVO-compliant properties the inspector's fields are
   bound to (through an NSObjectController per page in
   MBMappingInspector.xib); their setters make the change through the
   MBMappingEditor, as one undo step each, and key-value validation
   (-validateValue:forKey:error:, which a binding with
   NSValidatesImmediately calls) refuses what the mapping cannot take: a
   name another mapping has, a predicate or an expression that does not
   parse.  -reload tells observers that every property may have changed.

   An entity mapping's editor holds the mapping itself: its objects are
   changed in place, and a change of its entities can rename it.  A
   property row's editor holds its entity mapping and the row's name: the
   row may have no property mapping yet, and gets one when it is first
   edited.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class MBMappingEditor;

/* The pop-ups' item for no entity. */
extern NSString *const MBMappingNoEntityTitle;

@interface MBMappingObjectEditor : NSObject
@property (nonatomic, strong, readonly) MBMappingEditor *mappingEditor;
/* Whether it edits what `editor` edits. */
- (BOOL)editsSameAs:(MBMappingObjectEditor *)editor;
/* Every property's observers told it may have changed. */
- (void)reload;
/* What its user info table shows and edits. */
@property (nonatomic, copy) NSDictionary *userInfo;
@end

@interface MBEntityMappingEditor : MBMappingObjectEditor

+ (instancetype)editorForEntityMapping:(NSEntityMapping *)mapping mappingEditor:(MBMappingEditor *)mappingEditor;

@property (nonatomic, strong, readonly) NSEntityMapping *entityMapping;
@property (nonatomic, copy) NSString *name;   /* unique among the mappings */

/* The entities it pairs, as their pop-ups show them: "None", then the
   model's entities (and a name the model no longer has, which is still
   what the file says).  Changing one changes the mapping's type. */
@property (nonatomic, copy, readonly) NSArray *sourceEntityTitles;
@property (nonatomic, copy) NSString *sourceEntityTitle;
@property (nonatomic, copy, readonly) NSArray *destinationEntityTitles;
@property (nonatomic, copy) NSString *destinationEntityTitle;
@property (nonatomic, copy, readonly) NSString *mappingTypeName;
@property (nonatomic, copy) NSString *customPolicy;

/* Source Fetch: 0 Default (every object of the source entity), 1 Custom
   (those its filter predicate admits).  An added entity is fetched from
   nowhere: nothing to choose, nothing to narrow. */
@property (nonatomic, readonly) BOOL fetchesSource;
@property (nonatomic, assign) NSInteger sourceFetchIndex;
@property (nonatomic, readonly) BOOL filtersSource;
@property (nonatomic, copy) NSString *filterPredicate;   /* empty for none */

@end

@interface MBPropertyMappingEditor : MBMappingObjectEditor

+ (instancetype)editorForPropertyNamed:(NSString *)name
                       inEntityMapping:(NSEntityMapping *)mapping
                         relationships:(BOOL)relationships
                         mappingEditor:(MBMappingEditor *)mappingEditor;

@property (nonatomic, strong, readonly) NSEntityMapping *entityMapping;
@property (nonatomic, readonly) BOOL relationships;
/* Its property mapping, nil while nothing fills the row. */
@property (nonatomic, strong, readonly) NSPropertyMapping *propertyMapping;

/* The destination property it fills: its pop-up's items are the
   destination entity's attributes (or relationships).  Taking a name
   another row has swaps the two. */
@property (nonatomic, copy, readonly) NSArray *nameTitles;
@property (nonatomic, copy) NSString *name;

/* A value expression written by hand: empty for the one the compiler
   works out, which is what the field's placeholder shows. */
@property (nonatomic, copy) NSString *valueExpressionString;
@property (nonatomic, copy, readonly) NSString *generatedExpressionString;

/* A relationship's Source Fetch: 0 Auto Generate Value Expression (from a
   key path and the mapping that made what it reaches), 1 Custom (an
   expression written by hand). */
@property (nonatomic, assign) NSInteger sourceFetchIndex;
@property (nonatomic, readonly) BOOL generatesExpression;
@property (nonatomic, readonly) BOOL writesExpression;
@property (nonatomic, copy) NSString *keyPath;
@property (nonatomic, copy) NSString *mappingName;

@end
