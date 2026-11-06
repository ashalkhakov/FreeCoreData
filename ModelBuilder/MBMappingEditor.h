/* ModelBuilder — one mapping model, edited.  The coordinator the mapping
   window works through, as MBModelEditor is the model window's: it holds
   the mapping as a live NSMappingModel read from and written back to its
   xcmapping.xml (CDMappingCompiler and CDMappingSerializer), with the two
   models it maps between; makes every change to it, recording each one's
   inverse on the undo manager it is given; and says what changed and what
   is selected.

   The app's MBMappingDocument has one and gives it the document's undo
   manager; a host that keeps the XML as text of its own (UDCode's) gives
   it none, and the text's undo is the undo.

   The mapping's objects are changed in place, so a change's inverse is
   recorded against the object itself and finds it after a rename.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

/* Posted (object: the mapping editor) after every change to the mapping:
   once for an edit's, when it ends. */
extern NSString *const MBMappingEditorDidChangeNotification;
/* Posted (object: the mapping editor) when the selection changes: inside
   an edit, when it ends, after the mapping's change. */
extern NSString *const MBMappingEditorSelectionDidChangeNotification;

typedef NS_ENUM(NSInteger, MBMappingSelectionKind) {
  MBMappingSelectionNone = 0,
  MBMappingSelectionEntityMapping,
  MBMappingSelectionAttributeMapping,
  MBMappingSelectionRelationshipMapping
};

/* What is selected, by name: an entity mapping, or one of its property
   rows (a property of its destination entity, mapped or not yet). */
@interface MBMappingSelection : NSObject <NSCopying>
@property (nonatomic, readonly) MBMappingSelectionKind kind;
@property (nonatomic, copy, readonly) NSString *entityMappingName;
@property (nonatomic, copy, readonly) NSString *propertyName;
+ (instancetype)selectionOfKind:(MBMappingSelectionKind)kind
              entityMappingName:(NSString *)entityMappingName
                   propertyName:(NSString *)propertyName;
+ (instancetype)entityMappingNamed:(NSString *)name;
@end

@interface MBMappingEditor : NSObject

/* An editor of an empty mapping between no models, or of the mapping an
   xcmapping.xml describes: `path` is the .xcmappingmodel it is in, where
   the two models it names are looked for. */
- (instancetype)initWithUndoManager:(NSUndoManager *)undoManager;
- (instancetype)initWithXMLString:(NSString *)xml
                           atPath:(NSString *)path
                      undoManager:(NSUndoManager *)undoManager
                            error:(NSError **)error;

/* Where the inverses go; nil records none. */
@property (nonatomic, weak) NSUndoManager *undoManager;

@property (nonatomic, strong, readonly) NSMappingModel *mappingModel;
@property (nonatomic, strong, readonly) NSManagedObjectModel *sourceModel;
@property (nonatomic, strong, readonly) NSManagedObjectModel *destinationModel;

/* As the file records them, which is how Xcode's editor finds the models
   too: kept so the file written says what it said. */
@property (nonatomic, copy, readonly) NSString *sourceModelPath;
@property (nonatomic, copy, readonly) NSString *destinationModelPath;

/* The mapping as xcmapping.xml, written over the text it was read from
   (what only Xcode can put there is kept); and the mapping an
   xcmapping.xml describes, read (not an edit: nothing is recorded, and a
   failure changes nothing). */
- (NSString *)XMLString:(NSError **)error;
- (BOOL)readXMLString:(NSString *)xml atPath:(NSString *)path error:(NSError **)error;

/* The mapping and its models as given: a new mapping model's. */
- (void)setMappingModel:(NSMappingModel *)mappingModel
            sourceModel:(NSManagedObjectModel *)sourceModel
       destinationModel:(NSManagedObjectModel *)destinationModel
        sourceModelPath:(NSString *)sourceModelPath
   destinationModelPath:(NSString *)destinationModelPath;

/* What the window's parts show.  A rename keeps it (it follows the name);
   setting it posts MBMappingEditorSelectionDidChangeNotification. */
@property (nonatomic, copy) MBMappingSelection *selection;
- (NSEntityMapping *)selectedEntityMapping;

- (NSArray *)entityMappings;
- (NSEntityMapping *)entityMappingNamed:(NSString *)name;

/* The entities of each model, by name. */
- (NSArray *)sourceEntityNames;
- (NSArray *)destinationEntityNames;

/* The rows an entity mapping shows: the names of its destination entity's
   attributes (or relationships), in the entity's order, whether anything
   fills them yet or not, then any the mapping fills that the entity does
   not have.  Reading them changes nothing. */
- (NSArray *)propertyNamesOfEntityMapping:(NSEntityMapping *)mapping relationships:(BOOL)relationships;
/* The property mapping of a row, nil while nothing fills it. */
- (NSPropertyMapping *)propertyMappingNamed:(NSString *)name
                            inEntityMapping:(NSEntityMapping *)mapping
                              relationships:(BOOL)relationships;
/* The same, made (an undoable change) when there is none yet: for an edit
   of the row. */
- (NSPropertyMapping *)propertyMappingToEditNamed:(NSString *)name
                                  inEntityMapping:(NSEntityMapping *)mapping
                                    relationships:(BOOL)relationships;

/* The predicate an author wrote to narrow a mapping, nil for all objects
   of the entity.  Held in the mapping's source expression, which is built
   again when this changes. */
- (NSString *)filterPredicateOfEntityMapping:(NSEntityMapping *)mapping;
- (void)setFilterPredicate:(NSString *)predicate forEntityMapping:(NSEntityMapping *)mapping;

/* A value expression written by hand, nil for the one the compiler works
   out - which is what an editor shows as an empty cell. */
- (NSString *)valueExpressionStringOfPropertyMapping:(NSPropertyMapping *)property;
- (BOOL)setValueExpressionString:(NSString *)string
               ofPropertyMapping:(NSPropertyMapping *)property
                           error:(NSError **)error;

/* Mappings come and go: one per pair of entities the author pairs up. */
- (NSEntityMapping *)addEntityMappingFromEntityNamed:(NSString *)sourceName
                                      toEntityNamed:(NSString *)destinationName;
- (void)removeEntityMapping:(NSEntityMapping *)mapping;

/* What the inspector shows and sets on an entity mapping.  Its type is
   not the author's to choose: it follows from the entities it pairs, and
   changes when they do. */
- (NSString *)mappingTypeNameOfEntityMapping:(NSEntityMapping *)mapping;
- (void)setName:(NSString *)name ofEntityMapping:(NSEntityMapping *)mapping;
- (void)setSourceEntityName:(NSString *)sourceName
      destinationEntityName:(NSString *)destinationName
            ofEntityMapping:(NSEntityMapping *)mapping;
- (void)setMigrationPolicyClassName:(NSString *)className ofEntityMapping:(NSEntityMapping *)mapping;

/* User info, on an entity mapping or a property mapping alike. */
- (void)setUserInfo:(NSDictionary *)userInfo ofMappingObject:(id)subject;

/* Which destination property a property mapping fills.  Two mappings
   cannot fill one property, so taking a name another mapping has swaps
   the two. */
- (void)setName:(NSString *)name
    ofPropertyMapping:(NSPropertyMapping *)property
      inEntityMapping:(NSEntityMapping *)mapping;

/* A relationship filled through another entity mapping, as Xcode's
   "Auto Generate Value Expression" fills it: YES, with the key path it
   follows from the source object and the mapping that made the objects it
   reaches, when the relationship mapping is filled that way (or not yet
   filled at all, in which case the two are what the compiler would use). */
- (BOOL)relationshipMappingNamed:(NSString *)name
                 inEntityMapping:(NSEntityMapping *)mapping
                         keyPath:(NSString **)keyPath
                     mappingName:(NSString **)mappingName;
- (void)setKeyPath:(NSString *)keyPath
          mappingName:(NSString *)mappingName
ofRelationshipMapping:(NSPropertyMapping *)property;

/* "Custom" chosen in a Source Fetch pop-up before anything custom has
   been written: nothing in the mapping says so yet, so it is kept here,
   for as long as the mapping is edited - for an entity mapping, or (with
   a name) one of its relationship rows. */
- (BOOL)choseCustomFetchFor:(NSEntityMapping *)mapping property:(NSString *)propertyName;
- (void)setChoseCustomFetch:(BOOL)chose for:(NSEntityMapping *)mapping property:(NSString *)propertyName;

/* Undo, as in MBModelEditor: an edit is everything between -beginEdit:
   and the matching -endEdit (they nest; the outermost pair is one undo
   step, named by the first name given), and each change records its
   inverse - the value it replaced, set back through the same door. */
- (void)beginEdit:(NSString *)actionName;
- (void)endEdit;
- (void)setValue:(id)value forKey:(NSString *)key ofMappingObject:(id)subject;

@end
