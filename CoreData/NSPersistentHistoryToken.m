/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSPersistentHistoryToken.h"
#import "NSPersistentHistory-Private.h"
#import <Foundation/Foundation.h>

@implementation NSPersistentHistoryToken

-(void)dealloc {
   [_positions release];
   [super dealloc];
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<%@: %p %@>",[self class],self,_positions];
}

-(NSUInteger)hash {
   return [_positions hash];
}

-(BOOL)isEqual:other {
   if(![other isKindOfClass:[NSPersistentHistoryToken class]])
    return NO;
   return [_positions isEqual:((NSPersistentHistoryToken *)other)->_positions];
}

-copyWithZone:(NSZone *)zone {
   return [self retain];   /* immutable */
}

+(BOOL)supportsSecureCoding {
   return YES;
}

-initWithCoder:(NSCoder *)coder {
   NSSet *classes=[NSSet setWithObjects:[NSDictionary class],[NSString class],[NSNumber class],nil];

   _positions=[[coder decodeObjectOfClasses:classes forKey:@"positions"] copy];
   return self;
}

-(void)encodeWithCoder:(NSCoder *)coder {
   [coder encodeObject:_positions forKey:@"positions"];
}

@end

@implementation NSPersistentHistoryToken (CDPrivate)

+(instancetype)tokenWithTransactionNumbersByStoreIdentifier:(NSDictionary *)numbers {
   return [[[self alloc] _initWithPositions:numbers] autorelease];
}

-(int64_t)transactionNumberForStoreIdentifier:(NSString *)identifier {
   return [self _transactionNumberForStoreIdentifier:identifier];
}

-(instancetype)_initWithPositions:(NSDictionary *)positions {
   _positions=[positions copy];
   return self;
}

-(NSDictionary *)_positions {
   return _positions;
}

/* The transaction number this token stands at for the given store; 0
   (everything is "after") when the token has never seen the store. */
-(long long)_transactionNumberForStoreIdentifier:(NSString *)identifier {
   return [[_positions objectForKey:identifier] longLongValue];
}

@end
