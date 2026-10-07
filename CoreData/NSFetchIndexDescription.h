/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>

@class NSString, NSArray, NSPredicate, NSEntityDescription;

/* A fetch index of an entity (Xcode's Fetch Index): named, made of
   NSFetchIndexElementDescriptions, and optionally partial - covering only
   the rows a predicate accepts.  A store builds it when it creates its
   schema.  Indexes take no part in an entity's version hash, so adding or
   removing one never calls for a migration. */
@interface NSFetchIndexDescription : NSObject <NSCoding, NSCopying> {
    NSString *_name;
    NSArray *_elements;
    NSEntityDescription *_entity;                 /* not retained */
    NSPredicate *_partialIndexPredicate;
}

- (instancetype)initWithName:(NSString *)name elements:(NSArray *)elements;

- (NSString *)name;
- (void)setName:(NSString *)value;

/* Setting the elements makes each one this index's. */
- (NSArray *)elements;
- (void)setElements:(NSArray *)value;

/* Set by -[NSEntityDescription setIndexes:]. */
- (NSEntityDescription *)entity;

- (NSPredicate *)partialIndexPredicate;
- (void)setPartialIndexPredicate:(NSPredicate *)value;

@end
