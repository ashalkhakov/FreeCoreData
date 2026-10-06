/* ModelBuilder mapping document — an .xcmappingmodel wrapper edited
   through FreeCoreData's own classes: CDMappingCompiler reads the source
   into an NSMappingModel, the editor mutates the mapping objects
   directly, and CDMappingSerializer writes the source back.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@interface MBMappingDocument : NSDocument

/* The mapping being edited, and the two models it maps between. */
@property (nonatomic, strong) NSMappingModel *mappingModel;
@property (nonatomic, strong) NSManagedObjectModel *sourceModel;
@property (nonatomic, strong) NSManagedObjectModel *destinationModel;

/* As the source file records them, which is how Xcode's editor finds them
   too: kept so a file written here says what it said. */
@property (nonatomic, copy) NSString *sourceModelPath;
@property (nonatomic, copy) NSString *destinationModelPath;

- (NSArray *)entityMappings;

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

/* The property mappings of an entity mapping, in the order they are shown:
   every property of the destination entity, whether or not anything fills
   it yet. */
- (NSArray *)attributeMappingsOfEntityMapping:(NSEntityMapping *)mapping;
- (NSArray *)relationshipMappingsOfEntityMapping:(NSEntityMapping *)mapping;

/* Undo, as in MBDocument: an edit is everything between -beginEdit: and
   the matching -endEdit, and each change records its inverse. */
- (void)beginEdit:(NSString *)actionName;
- (void)endEdit;
- (void)setValue:(id)value forKey:(NSString *)key ofMappingObject:(id)subject;
- (void)noteMappingChanged;

@end
