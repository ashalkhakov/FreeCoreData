/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPersistentStoreRequest.h>
#import <CoreData/NSPersistentStoreResult.h>

@class NSEntityDescription, NSDictionary, NSMutableDictionary;

/* Inserts rows directly into a persistent store, bypassing contexts:
   no NSManagedObjects are materialized, validation does not run, and
   loaded contexts are not told (use
   mergeChangesFromRemoteContextSave:intoContexts: afterwards).  Rows
   come from an array of attribute dictionaries, or from a handler
   called once per row until it returns YES (the dictionary from the
   final, YES-returning call is not inserted).  Attributes absent from
   a dictionary take their model default values. */
@interface NSBatchInsertRequest : NSPersistentStoreRequest {
    NSString *_entityName;
    NSEntityDescription *_entity;
    NSArray *_objectsToInsert;
    BOOL (^_dictionaryHandler)(NSMutableDictionary *obj);
    NSBatchInsertRequestResultType _resultType;
}

+ (instancetype)batchInsertRequestWithEntityName:(NSString *)entityName objects:(NSArray *)dictionaries;

- (instancetype)initWithEntityName:(NSString *)entityName objects:(NSArray *)dictionaries;
- (instancetype)initWithEntity:(NSEntityDescription *)entity objects:(NSArray *)dictionaries;
- (instancetype)initWithEntityName:(NSString *)entityName dictionaryHandler:(BOOL (^)(NSMutableDictionary *obj))handler;
- (instancetype)initWithEntity:(NSEntityDescription *)entity dictionaryHandler:(BOOL (^)(NSMutableDictionary *obj))handler;

- (NSString *)entityName;
- (NSEntityDescription *)entity;

- (NSArray *)objectsToInsert;
- (void)setObjectsToInsert:(NSArray *)dictionaries;

- (BOOL (^)(NSMutableDictionary *obj))dictionaryHandler;

- (NSBatchInsertRequestResultType)resultType;   /* default StatusOnly */
- (void)setResultType:(NSBatchInsertRequestResultType)resultType;

@end
