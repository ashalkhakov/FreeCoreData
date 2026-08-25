/* ModelBuilder document — .xcdatamodeld editing over CDModelCompiler /
   CDModelSerializer (momc's parser and its inverse), so the editor,
   the compiler and the runtime share one schema implementation.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBDocument.h"
#import "MBWindowController.h"
#import "CDModelCompiler.h"
#import "CDModelSerializer.h"

static NSString *const kCurrentVersionKey = @"_XCCurrentVersionName";

@implementation MBDocument {
  /* version file name -> contents XML.  The edited version's entry is
     refreshed from the live model on save/switch; other versions ride
     along verbatim. */
  NSMutableDictionary *_versionXML;
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
  MBWindowController *controller = [[MBWindowController alloc] initWithWindowNibName:@"MBDocument"];
  [self addWindowController:controller];
}

- (void)noteModelChanged
{
  [self updateChangeCount:NSChangeDone];
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

- (BOOL)performXMLMutation:(void (^)(NSXMLElement *root))mutation
                     error:(NSError **)error
{
  NSString *xml = [self serializedEditedVersion:error];
  if (!xml) return NO;

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:error];
  if (!doc) return NO;
  mutation([doc rootElement]);

  NSString *mutated = [doc XMLStringWithOptions:NSXMLNodePrettyPrint];
  NSManagedObjectModel *model = [CDModelCompiler compileModelContentsXML:mutated error:error];
  if (!model) return NO;

  self.model = model;
  self.entityLayouts = layoutsFromContentsXML(mutated);
  [self noteModelChanged];
  return YES;
}

#pragma mark - Versions (Xcode Editor menu)

- (NSString *)addModelVersion
{
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
  [self noteModelChanged];
  return candidate;
}

- (BOOL)switchToVersion:(NSString *)name error:(NSError **)error
{
  if ([name isEqualToString:self.editedVersionName]) return YES;
  if (![self snapshotEditedVersion:error]) return NO;
  return [self loadVersionNamed:name error:error];
}

- (void)makeEditedVersionCurrent
{
  if ([self.currentVersionName isEqualToString:self.editedVersionName]) return;
  self.currentVersionName = self.editedVersionName;
  [self noteModelChanged];
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
  return [self loadVersionNamed:current error:error];
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
