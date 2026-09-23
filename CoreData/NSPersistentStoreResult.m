/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSPersistentStoreResult.h"
#import "NSPersistentStoreResult-Private.h"
#import <Foundation/Foundation.h>

@implementation NSPersistentStoreResult
@end

@implementation NSPersistentStoreAsynchronousResult

-(void)dealloc {
   [_managedObjectContext release];
   [_operationError release];
   [_progress release];
   [super dealloc];
}

-(NSManagedObjectContext *)managedObjectContext {
   return _managedObjectContext;
}

-(NSError *)operationError {
   return _operationError;
}

-(NSProgress *)progress {
   return _progress;
}

/* Cancellation flows through the progress; the executing context
   checks it before running the fetch and reports
   NSUserCancelledError through operationError. */
-(void)cancel {
   [_progress cancel];
}

@end

@implementation NSAsynchronousFetchResult

-(void)dealloc {
   [_fetchRequest release];
   [_finalResult release];
   [super dealloc];
}

-(NSAsynchronousFetchRequest *)fetchRequest {
   return _fetchRequest;
}

-(NSArray *)finalResult {
   return _finalResult;
}

@end

@implementation NSAsynchronousFetchResult (CDPrivate)

-(instancetype)_initWithManagedObjectContext:(NSManagedObjectContext *)context
                                fetchRequest:(NSAsynchronousFetchRequest *)request
                                    progress:(NSProgress *)progress {
   _managedObjectContext=[context retain];
   _fetchRequest=[request retain];
   _progress=[progress retain];
   return self;
}

-(void)_setFinalResult:(NSArray *)result {
   result=[result retain];
   [_finalResult release];
   _finalResult=result;
}

-(void)_setOperationError:(NSError *)error {
   error=[error retain];
   [_operationError release];
   _operationError=error;
}

@end

@implementation NSBatchInsertResult

-(void)dealloc {
   [_result release];
   [super dealloc];
}

-(id)result {
   return _result;
}

-(NSBatchInsertRequestResultType)resultType {
   return _resultType;
}

@end

@implementation NSBatchInsertResult (CDPrivate)

-(instancetype)_initWithResult:(id)result resultType:(NSBatchInsertRequestResultType)resultType {
   _result=[result retain];
   _resultType=resultType;
   return self;
}

@end

@implementation NSBatchUpdateResult

-(void)dealloc {
   [_result release];
   [super dealloc];
}

-(id)result {
   return _result;
}

-(NSBatchUpdateRequestResultType)resultType {
   return _resultType;
}

@end

@implementation NSBatchUpdateResult (CDPrivate)

-(instancetype)_initWithResult:(id)result resultType:(NSBatchUpdateRequestResultType)resultType {
   _result=[result retain];
   _resultType=resultType;
   return self;
}

@end

@implementation NSBatchDeleteResult

-(void)dealloc {
   [_result release];
   [super dealloc];
}

-(id)result {
   return _result;
}

-(NSBatchDeleteRequestResultType)resultType {
   return _resultType;
}

@end

@implementation NSBatchDeleteResult (CDPrivate)

-(instancetype)_initWithResult:(id)result resultType:(NSBatchDeleteRequestResultType)resultType {
   _result=[result retain];
   _resultType=resultType;
   return self;
}

@end

@implementation NSPersistentHistoryResult

-(void)dealloc {
   [_result release];
   [super dealloc];
}

-(id)result {
   return _result;
}

-(NSPersistentHistoryResultType)resultType {
   return _resultType;
}

@end

@implementation NSPersistentHistoryResult (CDPrivate)

-(instancetype)_initWithResult:(id)result resultType:(NSPersistentHistoryResultType)resultType {
   _result=[result retain];
   _resultType=resultType;
   return self;
}

@end
