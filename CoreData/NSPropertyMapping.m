/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPropertyMapping.h>

@implementation NSPropertyMapping

-(void)dealloc {
   [_name release];
   [_valueExpression release];
   [_userInfo release];
   [super dealloc];
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
