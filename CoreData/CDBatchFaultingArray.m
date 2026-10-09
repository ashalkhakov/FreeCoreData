/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "CDBatchFaultingArray.h"
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/NSFetchRequest.h>
#import <CoreData/NSManagedObject.h>
#import "NSManagedObjectContext-Private.h"
#import <Foundation/NSException.h>
#include <stdlib.h>

@implementation CDBatchFaultingArray

- (instancetype)initWithObjectIDs:(NSArray *)objectIDs
                            store:(NSPersistentStore *)store
                          context:(NSManagedObjectContext *)context
                          request:(NSFetchRequest *)request {
   if((self=[super init])==nil)
    return nil;
   _objectIDs=[objectIDs copy];
   _store=[store retain];
   _context=[context retain];
   _request=[request copy];
   _batchSize=[request fetchBatchSize];
   _objects=calloc(MAX([_objectIDs count],(NSUInteger)1),sizeof(id));
   return self;
}

-(void)dealloc {
   NSUInteger i,count=[_objectIDs count];

   for(i=0;i<count;i++)
    [_objects[i] release];
   free(_objects);
   [_objectIDs release];
   [_store release];
   [_context release];
   [_request release];
   [super dealloc];
}

-(NSUInteger)count {
   return [_objectIDs count];
}

/* The context finalizes each batch as it is read, not the whole answer. */
-(BOOL)_finalizesItsBatches {
   return YES;
}

-(void)_readBatchAtIndex:(NSUInteger)index {
   NSUInteger                    start=index-index%_batchSize;
   NSUInteger                    end=MIN(start+_batchSize,[_objectIDs count]);
   NSPersistentStoreCoordinator *coordinator=[_context persistentStoreCoordinator];
   NSMutableArray               *batch=[NSMutableArray arrayWithCapacity:end-start];
   NSUInteger                    i;

   [coordinator lock];
   NS_DURING
    for(i=start;i<end;i++)
     [batch addObject:[_context objectWithID:[_objectIDs objectAtIndex:i]]];
    if([_request includesPropertyValues])
     [_context _prefetchRowsForObjects:batch fromStore:_store];
   NS_HANDLER
    [coordinator unlock];
    [localException raise];
   NS_ENDHANDLER
   [coordinator unlock];

   for(i=start;i<end;i++)
    _objects[i]=[[batch objectAtIndex:i-start] retain];

   [_context _finalizeFetchedObjects:batch request:_request];
}

-(id)objectAtIndex:(NSUInteger)index {
   if(index>=[_objectIDs count])
    [NSException raise:NSRangeException format:@"index %lu beyond bounds [0 .. %ld]",(unsigned long)index,(long)[_objectIDs count]-1];

   if(_objects[index]==nil)
    [self _readBatchAtIndex:index];

   return _objects[index];
}

/* Found by ID, without reading any batch: an object of this context is
   the one registered for its ID. */
-(NSUInteger)indexOfObject:(id)object {
   if(![object isKindOfClass:[NSManagedObject class]] || [object managedObjectContext]!=_context)
    return NSNotFound;
   return [_objectIDs indexOfObject:[object objectID]];
}

-(BOOL)containsObject:(id)object {
   return [self indexOfObject:object]!=NSNotFound;
}

@end
