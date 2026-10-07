/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSFetchIndexDescription.h>
#import <CoreData/NSEntityDescription.h>
#import "NSFetchIndexDescription-Private.h"
#import <Foundation/Foundation.h>

@implementation NSFetchIndexDescription

-(instancetype)initWithName:(NSString *)name elements:(NSArray *)elements {
   if((self=[super init])==nil)
    return nil;

   _name=[name copy];
   [self setElements:elements];

   return self;
}

-(void)dealloc {
   for(NSFetchIndexElementDescription *element in _elements)
    if([element indexDescription]==self)
     [element _setIndexDescription:nil];
   [_name release];
   [_elements release];
   [_partialIndexPredicate release];
   [super dealloc];
}

-(instancetype)initWithCoder:(NSCoder *)coder {
   if((self=[super init])==nil)
    return nil;

   _name=[[coder decodeObjectForKey:@"NSIndexName"] copy];
   _entity=[coder decodeObjectForKey:@"NSEntity"];
   [self setElements:[coder decodeObjectForKey:@"NSIndexElements"]];

   /* A predicate, or its format where an archiver kept only that. */
   id predicate=[coder decodeObjectForKey:@"NSPartialIndexPredicate"];

   if([predicate isKindOfClass:[NSString class]])
    predicate=[NSPredicate predicateWithFormat:predicate];
   if([predicate respondsToSelector:@selector(allowEvaluation)])
    [predicate performSelector:@selector(allowEvaluation)];
   _partialIndexPredicate=[predicate retain];

   return self;
}

-(void)encodeWithCoder:(NSCoder *)coder {
   [coder encodeObject:_name forKey:@"NSIndexName"];
   [coder encodeObject:(_elements!=nil)?_elements:[NSArray array] forKey:@"NSIndexElements"];
   [coder encodeConditionalObject:_entity forKey:@"NSEntity"];
   if(_partialIndexPredicate!=nil)
    [coder encodeObject:_partialIndexPredicate forKey:@"NSPartialIndexPredicate"];
}

/* A copy has elements of its own, and the entity the original has. */
-(id)copyWithZone:(NSZone *)zone {
   NSMutableArray *elements=[NSMutableArray arrayWithCapacity:[_elements count]];

   for(NSFetchIndexElementDescription *element in _elements){
    NSFetchIndexElementDescription *copy=[element copyWithZone:zone];

    [elements addObject:copy];
    [copy release];
   }

   NSFetchIndexDescription *copy=[[[self class] allocWithZone:zone] initWithName:_name elements:elements];

   copy->_partialIndexPredicate=[_partialIndexPredicate copy];
   copy->_entity=_entity;

   return copy;
}

-(NSString *)name {
   return _name;
}

-(void)setName:(NSString *)value {
   value=[value copy];
   [_name release];
   _name=value;
}

-(NSArray *)elements {
   return (_elements!=nil)?_elements:[NSArray array];
}

-(void)setElements:(NSArray *)value {
   value=[value copy];

   for(NSFetchIndexElementDescription *element in _elements)
    if([element indexDescription]==self && ![value containsObject:element])
     [element _setIndexDescription:nil];
   for(NSFetchIndexElementDescription *element in value)
    [element _setIndexDescription:self];

   [_elements release];
   _elements=value;
}

-(NSEntityDescription *)entity {
   return _entity;
}

-(void)_setEntity:(NSEntityDescription *)entity {
   _entity=entity;
}

-(NSPredicate *)partialIndexPredicate {
   return _partialIndexPredicate;
}

-(void)setPartialIndexPredicate:(NSPredicate *)value {
   value=[value copy];
   [_partialIndexPredicate release];
   _partialIndexPredicate=value;
}

-(NSString *)description {
   NSMutableString *result=[NSMutableString stringWithFormat:@"<NSFetchIndexDescription : (%@:%@, elements: %@",
       [_entity name],_name,[self elements]];

   if(_partialIndexPredicate!=nil)
    [result appendFormat:@", predicate: %@",[_partialIndexPredicate predicateFormat]];
   [result appendString:@")>"];

   return result;
}

@end
