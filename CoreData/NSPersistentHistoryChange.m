/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSPersistentHistoryChange.h"
#import "NSPersistentHistory-Private.h"
#import <CoreData/NSManagedObjectID.h>
#import "NSEntityDescription.h"
#import "NSFetchRequest.h"
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

@implementation NSPersistentHistoryChange

/* The property names mirror the accessors, so a predicate built
   against this entity evaluates directly against
   NSPersistentHistoryChange instances through KVC (the canonical
   filter is changedObjectID == %@). */
+(NSEntityDescription *)entityDescription {
   static NSEntityDescription *entity=nil;
   static dispatch_once_t once;

   dispatch_once(&once,^{
     entity=[[NSEntityDescription alloc] init];
     [entity setName:@"Change"];   /* matches Apple's "Transaction" naming */
     [entity setProperties:[NSArray arrayWithObjects:
         CDHistoryEntityAttribute(@"changeID",NSInteger64AttributeType),
         CDHistoryEntityAttribute(@"changeType",NSInteger64AttributeType),
         CDHistoryEntityAttribute(@"changedObjectID",NSUndefinedAttributeType),
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
   [_changedObjectID release];
   [_tombstone release];
   [_updatedProperties release];
   [super dealloc];
}

-(int64_t)changeID {
   return _changeID;
}

-(NSPersistentHistoryChangeType)changeType {
   return _changeType;
}

-(NSManagedObjectID *)changedObjectID {
   return _changedObjectID;
}

-(NSDictionary *)tombstone {
   return _tombstone;
}

-(NSSet *)updatedProperties {
   return _updatedProperties;
}

-(NSPersistentHistoryTransaction *)transaction {
   return _transaction;
}

-copyWithZone:(NSZone *)zone {
   return [self retain];   /* immutable */
}

-(NSString *)description {
   NSString *type;

   switch(_changeType){
    case NSPersistentHistoryChangeTypeInsert: type=@"insert"; break;
    case NSPersistentHistoryChangeTypeUpdate: type=@"update"; break;
    case NSPersistentHistoryChangeTypeDelete: type=@"delete"; break;
    default: type=@"?"; break;
   }
   return [NSString stringWithFormat:@"<%@: %p changeID=%lld %@ %@>",[self class],self,(long long)_changeID,type,[[_changedObjectID URIRepresentation] absoluteString]];
}

@end

@implementation NSPersistentHistoryChange (CDPrivate)

-(instancetype)_initWithChangeID:(int64_t)changeID
                            type:(NSPersistentHistoryChangeType)type
                        objectID:(NSManagedObjectID *)objectID
               updatedProperties:(NSSet *)updatedProperties
                       tombstone:(NSDictionary *)tombstone {
   _changeID=changeID;
   _changeType=type;
   _changedObjectID=[objectID retain];
   _updatedProperties=[updatedProperties copy];
   _tombstone=[tombstone copy];
   return self;
}

-(void)_setTransaction:(NSPersistentHistoryTransaction *)transaction {
   _transaction=transaction;   /* not retained; the transaction owns us */
}

@end
