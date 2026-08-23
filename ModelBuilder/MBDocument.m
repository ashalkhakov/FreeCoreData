/* ModelBuilder document — a .xcdatamodeld wrapper (current version).
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBDocument.h"
#import "MBWindowController.h"

static NSString *const kCurrentVersionKey = @"_XCCurrentVersionName";

@implementation MBDocument {
  NSFileWrapper *_originalWrapper;
  NSString *_sourcePath;
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
  _model = [[MBModel alloc] init];
  [_model addEntityNamed:@"Entity"];
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

#pragma mark - Package IO

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
  (void)typeName;
  NSString *path = url.path;
  BOOL isDir = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:4 userInfo:@{
        NSLocalizedDescriptionKey: @"Expected a .xcdatamodeld or .xcdatamodel directory."
      }];
    }
    return NO;
  }

  NSString *current = nil;
  NSString *plistPath = [path stringByAppendingPathComponent:@".xccurrentversion"];
  NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
  current = plist[kCurrentVersionKey];

  NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:NULL];
  if (!current.length) {
    for (NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
      if ([name.pathExtension isEqualToString:@"xcdatamodel"]) { current = name; break; }
    }
  }

  NSString *contentsPath = nil;
  if (current.length)
    contentsPath = [[path stringByAppendingPathComponent:current] stringByAppendingPathComponent:@"contents"];
  if (![[NSFileManager defaultManager] fileExistsAtPath:contentsPath])
    contentsPath = [path stringByAppendingPathComponent:@"contents"];

  NSString *xml = [NSString stringWithContentsOfFile:contentsPath encoding:NSUTF8StringEncoding error:error];
  if (!xml) return NO;

  MBModel *model = [[MBModel alloc] init];
  model.versionName = current.length ? current : @"Model.xcdatamodel";
  if (![model loadFromXMLString:xml error:error]) return NO;
  self.model = model;
  _sourcePath = [path copy];
  return YES;
}

- (void)copySiblingVersionsFrom:(NSString *)src to:(NSString *)dst currentVersion:(NSString *)version
{
  if (!src.length || !dst.length || [src isEqualToString:dst]) return;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *names = [fm contentsOfDirectoryAtPath:src error:NULL];
  for (NSString *name in names) {
    if ([name isEqualToString:@".xccurrentversion"]) continue;
    if ([name isEqualToString:version]) continue;
    if ([name isEqualToString:@"contents"]) continue;
    if (![name.pathExtension isEqualToString:@"xcdatamodel"]) continue;
    NSString *from = [src stringByAppendingPathComponent:name];
    NSString *to = [dst stringByAppendingPathComponent:name];
    if ([fm fileExistsAtPath:to]) continue;
    [fm copyItemAtPath:from toPath:to error:NULL];
  }
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
  (void)typeName;
  NSString *path = url.path;
  NSString *version = self.model.versionName.length ? self.model.versionName : @"Model.xcdatamodel";
  if (![version.pathExtension isEqualToString:@"xcdatamodel"])
    version = [version stringByAppendingPathExtension:@"xcdatamodel"];

  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:path]) {
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error])
      return NO;
  }

  NSString *versionDir = [path stringByAppendingPathComponent:version];
  if (![fm fileExistsAtPath:versionDir]) {
    if (![fm createDirectoryAtPath:versionDir withIntermediateDirectories:YES attributes:nil error:error])
      return NO;
  }

  NSString *contentsPath = [versionDir stringByAppendingPathComponent:@"contents"];
  if (![[self.model XMLString] writeToFile:contentsPath atomically:YES encoding:NSUTF8StringEncoding error:error])
    return NO;

  NSString *origin = _sourcePath.length ? _sourcePath : self.fileURL.path;
  [self copySiblingVersionsFrom:origin to:path currentVersion:version];

  NSDictionary *plist = @{ kCurrentVersionKey: version };
  NSString *plistPath = [path stringByAppendingPathComponent:@".xccurrentversion"];
  if (![plist writeToFile:plistPath atomically:YES]) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:5 userInfo:@{
        NSLocalizedDescriptionKey: @"Could not write .xccurrentversion."
      }];
    }
    return NO;
  }
  _sourcePath = [path copy];
  return YES;
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)wrapper ofType:(NSString *)typeName error:(NSError **)error
{
  (void)typeName;
  _originalWrapper = wrapper;
  NSDictionary *children = wrapper.fileWrappers;
  NSString *current = nil;

  NSFileWrapper *plistWrap = children[@".xccurrentversion"];
  if (plistWrap.regularFile) {
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:plistWrap.regularFileContents
                                                                    options:0
                                                                     format:NULL
                                                                      error:NULL];
    current = plist[kCurrentVersionKey];
  }

  if (!current.length) {
    for (NSString *name in [[children allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
      if ([name.pathExtension isEqualToString:@"xcdatamodel"]) {
        current = name;
        break;
      }
    }
  }

  /* A bare .xcdatamodel (directory with a "contents" file) is also accepted. */
  NSFileWrapper *versionWrap = current.length ? children[current] : nil;
  NSFileWrapper *contentsWrap = versionWrap.fileWrappers[@"contents"] ?: children[@"contents"];
  if (!contentsWrap.regularFile) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:3 userInfo:@{
        NSLocalizedDescriptionKey:
            @"This package has no current .xcdatamodel/contents file."
      }];
    }
    return NO;
  }

  NSString *xml = [[NSString alloc] initWithData:contentsWrap.regularFileContents
                                        encoding:NSUTF8StringEncoding];
  MBModel *model = [[MBModel alloc] init];
  model.versionName = current.length ? current : @"Model.xcdatamodel";
  if (![model loadFromXMLString:xml error:error]) return NO;
  self.model = model;
  return YES;
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)typeName error:(NSError **)error
{
  (void)typeName;
  (void)error;
  NSString *version = self.model.versionName.length ? self.model.versionName : @"Model.xcdatamodel";
  if (![version.pathExtension isEqualToString:@"xcdatamodel"])
    version = [version stringByAppendingPathExtension:@"xcdatamodel"];

  NSData *xml = [[self.model XMLString] dataUsingEncoding:NSUTF8StringEncoding];
  NSFileWrapper *contents = [[NSFileWrapper alloc] initRegularFileWithContents:xml];
  contents.preferredFilename = @"contents";

  NSFileWrapper *versionDir = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
  versionDir.preferredFilename = version;
  [versionDir addFileWrapper:contents];

  NSDictionary *plist = @{ kCurrentVersionKey: version };
  NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:NULL];
  NSFileWrapper *current = [[NSFileWrapper alloc] initRegularFileWithContents:plistData];
  current.preferredFilename = @".xccurrentversion";

  NSFileWrapper *root = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
  /* Keep sibling versions from the originally opened package. */
  if (_originalWrapper.isDirectory) {
    [_originalWrapper.fileWrappers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSFileWrapper *child, BOOL *stop) {
      (void)stop;
      if ([name isEqualToString:@".xccurrentversion"]) return;
      if ([name isEqualToString:version]) return;
      if ([name isEqualToString:@"contents"]) return;
      NSFileWrapper *copy = [[NSFileWrapper alloc] initWithSerializedRepresentation:child.serializedRepresentation];
      if (copy) {
        copy.preferredFilename = name;
        [root addFileWrapper:copy];
      }
    }];
  }
  [root addFileWrapper:versionDir];
  [root addFileWrapper:current];
  return root;
}

@end
