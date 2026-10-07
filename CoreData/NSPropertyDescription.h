/* Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>

@class NSEntityDescription, NSArray, NSDictionary, NSData, NSString;

@interface NSPropertyDescription : NSObject <NSCoding, NSCopying> {
    NSEntityDescription *_entity;
    NSString *_propertyName;
    NSString *_versionHashModifier;
    NSString *_renamingIdentifier;
    BOOL _optional;
    BOOL _transient;
    NSDictionary *_userInfo;
    NSArray *_validationPredicates;
    NSArray *_validationWarnings;
    BOOL _indexed;              /* until the property joins an entity */
}

- (NSEntityDescription *)entity;

- (NSString *)name;
- (BOOL)isOptional;
- (BOOL)isTransient;
- (NSDictionary *)userInfo;
- (NSArray *)validationPredicates;
- (NSArray *)validationWarnings;

- (NSData *)versionHash;
- (NSString *)versionHashModifier;
- (void)setVersionHashModifier:(NSString *)value;

/* Apple semantics: returns the name when never explicitly set. */
- (NSString *)renamingIdentifier;
- (void)setRenamingIdentifier:(NSString *)value;

/* Whether a fetch index covers the property: for an attribute, whether it
   is the only element of an ascending binary index of its entity, partial
   or not; a relationship is
   always indexed, by its foreign key.  Setting it adds (or removes) an
   index named after the property, as Apple does. */
- (BOOL)isIndexed;
- (void)setIndexed:(BOOL)value;

- (void)setName:(NSString *)value;
- (void)setOptional:(BOOL)value;
- (void)setTransient:(BOOL)value;
- (void)setUserInfo:(NSDictionary *)value;
- (void)setValidationPredicates:(NSArray *)predicates withValidationWarnings:(NSArray *)warnings;

@end
