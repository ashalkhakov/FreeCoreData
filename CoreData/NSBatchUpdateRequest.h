/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPersistentStoreRequest.h>
#import <CoreData/NSPersistentStoreResult.h>

@class NSEntityDescription, NSPredicate, NSDictionary;

/* Updates rows matching a predicate directly in a persistent store,
   bypassing contexts (no validation, no materialized objects, loaded
   contexts stay stale until refreshed or merged).  propertiesToUpdate
   maps attribute names (or NSPropertyDescriptions) to the new values,
   given as constants or constant NSExpressions. */
@interface NSBatchUpdateRequest : NSPersistentStoreRequest {
    NSString *_entityName;
    NSEntityDescription *_entity;
    NSPredicate *_predicate;
    BOOL _includesSubentities;
    NSDictionary *_propertiesToUpdate;
    NSBatchUpdateRequestResultType _resultType;
}

+ (instancetype)batchUpdateRequestWithEntityName:(NSString *)entityName;

- (instancetype)initWithEntityName:(NSString *)entityName;
- (instancetype)initWithEntity:(NSEntityDescription *)entity;

- (NSString *)entityName;
- (NSEntityDescription *)entity;

- (NSPredicate *)predicate;
- (void)setPredicate:(NSPredicate *)predicate;

- (BOOL)includesSubentities;                    /* default YES */
- (void)setIncludesSubentities:(BOOL)flag;

- (NSDictionary *)propertiesToUpdate;
- (void)setPropertiesToUpdate:(NSDictionary *)properties;

- (NSBatchUpdateRequestResultType)resultType;   /* default NSStatusOnlyResultType */
- (void)setResultType:(NSBatchUpdateRequestResultType)resultType;

@end
