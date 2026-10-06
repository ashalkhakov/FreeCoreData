/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/Foundation.h>

@class NSMappingModel, NSManagedObjectModel, NSEntityMapping, NSEntityDescription;

extern NSString * const CDMappingCompilerErrorDomain;

extern NSString * const CDMappingSourceModelKey;
extern NSString * const CDMappingDestinationModelKey;
extern NSString * const CDMappingSourceModelPathKey;
extern NSString * const CDMappingDestinationModelPathKey;

/* Compiles a mapping model's source - an .xcmappingmodel, which is a
   directory holding an xcmapping.xml - into the .cdm a migration loads,
   the way Xcode's mapc does.

   The source says what the author chose: which entity maps to which, the
   predicate that narrows the objects a mapping applies to, and any value
   expression written by hand.  Everything else is worked out here from the
   two models the source carries copies of - the kind of each mapping, the
   version hashes, and the expressions no one wrote by hand. */
@interface CDMappingCompiler : NSObject

+ (NSMappingModel *)mappingModelAtPath:(NSString *)path error:(NSError **)error;

/* The same, for a caller that already has the two models - ModelBuilder
   while editing, a test with them loaded - and so needs none of the path
   resolving the other does. */
+ (NSMappingModel *)mappingModelAtPath:(NSString *)path
                           sourceModel:(NSManagedObjectModel *)sourceModel
                      destinationModel:(NSManagedObjectModel *)destinationModel
                                 error:(NSError **)error;
+ (BOOL)compileMappingModelAtPath:(NSString *)path toPath:(NSString *)destination error:(NSError **)error;

/* The two models a mapping model's source names, and the paths it names
   them by: what an editor needs to show which entities and properties
   there are to map.  Keys: CDMappingSourceModelKey, CDMappingDestination
   ModelKey, CDMappingSourceModelPathKey, CDMappingDestinationModelPathKey. */
+ (NSDictionary *)modelsForMappingModelAtPath:(NSString *)path error:(NSError **)error;

/* Warnings are reported through this, as momc does it. */
+ (void)setWarningHandler:(void (^)(NSString *message))handler;

/* The expression that says which objects a mapping applies to, built from
   an entity name and the predicate an author wrote - what an editor puts
   back when the predicate is edited. */
+ (NSExpression *)sourceExpressionForEntityNamed:(NSString *)entityName predicate:(NSString *)predicateString;

/* The expression that fills a relationship: the destination objects the
   named entity mapping made of whatever the source object reaches through
   the key path - which is what Xcode's "Auto Generate Value Expression"
   writes, from the key path and mapping name its inspector shows. */
+ (NSExpression *)valueExpressionForRelationshipKeyPath:(NSString *)keyPath throughMapping:(NSString *)mappingName;

/* A mapping from one entity to another (either may be nil, for an entity
   added or removed), of the type that follows from the two, fetching
   every object of the source entity.  It has no property mappings. */
+ (NSEntityMapping *)entityMappingFromEntity:(NSEntityDescription *)source
                                    toEntity:(NSEntityDescription *)destination;

/* What Xcode's New Mapping Model starts an author from: a mapping for
   each destination entity, from the source entity of the same name (or
   the one its renaming identifier names), with a row for each of its
   properties - empty, for the compiler to fill from the name, unless a
   renaming identifier says the property was called something else.  An
   entity the destination model dropped has no mapping, as in Xcode: its
   objects are simply not carried over. */
+ (NSMappingModel *)startingMappingModelFromSourceModel:(NSManagedObjectModel *)sourceModel
                                     toDestinationModel:(NSManagedObjectModel *)destinationModel;

/* The name an entity mapping goes by when the file does not give one. */
+ (NSString *)defaultNameForEntityMappingFromEntityNamed:(NSString *)sourceName
                                           toEntityNamed:(NSString *)destinationName;

@end
