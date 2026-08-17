/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSMergePolicy.h>
#import <Foundation/NSDictionary.h>

id NSErrorMergePolicy=nil;
id NSMergeByPropertyStoreTrumpMergePolicy=nil;
id NSMergeByPropertyObjectTrumpMergePolicy=nil;
id NSOverwriteMergePolicy=nil;
id NSRollbackMergePolicy=nil;

@implementation NSMergeConflict

-initWithSource:(NSManagedObject *)sourceObject
     newVersion:(NSUInteger)newVersion
     oldVersion:(NSUInteger)oldVersion
 cachedSnapshot:(NSDictionary *)cachedSnapshot
persistedSnapshot:(NSDictionary *)persistedSnapshot {
   _sourceObject=[sourceObject retain];
   _newVersionNumber=newVersion;
   _oldVersionNumber=oldVersion;
   _cachedSnapshot=[cachedSnapshot copy];
   _persistedSnapshot=[persistedSnapshot copy];
   _objectSnapshot=nil;
   return self;
}

-(void)dealloc {
   [_sourceObject release];
   [_objectSnapshot release];
   [_cachedSnapshot release];
   [_persistedSnapshot release];
   [super dealloc];
}

-(NSManagedObject *)sourceObject {
   return _sourceObject;
}

-(NSDictionary *)objectSnapshot {
   return _objectSnapshot;
}

-(void)_setObjectSnapshot:(NSDictionary *)snapshot {
   snapshot=[snapshot copy];
   [_objectSnapshot release];
   _objectSnapshot=snapshot;
}

-(NSDictionary *)cachedSnapshot {
   return _cachedSnapshot;
}

-(NSDictionary *)persistedSnapshot {
   return _persistedSnapshot;
}

-(NSUInteger)newVersionNumber {
   return _newVersionNumber;
}

-(NSUInteger)oldVersionNumber {
   return _oldVersionNumber;
}

@end

@implementation NSMergePolicy

+(void)initialize {
   if(self==[NSMergePolicy class]){
    if(NSErrorMergePolicy==nil)
     NSErrorMergePolicy=[[NSMergePolicy alloc] initWithMergeType:NSErrorMergePolicyType];
    if(NSMergeByPropertyStoreTrumpMergePolicy==nil)
     NSMergeByPropertyStoreTrumpMergePolicy=[[NSMergePolicy alloc] initWithMergeType:NSMergeByPropertyStoreTrumpMergePolicyType];
    if(NSMergeByPropertyObjectTrumpMergePolicy==nil)
     NSMergeByPropertyObjectTrumpMergePolicy=[[NSMergePolicy alloc] initWithMergeType:NSMergeByPropertyObjectTrumpMergePolicyType];
    if(NSOverwriteMergePolicy==nil)
     NSOverwriteMergePolicy=[[NSMergePolicy alloc] initWithMergeType:NSOverwriteMergePolicyType];
    if(NSRollbackMergePolicy==nil)
     NSRollbackMergePolicy=[[NSMergePolicy alloc] initWithMergeType:NSRollbackMergePolicyType];
   }
}

-initWithMergeType:(NSMergePolicyType)type {
   _mergeType=type;
   return self;
}

-(NSMergePolicyType)mergeType {
   return _mergeType;
}

/* Subclass hook; the built-in policies are resolved by
   NSManagedObjectContext during -save:. */
-(BOOL)resolveConflicts:(NSArray *)list error:(NSError **)error {
   return YES;
}

@end
