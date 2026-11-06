/* Editing view-models for the mapping inspector.
   See MBMappingEditors.h for the design.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingEditors.h"
#import "MBMappingEditor.h"
#import "MBEditors.h"

NSString *const MBMappingNoEntityTitle = @"None";

static BOOL MBRefuse(NSError **error, NSString *message)
{
  if (error)
    *error = [NSError errorWithDomain:MBEditorErrorDomain code:2
                             userInfo:@{ NSLocalizedDescriptionKey : message }];
  return NO;
}

static NSString *MBTrimmed(id value)
{
  return [[value description] ?: @"" stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/* "None", then `names`, then `current` when it is none of them. */
static NSArray *MBEntityTitles(NSArray *names, NSString *current)
{
  NSMutableArray *titles = [NSMutableArray arrayWithObject:MBMappingNoEntityTitle];
  [titles addObjectsFromArray:names];
  if (current.length && ![names containsObject:current]) [titles addObject:current];
  return titles;
}

static NSString *MBEntityFromTitle(NSString *title)
{
  return [title isEqualToString:MBMappingNoEntityTitle] ? nil : title;
}

@interface MBMappingObjectEditor () {
 @protected
  MBMappingEditor *_mappingEditor;
}
/* What its user info is on: the entity mapping, or the row's property
   mapping (made for an edit when there is none). */
- (id)userInfoSubjectToEdit:(BOOL)edit;
@end

@implementation MBMappingObjectEditor

- (MBMappingEditor *)mappingEditor { return _mappingEditor; }

- (BOOL)editsSameAs:(MBMappingObjectEditor *)editor
{
  return [editor class] == [self class] && editor->_mappingEditor == _mappingEditor;
}

- (void)reload
{
  MBReloadProperties(self, [MBMappingObjectEditor class]);
  [self willChangeValueForKey:@"userInfo"];
  [self didChangeValueForKey:@"userInfo"];
}

- (id)userInfoSubjectToEdit:(BOOL)edit
{
  (void)edit;
  return nil;
}

- (NSDictionary *)userInfo
{
  return [[self userInfoSubjectToEdit:NO] userInfo];
}

- (void)setUserInfo:(NSDictionary *)userInfo
{
  [_mappingEditor setUserInfo:userInfo ofMappingObject:[self userInfoSubjectToEdit:YES]];
}

@end

/* ---------------------------------------------------------------- */

@implementation MBEntityMappingEditor

+ (instancetype)editorForEntityMapping:(NSEntityMapping *)mapping mappingEditor:(MBMappingEditor *)mappingEditor
{
  if (!mapping) return nil;
  MBEntityMappingEditor *editor = [[self alloc] init];
  editor->_mappingEditor = mappingEditor;
  editor->_entityMapping = mapping;
  return editor;
}

- (BOOL)editsSameAs:(MBMappingObjectEditor *)editor
{
  return [super editsSameAs:editor] && ((MBEntityMappingEditor *)editor)->_entityMapping == _entityMapping;
}

- (id)userInfoSubjectToEdit:(BOOL)edit
{
  (void)edit;
  return _entityMapping;
}

- (NSString *)name { return [_entityMapping name] ?: @""; }

- (void)setName:(NSString *)name
{
  [_mappingEditor setName:MBTrimmed(name) ofEntityMapping:_entityMapping];
}

- (BOOL)validateName:(id *)value error:(NSError **)error
{
  NSString *name = MBTrimmed(*value);
  if (!name.length) return MBRefuse(error, @"An entity mapping needs a name.");
  NSEntityMapping *other = [_mappingEditor entityMappingNamed:name];
  if (other && other != _entityMapping)
    return MBRefuse(error, [NSString stringWithFormat:@"There is an entity mapping named “%@” already.", name]);
  *value = name;
  return YES;
}

- (NSArray *)sourceEntityTitles
{
  return MBEntityTitles([_mappingEditor sourceEntityNames], [_entityMapping sourceEntityName]);
}

- (NSString *)sourceEntityTitle
{
  return [_entityMapping sourceEntityName].length ? [_entityMapping sourceEntityName] : MBMappingNoEntityTitle;
}

- (void)setSourceEntityTitle:(NSString *)title
{
  [_mappingEditor setSourceEntityName:MBEntityFromTitle(title)
                destinationEntityName:[_entityMapping destinationEntityName]
                      ofEntityMapping:_entityMapping];
}

- (NSArray *)destinationEntityTitles
{
  return MBEntityTitles([_mappingEditor destinationEntityNames], [_entityMapping destinationEntityName]);
}

- (NSString *)destinationEntityTitle
{
  return [_entityMapping destinationEntityName].length ? [_entityMapping destinationEntityName]
                                                         : MBMappingNoEntityTitle;
}

- (void)setDestinationEntityTitle:(NSString *)title
{
  [_mappingEditor setSourceEntityName:[_entityMapping sourceEntityName]
                destinationEntityName:MBEntityFromTitle(title)
                      ofEntityMapping:_entityMapping];
}

- (NSString *)mappingTypeName { return [_mappingEditor mappingTypeNameOfEntityMapping:_entityMapping]; }

- (NSString *)customPolicy { return [_entityMapping entityMigrationPolicyClassName] ?: @""; }

- (void)setCustomPolicy:(NSString *)className
{
  [_mappingEditor setMigrationPolicyClassName:MBTrimmed(className) ofEntityMapping:_entityMapping];
}

- (BOOL)fetchesSource { return [_entityMapping sourceEntityName].length > 0; }

- (NSInteger)sourceFetchIndex
{
  if (!self.fetchesSource) return 0;
  return ([_mappingEditor filterPredicateOfEntityMapping:_entityMapping] != nil ||
          [_mappingEditor choseCustomFetchFor:_entityMapping property:nil]) ? 1 : 0;
}

/* Back to Default drops the predicate. */
- (void)setSourceFetchIndex:(NSInteger)index
{
  [_mappingEditor setChoseCustomFetch:(index == 1) for:_entityMapping property:nil];
  if (index != 1) [_mappingEditor setFilterPredicate:nil forEntityMapping:_entityMapping];
  [self reload];
}

- (BOOL)filtersSource { return self.fetchesSource && self.sourceFetchIndex == 1; }

- (NSString *)filterPredicate { return [_mappingEditor filterPredicateOfEntityMapping:_entityMapping] ?: @""; }

- (void)setFilterPredicate:(NSString *)predicate
{
  NSString *typed = MBTrimmed(predicate);
  [_mappingEditor setFilterPredicate:typed.length ? typed : nil forEntityMapping:_entityMapping];
}

- (BOOL)validateFilterPredicate:(id *)value error:(NSError **)error
{
  NSString *format = MBTrimmed(*value);
  if (format.length) {
    @try {
      [NSPredicate predicateWithFormat:format];
    } @catch (NSException *exception) {
      return MBRefuse(error, [NSString stringWithFormat:@"“%@” is not a predicate: %@",
                                                        format, exception.reason]);
    }
  }
  *value = format;
  return YES;
}

@end

/* ---------------------------------------------------------------- */

@implementation MBPropertyMappingEditor {
  NSString *_name;
}

+ (instancetype)editorForPropertyNamed:(NSString *)name
                       inEntityMapping:(NSEntityMapping *)mapping
                         relationships:(BOOL)relationships
                         mappingEditor:(MBMappingEditor *)mappingEditor
{
  if (!mapping || !name.length) return nil;
  MBPropertyMappingEditor *editor = [[self alloc] init];
  editor->_mappingEditor = mappingEditor;
  editor->_entityMapping = mapping;
  editor->_relationships = relationships;
  editor->_name = [name copy];
  return editor;
}

- (BOOL)editsSameAs:(MBMappingObjectEditor *)editor
{
  MBPropertyMappingEditor *other = (MBPropertyMappingEditor *)editor;
  return [super editsSameAs:editor] && other->_entityMapping == _entityMapping &&
      other->_relationships == _relationships && [other->_name isEqualToString:_name];
}

- (NSPropertyMapping *)propertyMapping
{
  return [_mappingEditor propertyMappingNamed:_name inEntityMapping:_entityMapping relationships:_relationships];
}

- (NSPropertyMapping *)propertyMappingToEdit
{
  return [_mappingEditor propertyMappingToEditNamed:_name inEntityMapping:_entityMapping relationships:_relationships];
}

- (id)userInfoSubjectToEdit:(BOOL)edit
{
  return edit ? [self propertyMappingToEdit] : [self propertyMapping];
}

- (NSArray *)nameTitles
{
  return [_mappingEditor propertyNamesOfEntityMapping:_entityMapping relationships:_relationships];
}

- (NSString *)name { return _name; }

/* The new name is the editor's before the selection follows it. */
- (void)setName:(NSString *)name
{
  if (!name.length || [name isEqualToString:_name]) return;
  NSString *old = _name;
  [_mappingEditor beginEdit:@"Change Destination Property"];
  NSPropertyMapping *property = [self propertyMappingToEdit];
  _name = [name copy];
  [_mappingEditor setName:name ofPropertyMapping:property inEntityMapping:_entityMapping];
  if (![[property name] isEqualToString:name]) _name = old;
  [_mappingEditor endEdit];
}

- (NSString *)valueExpressionString
{
  return [_mappingEditor valueExpressionStringOfPropertyMapping:self.propertyMapping] ?: @"";
}

- (void)setValueExpressionString:(NSString *)string
{
  NSString *typed = MBTrimmed(string);
  if ([typed isEqualToString:self.valueExpressionString]) return;
  [_mappingEditor beginEdit:@"Change Value Expression"];
  [_mappingEditor setValueExpressionString:typed ofPropertyMapping:[self propertyMappingToEdit] error:NULL];
  [_mappingEditor endEdit];
}

- (BOOL)validateValueExpressionString:(id *)value error:(NSError **)error
{
  NSString *string = MBTrimmed(*value);
  if (string.length) {
    @try {
      [NSExpression expressionWithFormat:string];
    } @catch (NSException *exception) {
      return MBRefuse(error, [NSString stringWithFormat:@"“%@” is not an expression: %@",
                                                        string, exception.reason]);
    }
  }
  *value = string;
  return YES;
}

/* What fills the row when nothing is written. */
- (NSString *)generatedExpressionString
{
  NSPropertyMapping *property = self.propertyMapping;
  if (property && [_mappingEditor valueExpressionStringOfPropertyMapping:property] == nil &&
      [property valueExpression])
    return [[property valueExpression] description];
  return @"Value Expression";
}

- (BOOL)generatesExpression
{
  return [_mappingEditor relationshipMappingNamed:_name inEntityMapping:_entityMapping
                                          keyPath:NULL mappingName:NULL] &&
      ![_mappingEditor choseCustomFetchFor:_entityMapping property:_name];
}

- (BOOL)writesExpression { return !self.generatesExpression; }

- (NSInteger)sourceFetchIndex { return self.generatesExpression ? 0 : 1; }

/* Back to Auto Generate: what the compiler works out from the names. */
- (void)setSourceFetchIndex:(NSInteger)index
{
  [_mappingEditor setChoseCustomFetch:(index == 1) for:_entityMapping property:_name];
  if (index != 1 && self.propertyMapping)
    [_mappingEditor setValueExpressionString:nil ofPropertyMapping:self.propertyMapping error:NULL];
  [self reload];
}

- (NSString *)keyPath
{
  NSString *keyPath = nil;
  return (self.generatesExpression &&
          [_mappingEditor relationshipMappingNamed:_name inEntityMapping:_entityMapping
                                           keyPath:&keyPath mappingName:NULL]) ? (keyPath ?: @"") : @"";
}

- (NSString *)mappingName
{
  NSString *mappingName = nil;
  return (self.generatesExpression &&
          [_mappingEditor relationshipMappingNamed:_name inEntityMapping:_entityMapping
                                           keyPath:NULL mappingName:&mappingName]) ? (mappingName ?: @"") : @"";
}

- (void)setKeyPath:(NSString *)keyPath
{
  [self setKeyPath:MBTrimmed(keyPath) mappingName:self.mappingName];
}

- (void)setMappingName:(NSString *)mappingName
{
  [self setKeyPath:self.keyPath mappingName:MBTrimmed(mappingName)];
}

- (void)setKeyPath:(NSString *)keyPath mappingName:(NSString *)mappingName
{
  if ([keyPath isEqualToString:self.keyPath] && [mappingName isEqualToString:self.mappingName]) return;
  [_mappingEditor beginEdit:@"Change Value Expression"];
  [_mappingEditor setKeyPath:keyPath mappingName:mappingName ofRelationshipMapping:[self propertyMappingToEdit]];
  [_mappingEditor endEdit];
}

@end
