/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* CoreDataVersioning-Private.h - deterministic digest used for model
   version hashes.

   The hashes produced here are NOT compatible with Apple's Core Data
   version hashes; they only need to be stable and self-consistent so that
   a store created by this framework can be checked for model
   compatibility later. The digest is a 16-byte value built from two
   independent 64-bit FNV-1a lanes over the UTF-8 canonical description of
   the hashed components. */

#ifndef COREDATA_VERSIONING_PRIVATE_H
#define COREDATA_VERSIONING_PRIVATE_H

#import <Foundation/Foundation.h>
#include <stdint.h>

static inline NSData *_NSCoreDataDigestForComponents(NSArray *components) {
   /* The unit separator makes the canonical form unambiguous. */
   NSString *canonical=[components componentsJoinedByString:@"\x1f"];
   NSData   *utf8=[canonical dataUsingEncoding:NSUTF8StringEncoding];
   const uint8_t *bytes=(const uint8_t *)[utf8 bytes];
   NSUInteger     i,length=[utf8 length];

   uint64_t lane0=0xcbf29ce484222325ULL; /* FNV-1a offset basis */
   uint64_t lane1=0x84222325cbf29ce4ULL; /* rotated basis for the 2nd lane */

   for(i=0;i<length;i++){
    lane0=(lane0^bytes[i])*0x100000001b3ULL;
    lane1=(lane1^bytes[length-1-i])*0x100000001b3ULL;
   }

   uint8_t digest[16];
   for(i=0;i<8;i++){
    digest[i]=(uint8_t)(lane0>>(i*8));
    digest[8+i]=(uint8_t)(lane1>>(i*8));
   }

   return [NSData dataWithBytes:digest length:sizeof(digest)];
}

#endif /* COREDATA_VERSIONING_PRIVATE_H */
