/* ModelBuilder — what can be done with a model as a whole (see
   MBModelCommands.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBModelCommands.h"
#import "MBModelEditor.h"
#import "CDModelCompiler.h"
#import "CDCodeGenerator.h"

@implementation MBModelCommands

+ (BOOL)validateModelOf:(MBModelEditor *)modelEditor
               warnings:(NSArray **)warnings
                  error:(NSError **)error
{
  NSMutableArray *collected = [NSMutableArray array];
  [CDModelCompiler setWarningHandler:^(NSString *message) {
    [collected addObject:message];
  }];

  NSError *localError = nil;
  NSString *xml = [modelEditor contentsXML:&localError];
  NSManagedObjectModel *reparsed = nil;
  if (xml)
    reparsed = [CDModelCompiler compileModelContentsXML:xml error:&localError];

  [CDModelCompiler setWarningHandler:nil];
  if (warnings) *warnings = collected;
  if (!reparsed) {
    if (error) *error = localError;
    return NO;
  }
  return YES;
}

+ (BOOL)compileModelAtPath:(NSString *)sourcePath
                  momdPath:(NSString **)momdPath
                     error:(NSError **)error
{
  if (!sourcePath.length) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:7 userInfo:@{
        NSLocalizedDescriptionKey: @"Save the document before compiling."
      }];
    }
    return NO;
  }
  NSString *destination = [[sourcePath stringByDeletingPathExtension]
      stringByAppendingPathExtension:@"momd"];
  if (momdPath) *momdPath = destination;
  return [CDModelCompiler compileModelSourceAtPath:sourcePath
                                            toPath:destination
                                             error:error];
}

+ (NSArray *)entitiesToGenerateInModel:(NSManagedObjectModel *)model
                              selected:(NSEntityDescription *)selected
{
  if (selected != nil && selected.managedObjectClassName.length &&
      ![selected.managedObjectClassName isEqualToString:@"NSManagedObject"])
    return @[ selected ];
  NSArray *entities = [CDCodeGenerator generatableEntitiesInModel:model onlyMarked:YES];
  if (!entities.count)
    entities = [CDCodeGenerator generatableEntitiesInModel:model onlyMarked:NO];
  return entities;
}

+ (NSArray *)writeClassesForEntities:(NSArray *)entities
                         toDirectory:(NSString *)directory
                               error:(NSError **)error
{
  return [CDCodeGenerator writeSourcesForEntities:entities
                                      toDirectory:directory
                                            error:error];
}

@end
