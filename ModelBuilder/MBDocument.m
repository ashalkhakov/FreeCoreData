/* ModelBuilder document — .xcdatamodeld editing over CDModelCompiler /
   CDModelSerializer (momc's parser and its inverse), so the editor,
   the compiler and the runtime share one schema implementation.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBDocument.h"
#import "MBWindowController.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"
#import "CDModelMutator.h"
#import "MBEditors.h"

static NSString *const kCurrentVersionKey = @"_XCCurrentVersionName";

@implementation MBDocument {
  /* version file name -> contents XML.  The edited version's entry is
     refreshed from the live model on save/switch; other versions ride
     along verbatim. */
  NSMutableDictionary *_versionXML;

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

+ (BOOL)autosavesInPlace
{
  return NO;
}

+ (NSArray *)readableTypes
{
  return @[ @"xcdatamodeld", @"xcdatamodel", @"Core Data Model", @"Core Data Model Version" ];
}

+ (NSArray *)writableTypes
{
  return @[ @"xcdatamodeld", @"Core Data Model" ];
}

- (instancetype)init
{
  self = [super init];
  if (!self) return nil;
  /* Grouping by event is off: every edit opens its own group (see "Undo"),
     so one user action is one undo step however the run loop turns, and
     edits made without a running run loop (the tests) group the same. */
  NSUndoManager *undo = [[NSUndoManager alloc] init];
  [undo setGroupsByEvent:NO];
  [self setUndoManager:undo];
  _versionXML = [NSMutableDictionary dictionary];
  self.entityLayouts = [NSMutableDictionary dictionary];

  NSEntityDescription *entity = [[NSEntityDescription alloc] init];
  entity.name = @"Entity";
  entity.managedObjectClassName = @"NSManagedObject";
  NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
  model.entities = @[ entity ];
  self.model = model;
  self.editedVersionName = @"Model.xcdatamodel";
  self.currentVersionName = self.editedVersionName;
  return self;
}

- (void)makeWindowControllers
{
  /* The window layout lives in MBDocumentWindow.xib (loaded by AppKit
     on macOS and by GSXib5 on GNUstep); MBWindowController adds the
     behavior in -windowDidLoad. */
  MBWindowController *controller =
      [[MBWindowController alloc] initWithWindowNibName:@"MBDocumentWindow"];
  [self addWindowController:controller];
}

- (void)noteModelChanged
{
  /* The change count follows the undo manager: NSDocument counts a change
     when an undo group closes and takes it back when it is undone, so the
     edited mark clears again once everything is undone.  Every edit
     registers an inverse (see "Undo"); nothing to count here. */
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

- (MBDocument *)undoProxy
{
  /* -prepareWithInvocationTarget: is typed id; type the proxy so the
     selectors resolve against this class. */
  return (MBDocument *)[[self undoManager] prepareWithInvocationTarget:self];
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

/* The proxy to record an inverse on, opening the edit's undo group the
   first time one is recorded -- so an edit that changes nothing leaves no
   empty step behind, and does not mark the document edited.  While an
   undo or redo runs, the undo manager has its own group open for the
   redo and no other is opened. */
- (MBDocument *)inverse
{
  NSUndoManager *undo = [self undoManager];
  if (!undo.isUndoing && !undo.isRedoing && !_groupOpen && _editDepth > 0) {
    [undo beginUndoGrouping];
    _groupOpen = YES;
    if (_pendingActionName.length) [undo setActionName:_pendingActionName];
  }
  return [self undoProxy];
}

- (void)registerInverseValue:(id)value forKey:(NSString *)key ofSubject:(id)subject
{
  if (!subject || ![[self undoManager] isUndoRegistrationEnabled]) return;
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
  MBEditor *editor = [MBEditor editorForSubject:subject document:self];
  [editor setValue:(value == [NSNull null] ? nil : value) forKey:key];
}

- (void)insertProperty:(NSPropertyDescription *)property
              intoEntity:(NSEntityDescription *)entity
                 atIndex:(NSUInteger)index
{
  [self beginEdit:nil];
  NSMutableArray *properties = [entity.properties mutableCopy];
  [properties insertObject:property atIndex:MIN(index, properties.count)];
  entity.properties = properties;
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
  NSUInteger index = [entity.properties indexOfObjectIdenticalTo:property];
  if (!entity || index == NSNotFound) return;
  [self beginEdit:nil];
  if ([property isKindOfClass:[NSRelationshipDescription class]]) {
    NSRelationshipDescription *inverse = [(NSRelationshipDescription *)property inverseRelationship];
    if (inverse.inverseRelationship == (NSRelationshipDescription *)property)
      inverse.inverseRelationship = nil;
  }
  NSMutableArray *properties = [entity.properties mutableCopy];
  [properties removeObjectAtIndex:index];
  entity.properties = properties;
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
  NSUInteger index = [entity.properties indexOfObjectIdenticalTo:current];
  if (!entity || index == NSNotFound) return;
  [self beginEdit:nil];
  NSMutableArray *properties = [entity.properties mutableCopy];
  [properties replaceObjectAtIndex:index withObject:replacement];
  entity.properties = properties;
  [[self inverse] replaceProperty:replacement withProperty:current];
  [self noteModelChanged];
  [self endEdit];
}

- (void)setEntities:(NSArray *)entities layouts:(NSDictionary *)layouts
{
  [self beginEdit:nil];
  [[self inverse] setEntities:self.model.entities layouts:[self.entityLayouts copy]];
  self.model.entities = entities;
  self.entityLayouts = [layouts mutableCopy];
  [self noteModelChanged];
  [self endEdit];
}

- (void)adoptModel:(NSManagedObjectModel *)model layouts:(NSDictionary *)layouts
{
  [self beginEdit:nil];
  [[self inverse] adoptModel:self.model layouts:[self.entityLayouts copy]];
  self.model = model;
  self.entityLayouts = [layouts mutableCopy];
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

/* Versions: the version XML dictionary holds immutable strings, so its
   copy is cheap and carries the others through; the edited version is
   the live model. */
- (void)restoreVersions:(NSDictionary *)versions
                 edited:(NSString *)edited
                current:(NSString *)current
                  model:(NSManagedObjectModel *)model
                layouts:(NSDictionary *)layouts
{
  [self beginEdit:nil];
  [[self inverse] restoreVersions:[_versionXML copy]
                           edited:self.editedVersionName
                          current:self.currentVersionName
                            model:self.model
                          layouts:[self.entityLayouts copy]];
  [_versionXML setDictionary:versions];
  self.editedVersionName = edited;
  self.currentVersionName = current;
  self.model = model;
  self.entityLayouts = [layouts mutableCopy];
  [self noteModelChanged];
  [self endEdit];
}

- (NSString *)defaultDraftName
{
  return @"Model";
}

- (NSString *)fileType
{
  return @"xcdatamodeld";
}

- (NSString *)windowNibName
{
  return nil; /* window controllers own the nib */
}

- (NSArray *)versionNames
{
  return [[_versionXML allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray *)sortedEntities
{
  return [self.model.entities sortedArrayUsingComparator:
      ^NSComparisonResult(NSEntityDescription *a, NSEntityDescription *b) {
        return [a.name compare:b.name];
      }];
}

#pragma mark - XML plumbing

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

- (NSString *)serializedEditedVersion:(NSError **)error
{
  return [CDModelSerializer contentsXMLForModel:self.model
                                  entityLayouts:self.entityLayouts
                                          error:error];
}

/* Refresh the cache entry for the version being edited. */
- (BOOL)snapshotEditedVersion:(NSError **)error
{
  NSString *xml = [self serializedEditedVersion:error];
  if (!xml) return NO;
  _versionXML[self.editedVersionName] = xml;
  return YES;
}

- (BOOL)loadVersionNamed:(NSString *)name error:(NSError **)error
{
  NSString *xml = _versionXML[name];
  if (!xml.length) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:6 userInfo:@{
        NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"No version named %@ in this document.", name]
      }];
    }
    return NO;
  }
  NSManagedObjectModel *model = [CDModelCompiler compileModelContentsXML:xml error:error];
  if (!model) return NO;
  self.model = model;
  self.editedVersionName = name;
  self.entityLayouts = layoutsFromContentsXML(xml);
  return YES;
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
  return YES;
}

#pragma mark - Configurations

- (NSArray *)configurationNames
{
  return [[self.model configurations] sortedArrayUsingSelector:@selector(compare:)];
}

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
  [self setUndoActionName:@"Rename Configuration"];
  return [self adoptMutation:[CDModelMutator model:self.model
                                     entityLayouts:self.entityLayouts
                        renamingConfigurationNamed:name
                                                to:newName
                                             error:error]];
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

#pragma mark - Versions (Xcode Editor menu)

- (NSString *)addModelVersion
{
  NSDictionary *versions = [_versionXML copy];
  NSString *edited = self.editedVersionName, *current = self.currentVersionName;
  NSManagedObjectModel *model = self.model;
  NSDictionary *layouts = [self.entityLayouts copy];
  if (![self snapshotEditedVersion:NULL]) return nil;

  NSString *base = [self.editedVersionName stringByDeletingPathExtension];
  /* Xcode names copies "Model 2", "Model 3", ... from the base name. */
  NSRange spaceDigit = [base rangeOfString:@" " options:NSBackwardsSearch];
  if (spaceDigit.location != NSNotFound &&
      [[base substringFromIndex:spaceDigit.location + 1] integerValue] > 0)
    base = [base substringToIndex:spaceDigit.location];

  NSUInteger counter = 2;
  NSString *candidate;
  do {
    candidate = [NSString stringWithFormat:@"%@ %lu.xcdatamodel", base, (unsigned long)counter];
    counter++;
  } while (_versionXML[candidate] != nil);

  _versionXML[candidate] = _versionXML[self.editedVersionName];
  [self loadVersionNamed:candidate error:NULL];
  [self beginEdit:@"Add Model Version"];
  [[self inverse] restoreVersions:versions edited:edited current:current
                            model:model layouts:layouts];
  [self noteModelChanged];
  [self endEdit];
  return candidate;
}

- (BOOL)switchToVersion:(NSString *)name error:(NSError **)error
{
  if ([name isEqualToString:self.editedVersionName]) return YES;
  if (![self snapshotEditedVersion:error]) return NO;
  if (![self loadVersionNamed:name error:error]) return NO;
  /* Switching the version being edited is not an edit; what was recorded
     against the other version's objects cannot be replayed on these. */
  [[self undoManager] removeAllActions];
  return YES;
}

- (void)makeEditedVersionCurrent
{
  if ([self.currentVersionName isEqualToString:self.editedVersionName]) return;
  [self beginEdit:@"Set Current Version"];
  [[self inverse] setCurrentVersionName:self.currentVersionName];
  self.currentVersionName = self.editedVersionName;
  [self noteModelChanged];
  [self endEdit];
}

#pragma mark - Validation / compilation

- (BOOL)validateModel:(NSError **)error warnings:(NSArray **)warnings
{
  NSMutableArray *collected = [NSMutableArray array];
  [CDModelCompiler setWarningHandler:^(NSString *message) {
    [collected addObject:message];
  }];

  NSError *localError = nil;
  NSString *xml = [self serializedEditedVersion:&localError];
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

- (BOOL)compileToMomd:(NSError **)error momdPath:(NSString **)momdPath
{
  NSString *sourcePath = self.fileURL.path;
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

#pragma mark - Package IO

- (BOOL)ingestVersionXML:(NSString *)xml
                   named:(NSString *)name
          currentVersion:(NSString *)current
                   error:(NSError **)error
{
  _versionXML[name] = xml;
  if ([name isEqualToString:current])
    return [self loadVersionNamed:name error:error];
  return YES;
}

- (BOOL)finishReadWithCurrentVersion:(NSString *)current error:(NSError **)error
{
  if (_versionXML.count == 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:3 userInfo:@{
        NSLocalizedDescriptionKey: @"This package has no .xcdatamodel version."
      }];
    }
    return NO;
  }
  if (!current.length || _versionXML[current] == nil)
    current = [self versionNames].firstObject;
  self.currentVersionName = current;
  if (![self loadVersionNamed:current error:error]) return NO;
  [[self undoManager] removeAllActions];
  return YES;
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
  (void)typeName;
  NSString *path = url.path;
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDir = NO;
  if (![fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:4 userInfo:@{
        NSLocalizedDescriptionKey: @"Expected a .xcdatamodeld or .xcdatamodel directory."
      }];
    }
    return NO;
  }

  _versionXML = [NSMutableDictionary dictionary];

  /* A bare .xcdatamodel: a directory with a contents file. */
  NSString *bareContents = [path stringByAppendingPathComponent:@"contents"];
  if ([fm fileExistsAtPath:bareContents]) {
    NSString *xml = [NSString stringWithContentsOfFile:bareContents
                                              encoding:NSUTF8StringEncoding
                                                 error:error];
    if (!xml) return NO;
    NSString *name = path.lastPathComponent;
    if (![name.pathExtension isEqualToString:@"xcdatamodel"])
      name = @"Model.xcdatamodel";
    _versionXML[name] = xml;
    return [self finishReadWithCurrentVersion:name error:error];
  }

  NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:
      [path stringByAppendingPathComponent:@".xccurrentversion"]];
  NSString *current = plist[kCurrentVersionKey];

  for (NSString *name in [fm contentsOfDirectoryAtPath:path error:NULL]) {
    if (![name.pathExtension isEqualToString:@"xcdatamodel"]) continue;
    NSString *contentsPath = [[path stringByAppendingPathComponent:name]
        stringByAppendingPathComponent:@"contents"];
    NSString *xml = [NSString stringWithContentsOfFile:contentsPath
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    if (xml.length) _versionXML[name] = xml;
  }
  return [self finishReadWithCurrentVersion:current error:error];
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)wrapper ofType:(NSString *)typeName error:(NSError **)error
{
  (void)typeName;
  _versionXML = [NSMutableDictionary dictionary];
  NSDictionary *children = wrapper.fileWrappers;
  NSString *current = nil;

  NSFileWrapper *plistWrap = children[@".xccurrentversion"];
  if ([plistWrap isRegularFile]) {
    NSDictionary *plist = [NSPropertyListSerialization
        propertyListWithData:plistWrap.regularFileContents
                     options:0
                      format:NULL
                       error:NULL];
    current = plist[kCurrentVersionKey];
  }

  /* Bare .xcdatamodel wrapper. */
  NSFileWrapper *bare = children[@"contents"];
  if ([bare isRegularFile]) {
    NSString *xml = [[NSString alloc] initWithData:bare.regularFileContents
                                          encoding:NSUTF8StringEncoding];
    NSString *name = wrapper.preferredFilename ?: @"Model.xcdatamodel";
    if (![name.pathExtension isEqualToString:@"xcdatamodel"])
      name = @"Model.xcdatamodel";
    _versionXML[name] = xml;
    return [self finishReadWithCurrentVersion:name error:error];
  }

  for (NSString *name in children) {
    if (![name.pathExtension isEqualToString:@"xcdatamodel"]) continue;
    NSFileWrapper *contents = [children[name] fileWrappers][@"contents"];
    if (![contents isRegularFile]) continue;
    NSString *xml = [[NSString alloc] initWithData:contents.regularFileContents
                                          encoding:NSUTF8StringEncoding];
    if (xml.length) _versionXML[name] = xml;
  }
  return [self finishReadWithCurrentVersion:current error:error];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
  (void)typeName;
  if (![self snapshotEditedVersion:error]) return NO;

  NSString *path = url.path;
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:path]) {
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error])
      return NO;
  }

  for (NSString *name in _versionXML) {
    NSString *versionDir = [path stringByAppendingPathComponent:name];
    if (![fm fileExistsAtPath:versionDir]) {
      if (![fm createDirectoryAtPath:versionDir withIntermediateDirectories:YES attributes:nil error:error])
        return NO;
    }
    if (![_versionXML[name] writeToFile:[versionDir stringByAppendingPathComponent:@"contents"]
                             atomically:YES
                               encoding:NSUTF8StringEncoding
                                  error:error])
      return NO;
  }

  NSDictionary *plist = @{ kCurrentVersionKey: self.currentVersionName ?: self.editedVersionName };
  NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:NULL];
  if (![plistData writeToFile:[path stringByAppendingPathComponent:@".xccurrentversion"]
                   atomically:YES]) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:5 userInfo:@{
        NSLocalizedDescriptionKey: @"Could not write .xccurrentversion."
      }];
    }
    return NO;
  }
  return YES;
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError **)error
{
  (void)typeName;
  if (![self snapshotEditedVersion:error]) return nil;

  NSFileWrapper *root = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];

  for (NSString *name in _versionXML) {
    NSFileWrapper *contents = [[NSFileWrapper alloc] initRegularFileWithContents:
        [_versionXML[name] dataUsingEncoding:NSUTF8StringEncoding]];
    contents.preferredFilename = @"contents";
    NSFileWrapper *versionDir = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
    versionDir.preferredFilename = name;
    [versionDir addFileWrapper:contents];
    [root addFileWrapper:versionDir];
  }

  NSDictionary *plist = @{ kCurrentVersionKey: self.currentVersionName ?: self.editedVersionName };
  NSFileWrapper *current = [[NSFileWrapper alloc] initRegularFileWithContents:
      [NSPropertyListSerialization dataWithPropertyList:plist
                                                 format:NSPropertyListXMLFormat_v1_0
                                                options:0
                                                  error:NULL]];
  current.preferredFilename = @".xccurrentversion";
  [root addFileWrapper:current];
  return root;
}

@end
