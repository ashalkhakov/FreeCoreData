/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSAttributeDescription.h>

@class NSExpression;

/* An attribute whose value is computed from other properties when a
   context is saved (Apple: macOS 10.15/iOS 13).  Matching Apple, the
   supported derivation expressions are:

   - a to-one key path to replicate, e.g. "name" or "author.name";
   - uppercase:/lowercase:/canonical: of a to-one string key path, where
     canonical: is the case- and diacritic-insensitive representation;
   - a to-many key path with a terminal aggregate operator, e.g.
     "friends.@count" or "items.amount.@sum" (matching Apple, an
     operator may not appear as an intermediate path component);
   - now(), the time of the save, for date attributes.

   Derived values are recomputed for the objects written by a save; a
   managed object's property does not reflect pending changes until the
   context is saved and the object refreshed (matching Apple - though
   this port may already show the new value after the save alone).

   Unlike Apple, whose atomic stores reject models containing derived
   attributes ("Core Data provided atomic stores do not support derived
   properties", verified on macOS), this port derives with a shared
   store-agnostic engine, so the SQLite, XML and in-memory stores all
   support derived attributes. */
@interface NSDerivedAttributeDescription : NSAttributeDescription {
    NSExpression *_derivationExpression;
}

- (NSExpression *)derivationExpression;

- (void)setDerivationExpression:(NSExpression *)value;

@end
