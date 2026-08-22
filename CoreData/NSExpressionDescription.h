/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPropertyDescription.h>
#import <CoreData/NSAttributeDescription.h>

@class NSExpression;

/* Describes a computed column for a fetch request's propertiesToFetch:
   the row value for `name` is the expression evaluated against the
   fetched row - a key path, or an aggregate (count:/sum:/min:/max:/
   average:) over the rows of the group when propertiesToGroupBy is in
   effect (over all rows otherwise).  Used with NSDictionaryResultType. */
@interface NSExpressionDescription : NSPropertyDescription {
    NSExpression *_expression;
    NSAttributeType _expressionResultType;
}

- (NSExpression *)expression;
- (void)setExpression:(NSExpression *)value;

- (NSAttributeType)expressionResultType;
- (void)setExpressionResultType:(NSAttributeType)value;

@end
