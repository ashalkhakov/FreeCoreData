/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSFetchIndexElementDescription.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSExpressionDescription.h>
#import "NSFetchIndexDescription-Private.h"
#import <Foundation/Foundation.h>

@implementation NSFetchIndexElementDescription

/* What an R-tree can index, as Apple's runtime and momc both have it. */
static BOOL propertyCanBeInAnRTree(NSPropertyDescription *property){
   if(![property isKindOfClass:[NSAttributeDescription class]])
    return NO;

   switch([(NSAttributeDescription *)property attributeType]){
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSFloatAttributeType:
     return YES;
    default:
     return NO;
   }
}

-(instancetype)initWithProperty:(NSPropertyDescription *)property collationType:(NSFetchIndexElementType)collationType {
   if((self=[super init])==nil)
    return nil;

   if([[property name] length]==0){
    [self release];
    [NSException raise:NSInvalidArgumentException format:@"Can't create an index element with an unnamed property"];
    return nil;
   }
   if(collationType==NSFetchIndexElementTypeRTree && !propertyCanBeInAnRTree(property)){
    [self release];
    [NSException raise:NSInvalidArgumentException format:@"Invalid collation type (rtree indexes can only be created for floats or integers < 32 bit)."];
    return nil;
   }

   _property=[property retain];
   _propertyName=[[property name] copy];
   _collationType=collationType;
   _ascending=YES;

   return self;
}

-(void)dealloc {
   [_property release];
   [_propertyName release];
   [super dealloc];
}

/* A property of the entity is archived by name and found again in the
   entity; an expression description belongs to no entity, so it is
   archived whole - Apple's NSIndexedProperty. */
-(instancetype)initWithCoder:(NSCoder *)coder {
   if((self=[super init])==nil)
    return nil;

   _propertyName=[[coder decodeObjectForKey:@"NSPropertyName"] copy];
   _property=[[coder decodeObjectForKey:@"NSIndexedProperty"] retain];
   _collationType=(NSFetchIndexElementType)[coder decodeIntegerForKey:@"NSFetchIndexElementType"];
   _ascending=[coder containsValueForKey:@"NSAscending"]?[coder decodeBoolForKey:@"NSAscending"]:YES;
   _indexDescription=[coder decodeObjectForKey:@"NSFetchIndexDescription"];

   return self;
}

-(void)encodeWithCoder:(NSCoder *)coder {
   [coder encodeObject:_propertyName forKey:@"NSPropertyName"];
   if([_property isKindOfClass:[NSExpressionDescription class]])
    [coder encodeObject:_property forKey:@"NSIndexedProperty"];
   [coder encodeInteger:_collationType forKey:@"NSFetchIndexElementType"];
   [coder encodeBool:_ascending forKey:@"NSAscending"];
   [coder encodeConditionalObject:_indexDescription forKey:@"NSFetchIndexDescription"];
}

-(id)copyWithZone:(NSZone *)zone {
   NSFetchIndexElementDescription *copy=[[[self class] allocWithZone:zone] init];

   copy->_property=[_property retain];
   copy->_propertyName=[_propertyName copy];
   copy->_collationType=_collationType;
   copy->_ascending=_ascending;

   return copy;
}

/* Found by name once, then kept, so that a renamed property is still
   the one indexed. */
-(NSPropertyDescription *)property {
   if(_property==nil)
    _property=[[[[_indexDescription entity] propertiesByName] objectForKey:_propertyName] retain];

   return _property;
}

-(NSString *)propertyName {
   NSString *name=[_property name];

   return (name!=nil)?name:_propertyName;
}

-(NSFetchIndexElementType)collationType {
   return _collationType;
}

-(void)setCollationType:(NSFetchIndexElementType)value {
   _collationType=value;
}

-(BOOL)isAscending {
   return _ascending;
}

-(void)setAscending:(BOOL)value {
   _ascending=value;
}

-(NSFetchIndexDescription *)indexDescription {
   return _indexDescription;
}

-(void)_setIndexDescription:(NSFetchIndexDescription *)index {
   _indexDescription=index;
}

-(NSString *)description {
   BOOL modeled=![[self property] isKindOfClass:[NSExpressionDescription class]];

   return [NSString stringWithFormat:@"<NSFetchIndexElementDescription : (%@ (%@), %lu, %@)>",
       _propertyName,modeled?@"modeled property":@"expression",(unsigned long)_collationType,_ascending?@"ascending":@"descending"];
}

@end
