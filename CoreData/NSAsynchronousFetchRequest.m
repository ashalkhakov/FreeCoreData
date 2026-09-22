/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSAsynchronousFetchRequest.h"
#import <CoreData/NSFetchRequest.h>
#import <Foundation/Foundation.h>

@implementation NSAsynchronousFetchRequest

-(instancetype)initWithFetchRequest:(NSFetchRequest *)request
                    completionBlock:(NSPersistentStoreAsynchronousFetchResultCompletionBlock)blk {
   _fetchRequest=[request retain];
   _completionBlock=[blk copy];
   _estimatedResultCount=0;
   return self;
}

-(void)dealloc {
   [_fetchRequest release];
   [_completionBlock release];
   [super dealloc];
}

-(NSPersistentStoreRequestType)requestType {
   return NSFetchRequestType;
}

-(NSFetchRequest *)fetchRequest {
   return _fetchRequest;
}

-(NSPersistentStoreAsynchronousFetchResultCompletionBlock)completionBlock {
   return _completionBlock;
}

-(NSInteger)estimatedResultCount {
   return _estimatedResultCount;
}

-(void)setEstimatedResultCount:(NSInteger)count {
   _estimatedResultCount=count;
}

-copyWithZone:(NSZone *)zone {
   NSAsynchronousFetchRequest *result=[super copyWithZone:zone];

   result->_fetchRequest=[_fetchRequest retain];
   result->_completionBlock=[_completionBlock copy];
   result->_estimatedResultCount=_estimatedResultCount;
   return result;
}

@end
