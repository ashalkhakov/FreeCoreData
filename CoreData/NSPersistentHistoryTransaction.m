/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSPersistentHistoryTransaction.h"
#import "NSPersistentHistory-Private.h"
#import "NSManagedObjectContext.h"
#import "NSEntityDescription.h"
#import "NSAttributeDescription.h"
#import "NSFetchRequest.h"
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

NSAttributeDescription *CDHistoryEntityAttribute(NSString *name,NSAttributeType type){
   NSAttributeDescription *attribute=[[[NSAttributeDescription alloc] init] autorelease];

   [attribute setName:name];
   [attribute setAttributeType:type];
   [attribute setOptional:YES];
   return attribute;
}

@implementation NSPersistentHistoryTransaction

/* The property names mirror the accessors, so a predicate built
   against this entity evaluates directly against
   NSPersistentHistoryTransaction instances through KVC. */
+(NSEntityDescription *)entityDescription {
   static NSEntityDescription *entity=nil;
   static dispatch_once_t once;

   dispatch_once(&once,^{
     entity=[[NSEntityDescription alloc] init];
     [entity setName:@"Transaction"];   /* Apple's name, verified on macOS */
     [entity setProperties:[NSArray arrayWithObjects:
         CDHistoryEntityAttribute(@"transactionNumber",NSInteger64AttributeType),
         CDHistoryEntityAttribute(@"timestamp",NSDateAttributeType),
         CDHistoryEntityAttribute(@"author",NSStringAttributeType),
         CDHistoryEntityAttribute(@"contextName",NSStringAttributeType),
         CDHistoryEntityAttribute(@"processID",NSStringAttributeType),
         CDHistoryEntityAttribute(@"bundleID",NSStringAttributeType),
         CDHistoryEntityAttribute(@"storeID",NSStringAttributeType),
         nil]];
   });
   return entity;
}

+(NSEntityDescription *)entityDescriptionWithContext:(NSManagedObjectContext *)context {
   return [self entityDescription];
}

+(NSFetchRequest *)fetchRequest {
   NSFetchRequest *request=[[[NSFetchRequest alloc] init] autorelease];

   [request setEntity:[self entityDescription]];
   return request;
}

-(void)dealloc {
   [_timestamp release];
   [_author release];
   [_contextName release];
   [_processID release];
   [_bundleID release];
   [_storeID release];
   [_changes release];
   [super dealloc];
}

-(int64_t)transactionNumber {
   return _transactionNumber;
}

-(NSDate *)timestamp {
   return _timestamp;
}

-(NSString *)author {
   return _author;
}

-(NSString *)contextName {
   return _contextName;
}

-(NSString *)processID {
   return _processID;
}

-(NSString *)bundleID {
   return _bundleID;
}

-(NSString *)storeID {
   return _storeID;
}

-(NSPersistentHistoryToken *)token {
   NSDictionary *positions=[NSDictionary dictionaryWithObject:[NSNumber numberWithLongLong:_transactionNumber] forKey:(_storeID!=nil)?_storeID:@""];

   return [[[NSPersistentHistoryToken alloc] _initWithPositions:positions] autorelease];
}

-(NSArray *)changes {
   return _changes;
}

/* A notification shaped for
   -[NSManagedObjectContext mergeChangesFromContextDidSaveNotification:]:
   the changed object IDs of this transaction, grouped by change type
   under the *ObjectIDsKey userInfo keys. */
-(NSNotification *)objectIDNotification {
   NSMutableSet       *inserted=[NSMutableSet set];
   NSMutableSet       *updated=[NSMutableSet set];
   NSMutableSet       *deleted=[NSMutableSet set];
   NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];
   NSInteger           i,count=[_changes count];

   for(i=0;i<count;i++){
    NSPersistentHistoryChange *change=[_changes objectAtIndex:i];

    switch([change changeType]){
     case NSPersistentHistoryChangeTypeInsert:
      [inserted addObject:[change changedObjectID]];
      break;
     case NSPersistentHistoryChangeTypeUpdate:
      [updated addObject:[change changedObjectID]];
      break;
     case NSPersistentHistoryChangeTypeDelete:
      [deleted addObject:[change changedObjectID]];
      break;
    }
   }
   if([inserted count]>0)
    [userInfo setObject:inserted forKey:NSInsertedObjectIDsKey];
   if([updated count]>0)
    [userInfo setObject:updated forKey:NSUpdatedObjectIDsKey];
   if([deleted count]>0)
    [userInfo setObject:deleted forKey:NSDeletedObjectIDsKey];

   return [NSNotification notificationWithName:NSManagedObjectContextDidSaveObjectIDsNotification object:nil userInfo:userInfo];
}

-copyWithZone:(NSZone *)zone {
   return [self retain];   /* immutable */
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<%@: %p #%lld at %@ author=%@ context=%@ changes=%lu>",[self class],self,(long long)_transactionNumber,_timestamp,_author,_contextName,(unsigned long)[_changes count]];
}

@end

@implementation NSPersistentHistoryTransaction (CDPrivate)

-(instancetype)_initWithNumber:(int64_t)number
                     timestamp:(NSDate *)timestamp
                        author:(NSString *)author
                   contextName:(NSString *)contextName
                     processID:(NSString *)processID
                      bundleID:(NSString *)bundleID
                       storeID:(NSString *)storeID
                       changes:(NSArray *)changes {
   _transactionNumber=number;
   _timestamp=[timestamp retain];
   _author=[author copy];
   _contextName=[contextName copy];
   _processID=[processID copy];
   _bundleID=[bundleID copy];
   _storeID=[storeID copy];
   [self _setChanges:changes];
   return self;
}

-(void)_setChanges:(NSArray *)changes {
   NSInteger i,count=[changes count];

   changes=[changes copy];
   [_changes release];
   _changes=changes;
   for(i=0;i<count;i++)
    [[_changes objectAtIndex:i] _setTransaction:self];
}

@end
