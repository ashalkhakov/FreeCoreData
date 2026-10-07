/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>

@class NSString, NSPropertyDescription, NSFetchIndexDescription;

/* How an element is indexed: by its value (an ordinary B-tree index), or
   as a range in an R-tree, which answers "inside this region" queries.
   An R-tree element must be an Integer 16, Integer 32 or Float
   attribute.  Apple's SQLite store builds no R-tree index on macOS, and
   neither does this port's; the type is kept in the model. */
typedef NS_ENUM(NSUInteger, NSFetchIndexElementType) {
    NSFetchIndexElementTypeBinary = 0,
    NSFetchIndexElementTypeRTree = 1,
};

/* One column of a fetch index: an attribute, a relationship (its foreign
   key), or an NSExpressionDescription, in ascending or descending order. */
@interface NSFetchIndexElementDescription : NSObject <NSCoding, NSCopying> {
    NSPropertyDescription *_property;
    NSString *_propertyName;
    NSFetchIndexElementType _collationType;
    BOOL _ascending;
    NSFetchIndexDescription *_indexDescription;   /* not retained */
}

/* Raises for a property with no name, and for an R-tree element on
   anything but an Integer 16, Integer 32 or Float attribute. */
- (instancetype)initWithProperty:(NSPropertyDescription *)property
                   collationType:(NSFetchIndexElementType)collationType;

/* The property, found again by name in the index's entity when the
   element was decoded from a model. */
- (NSPropertyDescription *)property;
- (NSString *)propertyName;

- (NSFetchIndexElementType)collationType;
- (void)setCollationType:(NSFetchIndexElementType)value;

/* YES unless set otherwise. */
- (BOOL)isAscending;
- (void)setAscending:(BOOL)value;

- (NSFetchIndexDescription *)indexDescription;

@end
