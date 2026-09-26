/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* CDObjectConstants-Private.h - managed objects and object IDs in a
   predicate, made comparable with what a store evaluates it against.

   A predicate names a row with a managed object or its NSManagedObjectID
   (department == %@), and Apple matches either, in any store. A store
   that evaluates predicates in memory compares with something of its own:
   an atomic store with its cache nodes, the SQLite store's fallback with
   the context's managed objects. Neither equals an object ID, nor an
   object of another context. So such a store evaluates a copy of the
   predicate in which each of them has been replaced by its own
   counterpart for the row. */

#import <Foundation/Foundation.h>

@class NSManagedObjectID;

/* What stands for a row in the predicate a store evaluates; nil when the
   store has no such row, and nothing in the store may equal it. */
typedef id (*CDObjectIDReplacement)(NSManagedObjectID *objectID,void *context);

/* The predicate with every managed object and object ID among its
   constants, alone or in an array, set or ordered set, replaced by what
   replace returns for its object ID; the predicate itself when it has
   none. */
NSPredicate *CDPredicateReplacingObjectIDs(NSPredicate *predicate,CDObjectIDReplacement replace,void *context);
