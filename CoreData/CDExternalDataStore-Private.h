/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/CDExternalDataStore.h>
#import <Foundation/NSData.h>

/* A value of a CDFileExternalDataStore, read only when its bytes are
   first needed - as Apple's _PFExternalReferenceData: a row that holds
   one costs a name, not the value, until someone looks.  Its length is
   the file's size.  A file gone by then is an exception, Apple's. */
@interface CDExternalReferenceData : NSData {
    CDFileExternalDataStore *_store;
    NSString *_name;
    NSData *_contents;
    NSUInteger _length;
    BOOL _knowsLength;
}

- (instancetype)initWithStore:(CDFileExternalDataStore *)store name:(NSString *)name;
- (id<CDExternalDataStore>)_externalDataStore;
- (NSString *)_externalDataName;

@end
