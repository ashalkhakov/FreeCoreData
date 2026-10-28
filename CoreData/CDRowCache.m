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
   NSManagedObjectID      *_objectID;
   NSIncrementalStoreNode *_row;
   NSTimeInterval          _readAt;
   NSUInteger              _holders;
   /* While no context holds it: its place in its store's retained rows. */
   CDRowCacheEntry        *_older,*_newer;
}
@end

@implementation CDRowCacheEntry
-(void)dealloc {
   [_objectID release];
   [_row release];
   [super dealloc];
}
@end

/* The rows of a store kept while no context holds them, the least
   recently let go of oldest. */
@interface CDRowCacheRetention : NSObject {
@public
   NSUInteger       _limit;
   NSTimeInterval   _interval;   /* none when not positive */
   NSUInteger       _count;
   CDRowCacheEntry *_oldest,*_newest;
}
@end

@implementation CDRowCacheRetention
@end

@implementation CDRowCache

-init {
   if((self=[super init])!=nil){
    _lock=[[NSLock alloc] init];
    _entries=[[NSMutableDictionary alloc] init];
    _retentions=NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks,NSObjectMapValueCallBacks,0);
   }
   return self;
}

-(void)dealloc {
   [_lock release];
   [_entries release];
   NSFreeMapTable(_retentions);
   [super dealloc];
}

-(void)retainRowsOfStore:(NSPersistentStore *)store limit:(NSUInteger)limit interval:(NSTimeInterval)interval {
   CDRowCacheRetention *retention=[[CDRowCacheRetention alloc] init];

   retention->_limit=limit;
   retention->_interval=interval;
   [_lock lock];
   NSMapInsert(_retentions,store,retention);
   [_lock unlock];
   [retention release];
}

-(CDRowCacheRetention *)_retentionOfStore:(NSPersistentStore *)store {
   return (store==nil)?nil:NSMapGet(_retentions,store);
}

-(void)_retain:(CDRowCacheEntry *)entry in:(CDRowCacheRetention *)retention {
   entry->_older=retention->_newest;
   entry->_newer=nil;
   if(retention->_newest!=nil)
    retention->_newest->_newer=entry;
   else
    retention->_oldest=entry;
   retention->_newest=entry;
   retention->_count++;
}

-(void)_unretain:(CDRowCacheEntry *)entry in:(CDRowCacheRetention *)retention {
   if(retention==nil)
    return;
   if(entry->_older!=nil)
    entry->_older->_newer=entry->_newer;
   else
    retention->_oldest=entry->_newer;
   if(entry->_newer!=nil)
    entry->_newer->_older=entry->_older;
   else
    retention->_newest=entry->_older;
   entry->_older=entry->_newer=nil;
   retention->_count--;
}

-(BOOL)_hasExpired:(CDRowCacheEntry *)entry in:(CDRowCacheRetention *)retention {
   return retention!=nil && retention->_interval>0 && [NSDate timeIntervalSinceReferenceDate]-entry->_readAt>retention->_interval;
}

/* Forgets entry, which no context holds. */
-(void)_drop:(CDRowCacheEntry *)entry {
   CDRowCacheRetention *retention=[self _retentionOfStore:[entry->_objectID persistentStore]];

   if(retention!=nil)
    [self _unretain:entry in:retention];
   [_entries removeObjectForKey:entry->_objectID];
}

-(void)holdObjectID:(NSManagedObjectID *)objectID {
   [_lock lock];
   CDRowCacheEntry *entry=[_entries objectForKey:objectID];

   if(entry==nil){
    entry=[[CDRowCacheEntry alloc] init];
    entry->_objectID=[objectID retain];
    [_entries setObject:entry forKey:objectID];
    [entry release];
   }
   else if(entry->_holders==0){
    CDRowCacheRetention *retention=[self _retentionOfStore:[objectID persistentStore]];

    [self _unretain:entry in:retention];
    if([self _hasExpired:entry in:retention]){
     [entry->_row release];
     entry->_row=nil;
    }
   }
   entry->_holders++;
   [_lock unlock];
}

-(void)releaseObjectID:(NSManagedObjectID *)objectID {
   [_lock lock];
   CDRowCacheEntry *entry=[_entries objectForKey:objectID];

   if(entry!=nil && --entry->_holders==0){
    CDRowCacheRetention *retention=[self _retentionOfStore:[objectID persistentStore]];

    if(retention==nil || entry->_row==nil || [self _hasExpired:entry in:retention])
     [_entries removeObjectForKey:objectID];
    else {
     [self _retain:entry in:retention];
     while(retention->_count>retention->_limit ||
           (retention->_oldest!=nil && [self _hasExpired:retention->_oldest in:retention]))
      [self _drop:retention->_oldest];
    }
   }
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

   if(entry!=nil && entry->_holders==0)
    [self _drop:entry];
   else if(entry!=nil){
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

     if(entry->_holders==0)
      [self _drop:entry];
     else {
      [entry->_row release];
      entry->_row=nil;
     }
    }
   NSMapRemove(_retentions,store);
   [_lock unlock];
}

@end
