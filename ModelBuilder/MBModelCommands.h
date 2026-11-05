/* ModelBuilder — what can be done with a model as a whole: checked as a
   build would check it, compiled to a .momd, its entities' classes
   written.  Nothing here touches a view; the window controller asks and
   shows the answers.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class MBModelEditor;

@interface MBModelCommands : NSObject

/* The version serialized and recompiled through momc's compiler: the
   checks a build would run.  Warnings collected, the first error
   reported. */
+ (BOOL)validateModelOf:(MBModelEditor *)modelEditor
               warnings:(NSArray **)warnings
                  error:(NSError **)error;

/* A saved .xcdatamodeld (or .xcdatamodel) compiled to a .momd beside it. */
+ (BOOL)compileModelAtPath:(NSString *)sourcePath
                  momdPath:(NSString **)momdPath
                     error:(NSError **)error;

/* The entities to write classes for: the one given, if it has a class of
   its own; otherwise those marked Class Definition or Category/Extension,
   or failing those every entity with a class of its own. */
+ (NSArray *)entitiesToGenerateInModel:(NSManagedObjectModel *)model
                              selected:(NSEntityDescription *)selected;

/* Their class files, into a directory; the paths written, or nil. */
+ (NSArray *)writeClassesForEntities:(NSArray *)entities
                         toDirectory:(NSString *)directory
                               error:(NSError **)error;

@end
