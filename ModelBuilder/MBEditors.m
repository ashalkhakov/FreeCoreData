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

@interface MBEditor () {
 @protected
  MBDocument *_document;
  NSError *_lastError;
}
- (void)noteEdited;
- (void)failWith:(NSString *)message;
- (id)undoSubject;
- (void)didChange:(NSString *)key from:(id)old;
@end

static BOOL MBValuesEqual(id a, id b)
{
  return a == b || [a isEqual:b];
}

@implementation MBEditor

- (MBDocument *)document { return _document; }
- (NSError *)lastError { return _lastError; }

- (void)noteEdited
{
  [_document noteModelChanged];
}

/* The description object this editor edits: what an undo is recorded
   against, since it outlives a rename. */
- (id)undoSubject { return nil; }

/* After a setter has applied (or refused) a change: if `key` now reads
   differently from `old`, record the inverse and note the edit.  A
   refusal or a no-op records nothing. */
- (void)didChange:(NSString *)key from:(id)old
{
  id now = [self valueForKey:key];
  if (MBValuesEqual(old, now)) return;
  [_document registerInverseValue:old forKey:key ofSubject:[self undoSubject]];
  [self noteEdited];
}

+ (MBEditor *)editorForSubject:(id)subject document:(MBDocument *)document
{
  if ([subject isKindOfClass:[NSEntityDescription class]])
    return [MBEntityEditor editorForEntityNamed:[subject name] document:document];
  if ([subject isKindOfClass:[NSAttributeDescription class]])
    return [MBAttributeEditor editorForAttributeNamed:[subject name]
                                               entity:[subject entity]
                                             document:document];
  if ([subject isKindOfClass:[NSRelationshipDescription class]])
    return [MBRelationshipEditor editorForRelationshipNamed:[subject name]
                                                     entity:[subject entity]
                                                   document:document];
  if ([subject isKindOfClass:[NSFetchRequest class]]) {
    NSDictionary *templates = [document.model fetchRequestTemplatesByName];
    for (NSString *name in templates)
      if (templates[name] == subject)
        return [MBFetchEditor editorForFetchRequestNamed:name document:document];
  }
  return nil;
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

- (id)undoSubject { return self.entity; }

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  if ([_document renameEntityNamed:_name to:name])
    _name = [name copy];
}

- (NSString *)className { return self.entity.managedObjectClassName; }

- (void)setClassName:(NSString *)className
{
  id old = self.className;
  self.entity.managedObjectClassName = className.length ? className : @"NSManagedObject";
  [self didChange:@"className" from:old];
}

- (BOOL)isAbstract { return self.entity.isAbstract; }

- (void)setAbstract:(BOOL)abstract
{
  id old = [self valueForKey:@"abstract"];
  self.entity.abstract = abstract;
  [self didChange:@"abstract" from:old];
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
  id old = self.hashModifier;
  [self.entity setVersionHashModifier:hashModifier.length ? hashModifier : nil];
  [self didChange:@"hashModifier" from:old];
}

- (NSString *)renamingIdentifier { return [self.entity renamingIdentifier] ?: @""; }

/* Setting the identifier to the current name (or nothing) resets to
   the defaulted state, mirroring Apple's fallback-to-name getter. */
- (void)setRenamingIdentifier:(NSString *)value
{
  NSString *wanted = value ?: @"";
  BOOL defaulted = !wanted.length || [wanted isEqualToString:self.entity.name];
  id old = self.renamingIdentifier;
  [self.entity setRenamingIdentifier:defaulted ? nil : wanted];
  [self didChange:@"renamingIdentifier" from:old];
}

- (NSString *)codegenType
{
  return [CDModelCompiler entityCodeGenerationType:self.entity] ?: @"";
}

- (void)setCodegenType:(NSString *)value
{
  id old = self.codegenType;
  [CDModelCompiler setEntity:self.entity codeGenerationType:value];
  [self didChange:@"codegenType" from:old];
}

- (NSDictionary *)userInfo { return self.entity.userInfo; }

- (void)setUserInfo:(NSDictionary *)userInfo
{
  id old = self.userInfo;
  self.entity.userInfo = userInfo.count ? userInfo : nil;
  [self didChange:@"userInfo" from:old];
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
  id old = self.constraintRows;
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
  [self didChange:@"constraintRows" from:old];
}

- (NSString *)addAttribute
{
  NSEntityDescription *entity = self.entity;
  NSString *name = MBUniquePropertyName(@"attribute", entity);
  NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
  attribute.name = name;
  attribute.attributeType = NSStringAttributeType;
  attribute.optional = YES;
  [_document insertProperty:attribute intoEntity:entity atIndex:entity.properties.count];
  return name;
}

- (void)removeAttributeNamed:(NSString *)name
{
  NSEntityDescription *entity = self.entity;
  NSAttributeDescription *attribute = entity.attributesByName[name];
  if (!attribute) return;
  [_document removeProperty:attribute];
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
  [_document insertProperty:relationship intoEntity:entity atIndex:entity.properties.count];
  return name;
}

- (void)removeRelationshipNamed:(NSString *)name
{
  NSEntityDescription *entity = self.entity;
  NSRelationshipDescription *relationship = entity.relationshipsByName[name];
  if (!relationship) return;
  [_document removeProperty:relationship];   /* unwires the inverse's pointer back */
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

- (id)undoSubject { return self.attribute; }

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  if (!name.length || [name isEqualToString:_name]) return;
  if (_entity.propertiesByName[name]) return;   /* duplicate */
  NSString *old = _name;
  self.attribute.name = name;
  _name = [name copy];
  [self didChange:@"name" from:old];
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
  id oldType = self.typeName, oldDefault = self.defaultValueObject;
  [_document beginEdit:nil];   /* two inverses, one step */
  attribute.attributeType = (NSAttributeType)type;
  attribute.defaultValue = nil;   /* the old default belongs to the old type */
  /* Transformer fields are left alone: Apple CoreData throws on nil,
     and the serializer ignores them for non-Transformable types. */
  /* The default's inverse first: undo runs them in reverse, so the type
     is back before the default it belongs to. */
  [self didChange:@"defaultValueObject" from:oldDefault];
  [self didChange:@"typeName" from:oldType];
  [_document endEdit];
}

- (BOOL)isOptional { return self.attribute.isOptional; }
- (void)setOptional:(BOOL)optional
{
  id old = [self valueForKey:@"optional"];
  self.attribute.optional = optional;
  [self didChange:@"optional" from:old];
}
- (BOOL)isTransient { return self.attribute.isTransient; }
- (void)setTransient:(BOOL)transient
{
  id old = [self valueForKey:@"transient"];
  self.attribute.transient = transient;
  [self didChange:@"transient" from:old];
}

/* The default value as stored, for undo: lossless where -defaultString
   is a rendering of it. */
- (id)defaultValueObject { return self.attribute.defaultValue; }
- (void)setDefaultValueObject:(id)value
{
  id old = self.defaultValueObject;
  self.attribute.defaultValue = value;
  [self didChange:@"defaultValueObject" from:old];
}

- (NSString *)hashModifier { return [self.attribute versionHashModifier] ?: @""; }

- (void)setHashModifier:(NSString *)hashModifier
{
  id old = self.hashModifier;
  [self.attribute setVersionHashModifier:hashModifier.length ? hashModifier : nil];
  [self didChange:@"hashModifier" from:old];
}

- (NSString *)renamingIdentifier { return [self.attribute renamingIdentifier] ?: @""; }

- (void)setRenamingIdentifier:(NSString *)value
{
  NSString *wanted = value ?: @"";
  BOOL defaulted = !wanted.length || [wanted isEqualToString:_name];
  id old = self.renamingIdentifier;
  [self.attribute setRenamingIdentifier:defaulted ? nil : wanted];
  [self didChange:@"renamingIdentifier" from:old];
}

- (BOOL)scalarType
{
  return [CDModelCompiler attributeUsesScalarValueType:self.attribute];
}

- (void)setScalarType:(BOOL)scalarType
{
  id old = [self valueForKey:@"scalarType"];
  [CDModelCompiler setAttribute:self.attribute usesScalarValueType:scalarType];
  [self didChange:@"scalarType" from:old];
}

/* Validation plumbing: read the canonical info dictionary, mutate one
   key, and reapply - CDModelCompiler owns the predicate shapes. */
- (NSDictionary *)validationInfo
{
  return [CDModelCompiler validationInfoForAttribute:self.attribute];
}

- (void)setValidationValue:(id)value forKey:(NSString *)key
{
  NSMutableDictionary *info = [[self validationInfo] mutableCopy];
  if (value) info[key] = value;
  else [info removeObjectForKey:key];
  [self setValidationInfo:info];
}

/* The whole validation dictionary: what undo restores, one key or many. */
- (void)setValidationInfo:(NSDictionary *)info
{
  id old = [self validationInfo];
  [CDModelCompiler applyValidationInfo:info ?: @{} toAttribute:self.attribute];
  [self didChange:@"validationInfo" from:old];
}

- (NSString *)validationMin { return [self validationInfo][@"min"] ?: @""; }
- (void)setValidationMin:(NSString *)v { [self setValidationValue:v.length ? v : nil forKey:@"min"]; }
- (NSString *)validationMax { return [self validationInfo][@"max"] ?: @""; }
- (void)setValidationMax:(NSString *)v { [self setValidationValue:v.length ? v : nil forKey:@"max"]; }
- (NSString *)minLengthString { return [self validationInfo][@"minLength"] ?: @""; }
- (void)setMinLengthString:(NSString *)v { [self setValidationValue:v.length ? v : nil forKey:@"minLength"]; }
- (NSString *)maxLengthString { return [self validationInfo][@"maxLength"] ?: @""; }
- (void)setMaxLengthString:(NSString *)v { [self setValidationValue:v.length ? v : nil forKey:@"maxLength"]; }
- (NSString *)regexString { return [self validationInfo][@"regex"] ?: @""; }
- (void)setRegexString:(NSString *)v { [self setValidationValue:v.length ? v : nil forKey:@"regex"]; }
- (NSDate *)validationMinDate { return [self validationInfo][@"minDate"]; }
- (void)setValidationMinDate:(NSDate *)date { [self setValidationValue:date forKey:@"minDate"]; }
- (NSDate *)validationMaxDate { return [self validationInfo][@"maxDate"]; }
- (void)setValidationMaxDate:(NSDate *)date { [self setValidationValue:date forKey:@"maxDate"]; }

- (NSDictionary *)userInfo { return self.attribute.userInfo; }

- (void)setUserInfo:(NSDictionary *)userInfo
{
  id old = self.userInfo;
  self.attribute.userInfo = userInfo.count ? userInfo : nil;
  [self didChange:@"userInfo" from:old];
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
  id old = self.defaultValueObject;
  if (!string.length) {
    attribute.defaultValue = nil;
    [self didChange:@"defaultValueObject" from:old];
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
  [self didChange:@"defaultValueObject" from:old];
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
  id old = self.defaultValueObject;
  attribute.defaultValue = date;
  [self didChange:@"defaultValueObject" from:old];
}

- (NSString *)transformerName { return [self.attribute valueTransformerName] ?: @""; }

- (void)setTransformerName:(NSString *)name
{
  id old = self.transformerName;
  [self.attribute setValueTransformerName:name ?: @""];   /* never nil: Apple throws */
  [self didChange:@"transformerName" from:old];
}

- (NSString *)customClassName { return [self.attribute attributeValueClassName] ?: @""; }

- (void)setCustomClassName:(NSString *)name
{
  id old = self.customClassName;
  [self.attribute setAttributeValueClassName:name ?: @""];
  [self didChange:@"customClassName" from:old];
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
    [_document replaceProperty:attribute withProperty:plain];   /* undo puts this one back */
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
    id old = self.derivationString;
    [(NSDerivedAttributeDescription *)attribute setDerivationExpression:expression];
    [self didChange:@"derivationString" from:old];
    return;
  }
  NSDerivedAttributeDescription *replacement = [[NSDerivedAttributeDescription alloc] init];
  replacement.name = attribute.name;
  replacement.attributeType = attribute.attributeType;
  replacement.optional = attribute.isOptional;
  replacement.transient = attribute.isTransient;
  replacement.userInfo = attribute.userInfo;
  replacement.derivationExpression = expression;
  [_document replaceProperty:attribute withProperty:replacement];
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

- (id)undoSubject { return self.relationship; }

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  if (!name.length || [name isEqualToString:_name]) return;
  if (_entity.propertiesByName[name]) return;   /* duplicate */
  NSString *old = _name;
  self.relationship.name = name;
  _name = [name copy];
  [self didChange:@"name" from:old];
}

- (NSString *)destinationName { return self.relationship.destinationEntity.name ?: @""; }

- (void)setDestinationName:(NSString *)name
{
  NSRelationshipDescription *relationship = self.relationship;
  NSEntityDescription *destination = name.length
      ? _document.model.entitiesByName[name] : nil;
  if (destination == relationship.destinationEntity) return;
  id oldDestination = self.destinationName, oldInverse = self.inverseName;
  [_document beginEdit:nil];   /* two inverses, one step */
  NSRelationshipDescription *previousInverse = relationship.inverseRelationship;
  if (previousInverse.inverseRelationship == relationship)
    previousInverse.inverseRelationship = nil;
  relationship.inverseRelationship = nil;   /* the old inverse points elsewhere */
  relationship.destinationEntity = destination;
  /* The inverse's first: undo sets the destination back, then wires the
     inverse on it again. */
  [self didChange:@"inverseName" from:oldInverse];
  [self didChange:@"destinationName" from:oldDestination];
  [_document endEdit];
}

- (NSString *)inverseName { return self.relationship.inverseRelationship.name ?: @""; }

- (void)setInverseName:(NSString *)name
{
  NSRelationshipDescription *relationship = self.relationship;
  NSRelationshipDescription *previousInverse = relationship.inverseRelationship;
  id old = self.inverseName;
  if (!name.length || [name isEqualToString:@"(none)"]) {
    if (previousInverse.inverseRelationship == relationship)
      previousInverse.inverseRelationship = nil;
    relationship.inverseRelationship = nil;
    [self didChange:@"inverseName" from:old];
    return;
  }
  NSRelationshipDescription *inverse =
      relationship.destinationEntity.relationshipsByName[name];
  if (!inverse || inverse == previousInverse) return;
  if (previousInverse.inverseRelationship == relationship)
    previousInverse.inverseRelationship = nil;
  relationship.inverseRelationship = inverse;
  inverse.inverseRelationship = relationship;
  [self didChange:@"inverseName" from:old];
}

- (BOOL)isToMany { return self.relationship.isToMany; }

- (void)setToMany:(BOOL)toMany
{
  NSRelationshipDescription *relationship = self.relationship;
  if (toMany == relationship.isToMany) return;
  id oldToMany = [self valueForKey:@"toMany"];
  id oldMin = self.storedMinCount, oldMax = self.storedMaxCount, oldOrdered = self.storedOrdered;
  [_document beginEdit:nil];   /* several inverses, one step */
  if (toMany) {
    relationship.maxCount = 0;
  } else {
    relationship.minCount = 0;
    relationship.maxCount = 1;
    relationship.ordered = NO;
  }
  /* The counts' inverses first: undo turns to-many back, then restores
     them exactly as they were. */
  [self didChange:@"storedMinCount" from:oldMin];
  [self didChange:@"storedMaxCount" from:oldMax];
  [self didChange:@"storedOrdered" from:oldOrdered];
  [self didChange:@"toMany" from:oldToMany];
  [_document endEdit];
}

/* The counts and ordering as stored, whatever the relationship's shape:
   what undo restores when turning to-one resets them. */
- (NSNumber *)storedMinCount { return @(self.relationship.minCount); }
- (void)setStoredMinCount:(NSNumber *)value
{
  id old = self.storedMinCount;
  self.relationship.minCount = value.intValue;
  [self didChange:@"storedMinCount" from:old];
}
- (NSNumber *)storedMaxCount { return @(self.relationship.maxCount); }
- (void)setStoredMaxCount:(NSNumber *)value
{
  id old = self.storedMaxCount;
  self.relationship.maxCount = value.intValue;
  [self didChange:@"storedMaxCount" from:old];
}
- (NSNumber *)storedOrdered { return @(self.relationship.isOrdered); }
- (void)setStoredOrdered:(NSNumber *)value
{
  id old = self.storedOrdered;
  self.relationship.ordered = value.boolValue;
  [self didChange:@"storedOrdered" from:old];
}

- (BOOL)isOrdered { return self.relationship.isToMany && self.relationship.isOrdered; }

- (void)setOrdered:(BOOL)ordered
{
  if (!self.relationship.isToMany) return;
  id old = [self valueForKey:@"ordered"];
  self.relationship.ordered = ordered;
  [self didChange:@"ordered" from:old];
}

- (NSInteger)minCount { return self.relationship.isToMany ? self.relationship.minCount : 0; }

- (void)setMinCount:(NSInteger)minCount
{
  if (!self.relationship.isToMany) return;
  id old = [self valueForKey:@"minCount"];
  self.relationship.minCount = MAX(0, minCount);
  [self didChange:@"minCount" from:old];
}

- (NSInteger)maxCount { return self.relationship.isToMany ? self.relationship.maxCount : 0; }

- (void)setMaxCount:(NSInteger)maxCount
{
  NSRelationshipDescription *relationship = self.relationship;
  if (!relationship.isToMany) return;
  id old = [self valueForKey:@"maxCount"];
  relationship.maxCount = (maxCount == 1) ? 0 : MAX(0, maxCount);
  [self didChange:@"maxCount" from:old];
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
  id old = self.deleteRuleName;
  switch (idx) {
    case 1: self.relationship.deleteRule = NSCascadeDeleteRule; break;
    case 2: self.relationship.deleteRule = NSDenyDeleteRule; break;
    case 3: self.relationship.deleteRule = NSNoActionDeleteRule; break;
    default: self.relationship.deleteRule = NSNullifyDeleteRule; break;
  }
  [self didChange:@"deleteRuleName" from:old];
}

- (BOOL)isOptional { return self.relationship.isOptional; }
- (void)setOptional:(BOOL)optional
{
  id old = [self valueForKey:@"optional"];
  self.relationship.optional = optional;
  [self didChange:@"optional" from:old];
}
- (BOOL)isTransient { return self.relationship.isTransient; }
- (void)setTransient:(BOOL)transient
{
  id old = [self valueForKey:@"transient"];
  self.relationship.transient = transient;
  [self didChange:@"transient" from:old];
}

- (NSString *)hashModifier { return [self.relationship versionHashModifier] ?: @""; }

- (void)setHashModifier:(NSString *)hashModifier
{
  id old = self.hashModifier;
  [self.relationship setVersionHashModifier:hashModifier.length ? hashModifier : nil];
  [self didChange:@"hashModifier" from:old];
}

- (NSString *)renamingIdentifier { return [self.relationship renamingIdentifier] ?: @""; }

- (void)setRenamingIdentifier:(NSString *)value
{
  NSString *wanted = value ?: @"";
  BOOL defaulted = !wanted.length || [wanted isEqualToString:_name];
  id old = self.renamingIdentifier;
  [self.relationship setRenamingIdentifier:defaulted ? nil : wanted];
  [self didChange:@"renamingIdentifier" from:old];
}

- (NSDictionary *)userInfo { return self.relationship.userInfo; }

- (void)setUserInfo:(NSDictionary *)userInfo
{
  id old = self.userInfo;
  self.relationship.userInfo = userInfo.count ? userInfo : nil;
  [self didChange:@"userInfo" from:old];
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

- (id)undoSubject { return self.request; }

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
  id old = self.entityName;
  self.request.entity = entity;
  [self didChange:@"entityName" from:old];
}

- (NSUInteger)fetchLimit { return [self.request fetchLimit]; }

- (void)setFetchLimit:(NSUInteger)fetchLimit
{
  id old = [self valueForKey:@"fetchLimit"];
  [self.request setFetchLimit:fetchLimit];
  [self didChange:@"fetchLimit" from:old];
}

- (NSFetchRequestResultType)resultType { return [self.request resultType]; }

- (void)setResultType:(NSFetchRequestResultType)resultType
{
  id old = [self valueForKey:@"resultType"];
  [self.request setResultType:resultType];
  [self didChange:@"resultType" from:old];
}

- (NSUInteger)fetchBatchSize { return [self.request fetchBatchSize]; }

- (void)setFetchBatchSize:(NSUInteger)size
{
  id old = [self valueForKey:@"fetchBatchSize"];
  [self.request setFetchBatchSize:size];
  [self didChange:@"fetchBatchSize" from:old];
}

#define MB_FETCH_FLAG(Getter, Setter) \
- (BOOL)Getter { return [self.request Getter]; } \
- (void)Setter:(BOOL)value \
{ \
  id old = [self valueForKey:@#Getter]; \
  [self.request Setter:value]; \
  [self didChange:@#Getter from:old]; \
}

MB_FETCH_FLAG(includesSubentities, setIncludesSubentities)
MB_FETCH_FLAG(includesPropertyValues, setIncludesPropertyValues)
MB_FETCH_FLAG(returnsObjectsAsFaults, setReturnsObjectsAsFaults)
MB_FETCH_FLAG(includesPendingChanges, setIncludesPendingChanges)
MB_FETCH_FLAG(returnsDistinctResults, setReturnsDistinctResults)
#undef MB_FETCH_FLAG

- (NSPredicate *)predicate { return self.request.predicate; }

- (void)setPredicate:(NSPredicate *)predicate
{
  id old = self.predicate;
  self.request.predicate = predicate;
  [self didChange:@"predicate" from:old];
}

- (NSString *)predicateFormat
{
  return self.request.predicate ? [self.request.predicate predicateFormat] : @"";
}

- (void)setPredicateFormat:(NSString *)format
{
  if (!format.length) {
    self.predicate = nil;
    return;
  }
  @try {
    self.predicate = [NSPredicate predicateWithFormat:format];
  } @catch (NSException *exception) {
    [self failWith:[NSString stringWithFormat:@"Invalid predicate: %@", format]];
  }
}

@end
