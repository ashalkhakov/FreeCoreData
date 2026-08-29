/* Editing view-models for the ModelBuilder inspector.
   See MBEditors.h for the design.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBEditors.h"
#import "MBDocument.h"
#import "CDModelCompiler.h"

static NSString *MBUniquePropertyName(NSString *base, NSEntityDescription *entity)
{
  NSArray *names = entity.propertiesByName.allKeys;
  if (![names containsObject:base]) return base;
  NSUInteger counter = 2;
  NSString *candidate;
  do {
    candidate = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)counter];
    counter++;
  } while ([names containsObject:candidate]);
  return candidate;
}

static void MBReplaceProperty(NSEntityDescription *entity,
                              NSPropertyDescription *old,
                              NSPropertyDescription *replacement)
{
  NSMutableArray *properties = [entity.properties mutableCopy];
  NSUInteger idx = [properties indexOfObjectIdenticalTo:old];
  if (idx == NSNotFound) return;
  if (replacement) [properties replaceObjectAtIndex:idx withObject:replacement];
  else [properties removeObjectAtIndex:idx];
  entity.properties = properties;
}

@interface MBEditor () {
 @protected
  MBDocument *_document;
  NSError *_lastError;
}
- (void)noteEdited;
- (void)failWith:(NSString *)message;
@end

@implementation MBEditor

- (MBDocument *)document { return _document; }
- (NSError *)lastError { return _lastError; }

- (void)noteEdited
{
  [_document noteModelChanged];
}

- (void)failWith:(NSString *)message
{
  _lastError = [NSError errorWithDomain:@"MBEditors" code:1
      userInfo:@{ NSLocalizedDescriptionKey : message }];
}

@end

/* ---------------------------------------------------------------- */

@implementation MBEntityEditor {
  NSString *_name;
}

+ (instancetype)editorForEntityNamed:(NSString *)name document:(MBDocument *)document
{
  if (!document.model.entitiesByName[name]) return nil;
  MBEntityEditor *editor = [[self alloc] init];
  editor->_document = document;
  editor->_name = [name copy];
  return editor;
}

- (NSEntityDescription *)entity
{
  return _document.model.entitiesByName[_name];
}

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  if ([_document renameEntityNamed:_name to:name])
    _name = [name copy];
}

- (NSString *)className { return self.entity.managedObjectClassName; }

- (void)setClassName:(NSString *)className
{
  self.entity.managedObjectClassName = className.length ? className : @"NSManagedObject";
  [self noteEdited];
}

- (BOOL)isAbstract { return self.entity.isAbstract; }

- (void)setAbstract:(BOOL)abstract
{
  self.entity.abstract = abstract;
  [self noteEdited];
}

- (NSString *)parentName { return self.entity.superentity.name ?: @""; }

/* Reparenting is graph surgery: the document recompiles through momc,
   which REPLACES the model - this editor stays valid because it
   resolves by name. */
- (void)setParentName:(NSString *)parentName
{
  NSString *wanted = parentName ?: @"";
  if ([wanted isEqualToString:self.parentName]) return;
  NSError *error = nil;
  if (![_document setParentOfEntityNamed:_name to:wanted error:&error])
    _lastError = error;
}

- (NSString *)hashModifier { return [self.entity versionHashModifier] ?: @""; }

- (void)setHashModifier:(NSString *)hashModifier
{
  [self.entity setVersionHashModifier:hashModifier.length ? hashModifier : nil];
  [self noteEdited];
}

- (NSDictionary *)userInfo { return self.entity.userInfo; }

- (void)setUserInfo:(NSDictionary *)userInfo
{
  self.entity.userInfo = userInfo.count ? userInfo : nil;
  [self noteEdited];
}

- (NSArray *)constraintRows
{
  NSMutableArray *rows = [NSMutableArray array];
  for (NSArray *constraint in [self.entity uniquenessConstraints]) {
    NSMutableArray *names = [NSMutableArray array];
    for (id member in constraint)
      [names addObject:[member isKindOfClass:[NSPropertyDescription class]]
          ? [(NSPropertyDescription *)member name] : [member description]];
    [rows addObject:[names componentsJoinedByString:@", "]];
  }
  return rows;
}

- (void)setConstraintRows:(NSArray *)rows
{
  NSMutableArray *constraints = [NSMutableArray array];
  for (NSString *row in rows) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *piece in [row componentsSeparatedByString:@","]) {
      NSString *trimmed = [piece stringByTrimmingCharactersInSet:
          [NSCharacterSet whitespaceCharacterSet]];
      if (trimmed.length) [names addObject:trimmed];
    }
    if (names.count) [constraints addObject:names];
  }
  [self.entity setUniquenessConstraints:constraints.count ? constraints : nil];
  [self noteEdited];
}

- (NSString *)addAttribute
{
  NSEntityDescription *entity = self.entity;
  NSString *name = MBUniquePropertyName(@"attribute", entity);
  NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
  attribute.name = name;
  attribute.attributeType = NSStringAttributeType;
  attribute.optional = YES;
  entity.properties = [entity.properties arrayByAddingObject:attribute];
  [self noteEdited];
  return name;
}

- (void)removeAttributeNamed:(NSString *)name
{
  NSEntityDescription *entity = self.entity;
  NSAttributeDescription *attribute = entity.attributesByName[name];
  if (!attribute) return;
  MBReplaceProperty(entity, attribute, nil);
  [self noteEdited];
}

- (NSString *)addRelationship
{
  NSEntityDescription *entity = self.entity;
  NSString *name = MBUniquePropertyName(@"relationship", entity);
  NSRelationshipDescription *relationship = [[NSRelationshipDescription alloc] init];
  relationship.name = name;
  relationship.optional = YES;
  relationship.minCount = 0;
  relationship.maxCount = 1;
  relationship.deleteRule = NSNullifyDeleteRule;
  NSEntityDescription *destination = entity;
  for (NSEntityDescription *other in [_document sortedEntities])
    if (other != entity) { destination = other; break; }
  relationship.destinationEntity = destination;
  entity.properties = [entity.properties arrayByAddingObject:relationship];
  [self noteEdited];
  return name;
}

- (void)removeRelationshipNamed:(NSString *)name
{
  NSEntityDescription *entity = self.entity;
  NSRelationshipDescription *relationship = entity.relationshipsByName[name];
  if (!relationship) return;
  NSRelationshipDescription *inverse = relationship.inverseRelationship;
  if (inverse.inverseRelationship == relationship)
    inverse.inverseRelationship = nil;
  MBReplaceProperty(entity, relationship, nil);
  [self noteEdited];
}

@end

/* ---------------------------------------------------------------- */

@implementation MBAttributeEditor {
  NSEntityDescription *_entity;
  NSString *_name;
}

+ (instancetype)editorForAttributeNamed:(NSString *)name
                                 entity:(NSEntityDescription *)entity
                               document:(MBDocument *)document
{
  if (!entity.attributesByName[name]) return nil;
  MBAttributeEditor *editor = [[self alloc] init];
  editor->_document = document;
  editor->_entity = entity;
  editor->_name = [name copy];
  return editor;
}

- (NSAttributeDescription *)attribute
{
  return _entity.attributesByName[_name];
}

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  if (!name.length || [name isEqualToString:_name]) return;
  if (_entity.propertiesByName[name]) return;   /* duplicate */
  self.attribute.name = name;
  _name = [name copy];
  [self noteEdited];
}

- (NSString *)typeName
{
  return [CDModelCompiler nameForAttributeType:self.attribute.attributeType] ?: @"";
}

- (void)setTypeName:(NSString *)typeName
{
  NSInteger type = [CDModelCompiler attributeTypeNamed:typeName];
  NSAttributeDescription *attribute = self.attribute;
  if (type < 0 || (NSAttributeType)type == attribute.attributeType) return;
  attribute.attributeType = (NSAttributeType)type;
  attribute.defaultValue = nil;   /* the old default belongs to the old type */
  /* Transformer fields are left alone: Apple CoreData throws on nil,
     and the serializer ignores them for non-Transformable types. */
  [self noteEdited];
}

- (BOOL)isOptional { return self.attribute.isOptional; }
- (void)setOptional:(BOOL)optional { self.attribute.optional = optional; [self noteEdited]; }
- (BOOL)isTransient { return self.attribute.isTransient; }
- (void)setTransient:(BOOL)transient { self.attribute.transient = transient; [self noteEdited]; }

- (NSString *)hashModifier { return [self.attribute versionHashModifier] ?: @""; }

- (void)setHashModifier:(NSString *)hashModifier
{
  [self.attribute setVersionHashModifier:hashModifier.length ? hashModifier : nil];
  [self noteEdited];
}

- (NSDictionary *)userInfo { return self.attribute.userInfo; }

- (void)setUserInfo:(NSDictionary *)userInfo
{
  self.attribute.userInfo = userInfo.count ? userInfo : nil;
  [self noteEdited];
}

- (NSString *)defaultString
{
  NSAttributeDescription *attribute = self.attribute;
  id value = attribute.defaultValue;
  if (!value) return @"";
  switch (attribute.attributeType) {
    case NSBooleanAttributeType: return [value boolValue] ? @"YES" : @"NO";
    case NSUUIDAttributeType: return [value UUIDString];
    case NSURIAttributeType: return [value absoluteString];
    default: return [value description];
  }
}

- (void)setDefaultString:(NSString *)string
{
  NSAttributeDescription *attribute = self.attribute;
  if (!string.length) {
    attribute.defaultValue = nil;
    [self noteEdited];
    return;
  }
  switch (attribute.attributeType) {
    case NSStringAttributeType: attribute.defaultValue = string; break;
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
      attribute.defaultValue = @([string longLongValue]); break;
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
      attribute.defaultValue = @([string doubleValue]); break;
    case NSDecimalAttributeType:
      attribute.defaultValue = [NSDecimalNumber decimalNumberWithString:string]; break;
    case NSBooleanAttributeType:
      attribute.defaultValue = @([string isEqualToString:@"YES"] || [string isEqualToString:@"1"]);
      break;
    case NSUUIDAttributeType:
      attribute.defaultValue = [[NSUUID alloc] initWithUUIDString:string]; break;
    case NSURIAttributeType:
      attribute.defaultValue = [NSURL URLWithString:string]; break;
    default: return;   /* dates use defaultDate; binary/transformable have none */
  }
  [self noteEdited];
}

- (NSDate *)defaultDate
{
  NSAttributeDescription *attribute = self.attribute;
  return (attribute.attributeType == NSDateAttributeType) ? attribute.defaultValue : nil;
}

- (void)setDefaultDate:(NSDate *)date
{
  NSAttributeDescription *attribute = self.attribute;
  if (attribute.attributeType != NSDateAttributeType) return;
  attribute.defaultValue = date;
  [self noteEdited];
}

- (NSString *)transformerName { return [self.attribute valueTransformerName] ?: @""; }

- (void)setTransformerName:(NSString *)name
{
  [self.attribute setValueTransformerName:name ?: @""];   /* never nil: Apple throws */
  [self noteEdited];
}

- (NSString *)customClassName { return [self.attribute attributeValueClassName] ?: @""; }

- (void)setCustomClassName:(NSString *)name
{
  [self.attribute setAttributeValueClassName:name ?: @""];
  [self noteEdited];
}

- (BOOL)isDerived
{
  return [self.attribute isKindOfClass:[NSDerivedAttributeDescription class]];
}

- (NSString *)derivationString
{
  if (!self.isDerived) return @"";
  NSExpression *expression =
      [(NSDerivedAttributeDescription *)self.attribute derivationExpression];
  if (!expression) return @"";
  switch (expression.expressionType) {
    case NSKeyPathExpressionType: return expression.keyPath;
    case NSFunctionExpressionType: {
      NSString *name = expression.function;
      if ([name hasSuffix:@":"]) name = [name substringToIndex:name.length - 1];
      if (expression.arguments.count == 0) return [name stringByAppendingString:@"()"];
      NSExpression *arg = expression.arguments.firstObject;
      NSString *argString = (arg.expressionType == NSKeyPathExpressionType)
          ? arg.keyPath : [arg description];
      return [NSString stringWithFormat:@"%@:(%@)", name, argString];
    }
    default: return [expression description];
  }
}

/* Non-empty <-> empty flips replace the description object; the
   editor keeps resolving by name, so it survives the swap. */
- (void)setDerivationString:(NSString *)string
{
  NSAttributeDescription *attribute = self.attribute;
  BOOL derived = self.isDerived;
  if (!string.length) {
    if (!derived) return;
    NSAttributeDescription *plain = [[NSAttributeDescription alloc] init];
    plain.name = attribute.name;
    plain.attributeType = attribute.attributeType;
    plain.optional = attribute.isOptional;
    plain.transient = attribute.isTransient;
    plain.defaultValue = attribute.defaultValue;
    plain.userInfo = attribute.userInfo;
    MBReplaceProperty(_entity, attribute, plain);
    [self noteEdited];
    return;
  }
  NSError *error = nil;
  NSExpression *expression =
      [CDModelCompiler derivationExpressionFromString:string error:&error];
  if (!expression) {
    _lastError = error;
    return;
  }
  if (derived) {
    [(NSDerivedAttributeDescription *)attribute setDerivationExpression:expression];
    [self noteEdited];
    return;
  }
  NSDerivedAttributeDescription *replacement = [[NSDerivedAttributeDescription alloc] init];
  replacement.name = attribute.name;
  replacement.attributeType = attribute.attributeType;
  replacement.optional = attribute.isOptional;
  replacement.transient = attribute.isTransient;
  replacement.userInfo = attribute.userInfo;
  replacement.derivationExpression = expression;
  MBReplaceProperty(_entity, attribute, replacement);
  [self noteEdited];
}

@end

/* ---------------------------------------------------------------- */

@implementation MBRelationshipEditor {
  NSEntityDescription *_entity;
  NSString *_name;
}

+ (instancetype)editorForRelationshipNamed:(NSString *)name
                                    entity:(NSEntityDescription *)entity
                                  document:(MBDocument *)document
{
  if (!entity.relationshipsByName[name]) return nil;
  MBRelationshipEditor *editor = [[self alloc] init];
  editor->_document = document;
  editor->_entity = entity;
  editor->_name = [name copy];
  return editor;
}

- (NSRelationshipDescription *)relationship
{
  return _entity.relationshipsByName[_name];
}

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  if (!name.length || [name isEqualToString:_name]) return;
  if (_entity.propertiesByName[name]) return;   /* duplicate */
  self.relationship.name = name;
  _name = [name copy];
  [self noteEdited];
}

- (NSString *)destinationName { return self.relationship.destinationEntity.name ?: @""; }

- (void)setDestinationName:(NSString *)name
{
  NSRelationshipDescription *relationship = self.relationship;
  NSEntityDescription *destination = name.length
      ? _document.model.entitiesByName[name] : nil;
  if (destination == relationship.destinationEntity) return;
  NSRelationshipDescription *previousInverse = relationship.inverseRelationship;
  if (previousInverse.inverseRelationship == relationship)
    previousInverse.inverseRelationship = nil;
  relationship.inverseRelationship = nil;   /* the old inverse points elsewhere */
  relationship.destinationEntity = destination;
  [self noteEdited];
}

- (NSString *)inverseName { return self.relationship.inverseRelationship.name ?: @""; }

- (void)setInverseName:(NSString *)name
{
  NSRelationshipDescription *relationship = self.relationship;
  NSRelationshipDescription *previousInverse = relationship.inverseRelationship;
  if (!name.length || [name isEqualToString:@"(none)"]) {
    if (previousInverse.inverseRelationship == relationship)
      previousInverse.inverseRelationship = nil;
    relationship.inverseRelationship = nil;
    [self noteEdited];
    return;
  }
  NSRelationshipDescription *inverse =
      relationship.destinationEntity.relationshipsByName[name];
  if (!inverse || inverse == previousInverse) return;
  if (previousInverse.inverseRelationship == relationship)
    previousInverse.inverseRelationship = nil;
  relationship.inverseRelationship = inverse;
  inverse.inverseRelationship = relationship;
  [self noteEdited];
}

- (BOOL)isToMany { return self.relationship.isToMany; }

- (void)setToMany:(BOOL)toMany
{
  NSRelationshipDescription *relationship = self.relationship;
  if (toMany == relationship.isToMany) return;
  if (toMany) {
    relationship.maxCount = 0;
  } else {
    relationship.minCount = 0;
    relationship.maxCount = 1;
    relationship.ordered = NO;
  }
  [self noteEdited];
}

- (BOOL)isOrdered { return self.relationship.isToMany && self.relationship.isOrdered; }

- (void)setOrdered:(BOOL)ordered
{
  if (!self.relationship.isToMany) return;
  self.relationship.ordered = ordered;
  [self noteEdited];
}

- (NSInteger)minCount { return self.relationship.isToMany ? self.relationship.minCount : 0; }

- (void)setMinCount:(NSInteger)minCount
{
  if (!self.relationship.isToMany) return;
  self.relationship.minCount = MAX(0, minCount);
  [self noteEdited];
}

- (NSInteger)maxCount { return self.relationship.isToMany ? self.relationship.maxCount : 0; }

- (void)setMaxCount:(NSInteger)maxCount
{
  NSRelationshipDescription *relationship = self.relationship;
  if (!relationship.isToMany) return;
  relationship.maxCount = (maxCount == 1) ? 0 : MAX(0, maxCount);
  [self noteEdited];
}

- (NSString *)deleteRuleName
{
  NSArray *names = [CDModelCompiler deleteRuleNames];
  switch (self.relationship.deleteRule) {
    case NSCascadeDeleteRule:  return names[1];
    case NSDenyDeleteRule:     return names[2];
    case NSNoActionDeleteRule: return names[3];
    default:                   return names[0];
  }
}

- (void)setDeleteRuleName:(NSString *)name
{
  NSUInteger idx = [[CDModelCompiler deleteRuleNames] indexOfObject:name];
  switch (idx) {
    case 1: self.relationship.deleteRule = NSCascadeDeleteRule; break;
    case 2: self.relationship.deleteRule = NSDenyDeleteRule; break;
    case 3: self.relationship.deleteRule = NSNoActionDeleteRule; break;
    default: self.relationship.deleteRule = NSNullifyDeleteRule; break;
  }
  [self noteEdited];
}

- (BOOL)isOptional { return self.relationship.isOptional; }
- (void)setOptional:(BOOL)optional { self.relationship.optional = optional; [self noteEdited]; }
- (BOOL)isTransient { return self.relationship.isTransient; }
- (void)setTransient:(BOOL)transient { self.relationship.transient = transient; [self noteEdited]; }

- (NSString *)hashModifier { return [self.relationship versionHashModifier] ?: @""; }

- (void)setHashModifier:(NSString *)hashModifier
{
  [self.relationship setVersionHashModifier:hashModifier.length ? hashModifier : nil];
  [self noteEdited];
}

- (NSDictionary *)userInfo { return self.relationship.userInfo; }

- (void)setUserInfo:(NSDictionary *)userInfo
{
  self.relationship.userInfo = userInfo.count ? userInfo : nil;
  [self noteEdited];
}

@end

/* ---------------------------------------------------------------- */

@implementation MBFetchEditor {
  NSString *_name;
}

+ (instancetype)editorForFetchRequestNamed:(NSString *)name document:(MBDocument *)document
{
  if (![document.model fetchRequestTemplateForName:name]) return nil;
  MBFetchEditor *editor = [[self alloc] init];
  editor->_document = document;
  editor->_name = [name copy];
  return editor;
}

- (NSFetchRequest *)request
{
  return [_document.model fetchRequestTemplateForName:_name];
}

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  if ([_document renameFetchRequestNamed:_name to:name])
    _name = [name copy];
}

- (NSString *)entityName { return self.request.entity.name ?: @""; }

- (void)setEntityName:(NSString *)name
{
  NSEntityDescription *entity = name.length
      ? _document.model.entitiesByName[name] : nil;
  if (!entity || entity == self.request.entity) return;
  self.request.entity = entity;
  [self noteEdited];
}

- (NSUInteger)fetchLimit { return [self.request fetchLimit]; }

- (void)setFetchLimit:(NSUInteger)fetchLimit
{
  [self.request setFetchLimit:fetchLimit];
  [self noteEdited];
}

- (NSPredicate *)predicate { return self.request.predicate; }

- (void)setPredicate:(NSPredicate *)predicate
{
  self.request.predicate = predicate;
  [self noteEdited];
}

- (NSString *)predicateFormat
{
  return self.request.predicate ? [self.request.predicate predicateFormat] : @"";
}

- (void)setPredicateFormat:(NSString *)format
{
  if (!format.length) {
    self.request.predicate = nil;
    [self noteEdited];
    return;
  }
  @try {
    self.request.predicate = [NSPredicate predicateWithFormat:format];
    [self noteEdited];
  } @catch (NSException *exception) {
    [self failWith:[NSString stringWithFormat:@"Invalid predicate: %@", format]];
  }
}

@end
