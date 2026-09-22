/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSBatchUpdateRequest.h"
#import <CoreData/NSEntityDescription.h>
#import <Foundation/Foundation.h>

@implementation NSBatchUpdateRequest

+(instancetype)batchUpdateRequestWithEntityName:(NSString *)entityName {
   return [[[self alloc] initWithEntityName:entityName] autorelease];
}

-(instancetype)initWithEntityName:(NSString *)entityName {
   _entityName=[entityName copy];
   _includesSubentities=YES;
   _resultType=NSStatusOnlyResultType;
   return self;
}

-(instancetype)initWithEntity:(NSEntityDescription *)entity {
   self=[self initWithEntityName:[entity name]];
   _entity=[entity retain];
   return self;
}

-(void)dealloc {
   [_entityName release];
   [_entity release];
   [_predicate release];
   [_propertiesToUpdate release];
   [super dealloc];
}

-(NSPersistentStoreRequestType)requestType {
   return NSBatchUpdateRequestType;
}

-(NSString *)entityName {
   return _entityName;
}

-(NSEntityDescription *)entity {
   return _entity;
}

-(NSPredicate *)predicate {
   return _predicate;
}

-(void)setPredicate:(NSPredicate *)predicate {
   predicate=[predicate retain];
   [_predicate release];
   _predicate=predicate;
}

-(BOOL)includesSubentities {
   return _includesSubentities;
}

-(void)setIncludesSubentities:(BOOL)flag {
   _includesSubentities=flag;
}

-(NSDictionary *)propertiesToUpdate {
   return _propertiesToUpdate;
}

-(void)setPropertiesToUpdate:(NSDictionary *)properties {
   properties=[properties copy];
   [_propertiesToUpdate release];
   _propertiesToUpdate=properties;
}

-(NSBatchUpdateRequestResultType)resultType {
   return _resultType;
}

-(void)setResultType:(NSBatchUpdateRequestResultType)resultType {
   _resultType=resultType;
}

-copyWithZone:(NSZone *)zone {
   NSBatchUpdateRequest *result=[super copyWithZone:zone];

   result->_entityName=[_entityName copy];
   result->_entity=[_entity retain];
   result->_predicate=[_predicate retain];
   result->_includesSubentities=_includesSubentities;
   result->_propertiesToUpdate=[_propertiesToUpdate copy];
   result->_resultType=_resultType;
   return result;
}

@end
