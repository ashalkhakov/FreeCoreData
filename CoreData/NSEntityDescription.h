/* Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/Foundation.h>

@class NSManagedObject, NSManagedObjectContext, NSManagedObjectModel, NSPropertyDescription, NSAttributeDescription;

@interface NSEntityDescription : NSObject {
    NSString *_className;
    NSString *_name;
    NSManagedObjectModel *_model;
    /* Apple's -properties order is UNSPECIFIED - macOS returns
       dictionary hash order, not setProperties: order (verified by
       testPropertiesPreserveTheirOrder's arbitration run).  The port
       picks insertion order as its deterministic instance of
       "unspecified": the ordered array is the authoritative storage,
       the dictionary a name index over it.  Order-sensitive tooling
       (the code generator) must impose its own ordering either way. */
    NSMutableArray *_properties;
    NSMutableDictionary *_propertiesByName;
    NSMutableDictionary *_subentities;
    NSEntityDescription *_superentity;
    NSDictionary *_userInfo;
    id _versionHashModifier;
    NSString *_renamingIdentifier;
    NSMutableDictionary *_selectorPropertyMap;
    NSArray *_uniquenessConstraints;
    NSArray *_compoundIndexes;
    BOOL _isAbstract;
    BOOL _hasBeenInstantiated;
}

- (BOOL)_hasBeenInstantiated;

+ (NSEntityDescription *)entityForName:(NSString *)entityName inManagedObjectContext:(NSManagedObjectContext *)moc;

+ insertNewObjectForEntityForName:(NSString *)entityName inManagedObjectContext:(NSManagedObjectContext *)moc;

- (NSManagedObjectModel *)managedObjectModel;

- (NSString *)name;
- (BOOL)isAbstract;
- (NSString *)managedObjectClassName;
- (NSArray *)properties;
- (NSArray *)subentities;
- (NSDictionary *)userInfo;

- (void)setName:(NSString *)value;
- (void)setAbstract:(BOOL)value;
- (void)setManagedObjectClassName:(NSString *)value;
- (void)setProperties:(NSArray *)value;
- (void)setSubentities:(NSArray *)value;
- (void)setUserInfo:(NSDictionary *)value;

- (NSEntityDescription *)superentity;
- (NSDictionary *)subentitiesByName;
- (NSDictionary *)attributesByName;
- (NSDictionary *)propertiesByName;
- (NSDictionary *)relationshipsByName;
- (NSArray *)relationshipsWithDestinationEntity:(NSEntityDescription *)entity;

- (NSData *)versionHash;
- (NSString *)versionHashModifier;
- (void)setVersionHashModifier:(NSString *)value;

/* Apple semantics: returns the name when never explicitly set. */
- (NSString *)renamingIdentifier;
- (void)setRenamingIdentifier:(NSString *)value;

/* An array of arrays; each inner array holds NSAttributeDescriptions or
   attribute-name strings whose combined value must be unique per
   instance.  Matching Apple, the constraints are part of the entity's
   version hash.  NOTE: the built-in stores do not enforce the
   constraints yet - the model metadata is exposed for store
   implementations (and tooling) to consume. */
- (NSArray *)uniquenessConstraints;
- (void)setUniquenessConstraints:(NSArray *)value;

/* Deprecated on Apple (replaced by fetch indexes); verified on macOS,
   the setter is a no-op there and the getter returns an empty array.
   This port stores the value for callers that still use the API. */
- (NSArray *)compoundIndexes;
- (void)setCompoundIndexes:(NSArray *)value;

@end
