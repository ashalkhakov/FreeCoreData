/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPropertyMapping.h>

/* Core Data's own class for a property mapping's transformations, named
   here only so that a mapping model written in Xcode - where the editor
   offers them - can be read.  Nothing migrates through them yet: the value
   expression is what fills a property. */
@interface NSPropertyTransform : NSObject <NSCoding>
{
   NSString     *_propertyName;
   NSExpression *_valueExpression;
   id            _prerequisiteTransform;
   BOOL          _replaceMissingValueOnly;
}
@end

@implementation NSPropertyTransform

-(id)initWithCoder:(NSCoder *)coder {
   if((self=[super init])==nil)
    return nil;

   if([coder allowsKeyedCoding]){
    _propertyName=[[coder decodeObjectForKey:@"NSPropertyName"] copy];
    _valueExpression=[[coder decodeObjectForKey:@"NSValueExpression"] retain];
    _prerequisiteTransform=[[coder decodeObjectForKey:@"NSPrerequisiteTransform"] retain];
    _replaceMissingValueOnly=[coder decodeBoolForKey:@"NSReplaceMissingValueOnly"];
   }

   return self;
}

-(void)encodeWithCoder:(NSCoder *)coder {
   if([coder allowsKeyedCoding]){
    [coder encodeObject:_propertyName forKey:@"NSPropertyName"];
    [coder encodeObject:_valueExpression forKey:@"NSValueExpression"];
    [coder encodeObject:_prerequisiteTransform forKey:@"NSPrerequisiteTransform"];
    [coder encodeBool:_replaceMissingValueOnly forKey:@"NSReplaceMissingValueOnly"];
   }
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<%@ %@ = %@>",[self class],_propertyName,_valueExpression];
}

-(void)dealloc {
   [_propertyName release];
   [_valueExpression release];
   [_prerequisiteTransform release];
   [super dealloc];
}

@end

@implementation NSPropertyMapping

-(void)dealloc {
   [_name release];
   [_valueExpression release];
   [_userInfo release];
   [_propertyTransforms release];
   [super dealloc];
}

/* A property mapping names the destination property it fills, and may carry
   the transformations Xcode's editor offers.  Those are of a class of Core
   Data's own, which is here so that a model carrying them can be read; what
   fills the property is the value expression. */
-(id)initWithCoder:(NSCoder *)coder {
   if((self=[super init])==nil)
    return nil;

   if(![coder allowsKeyedCoding]){
    [NSException raise:NSInvalidArgumentException format:@"%@ needs a keyed archive",[self class]];
    return nil;
   }

   _name=[[coder decodeObjectForKey:@"NSDestinationPropertyName"] copy];
   _valueExpression=[[coder decodeObjectForKey:@"NSValueExpression"] retain];
   _userInfo=[[coder decodeObjectForKey:@"NSUserInfo"] copy];
   _propertyTransforms=[[coder decodeObjectForKey:@"NSPropertyTransforms"] copy];

   return self;
}

-(void)encodeWithCoder:(NSCoder *)coder {
   if(![coder allowsKeyedCoding]){
    [NSException raise:NSInvalidArgumentException format:@"%@ needs a keyed archive",[self class]];
    return;
   }

   [coder encodeObject:_name forKey:@"NSDestinationPropertyName"];
   [coder encodeObject:_valueExpression forKey:@"NSValueExpression"];
   [coder encodeObject:_userInfo forKey:@"NSUserInfo"];
   [coder encodeObject:_propertyTransforms forKey:@"NSPropertyTransforms"];
}

-(NSString *)name {
   return _name;
}

-(void)setName:(NSString *)name {
   name=[name copy];
   [_name release];
   _name=name;
}

-(NSExpression *)valueExpression {
   return _valueExpression;
}

-(void)setValueExpression:(NSExpression *)expression {
   expression=[expression retain];
   [_valueExpression release];
   _valueExpression=expression;
}

-(NSDictionary *)userInfo {
   return _userInfo;
}

-(void)setUserInfo:(NSDictionary *)userInfo {
   userInfo=[userInfo copy];
   [_userInfo release];
   _userInfo=userInfo;
}

@end
