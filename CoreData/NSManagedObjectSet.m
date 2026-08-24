/* This file is part of the CoreData framework port for GNUstep.
   Ported from the Cocotron project (https://github.com/cjwl/cocotron).

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>
   Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSManagedObjectSet.h"
#import <Foundation/NSException.h>
#import "NSManagedObjectSetEnumerator.h"
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObject.h>

@implementation NSManagedObjectSet

-initWithManagedObjectContext:(NSManagedObjectContext *)context set:(NSSet *)set {
   _context=[context retain];
   _owner=nil;
   _key=nil;
   _set=[set retain];
   return self;
}

-initWithManagedObject:(NSManagedObject *)owner key:(NSString *)key {
   _context=[[owner managedObjectContext] retain];
   _owner=[owner retain];
   _key=[key copy];
   _set=nil;
   return self;
}

-(void)dealloc {
   [_context release];
   [_owner release];
   [_key release];
   [_set release];
   [super dealloc];
}

/* Current membership as object IDs.  A live view reads the owner's
   primitive value on every access, so the set tracks the relationship
   instead of freezing the state it was created with. */
-(NSSet *)_memberIDs {
   if(_owner!=nil){
    id value=[_owner primitiveValueForKey:_key];

    return (value!=nil)?value:(id)[NSSet set];
   }
   return _set;
}

-(NSUInteger)count {
   return [[self _memberIDs] count];
}

-member:object {
   id memberID=[[self _memberIDs] member:[object objectID]];

   return (memberID==nil)?nil:[_context objectWithID:memberID];
}

-(NSEnumerator *)objectEnumerator {
   NSEnumerator *state=[[self _memberIDs] objectEnumerator];
   
   if(state==nil)
    return nil;
    
   return [[[NSManagedObjectSetEnumerator alloc] initWithManagedObjectContext:_context objectEnumerator:state] autorelease];
}

-(NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len {
   NSUInteger count=[[self _memberIDs] countByEnumeratingWithState:state objects:stackbuf count:len];
   NSUInteger i;

   for(i=0;i<count;i++)
    stackbuf[i]=[_context objectWithID:state->itemsPtr[i]];

   state->itemsPtr=stackbuf;

   return count;
}

/* Mutations route through the owner's setter - the same path as
   -setValue:forKey: - so change tracking, undo capture and inverse
   maintenance all apply.  Membership is rebuilt from the live view
   because the setter replaces the primitive collection wholesale. */
-(NSMutableSet *)_memberObjectsAfterRemoving:(id)removed adding:(id)added {
   NSManagedObjectID *removedID=[removed objectID];
   NSMutableSet      *members=[NSMutableSet set];

   for(NSManagedObjectID *memberID in [self _memberIDs]){
    if(removedID!=nil && [memberID isEqual:removedID])
     continue;
    [members addObject:[_context objectWithID:memberID]];
   }
   if(added!=nil)
    [members addObject:added];
   return members;
}

-(void)addObject:object {
   if(_owner==nil)
    [NSException raise:NSInternalInconsistencyException
                format:@"-[NSManagedObjectSet addObject:]: this set is an immutable snapshot"];
   if([[self _memberIDs] member:[object objectID]]!=nil)
    return;

   [_owner setValue:[self _memberObjectsAfterRemoving:nil adding:object] forKey:_key];
}

-(void)removeObject:object {
   if(_owner==nil)
    [NSException raise:NSInternalInconsistencyException
                format:@"-[NSManagedObjectSet removeObject:]: this set is an immutable snapshot"];
   if([[self _memberIDs] member:[object objectID]]==nil)
    return;

   [_owner setValue:[self _memberObjectsAfterRemoving:object adding:nil] forKey:_key];
}

@end
