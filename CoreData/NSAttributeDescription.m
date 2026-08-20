/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSEntityDescription.h>
#import <Foundation/Foundation.h>

@interface NSPropertyDescription(VersionHashPrivate)
- (void)_appendVersionHashComponents:(NSMutableArray *)components;
@end

@implementation NSAttributeDescription

-initWithCoder:(NSCoder *)coder {
   if(![coder allowsKeyedCoding])
    [NSException raise: NSInvalidArgumentException format: @"%@ can not initWithCoder:%@", [self class], [coder class]];

   [super initWithCoder:coder];

   _attributeType = [coder decodeIntForKey: @"NSAttributeType"];
   _valueClassName= [[coder decodeObjectForKey: @"NSAttributeValueClassName"] retain];
   _defaultValue = [[coder decodeObjectForKey: @"NSDefaultValue"] retain];
   _valueTransformerName= [[coder decodeObjectForKey: @"NSValueTransformerName"] retain];

   return self;
}


- (void) encodeWithCoder: (NSCoder *) coder {
   [super encodeWithCoder:coder];

   [coder encodeInt:_attributeType forKey: @"NSAttributeType"];
   if(_valueClassName!=nil)
    [coder encodeObject:_valueClassName forKey: @"NSAttributeValueClassName"];
   if(_defaultValue!=nil)
    [coder encodeObject:_defaultValue forKey: @"NSDefaultValue"];
   if(_valueTransformerName!=nil)
    [coder encodeObject:_valueTransformerName forKey: @"NSValueTransformerName"];
}


-copyWithZone: (NSZone *) zone {
   return [self retain];
}


-(void)dealloc {
   [_valueClassName release];
   [_defaultValue release];
   [_propertyName release];
   [_valueTransformerName release];
   [super dealloc];
}


- (NSString *) description {
    return [NSString stringWithFormat: @"<NSAttributeDescription: %@ %@>",_valueClassName, _propertyName];
}


- (NSString *) attributeValueClassName {
    return _valueClassName;
}


- (NSAttributeType) attributeType {
    return _attributeType;
}


- (id) defaultValue {
    return _defaultValue;
}


- (NSString *) valueTransformerName {
    return _valueTransformerName;
}


- (void) setAttributeType: (NSAttributeType) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    _attributeType = value;
}


- (void) setAttributeValueClassName: (NSString *) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }

    value=[value copy];
    [_valueClassName release];
    _valueClassName=value;
}


- (void) setDefaultValue: (id) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }

    value=[value retain];
    [_defaultValue release];
    _defaultValue=value;
}


- (void) setValueTransformerName: (NSString *) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }

    value=[value copy];
    [_valueTransformerName release];
    _valueTransformerName=value;
}


- (void) _appendVersionHashComponents: (NSMutableArray *) components {
    [super _appendVersionHashComponents:components];
    [components addObject:[NSString stringWithFormat:@"%d",(int)_attributeType]];
    [components addObject:(_valueClassName!=nil)?_valueClassName:@""];
}

@end

/* Conversion between transformable attribute values and their stored
   NSData representation (see NSAttributeDescription-Private.h).

   Apple's contract (NSAttributeDescription.valueTransformerName docs):
   a custom transformer must return an NSData instance from
   -transformedValue: and allow reverse transformation, so saving applies
   -transformedValue: and loading applies -reverseTransformedValue:.

   The built-in unarchiving transformers (NSUnarchiveFromDataTransformerName,
   NSKeyedUnarchiveFromDataTransformerName and, on newer Apple systems,
   NSSecureUnarchiveFromDataTransformer) transform in the opposite
   direction - data to object - and Apple applies them in reverse when
   saving.  They all archive via NSCoding, which is also what the default
   (nil name) does, so those names are mapped directly onto keyed
   archiving here. */

/* Matches the built-in unarchiving transformer names.  Verified on
   macOS: the runtime values of the Foundation constants are the short
   forms "NSKeyedUnarchiveFromData" / "NSSecureUnarchiveFromData" (also
   what Xcode's model editor writes into a model's Transformer field),
   so a substring match covers both those and the symbol-style names. */
static BOOL isUnarchiveFromDataTransformerName(NSString *name){
   return [name rangeOfString:@"UnarchiveFromData"].location!=NSNotFound;
}

@implementation NSAttributeDescription (TransformablePrivate)

- (NSData *) _dataFromTransformableValue: (id) value {
    if(value==nil)
     return nil;

    /* The default (nil) and the built-in unarchiving transformer names
       all archive via NSCoding using keyed archiving. */
    if(_valueTransformerName==nil ||
       isUnarchiveFromDataTransformerName(_valueTransformerName))
     return [NSKeyedArchiver archivedDataWithRootObject:value];

    NSValueTransformer *transformer=[NSValueTransformer valueTransformerForName:_valueTransformerName];

    if(transformer==nil){
     NSLog(@"No NSValueTransformer registered with name %@ for attribute %@",_valueTransformerName,[self name]);
     return nil;
    }

    /* A registered transformer whose class is an unarchiving transformer
       (data to object) is applied in reverse, matching Apple. */
    if(isUnarchiveFromDataTransformerName(NSStringFromClass([transformer class])))
     return [transformer reverseTransformedValue:value];

    id transformed=[transformer transformedValue:value];

    if(![transformed isKindOfClass:[NSData class]]){
     NSLog(@"Value transformer %@ for attribute %@ did not produce NSData",_valueTransformerName,[self name]);
     return nil;
    }

    return transformed;
}

- (id) _transformableValueFromData: (NSData *) data {
    if(data==nil)
     return nil;

    if(_valueTransformerName==nil ||
       isUnarchiveFromDataTransformerName(_valueTransformerName))
     return [NSKeyedUnarchiver unarchiveObjectWithData:data];

    NSValueTransformer *transformer=[NSValueTransformer valueTransformerForName:_valueTransformerName];

    if(transformer==nil){
     NSLog(@"No NSValueTransformer registered with name %@ for attribute %@",_valueTransformerName,[self name]);
     return nil;
    }

    if(isUnarchiveFromDataTransformerName(NSStringFromClass([transformer class])))
     return [transformer transformedValue:data];

    return [transformer reverseTransformedValue:data];
}

@end
