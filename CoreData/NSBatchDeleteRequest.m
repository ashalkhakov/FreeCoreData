/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSBatchDeleteRequest.h"
#import "NSBatchDeleteRequest-Private.h"
#import <CoreData/NSFetchRequest.h>
#import <CoreData/NSManagedObjectID.h>
#import <Foundation/Foundation.h>

@implementation NSBatchDeleteRequest

-(instancetype)initWithFetchRequest:(NSFetchRequest *)fetch {
   _fetchRequest=[fetch copy];
   _resultType=NSBatchDeleteResultTypeStatusOnly;
   return self;
}

-(instancetype)initWithObjectIDs:(NSArray *)objects {
   _objectIDs=[objects copy];
   _resultType=NSBatchDeleteResultTypeStatusOnly;

   /* Mirror Apple's shape: an ID-based request still exposes a fetch
      request (entity of the first ID, SELF IN the IDs). */
   if([objects count]>0){
    NSFetchRequest *fetch=[[[NSFetchRequest alloc] init] autorelease];

    [fetch setEntity:[(NSManagedObjectID *)[objects objectAtIndex:0] entity]];
    [fetch setPredicate:[NSPredicate predicateWithFormat:@"SELF IN %@",objects]];
    _fetchRequest=[fetch copy];
   }
   return self;
}

-(void)dealloc {
   [_fetchRequest release];
   [_objectIDs release];
   [super dealloc];
}

-(NSPersistentStoreRequestType)requestType {
   return NSBatchDeleteRequestType;
}

-(NSFetchRequest *)fetchRequest {
   return _fetchRequest;
}

-(NSBatchDeleteRequestResultType)resultType {
   return _resultType;
}

-(void)setResultType:(NSBatchDeleteRequestResultType)resultType {
   _resultType=resultType;
}

-copyWithZone:(NSZone *)zone {
   NSBatchDeleteRequest *result=[super copyWithZone:zone];

   result->_fetchRequest=[_fetchRequest copy];
   result->_objectIDs=[_objectIDs copy];
   result->_resultType=_resultType;
   return result;
}

@end

@implementation NSBatchDeleteRequest (CDPrivate)

-(NSArray *)_objectIDsToDelete {
   return _objectIDs;
}

@end
