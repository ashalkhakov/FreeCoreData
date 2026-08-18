/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSRelationshipDescription.h>
#import <CoreData/NSEntityDescription.h>
#import <Foundation/Foundation.h>

@interface NSPropertyDescription(VersionHashPrivate)
- (void)_appendVersionHashComponents:(NSMutableArray *)components;
@end

@implementation NSRelationshipDescription

-initWithCoder: (NSCoder *) coder {
   if(![coder allowsKeyedCoding])
    [NSException raise: NSInvalidArgumentException format: @"%@ can not initWithCoder:%@", [self class], [coder class]];

   [super initWithCoder:coder];
   
   _deleteRule = [coder decodeIntForKey: @"NSDeleteRule"];
   _destinationEntity = [coder decodeObjectForKey: @"NSDestinationEntity"];
   _inverseRelationship = [coder decodeObjectForKey: @"NSInverseRelationship"];
   _optional = [coder decodeBoolForKey: @"NSIsOptional"];
   _maxCount = [coder decodeIntForKey: @"NSMaxCount"];
   _minCount = [coder decodeIntForKey: @"NSMinCount"];
       
   _destinationEntityName= [[coder decodeObjectForKey: @"_NSDestinationEntityName"] copy];
   _inverseRelationshipName= [[coder decodeObjectForKey: @"_NSInverseRelationshipName"] copy];
       
   return self;
}


- (void) encodeWithCoder: (NSCoder *) coder {
   [super encodeWithCoder:coder];

   [coder encodeInt:_deleteRule forKey: @"NSDeleteRule"];
   [coder encodeConditionalObject:_destinationEntity forKey: @"NSDestinationEntity"];
   [coder encodeConditionalObject:_inverseRelationship forKey: @"NSInverseRelationship"];
   [coder encodeInt:_maxCount forKey: @"NSMaxCount"];
   [coder encodeInt:_minCount forKey: @"NSMinCount"];

   NSString *destinationEntityName=(_destinationEntityName!=nil)?_destinationEntityName:[_destinationEntity name];
   NSString *inverseRelationshipName=(_inverseRelationshipName!=nil)?_inverseRelationshipName:[_inverseRelationship name];

   if(destinationEntityName!=nil)
    [coder encodeObject:destinationEntityName forKey: @"_NSDestinationEntityName"];
   if(inverseRelationshipName!=nil)
    [coder encodeObject:inverseRelationshipName forKey: @"_NSInverseRelationshipName"];
}


- (NSString *) description {
    return [NSString stringWithFormat: @"<NSRelationshipDescription: %@->%@>",
		     _propertyName, _destinationEntityName];
}


- (BOOL) isToMany {
   /* A relationship is to-one when its maximum count is exactly one;
      the minimum count only expresses whether it is mandatory.  A max
      count of zero means "unbounded", i.e. to-many. */
   return (_maxCount==1)?NO:YES;
}


- (int) maxCount {
    return _maxCount;
}


- (int) minCount {
    return _minCount;
}


- (NSDeleteRule) deleteRule {
    return _deleteRule;
}


- (NSEntityDescription *) destinationEntity {
    return _destinationEntity;
}


- (NSRelationshipDescription *) inverseRelationship {
    return _inverseRelationship;
}


- (void) setMaxCount: (int) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    _maxCount = value;
}


- (void) setMinCount: (int) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    _minCount = value;
}


- (void) setDeleteRule: (NSDeleteRule) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    _deleteRule = value;
}


- (void) setDestinationEntity: (NSEntityDescription *) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    _destinationEntity = value;
    _destinationEntityName = [value name];
}


- (void) setInverseRelationship: (NSRelationshipDescription *) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    _inverseRelationship = value;
    _inverseRelationshipName = [value name];
}


- (void) _appendVersionHashComponents: (NSMutableArray *) components {
    NSString *destinationName=(_destinationEntityName!=nil)?_destinationEntityName:[_destinationEntity name];

    [super _appendVersionHashComponents:components];
    [components addObject:(destinationName!=nil)?destinationName:@""];
    [components addObject:[self isToMany]?@"1":@"0"];
    [components addObject:[NSString stringWithFormat:@"%d",(int)_deleteRule]];
    [components addObject:[NSString stringWithFormat:@"%lu",(unsigned long)_minCount]];
    [components addObject:[NSString stringWithFormat:@"%lu",(unsigned long)_maxCount]];
}


@end
