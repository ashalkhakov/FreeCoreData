/* Editing view-models for the ModelBuilder inspector — one per
   selection kind.  Each wraps (description object + MBDocument) and
   exposes plain KVC properties whose setters hide the editing
   specifics: validated renames that refuse duplicates, type changes
   that drop the stale default, two-sided inverse wiring, reparenting
   through the document's XML path, derived-attribute flips that
   replace the description object.  The window controller copies
   control values in and out; nothing here touches a view, so the
   properties are bindable in principle.

   Editors resolve their description object by name on every access,
   so they stay valid across renames and across the plain<->derived
   replacement.  Setters that can fail record the reason in lastError
   (checked by the controller after an apply pass) instead of throwing.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
/* AppKit before CoreData: the port defines NSAttributeType compatibly
   with GNUstep AppKit only in that order (see NSAttributeDescription.h). */
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class MBDocument;

@interface MBEditor : NSObject
@property (nonatomic, strong, readonly) MBDocument *document;
@property (nonatomic, strong, readonly) NSError *lastError;
@end

/* ---------------------------------------------------------------- */

@interface MBEntityEditor : MBEditor

+ (instancetype)editorForEntityNamed:(NSString *)name document:(MBDocument *)document;

@property (nonatomic, strong, readonly) NSEntityDescription *entity;
@property (nonatomic, copy) NSString *name;          /* validated rename */
@property (nonatomic, copy) NSString *className;     /* empty -> NSManagedObject */
@property (nonatomic, assign, getter=isAbstract) BOOL abstract;
@property (nonatomic, copy) NSString *parentName;    /* empty detaches; XML path */
@property (nonatomic, copy) NSString *hashModifier;  /* empty -> nil */
@property (nonatomic, copy) NSString *renamingIdentifier; /* shows the name when defaulted; setting it to the name (or empty) resets */
@property (nonatomic, copy) NSString *codegenType; /* Xcode XML spelling: @"class", @"category", or empty for Manual/None */
@property (nonatomic, copy) NSDictionary *userInfo;

/* Uniqueness constraints as comma-joined attribute-name strings, one
   per constraint (the table's row format). */
@property (nonatomic, copy) NSArray *constraintRows;

/* Property lifecycle.  Add returns the new property's name; removes
   unwire a removed relationship's inverse. */
- (NSString *)addAttribute;
- (void)removeAttributeNamed:(NSString *)name;
- (NSString *)addRelationship;
- (void)removeRelationshipNamed:(NSString *)name;

@end

/* ---------------------------------------------------------------- */

@interface MBAttributeEditor : MBEditor

+ (instancetype)editorForAttributeNamed:(NSString *)name
                                 entity:(NSEntityDescription *)entity
                               document:(MBDocument *)document;

@property (nonatomic, strong, readonly) NSAttributeDescription *attribute;
@property (nonatomic, copy) NSString *name;          /* validated rename */
@property (nonatomic, copy) NSString *typeName;      /* momc spelling; change drops default */
@property (nonatomic, assign, getter=isOptional) BOOL optional;
@property (nonatomic, assign, getter=isTransient) BOOL transient;
@property (nonatomic, copy) NSString *hashModifier;
@property (nonatomic, copy) NSDictionary *userInfo;

/* Default value, as the inspector edits it: a string parsed per the
   current type (numbers, strings, booleans as YES/NO, UUIDs, URIs) or
   a date for date attributes.  Empty/nil clears. */
@property (nonatomic, copy) NSString *defaultString;
@property (nonatomic, copy) NSDate *defaultDate;

/* Transformable details.  Empty strings mean "unset" (never nil on
   the description: Apple CoreData throws). */
@property (nonatomic, copy) NSString *transformerName;
@property (nonatomic, copy) NSString *customClassName;

/* Non-empty makes the attribute derived (replacing the description
   object), empty makes it plain; invalid expressions set lastError
   and leave the attribute unchanged. */
@property (nonatomic, copy) NSString *derivationString;
@property (nonatomic, readonly, getter=isDerived) BOOL derived;

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

@end

/* ---------------------------------------------------------------- */

@interface MBRelationshipEditor : MBEditor

+ (instancetype)editorForRelationshipNamed:(NSString *)name
                                    entity:(NSEntityDescription *)entity
                                  document:(MBDocument *)document;

@property (nonatomic, strong, readonly) NSRelationshipDescription *relationship;
@property (nonatomic, copy) NSString *name;            /* validated rename */
@property (nonatomic, copy) NSString *destinationName; /* unwires a stale inverse */
@property (nonatomic, copy) NSString *inverseName;     /* empty unwires; wires both sides */
@property (nonatomic, assign, getter=isToMany) BOOL toMany;
@property (nonatomic, assign, getter=isOrdered) BOOL ordered;   /* to-many only */
@property (nonatomic, assign) NSInteger minCount;      /* to-many only; 0 = unset */
@property (nonatomic, assign) NSInteger maxCount;      /* to-many only; 0/1 = unbounded */
@property (nonatomic, copy) NSString *deleteRuleName;  /* momc spelling */
@property (nonatomic, assign, getter=isOptional) BOOL optional;
@property (nonatomic, assign, getter=isTransient) BOOL transient;
@property (nonatomic, copy) NSString *hashModifier;
@property (nonatomic, copy) NSString *renamingIdentifier;
@property (nonatomic, copy) NSDictionary *userInfo;

@end

/* ---------------------------------------------------------------- */

@interface MBFetchEditor : MBEditor

+ (instancetype)editorForFetchRequestNamed:(NSString *)name document:(MBDocument *)document;

@property (nonatomic, strong, readonly) NSFetchRequest *request;
@property (nonatomic, copy) NSString *name;            /* re-keys the template map */
@property (nonatomic, copy) NSString *entityName;
@property (nonatomic, assign) NSUInteger fetchLimit;   /* 0 = no limit */

/* Predicate as format string; empty clears, an unparseable string
   sets lastError and keeps the old predicate. */
@property (nonatomic, copy) NSString *predicateFormat;
@property (nonatomic, strong) NSPredicate *predicate;

/* Template result shape and paging. */
@property (nonatomic, assign) NSFetchRequestResultType resultType;
@property (nonatomic, assign) NSUInteger fetchBatchSize;

/* The template flags; like Apple's momc, absent-in-XML means NO. */
@property (nonatomic, assign) BOOL includesSubentities;
@property (nonatomic, assign) BOOL includesPropertyValues;
@property (nonatomic, assign) BOOL returnsObjectsAsFaults;
@property (nonatomic, assign) BOOL includesPendingChanges;
@property (nonatomic, assign) BOOL returnsDistinctResults;

@end
