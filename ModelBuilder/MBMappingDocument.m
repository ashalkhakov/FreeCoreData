/* ModelBuilder mapping document.  See MBMappingDocument.h.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingDocument.h"
#import "CDMappingCompiler.h"
#import "CDMappingSerializer.h"
#import "MBMappingWindowController.h"

@implementation MBMappingDocument
{
  NSUInteger      _editDepth;
  BOOL            _groupOpen;
  NSString       *_pendingActionName;
  NSString       *_nextActionName;
  NSMutableSet   *_inversesThisGroup;
}

+ (BOOL)autosavesInPlace
{
  return NO;
}

+ (NSArray *)readableTypes
{
  return @[ @"Core Data Mapping Model" ];
}

+ (NSArray *)writableTypes
{
  return [self readableTypes];
}

- (NSString *)fileType
{
  return @"Core Data Mapping Model";
}

- (instancetype)init
{
  if ((self = [super init])) {
    _mappingModel = [[NSMappingModel alloc] init];
    [_mappingModel setEntityMappings:@[]];
  }
  return self;
}

/* -- the file ------------------------------------------------------- */

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
  NSDictionary *models = [CDMappingCompiler modelsForMappingModelAtPath:[url path] error:error];

  if (models == nil) return NO;

  NSManagedObjectModel *source = models[CDMappingSourceModelKey];
  NSManagedObjectModel *destination = models[CDMappingDestinationModelKey];

  if (source == nil || destination == nil) return NO;

  NSMappingModel *mapping = [CDMappingCompiler mappingModelAtPath:[url path]
                                                      sourceModel:source
                                                 destinationModel:destination
                                                            error:error];
  if (mapping == nil) return NO;

  self.mappingModel = mapping;
  self.sourceModel = source;
  self.destinationModel = destination;
  self.sourceModelPath = models[CDMappingSourceModelPathKey];
  self.destinationModelPath = models[CDMappingDestinationModelPathKey];

  return YES;
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
  return [CDMappingSerializer writeMappingModel:self.mappingModel
                                         toPath:[url path]
                                sourceModelPath:self.sourceModelPath
                           destinationModelPath:self.destinationModelPath
                                          error:error];
}

- (void)makeWindowControllers
{
  [self addWindowController:
      [[MBMappingWindowController alloc] initWithWindowNibName:@"MBMappingWindow"]];
}

- (NSString *)windowNibName
{
  return @"MBMappingWindow";
}

- (void)noteMappingChanged
{
  [self updateChangeCount:NSChangeDone];
}

/* -- what the editor shows ------------------------------------------ */

- (NSArray *)entityMappings
{
  return [self.mappingModel entityMappings] ?: @[];
}

- (NSEntityDescription *)destinationEntityOfMapping:(NSEntityMapping *)mapping
{
  NSString *name = [mapping destinationEntityName];

  return name.length ? [[self.destinationModel entitiesByName] objectForKey:name] : nil;
}

/* Every property of the destination entity has a row, whether anything
   fills it or not: a mapping that fills nothing is a column of blanks,
   which is the thing an author is there to fix. */
- (NSArray *)propertyMappingsOfEntityMapping:(NSEntityMapping *)mapping
                               relationships:(BOOL)wantRelationships
{
  NSArray *existing = wantRelationships ? [mapping relationshipMappings] : [mapping attributeMappings];
  NSEntityDescription *entity = [self destinationEntityOfMapping:mapping];

  if (entity == nil) return existing ?: @[];

  NSMutableDictionary *byName = [NSMutableDictionary dictionary];

  for (NSPropertyMapping *property in existing)
    if ([property name]) [byName setObject:property forKey:[property name]];

  NSMutableArray *result = [NSMutableArray array];

  for (NSPropertyDescription *property in [entity properties]) {
    BOOL isRelationship = [property isKindOfClass:[NSRelationshipDescription class]];

    if (isRelationship != wantRelationships) continue;

    NSPropertyMapping *mappingForProperty = [byName objectForKey:[property name]];

    if (mappingForProperty == nil) {
      mappingForProperty = [[NSPropertyMapping alloc] init];
      [mappingForProperty setName:[property name]];
      [self addPropertyMapping:mappingForProperty
             toEntityMapping:mapping
                relationship:wantRelationships];
    }
    [result addObject:mappingForProperty];
  }

  return result;
}

- (NSArray *)attributeMappingsOfEntityMapping:(NSEntityMapping *)mapping
{
  return [self propertyMappingsOfEntityMapping:mapping relationships:NO];
}

- (NSArray *)relationshipMappingsOfEntityMapping:(NSEntityMapping *)mapping
{
  return [self propertyMappingsOfEntityMapping:mapping relationships:YES];
}

- (void)addPropertyMapping:(NSPropertyMapping *)property
           toEntityMapping:(NSEntityMapping *)mapping
              relationship:(BOOL)isRelationship
{
  NSArray *existing = isRelationship ? [mapping relationshipMappings] : [mapping attributeMappings];
  NSArray *updated = [(existing ?: @[]) arrayByAddingObject:property];

  if (isRelationship)
    [mapping setRelationshipMappings:updated];
  else
    [mapping setAttributeMappings:updated];
}

/* -- the edits ------------------------------------------------------- */

- (NSString *)filterPredicateOfEntityMapping:(NSEntityMapping *)mapping
{
  NSExpression *fetch = [mapping sourceExpression];

  if (fetch == nil || [fetch expressionType] != NSFetchRequestExpressionType) return nil;

  NSExpression *request = [(NSFetchRequestExpression *)fetch requestExpression];

  if ([request expressionType] != NSFunctionExpressionType) return nil;

  NSArray *arguments = [request arguments];

  if (arguments.count < 2) return nil;

  NSExpression *predicate = [arguments objectAtIndex:1];
  id value = ([predicate expressionType] == NSConstantValueExpressionType)
      ? [predicate constantValue] : nil;

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
  if ([CDMappingSerializer isGeneratedExpression:expression forPropertyNamed:[property name]])
    return nil;

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
    }
    @catch (NSException *exception) {
      if (error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSFormattingError
                                 userInfo:@{ NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"%@ is not an expression: %@", string, [exception reason]] }];
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
  NSEntityDescription *source = sourceName.length
      ? [[self.sourceModel entitiesByName] objectForKey:sourceName] : nil;
  NSEntityDescription *destination = destinationName.length
      ? [[self.destinationModel entitiesByName] objectForKey:destinationName] : nil;
  NSEntityMapping *mapping = [[NSEntityMapping alloc] init];

  [mapping setName:(sourceName.length && destinationName.length)
      ? [NSString stringWithFormat:@"%@To%@", sourceName, destinationName]
      : (destinationName.length ? destinationName : sourceName)];
  [mapping setSourceEntityName:sourceName];
  [mapping setDestinationEntityName:destinationName];
  [mapping setSourceEntityVersionHash:[source versionHash]];
  [mapping setDestinationEntityVersionHash:[destination versionHash]];
  [mapping setAttributeMappings:@[]];
  [mapping setRelationshipMappings:@[]];

  /* The kind the compiler would work out anyway, so the editor shows it. */
  if (source == nil)
    [mapping setMappingType:NSAddEntityMappingType];
  else if (destination == nil)
    [mapping setMappingType:NSRemoveEntityMappingType];
  else if ([[source versionHash] isEqual:[destination versionHash]])
    [mapping setMappingType:NSCopyEntityMappingType];
  else
    [mapping setMappingType:NSTransformEntityMappingType];

  if (source != nil)
    [mapping setSourceExpression:
        [CDMappingCompiler sourceExpressionForEntityNamed:sourceName predicate:@"TRUEPREDICATE"]];

  [self beginEdit:@"Add Entity Mapping"];
  [self setValue:[[self entityMappings] arrayByAddingObject:mapping]
          forKey:@"entityMappings"
 ofMappingObject:self.mappingModel];
  [self endEdit];

  return mapping;
}

- (void)removeEntityMapping:(NSEntityMapping *)mapping
{
  NSMutableArray *remaining = [[self entityMappings] mutableCopy];

  if (![remaining containsObject:mapping]) return;
  [remaining removeObject:mapping];

  [self beginEdit:@"Remove Entity Mapping"];
  [self setValue:remaining forKey:@"entityMappings" ofMappingObject:self.mappingModel];
  [self endEdit];
}

/* -- undo, one inverse per change ------------------------------------ */

- (void)setUndoActionName:(NSString *)name
{
  if (_editDepth > 0) {
    if (!_pendingActionName.length) _pendingActionName = [name copy];
  } else {
    _nextActionName = [name copy];
  }
}

- (void)beginEdit:(NSString *)actionName
{
  if (_editDepth++ == 0) {
    _pendingActionName = [(actionName.length ? actionName : _nextActionName) copy];
    _nextActionName = nil;
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
    [[self undoManager] endUndoGrouping];
  }
  _pendingActionName = nil;
  _inversesThisGroup = nil;
}

- (MBMappingDocument *)inverse
{
  NSUndoManager *undo = [self undoManager];

  if (!undo.isUndoing && !undo.isRedoing && !_groupOpen && _editDepth > 0) {
    [undo beginUndoGrouping];
    _groupOpen = YES;
    if (_pendingActionName.length) [undo setActionName:_pendingActionName];
  }
  return (MBMappingDocument *)[undo prepareWithInvocationTarget:self];
}

/* Every change goes through here, so every change records the value it
   replaced - and the undo, replayed through the same door, records the
   redo. */
- (void)setValue:(id)value forKey:(NSString *)key ofMappingObject:(id)subject
{
  if (subject == nil) return;

  id current = [subject valueForKey:key];

  if (current == value || [current isEqual:value]) return;

  if ([[self undoManager] isUndoRegistrationEnabled]) {
    [self beginEdit:nil];

    NSString *token = [NSString stringWithFormat:@"%p|%@", subject, key];

    if (![_inversesThisGroup containsObject:token]) {
      [_inversesThisGroup addObject:token];
      [[self inverse] setValue:current ?: [NSNull null] forKey:key ofMappingObject:subject];
    }
    [self endEdit];
  }

  [subject setValue:(value == [NSNull null] ? nil : value) forKey:key];
  [self noteMappingChanged];
}

@end
