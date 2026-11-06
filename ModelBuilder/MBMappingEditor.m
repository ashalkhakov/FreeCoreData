/* ModelBuilder — one mapping model, edited (see MBMappingEditor.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingEditor.h"
#import "CDMappingCompiler.h"
#import "CDMappingSerializer.h"

NSString *const MBMappingEditorDidChangeNotification = @"MBMappingEditorDidChange";
NSString *const MBMappingEditorSelectionDidChangeNotification = @"MBMappingEditorSelectionDidChange";

static BOOL MBSameString(NSString *a, NSString *b)
{
  return a == b || [a isEqualToString:b];
}

@implementation MBMappingSelection

+ (instancetype)selectionOfKind:(MBMappingSelectionKind)kind
              entityMappingName:(NSString *)entityMappingName
                   propertyName:(NSString *)propertyName
{
  MBMappingSelection *selection = [[self alloc] init];
  selection->_kind = kind;
  selection->_entityMappingName = [entityMappingName copy];
  selection->_propertyName = [propertyName copy];
  return selection;
}

+ (instancetype)entityMappingNamed:(NSString *)name
{
  return [self selectionOfKind:MBMappingSelectionEntityMapping entityMappingName:name propertyName:nil];
}

- (id)copyWithZone:(NSZone *)zone
{
  (void)zone;
  return self;   /* immutable */
}

- (BOOL)isEqual:(id)object
{
  if (object == self) return YES;
  if (![object isKindOfClass:[MBMappingSelection class]]) return NO;
  MBMappingSelection *other = object;
  return other.kind == _kind && MBSameString(other.entityMappingName, _entityMappingName) &&
      MBSameString(other.propertyName, _propertyName);
}

- (NSUInteger)hash
{
  return (NSUInteger)_kind ^ _entityMappingName.hash ^ _propertyName.hash;
}

@end

@implementation MBMappingEditor {
  NSString *_xml;   /* the text read last: what a write keeps of it */

  /* Undo bookkeeping, as MBModelEditor's: how deep -beginEdit: calls are
     nested, whether the outermost one has opened its undo group yet, the
     action name it will carry, which subject/key pairs already have an
     inverse in it, and what it changed. */
  NSInteger _editDepth;
  BOOL _groupOpen;
  NSString *_pendingActionName;
  NSMutableSet *_inversesThisGroup;
  BOOL _changedInEdit;
  BOOL _selectedInEdit;
  NSMutableSet *_customFetches;
}

- (instancetype)initWithUndoManager:(NSUndoManager *)undoManager
{
  if ((self = [super init])) {
    _undoManager = undoManager;
    _mappingModel = [[NSMappingModel alloc] init];
    [_mappingModel setEntityMappings:@[]];
  }
  return self;
}

- (instancetype)initWithXMLString:(NSString *)xml
                           atPath:(NSString *)path
                      undoManager:(NSUndoManager *)undoManager
                            error:(NSError **)error
{
  self = [self initWithUndoManager:undoManager];
  if (!self) return nil;
  if (![self readXMLString:xml atPath:path error:error]) return nil;
  return self;
}

#pragma mark - The file

- (BOOL)readXMLString:(NSString *)xml atPath:(NSString *)path error:(NSError **)error
{
  NSDictionary *models = [CDMappingCompiler modelsForMappingXMLString:xml atPath:path error:error];
  NSManagedObjectModel *source = models[CDMappingSourceModelKey];
  NSManagedObjectModel *destination = models[CDMappingDestinationModelKey];
  if (source == nil || destination == nil) return NO;

  NSMappingModel *mapping = [CDMappingCompiler mappingModelFromXMLString:xml
                                                                  atPath:path
                                                             sourceModel:source
                                                        destinationModel:destination
                                                                   error:error];
  if (mapping == nil) return NO;

  _xml = [xml copy];
  [self setMappingModel:mapping
            sourceModel:source
       destinationModel:destination
        sourceModelPath:models[CDMappingSourceModelPathKey]
   destinationModelPath:models[CDMappingDestinationModelPathKey]];
  return YES;
}

- (NSString *)XMLString:(NSError **)error
{
  return [CDMappingSerializer xcmappingXMLForMappingModel:_mappingModel
                                          sourceModelPath:_sourceModelPath
                                     destinationModelPath:_destinationModelPath
                                            overXMLString:_xml
                                                    error:error];
}

- (void)setMappingModel:(NSMappingModel *)mappingModel
            sourceModel:(NSManagedObjectModel *)sourceModel
       destinationModel:(NSManagedObjectModel *)destinationModel
        sourceModelPath:(NSString *)sourceModelPath
   destinationModelPath:(NSString *)destinationModelPath
{
  _mappingModel = mappingModel;
  _sourceModel = sourceModel;
  _destinationModel = destinationModel;
  _sourceModelPath = [sourceModelPath copy];
  _destinationModelPath = [destinationModelPath copy];
  [self noteMappingChanged];
}

- (void)noteMappingChanged
{
  if (_editDepth > 0) {
    _changedInEdit = YES;   /* told once, when the edit ends */
    return;
  }
  [[NSNotificationCenter defaultCenter]
      postNotificationName:MBMappingEditorDidChangeNotification object:self];
}

#pragma mark - The selection

- (void)setSelection:(MBMappingSelection *)selection
{
  if (selection == _selection || [selection isEqual:_selection]) return;
  _selection = [selection copy];
  if (_editDepth > 0) {
    _selectedInEdit = YES;   /* told after the mapping's change, when the edit ends */
    return;
  }
  [[NSNotificationCenter defaultCenter]
      postNotificationName:MBMappingEditorSelectionDidChangeNotification object:self];
}

- (NSEntityMapping *)selectedEntityMapping
{
  return [self entityMappingNamed:_selection.entityMappingName];
}

/* A mapping object renamed: the selection that named it names it again. */
- (void)noteRenameOf:(id)subject from:(NSString *)oldName to:(NSString *)newName
{
  MBMappingSelection *s = _selection;
  if (!s || !oldName) return;
  if ([subject isKindOfClass:[NSEntityMapping class]]) {
    if (MBSameString(s.entityMappingName, oldName))
      self.selection = [MBMappingSelection selectionOfKind:s.kind entityMappingName:newName
                                              propertyName:s.propertyName];
    return;
  }
  NSEntityMapping *selected = [self selectedEntityMapping];
  NSArray *rows = s.kind == MBMappingSelectionRelationshipMapping ? [selected relationshipMappings]
                : s.kind == MBMappingSelectionAttributeMapping ? [selected attributeMappings] : nil;
  if ([rows indexOfObjectIdenticalTo:subject] != NSNotFound && MBSameString(s.propertyName, oldName))
    self.selection = [MBMappingSelection selectionOfKind:s.kind entityMappingName:s.entityMappingName
                                            propertyName:newName];
}

#pragma mark - What there is

- (NSArray *)entityMappings
{
  return [_mappingModel entityMappings] ?: @[];
}

- (NSEntityMapping *)entityMappingNamed:(NSString *)name
{
  if (!name) return nil;
  for (NSEntityMapping *mapping in [self entityMappings])
    if ([[mapping name] isEqualToString:name]) return mapping;
  return nil;
}

- (NSArray *)sourceEntityNames
{
  return [[[_sourceModel entitiesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray *)destinationEntityNames
{
  return [[[_destinationModel entitiesByName] allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSEntityDescription *)destinationEntityOfMapping:(NSEntityMapping *)mapping
{
  NSString *name = [mapping destinationEntityName];
  return name.length ? [[_destinationModel entitiesByName] objectForKey:name] : nil;
}

/* Every property of the destination entity has a row, whether anything
   fills it or not: a mapping that fills nothing is a column of blanks,
   which is the thing an author is there to fix. */
- (NSArray *)propertyNamesOfEntityMapping:(NSEntityMapping *)mapping relationships:(BOOL)relationships
{
  NSMutableArray *names = [NSMutableArray array];
  for (NSPropertyDescription *property in [[self destinationEntityOfMapping:mapping] properties])
    if ([property isKindOfClass:[NSRelationshipDescription class]] == relationships && [property name])
      [names addObject:[property name]];
  for (NSPropertyMapping *property in relationships ? [mapping relationshipMappings] : [mapping attributeMappings])
    if ([property name] && ![names containsObject:[property name]]) [names addObject:[property name]];
  return names;
}

- (NSPropertyMapping *)propertyMappingNamed:(NSString *)name
                            inEntityMapping:(NSEntityMapping *)mapping
                              relationships:(BOOL)relationships
{
  for (NSPropertyMapping *property in relationships ? [mapping relationshipMappings] : [mapping attributeMappings])
    if ([[property name] isEqualToString:name]) return property;
  return nil;
}

- (NSPropertyMapping *)propertyMappingToEditNamed:(NSString *)name
                                  inEntityMapping:(NSEntityMapping *)mapping
                                    relationships:(BOOL)relationships
{
  NSPropertyMapping *property = [self propertyMappingNamed:name inEntityMapping:mapping relationships:relationships];
  if (property || !mapping || !name.length) return property;
  property = [[NSPropertyMapping alloc] init];
  [property setName:name];
  NSString *key = relationships ? @"relationshipMappings" : @"attributeMappings";
  [self setValue:[([mapping valueForKey:key] ?: @[]) arrayByAddingObject:property]
          forKey:key ofMappingObject:mapping];
  return property;
}

#pragma mark - The edits

- (NSString *)filterPredicateOfEntityMapping:(NSEntityMapping *)mapping
{
  NSExpression *fetch = [mapping sourceExpression];
  if (fetch == nil || [fetch expressionType] != NSFetchRequestExpressionType) return nil;
  NSExpression *request = [(NSFetchRequestExpression *)fetch requestExpression];
  if ([request expressionType] != NSFunctionExpressionType) return nil;
  NSArray *arguments = [request arguments];
  if (arguments.count < 2) return nil;
  NSExpression *predicate = [arguments objectAtIndex:1];
  id value = ([predicate expressionType] == NSConstantValueExpressionType) ? [predicate constantValue] : nil;
  if (![value isKindOfClass:[NSString class]]) return nil;
  return [value isEqualToString:@"TRUEPREDICATE"] ? nil : value;
}

- (void)setFilterPredicate:(NSString *)predicate forEntityMapping:(NSEntityMapping *)mapping
{
  if ([mapping sourceEntityName].length == 0) return;   /* an added entity fetches nothing */
  NSExpression *rebuilt = [CDMappingCompiler
      sourceExpressionForEntityNamed:[mapping sourceEntityName]
                           predicate:predicate.length ? predicate : @"TRUEPREDICATE"];
  [self beginEdit:@"Change Filter Predicate"];
  [self setValue:rebuilt forKey:@"sourceExpression" ofMappingObject:mapping];
  [self endEdit];
}

/* An expression the compiler would have worked out anyway is shown as
   nothing, which is what it is: the editor's blank cell means "whatever
   follows from the name", and is what the file stores. */
- (NSString *)valueExpressionStringOfPropertyMapping:(NSPropertyMapping *)property
{
  NSExpression *expression = [property valueExpression];
  if (expression == nil) return nil;
  if ([CDMappingSerializer isGeneratedExpression:expression forPropertyNamed:[property name]]) return nil;
  return [expression description];
}

- (BOOL)setValueExpressionString:(NSString *)string
               ofPropertyMapping:(NSPropertyMapping *)property
                           error:(NSError **)error
{
  NSExpression *expression = nil;
  if (string.length > 0) {
    @try {
      expression = [NSExpression expressionWithFormat:string];
    } @catch (NSException *exception) {
      if (error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFormattingError userInfo:@{
          NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@ is not an expression: %@",
                                                                 string, [exception reason]]
        }];
      return NO;
    }
  }
  [self beginEdit:@"Change Value Expression"];
  [self setValue:expression forKey:@"valueExpression" ofMappingObject:property];
  [self endEdit];
  return YES;
}

- (NSEntityMapping *)addEntityMappingFromEntityNamed:(NSString *)sourceName
                                      toEntityNamed:(NSString *)destinationName
{
  NSEntityDescription *source = sourceName.length ? [[_sourceModel entitiesByName] objectForKey:sourceName] : nil;
  NSEntityDescription *destination = destinationName.length
      ? [[_destinationModel entitiesByName] objectForKey:destinationName] : nil;
  NSEntityMapping *mapping = [CDMappingCompiler entityMappingFromEntity:source toEntity:destination];

  /* Names are how a mapping is found again: a new one takes one of its own. */
  NSString *base = [mapping name] ?: @"Mapping", *name = base;
  for (NSUInteger n = 2; [self entityMappingNamed:name]; n++)
    name = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)n];
  [mapping setName:name];

  [self beginEdit:@"Add Entity Mapping"];
  [self setValue:[[self entityMappings] arrayByAddingObject:mapping]
          forKey:@"entityMappings" ofMappingObject:_mappingModel];
  [self endEdit];
  return mapping;
}

- (void)removeEntityMapping:(NSEntityMapping *)mapping
{
  NSMutableArray *remaining = [[self entityMappings] mutableCopy];
  if ([remaining indexOfObjectIdenticalTo:mapping] == NSNotFound) return;
  [remaining removeObjectIdenticalTo:mapping];
  [self beginEdit:@"Remove Entity Mapping"];
  [self setValue:remaining forKey:@"entityMappings" ofMappingObject:_mappingModel];
  [self endEdit];
}

- (NSString *)mappingTypeNameOfEntityMapping:(NSEntityMapping *)mapping
{
  switch ([mapping mappingType]) {
    case NSAddEntityMappingType:       return @"Add";
    case NSRemoveEntityMappingType:    return @"Remove";
    case NSCopyEntityMappingType:      return @"Copy";
    case NSTransformEntityMappingType: return @"Transform";
    case NSCustomEntityMappingType:    return @"Custom";
    default:                           return @"Undefined";
  }
}

- (void)setName:(NSString *)name ofEntityMapping:(NSEntityMapping *)mapping
{
  if (name.length == 0 || [self entityMappingNamed:name]) return;
  [self beginEdit:@"Rename Entity Mapping"];
  [self setValue:name forKey:@"name" ofMappingObject:mapping];
  [self endEdit];
}

- (void)setSourceEntityName:(NSString *)sourceName
      destinationEntityName:(NSString *)destinationName
            ofEntityMapping:(NSEntityMapping *)mapping
{
  NSEntityDescription *source = sourceName.length ? [[_sourceModel entitiesByName] objectForKey:sourceName] : nil;
  NSEntityDescription *destination = destinationName.length
      ? [[_destinationModel entitiesByName] objectForKey:destinationName] : nil;
  NSString *wasDefaultName = [CDMappingCompiler
      defaultNameForEntityMappingFromEntityNamed:[mapping sourceEntityName]
                                   toEntityNamed:[mapping destinationEntityName]];
  NSString *predicate = [self filterPredicateOfEntityMapping:mapping];
  NSEntityMappingType type;

  if (source == nil)
    type = NSAddEntityMappingType;
  else if (destination == nil)
    type = NSRemoveEntityMappingType;
  else if ([[source versionHash] isEqual:[destination versionHash]])
    type = NSCopyEntityMappingType;
  else
    type = NSTransformEntityMappingType;

  [self beginEdit:@"Change Entity Mapping"];
  [self setValue:sourceName.length ? sourceName : nil forKey:@"sourceEntityName" ofMappingObject:mapping];
  [self setValue:destinationName.length ? destinationName : nil
          forKey:@"destinationEntityName" ofMappingObject:mapping];
  [self setValue:[source versionHash] forKey:@"sourceEntityVersionHash" ofMappingObject:mapping];
  [self setValue:[destination versionHash] forKey:@"destinationEntityVersionHash" ofMappingObject:mapping];
  [self setValue:@(type) forKey:@"mappingType" ofMappingObject:mapping];
  [self setValue:(source != nil)
      ? [CDMappingCompiler sourceExpressionForEntityNamed:sourceName
                                                predicate:predicate.length ? predicate : @"TRUEPREDICATE"]
      : nil
          forKey:@"sourceExpression" ofMappingObject:mapping];
  /* A name that only said which entities were paired says it again, if
     no other mapping has it. */
  NSString *defaultName = [CDMappingCompiler defaultNameForEntityMappingFromEntityNamed:sourceName
                                                                          toEntityNamed:destinationName];
  if ([[mapping name] isEqualToString:wasDefaultName] && ![self entityMappingNamed:defaultName])
    [self setValue:defaultName forKey:@"name" ofMappingObject:mapping];
  [self endEdit];
}

- (void)setMigrationPolicyClassName:(NSString *)className ofEntityMapping:(NSEntityMapping *)mapping
{
  [self beginEdit:@"Change Custom Policy"];
  [self setValue:className.length ? className : nil forKey:@"entityMigrationPolicyClassName" ofMappingObject:mapping];
  [self endEdit];
}

- (void)setUserInfo:(NSDictionary *)userInfo ofMappingObject:(id)subject
{
  [self beginEdit:@"Change User Info"];
  [self setValue:userInfo.count ? [userInfo copy] : nil forKey:@"userInfo" ofMappingObject:subject];
  [self endEdit];
}

- (void)setName:(NSString *)name
    ofPropertyMapping:(NSPropertyMapping *)property
      inEntityMapping:(NSEntityMapping *)mapping
{
  NSString *was = [property name];
  if (name.length == 0 || [name isEqualToString:was]) return;
  [self beginEdit:@"Change Destination Property"];
  for (NSPropertyMapping *other in [([mapping attributeMappings] ?: @[])
           arrayByAddingObjectsFromArray:[mapping relationshipMappings] ?: @[]])
    if (other != property && [[other name] isEqualToString:name])
      [self setValue:was forKey:@"name" ofMappingObject:other];
  [self setValue:name forKey:@"name" ofMappingObject:property];
  [self endEdit];
}

/* The mapping the compiler fills a relationship through: the one that
   makes the destination entity the source relationship reaches. */
- (NSString *)defaultMappingNameForRelationshipNamed:(NSString *)name
                                     inEntityMapping:(NSEntityMapping *)mapping
{
  NSEntityDescription *source = [[_sourceModel entitiesByName] objectForKey:[mapping sourceEntityName]];
  NSRelationshipDescription *relationship = [[source relationshipsByName] objectForKey:name];
  NSString *reached = [[relationship destinationEntity] name];
  if (reached == nil) return nil;
  for (NSEntityMapping *candidate in [self entityMappings])
    if ([[candidate destinationEntityName] isEqualToString:reached]) return [candidate name];
  return nil;
}

- (BOOL)relationshipMappingNamed:(NSString *)name
                 inEntityMapping:(NSEntityMapping *)mapping
                         keyPath:(NSString **)keyPath
                     mappingName:(NSString **)mappingName
{
  NSPropertyMapping *property = [self propertyMappingNamed:name inEntityMapping:mapping relationships:YES];
  NSExpression *expression = [property valueExpression];
  NSString *path = nil, *through = nil;

  if (expression != nil
      && ![CDMappingSerializer relationshipExpression:expression mappingName:&through keyPath:&path])
    return NO;
  if (expression == nil) {
    path = name;
    through = [self defaultMappingNameForRelationshipNamed:name inEntityMapping:mapping];
  }
  if (keyPath != NULL) *keyPath = path;
  if (mappingName != NULL) *mappingName = through;
  return YES;
}

- (void)setKeyPath:(NSString *)keyPath
          mappingName:(NSString *)mappingName
ofRelationshipMapping:(NSPropertyMapping *)property
{
  NSExpression *expression = (keyPath.length && mappingName.length)
      ? [CDMappingCompiler valueExpressionForRelationshipKeyPath:keyPath throughMapping:mappingName]
      : nil;
  [self beginEdit:@"Change Value Expression"];
  [self setValue:expression forKey:@"valueExpression" ofMappingObject:property];
  [self endEdit];
}

#pragma mark - What the window remembers

static NSString *MBFetchToken(NSEntityMapping *mapping, NSString *propertyName)
{
  return [NSString stringWithFormat:@"%p|%@", (void *)mapping, propertyName ?: @""];
}

- (BOOL)choseCustomFetchFor:(NSEntityMapping *)mapping property:(NSString *)propertyName
{
  return [_customFetches containsObject:MBFetchToken(mapping, propertyName)];
}

- (void)setChoseCustomFetch:(BOOL)chose for:(NSEntityMapping *)mapping property:(NSString *)propertyName
{
  if (!_customFetches) _customFetches = [NSMutableSet set];
  if (chose) [_customFetches addObject:MBFetchToken(mapping, propertyName)];
  else [_customFetches removeObject:MBFetchToken(mapping, propertyName)];
}

#pragma mark - Undo, one inverse per change

- (void)beginEdit:(NSString *)actionName
{
  if (_editDepth++ == 0) {
    _pendingActionName = [actionName copy];
    _inversesThisGroup = [NSMutableSet set];
  } else if (!_pendingActionName.length && actionName.length) {
    _pendingActionName = [actionName copy];
  }
}

- (void)endEdit
{
  if (_editDepth == 0) return;
  if (--_editDepth > 0) return;
  if (_groupOpen) {
    _groupOpen = NO;
    [_undoManager endUndoGrouping];
  }
  _pendingActionName = nil;
  _inversesThisGroup = nil;
  if (_changedInEdit) {
    _changedInEdit = NO;
    [self noteMappingChanged];
  }
  if (_selectedInEdit) {
    _selectedInEdit = NO;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:MBMappingEditorSelectionDidChangeNotification object:self];
  }
}

/* The proxy to record an inverse on, opening the edit's undo group the
   first time one is recorded - so an edit that changes nothing leaves no
   empty step.  While an undo or redo runs, the undo manager has its own
   group open for the redo and no other is opened. */
- (MBMappingEditor *)inverse
{
  NSUndoManager *undo = _undoManager;
  if (!undo.isUndoing && !undo.isRedoing && !_groupOpen && _editDepth > 0) {
    [undo beginUndoGrouping];
    _groupOpen = YES;
    if (_pendingActionName.length) [undo setActionName:_pendingActionName];
  }
  return (MBMappingEditor *)[undo prepareWithInvocationTarget:self];
}

/* Every change goes through here, so every change records the value it
   replaced - and the undo, replayed through the same door, records the
   redo.  A rename takes the selection along. */
- (void)setValue:(id)value forKey:(NSString *)key ofMappingObject:(id)subject
{
  if (subject == nil) return;
  if (value == [NSNull null]) value = nil;
  id current = [subject valueForKey:key];
  if (current == value || [current isEqual:value]) return;

  [self beginEdit:nil];
  if ([_undoManager isUndoRegistrationEnabled]) {
    NSString *token = [NSString stringWithFormat:@"%p|%@", subject, key];
    if (![_inversesThisGroup containsObject:token]) {
      [_inversesThisGroup addObject:token];
      [[self inverse] setValue:current ?: [NSNull null] forKey:key ofMappingObject:subject];
    }
  }
  [subject setValue:value forKey:key];
  if ([key isEqualToString:@"name"]) [self noteRenameOf:subject from:current to:value];
  [self noteMappingChanged];
  [self endEdit];
}

@end
