/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "CDExternalDataStore-Private.h"
#import <Foundation/Foundation.h>

NSString * const CDExternalDataStoreOption=@"CDExternalDataStoreOption";

@implementation CDFileExternalDataStore

-(instancetype)initWithDirectory:(NSString *)directory {
   if((self=[super init])==nil)
    return nil;
   _directory=[directory copy];
   return self;
}

-(void)dealloc {
   [_directory release];
   [super dealloc];
}

-(NSString *)directory {
   return _directory;
}

-(NSString *)_pathOfName:(NSString *)name {
   return [_directory stringByAppendingPathComponent:name];
}

-(BOOL)writeData:(NSData *)data named:(NSString *)name error:(NSError **)error {
   if(![[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:error])
    return NO;
   return [data writeToFile:[self _pathOfName:name] options:0 error:error];
}

-(NSData *)dataNamed:(NSString *)name {
   return [[[CDExternalReferenceData alloc] initWithStore:self name:name] autorelease];
}

-(BOOL)removeDataNamed:(NSString *)name error:(NSError **)error {
   NSString *path=[self _pathOfName:name];

   if(![[NSFileManager defaultManager] fileExistsAtPath:path])
    return YES;
   return [[NSFileManager defaultManager] removeItemAtPath:path error:error];
}

-(BOOL)removeAllDataWithError:(NSError **)error {
   if(![[NSFileManager defaultManager] fileExistsAtPath:_directory])
    return YES;
   return [[NSFileManager defaultManager] removeItemAtPath:_directory error:error];
}

-(BOOL)copyDataNamed:(NSString *)name toName:(NSString *)newName error:(NSError **)error {
   if(![[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES attributes:nil error:error])
    return NO;
   return [[NSFileManager defaultManager] copyItemAtPath:[self _pathOfName:name] toPath:[self _pathOfName:newName] error:error];
}

@end

@implementation CDExternalReferenceData

-(instancetype)initWithStore:(CDFileExternalDataStore *)store name:(NSString *)name {
   if((self=[super init])==nil)
    return nil;
   _store=[store retain];
   _name=[name copy];
   return self;
}

/* What GNUstep's -[NSData init] asks a subclass for: nothing here. */
-initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)freeWhenDone {
   return self;
}

-(void)dealloc {
   [_store release];
   [_name release];
   [_contents release];
   [super dealloc];
}

-(id<CDExternalDataStore>)_externalDataStore {
   return _store;
}

-(NSString *)_externalDataName {
   return _name;
}

static void raiseMissingExternalFile(void){
   [NSException raise:NSInternalInconsistencyException format:@"External data reference can't find underlying file."];
}

-(NSData *)_contents {
   @synchronized(self){
    if(_contents==nil){
     _contents=[[NSData alloc] initWithContentsOfFile:[_store _pathOfName:_name] options:NSDataReadingMappedIfSafe error:NULL];
     if(_contents==nil)
      raiseMissingExternalFile();
    }
    return _contents;
   }
}

-(const void *)bytes {
   return [[self _contents] bytes];
}

-(NSUInteger)length {
   @synchronized(self){
    if(_contents!=nil)
     return [_contents length];
    if(!_knowsLength){
     NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:[_store _pathOfName:_name] error:NULL];

     if(attributes==nil)
      raiseMissingExternalFile();
     _length=(NSUInteger)[attributes fileSize];
     _knowsLength=YES;
    }
    return _length;
   }
}

-copyWithZone:(NSZone *)zone {
   return [self retain];
}

/* Told apart without reading either file where it can be: by the file,
   or by the lengths. */
-(BOOL)isEqualToData:(NSData *)other {
   if(other==self)
    return YES;
   if([other isKindOfClass:[CDExternalReferenceData class]] &&
      [(CDExternalReferenceData *)other _externalDataStore]==_store &&
      [[(CDExternalReferenceData *)other _externalDataName] isEqualToString:_name])
    return YES;
   if([other length]!=[self length])
    return NO;
   return [[self _contents] isEqualToData:other];
}

-(BOOL)isEqual:(id)other {
   return [other isKindOfClass:[NSData class]] && [self isEqualToData:other];
}

-(NSUInteger)hash {
   return [self length];
}

@end
