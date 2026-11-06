/* ModelBuilder mapping document.  See MBMappingDocument.h.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBMappingDocument.h"
#import "MBMappingEditor.h"
#import "MBMappingWindowController.h"

@implementation MBMappingDocument

+ (BOOL)autosavesInPlace
{
  return NO;
}

+ (NSArray *)readableTypes
{
  return @[ @"xcmappingmodel", @"Core Data Mapping Model" ];
}

+ (NSArray *)writableTypes
{
  return @[ @"xcmappingmodel", @"Core Data Mapping Model" ];
}

- (NSString *)fileType
{
  return @"Core Data Mapping Model";
}

/* Grouping by event is off, as MBDocument's: every edit opens its own
   group (see MBMappingEditor's undo), so one user action is one undo step
   however the run loop turns.  A document's change count follows its
   undo manager: NSDocument counts a change when a group closes and takes
   it back when it is undone. */
- (instancetype)init
{
  if ((self = [super init])) {
    NSUndoManager *undo = [[NSUndoManager alloc] init];
    [undo setGroupsByEvent:NO];
    [self setUndoManager:undo];
  }
  return self;
}

- (void)setUndoManager:(NSUndoManager *)undoManager
{
  [super setUndoManager:undoManager];
  if (!_mappingEditor) _mappingEditor = [[MBMappingEditor alloc] initWithUndoManager:undoManager];
  _mappingEditor.undoManager = undoManager;
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
  (void)type;
  NSString *path = [url path];
  NSString *xml = [NSString stringWithContentsOfFile:[path stringByAppendingPathComponent:@"xcmapping.xml"]
                                            encoding:NSUTF8StringEncoding
                                               error:error];
  if (xml == nil) return NO;
  [[self undoManager] disableUndoRegistration];
  BOOL read = [_mappingEditor readXMLString:xml atPath:path error:error];
  [[self undoManager] enableUndoRegistration];
  return read;
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
  (void)type;
  NSString *xml = [_mappingEditor XMLString:error];
  if (xml == nil) return NO;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:[url path]
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error])
    return NO;
  return [xml writeToFile:[[url path] stringByAppendingPathComponent:@"xcmapping.xml"]
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:error];
}

- (void)makeWindowControllers
{
  [self addWindowController:[[MBMappingWindowController alloc] init]];
}

@end
