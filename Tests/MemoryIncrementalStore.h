/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* MemoryIncrementalStore - a minimal in-memory NSIncrementalStore subclass
   shared by the incremental store test cases. */

#import <CoreData/CoreData.h>

/* A minimal in-memory NSIncrementalStore subclass implementing the
   documented NSIncrementalStore contract.  It is deliberately written
   against Apple's official documentation so that the test cases run
   identically against Apple's CoreData on macOS and against the GNUstep
   port.  Rows are kept as: entity name -> (reference object -> attribute
   values dictionary). */

extern NSString * const MemoryIncrementalStoreType;

@interface MemoryIncrementalStore : NSIncrementalStore

@property (nonatomic, strong) NSMutableDictionary *rows;

@property (nonatomic) NSUInteger loadMetadataCallCount;
@property (nonatomic) NSUInteger fetchRequestCount;
@property (nonatomic) NSUInteger saveRequestCount;
@property (nonatomic) NSUInteger newValuesCallCount;
@property (nonatomic) NSUInteger obtainPermanentIDsCallCount;
@property (nonatomic) NSUInteger lastInsertedCount;
@property (nonatomic) NSUInteger lastUpdatedCount;
@property (nonatomic) NSUInteger lastDeletedCount;
@property (nonatomic) long long nextReferenceNumber;

- (NSMutableDictionary *)tableForEntityName:(NSString *)entityName;

@end

/* An incremental store registered under one type whose -type reports
   another; adding it must fail with NSPersistentStoreTypeMismatchError
   (134010), mirroring Apple. */
extern NSString * const MismatchIncrementalStoreType;

@interface MismatchIncrementalStore : MemoryIncrementalStore
@end

/* A two-attribute Person model used by the incremental store tests. */
NSManagedObjectModel *IncrementalStoreTestModel(void);
