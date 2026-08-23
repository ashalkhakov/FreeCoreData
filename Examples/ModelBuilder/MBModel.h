/* ModelBuilder — in-memory graph of an Xcode .xcdatamodel contents file.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#pragma once
#import <Foundation/Foundation.h>

@interface MBUserInfo : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *value;
+ (instancetype)entryWithKey:(NSString *)key value:(NSString *)value;
@end

@interface MBAttribute : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *attributeType;
@property (nonatomic, assign) BOOL optional;
@property (nonatomic, assign) BOOL transient;
@property (nonatomic, assign) BOOL indexed;
@property (nonatomic, assign) BOOL usesScalarValueType;
@property (nonatomic, copy) NSString *defaultValueString;
@property (nonatomic, copy) NSString *minValueString;
@property (nonatomic, copy) NSString *maxValueString;
@property (nonatomic, strong) NSMutableArray<MBUserInfo *> *userInfo;
@end

@interface MBRelationship : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *destinationEntity;
@property (nonatomic, copy) NSString *inverseName;
@property (nonatomic, copy) NSString *inverseEntity;
@property (nonatomic, assign) BOOL optional;
@property (nonatomic, assign) BOOL toMany;
@property (nonatomic, assign) NSUInteger minCount;
@property (nonatomic, assign) NSUInteger maxCount;
@property (nonatomic, copy) NSString *deletionRule;
@property (nonatomic, strong) NSMutableArray<MBUserInfo *> *userInfo;
@end

@interface MBEntity : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *representedClassName;
@property (nonatomic, copy) NSString *parentEntity;
@property (nonatomic, assign) BOOL isAbstract;
@property (nonatomic, assign) BOOL syncable;
@property (nonatomic, strong) NSMutableArray<MBAttribute *> *attributes;
@property (nonatomic, strong) NSMutableArray<MBRelationship *> *relationships;
@property (nonatomic, strong) NSMutableArray<MBUserInfo *> *userInfo;
@property (nonatomic, assign) NSInteger positionX;
@property (nonatomic, assign) NSInteger positionY;
@property (nonatomic, assign) NSInteger canvasWidth;
@property (nonatomic, assign) NSInteger canvasHeight;
- (MBAttribute *)attributeNamed:(NSString *)name;
- (MBRelationship *)relationshipNamed:(NSString *)name;
@end

@interface MBFetchRequest : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *entityName;
@property (nonatomic, copy) NSString *predicateString;
@end

@interface MBModel : NSObject
@property (nonatomic, copy) NSString *versionName;
@property (nonatomic, copy) NSString *sourceLanguage;
@property (nonatomic, copy) NSString *userDefinedModelVersionIdentifier;
@property (nonatomic, strong) NSMutableArray<MBEntity *> *entities;
@property (nonatomic, strong) NSMutableArray<MBFetchRequest *> *fetchRequests;

+ (NSArray<NSString *> *)attributeTypeNames;
+ (NSArray<NSString *> *)deletionRuleNames;

- (BOOL)loadFromXMLString:(NSString *)xml error:(NSError **)error;
- (NSString *)XMLString;

- (MBEntity *)entityNamed:(NSString *)name;
- (MBEntity *)addEntityNamed:(NSString *)name;
- (void)removeEntity:(MBEntity *)entity;
- (MBFetchRequest *)addFetchRequestNamed:(NSString *)name entityName:(NSString *)entityName;
- (void)removeFetchRequest:(MBFetchRequest *)request;
- (void)renameEntity:(MBEntity *)entity to:(NSString *)newName;
- (NSString *)uniqueEntityName;
- (NSString *)uniqueName:(NSString *)base among:(NSArray *)names;
@end
