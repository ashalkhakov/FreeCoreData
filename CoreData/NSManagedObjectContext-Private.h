/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net> (Cocotron project)
   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSManagedObjectContext.h>

@class NSAtomicStoreCacheNode;

@interface NSManagedObjectContext (private)
- (NSAtomicStoreCacheNode *)_cacheNodeForObjectID:(NSManagedObjectID *)objectID;
- (void)_registerObject:(NSManagedObject *)object;

/* Undo support.  Managed objects report every mutation here from
   -willChangeValueForKey: BEFORE the change applies, so the context can
   snapshot the pre-change primitive value for the undo manager.
   Registration is suspended (recursively) around work that must never
   be undoable, e.g. fault realization / awakeFromFetch. */
- (void)_object:(NSManagedObject *)object willChangeValueForKey:(NSString *)key;
- (void)_disableUndoRegistration;
- (void)_enableUndoRegistration;
@end
