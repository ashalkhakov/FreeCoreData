/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSSaveChangesRequest.h>
#import <Foundation/NSSet.h>

@implementation NSSaveChangesRequest

-initWithInsertedObjects:(NSSet *)insertedObjects updatedObjects:(NSSet *)updatedObjects deletedObjects:(NSSet *)deletedObjects lockedObjects:(NSSet *)lockedObjects {
   _insertedObjects=[insertedObjects copy];
   _updatedObjects=[updatedObjects copy];
   _deletedObjects=[deletedObjects copy];
   _lockedObjects=[lockedObjects copy];
   return self;
}

-(void)dealloc {
   [_insertedObjects release];
   [_updatedObjects release];
   [_deletedObjects release];
   [_lockedObjects release];
   [super dealloc];
}

-(NSPersistentStoreRequestType)requestType {
   return NSSaveRequestType;
}

-(NSSet *)insertedObjects {
   return _insertedObjects;
}

-(NSSet *)updatedObjects {
   return _updatedObjects;
}

-(NSSet *)deletedObjects {
   return _deletedObjects;
}

-(NSSet *)lockedObjects {
   return _lockedObjects;
}

-copyWithZone:(NSZone *)zone {
   NSSaveChangesRequest *result=[[[self class] allocWithZone:zone] initWithInsertedObjects:_insertedObjects updatedObjects:_updatedObjects deletedObjects:_deletedObjects lockedObjects:_lockedObjects];

   [result setAffectedStores:[self affectedStores]];

   return result;
}

@end
