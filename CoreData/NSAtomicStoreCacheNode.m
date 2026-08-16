/* This file is part of the CoreData framework port for GNUstep.
   Ported from the Cocotron project (https://github.com/cjwl/cocotron).

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>
   Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSAtomicStoreCacheNode.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

@implementation NSAtomicStoreCacheNode

-initWithObjectID:(NSManagedObjectID *)objectID {
   _objectID=[objectID copy];
   _propertyCache=nil;
   return self;
}

-(void)dealloc {
   [_objectID release];
   [_propertyCache release];
   [super dealloc];
}

-(NSUInteger)hash {
   return [_objectID hash];
}

-(BOOL)isEqual:other {
   return [_objectID isEqual:other];
}

-(NSManagedObjectID *)objectID {
   return _objectID;
}

-(NSMutableDictionary *)propertyCache {
   return _propertyCache;
}

-(void)setPropertyCache:(NSMutableDictionary *)value {
   value=[value retain];
   [_propertyCache release];
   _propertyCache=value;
}

-(void)setValue:value forKey:(NSString *)key {
   if(_propertyCache==nil)
    _propertyCache=[[NSMutableDictionary alloc] init];

   if(value==nil)
    [_propertyCache removeObjectForKey:key];
   else {
    [_propertyCache setObject:value forKey:key];
   }
}

-valueForKey:(NSString *)key {
   return [_propertyCache objectForKey:key];
}

@end
