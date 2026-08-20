/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSDerivedAttributeDescription-Private.h - the derivation engine used by
   the persistent stores and the coordinator; not installed.

   The engine is store-agnostic: every store computes derived values in
   ObjC at save time through -_derivedValueForObject:, so all store types
   support derived attributes.  The SQLite store additionally lets the
   database own same-table plain copies via GENERATED ALWAYS AS ... STORED
   columns (-_generatedColumnSourceName); those columns are omitted from
   INSERT/UPDATE statements.  String transforms are deliberately NOT
   generated columns: SQLite's UPPER()/LOWER() are ASCII-only, while the
   ObjC engine (and Apple) use full Unicode semantics. */

#import <CoreData/NSDerivedAttributeDescription.h>

@class NSError, NSManagedObject, NSManagedObjectModel;

/* Validates every derived attribute in the model; used when a persistent
   store of any type is added.  Returns NO (with *error set) when a
   derivation expression is missing, malformed or unsupported. */
BOOL _NSValidateDerivedAttributesInModel(NSManagedObjectModel *model, NSError **error);

@interface NSDerivedAttributeDescription (DerivationPrivate)

/* Validates the derivation expression against the attribute's entity. */
- (BOOL)_validateDerivationWithError:(NSError **)error;

/* Computes the derived value for `object` at save time. */
- (id)_derivedValueForObject:(NSManagedObject *)object;

/* When the derivation is a plain copy of another (non-derived) attribute
   of the same entity, returns that attribute's property name so the
   SQLite store can declare a GENERATED ALWAYS AS ... STORED column;
   returns nil for every other derivation form. */
- (NSString *)_generatedColumnSourceName;

@end
