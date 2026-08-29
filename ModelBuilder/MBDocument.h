/* ModelBuilder document — a .xcdatamodeld wrapper edited through
   FreeCoreData's own model classes: CDModelCompiler parses the version
   XML into an NSManagedObjectModel, the editor mutates the description
   objects directly, and CDModelSerializer writes Xcode's XML back.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@interface MBDocument : NSDocument

/* The version being edited, as a live NSManagedObjectModel. */
@property (nonatomic, strong) NSManagedObjectModel *model;

/* File name of the version being edited ("Model 2.xcdatamodel"). */
@property (nonatomic, copy) NSString *editedVersionName;

/* File name of the version .xccurrentversion points at. */
@property (nonatomic, copy) NSString *currentVersionName;

/* Canvas geometry per entity name: {"positionX","positionY","width",
   "height"} string values, preserved through the <elements> section. */
@property (nonatomic, strong) NSMutableDictionary *entityLayouts;

- (NSArray *)versionNames;      /* sorted version file names */
- (NSArray *)sortedEntities;    /* model entities sorted by name */
- (void)noteModelChanged;

/* Xcode's Editor menu: Add Model Version duplicates the edited version
   under a fresh name (and starts editing it); Set Current Version moves
   the .xccurrentversion pointer. */
- (NSString *)addModelVersion;
- (BOOL)switchToVersion:(NSString *)name error:(NSError **)error;
- (void)makeEditedVersionCurrent;

/* Entity lifecycle.  Renames re-key the layout sidecar and refuse
   duplicates; removal and reparenting are structural surgery performed
   at the model layer (CDModelMutator, beside the compiler and
   serializer), so momc renormalizes relationships, configurations,
   fetch templates and subentity wiring in one step and a failed edit
   leaves the document unchanged. */
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

/* Configurations, edited through CDModelMutator (add, remove, rename,
   membership toggling) so the compiler renormalizes each change -
   NSManagedObjectModel has no mutation API for them. */
- (NSArray *)configurationNames;   /* sorted */
- (NSString *)addConfiguration;
- (BOOL)removeConfigurationNamed:(NSString *)name error:(NSError **)error;
- (BOOL)renameConfiguration:(NSString *)name to:(NSString *)newName error:(NSError **)error;
- (BOOL)setEntityNamed:(NSString *)entityName
       inConfiguration:(NSString *)configurationName
                member:(BOOL)member
                 error:(NSError **)error;

/* Serialize-and-recompile the edited model through momc's compiler:
   the same checks a build would run.  Warnings collected, first error
   reported. */
- (BOOL)validateModel:(NSError **)error warnings:(NSArray **)warnings;

/* Compile the saved document to a .momd next to it (momc in-process).
   The document must have been saved first. */
- (BOOL)compileToMomd:(NSError **)error momdPath:(NSString **)momdPath;

@end
