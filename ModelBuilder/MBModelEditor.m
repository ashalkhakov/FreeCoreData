/* ModelBuilder — one model version, edited (see MBModelEditor.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBModelEditor.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"
#import "CDModelMutator.h"
#import "MBEditors.h"

NSString *const MBModelEditorDidChangeNotification = @"MBModelEditorDidChangeNotification";
NSString *const MBModelEditorSelectionDidChangeNotification = @"MBModelEditorSelectionDidChangeNotification";

@implementation MBSelection

+ (instancetype)selectionOfKind:(MBSelectionKind)kind
                     entityName:(NSString *)entityName
                           name:(NSString *)name
              configurationName:(NSString *)configurationName
{
  MBSelection *selection = [[self alloc] init];
  selection->_kind = kind;
  selection->_entityName = [entityName copy];
  selection->_name = [name copy];
  selection->_configurationName = [configurationName copy];
  return selection;
}

+ (instancetype)entityNamed:(NSString *)name
{
  return [self selectionOfKind:MBSelectionEntity entityName:name name:nil configurationName:nil];
}

+ (instancetype)fetchRequestNamed:(NSString *)name
{
  return [self selectionOfKind:MBSelectionFetchRequest entityName:nil name:name configurationName:nil];
}

+ (instancetype)configurationNamed:(NSString *)name
{
  return [self selectionOfKind:MBSelectionConfiguration entityName:nil name:nil configurationName:name];
}

- (id)copyWithZone:(NSZone *)zone
{
  (void)zone;
  return self;   /* immutable */
}

static BOOL MBSameString(NSString *a, NSString *b)
{
  return a == b || [a isEqualToString:b];
}

- (BOOL)isEqual:(id)other
{
  if (![other isKindOfClass:[MBSelection class]]) return NO;
  MBSelection *o = other;
  return o->_kind == _kind && MBSameString(o->_entityName, _entityName) &&
         MBSameString(o->_name, _name) && MBSameString(o->_configurationName, _configurationName);
}

- (NSUInteger)hash
{
  return (NSUInteger)_kind ^ _entityName.hash ^ _name.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<MBSelection %ld %@ %@ %@>", (long)_kind,
          _entityName, _name, _configurationName];
}

@end

@implementation MBModelEditor {
  NSManagedObjectModel *_model;
  NSMutableDictionary *_entityLayouts;

  /* Undo bookkeeping (see "Undo" below): how deep -beginEdit: calls are
     nested, whether the outermost one has opened its undo group yet, the
     action name it will carry, and which subject/key pairs already have
     an inverse in it. */
  NSInteger _editDepth;
  BOOL _groupOpen;
  NSString *_pendingActionName;
  NSString *_nextActionName;   /* for the next edit (-setUndoActionName:) */
  NSMutableSet *_inversesThisGroup;
}

@synthesize model = _model;
@synthesize entityLayouts = _entityLayouts;

- (instancetype)initWithUndoManager:(NSUndoManager *)undoManager
{
  self = [super init];
  if (!self) return nil;
  _undoManager = undoManager;
  _entityLayouts = [NSMutableDictionary dictionary];
  NSEntityDescription *entity = [[NSEntityDescription alloc] init];
  entity.name = @"Entity";
  entity.managedObjectClassName = @"NSManagedObject";
  _model = [[NSManagedObjectModel alloc] init];
  _model.entities = @[ entity ];
  return self;
}

- (instancetype)initWithContentsXML:(NSString *)xml
                        undoManager:(NSUndoManager *)undoManager
                              error:(NSError **)error
{
  self = [self initWithUndoManager:undoManager];
  if (!self) return nil;
  if (![self readContentsXML:xml error:error]) return nil;
  return self;
}

#pragma mark - The selection

- (void)setSelection:(MBSelection *)selection
{
  if (selection == _selection || [selection isEqual:_selection]) return;
  _selection = [selection copy];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:MBModelEditorSelectionDidChangeNotification object:self];
}

- (NSEntityDescription *)selectedEntity
{
  NSString *name = _selection.entityName;
  return name ? _model.entitiesByName[name] : nil;
}

- (NSPropertyDescription *)selectedProperty
{
  NSEntityDescription *entity = [self selectedEntity];
  if (!_selection.name) return nil;
  if (_selection.kind == MBSelectionAttribute) return entity.attributesByName[_selection.name];
  if (_selection.kind == MBSelectionRelationship) return entity.relationshipsByName[_selection.name];
  return nil;
}

- (NSFetchRequest *)selectedFetchRequest
{
  if (_selection.kind != MBSelectionFetchRequest || !_selection.name) return nil;
  return [_model fetchRequestTemplateForName:_selection.name];
}

/* The selection, with the name it had replaced by the new one. */
- (void)renameInSelection:(BOOL)entity
            configuration:(BOOL)configuration
                     kind:(MBSelectionKind)kind
                     from:(NSString *)oldName
                       to:(NSString *)newName
{
  MBSelection *s = _selection;
  if (!s) return;
  NSString *entityName = s.entityName, *name = s.name, *configurationName = s.configurationName;
  if (entity && MBSameString(entityName, oldName)) entityName = newName;
  if (configuration && MBSameString(configurationName, oldName)) configurationName = newName;
  if (kind != MBSelectionNone && s.kind == kind && MBSameString(name, oldName)) name = newName;
  self.selection = [MBSelection selectionOfKind:s.kind entityName:entityName name:name
                              configurationName:configurationName];
}

- (void)noteRenameOfKind:(MBSelectionKind)kind
                 inEntity:(NSString *)entityName
                     from:(NSString *)oldName
                       to:(NSString *)newName
{
  if (!MBSameString(_selection.entityName, entityName)) return;
  [self renameInSelection:NO configuration:NO kind:kind from:oldName to:newName];
}

- (void)noteModelChanged
{
  /* A document's change count follows its undo manager: NSDocument counts
     a change when an undo group closes and takes it back when it is
     undone.  Every edit registers an inverse (see "Undo"). */
  [[NSNotificationCenter defaultCenter]
      postNotificationName:MBModelEditorDidChangeNotification object:self];
}

- (NSArray *)sortedEntities
{
  return [self.model.entities sortedArrayUsingComparator:
      ^NSComparisonResult(NSEntityDescription *a, NSEntityDescription *b) {
        return [a.name compare:b.name];
      }];
}

- (NSArray *)configurationNames
{
  return [[_model configurations] sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Contents XML

static NSMutableDictionary *layoutsFromContentsXML(NSString *xml)
{
  NSMutableDictionary *layouts = [NSMutableDictionary dictionary];
  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL];

  for (NSXMLElement *wrap in [[doc rootElement] elementsForName:@"elements"]) {
    for (NSXMLElement *el in [wrap elementsForName:@"element"]) {
      NSString *name = [[el attributeForName:@"name"] stringValue];
      if (!name.length) continue;
      NSMutableDictionary *layout = [NSMutableDictionary dictionary];
      for (NSString *key in @[ @"positionX", @"positionY", @"width", @"height" ]) {
        NSString *value = [[el attributeForName:key] stringValue];
        if (value.length) layout[key] = value;
      }
      layouts[name] = layout;
    }
  }
  return layouts;
}

- (NSString *)contentsXML:(NSError **)error
{
  return [CDModelSerializer contentsXMLForModel:_model
                                  entityLayouts:_entityLayouts
                                          error:error];
}

- (BOOL)readContentsXML:(NSString *)xml error:(NSError **)error
{
  NSManagedObjectModel *model = [CDModelCompiler compileModelContentsXML:xml error:error];
  if (!model) return NO;
  _model = model;
  _entityLayouts = layoutsFromContentsXML(xml);
  [self noteModelChanged];
  return YES;
}

- (void)replaceModel:(NSManagedObjectModel *)model layouts:(NSDictionary *)layouts
{
  _model = model;
  _entityLayouts = [layouts mutableCopy];
  [self noteModelChanged];
}

#pragma mark - Undo

/* Undo is granular.  Each edit records its own inverse -- the same
   setter with the previous value, or the operation that takes a
   structural change back -- against the description object it changed,
   not its name, so an undo finds it after a rename.  When the inverse
   runs it records the redo the same way.  Operations that already rebuild
   the model (entity removal and reparenting, configurations) keep the
   previous model object and put it back: a pointer swap, no copying. */

/* Names the next undo step, for operations that open no group of their
   own before recording (the mutator-backed ones). */
- (void)setUndoActionName:(NSString *)name
{
  if (_editDepth > 0) {
    if (!_pendingActionName.length) _pendingActionName = [name copy];
  } else {
    _nextActionName = [name copy];
  }
}

- (MBModelEditor *)undoProxy
{
  /* -prepareWithInvocationTarget: is typed id; type the proxy so the
     selectors resolve against this class. */
  return (MBModelEditor *)[_undoManager prepareWithInvocationTarget:self];
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
    [_undoManager endUndoGrouping];
  }
  _pendingActionName = nil;
  _inversesThisGroup = nil;
}

/* The proxy to record an inverse on, opening the edit's undo group the
   first time one is recorded -- so an edit that changes nothing leaves no
   empty step behind, and does not mark the document edited.  While an
   undo or redo runs, the undo manager has its own group open for the
   redo and no other is opened. */
- (MBModelEditor *)inverse
{
  NSUndoManager *undo = _undoManager;
  if (!undo.isUndoing && !undo.isRedoing && !_groupOpen && _editDepth > 0) {
    [undo beginUndoGrouping];
    _groupOpen = YES;
    if (_pendingActionName.length) [undo setActionName:_pendingActionName];
  }
  return [self undoProxy];
}

- (id)inverseFor:(id)target
{
  [self inverse];   /* opens the edit's undo group */
  return [_undoManager prepareWithInvocationTarget:target];
}

- (void)registerInverseValue:(id)value forKey:(NSString *)key ofSubject:(id)subject
{
  if (!subject || ![_undoManager isUndoRegistrationEnabled]) return;
  [self beginEdit:nil];
  /* The first inverse per subject and key in a group wins: a stepper held
     down, or an inspector applying the same field twice, is one step back
     to where it started. */
  NSString *token = [NSString stringWithFormat:@"%p|%@", subject, key];
  if (![_inversesThisGroup containsObject:token]) {
    [_inversesThisGroup addObject:token];
    [[self inverse] applyValue:value ?: [NSNull null] forKey:key ofSubject:subject];
  }
  [self endEdit];
}

/* Inverse of a value edit: the editor for the subject, as it is now, set
   back through the same setter -- which records the redo. */
- (void)applyValue:(id)value forKey:(NSString *)key ofSubject:(id)subject
{
  MBEditor *editor = [MBEditor editorForSubject:subject modelEditor:self];
  [editor setValue:(value == [NSNull null] ? nil : value) forKey:key];
}

/* Apple's CoreData drops the fetch indexes of an entity, and of every
   entity above it, when its properties are set - even to the same ones.
   They are put back. */
static void MBSetPropertiesKeepingIndexes(NSEntityDescription *entity, NSArray *properties)
{
  NSMutableArray *chain = [NSMutableArray array];
  NSMutableArray *indexes = [NSMutableArray array];
  for (NSEntityDescription *check = entity; check; check = check.superentity) {
    [chain addObject:check];
    [indexes addObject:check.indexes ?: @[]];
  }
  entity.properties = properties;
  for (NSUInteger i = 0; i < chain.count; i++)
    if (![[chain[i] indexes] isEqualToArray:indexes[i]]) {
      [chain[i] setIndexes:@[]];   /* see -[MBEntityEditor setFetchIndexRows:] */
      [chain[i] setIndexes:indexes[i]];
    }
}

- (void)insertProperty:(NSPropertyDescription *)property
              intoEntity:(NSEntityDescription *)entity
                 atIndex:(NSUInteger)index
{
  [self beginEdit:nil];
  NSMutableArray *properties = [[CDModelCompiler declaredPropertiesOfEntity:entity] mutableCopy];
  [properties insertObject:property atIndex:MIN(index, properties.count)];
  MBSetPropertiesKeepingIndexes(entity, properties);
  /* A removed relationship kept its own inverse; its partner's pointer
     back was cut on removal, and is restored with it. */
  if ([property isKindOfClass:[NSRelationshipDescription class]]) {
    NSRelationshipDescription *inverse = [(NSRelationshipDescription *)property inverseRelationship];
    if (inverse && inverse.inverseRelationship == nil)
      inverse.inverseRelationship = (NSRelationshipDescription *)property;
  }
  [[self inverse] removeProperty:property];
  [self noteModelChanged];
  [self endEdit];
}

- (void)removeProperty:(NSPropertyDescription *)property
{
  NSEntityDescription *entity = property.entity;
  NSUInteger index = [[CDModelCompiler declaredPropertiesOfEntity:entity] indexOfObjectIdenticalTo:property];
  if (!entity || index == NSNotFound) return;
  [self beginEdit:nil];
  if ([property isKindOfClass:[NSRelationshipDescription class]]) {
    NSRelationshipDescription *inverse = [(NSRelationshipDescription *)property inverseRelationship];
    if (inverse.inverseRelationship == (NSRelationshipDescription *)property)
      inverse.inverseRelationship = nil;
  }
  NSMutableArray *properties = [[CDModelCompiler declaredPropertiesOfEntity:entity] mutableCopy];
  [properties removeObjectAtIndex:index];
  MBSetPropertiesKeepingIndexes(entity, properties);
  [[self inverse] insertProperty:property intoEntity:entity atIndex:index];
  [self noteModelChanged];
  [self endEdit];
}

/* One description object standing in for another at the same place --
   an attribute becoming derived, or plain again. */
- (void)replaceProperty:(NSPropertyDescription *)current
           withProperty:(NSPropertyDescription *)replacement
{
  NSEntityDescription *entity = current.entity;
  NSUInteger index = [[CDModelCompiler declaredPropertiesOfEntity:entity] indexOfObjectIdenticalTo:current];
  if (!entity || index == NSNotFound) return;
  [self beginEdit:nil];
  NSMutableArray *properties = [[CDModelCompiler declaredPropertiesOfEntity:entity] mutableCopy];
  [properties replaceObjectAtIndex:index withObject:replacement];
  MBSetPropertiesKeepingIndexes(entity, properties);
  [[self inverse] replaceProperty:replacement withProperty:current];
  [self noteModelChanged];
  [self endEdit];
}

- (void)setEntities:(NSArray *)entities layouts:(NSDictionary *)layouts
{
  [self beginEdit:nil];
  [[self inverse] setEntities:self.model.entities layouts:[self.entityLayouts copy]];
  _model.entities = entities;
  _entityLayouts = [layouts mutableCopy];
  [self noteModelChanged];
  [self endEdit];
}

- (void)adoptModel:(NSManagedObjectModel *)model layouts:(NSDictionary *)layouts
{
  [self beginEdit:nil];
  [[self inverse] adoptModel:self.model layouts:[self.entityLayouts copy]];
  _model = model;
  _entityLayouts = [layouts mutableCopy];
  [self noteModelChanged];
  [self endEdit];
}

- (void)setFetchRequest:(NSFetchRequest *)request forName:(NSString *)name
{
  [self beginEdit:nil];
  NSFetchRequest *previous = [self.model fetchRequestTemplateForName:name];
  [[self inverse] setFetchRequest:previous forName:name];
  [self.model setFetchRequestTemplate:request forName:name];
  [self noteModelChanged];
  [self endEdit];
}

/* Structural surgery lives at the model layer (CDModelMutator, next
   to the compiler and serializer); the document adopts a successful
   mutation's renormalized model and re-derives the layout sidecar
   from the mutated XML. */
- (BOOL)adoptMutation:(CDModelMutationResult *)result
{
  if (!result) {
    _nextActionName = nil;   /* nothing happened to name */
    return NO;
  }
  [self adoptModel:result.model layouts:layoutsFromContentsXML(result.contentsXML)];
  return YES;
}

#pragma mark - Entity lifecycle

static NSString *MBUniqueName(NSString *base, NSArray *names)
{
  if (![names containsObject:base]) return base;
  NSUInteger counter = 2;
  NSString *candidate;
  do {
    candidate = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)counter];
    counter++;
  } while ([names containsObject:candidate]);
  return candidate;
}

- (NSString *)addEntity
{
  NSString *name = MBUniqueName(@"Entity",
      [self.model.entities valueForKey:@"name"] ?: @[]);
  NSEntityDescription *entity = [[NSEntityDescription alloc] init];
  entity.name = name;
  entity.managedObjectClassName = @"NSManagedObject";
  [self beginEdit:@"Add Entity"];
  [self setEntities:[self.model.entities arrayByAddingObject:entity]
            layouts:self.entityLayouts];
  [self endEdit];
  return name;
}

- (BOOL)renameEntityNamed:(NSString *)name to:(NSString *)newName
{
  NSEntityDescription *entity = self.model.entitiesByName[name];
  if (!entity || !newName.length) return NO;
  if ([name isEqualToString:newName]) return YES;
  if (self.model.entitiesByName[newName]) return NO;
  [self beginEdit:@"Rename Entity"];
  if (self.entityLayouts[name]) {
    self.entityLayouts[newName] = self.entityLayouts[name];
    [self.entityLayouts removeObjectForKey:name];
  }
  entity.name = newName;
  [self renameInSelection:YES configuration:NO kind:MBSelectionNone from:name to:newName];
  [[self inverse] renameEntityNamed:newName to:name];
  [self noteModelChanged];
  [self endEdit];
  return YES;
}

/* Entity deletion ripples through relationships, configurations, fetch
   templates and subentity wiring; reparenting has no description-class
   API.  Both are CDModelMutator surgery, renormalized by momc. */
- (BOOL)removeEntityNamed:(NSString *)name error:(NSError **)error
{
  [self setUndoActionName:@"Delete Entity"];
  return [self adoptMutation:[CDModelMutator model:self.model
                                     entityLayouts:self.entityLayouts
                               removingEntityNamed:name
                                             error:error]];
}

- (BOOL)setParentOfEntityNamed:(NSString *)entityName
                            to:(NSString *)parentName
                         error:(NSError **)error
{
  [self setUndoActionName:@"Change Parent Entity"];
  return [self adoptMutation:[CDModelMutator model:self.model
                                     entityLayouts:self.entityLayouts
                        settingParentOfEntityNamed:entityName
                                                to:parentName
                                             error:error]];
}

#pragma mark - Fetch request lifecycle

- (NSString *)addFetchRequestForEntityNamed:(NSString *)entityName
{
  NSEntityDescription *entity = entityName.length
      ? self.model.entitiesByName[entityName] : nil;
  if (!entity) entity = [self sortedEntities].firstObject;
  if (!entity) return nil;
  NSString *name = MBUniqueName(@"FetchRequest",
      [[self.model fetchRequestTemplatesByName] allKeys]);
  NSFetchRequest *request = [[NSFetchRequest alloc] init];
  request.entity = entity;
  [self beginEdit:@"Add Fetch Request"];
  [self setFetchRequest:request forName:name];
  [self endEdit];
  return name;
}

- (void)removeFetchRequestNamed:(NSString *)name
{
  if (![self.model fetchRequestTemplateForName:name]) return;
  [self beginEdit:@"Delete Fetch Request"];
  [self setFetchRequest:nil forName:name];
  [self endEdit];
}

- (BOOL)renameFetchRequestNamed:(NSString *)name to:(NSString *)newName
{
  if (!newName.length || [name isEqualToString:newName]) return NO;
  NSFetchRequest *request = [self.model fetchRequestTemplateForName:name];
  if (!request || [self.model fetchRequestTemplateForName:newName]) return NO;
  [self beginEdit:@"Rename Fetch Request"];
  [self setFetchRequest:nil forName:name];
  [self setFetchRequest:request forName:newName];
  [self endEdit];
  [self renameInSelection:NO configuration:NO kind:MBSelectionFetchRequest from:name to:newName];
  return YES;
}

#pragma mark - Configurations


- (NSString *)addConfiguration
{
  NSArray *names = [self configurationNames];
  NSUInteger counter = 1;
  NSString *candidate = @"Configuration";
  while ([names containsObject:candidate]) {
    counter++;
    candidate = [NSString stringWithFormat:@"Configuration %lu", (unsigned long)counter];
  }
  [self setUndoActionName:@"Add Configuration"];
  if (![self adoptMutation:[CDModelMutator model:self.model
                                   entityLayouts:self.entityLayouts
                        addingConfigurationNamed:candidate
                                           error:NULL]])
    return nil;
  return candidate;
}

- (BOOL)removeConfigurationNamed:(NSString *)name error:(NSError **)error
{
  [self setUndoActionName:@"Delete Configuration"];
  return [self adoptMutation:[CDModelMutator model:self.model
                                     entityLayouts:self.entityLayouts
                        removingConfigurationNamed:name
                                             error:error]];
}

- (BOOL)renameConfiguration:(NSString *)name to:(NSString *)newName error:(NSError **)error
{
  if (!newName.length || [name isEqualToString:newName]) return YES;
  if ([[self configurationNames] containsObject:newName]) return YES;
  [self beginEdit:@"Rename Configuration"];
  BOOL renamed = [self adoptMutation:[CDModelMutator model:self.model
                                             entityLayouts:self.entityLayouts
                                renamingConfigurationNamed:name
                                                        to:newName
                                                     error:error]];
  if (renamed) [self moveSelectedConfigurationFrom:name to:newName];
  [self endEdit];
  return renamed;
}

/* The selection follows a renamed configuration, and back on undo (the
   mutation's own inverse puts the model back, not the name). */
- (void)moveSelectedConfigurationFrom:(NSString *)name to:(NSString *)newName
{
  [self beginEdit:nil];
  [[self inverse] moveSelectedConfigurationFrom:newName to:name];
  [self renameInSelection:NO configuration:YES kind:MBSelectionNone from:name to:newName];
  [self endEdit];
}

- (BOOL)setEntityNamed:(NSString *)entityName
       inConfiguration:(NSString *)configurationName
                member:(BOOL)member
                 error:(NSError **)error
{
  [self setUndoActionName:member ? @"Add to Configuration" : @"Remove from Configuration"];
  return [self adoptMutation:[CDModelMutator model:self.model
                                     entityLayouts:self.entityLayouts
                                settingEntityNamed:entityName
                                   inConfiguration:configurationName
                                            member:member
                                             error:error]];
}

@end
