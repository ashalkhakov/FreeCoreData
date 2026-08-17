/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>

@class NSManagedObject, NSDictionary, NSArray, NSError;

typedef enum {
    NSErrorMergePolicyType                    = 0x00,
    NSMergeByPropertyStoreTrumpMergePolicyType = 0x01,
    NSMergeByPropertyObjectTrumpMergePolicyType = 0x02,
    NSOverwriteMergePolicyType                = 0x03,
    NSRollbackMergePolicyType                 = 0x04
} NSMergePolicyType;

/* Default: causes a save to fail if there are any merge conflicts. */
COREDATA_EXPORT id NSErrorMergePolicy;
/* Merges conflicts property-by-property, external (persisted) changes
   trump in-memory changes. */
COREDATA_EXPORT id NSMergeByPropertyStoreTrumpMergePolicy;
/* Merges conflicts property-by-property, in-memory changes trump
   external (persisted) changes. */
COREDATA_EXPORT id NSMergeByPropertyObjectTrumpMergePolicy;
/* Saves the entire in-memory object over the persisted version. */
COREDATA_EXPORT id NSOverwriteMergePolicy;
/* Discards in-memory state and keeps the persisted version. */
COREDATA_EXPORT id NSRollbackMergePolicy;

/* Describes an optimistic-locking conflict. For a conflict between a
   context and the coordinator's row cache: objectSnapshot holds the
   committed values the context last read, cachedSnapshot holds the newer
   row cache values, and persistedSnapshot is nil. */
@interface NSMergeConflict : NSObject {
    NSManagedObject *_sourceObject;
    NSDictionary *_objectSnapshot;
    NSDictionary *_cachedSnapshot;
    NSDictionary *_persistedSnapshot;
    NSUInteger _newVersionNumber;
    NSUInteger _oldVersionNumber;
}

- (id)initWithSource:(NSManagedObject *)sourceObject
          newVersion:(NSUInteger)newVersion
          oldVersion:(NSUInteger)oldVersion
      cachedSnapshot:(NSDictionary *)cachedSnapshot
   persistedSnapshot:(NSDictionary *)persistedSnapshot;

- (NSManagedObject *)sourceObject;
- (NSDictionary *)objectSnapshot;
- (NSDictionary *)cachedSnapshot;
- (NSDictionary *)persistedSnapshot;
- (NSUInteger)newVersionNumber;
- (NSUInteger)oldVersionNumber;

@end

@interface NSMergePolicy : NSObject {
    NSMergePolicyType _mergeType;
}

- (id)initWithMergeType:(NSMergePolicyType)type;

- (NSMergePolicyType)mergeType;

- (BOOL)resolveConflicts:(NSArray *)list error:(NSError **)error;

@end
