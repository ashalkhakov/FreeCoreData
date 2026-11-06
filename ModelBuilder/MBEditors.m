/* Editing view-models for the ModelBuilder inspector.
   See MBEditors.h for the design.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBEditors.h"
#import "MBModelEditor.h"
#import "CDModelCompiler.h"
#import "CDModelMutator.h"
#import <objc/runtime.h>

NSString *const MBEditorErrorDomain = @"MBEditors";

static NSString *const MBNoneTitle = @"(none)";

void MBReloadProperties(NSObject *object, Class root)
{
  NSMutableArray *keys = [NSMutableArray array];
  for (Class cls = [object class]; cls && cls != root; cls = class_getSuperclass(cls)) {
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &count);
    for (unsigned int i = 0; i < count; i++)
      [keys addObject:@(property_getName(properties[i]))];
    free(properties);
  }
  for (NSString *key in keys) [object willChangeValueForKey:key];
  for (NSString *key in [keys reverseObjectEnumerator]) [object didChangeValueForKey:key];
}

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
  MBModelEditor *_modelEditor;
  NSError *_lastError;
}
- (void)noteEdited;
- (void)failWith:(NSString *)message;
- (id)undoSubject;
- (NSString *)editActionName;
- (void)didChange:(NSString *)key from:(id)old;
@end

static BOOL MBValuesEqual(id a, id b)
{
  return a == b || [a isEqual:b];
}

/* A validation's refusal: NO, and why. */
static BOOL MBRefuse(NSError **error, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);
static BOOL MBRefuse(NSError **error, NSString *format, ...)
{
  if (error) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    *error = [NSError errorWithDomain:MBEditorErrorDomain code:2
                             userInfo:@{ NSLocalizedDescriptionKey : message }];
  }
  return NO;
}

static NSString *MBTrimmed(id value)
{
  return [[value description] ?: @"" stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/* A name an editor's object can be given: not empty, and no other's in
   `taken` (the old name aside). */
static BOOL MBValidateName(id *value, NSString *old, NSArray *taken, NSString *what, NSError **error)
{
  NSString *name = MBTrimmed(*value);
  if (!name.length)
    return MBRefuse(error, @"A %@ needs a name.", what);
  if (![name isEqualToString:old] && [taken containsObject:name])
    return MBRefuse(error, @"There is a %@ named \u201c%@\u201d already.", what, name);
  *value = name;
  return YES;
}

/* None, or a whole number from `least` to `most` (a formatted field's
   NSNumber, or its text). */
static BOOL MBValidateWholeNumber(id *value, long long least, long long most, NSString *what, NSError **error)
{
  id given = *value;
  if (given == nil || ([given isKindOfClass:[NSString class]] && !MBTrimmed(given).length)) {
    *value = nil;
    return YES;
  }
  NSString *string = MBTrimmed(given);
  NSScanner *scanner = [NSScanner scannerWithString:string];
  long long number;
  if (![scanner scanLongLong:&number] || !scanner.isAtEnd || number < least || number > most)
    return MBRefuse(error, @"The %@ must be a whole number from %lld to %lld.", what, least, most);
  *value = @(number);
  return YES;
}

/* None, or a number. */
static BOOL MBValidateNumber(id *value, NSString *what, NSError **error)
{
  id given = *value;
  if (given == nil || [given isKindOfClass:[NSNumber class]]) return YES;
  NSString *string = MBTrimmed(given);
  if (!string.length) {
    *value = nil;
    return YES;
  }
  NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:string];
  if ([number isEqual:[NSDecimalNumber notANumber]])
    return MBRefuse(error, @"The %@ must be a number.", what);
  *value = number;
  return YES;
}

/* A number's text, for the string forms the model keeps; empty for none. */
static NSString *MBNumberString(id number)
{
  return number ? [number description] : @"";
}

/* Empty, or a predicate's format. */
static BOOL MBValidatePredicate(id *value, NSError **error)
{
  NSString *format = MBTrimmed(*value);
  if (format.length) {
    @try {
      [NSPredicate predicateWithFormat:format];
    } @catch (NSException *exception) {
      return MBRefuse(error, @"\u201c%@\u201d is not a predicate: %@", format, exception.reason);
    }
  }
  *value = format;
  return YES;
}

@implementation MBEditor

- (MBModelEditor *)modelEditor { return _modelEditor; }
- (NSError *)lastError { return _lastError; }

- (BOOL)editsSameAs:(MBEditor *)editor
{
  return [editor class] == [self class] && editor->_modelEditor == _modelEditor;
}

- (void)reload
{
  MBReloadProperties(self, [MBEditor class]);
}

- (void)noteEdited
{
  [_modelEditor noteModelChanged];
}

/* The description object this editor edits: what an undo is recorded
   against, since it outlives a rename. */
- (id)undoSubject { return nil; }

/* What an undo step of a change made through it is called. */
- (NSString *)editActionName { return nil; }

/* After a setter has applied (or refused) a change: if `key` now reads
   differently from `old`, record the inverse and note the edit, in an
   edit of its own unless one is open.  A refusal or a no-op records
   nothing. */
- (void)didChange:(NSString *)key from:(id)old
{
  id now = [self valueForKey:key];
  if (MBValuesEqual(old, now)) return;
  [_modelEditor beginEdit:[self editActionName]];
  [_modelEditor registerInverseValue:old forKey:key ofSubject:[self undoSubject]];
  [self noteEdited];
  [_modelEditor endEdit];
}

+ (MBEditor *)editorForSubject:(id)subject modelEditor:(MBModelEditor *)modelEditor
{
  /* The editor's model, whichever object it is now: graph surgery
     replaces it. */
  if ([subject isKindOfClass:[NSManagedObjectModel class]])
    return [MBVersionEditor editorForModelEditor:modelEditor];
  if ([subject isKindOfClass:[NSEntityDescription class]])
    return [MBEntityEditor editorForEntityNamed:[subject name] modelEditor:modelEditor];
  if ([subject isKindOfClass:[NSAttributeDescription class]])
    return [MBAttributeEditor editorForAttributeNamed:[subject name]
                                               entity:[subject entity]
                                             modelEditor:modelEditor];
  if ([subject isKindOfClass:[NSRelationshipDescription class]])
    return [MBRelationshipEditor editorForRelationshipNamed:[subject name]
                                                     entity:[subject entity]
                                                   modelEditor:modelEditor];
  if ([subject isKindOfClass:[NSFetchRequest class]]) {
    NSDictionary *templates = [modelEditor.model fetchRequestTemplatesByName];
    for (NSString *name in templates)
      if (templates[name] == subject)
        return [MBFetchEditor editorForFetchRequestNamed:name modelEditor:modelEditor];
  }
  return nil;
}

- (void)failWith:(NSString *)message
{
  _lastError = [NSError errorWithDomain:MBEditorErrorDomain code:1
      userInfo:@{ NSLocalizedDescriptionKey : message }];
}

@end

/* ---------------------------------------------------------------- */

@implementation MBVersionEditor

+ (instancetype)editorForModelEditor:(MBModelEditor *)modelEditor
{
  if (!modelEditor.model) return nil;
  MBVersionEditor *editor = [[self alloc] init];
  editor->_modelEditor = modelEditor;
  return editor;
}

- (id)undoSubject { return _modelEditor.model; }
- (NSString *)editActionName { return @"Edit Model Identifier"; }

/* One identifier per version, as an .xcdatamodel holds one; with several
   (set in code), the first by name, as the serializer writes. */
- (NSString *)versionIdentifier
{
  NSArray *identifiers = [[_modelEditor.model.versionIdentifiers allObjects]
      sortedArrayUsingSelector:@selector(compare:)];
  id first = identifiers.firstObject;
  return [first isKindOfClass:[NSString class]] ? first : ([first description] ?: @"");
}

- (void)setVersionIdentifier:(NSString *)versionIdentifier
{
  NSString *wanted = [versionIdentifier stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
  id old = self.versionIdentifier;
  _modelEditor.model.versionIdentifiers = wanted.length ? [NSSet setWithObject:wanted] : [NSSet set];
  [self didChange:@"versionIdentifier" from:old];
}

@end

/* ---------------------------------------------------------------- */

@implementation MBEntityEditor {
  NSString *_name;
}

+ (instancetype)editorForEntityNamed:(NSString *)name modelEditor:(MBModelEditor *)modelEditor
{
  if (!modelEditor.model.entitiesByName[name]) return nil;
  MBEntityEditor *editor = [[self alloc] init];
  editor->_modelEditor = modelEditor;
  editor->_name = [name copy];
  return editor;
}

- (NSEntityDescription *)entity
{
  return _modelEditor.model.entitiesByName[_name];
}

- (id)undoSubject { return self.entity; }
- (NSString *)editActionName { return @"Edit Entity"; }

- (BOOL)editsSameAs:(MBEditor *)editor
{
  return [super editsSameAs:editor] && [((MBEntityEditor *)editor)->_name isEqualToString:_name];
}

- (NSString *)name { return _name; }

/* The new name is the editor's before the selection follows it. */
- (void)setName:(NSString *)name
{
  NSString *old = _name;
  _name = [name copy];
  if (![_modelEditor renameEntityNamed:old to:name])
    _name = old;
}

- (BOOL)validateName:(id *)value error:(NSError **)error
{
  return MBValidateName(value, _name, [_modelEditor.model.entitiesByName allKeys], @"entity", error);
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

/* Reparenting is graph surgery: the model editor recompiles through momc,
   which REPLACES the model - this editor stays valid because it
   resolves by name. */
- (void)setParentName:(NSString *)parentName
{
  NSString *wanted = parentName ?: @"";
  if ([wanted isEqualToString:self.parentName]) return;
  NSError *error = nil;
  if (![_modelEditor setParentOfEntityNamed:_name to:wanted error:&error])
    _lastError = error;
}

- (NSArray *)parentTitles
{
  NSMutableArray *titles = [NSMutableArray arrayWithObject:MBNoneTitle];
  for (NSEntityDescription *entity in [_modelEditor sortedEntities])
    if (![entity.name isEqualToString:_name]) [titles addObject:entity.name ?: @""];
  return titles;
}

- (NSString *)parentTitle
{
  NSString *parent = self.parentName;
  return parent.length ? parent : MBNoneTitle;
}

- (void)setParentTitle:(NSString *)title
{
  self.parentName = [title isEqualToString:MBNoneTitle] ? @"" : title;
}

/* A parent beneath the entity is refused; any other is tried on the
   model as it is, and kept only when the reparenting works (a property
   clash with the new parent's, say, refuses). */
- (BOOL)validateParentTitle:(id *)value error:(NSError **)error
{
  NSString *parent = [*value isEqualToString:MBNoneTitle] ? @"" : (*value ?: @"");
  if ([parent isEqualToString:self.parentName]) return YES;
  for (NSEntityDescription *above = _modelEditor.model.entitiesByName[parent]; above; above = above.superentity)
    if ([above.name isEqualToString:_name])
      return MBRefuse(error, @"%@ cannot have %@ as its parent: %@ is beneath it.", _name, parent, parent);
  NSError *failure = nil;
  if (![CDModelMutator model:_modelEditor.model entityLayouts:_modelEditor.entityLayouts
          settingParentOfEntityNamed:_name to:parent error:&failure])
    return MBRefuse(error, @"%@ cannot have %@ as its parent: %@", _name,
                    parent.length ? parent : @"no entity", failure.localizedDescription ?: @"");
  return YES;
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

- (NSInteger)codegenIndex
{
  NSString *codegen = self.codegenType;
  if ([codegen isEqualToString:@"class"]) return 1;
  if ([codegen isEqualToString:@"category"]) return 2;
  return 0;
}

- (void)setCodegenIndex:(NSInteger)index
{
  self.codegenType = index == 1 ? @"class" : index == 2 ? @"category" : @"";
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

- (NSArray *)fetchIndexRows
{
  NSMutableArray *rows = [NSMutableArray array];
  for (NSFetchIndexDescription *index in [self.entity indexes]) {
    NSMutableArray *elements = [NSMutableArray array];
    for (NSFetchIndexElementDescription *element in index.elements) {
      NSMutableDictionary *row = [NSMutableDictionary dictionary];
      NSPropertyDescription *property = element.property;
      if ([property isKindOfClass:[NSExpressionDescription class]]) row[@"expression"] = property;
      else row[@"property"] = element.propertyName ?: @"";
      if (element.collationType == NSFetchIndexElementTypeRTree) row[@"rtree"] = @YES;
      if (!element.isAscending) row[@"ascending"] = @NO;
      [elements addObject:row];
    }
    NSMutableDictionary *row = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        index.name ?: @"", @"name", elements, @"elements", nil];
    if (index.partialIndexPredicate) row[@"predicate"] = index.partialIndexPredicate.predicateFormat;
    [rows addObject:row];
  }
  return rows;
}

- (void)setFetchIndexRows:(NSArray *)rows
{
  id old = self.fetchIndexRows;
  NSEntityDescription *entity = self.entity;
  NSMutableArray *indexes = [NSMutableArray array];

  for (NSDictionary *row in rows) {
    NSMutableArray *elements = [NSMutableArray array];
    for (NSDictionary *item in row[@"elements"]) {
      NSPropertyDescription *property = item[@"expression"] ?: entity.propertiesByName[item[@"property"]];
      if (!property) continue;   /* a property since removed */
      NSFetchIndexElementDescription *element = nil;
      @try {
        element = [[NSFetchIndexElementDescription alloc]
            initWithProperty:property
               collationType:[item[@"rtree"] boolValue] ? NSFetchIndexElementTypeRTree : NSFetchIndexElementTypeBinary];
      } @catch (NSException *exception) {
        [self failWith:[NSString stringWithFormat:@"%@: %@", row[@"name"], exception.reason]];
        return;
      }
      element.ascending = item[@"ascending"] ? [item[@"ascending"] boolValue] : YES;
      [elements addObject:element];
    }
    NSFetchIndexDescription *index = nil;
    @try {
      index = [[NSFetchIndexDescription alloc] initWithName:row[@"name"] elements:elements];
    } @catch (NSException *exception) {
      [self failWith:[NSString stringWithFormat:@"%@: %@", row[@"name"], exception.reason]];
      return;
    }
    NSString *format = row[@"predicate"];
    if (format.length) {
      @try {
        index.partialIndexPredicate = [NSPredicate predicateWithFormat:format];
      } @catch (NSException *exception) {
        [self failWith:[NSString stringWithFormat:@"%@ is not a predicate: %@", format, exception.reason]];
        return;
      }
    }
    [indexes addObject:index];
  }
  /* Apple's CoreData refuses a name the entity has already - the same
     index's included - so the old ones go first. */
  [entity setIndexes:@[]];
  [entity setIndexes:indexes];
  [self didChange:@"fetchIndexRows" from:old];
}

/* A new index, named like Xcode's, on the entity's first attribute. */
- (NSString *)addFetchIndex
{
  NSMutableArray *rows = [self.fetchIndexRows mutableCopy];
  NSString *name = @"index";
  NSArray *taken = [rows valueForKey:@"name"];
  for (NSUInteger n = 2; [taken containsObject:name]; n++)
    name = [NSString stringWithFormat:@"index%lu", (unsigned long)n];
  NSString *first = [[[self.entity.attributesByName allKeys] sortedArrayUsingSelector:@selector(compare:)] firstObject];
  NSArray *elements = first ? @[ @{ @"property" : first } ] : @[];
  [rows addObject:@{ @"name" : name, @"elements" : elements }];
  self.fetchIndexRows = rows;
  return name;
}

- (void)removeFetchIndexNamed:(NSString *)name
{
  NSMutableArray *rows = [NSMutableArray array];
  for (NSDictionary *row in self.fetchIndexRows)
    if (![row[@"name"] isEqualToString:name]) [rows addObject:row];
  self.fetchIndexRows = rows;
}

/* Before a property goes: out of every index that names it, and an index
   left with nothing goes with it. */
- (void)removeFromFetchIndexesPropertyNamed:(NSString *)name
{
  NSMutableArray *rows = [NSMutableArray array];
  BOOL changed = NO;
  for (NSDictionary *row in self.fetchIndexRows) {
    NSMutableArray *elements = [NSMutableArray array];
    for (NSDictionary *item in row[@"elements"])
      if ([item[@"property"] isEqualToString:name]) changed = YES;
      else [elements addObject:item];
    if (elements.count == 0 && [row[@"elements"] count] > 0) continue;
    NSMutableDictionary *kept = [row mutableCopy];
    kept[@"elements"] = elements;
    [rows addObject:kept];
  }
  if (changed) self.fetchIndexRows = rows;
}

- (NSString *)addAttribute
{
  NSEntityDescription *entity = self.entity;
  NSString *name = MBUniquePropertyName(@"attribute", entity);
  NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
  attribute.name = name;
  attribute.attributeType = NSStringAttributeType;
  attribute.optional = YES;
  [_modelEditor insertProperty:attribute intoEntity:entity atIndex:[CDModelCompiler declaredPropertiesOfEntity:entity].count];
  return name;
}

- (void)removeAttributeNamed:(NSString *)name
{
  NSEntityDescription *entity = self.entity;
  NSAttributeDescription *attribute = entity.attributesByName[name];
  if (!attribute) return;
  [_modelEditor beginEdit:nil];
  [self removeFromFetchIndexesPropertyNamed:name];
  [_modelEditor removeProperty:attribute];
  [_modelEditor endEdit];
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
  for (NSEntityDescription *other in [_modelEditor sortedEntities])
    if (other != entity) { destination = other; break; }
  relationship.destinationEntity = destination;
  [_modelEditor insertProperty:relationship intoEntity:entity atIndex:[CDModelCompiler declaredPropertiesOfEntity:entity].count];
  return name;
}

- (void)removeRelationshipNamed:(NSString *)name
{
  NSEntityDescription *entity = self.entity;
  NSRelationshipDescription *relationship = entity.relationshipsByName[name];
  if (!relationship) return;
  [_modelEditor beginEdit:nil];
  [self removeFromFetchIndexesPropertyNamed:name];
  [_modelEditor removeProperty:relationship];   /* unwires the inverse's pointer back */
  [_modelEditor endEdit];
}

@end

/* ---------------------------------------------------------------- */

@implementation MBAttributeEditor {
  NSString *_entityName;
  NSString *_name;
  NSDate *_proposedDate;   /* what a date picker shows while it has no date */
}

+ (instancetype)editorForAttributeNamed:(NSString *)name
                                 entity:(NSEntityDescription *)entity
                               modelEditor:(MBModelEditor *)modelEditor
{
  if (!entity.attributesByName[name]) return nil;
  MBAttributeEditor *editor = [[self alloc] init];
  editor->_modelEditor = modelEditor;
  editor->_entityName = [entity.name copy];
  editor->_name = [name copy];
  return editor;
}

- (BOOL)editsSameAs:(MBEditor *)editor
{
  MBAttributeEditor *other = (MBAttributeEditor *)editor;
  return [super editsSameAs:editor] && [other->_entityName isEqualToString:_entityName] &&
      [other->_name isEqualToString:_name];
}

- (NSEntityDescription *)entity
{
  return _modelEditor.model.entitiesByName[_entityName];
}

- (NSAttributeDescription *)attribute
{
  return self.entity.attributesByName[_name];
}

- (id)undoSubject { return self.attribute; }
- (NSString *)editActionName { return @"Edit Attribute"; }

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  if (!name.length || [name isEqualToString:_name]) return;
  if (self.entity.propertiesByName[name]) return;   /* duplicate */
  NSString *old = _name;
  self.attribute.name = name;
  _name = [name copy];
  [_modelEditor noteRenameOfKind:MBSelectionAttribute inEntity:_entityName from:old to:name];
  [self didChange:@"name" from:old];
}

- (BOOL)validateName:(id *)value error:(NSError **)error
{
  return MBValidateName(value, _name, [self.entity.propertiesByName allKeys], @"property", error);
}

- (NSArray *)typeNames { return [CDModelCompiler attributeTypeNames]; }

- (BOOL)isBinary { return self.attribute.attributeType == NSBinaryDataAttributeType; }

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
  id oldExternal = self.storedAllowsExternalBinaryDataStorage;
  [_modelEditor beginEdit:nil];   /* several inverses, one step */
  attribute.attributeType = (NSAttributeType)type;
  attribute.defaultValue = nil;   /* the old default belongs to the old type */
  /* Binary Data alone may be kept outside the store: the option goes
     when the type does. */
  if (type != NSBinaryDataAttributeType) attribute.allowsExternalBinaryDataStorage = NO;
  /* Transformer fields are left alone: Apple CoreData throws on nil,
     and the serializer ignores them for non-Transformable types. */
  /* The default's inverse first: undo runs them in reverse, so the type
     is back before the default it belongs to. */
  [self didChange:@"defaultValueObject" from:oldDefault];
  [self didChange:@"storedAllowsExternalBinaryDataStorage" from:oldExternal];
  [self didChange:@"typeName" from:oldType];
  [_modelEditor endEdit];
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
- (BOOL)preservesValueInHistoryOnDeletion
{
  return self.attribute.preservesValueInHistoryOnDeletion;
}
- (void)setPreservesValueInHistoryOnDeletion:(BOOL)preserves
{
  id old = [self valueForKey:@"preservesValueInHistoryOnDeletion"];
  self.attribute.preservesValueInHistoryOnDeletion = preserves;
  [self didChange:@"preservesValueInHistoryOnDeletion" from:old];
}
- (BOOL)allowsExternalBinaryDataStorage
{
  return self.isBinary && self.attribute.allowsExternalBinaryDataStorage;
}
- (void)setAllowsExternalBinaryDataStorage:(BOOL)allows
{
  if (!self.isBinary) return;
  id old = [self valueForKey:@"allowsExternalBinaryDataStorage"];
  self.attribute.allowsExternalBinaryDataStorage = allows;
  [self didChange:@"allowsExternalBinaryDataStorage" from:old];
}
/* The option as stored, whatever the type: what undo restores when a
   type change drops it. */
- (NSNumber *)storedAllowsExternalBinaryDataStorage
{
  return @(self.attribute.allowsExternalBinaryDataStorage);
}
- (void)setStoredAllowsExternalBinaryDataStorage:(NSNumber *)value
{
  id old = self.storedAllowsExternalBinaryDataStorage;
  self.attribute.allowsExternalBinaryDataStorage = value.boolValue;
  [self didChange:@"storedAllowsExternalBinaryDataStorage" from:old];
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

/* The bounds as their formatted fields give and show them. */
- (NSNumber *)validationMinNumber
{
  NSString *string = self.validationMin;
  return string.length ? [NSDecimalNumber decimalNumberWithString:string] : nil;
}
- (void)setValidationMinNumber:(NSNumber *)number { self.validationMin = MBNumberString(number); }
- (BOOL)validateValidationMinNumber:(id *)value error:(NSError **)error
{
  return MBValidateNumber(value, @"minimum", error);
}
- (NSNumber *)validationMaxNumber
{
  NSString *string = self.validationMax;
  return string.length ? [NSDecimalNumber decimalNumberWithString:string] : nil;
}
- (void)setValidationMaxNumber:(NSNumber *)number { self.validationMax = MBNumberString(number); }
- (BOOL)validateValidationMaxNumber:(id *)value error:(NSError **)error
{
  return MBValidateNumber(value, @"maximum", error);
}
- (NSNumber *)minLengthNumber
{
  NSString *string = self.minLengthString;
  return string.length ? @(string.longLongValue) : nil;
}
- (void)setMinLengthNumber:(NSNumber *)number { self.minLengthString = MBNumberString(number); }
- (BOOL)validateMinLengthNumber:(id *)value error:(NSError **)error
{
  return MBValidateWholeNumber(value, 0, LLONG_MAX, @"minimum length", error);
}
- (NSNumber *)maxLengthNumber
{
  NSString *string = self.maxLengthString;
  return string.length ? @(string.longLongValue) : nil;
}
- (void)setMaxLengthNumber:(NSNumber *)number { self.maxLengthString = MBNumberString(number); }
- (BOOL)validateMaxLengthNumber:(id *)value error:(NSError **)error
{
  return MBValidateWholeNumber(value, 0, LLONG_MAX, @"maximum length", error);
}
- (BOOL)validateRegexString:(id *)value error:(NSError **)error
{
  NSString *pattern = [*value description] ?: @"";
  NSError *failure = nil;
  if (pattern.length && ![NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&failure])
    return MBRefuse(error, @"\u201c%@\u201d is not a regular expression.", pattern);
  return YES;
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

- (NSDate *)proposedDate
{
  if (!_proposedDate) _proposedDate = [NSDate date];
  return _proposedDate;
}

/* A date ticked or not, through its `key`: unticked, the picker keeps
   showing the date it had. */
- (BOOL)hasDateForKey:(NSString *)key { return [self valueForKey:key] != nil; }
- (void)setHas:(BOOL)has dateForKey:(NSString *)key
{
  NSDate *date = [self valueForKey:key];
  if (has == (date != nil)) return;
  if (!has) _proposedDate = date;
  [self setValue:has ? [self proposedDate] : nil forKey:key];
}
- (NSDate *)shownDateForKey:(NSString *)key { return [self valueForKey:key] ?: [self proposedDate]; }
- (void)setShownDate:(NSDate *)date forKey:(NSString *)key
{
  if ([self valueForKey:key]) [self setValue:date forKey:key];
  else _proposedDate = date;
}

- (BOOL)hasDefaultDate { return [self hasDateForKey:@"defaultDate"]; }
- (void)setHasDefaultDate:(BOOL)has { [self setHas:has dateForKey:@"defaultDate"]; }
- (NSDate *)shownDefaultDate { return [self shownDateForKey:@"defaultDate"]; }
- (void)setShownDefaultDate:(NSDate *)date { [self setShownDate:date forKey:@"defaultDate"]; }
- (BOOL)hasValidationMinDate { return [self hasDateForKey:@"validationMinDate"]; }
- (void)setHasValidationMinDate:(BOOL)has { [self setHas:has dateForKey:@"validationMinDate"]; }
- (NSDate *)shownValidationMinDate { return [self shownDateForKey:@"validationMinDate"]; }
- (void)setShownValidationMinDate:(NSDate *)date { [self setShownDate:date forKey:@"validationMinDate"]; }
- (BOOL)hasValidationMaxDate { return [self hasDateForKey:@"validationMaxDate"]; }
- (void)setHasValidationMaxDate:(BOOL)has { [self setHas:has dateForKey:@"validationMaxDate"]; }
- (NSDate *)shownValidationMaxDate { return [self shownDateForKey:@"validationMaxDate"]; }
- (void)setShownValidationMaxDate:(NSDate *)date { [self setShownDate:date forKey:@"validationMaxDate"]; }

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
  if (!string.length && attribute.attributeType == NSStringAttributeType && old) {
    attribute.defaultValue = @"";
    [self didChange:@"defaultValueObject" from:old];
    return;
  }
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

/* What the type takes, as -setDefaultString: reads it. */
- (BOOL)validateDefaultString:(id *)value error:(NSError **)error
{
  NSAttributeType type = self.attribute.attributeType;
  NSString *string = (type == NSStringAttributeType) ? ([*value description] ?: @"") : MBTrimmed(*value);
  if (!string.length || type == NSStringAttributeType) {
    *value = string;
    return YES;
  }
  NSScanner *scanner = [NSScanner scannerWithString:string];
  switch (type) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType: {
      long long number;
      long long limit = type == NSInteger16AttributeType ? INT16_MAX
          : type == NSInteger32AttributeType ? INT32_MAX : LLONG_MAX;
      if (![scanner scanLongLong:&number] || !scanner.isAtEnd || number > limit || number < -limit - 1)
        return MBRefuse(error, @"A %@ default must be a whole number from %lld to %lld.",
                        self.typeName, -limit - 1, limit);
      break;
    }
    case NSDoubleAttributeType:
    case NSFloatAttributeType: {
      double number;
      if (![scanner scanDouble:&number] || !scanner.isAtEnd)
        return MBRefuse(error, @"A %@ default must be a number.", self.typeName);
      break;
    }
    case NSDecimalAttributeType:
      if ([[NSDecimalNumber decimalNumberWithString:string] isEqual:[NSDecimalNumber notANumber]])
        return MBRefuse(error, @"A Decimal default must be a number.");
      break;
    case NSBooleanAttributeType:
      if (![@[ @"YES", @"NO", @"1", @"0" ] containsObject:string])
        return MBRefuse(error, @"A Boolean default is YES or NO.");
      break;
    case NSUUIDAttributeType:
      if (![[NSUUID alloc] initWithUUIDString:string])
        return MBRefuse(error, @"\u201c%@\u201d is not a UUID.", string);
      break;
    case NSURIAttributeType:
      if (![NSURL URLWithString:string])
        return MBRefuse(error, @"\u201c%@\u201d is not a URI.", string);
      break;
    default:
      break;
  }
  *value = string;
  return YES;
}

static BOOL MBIsNumberType(NSAttributeType type)
{
  switch (type) {
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSDecimalAttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
      return YES;
    default:
      return NO;
  }
}

- (NSNumber *)defaultNumber
{
  NSAttributeDescription *attribute = self.attribute;
  return MBIsNumberType(attribute.attributeType) ? attribute.defaultValue : nil;
}

- (void)setDefaultNumber:(NSNumber *)number
{
  if (!MBIsNumberType(self.attribute.attributeType)) return;
  self.defaultString = MBNumberString(number);
}

/* A whole number in the type's range for an integer, a number else. */
- (BOOL)validateDefaultNumber:(id *)value error:(NSError **)error
{
  NSAttributeType type = self.attribute.attributeType;
  if (type == NSInteger16AttributeType || type == NSInteger32AttributeType || type == NSInteger64AttributeType) {
    long long limit = type == NSInteger16AttributeType ? INT16_MAX
        : type == NSInteger32AttributeType ? INT32_MAX : LLONG_MAX;
    NSString *what = [NSString stringWithFormat:@"%@ default", self.typeName];
    return MBValidateWholeNumber(value, -limit - 1, limit, what, error);
  }
  return MBValidateNumber(value, @"default", error);
}

- (BOOL)hasDefaultString { return self.attribute.defaultValue != nil; }

- (void)setHasDefaultString:(BOOL)has
{
  if (has == self.hasDefaultString) return;
  self.defaultValueObject = has ? @"" : nil;
}

- (NSInteger)boolDefaultIndex
{
  NSString *string = self.defaultString;
  return [string isEqualToString:@"YES"] ? 1 : [string isEqualToString:@"NO"] ? 2 : 0;
}

/* Only YES/NO are values; No Value clears. */
- (void)setBoolDefaultIndex:(NSInteger)index
{
  self.defaultString = index == 1 ? @"YES" : index == 2 ? @"NO" : @"";
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

- (NSString *)derivationToolTip
{
  return self.isDerived
      ? [NSString stringWithFormat:@"Derivation: %@ \u2014 uncheck and re-check to edit.",
         self.derivationString]
      : @"Turns the attribute into a derived attribute (you will be asked for the derivation expression).";
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
    plain.preservesValueInHistoryOnDeletion = attribute.preservesValueInHistoryOnDeletion;
    plain.allowsExternalBinaryDataStorage = attribute.allowsExternalBinaryDataStorage;
    plain.defaultValue = attribute.defaultValue;
    plain.userInfo = attribute.userInfo;
    [_modelEditor replaceProperty:attribute withProperty:plain];   /* undo puts this one back */
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
  replacement.preservesValueInHistoryOnDeletion = attribute.preservesValueInHistoryOnDeletion;
  replacement.allowsExternalBinaryDataStorage = attribute.allowsExternalBinaryDataStorage;
  replacement.userInfo = attribute.userInfo;
  replacement.derivationExpression = expression;
  [_modelEditor replaceProperty:attribute withProperty:replacement];
}

@end

/* ---------------------------------------------------------------- */

@implementation MBRelationshipEditor {
  NSString *_entityName;
  NSString *_name;
}

+ (instancetype)editorForRelationshipNamed:(NSString *)name
                                    entity:(NSEntityDescription *)entity
                                  modelEditor:(MBModelEditor *)modelEditor
{
  if (!entity.relationshipsByName[name]) return nil;
  MBRelationshipEditor *editor = [[self alloc] init];
  editor->_modelEditor = modelEditor;
  editor->_entityName = [entity.name copy];
  editor->_name = [name copy];
  return editor;
}

- (BOOL)editsSameAs:(MBEditor *)editor
{
  MBRelationshipEditor *other = (MBRelationshipEditor *)editor;
  return [super editsSameAs:editor] && [other->_entityName isEqualToString:_entityName] &&
      [other->_name isEqualToString:_name];
}

- (NSEntityDescription *)entity
{
  return _modelEditor.model.entitiesByName[_entityName];
}

- (NSRelationshipDescription *)relationship
{
  return self.entity.relationshipsByName[_name];
}

- (id)undoSubject { return self.relationship; }
- (NSString *)editActionName { return @"Edit Relationship"; }

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  if (!name.length || [name isEqualToString:_name]) return;
  if (self.entity.propertiesByName[name]) return;   /* duplicate */
  NSString *old = _name;
  self.relationship.name = name;
  _name = [name copy];
  [_modelEditor noteRenameOfKind:MBSelectionRelationship inEntity:_entityName from:old to:name];
  [self didChange:@"name" from:old];
}

- (BOOL)validateName:(id *)value error:(NSError **)error
{
  return MBValidateName(value, _name, [self.entity.propertiesByName allKeys], @"property", error);
}

- (NSArray *)destinationTitles
{
  NSMutableArray *titles = [NSMutableArray arrayWithObject:MBNoneTitle];
  for (NSEntityDescription *entity in [_modelEditor sortedEntities])
    [titles addObject:entity.name ?: @""];
  return titles;
}

- (NSString *)destinationTitle
{
  NSString *name = self.destinationName;
  return name.length ? name : MBNoneTitle;
}

- (void)setDestinationTitle:(NSString *)title
{
  self.destinationName = [title isEqualToString:MBNoneTitle] ? @"" : title;
}

- (NSArray *)inverseTitles
{
  NSMutableArray *titles = [NSMutableArray arrayWithObject:MBNoneTitle];
  NSDictionary *relationships = self.relationship.destinationEntity.relationshipsByName;
  [titles addObjectsFromArray:[[relationships allKeys] sortedArrayUsingSelector:@selector(compare:)]];
  return titles;
}

- (NSString *)inverseTitle
{
  NSString *name = self.inverseName;
  return name.length ? name : MBNoneTitle;
}

- (void)setInverseTitle:(NSString *)title
{
  self.inverseName = [title isEqualToString:MBNoneTitle] ? @"" : title;
}

- (NSInteger)typeIndex { return self.isToMany ? 0 : 1; }

- (void)setTypeIndex:(NSInteger)index
{
  self.toMany = (index == 0);
}

- (NSString *)destinationName { return self.relationship.destinationEntity.name ?: @""; }

- (void)setDestinationName:(NSString *)name
{
  NSRelationshipDescription *relationship = self.relationship;
  NSEntityDescription *destination = name.length
      ? _modelEditor.model.entitiesByName[name] : nil;
  if (destination == relationship.destinationEntity) return;
  id oldDestination = self.destinationName, oldInverse = self.inverseName;
  [_modelEditor beginEdit:nil];   /* two inverses, one step */
  NSRelationshipDescription *previousInverse = relationship.inverseRelationship;
  if (previousInverse.inverseRelationship == relationship)
    previousInverse.inverseRelationship = nil;
  relationship.inverseRelationship = nil;   /* the old inverse points elsewhere */
  relationship.destinationEntity = destination;
  /* The inverse's first: undo sets the destination back, then wires the
     inverse on it again. */
  [self didChange:@"inverseName" from:oldInverse];
  [self didChange:@"destinationName" from:oldDestination];
  [_modelEditor endEdit];
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
  [_modelEditor beginEdit:nil];   /* several inverses, one step */
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
  [_modelEditor endEdit];
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

- (NSNumber *)minCountNumber
{
  NSInteger count = self.minCount;
  return count ? @(count) : nil;
}

- (void)setMinCountNumber:(NSNumber *)number { self.minCount = number.integerValue; }

- (BOOL)validateMinCountNumber:(id *)value error:(NSError **)error
{
  return MBValidateWholeNumber(value, 0, INT32_MAX, @"minimum count", error);
}

- (NSNumber *)maxCountNumber
{
  NSInteger count = self.maxCount;
  return count ? @(count) : nil;
}

- (void)setMaxCountNumber:(NSNumber *)number { self.maxCount = number.integerValue; }

- (BOOL)validateMaxCountNumber:(id *)value error:(NSError **)error
{
  return MBValidateWholeNumber(value, 0, INT32_MAX, @"maximum count", error);
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

/* The pop-up's order, against momc's spellings. */
static NSArray *MBDeleteRulesInPopupOrder(void)
{
  return @[ @"No Action", @"Nullify", @"Cascade", @"Deny" ];
}

- (NSInteger)deleteRuleIndex
{
  NSUInteger index = [MBDeleteRulesInPopupOrder() indexOfObject:self.deleteRuleName];
  return index == NSNotFound ? 1 : (NSInteger)index;
}

- (void)setDeleteRuleIndex:(NSInteger)index
{
  NSArray *rules = MBDeleteRulesInPopupOrder();
  if (index >= 0 && (NSUInteger)index < rules.count) self.deleteRuleName = rules[(NSUInteger)index];
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

+ (instancetype)editorForFetchRequestNamed:(NSString *)name modelEditor:(MBModelEditor *)modelEditor
{
  if (![modelEditor.model fetchRequestTemplateForName:name]) return nil;
  MBFetchEditor *editor = [[self alloc] init];
  editor->_modelEditor = modelEditor;
  editor->_name = [name copy];
  return editor;
}

- (NSFetchRequest *)request
{
  return [_modelEditor.model fetchRequestTemplateForName:_name];
}

- (id)undoSubject { return self.request; }
- (NSString *)editActionName { return @"Edit Fetch Request"; }

- (BOOL)editsSameAs:(MBEditor *)editor
{
  return [super editsSameAs:editor] && [((MBFetchEditor *)editor)->_name isEqualToString:_name];
}

- (NSString *)name { return _name; }

/* The new name is the editor's before the selection follows it. */
- (void)setName:(NSString *)name
{
  NSString *old = _name;
  _name = [name copy];
  if (![_modelEditor renameFetchRequestNamed:old to:name])
    _name = old;
}

- (BOOL)validateName:(id *)value error:(NSError **)error
{
  return MBValidateName(value, _name, [[_modelEditor.model fetchRequestTemplatesByName] allKeys],
                        @"fetch request", error);
}

- (NSArray *)entityNames
{
  return [[_modelEditor sortedEntities] valueForKey:@"name"];
}

- (NSString *)entityName { return self.request.entity.name ?: @""; }

- (void)setEntityName:(NSString *)name
{
  NSEntityDescription *entity = name.length
      ? _modelEditor.model.entitiesByName[name] : nil;
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

- (NSNumber *)fetchLimitNumber
{
  NSUInteger limit = self.fetchLimit;
  return limit ? @(limit) : nil;
}

- (void)setFetchLimitNumber:(NSNumber *)number
{
  self.fetchLimit = (NSUInteger)MAX(0, number.integerValue);
}

- (BOOL)validateFetchLimitNumber:(id *)value error:(NSError **)error
{
  return MBValidateWholeNumber(value, 0, INT32_MAX, @"fetch limit", error);
}

- (NSNumber *)fetchBatchSizeNumber
{
  NSUInteger size = self.fetchBatchSize;
  return size ? @(size) : nil;
}

- (void)setFetchBatchSizeNumber:(NSNumber *)number
{
  self.fetchBatchSize = (NSUInteger)MAX(0, number.integerValue);
}

- (BOOL)validateFetchBatchSizeNumber:(id *)value error:(NSError **)error
{
  return MBValidateWholeNumber(value, 0, INT32_MAX, @"batch size", error);
}

/* The pop-up's index is the resultType integer in the model XML (0/1/2). */
- (NSInteger)resultTypeIndex
{
  switch (self.resultType) {
    case NSManagedObjectIDResultType: return 1;
    case NSDictionaryResultType:      return 2;
    default:                          return 0;
  }
}

- (void)setResultTypeIndex:(NSInteger)index
{
  self.resultType = index == 1 ? NSManagedObjectIDResultType
      : index == 2 ? NSDictionaryResultType : NSManagedObjectResultType;
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

- (BOOL)validatePredicateFormat:(id *)value error:(NSError **)error
{
  return MBValidatePredicate(value, error);
}

@end

/* ---------------------------------------------------------------- */

@implementation MBFetchIndexEditor {
  NSString *_entityName;
  NSString *_name;
}

+ (instancetype)editorForFetchIndexNamed:(NSString *)name
                                  entity:(NSEntityDescription *)entity
                             modelEditor:(MBModelEditor *)modelEditor
{
  MBFetchIndexEditor *editor = [[self alloc] init];
  editor->_modelEditor = modelEditor;
  editor->_entityName = [entity.name copy];
  editor->_name = [name copy];
  return editor.row ? editor : nil;
}

- (BOOL)editsSameAs:(MBEditor *)editor
{
  MBFetchIndexEditor *other = (MBFetchIndexEditor *)editor;
  return [super editsSameAs:editor] && [other->_entityName isEqualToString:_entityName] &&
      [other->_name isEqualToString:_name];
}

- (MBEntityEditor *)entityEditor
{
  return [MBEntityEditor editorForEntityNamed:_entityName modelEditor:_modelEditor];
}

- (NSDictionary *)row
{
  for (NSDictionary *row in [self entityEditor].fetchIndexRows)
    if ([row[@"name"] isEqualToString:_name]) return row;
  return nil;
}

/* The index's row changed, as one undo step; a rename is the editor's,
   and the selection's, before the change is told. */
- (void)changeRow:(void (^)(NSMutableDictionary *row))change action:(NSString *)action
{
  MBEntityEditor *entityEditor = [self entityEditor];
  NSMutableArray *rows = [NSMutableArray array];
  NSString *old = _name, *renamed = _name;
  for (NSDictionary *row in entityEditor.fetchIndexRows) {
    NSMutableDictionary *copy = [row mutableCopy];
    if ([row[@"name"] isEqualToString:old]) {
      change(copy);
      renamed = copy[@"name"];
    }
    [rows addObject:copy];
  }
  [_modelEditor beginEdit:action];
  _name = [renamed copy];
  entityEditor.fetchIndexRows = rows;
  if (entityEditor.lastError) {
    _lastError = entityEditor.lastError;
    _name = old;
  } else if (![renamed isEqualToString:old]) {
    [_modelEditor noteRenameOfKind:MBSelectionFetchIndex inEntity:_entityName from:old to:renamed];
  }
  [_modelEditor endEdit];
}

- (NSString *)name { return _name; }

- (void)setName:(NSString *)name
{
  NSString *wanted = MBTrimmed(name);
  if (!wanted.length || [wanted isEqualToString:_name]) return;
  if ([[[self entityEditor].fetchIndexRows valueForKey:@"name"] containsObject:wanted]) return;
  [self changeRow:^(NSMutableDictionary *row) { row[@"name"] = wanted; } action:@"Rename Fetch Index"];
}

- (BOOL)validateName:(id *)value error:(NSError **)error
{
  return MBValidateName(value, _name, [[self entityEditor].fetchIndexRows valueForKey:@"name"],
                        @"fetch index", error);
}

- (NSString *)predicateFormat { return self.row[@"predicate"] ?: @""; }

- (void)setPredicateFormat:(NSString *)format
{
  NSString *wanted = MBTrimmed(format);
  if ([wanted isEqualToString:self.predicateFormat]) return;
  [self changeRow:^(NSMutableDictionary *row) {
          if (wanted.length) row[@"predicate"] = wanted;
          else [row removeObjectForKey:@"predicate"];
        }
           action:@"Edit Partial Predicate"];
}

- (BOOL)validatePredicateFormat:(id *)value error:(NSError **)error
{
  return MBValidatePredicate(value, error);
}

@end
