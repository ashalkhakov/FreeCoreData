/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>

@class NSData, NSString, NSError;

/* Where a store keeps the binary values it keeps outside its rows: those
   of attributes that allow external storage, larger than 128 KiB.  A
   FreeCoreData addition - Apple's stores keep them in files beside a
   SQLite store, and so does this framework's unless told otherwise.

   A store is given one with CDExternalDataStoreOption among its options:
   the SQLite store instead of its directory, and the PostgreSQL and
   MySQL stores, which keep every value in its row without one.  An
   object kept in S3, say, suits a server.

   The store names each value (a UUID) and remembers the name in the
   row; the external data store keeps the bytes.  It is called from the
   store's own requests, under the coordinator's lock. */
@protocol CDExternalDataStore <NSObject>

/* Keeps data under name.  A value is written before the request that
   writes its row is committed, and taken away again if that fails. */
- (BOOL)writeData:(NSData *)data named:(NSString *)name error:(NSError **)error;

/* The data kept under name.  It may be read only when its bytes are
   first needed (the file store's is); if it is not there by then, that
   is an exception. */
- (NSData *)dataNamed:(NSString *)name;

/* Takes away what is kept under name: when the request that let go of it
   (a row deleted, a value written over) is committed.  Taking away what
   is not there is no error. */
- (BOOL)removeDataNamed:(NSString *)name error:(NSError **)error;

@optional

/* Takes away everything kept: when the store is destroyed. */
- (BOOL)removeAllDataWithError:(NSError **)error;

/* Keeps under newName a copy of what is kept under name: when a value
   read from this store is given to another row.  Without it the copy is
   written from the value's bytes. */
- (BOOL)copyDataNamed:(NSString *)name toName:(NSString *)newName error:(NSError **)error;

@end

/* The option (an object conforming to CDExternalDataStore) that tells a
   store where to keep its external values. */
COREDATA_EXPORT NSString *const CDExternalDataStoreOption;

/* Values kept as files in a directory, made when the first is written.
   What a SQLite store uses by default, in .<name>_SUPPORT/_EXTERNAL_DATA
   beside its file, as Apple's does. */
@interface CDFileExternalDataStore : NSObject <CDExternalDataStore> {
    NSString *_directory;
}

- (instancetype)initWithDirectory:(NSString *)directory;
- (NSString *)directory;

@end
