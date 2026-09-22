/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSBatchInsertRequest.h"
#import <CoreData/NSEntityDescription.h>
#import <Foundation/Foundation.h>

@implementation NSBatchInsertRequest

+(instancetype)batchInsertRequestWithEntityName:(NSString *)entityName objects:(NSArray *)dictionaries {
   return [[[self alloc] initWithEntityName:entityName objects:dictionaries] autorelease];
}

-(instancetype)initWithEntityName:(NSString *)entityName objects:(NSArray *)dictionaries {
   _entityName=[entityName copy];
   _objectsToInsert=[dictionaries copy];
   _resultType=NSBatchInsertRequestResultTypeStatusOnly;
   return self;
}

-(instancetype)initWithEntity:(NSEntityDescription *)entity objects:(NSArray *)dictionaries {
   self=[self initWithEntityName:[entity name] objects:dictionaries];
   _entity=[entity retain];
   return self;
}

-(instancetype)initWithEntityName:(NSString *)entityName dictionaryHandler:(BOOL (^)(NSMutableDictionary *obj))handler {
   _entityName=[entityName copy];
   _dictionaryHandler=[handler copy];
   _resultType=NSBatchInsertRequestResultTypeStatusOnly;
   return self;
}

-(instancetype)initWithEntity:(NSEntityDescription *)entity dictionaryHandler:(BOOL (^)(NSMutableDictionary *obj))handler {
   self=[self initWithEntityName:[entity name] dictionaryHandler:handler];
   _entity=[entity retain];
   return self;
}

-(void)dealloc {
   [_entityName release];
   [_entity release];
   [_objectsToInsert release];
   [_dictionaryHandler release];
   [super dealloc];
}

-(NSPersistentStoreRequestType)requestType {
   return NSBatchInsertRequestType;
}

-(NSString *)entityName {
   return _entityName;
}

-(NSEntityDescription *)entity {
   return _entity;
}

-(NSArray *)objectsToInsert {
   return _objectsToInsert;
}

-(void)setObjectsToInsert:(NSArray *)dictionaries {
   dictionaries=[dictionaries copy];
   [_objectsToInsert release];
   _objectsToInsert=dictionaries;
}

-(BOOL (^)(NSMutableDictionary *obj))dictionaryHandler {
   return _dictionaryHandler;
}

-(NSBatchInsertRequestResultType)resultType {
   return _resultType;
}

-(void)setResultType:(NSBatchInsertRequestResultType)resultType {
   _resultType=resultType;
}

-copyWithZone:(NSZone *)zone {
   NSBatchInsertRequest *result=[super copyWithZone:zone];

   result->_entityName=[_entityName copy];
   result->_entity=[_entity retain];
   result->_objectsToInsert=[_objectsToInsert copy];
   result->_dictionaryHandler=[_dictionaryHandler copy];
   result->_resultType=_resultType;
   return result;
}

@end
