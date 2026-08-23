/* ModelBuilder — in-memory graph of an Xcode .xcdatamodel contents file.
   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBModel.h"

static NSString *MBAttr(NSXMLElement *el, NSString *name)
{
  NSXMLNode *node = [el attributeForName:name];
  return node.stringValue;
}

static BOOL MBFlag(NSXMLElement *el, NSString *name, BOOL fallback)
{
  NSString *value = MBAttr(el, name);
  if (!value.length) return fallback;
  return [value isEqualToString:@"YES"] || [value isEqualToString:@"true"];
}

static void MBSetAttr(NSXMLElement *el, NSString *name, NSString *value)
{
  if (!value.length) return;
  [el addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
}

static void MBSetFlag(NSXMLElement *el, NSString *name, BOOL on)
{
  [el addAttribute:[NSXMLNode attributeWithName:name stringValue:on ? @"YES" : @"NO"]];
}

static NSMutableArray *MBReadUserInfo(NSXMLElement *parent)
{
  NSMutableArray *rows = [NSMutableArray array];
  for (NSXMLElement *info in [parent elementsForName:@"userInfo"]) {
    for (NSXMLElement *entry in [info elementsForName:@"entry"]) {
      MBUserInfo *row = [MBUserInfo entryWithKey:MBAttr(entry, @"key")
                                          value:MBAttr(entry, @"value")];
      if (row.key.length) [rows addObject:row];
    }
  }
  return rows;
}

static void MBWriteUserInfo(NSXMLElement *parent, NSArray<MBUserInfo *> *rows)
{
  if (!rows.count) return;
  NSXMLElement *info = [NSXMLElement elementWithName:@"userInfo"];
  for (MBUserInfo *row in rows) {
    if (!row.key.length) continue;
    NSXMLElement *entry = [NSXMLElement elementWithName:@"entry"];
    MBSetAttr(entry, @"key", row.key);
    MBSetAttr(entry, @"value", row.value ?: @"");
    [info addChild:entry];
  }
  if (info.childCount) [parent addChild:info];
}

@implementation MBUserInfo
+ (instancetype)entryWithKey:(NSString *)key value:(NSString *)value
{
  MBUserInfo *row = [[self alloc] init];
  row.key = key;
  row.value = value;
  return row;
}
@end

@implementation MBAttribute
- (instancetype)init
{
  self = [super init];
  if (!self) return nil;
  _name = @"attribute";
  _attributeType = @"String";
  _optional = YES;
  _userInfo = [NSMutableArray array];
  return self;
}
@end

@implementation MBRelationship
- (instancetype)init
{
  self = [super init];
  if (!self) return nil;
  _name = @"relationship";
  _optional = YES;
  _toMany = NO;
  _ordered = NO;
  _maxCount = 1;
  _deletionRule = @"Nullify";
  _userInfo = [NSMutableArray array];
  return self;
}
@end

@implementation MBEntity
- (instancetype)init
{
  self = [super init];
  if (!self) return nil;
  _name = @"Entity";
  _syncable = YES;
  _attributes = [NSMutableArray array];
  _relationships = [NSMutableArray array];
  _userInfo = [NSMutableArray array];
  _canvasWidth = 140;
  _canvasHeight = 88;
  return self;
}
- (MBAttribute *)attributeNamed:(NSString *)name
{
  for (MBAttribute *a in self.attributes)
    if ([a.name isEqualToString:name]) return a;
  return nil;
}
- (MBRelationship *)relationshipNamed:(NSString *)name
{
  for (MBRelationship *r in self.relationships)
    if ([r.name isEqualToString:name]) return r;
  return nil;
}
@end

@implementation MBFetchRequest
- (instancetype)init
{
  self = [super init];
  if (!self) return nil;
  _name = @"fetch";
  _predicateString = @"";
  return self;
}
@end

@implementation MBModel

+ (NSArray<NSString *> *)attributeTypeNames
{
  return @[
    @"Undefined", @"Integer 16", @"Integer 32", @"Integer 64",
    @"Decimal", @"Double", @"Float", @"String", @"Boolean",
    @"Date", @"Binary", @"UUID", @"URI", @"Transformable", @"Object ID"
  ];
}

+ (NSArray<NSString *> *)deletionRuleNames
{
  return @[ @"Nullify", @"Cascade", @"Deny", @"No Action" ];
}

- (instancetype)init
{
  self = [super init];
  if (!self) return nil;
  _versionName = @"Model.xcdatamodel";
  _sourceLanguage = @"Objective-C";
  _userDefinedModelVersionIdentifier = @"";
  _entities = [NSMutableArray array];
  _fetchRequests = [NSMutableArray array];
  return self;
}

- (MBEntity *)entityNamed:(NSString *)name
{
  for (MBEntity *e in self.entities)
    if ([e.name isEqualToString:name]) return e;
  return nil;
}

- (NSString *)uniqueName:(NSString *)base among:(NSArray *)names
{
  if (![names containsObject:base]) return base;
  NSInteger n = 1;
  while ([names containsObject:[NSString stringWithFormat:@"%@%ld", base, (long)n]])
    n++;
  return [NSString stringWithFormat:@"%@%ld", base, (long)n];
}

- (NSString *)uniqueEntityName
{
  NSMutableArray *names = [NSMutableArray array];
  for (MBEntity *e in self.entities) if (e.name) [names addObject:e.name];
  return [self uniqueName:@"Entity" among:names];
}

- (MBEntity *)addEntityNamed:(NSString *)name
{
  MBEntity *entity = [[MBEntity alloc] init];
  entity.name = name.length ? name : [self uniqueEntityName];
  entity.positionX = (NSInteger)self.entities.count * 180;
  [self.entities addObject:entity];
  return entity;
}

- (void)removeEntity:(MBEntity *)entity
{
  if (!entity) return;
  NSString *name = entity.name;
  [self.entities removeObject:entity];
  for (MBEntity *other in self.entities) {
    if ([other.parentEntity isEqualToString:name]) other.parentEntity = nil;
    NSMutableArray *drop = [NSMutableArray array];
    for (MBRelationship *rel in other.relationships) {
      if ([rel.destinationEntity isEqualToString:name]) [drop addObject:rel];
    }
    [other.relationships removeObjectsInArray:drop];
  }
  NSMutableArray *fetches = [NSMutableArray array];
  for (MBFetchRequest *req in self.fetchRequests) {
    if ([req.entityName isEqualToString:name]) [fetches addObject:req];
  }
  [self.fetchRequests removeObjectsInArray:fetches];
}

- (void)renameEntity:(MBEntity *)entity to:(NSString *)newName
{
  if (!entity || !newName.length || [entity.name isEqualToString:newName]) return;
  if ([self entityNamed:newName]) return;
  NSString *old = entity.name;
  entity.name = newName;
  for (MBEntity *other in self.entities) {
    if ([other.parentEntity isEqualToString:old]) other.parentEntity = newName;
    for (MBRelationship *rel in other.relationships) {
      if ([rel.destinationEntity isEqualToString:old]) rel.destinationEntity = newName;
      if ([rel.inverseEntity isEqualToString:old]) rel.inverseEntity = newName;
    }
  }
  for (MBFetchRequest *req in self.fetchRequests) {
    if ([req.entityName isEqualToString:old]) req.entityName = newName;
  }
}

- (MBFetchRequest *)addFetchRequestNamed:(NSString *)name entityName:(NSString *)entityName
{
  NSMutableArray *names = [NSMutableArray array];
  for (MBFetchRequest *r in self.fetchRequests) if (r.name) [names addObject:r.name];
  MBFetchRequest *req = [[MBFetchRequest alloc] init];
  req.name = name.length ? name : [self uniqueName:@"Fetch" among:names];
  req.entityName = entityName;
  [self.fetchRequests addObject:req];
  return req;
}

- (void)removeFetchRequest:(MBFetchRequest *)request
{
  if (request) [self.fetchRequests removeObject:request];
}

- (BOOL)loadFromXMLString:(NSString *)xml error:(NSError **)error
{
  if (!xml.length) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:1
                               userInfo:@{ NSLocalizedDescriptionKey: @"Empty model file." }];
    }
    return NO;
  }
  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:error];
  if (!doc) return NO;
  NSXMLElement *root = doc.rootElement;
  if (![root.name isEqualToString:@"model"]) {
    if (error) {
      *error = [NSError errorWithDomain:@"ModelBuilder" code:2
                               userInfo:@{ NSLocalizedDescriptionKey: @"Not an Xcode data model." }];
    }
    return NO;
  }
  NSString *lang = MBAttr(root, @"sourceLanguage");
  if (lang.length) self.sourceLanguage = lang;
  NSString *ident = MBAttr(root, @"userDefinedModelVersionIdentifier");
  if (ident) self.userDefinedModelVersionIdentifier = ident;

  [self.entities removeAllObjects];
  [self.fetchRequests removeAllObjects];

  for (NSXMLElement *el in [root elementsForName:@"entity"]) {
    MBEntity *entity = [[MBEntity alloc] init];
    entity.name = MBAttr(el, @"name") ?: @"Entity";
    entity.representedClassName = MBAttr(el, @"representedClassName");
    entity.parentEntity = MBAttr(el, @"parentEntity");
    entity.isAbstract = MBFlag(el, @"isAbstract", NO);
    entity.syncable = MBFlag(el, @"syncable", YES);
    for (NSXMLElement *ael in [el elementsForName:@"attribute"]) {
      MBAttribute *attr = [[MBAttribute alloc] init];
      attr.name = MBAttr(ael, @"name") ?: @"attribute";
      attr.attributeType = MBAttr(ael, @"attributeType") ?: @"String";
      attr.optional = MBFlag(ael, @"optional", NO);
      attr.transient = MBFlag(ael, @"transient", NO);
      attr.indexed = MBFlag(ael, @"indexed", NO);
      attr.usesScalarValueType = MBFlag(ael, @"usesScalarValueType", NO);
      attr.defaultValueString = MBAttr(ael, @"defaultValueString");
      attr.minValueString = MBAttr(ael, @"minValueString");
      attr.maxValueString = MBAttr(ael, @"maxValueString");
      attr.userInfo = MBReadUserInfo(ael);
      [entity.attributes addObject:attr];
    }
    for (NSXMLElement *relEl in [el elementsForName:@"relationship"]) {
      MBRelationship *rel = [[MBRelationship alloc] init];
      rel.name = MBAttr(relEl, @"name") ?: @"relationship";
      rel.destinationEntity = MBAttr(relEl, @"destinationEntity");
      rel.inverseName = MBAttr(relEl, @"inverseName");
      rel.inverseEntity = MBAttr(relEl, @"inverseEntity");
      rel.optional = MBFlag(relEl, @"optional", NO);
      rel.toMany = MBFlag(relEl, @"toMany", NO);
      rel.ordered = MBFlag(relEl, @"ordered", NO);
      rel.deletionRule = MBAttr(relEl, @"deletionRule") ?: @"Nullify";
      NSString *minS = MBAttr(relEl, @"minCount");
      NSString *maxS = MBAttr(relEl, @"maxCount");
      if (minS.length) rel.minCount = (NSUInteger)minS.integerValue;
      if (maxS.length) {
        rel.maxCount = (NSUInteger)maxS.integerValue;
        if (rel.maxCount == 1) rel.toMany = NO;
      } else if (rel.toMany) {
        rel.maxCount = 0;
      } else {
        rel.maxCount = 1;
      }
      rel.userInfo = MBReadUserInfo(relEl);
      [entity.relationships addObject:rel];
    }
    entity.userInfo = MBReadUserInfo(el);
    [self.entities addObject:entity];
  }

  for (NSXMLElement *el in [root elementsForName:@"fetchRequest"]) {
    MBFetchRequest *req = [[MBFetchRequest alloc] init];
    req.name = MBAttr(el, @"name") ?: @"fetch";
    req.entityName = MBAttr(el, @"entity");
    req.predicateString = MBAttr(el, @"predicateString") ?: @"";
    [self.fetchRequests addObject:req];
  }

  for (NSXMLElement *wrap in [root elementsForName:@"elements"]) {
    for (NSXMLElement *el in [wrap elementsForName:@"element"]) {
      MBEntity *entity = [self entityNamed:MBAttr(el, @"name")];
      if (!entity) continue;
      entity.positionX = MBAttr(el, @"positionX").integerValue;
      entity.positionY = MBAttr(el, @"positionY").integerValue;
      entity.canvasWidth = MBAttr(el, @"width").integerValue ?: 140;
      entity.canvasHeight = MBAttr(el, @"height").integerValue ?: 88;
    }
  }
  return YES;
}

- (NSString *)XMLString
{
  NSXMLElement *root = [NSXMLElement elementWithName:@"model"];
  MBSetAttr(root, @"type", @"com.apple.IDECoreDataModeler.DataModel");
  MBSetAttr(root, @"documentVersion", @"1.0");
  MBSetAttr(root, @"lastSavedToolsVersion", @"ModelBuilder");
  MBSetAttr(root, @"minimumToolsVersion", @"Automatic");
  MBSetAttr(root, @"sourceLanguage", self.sourceLanguage.length ? self.sourceLanguage : @"Objective-C");
  MBSetAttr(root, @"userDefinedModelVersionIdentifier",
            self.userDefinedModelVersionIdentifier ?: @"");

  for (MBEntity *entity in self.entities) {
    NSXMLElement *el = [NSXMLElement elementWithName:@"entity"];
    MBSetAttr(el, @"name", entity.name);
    MBSetAttr(el, @"representedClassName", entity.representedClassName);
    MBSetAttr(el, @"parentEntity", entity.parentEntity);
    if (entity.isAbstract) MBSetFlag(el, @"isAbstract", YES);
    MBSetFlag(el, @"syncable", entity.syncable);
    for (MBAttribute *attr in entity.attributes) {
      NSXMLElement *ael = [NSXMLElement elementWithName:@"attribute"];
      MBSetAttr(ael, @"name", attr.name);
      if (attr.optional) MBSetFlag(ael, @"optional", YES);
      else MBSetFlag(ael, @"optional", NO);
      if (attr.transient) MBSetFlag(ael, @"transient", YES);
      if (attr.indexed) MBSetFlag(ael, @"indexed", YES);
      MBSetAttr(ael, @"attributeType", attr.attributeType ?: @"String");
      MBSetAttr(ael, @"defaultValueString", attr.defaultValueString);
      MBSetAttr(ael, @"minValueString", attr.minValueString);
      MBSetAttr(ael, @"maxValueString", attr.maxValueString);
      if (attr.usesScalarValueType) MBSetFlag(ael, @"usesScalarValueType", YES);
      else MBSetFlag(ael, @"usesScalarValueType", NO);
      MBWriteUserInfo(ael, attr.userInfo);
      [el addChild:ael];
    }
    for (MBRelationship *rel in entity.relationships) {
      NSXMLElement *relEl = [NSXMLElement elementWithName:@"relationship"];
      MBSetAttr(relEl, @"name", rel.name);
      if (rel.optional) MBSetFlag(relEl, @"optional", YES);
      else MBSetFlag(relEl, @"optional", NO);
      if (rel.toMany) {
        MBSetFlag(relEl, @"toMany", YES);
        if (rel.ordered) MBSetFlag(relEl, @"ordered", YES);
      } else {
        MBSetAttr(relEl, @"maxCount", @"1");
      }
      if (rel.minCount > 0)
        MBSetAttr(relEl, @"minCount", [NSString stringWithFormat:@"%lu", (unsigned long)rel.minCount]);
      if (rel.toMany && rel.maxCount > 0)
        MBSetAttr(relEl, @"maxCount", [NSString stringWithFormat:@"%lu", (unsigned long)rel.maxCount]);
      MBSetAttr(relEl, @"deletionRule", rel.deletionRule.length ? rel.deletionRule : @"Nullify");
      MBSetAttr(relEl, @"destinationEntity", rel.destinationEntity);
      MBSetAttr(relEl, @"inverseName", rel.inverseName);
      MBSetAttr(relEl, @"inverseEntity", rel.inverseEntity);
      MBWriteUserInfo(relEl, rel.userInfo);
      [el addChild:relEl];
    }
    MBWriteUserInfo(el, entity.userInfo);
    [root addChild:el];
  }

  for (MBFetchRequest *req in self.fetchRequests) {
    NSXMLElement *el = [NSXMLElement elementWithName:@"fetchRequest"];
    MBSetAttr(el, @"name", req.name);
    MBSetAttr(el, @"entity", req.entityName);
    MBSetAttr(el, @"predicateString", req.predicateString ?: @"");
    [root addChild:el];
  }

  NSXMLElement *elements = [NSXMLElement elementWithName:@"elements"];
  for (MBEntity *entity in self.entities) {
    NSXMLElement *el = [NSXMLElement elementWithName:@"element"];
    MBSetAttr(el, @"name", entity.name);
    MBSetAttr(el, @"positionX", [NSString stringWithFormat:@"%ld", (long)entity.positionX]);
    MBSetAttr(el, @"positionY", [NSString stringWithFormat:@"%ld", (long)entity.positionY]);
    MBSetAttr(el, @"width", [NSString stringWithFormat:@"%ld", (long)(entity.canvasWidth ?: 140)]);
    MBSetAttr(el, @"height", [NSString stringWithFormat:@"%ld", (long)(entity.canvasHeight ?: 88)]);
    [elements addChild:el];
  }
  [root addChild:elements];

  NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
  doc.version = @"1.0";
  doc.characterEncoding = @"UTF-8";
  doc.standalone = YES;
  return [doc XMLStringWithOptions:NSXMLNodePrettyPrint];
}

@end
