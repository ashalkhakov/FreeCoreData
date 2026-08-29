/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSEntityDescription-Private.h"
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/NSPropertyDescription.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import <CoreData/NSManagedObject.h>
#import <Foundation/Foundation.h>
#import "CoreDataUtilities.h"
#import "CoreDataVersioning-Private.h"
#import <objc/runtime.h>
#import <ctype.h>
#import <string.h>
#import <stdint.h>


@interface NSPropertyDescription(CoreDataPrivate)
- (void)_setEntity:(NSEntityDescription *)entity;
@end

@implementation NSEntityDescription

static id getValue(id self, SEL selector) {
    NSPropertyDescription *property = [[self entity] _propertyForSelector: selector];
    id result= [self valueForKey:[property name]];
   return result;
}


static void setValue(id self, SEL selector, id newValue) {
    NSPropertyDescription *property = [[self entity] _propertyForSelector: selector];
    [self setValue: newValue forKey:[property name]];
}

/* Scalar-typed accessors.  A @dynamic property declared with a scalar
   type ("@property (nonatomic) float depthHack;") must be backed by an
   IMP whose ABI matches that declaration: the object-typed getValue
   above returns an NSNumber pointer in the integer return register,
   while the caller of a float property reads the FP return register -
   so scalar reads through dot syntax returned garbage (and writes
   corrupted, boxing the bit pattern of a float as a pointer).  KVC was
   unaffected, which masked the bug (reported by UDQuakeTools).  One
   getter/setter pair per scalar encoding, boxing through KVC like the
   object versions. */
#define CD_SCALAR_ACCESSORS(SUFFIX,TYPE,BOX,UNBOX) \
static TYPE getValue_##SUFFIX(id self,SEL selector) { \
    NSPropertyDescription *property=[[self entity] _propertyForSelector:selector]; \
    return [[self valueForKey:[property name]] UNBOX]; \
} \
static void setValue_##SUFFIX(id self,SEL selector,TYPE newValue) { \
    NSPropertyDescription *property=[[self entity] _propertyForSelector:selector]; \
    [self setValue:[NSNumber BOX:newValue] forKey:[property name]]; \
}

CD_SCALAR_ACCESSORS(char,signed char,numberWithChar,charValue)
CD_SCALAR_ACCESSORS(uchar,unsigned char,numberWithUnsignedChar,unsignedCharValue)
CD_SCALAR_ACCESSORS(bool,bool,numberWithBool,boolValue)
CD_SCALAR_ACCESSORS(short,short,numberWithShort,shortValue)
CD_SCALAR_ACCESSORS(ushort,unsigned short,numberWithUnsignedShort,unsignedShortValue)
CD_SCALAR_ACCESSORS(int,int,numberWithInt,intValue)
CD_SCALAR_ACCESSORS(uint,unsigned int,numberWithUnsignedInt,unsignedIntValue)
CD_SCALAR_ACCESSORS(long,long,numberWithLong,longValue)
CD_SCALAR_ACCESSORS(ulong,unsigned long,numberWithUnsignedLong,unsignedLongValue)
CD_SCALAR_ACCESSORS(longlong,long long,numberWithLongLong,longLongValue)
CD_SCALAR_ACCESSORS(ulonglong,unsigned long long,numberWithUnsignedLongLong,unsignedLongLongValue)
CD_SCALAR_ACCESSORS(float,float,numberWithFloat,floatValue)
CD_SCALAR_ACCESSORS(double,double,numberWithDouble,doubleValue)

#undef CD_SCALAR_ACCESSORS

/* Getter/setter IMP pair for one scalar type encoding character, or
   NULL IMPs when the encoding is not a supported scalar. */
static void scalarAccessorsForEncoding(char encoding,IMP *getterp,IMP *setterp){
    switch(encoding){
        case 'c': *getterp=(IMP)getValue_char;     *setterp=(IMP)setValue_char;     return;
        case 'C': *getterp=(IMP)getValue_uchar;    *setterp=(IMP)setValue_uchar;    return;
        case 'B': *getterp=(IMP)getValue_bool;     *setterp=(IMP)setValue_bool;     return;
        case 's': *getterp=(IMP)getValue_short;    *setterp=(IMP)setValue_short;    return;
        case 'S': *getterp=(IMP)getValue_ushort;   *setterp=(IMP)setValue_ushort;   return;
        case 'i': *getterp=(IMP)getValue_int;      *setterp=(IMP)setValue_int;      return;
        case 'I': *getterp=(IMP)getValue_uint;     *setterp=(IMP)setValue_uint;     return;
        case 'l': *getterp=(IMP)getValue_long;     *setterp=(IMP)setValue_long;     return;
        case 'L': *getterp=(IMP)getValue_ulong;    *setterp=(IMP)setValue_ulong;    return;
        case 'q': *getterp=(IMP)getValue_longlong; *setterp=(IMP)setValue_longlong; return;
        case 'Q': *getterp=(IMP)getValue_ulonglong;*setterp=(IMP)setValue_ulonglong;return;
        case 'f': *getterp=(IMP)getValue_float;    *setterp=(IMP)setValue_float;    return;
        case 'd': *getterp=(IMP)getValue_double;   *setterp=(IMP)setValue_double;   return;
        default:  *getterp=NULL;                   *setterp=NULL;                   return;
    }
}

/* First character of the declared @property type on the target class
   (from the runtime's "T<encoding>,..." attribute string), or 0 when
   the class declares no such property. */
static char declaredPropertyTypeEncoding(Class class,NSString *propertyName){
    objc_property_t property=class_getProperty(class,[propertyName UTF8String]);

    if(property==NULL)
        return 0;

    const char *attributes=property_getAttributes(property);

    if(attributes==NULL || attributes[0]!='T')
        return 0;
    return attributes[1];
}

static void addObject(id self,SEL selector, id value){
   NSPropertyDescription *property=[[self entity] _propertyForSelector:selector];
   NSMutableSet *set=[self mutableSetValueForKey:[property name]];

   [set addObject:value];
}

static void removeObject(id self,SEL selector, id value){
   NSPropertyDescription *property=[[self entity] _propertyForSelector:selector];
   NSMutableSet *set=[self mutableSetValueForKey:[property name]];
   [set removeObject:value];
}

static void addObjectSet(id self,SEL selector,NSSet *values){
   NSPropertyDescription *property=[[self entity] _propertyForSelector:selector];
   NSMutableSet *set=[self mutableSetValueForKey:[property name]];
   [set unionSet:values];
}

static void removeObjectSet(id self,SEL selector,NSSet *values){
   NSPropertyDescription *property=[[self entity] _propertyForSelector:selector];
   NSMutableSet *set=[self mutableSetValueForKey:[property name]];
   [set minusSet:values];
}

BOOL _NSManagedObjectIMPIsGeneratedAccessor(IMP imp) {
   if(imp==(IMP)getValue || imp==(IMP)setValue || imp==(IMP)addObject ||
      imp==(IMP)removeObject || imp==(IMP)addObjectSet || imp==(IMP)removeObjectSet)
    return YES;

   /* The scalar accessors read through -valueForKey:; failing to
      recognize them here would make that read recurse forever. */
   static const char scalarEncodings[]="cCBsSiIlLqQfd";

   for(const char *encoding=scalarEncodings;*encoding!=0;encoding++){
    IMP getter=NULL,setter=NULL;

    scalarAccessorsForEncoding(*encoding,&getter,&setter);
    if(imp==getter || imp==setter)
     return YES;
   }
   return NO;
}

id keyObjectForSelector(SEL selector){
   return [NSNumber numberWithInteger: (NSInteger) selector];
}


static void appendMethodToList(Class class,NSString *selectorName,IMP imp,const char *types,SEL *selectorp){
    
    SEL selector=NSSelectorFromString(selectorName);
    
    class_addMethod(class, selector, imp, types);
    
    *selectorp=selector;
}

-initWithCoder:(NSCoder *)coder {
    if(![coder allowsKeyedCoding]) {
        [NSException raise: NSInvalidArgumentException format: @"%@ can not initWithCoder:%@", [self class], [coder class]];
        return nil;
    }
    
    _className = [[coder decodeObjectForKey: @"NSClassNameForEntity"] retain];
    _name = [[coder decodeObjectForKey: @"NSEntityName"] retain];
    _model = [coder decodeObjectForKey: @"NSManagedObjectModel"];
    /* NSProperties is a name->property dictionary, matching Apple's
       mom archives.  The port adds GSPropertyOrder (property names)
       so its own archive round trips keep -properties stable;
       archives without it (older port moms) fall back to name order
       - which is what Xcode's alphabetized model XML compiles to
       anyway.  (Apple's -properties order is unspecified, so the
       side key is a port nicety, not a compatibility need.) */
    {
     id decodedProperties = [coder decodeObjectForKey: @"NSProperties"];
     NSArray *order = [coder decodeObjectForKey: @"GSPropertyOrder"];

     _properties = [[NSMutableArray alloc] init];
     if([decodedProperties isKindOfClass: [NSDictionary class]]) {
        _propertiesByName = [decodedProperties mutableCopy];
        if(order == nil)
            order = [[decodedProperties allKeys]
                sortedArrayUsingSelector: @selector(compare:)];
        for(NSString *propertyName in order) {
            id property = [decodedProperties objectForKey: propertyName];
            if(property != nil)
                [_properties addObject: property];
        }
     }
     else {
        /* tolerate an array encoding: the array is its own order */
        _propertiesByName = [[NSMutableDictionary alloc] init];
        for(NSPropertyDescription *property in decodedProperties) {
            [_properties addObject: property];
            [_propertiesByName setObject: property forKey: [property name]];
        }
     }
    }
    _subentities = [[coder decodeObjectForKey: @"NSSubentities"] retain];
    _superentity = [[coder decodeObjectForKey: @"NSSuperentity"] retain];
    _userInfo = [[coder decodeObjectForKey: @"NSUserInfo"] retain];
    _versionHashModifier= [[coder decodeObjectForKey: @"NSVersionHashModifier"] retain];
    _renamingIdentifier= [[coder decodeObjectForKey: @"NSRenamingIdentifier"] retain];
    _uniquenessConstraints = [[coder decodeObjectForKey: @"NSUniquenessConstraints"] retain];
    _compoundIndexes = [[coder decodeObjectForKey: @"NSCompoundIndexes"] retain];
    /* Apple's momc only writes the flag when the entity is abstract. */
    _isAbstract = [coder decodeBoolForKey: @"NSIsAbstract"];
    
    _selectorPropertyMap = [[NSMutableDictionary alloc] init];
    
    _hasBeenInstantiated = NO;
    
    [self _installPropertyAccessors];
    return self;
}

/* Installs the generated @dynamic accessor implementations
   (property/setProperty:, and add<Key>Object:-style mutators for
   to-manys) on the entity's managed object class, and fills the
   selector -> property map they dispatch through.  Historically this
   only ran while decoding a compiled model, so entities built in code
   answered valueForKey: but raised doesNotRecognizeSelector for a
   plain property message; it now also runs when the model is attached
   to a persistent store coordinator (see -_setInstantiated).
   Idempotent: class_addMethod leaves existing implementations alone
   and the map entries are simply rewritten. */
-(void)_installPropertyAccessors {
    if(_className==nil)
        return;

    Class class=NSClassFromString(_className);

    if(class==Nil)
        return;
    if(_selectorPropertyMap==nil)
        _selectorPropertyMap=[[NSMutableDictionary alloc] init];

    for(NSPropertyDescription *property in _properties) {
        NSString *propertyName=[property name];
        NSString *upperName=[[[propertyName substringToIndex:1] uppercaseString] stringByAppendingString:[propertyName substringFromIndex: 1]];
        SEL       selector;

        /* The accessor ABI must match the property's DECLARED type on
           the subclass: "@property (nonatomic) float x;" needs an IMP
           that returns float in the FP register - the object-typed IMP
           would leave an NSNumber in the integer register and the
           caller would read garbage.  Classes without a matching
           @property declaration (or with an object-typed one) get the
           object accessors, as before. */
        IMP  getterIMP=(IMP)getValue;
        IMP  setterIMP=(IMP)setValue;
        char getterTypes[4]={'@','@',':',0};
        char setterTypes[5]={'v','@',':','@',0};
        char encoding=declaredPropertyTypeEncoding(class,propertyName);

        if(encoding!=0 && encoding!='@'){
            IMP scalarGetter=NULL,scalarSetter=NULL;

            scalarAccessorsForEncoding(encoding,&scalarGetter,&scalarSetter);
            if(scalarGetter!=NULL){
                getterIMP=scalarGetter;
                setterIMP=scalarSetter;
                getterTypes[0]=encoding;
                setterTypes[3]=encoding;
            }
        }

        appendMethodToList(class,propertyName,getterIMP,getterTypes,&selector);
        [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
        
        appendMethodToList(class,[NSString stringWithFormat: @"set%@:",upperName],setterIMP,setterTypes,&selector);
        [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
        
        if([property isKindOfClass: [NSRelationshipDescription class]]) {
            NSRelationshipDescription *relationship= (NSRelationshipDescription *) property;
            
            if([relationship isToMany]){
                appendMethodToList(class,[NSString stringWithFormat: @"add%@Object:",upperName],(IMP)addObject,"v@:@",&selector);     
                [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
                
                appendMethodToList(class,[NSString stringWithFormat: @"remove%@Object:",upperName],(IMP)removeObject,"v@:@",&selector);     
                [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
                
                appendMethodToList(class,[NSString stringWithFormat: @"add%@:",upperName],(IMP)addObjectSet,"v@:@",&selector);     
                [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
                
                appendMethodToList(class,[NSString stringWithFormat: @"remove%@:",upperName],(IMP)removeObjectSet,"v@:@",&selector);     
                [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
            }
        }
    }
}

/* Called when the model this entity belongs to is attached to a
   persistent store coordinator: the entity is in use from here on
   (description setters refuse changes) and its accessor
   implementations must exist no matter how the entity was built. */
-(void)_setInstantiated {
    _hasBeenInstantiated = YES;
    [self _installPropertyAccessors];
}


- (void) encodeWithCoder: (NSCoder *) coder {
    if(![coder allowsKeyedCoding])
	[NSException raise: NSInvalidArgumentException format: @"%@ can not encodeWithCoder:%@", [self class], [coder class]];

    if(_className!=nil)
	[coder encodeObject:_className forKey: @"NSClassNameForEntity"];
    [coder encodeObject:_name forKey: @"NSEntityName"];
    [coder encodeConditionalObject:_model forKey: @"NSManagedObjectModel"];
    /* the Apple-shaped dictionary plus the port's order side-key (see
       initWithCoder:) */
    [coder encodeObject:_propertiesByName forKey: @"NSProperties"];
    [coder encodeObject:[_properties valueForKey: @"name"] forKey: @"GSPropertyOrder"];
    if([_subentities count]>0)
	[coder encodeObject:_subentities forKey: @"NSSubentities"];
    [coder encodeConditionalObject:_superentity forKey: @"NSSuperentity"];
    if(_userInfo!=nil)
	[coder encodeObject:_userInfo forKey: @"NSUserInfo"];
    if(_versionHashModifier!=nil)
	[coder encodeObject:_versionHashModifier forKey: @"NSVersionHashModifier"];
    if(_renamingIdentifier!=nil)
	[coder encodeObject:_renamingIdentifier forKey: @"NSRenamingIdentifier"];
    if([_uniquenessConstraints count]>0)
	[coder encodeObject:_uniquenessConstraints forKey: @"NSUniquenessConstraints"];
    if([_compoundIndexes count]>0)
	[coder encodeObject:_compoundIndexes forKey: @"NSCompoundIndexes"];
    /* Mirror Apple's momc: the flag is only written when YES. */
    if(_isAbstract)
	[coder encodeBool:YES forKey: @"NSIsAbstract"];
}


- (NSString *) description {
    return [NSString stringWithFormat: @"<NSEntityDescription %@>", _name];
}

/* The property-name candidates a generated accessor selector can
   stand for: "sourceText", "setSourceText:", "addTracksObject:",
   "removeTracksObject:", "addTracks:", "removeTracks:".  The inner
   name is tried both verbatim and with its first letter lowercased
   ("setURL:" names a property spelled "URL"). */
static void appendPropertyNameCandidates(NSMutableArray *candidates,NSString *selectorName){
   NSString *inner=nil;

   if([selectorName rangeOfString:@":"].location==NSNotFound){
    [candidates addObject:selectorName];
    return;
   }

   if([selectorName hasPrefix:@"set"] && [selectorName hasSuffix:@":"])
    inner=[selectorName substringWithRange:NSMakeRange(3,[selectorName length]-4)];
   else if([selectorName hasPrefix:@"add"] && [selectorName hasSuffix:@"Object:"])
    inner=[selectorName substringWithRange:NSMakeRange(3,[selectorName length]-10)];
   else if([selectorName hasPrefix:@"remove"] && [selectorName hasSuffix:@"Object:"])
    inner=[selectorName substringWithRange:NSMakeRange(6,[selectorName length]-13)];
   else if([selectorName hasPrefix:@"add"] && [selectorName hasSuffix:@":"])
    inner=[selectorName substringWithRange:NSMakeRange(3,[selectorName length]-4)];
   else if([selectorName hasPrefix:@"remove"] && [selectorName hasSuffix:@":"])
    inner=[selectorName substringWithRange:NSMakeRange(6,[selectorName length]-7)];

   if([inner length]==0)
    return;

   [candidates addObject:inner];
   [candidates addObject:[[[inner substringToIndex:1] lowercaseString]
       stringByAppendingString:[inner substringFromIndex:1]]];
}

-(NSPropertyDescription *)_propertyForSelector:(SEL) selector {
   id keyObject=keyObjectForSelector(selector);
   NSString *selectorName=NSStringFromSelector(selector);
   NSMutableArray *candidates=[NSMutableArray array];
   NSEntityDescription *entity;

   appendPropertyNameCandidates(candidates,selectorName);

   for(entity = self; entity; entity = [entity superentity]) {
    NSPropertyDescription *result= [entity->_selectorPropertyMap objectForKey:keyObject];
    
	if(result)
     return result;

    /* Name-based resolution: the map above keys selectors by pointer,
       which misses when the dispatched selector is a typed one (the ng
       runtime interns typed and untyped selectors separately), and is
       empty for entities built programmatically - the accessor name
       itself is the reliable identity. */
    for(NSString *candidate in candidates){
     result=[entity->_propertiesByName objectForKey:candidate];

     if(result)
      return result;
    }
   }
   return nil;
}


- (BOOL) _hasBeenInstantiated {
    return _hasBeenInstantiated;
}


+(NSEntityDescription *)entityForName: (NSString *)entityName inManagedObjectContext:(NSManagedObjectContext *)context {
   NSDictionary *entities=[[[context persistentStoreCoordinator] managedObjectModel] entitiesByName];
    
   return [entities objectForKey:entityName];
}


+ insertNewObjectForEntityForName:(NSString *)entityName inManagedObjectContext:(NSManagedObjectContext *)context {
   NSEntityDescription *entity=[self entityForName:entityName inManagedObjectContext:context];
   NSString            *className=[entity managedObjectClassName];
   Class                class;
 
   if(className)
    class = NSClassFromString(className);
   else {
    NSLog(@"Entity %@ has no managedObjectClassName set, using NSManagedObject",[entity name]);
    
    class = [NSManagedObject class];
   }
   
   return [[[class alloc] initWithEntity: entity insertIntoManagedObjectContext: context] autorelease];
}


-(NSManagedObjectModel *)managedObjectModel {
   return _model;
}

-(NSString *)name {
   return _name;
}


-(BOOL)isAbstract {
   return _isAbstract;
}


-(NSString *)managedObjectClassName {
   if(_className==nil)
    return @"NSManagedObject";
    
   return _className;
}


-(NSArray *)properties {
   /* insertion order - a deterministic instance of Apple's
      unspecified (dictionary-driven) order; see the header note */
   return [[_properties copy] autorelease];
}


-(NSArray *)subentities {
   return [_subentities allValues];
}


-(NSDictionary *)userInfo {
   return _userInfo;
}


-(void)setName:(NSString *)value {
   if(_hasBeenInstantiated) {
    NSLog(@"Attempt to modify entity after instantiating it.");
    return;
   }
   
   value=[value copy];
   [_name release];
   _name=value;
}


- (void) setAbstract: (BOOL) value {
    if(_hasBeenInstantiated) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    _isAbstract=value;
}


- (void) setManagedObjectClassName: (NSString *) value {
    if(_hasBeenInstantiated) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    value=[value copy];
    [_className release];
    _className=value;
}


- (void) setProperties: (NSArray *) value {
   if(_hasBeenInstantiated) {
    NSLog(@"Attempt to modify entity after instantiating it.");
    return;
   }

   NSMutableArray *properties=[[NSMutableArray alloc] init];
   NSMutableDictionary *byName=[[NSMutableDictionary alloc] init];

   for(NSPropertyDescription *property in value){
    [properties addObject:property];
    [byName setObject:property forKey:[property name]];
    [property _setEntity:self];
   }

   [_properties release];
   _properties=properties;
   [_propertiesByName release];
   _propertiesByName=byName;
}


- (void) setSubentities: (NSArray *) value {
    if(_hasBeenInstantiated) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    NSMutableDictionary *table=[[NSMutableDictionary alloc] init];

    for(NSEntityDescription *entity in value){
	[table setObject:entity forKey:[entity name]];
	if(entity->_superentity!=self){
	    [entity->_superentity release];
	    entity->_superentity=[self retain];
	}
    }

    [_subentities release];
    _subentities=table;
}


- (void) setUserInfo: (NSDictionary *) value {
    if(_hasBeenInstantiated) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }
    
    value=[value copy];
    [_userInfo release];
    _userInfo=value;
}


-(NSEntityDescription *)superentity {
   return _superentity;
}


-(NSDictionary *)subentitiesByName {
   return (_subentities!=nil)?_subentities:[NSDictionary dictionary];
}


-(NSDictionary *)attributesByName {
   NSMutableDictionary *result=[NSMutableDictionary dictionary];
   
   for(NSPropertyDescription *check in [[self propertiesByName] allValues]){
    if([check isKindOfClass:[NSAttributeDescription class]]){
     [result setObject:check forKey:[check name]];
    }
   }
      
   return result;
}


/* Apple includes inherited properties: an entity's propertiesByName covers
   its own properties plus those of every superentity (a subentity's own
   property shadows a same-named inherited one). */
-(NSDictionary *)propertiesByName {
   if(_superentity==nil)
    return _propertiesByName;

   NSMutableDictionary *result=[NSMutableDictionary dictionary];
   NSEntityDescription *check;

   for(check=self;check!=nil;check=check->_superentity){
    for(NSString *name in check->_propertiesByName){
     if([result objectForKey:name]==nil)
      [result setObject:[check->_propertiesByName objectForKey:name] forKey:name];
    }
   }

   return result;
}


-(NSDictionary *)relationshipsByName {
   NSMutableDictionary *result=[NSMutableDictionary dictionary];
   
   for(NSPropertyDescription *check in [[self propertiesByName] allValues]){
    if([check isKindOfClass:[NSRelationshipDescription class]]){
     [result setObject:check forKey:[check name]];
    }
   }
      
   return result;
}


-(NSArray *)relationshipsWithDestinationEntity:(NSEntityDescription *)entity {
   NSMutableArray *result=[NSMutableArray array];

   for(NSPropertyDescription *check in _properties){
    if([check isKindOfClass:[NSRelationshipDescription class]]){
     if([[check entity] isEqual:entity])
      [result addObject:check];
    }
   }
   
   return result;
}

-(NSData *)versionHash {
   NSMutableArray *components=[NSMutableArray array];
   NSMutableArray *propertyHashes=[NSMutableArray array];

   [components addObject:(_name!=nil)?_name:@""];
   [components addObject:_isAbstract?@"1":@"0"];
   if(_versionHashModifier!=nil)
    [components addObject:_versionHashModifier];

   /* Matching Apple, uniqueness constraints form part of the version
      hash.  Attribute descriptions and name strings hash identically,
      and the component is only added when constraints exist so that
      models without any keep their historical hashes. */
   if([_uniquenessConstraints count]>0){
    NSMutableArray *normalized=[NSMutableArray array];

    for(NSArray *constraint in _uniquenessConstraints){
     NSMutableArray *names=[NSMutableArray array];

     for(id element in constraint)
      [names addObject:[element isKindOfClass:[NSString class]]?element:[(NSPropertyDescription *)element name]];

     [normalized addObject:[names componentsJoinedByString:@","]];
    }

    [components addObject:[NSString stringWithFormat:@"constraints:%@",[normalized componentsJoinedByString:@";"]]];
   }

   /* name-sorted, not model-ordered: reordering properties must not
      change the version hash */
   for(NSString *propertyName in [[_propertiesByName allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    NSPropertyDescription *property=[_propertiesByName objectForKey:propertyName];
    NSData                *hash=[property versionHash];
    NSMutableString       *hex=[NSMutableString string];
    const uint8_t         *bytes=[hash bytes];
    NSUInteger             i,length=[hash length];

    for(i=0;i<length;i++)
     [hex appendFormat:@"%02x",bytes[i]];

    [propertyHashes addObject:hex];
   }

   [components addObjectsFromArray:propertyHashes];

   return _NSCoreDataDigestForComponents(components);
}


-(NSString *)versionHashModifier {
   return _versionHashModifier;
}


-(NSArray *)uniquenessConstraints {
   return (_uniquenessConstraints!=nil)?_uniquenessConstraints:[NSArray array];
}


-(void)setUniquenessConstraints:(NSArray *)value {
   if(_hasBeenInstantiated) {
    NSLog(@"Attempt to modify entity after instantiating it.");
    return;
   }

   value=[value copy];
   [_uniquenessConstraints release];
   _uniquenessConstraints=value;
}


-(NSArray *)compoundIndexes {
   return (_compoundIndexes!=nil)?_compoundIndexes:[NSArray array];
}


-(void)setCompoundIndexes:(NSArray *)value {
   if(_hasBeenInstantiated) {
    NSLog(@"Attempt to modify entity after instantiating it.");
    return;
   }

   value=[value copy];
   [_compoundIndexes release];
   _compoundIndexes=value;
}


-(void)setVersionHashModifier:(NSString *)value {
   if(_hasBeenInstantiated) {
    NSLog(@"Attempt to modify entity after instantiating it.");
    return;
   }

   value=[value copy];
   [_versionHashModifier release];
   _versionHashModifier=value;
}


/* Apple semantics: an unset renaming identifier reads as the name;
   the raw value stays nil so serializers can tell "defaulted" from
   "explicitly set".  Does not participate in the version hash. */
-(NSString *)renamingIdentifier {
   return (_renamingIdentifier!=nil)?_renamingIdentifier:_name;
}


-(void)setRenamingIdentifier:(NSString *)value {
   value=[value copy];
   [_renamingIdentifier release];
   _renamingIdentifier=value;
}


-(BOOL)_isKindOfEntity:(NSEntityDescription *)other {
   NSEntityDescription *check=self;
   
   for(;check!=nil;check=check->_superentity)
    if(check==other)
     return YES;
   
   return NO;
}

@end
