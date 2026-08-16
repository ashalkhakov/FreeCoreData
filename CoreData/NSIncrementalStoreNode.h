/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <stdint.h>

@class NSManagedObjectID, NSDictionary, NSPropertyDescription;

/* A concrete class representing a single record (row) fetched from an
   incremental store.  Values are keyed by property name: attribute values
   are the attribute objects themselves, to-one relationship values are
   NSManagedObjectIDs.  To-many relationships are not stored in nodes; they
   are obtained via -[NSIncrementalStore newValueForRelationship:...]. */
@interface NSIncrementalStoreNode : NSObject {
    NSManagedObjectID *_objectID;
    NSDictionary *_values;
    uint64_t _version;
}

- initWithObjectID:(NSManagedObjectID *)objectID withValues:(NSDictionary *)values version:(uint64_t)version;

- (void)updateWithValues:(NSDictionary *)values version:(uint64_t)version;

- (NSManagedObjectID *)objectID;
- (uint64_t)version;

- (id)valueForPropertyDescription:(NSPropertyDescription *)prop;

@end
