/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSPersistentHistoryChangeRequest.h"
#import "NSPersistentHistory-Private.h"
#import <Foundation/Foundation.h>

@implementation NSPersistentHistoryChangeRequest

-init {
   [super init];
   _anchorTransactionNumber=-1;
   _resultType=NSPersistentHistoryResultTypeTransactionsAndChanges;
   return self;
}

-(void)dealloc {
   [_anchorDate release];
   [_anchorToken release];
   [_fetchRequest release];
   [super dealloc];
}

+(instancetype)fetchHistoryAfterDate:(NSDate *)date {
   NSPersistentHistoryChangeRequest *result=[[[self alloc] init] autorelease];

   result->_anchorDate=[date retain];
   return result;
}

+(instancetype)fetchHistoryAfterToken:(NSPersistentHistoryToken *)token {
   NSPersistentHistoryChangeRequest *result=[[[self alloc] init] autorelease];

   result->_anchorToken=[token retain];
   return result;
}

+(instancetype)fetchHistoryAfterTransaction:(NSPersistentHistoryTransaction *)transaction {
   NSPersistentHistoryChangeRequest *result=[[[self alloc] init] autorelease];

   if(transaction!=nil)
    result->_anchorTransactionNumber=[transaction transactionNumber];
   return result;
}

+(instancetype)fetchHistoryWithFetchRequest:(NSFetchRequest *)fetchRequest {
   NSPersistentHistoryChangeRequest *result=[[[self alloc] init] autorelease];

   result->_fetchRequest=[fetchRequest retain];
   return result;
}

+(instancetype)deleteHistoryBeforeDate:(NSDate *)date {
   NSPersistentHistoryChangeRequest *result=[self fetchHistoryAfterDate:date];

   result->_isPurge=YES;
   result->_resultType=NSPersistentHistoryResultTypeStatusOnly;
   return result;
}

+(instancetype)deleteHistoryBeforeToken:(NSPersistentHistoryToken *)token {
   NSPersistentHistoryChangeRequest *result=[self fetchHistoryAfterToken:token];

   result->_isPurge=YES;
   result->_resultType=NSPersistentHistoryResultTypeStatusOnly;
   return result;
}

+(instancetype)deleteHistoryBeforeTransaction:(NSPersistentHistoryTransaction *)transaction {
   NSPersistentHistoryChangeRequest *result=[self fetchHistoryAfterTransaction:transaction];

   result->_isPurge=YES;
   result->_resultType=NSPersistentHistoryResultTypeStatusOnly;
   return result;
}

-(NSPersistentStoreRequestType)requestType {
   return NSPersistentHistoryRequestType;
}

-(NSPersistentHistoryResultType)resultType {
   return _resultType;
}

-(void)setResultType:(NSPersistentHistoryResultType)resultType {
   _resultType=resultType;
}

-(NSPersistentHistoryToken *)token {
   return _anchorToken;
}

-(NSFetchRequest *)fetchRequest {
   return _fetchRequest;
}

-(void)setFetchRequest:(NSFetchRequest *)fetchRequest {
   fetchRequest=[fetchRequest retain];
   [_fetchRequest release];
   _fetchRequest=fetchRequest;
}

-copyWithZone:(NSZone *)zone {
   NSPersistentHistoryChangeRequest *copy=[[[self class] allocWithZone:zone] init];

   copy->_isPurge=_isPurge;
   copy->_anchorDate=[_anchorDate retain];
   copy->_anchorToken=[_anchorToken retain];
   copy->_anchorTransactionNumber=_anchorTransactionNumber;
   copy->_fetchRequest=[_fetchRequest retain];
   copy->_resultType=_resultType;
   [copy setAffectedStores:[self affectedStores]];
   return copy;
}

/* Reading the request: additions of this framework's, so that a store
   outside it can implement history.  See the header. */

-(BOOL)isPurgeRequest {
   return _isPurge;
}

-(NSDate *)anchorDate {
   return _anchorDate;
}

-(int64_t)anchorTransactionNumber {
   return _anchorTransactionNumber;
}

@end

/* The original spellings, kept because the in-tree SQLite store and the
   tests use them; each is the public accessor above. */
@implementation NSPersistentHistoryChangeRequest (CDPrivate)

-(BOOL)_isPurge {
   return [self isPurgeRequest];
}

-(NSDate *)_anchorDate {
   return [self anchorDate];
}

-(NSPersistentHistoryToken *)_anchorToken {
   return _anchorToken;
}

-(int64_t)_anchorTransactionNumber {
   return [self anchorTransactionNumber];
}

@end
