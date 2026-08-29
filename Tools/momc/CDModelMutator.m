/* Structural model surgery: serialize -> edit XML -> recompile.
   See CDModelMutator.h for the design.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "CDModelMutator.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"

@interface CDModelMutationResult ()
+ (instancetype)resultWithModel:(NSManagedObjectModel *)model
                    contentsXML:(NSString *)xml;
@end

@implementation CDModelMutationResult {
  NSManagedObjectModel *_model;
  NSString *_contentsXML;
}

+ (instancetype)resultWithModel:(NSManagedObjectModel *)model
                    contentsXML:(NSString *)xml
{
  CDModelMutationResult *result = [[self alloc] init];
  result->_model = model;
  result->_contentsXML = [xml copy];
  return result;
}

- (NSManagedObjectModel *)model { return _model; }
- (NSString *)contentsXML { return _contentsXML; }

@end

@implementation CDModelMutator

/* The generic core: serialize (with layout geometry so <elements>
   survives), parse, run the edit, recompile.  On any failure the
   caller's model is untouched. */
+ (CDModelMutationResult *)mutateModel:(NSManagedObjectModel *)model
                         entityLayouts:(NSDictionary *)layouts
                             withBlock:(void (^)(NSXMLElement *root))mutation
                                 error:(NSError **)error
{
  NSString *xml = [CDModelSerializer contentsXMLForModel:model
                                           entityLayouts:layouts
                                                   error:error];
  if (!xml) return nil;

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml
                                                        options:0
                                                          error:error];
  if (!doc) return nil;
  mutation([doc rootElement]);

  NSString *mutated = [doc XMLStringWithOptions:NSXMLNodePrettyPrint];
  NSManagedObjectModel *renormalized =
      [CDModelCompiler compileModelContentsXML:mutated error:error];
  if (!renormalized) return nil;

  return [CDModelMutationResult resultWithModel:renormalized contentsXML:mutated];
}

#pragma mark - Entities

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
             removingEntityNamed:(NSString *)doomed
                           error:(NSError **)error
{
  return [self mutateModel:model entityLayouts:layouts withBlock:^(NSXMLElement *root) {
    NSMutableArray *goners = [NSMutableArray array];
    for (NSXMLElement *el in [root elementsForName:@"entity"]) {
      NSString *name = [[el attributeForName:@"name"] stringValue];
      if ([name isEqualToString:doomed]) { [goners addObject:el]; continue; }
      if ([[[el attributeForName:@"parentEntity"] stringValue] isEqualToString:doomed])
        [el removeAttributeForName:@"parentEntity"];
      NSMutableArray *deadRels = [NSMutableArray array];
      for (NSXMLElement *rel in [el elementsForName:@"relationship"]) {
        if ([[[rel attributeForName:@"destinationEntity"] stringValue] isEqualToString:doomed])
          [deadRels addObject:rel];
        else if ([[[rel attributeForName:@"inverseEntity"] stringValue] isEqualToString:doomed]) {
          [rel removeAttributeForName:@"inverseName"];
          [rel removeAttributeForName:@"inverseEntity"];
        }
      }
      for (NSXMLElement *rel in deadRels)
        [el removeChildAtIndex:[[el children] indexOfObjectIdenticalTo:rel]];
    }
    for (NSXMLElement *el in [root elementsForName:@"configuration"]) {
      NSMutableArray *deadMembers = [NSMutableArray array];
      for (NSXMLElement *member in [el elementsForName:@"memberEntity"])
        if ([[[member attributeForName:@"name"] stringValue] isEqualToString:doomed])
          [deadMembers addObject:member];
      for (NSXMLElement *member in deadMembers)
        [el removeChildAtIndex:[[el children] indexOfObjectIdenticalTo:member]];
    }
    for (NSXMLElement *fetch in [root elementsForName:@"fetchRequest"])
      if ([[[fetch attributeForName:@"entity"] stringValue] isEqualToString:doomed])
        [goners addObject:fetch];
    for (NSXMLElement *wrap in [root elementsForName:@"elements"])
      for (NSXMLElement *el in [wrap elementsForName:@"element"])
        if ([[[el attributeForName:@"name"] stringValue] isEqualToString:doomed])
          [goners addObject:el];
    for (NSXMLElement *el in goners)
      [(NSXMLElement *)[el parent] removeChildAtIndex:
          [[[el parent] children] indexOfObjectIdenticalTo:el]];
  } error:error];
}

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
      settingParentOfEntityNamed:(NSString *)entityName
                              to:(NSString *)parentName
                           error:(NSError **)error
{
  return [self mutateModel:model entityLayouts:layouts withBlock:^(NSXMLElement *root) {
    for (NSXMLElement *el in [root elementsForName:@"entity"]) {
      if (![[[el attributeForName:@"name"] stringValue] isEqualToString:entityName])
        continue;
      [el removeAttributeForName:@"parentEntity"];
      if (parentName.length)
        [el addAttribute:[NSXMLNode attributeWithName:@"parentEntity"
                                          stringValue:parentName]];
    }
  } error:error];
}

#pragma mark - Configurations

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
        addingConfigurationNamed:(NSString *)name
                           error:(NSError **)error
{
  return [self mutateModel:model entityLayouts:layouts withBlock:^(NSXMLElement *root) {
    NSXMLElement *el = [NSXMLElement elementWithName:@"configuration"];
    [el addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:name]];
    /* Insert before <elements> to keep Xcode's section order. */
    NSArray *elements = [root elementsForName:@"elements"];
    if (elements.count) {
      NSUInteger idx = [[root children] indexOfObjectIdenticalTo:elements.firstObject];
      [root insertChild:el atIndex:idx];
    } else {
      [root addChild:el];
    }
  } error:error];
}

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
      removingConfigurationNamed:(NSString *)name
                           error:(NSError **)error
{
  return [self mutateModel:model entityLayouts:layouts withBlock:^(NSXMLElement *root) {
    NSMutableArray *dead = [NSMutableArray array];
    for (NSXMLElement *el in [root elementsForName:@"configuration"])
      if ([[[el attributeForName:@"name"] stringValue] isEqualToString:name])
        [dead addObject:el];
    for (NSXMLElement *el in dead)
      [root removeChildAtIndex:[[root children] indexOfObjectIdenticalTo:el]];
  } error:error];
}

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
      renamingConfigurationNamed:(NSString *)name
                              to:(NSString *)newName
                           error:(NSError **)error
{
  return [self mutateModel:model entityLayouts:layouts withBlock:^(NSXMLElement *root) {
    for (NSXMLElement *el in [root elementsForName:@"configuration"]) {
      if (![[[el attributeForName:@"name"] stringValue] isEqualToString:name]) continue;
      [el removeAttributeForName:@"name"];
      [el addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:newName]];
    }
  } error:error];
}

+ (CDModelMutationResult *)model:(NSManagedObjectModel *)model
                   entityLayouts:(NSDictionary *)layouts
              settingEntityNamed:(NSString *)entityName
                 inConfiguration:(NSString *)configurationName
                          member:(BOOL)member
                           error:(NSError **)error
{
  return [self mutateModel:model entityLayouts:layouts withBlock:^(NSXMLElement *root) {
    for (NSXMLElement *el in [root elementsForName:@"configuration"]) {
      if (![[[el attributeForName:@"name"] stringValue]
              isEqualToString:configurationName]) continue;
      NSXMLElement *existing = nil;
      for (NSXMLElement *m in [el elementsForName:@"memberEntity"])
        if ([[[m attributeForName:@"name"] stringValue] isEqualToString:entityName])
          existing = m;
      if (member && !existing) {
        NSXMLElement *m = [NSXMLElement elementWithName:@"memberEntity"];
        [m addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:entityName]];
        [el addChild:m];
      } else if (!member && existing) {
        [el removeChildAtIndex:[[el children] indexOfObjectIdenticalTo:existing]];
      }
    }
  } error:error];
}

@end
