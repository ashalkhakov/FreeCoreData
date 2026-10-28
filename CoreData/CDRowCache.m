/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDRowCache.h"
#import <CoreData/NSIncrementalStoreNode.h>
#import <CoreData/NSManagedObjectID.h>

@interface CDRowCacheEntry : NSObject {
@public
   NSIncrementalStoreNode *_row;
   NSTimeInterval          _readAt;
   NSUInteger              _holders;
}
@end

@implementation CDRowCacheEntry
-(void)dealloc {
   [_row release];
   [super dealloc];
}
@end

@implementation CDRowCache

-init {
   if((self=[super init])!=nil){
    _lock=[[NSLock alloc] init];
    _entries=[[NSMutableDictionary alloc] init];
   }
   return self;
}

-(void)dealloc {
   [_lock release];
   [_entries release];
   [super dealloc];
}

-(void)holdObjectID:(NSManagedObjectID *)objectID {
   [_lock lock];
   CDRowCacheEntry *entry=[_entries objectForKey:objectID];

   if(entry==nil){
    entry=[[CDRowCacheEntry alloc] init];
    [_entries setObject:entry forKey:objectID];
    [entry release];
   }
   entry->_holders++;
   [_lock unlock];
}

-(void)releaseObjectID:(NSManagedObjectID *)objectID {
   [_lock lock];
   CDRowCacheEntry *entry=[_entries objectForKey:objectID];

   if(entry!=nil && --entry->_holders==0)
    [_entries removeObjectForKey:objectID];
   [_lock unlock];
}

-(NSIncrementalStoreNode *)rowForObjectID:(NSManagedObjectID *)objectID staleness:(NSTimeInterval)staleness {
   NSIncrementalStoreNode *row=nil;

   if(staleness==0)
    return nil;

   [_lock lock];
   CDRowCacheEntry *entry=[_entries objectForKey:objectID];

   if(entry!=nil && entry->_row!=nil &&
      (staleness<0 || [NSDate timeIntervalSinceReferenceDate]-entry->_readAt<=staleness))
    row=[[entry->_row retain] autorelease];
   [_lock unlock];
   return row;
}

-(void)setRow:(NSIncrementalStoreNode *)row forObjectID:(NSManagedObjectID *)objectID {
   if(row==nil)
    return;

   [_lock lock];
   CDRowCacheEntry *entry=[_entries objectForKey:objectID];

   if(entry!=nil){
    [row retain];
    [entry->_row release];
    entry->_row=row;
    entry->_readAt=[NSDate timeIntervalSinceReferenceDate];
   }
   [_lock unlock];
}

-(void)forgetRowForObjectID:(NSManagedObjectID *)objectID {
   [_lock lock];
   CDRowCacheEntry *entry=[_entries objectForKey:objectID];

   if(entry!=nil){
    [entry->_row release];
    entry->_row=nil;
   }
   [_lock unlock];
}

-(void)forgetRowsOfStore:(NSPersistentStore *)store {
   [_lock lock];
   for(NSManagedObjectID *objectID in [_entries allKeys])
    if([objectID persistentStore]==store){
     CDRowCacheEntry *entry=[_entries objectForKey:objectID];

     [entry->_row release];
     entry->_row=nil;
    }
   [_lock unlock];
}

@end
