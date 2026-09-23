/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>

@class NSDictionary;

/* An opaque bookmark into a store's persistent history: archive it
   (NSSecureCoding) to remember how far history has been processed, and
   hand it back to NSPersistentHistoryChangeRequest to fetch what came
   after or purge what came before.  Internally one transaction number
   per store identifier. */
@interface NSPersistentHistoryToken : NSObject <NSCopying, NSSecureCoding> {
    NSDictionary *_positions;   /* store identifier -> NSNumber (transaction number) */
}


/* --- Building and reading a token (a FreeCoreData addition) ---------
 
   Apple publishes nothing on this class at all, which leaves a persistent
   store outside the framework unable to answer a history request: it can
   neither say where its history has reached nor read the anchor it was
   given.  These two do that, and nothing else.  Code that must also build
   against Apple's CoreData should test for them with -respondsToSelector:
   and treat their absence as "history is not supported here". */

/* A token recording how far each store has got, keyed by store identifier
   with NSNumber transaction numbers. */
+ (instancetype)tokenWithTransactionNumbersByStoreIdentifier:(NSDictionary *)numbers;

/* The transaction number this token records for one store, or 0 when it
   records nothing for it. */
- (int64_t)transactionNumberForStoreIdentifier:(NSString *)identifier;

@end
