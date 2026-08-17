/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPropertyDescription.h>
#import "CoreDataUtilities.h"
#import "CoreDataVersioning-Private.h"
#import <Foundation/NSCoder.h>

@implementation NSPropertyDescription

-init {
   _entity=nil;
   _propertyName=nil;
   /* Properties are optional by default, as on Apple's CoreData. */
   _optional=YES;
   return self;
}

-initWithCoder:(NSCoder *)coder {
   if(![coder allowsKeyedCoding])
    [NSException raise: NSInvalidArgumentException format: @"%@ can not initWithCoder:%@", [self class], [coder class]];

   _entity=[coder decodeObjectForKey: @"NSEntity"];
   _propertyName=[[coder decodeObjectForKey: @"NSPropertyName"] copy];
   _versionHashModifier=[[coder decodeObjectForKey: @"NSVersionHashModifier"] copy];
   
   return self;
}


- (void) encodeWithCoder: (NSCoder *) coder {
    NSInvalidAbstractInvocation();
}


- (BOOL) isEqual: (id) object {
    if(![object isKindOfClass: [NSPropertyDescription class]])
	return NO;
    NSPropertyDescription *property = (NSPropertyDescription *) object;
    if((_entity == [property entity]) &&
       [_propertyName isEqualToString: [property name]])
	return YES;
    else
	return NO;
}


- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}


- (NSEntityDescription *) entity {
    return _entity;
}

/* Private: back-reference set by -[NSEntityDescription setProperties:].
   Not retained; the entity owns its properties. */
- (void) _setEntity: (NSEntityDescription *) entity {
    _entity=entity;
}


- (NSString *) name {
    return _propertyName;
}


- (BOOL) isOptional {
    return _optional;
}


- (BOOL) isTransient {
    return _transient;
}


- (NSDictionary *) userInfo {
    return _userInfo;
}


- (NSArray *) validationPredicates {
    return _validationPredicates;
}


- (NSArray *) validationWarnings {
    return _validationWarnings;
}


/* Private: subclasses append the components that participate in the
   version hash. */
- (void) _appendVersionHashComponents: (NSMutableArray *) components {
    [components addObject:NSStringFromClass([self class])];
    [components addObject:(_propertyName!=nil)?_propertyName:@""];
    [components addObject:_optional?@"1":@"0"];
    if(_versionHashModifier!=nil)
	[components addObject:_versionHashModifier];
}


- (NSData *) versionHash {
    NSMutableArray *components=[NSMutableArray array];

    [self _appendVersionHashComponents:components];

    return _NSCoreDataDigestForComponents(components);
}


- (NSString *) versionHashModifier {
    return _versionHashModifier;
}


- (void) setVersionHashModifier: (NSString *) value {
    value=[value copy];
    [_versionHashModifier release];
    _versionHashModifier=value;
}


- (void) setName: (NSString *) value {
    value=[value copy];
    [_propertyName release];
    _propertyName=value;
}


- (void) setOptional: (BOOL) value {
    _optional=value;
}


- (void) setTransient: (BOOL) value {
    _transient=value;
}


- (void) setUserInfo: (NSDictionary *) value {
    value=[value copy];
    [_userInfo release];
    _userInfo=value;
}


- (void) setValidationPredicates: (NSArray *) predicates
	  withValidationWarnings: (NSArray *) warnings
{
    predicates=[predicates copy];
    [_validationPredicates release];
    _validationPredicates=predicates;

    warnings=[warnings copy];
    [_validationWarnings release];
    _validationWarnings=warnings;
}


@end
