/* Structural model surgery at the model layer, beside the compiler
   and serializer that define the schema.  Some edits ripple through
   the whole graph - deleting an entity touches relationships,
   configurations, fetch templates and subentity wiring; reparenting
   has no description-class API at all (subentities cannot be
   detached).  Each operation here serializes the model to Xcode's
   contents XML, performs the edit there, and recompiles through
   CDModelCompiler, so momc renormalizes everything in one step and an
   invalid edit fails with the compiler's error, leaving the inputs
   untouched.

   Configurations are XML-only state on this API for the same reason:
   NSManagedObjectModel has no mutation API for them.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

/* A successful mutation: the renormalized model, and the contents XML
   it was compiled from (for callers that track XML-side state such as
   entity layout geometry). */
@interface CDModelMutationResult : NSObject
@property (nonatomic, strong, readonly) NSManagedObjectModel *model;
@property (nonatomic, copy, readonly) NSString *contentsXML;
@end

@interface CDModelMutator : NSObject

/* Entities */
+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
             removingEntityNamed:(NSString *)name
                           error:(NSError **)error;

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
      settingParentOfEntityNamed:(NSString *)entityName
                              to:(NSString *)parentName   /* empty detaches */
                           error:(NSError **)error;

/* Configurations */
+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
        addingConfigurationNamed:(NSString *)name
                           error:(NSError **)error;

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
      removingConfigurationNamed:(NSString *)name
                           error:(NSError **)error;

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
      renamingConfigurationNamed:(NSString *)name
                              to:(NSString *)newName
                           error:(NSError **)error;

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
              settingEntityNamed:(NSString *)entityName
                 inConfiguration:(NSString *)configurationName
                          member:(BOOL)member
                           error:(NSError **)error;

@end
