/* Editing view-models for the ModelBuilder inspector — one per
   selection kind.  Each wraps (description object + MBModelEditor) and
   exposes KVC/KVO-compliant properties whose setters hide the editing
   specifics: validated renames that refuse duplicates, type changes
   that drop the stale default, two-sided inverse wiring, reparenting
   through the model editor's XML path, derived-attribute flips that
   replace the description object.  The inspector binds its fields to
   them (through an NSObjectController per page in MBInspector.xib);
   nothing here touches a view.

   They are the model layer's gate: what a field gives is validated
   here, by key-value validation (-validateValue:forKey:error:, which a
   binding with NSValidatesImmediately calls): a name must be new, a
   number a number, a predicate must parse, a parent must not make a
   cycle.  A setter given an unvalidated value still refuses what it
   cannot take, and records why in lastError instead of throwing.

   Editors resolve their description object by name on every access,
   so they stay valid across renames, across the plain<->derived
   replacement and across graph surgery that replaces the model.  The
   object can change under an editor (an undo, another part's edit):
   -reload tells its observers that every property may have changed.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
/* AppKit before CoreData: the port defines NSAttributeType compatibly
   with GNUstep AppKit only in that order (see NSAttributeDescription.h). */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class MBModelEditor;

/* The domain of the editors' errors, validation's included. */
extern NSString *const MBEditorErrorDomain;

/* `object`'s observers told that each of its properties, declared by its
   class and its superclasses below `root`, may have changed. */
void MBReloadProperties(NSObject *object, Class root);

@interface MBEditor : NSObject
@property (nonatomic, strong, readonly) MBModelEditor *modelEditor;
@property (nonatomic, strong, readonly) NSError *lastError;
/* The editor for a description object (an entity, attribute,
   relationship or fetch request of the model editor's model), as it is now.
   Undo replays an edit on it: its setters record the redo. */
+ (MBEditor *)editorForSubject:(id)subject modelEditor:(MBModelEditor *)modelEditor;

/* Whether it edits what `editor` edits (the same kind, by the same names). */
- (BOOL)editsSameAs:(MBEditor *)editor;
/* Every property's observers told it may have changed. */
- (void)reload;
@end

/* ---------------------------------------------------------------- */

/* The model version itself - what Xcode's File inspector shows for a
   selected .xcdatamodel under "Core Data Model". */
@interface MBVersionEditor : MBEditor

+ (instancetype)editorForModelEditor:(MBModelEditor *)modelEditor;

/* The version's Identifier (userDefinedModelVersionIdentifier): the
   model's one version identifier; empty -> none. */
@property (nonatomic, copy) NSString *versionIdentifier;

@end

/* ---------------------------------------------------------------- */

@interface MBEntityEditor : MBEditor

+ (instancetype)editorForEntityNamed:(NSString *)name modelEditor:(MBModelEditor *)modelEditor;

@property (nonatomic, strong, readonly) NSEntityDescription *entity;
@property (nonatomic, copy) NSString *name;          /* validated rename */
@property (nonatomic, copy) NSString *className;     /* empty -> NSManagedObject */
@property (nonatomic, assign, getter=isAbstract) BOOL abstract;
@property (nonatomic, copy) NSString *parentName;    /* empty detaches; XML path */
/* The parent as its pop-up shows it: "(none)", then every other entity. */
@property (nonatomic, copy, readonly) NSArray *parentTitles;
@property (nonatomic, copy) NSString *parentTitle;
@property (nonatomic, copy) NSString *hashModifier;  /* empty -> nil */
@property (nonatomic, copy) NSString *renamingIdentifier; /* shows the name when defaulted; setting it to the name (or empty) resets */
@property (nonatomic, copy) NSString *codegenType; /* Xcode XML spelling: @"class", @"category", or empty for Manual/None */
/* The pop-up's order: Manual/None, Class Definition, Category/Extension. */
@property (nonatomic, assign) NSInteger codegenIndex;
@property (nonatomic, copy) NSDictionary *userInfo;

/* Uniqueness constraints as comma-joined attribute-name strings, one
   per constraint (the table's row format). */
@property (nonatomic, copy) NSArray *constraintRows;

/* The entity's fetch indexes, one dictionary per index, in order:
     name       the index's name
     predicate  its partial predicate's format, or absent
     elements   one dictionary per element:
                  property    the property's name (an attribute, or a
                              to-one relationship)
                  expression  instead of a property: the index's own
                              NSExpressionDescription
                  rtree       @YES for an R-tree element
                  ascending   @NO for a descending one
   Setting them replaces the indexes - refusing (lastError) a predicate
   that does not parse, an R-tree element that is not a small number, or
   an index of R-tree and binary elements both. */
@property (nonatomic, copy) NSArray *fetchIndexRows;
- (NSString *)addFetchIndex;
- (void)removeFetchIndexNamed:(NSString *)name;

/* Property lifecycle.  Add returns the new property's name; removes
   unwire a removed relationship's inverse, and take the property out of
   any fetch index that names it. */
- (NSString *)addAttribute;
- (void)removeAttributeNamed:(NSString *)name;
- (NSString *)addRelationship;
- (void)removeRelationshipNamed:(NSString *)name;

@end

/* ---------------------------------------------------------------- */

@interface MBAttributeEditor : MBEditor

+ (instancetype)editorForAttributeNamed:(NSString *)name
                                 entity:(NSEntityDescription *)entity
                               modelEditor:(MBModelEditor *)modelEditor;

@property (nonatomic, strong, readonly) NSAttributeDescription *attribute;
@property (nonatomic, copy) NSString *name;          /* validated rename */
@property (nonatomic, copy) NSString *typeName;      /* momc spelling; change drops default */
/* What momc accepts, the type pop-up's items. */
@property (nonatomic, copy, readonly) NSArray *typeNames;
@property (nonatomic, readonly, getter=isBinary) BOOL binary;
@property (nonatomic, assign, getter=isOptional) BOOL optional;
@property (nonatomic, assign, getter=isTransient) BOOL transient;
/* With persistent history tracking, a deleted object's last value for
   this attribute is kept in the history change's tombstone
   (preserveAfterDeletion in the model XML, as Xcode writes it). */
@property (nonatomic, assign) BOOL preservesValueInHistoryOnDeletion;
/* A SQLite store may keep a Binary Data value larger than 128 KiB in a
   file of its own (allowsExternalBinaryDataStorage in the model XML):
   an option of Binary Data alone, as Xcode's. */
@property (nonatomic, assign) BOOL allowsExternalBinaryDataStorage;
@property (nonatomic, copy) NSString *hashModifier;
@property (nonatomic, copy) NSDictionary *userInfo;

/* Default value, as the inspector edits it: a string parsed per the
   current type (numbers, strings, booleans as YES/NO, UUIDs, URIs) or
   a date for date attributes.  Empty/nil clears, but a string
   attribute's default stays, empty, while it has one. */
@property (nonatomic, copy) NSString *defaultString;
@property (nonatomic, copy) NSDate *defaultDate;
/* A number's default as its formatted field gives and shows it: nil for none. */
@property (nonatomic, copy) NSNumber *defaultNumber;
/* A string's default ticked: an empty one, or none. */
@property (nonatomic, assign) BOOL hasDefaultString;
/* A boolean's default as its pop-up's index: No Value, YES, NO. */
@property (nonatomic, assign) NSInteger boolDefaultIndex;

/* The dates, each as a tick and a picker: ticking gives it what the
   picker shows, which without a date is the moment the editor was made. */
@property (nonatomic, assign) BOOL hasDefaultDate;
@property (nonatomic, copy) NSDate *shownDefaultDate;
@property (nonatomic, assign) BOOL hasValidationMinDate;
@property (nonatomic, copy) NSDate *shownValidationMinDate;
@property (nonatomic, assign) BOOL hasValidationMaxDate;
@property (nonatomic, copy) NSDate *shownValidationMaxDate;

/* Transformable details.  Empty strings mean "unset" (never nil on
   the description: Apple CoreData throws). */
@property (nonatomic, copy) NSString *transformerName;
@property (nonatomic, copy) NSString *customClassName;

/* Non-empty makes the attribute derived (replacing the description
   object), empty makes it plain; invalid expressions set lastError
   and leave the attribute unchanged. */
@property (nonatomic, copy) NSString *derivationString;
@property (nonatomic, readonly, getter=isDerived) BOOL derived;
/* What the Derived tick's tool tip says. */
@property (nonatomic, copy, readonly) NSString *derivationToolTip;

@property (nonatomic, copy) NSString *renamingIdentifier;

/* usesScalarValueType (codegen metadata; see CDModelCompiler). */
@property (nonatomic, assign) BOOL scalarType;

/* Validation, over CDModelCompiler's canonical predicate shapes.
   Strings; empty clears.  Numbers use min/max, strings use the length
   pair and the regex, dates use the NSDate pair (nil clears). */
@property (nonatomic, copy) NSString *validationMin;
@property (nonatomic, copy) NSString *validationMax;
@property (nonatomic, copy) NSString *minLengthString;
@property (nonatomic, copy) NSString *maxLengthString;
@property (nonatomic, copy) NSString *regexString;
@property (nonatomic, copy) NSDate *validationMinDate;
@property (nonatomic, copy) NSDate *validationMaxDate;
/* The number bounds and the lengths as their formatted fields give and
   show them: nil for none. */
@property (nonatomic, copy) NSNumber *validationMinNumber;
@property (nonatomic, copy) NSNumber *validationMaxNumber;
@property (nonatomic, copy) NSNumber *minLengthNumber;
@property (nonatomic, copy) NSNumber *maxLengthNumber;

@end

/* ---------------------------------------------------------------- */

@interface MBRelationshipEditor : MBEditor

+ (instancetype)editorForRelationshipNamed:(NSString *)name
                                    entity:(NSEntityDescription *)entity
                                  modelEditor:(MBModelEditor *)modelEditor;

@property (nonatomic, strong, readonly) NSRelationshipDescription *relationship;
@property (nonatomic, copy) NSString *name;            /* validated rename */
@property (nonatomic, copy) NSString *destinationName; /* unwires a stale inverse */
@property (nonatomic, copy) NSString *inverseName;     /* empty unwires; wires both sides */
/* The destination and the inverse as their pop-ups show them:
   "(none)", then the model's entities / the destination's relationships. */
@property (nonatomic, copy, readonly) NSArray *destinationTitles;
@property (nonatomic, copy) NSString *destinationTitle;
@property (nonatomic, copy, readonly) NSArray *inverseTitles;
@property (nonatomic, copy) NSString *inverseTitle;
@property (nonatomic, assign, getter=isToMany) BOOL toMany;
/* The type as its pop-up's index: To Many, To One. */
@property (nonatomic, assign) NSInteger typeIndex;
@property (nonatomic, assign, getter=isOrdered) BOOL ordered;   /* to-many only */
@property (nonatomic, assign) NSInteger minCount;      /* to-many only; 0 = unset */
@property (nonatomic, assign) NSInteger maxCount;      /* to-many only; 0/1 = unbounded */
/* The counts as their formatted fields give and show them: nil for unset. */
@property (nonatomic, copy) NSNumber *minCountNumber;
@property (nonatomic, copy) NSNumber *maxCountNumber;
@property (nonatomic, copy) NSString *deleteRuleName;  /* momc spelling */
/* The rule as its pop-up's index: No Action, Nullify, Cascade, Deny. */
@property (nonatomic, assign) NSInteger deleteRuleIndex;
@property (nonatomic, assign, getter=isOptional) BOOL optional;
@property (nonatomic, assign, getter=isTransient) BOOL transient;
@property (nonatomic, copy) NSString *hashModifier;
@property (nonatomic, copy) NSString *renamingIdentifier;
@property (nonatomic, copy) NSDictionary *userInfo;

@end

/* ---------------------------------------------------------------- */

@interface MBFetchEditor : MBEditor

+ (instancetype)editorForFetchRequestNamed:(NSString *)name modelEditor:(MBModelEditor *)modelEditor;

@property (nonatomic, strong, readonly) NSFetchRequest *request;
@property (nonatomic, copy) NSString *name;            /* re-keys the template map */
@property (nonatomic, copy) NSString *entityName;
/* The model's entities, by name: the entity pop-up's items. */
@property (nonatomic, copy, readonly) NSArray *entityNames;
@property (nonatomic, assign) NSUInteger fetchLimit;   /* 0 = no limit */

/* Predicate as format string; empty clears, an unparseable string
   sets lastError and keeps the old predicate. */
@property (nonatomic, copy) NSString *predicateFormat;
@property (nonatomic, strong) NSPredicate *predicate;

/* Template result shape and paging. */
@property (nonatomic, assign) NSFetchRequestResultType resultType;
/* The pop-up's order: Objects, Object IDs, Dictionaries. */
@property (nonatomic, assign) NSInteger resultTypeIndex;
@property (nonatomic, assign) NSUInteger fetchBatchSize;
/* The limit and the batch size as their formatted fields give and show
   them: nil for 0. */
@property (nonatomic, copy) NSNumber *fetchLimitNumber;
@property (nonatomic, copy) NSNumber *fetchBatchSizeNumber;

/* The template flags; like Apple's momc, absent-in-XML means NO. */
@property (nonatomic, assign) BOOL includesSubentities;
@property (nonatomic, assign) BOOL includesPropertyValues;
@property (nonatomic, assign) BOOL returnsObjectsAsFaults;
@property (nonatomic, assign) BOOL includesPendingChanges;
@property (nonatomic, assign) BOOL returnsDistinctResults;

@end

/* ---------------------------------------------------------------- */

/* One fetch index of an entity, through its entity's fetchIndexRows. */
@interface MBFetchIndexEditor : MBEditor

+ (instancetype)editorForFetchIndexNamed:(NSString *)name
                                  entity:(NSEntityDescription *)entity
                             modelEditor:(MBModelEditor *)modelEditor;

/* Its row (see MBEntityEditor's fetchIndexRows). */
@property (nonatomic, copy, readonly) NSDictionary *row;
@property (nonatomic, copy) NSString *name;              /* unique in the entity; the selection follows */
@property (nonatomic, copy) NSString *predicateFormat;   /* the partial predicate; empty for none */

@end
