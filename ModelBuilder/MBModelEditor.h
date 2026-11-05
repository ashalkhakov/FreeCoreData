/* ModelBuilder — one model version, edited.  The coordinator the rest of
   the editor works through: it holds the version as a live
   NSManagedObjectModel read from and written back to its contents XML
   (CDModelCompiler and CDModelSerializer, momc's parser and its inverse),
   makes every structural change to it, records each change's inverse on
   the undo manager it is given, and says when the model changed.

   The app's MBDocument has one for the version being edited and gives it
   the document's undo manager; a host that keeps the XML as text of its
   own (UDCode's) gives it none, and the text's undo is the undo.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

/* Posted (object: the model editor) after every change to the model. */
extern NSString *const MBModelEditorDidChangeNotification;
/* Posted (object: the model editor) when the selection changes. */
extern NSString *const MBModelEditorSelectionDidChangeNotification;

typedef NS_ENUM(NSInteger, MBSelectionKind) {
  MBSelectionNone = 0,
  MBSelectionEntity,
  MBSelectionAttribute,
  MBSelectionRelationship,
  MBSelectionFetchRequest,
  MBSelectionConfiguration,
  MBSelectionFetchIndex
};

/* What is selected, by name, so that it outlives the model being
   rebuilt (removal, reparenting and configurations recompile it): an
   entity; an attribute, relationship or fetch index of an entity; a fetch
   request; a configuration (the implicit Default is "Default": a model
   that declares a configuration of that name has no implicit one), and
   perhaps an entity picked on its page. */
@interface MBSelection : NSObject <NSCopying>
@property (nonatomic, readonly) MBSelectionKind kind;
@property (nonatomic, copy, readonly) NSString *entityName;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *configurationName;
+ (instancetype)selectionOfKind:(MBSelectionKind)kind
                     entityName:(NSString *)entityName
                           name:(NSString *)name
              configurationName:(NSString *)configurationName;
+ (instancetype)entityNamed:(NSString *)name;
+ (instancetype)fetchRequestNamed:(NSString *)name;
+ (instancetype)configurationNamed:(NSString *)name;
@end

@interface MBModelEditor : NSObject

/* An editor of a new model with one entity, or of the version a contents
   XML describes. */
- (instancetype)initWithUndoManager:(NSUndoManager *)undoManager;
- (instancetype)initWithContentsXML:(NSString *)xml
                        undoManager:(NSUndoManager *)undoManager
                              error:(NSError **)error;

/* Where the inverses go; nil records none. */
@property (nonatomic, weak) NSUndoManager *undoManager;

/* The version, as a live model. */
@property (nonatomic, strong, readonly) NSManagedObjectModel *model;

/* Canvas geometry per entity name: {"positionX","positionY","width",
   "height"} string values, preserved through the <elements> section. */
@property (nonatomic, strong, readonly) NSMutableDictionary *entityLayouts;

/* The version as contents XML, and the version a contents XML describes
   (not an edit: nothing is recorded, and a failure changes nothing). */
- (NSString *)contentsXML:(NSError **)error;
- (BOOL)readContentsXML:(NSString *)xml error:(NSError **)error;

/* What the window's parts show.  A rename keeps it (it follows the
   name); setting it posts MBModelEditorSelectionDidChangeNotification. */
@property (nonatomic, copy) MBSelection *selection;

/* The selection's objects, as the model has them now (nil where it names
   nothing that is there). */
- (NSEntityDescription *)selectedEntity;
- (NSPropertyDescription *)selectedProperty;
- (NSFetchRequest *)selectedFetchRequest;

- (NSArray *)sortedEntities;       /* the model's entities, by name */
- (NSArray *)configurationNames;   /* sorted */

/* Says the model changed (MBModelEditorDidChangeNotification). */
- (void)noteModelChanged;

/* A property or a fetch index of an entity renamed, by its editor: the
   selection follows it. */
- (void)noteRenameOfKind:(MBSelectionKind)kind
                 inEntity:(NSString *)entityName
                     from:(NSString *)oldName
                       to:(NSString *)newName;

/* Undo.  An edit is everything between -beginEdit: and the matching
   -endEdit (they nest; the outermost pair is one undo step, named by the
   first name given).  Inside it, each change records its inverse:
   editors through -registerInverseValue:forKey:ofSubject: -- the previous
   value of an editor key, replayed on the description object's editor --
   and structural changes through the operations below, which record
   their own.  An edit that records nothing leaves no undo step. */
- (void)beginEdit:(NSString *)actionName;
- (void)endEdit;
- (void)setUndoActionName:(NSString *)name;   /* names the next edit */
- (void)registerInverseValue:(id)value forKey:(NSString *)key ofSubject:(id)subject;

/* The proxy to record the inverse of a change of another object's on
   (the document's versions), in the edit's undo step; nil without an
   undo manager. */
- (id)inverseFor:(id)target;

/* The model and its layouts replaced as they are: for an inverse that
   puts back what it recorded itself. */
- (void)replaceModel:(NSManagedObjectModel *)model layouts:(NSDictionary *)layouts;

/* Properties, as structural changes that record their own inverses. */
- (void)insertProperty:(NSPropertyDescription *)property
              intoEntity:(NSEntityDescription *)entity
                 atIndex:(NSUInteger)index;
- (void)removeProperty:(NSPropertyDescription *)property;
- (void)replaceProperty:(NSPropertyDescription *)current
           withProperty:(NSPropertyDescription *)replacement;

/* Entity lifecycle.  Renames re-key the layout sidecar and refuse
   duplicates; removal and reparenting are structural surgery performed
   at the model layer (CDModelMutator, beside the compiler and
   serializer), so momc renormalizes relationships, configurations,
   fetch templates and subentity wiring in one step and a failed edit
   leaves the model unchanged. */
- (NSString *)addEntity;                       /* returns the new name */
- (BOOL)renameEntityNamed:(NSString *)name to:(NSString *)newName;
- (BOOL)removeEntityNamed:(NSString *)name error:(NSError **)error;
- (BOOL)setParentOfEntityNamed:(NSString *)entityName
                            to:(NSString *)parentName   /* empty = detach */
                         error:(NSError **)error;

/* Fetch request template lifecycle.  Add picks the named entity, or
   the first entity when nil; rename refuses duplicates. */
- (NSString *)addFetchRequestForEntityNamed:(NSString *)entityName;
- (void)removeFetchRequestNamed:(NSString *)name;
- (BOOL)renameFetchRequestNamed:(NSString *)name to:(NSString *)newName;
- (void)setFetchRequest:(NSFetchRequest *)request forName:(NSString *)name;

/* Configurations, edited through CDModelMutator (add, remove, rename,
   membership toggling) so the compiler renormalizes each change -
   NSManagedObjectModel has no mutation API for them. */
- (NSString *)addConfiguration;
- (BOOL)removeConfigurationNamed:(NSString *)name error:(NSError **)error;
- (BOOL)renameConfiguration:(NSString *)name to:(NSString *)newName error:(NSError **)error;
- (BOOL)setEntityNamed:(NSString *)entityName
       inConfiguration:(NSString *)configurationName
                member:(BOOL)member
                 error:(NSError **)error;

@end
