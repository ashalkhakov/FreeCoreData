/* ModelBuilder document — a .xcdatamodeld package (see MBDocument.h).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBDocument.h"
#import "MBWindowController.h"

static NSString *const kCurrentVersionKey = @"_XCCurrentVersionName";

@implementation MBDocument {
  /* version file name -> contents XML.  The edited version's entry is
     refreshed from the model editor on save/switch; other versions ride
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
  /* Grouping by event is off: every edit opens its own group (see
     MBModelEditor's "Undo"), so one user action is one undo step however
     the run loop turns, and edits made without a running run loop (the
     tests) group the same. */
  NSUndoManager *undo = [[NSUndoManager alloc] init];
  [undo setGroupsByEvent:NO];
  [self setUndoManager:undo];
  _versionXML = [NSMutableDictionary dictionary];
  _modelEditor = [[MBModelEditor alloc] initWithUndoManager:undo];
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

/* Versions: the version XML dictionary holds immutable strings, so its
   copy is cheap and carries the others through; the edited version is
   the model editor's. */
- (void)restoreVersions:(NSDictionary *)versions
                 edited:(NSString *)edited
                current:(NSString *)current
                  model:(NSManagedObjectModel *)model
                layouts:(NSDictionary *)layouts
{
  [_modelEditor beginEdit:nil];
  [[_modelEditor inverseFor:self] restoreVersions:[_versionXML copy]
                                           edited:self.editedVersionName
                                          current:self.currentVersionName
                                            model:_modelEditor.model
                                          layouts:[_modelEditor.entityLayouts copy]];
  [_versionXML setDictionary:versions];
  self.editedVersionName = edited;
  self.currentVersionName = current;
  [_modelEditor replaceModel:model layouts:layouts];
  [_modelEditor endEdit];
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

#pragma mark - Version XML

/* Refresh the cache entry for the version being edited. */
- (BOOL)snapshotEditedVersion:(NSError **)error
{
  NSString *xml = [_modelEditor contentsXML:error];
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
  if (![_modelEditor readContentsXML:xml error:error]) return NO;
  self.editedVersionName = name;
  return YES;
}

#pragma mark - Versions (Xcode Editor menu)

- (NSString *)addModelVersion
{
  NSDictionary *versions = [_versionXML copy];
  NSString *edited = self.editedVersionName, *current = self.currentVersionName;
  NSManagedObjectModel *model = _modelEditor.model;
  NSDictionary *layouts = [_modelEditor.entityLayouts copy];
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
  [_modelEditor beginEdit:@"Add Model Version"];
  [[_modelEditor inverseFor:self] restoreVersions:versions edited:edited current:current
                                            model:model layouts:layouts];
  [_modelEditor noteModelChanged];
  [_modelEditor endEdit];
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
  [_modelEditor beginEdit:@"Set Current Version"];
  [[_modelEditor inverseFor:self] setCurrentVersionName:self.currentVersionName];
  self.currentVersionName = self.editedVersionName;
  [_modelEditor noteModelChanged];
  [_modelEditor endEdit];
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
