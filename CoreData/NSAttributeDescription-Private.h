/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSAttributeDescription-Private.h - conversion between transformable
   attribute values and their NSData storage representation.  Used by the
   persistent stores; not installed. */

#import <CoreData/NSAttributeDescription.h>

@interface NSAttributeDescription (TransformablePrivate)

/* Converts a transformable attribute value into the NSData instance that
   is stored, honoring valueTransformerName.  Returns nil (after logging)
   when the value cannot be transformed. */
- (NSData *)_dataFromTransformableValue:(id)value;

/* Converts stored NSData back into the attribute value.  Returns nil
   (after logging) when the data cannot be reverse transformed. */
- (id)_transformableValueFromData:(NSData *)data;

@end
