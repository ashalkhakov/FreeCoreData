/* Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPropertyDescription.h>

/* GNUstep's AppKit duplicates the NSAttributeType constants in
   NSPredicateEditorRowTemplate.h (GNUstep itself has no CoreData).  When
   that header has already been included, reuse its definition instead of
   redefining the enumerators.  Import AppKit before CoreData in programs
   that use both. */
#if !defined(_GNUstep_H_NSPredicateEditorRowTemplate)
typedef enum {
    NSUndefinedAttributeType = 0,
    NSInteger16AttributeType = 100,
    NSInteger32AttributeType = 200,
    NSInteger64AttributeType = 300,
    NSDecimalAttributeType = 400,
    NSDoubleAttributeType = 500,
    NSFloatAttributeType = 600,
    NSStringAttributeType = 700,
    NSBooleanAttributeType = 800,
    NSDateAttributeType = 900,
    NSBinaryDataAttributeType = 1000,
    NSUUIDAttributeType = 1100,
    NSURIAttributeType = 1200,
    NSTransformableAttributeType = 1800
} NSAttributeType;
#endif

@interface NSAttributeDescription : NSPropertyDescription {
    NSAttributeType _attributeType;
    NSString *_valueClassName;
    id _defaultValue;
    NSString *_valueTransformerName;
}

- (NSString *)attributeValueClassName;

- (NSAttributeType)attributeType;
- (id)defaultValue;

/* The name of the NSValueTransformer used to convert an
   NSTransformableAttributeType value to and from NSData.  Per Apple's
   documentation the transformer must return an NSData instance from
   -transformedValue: and allow reverse transformation; when the name is
   nil, a default transformer using keyed archiving (NSCoding) is
   applied.  The built-in ...UnarchiveFromData... transformers transform
   data to object and are applied in reverse, matching Apple. */
- (NSString *)valueTransformerName;

- (void)setAttributeType:(NSAttributeType)value;
- (void)setAttributeValueClassName:(NSString *)value;
- (void)setDefaultValue:(id)value;
- (void)setValueTransformerName:(NSString *)value;

@end
