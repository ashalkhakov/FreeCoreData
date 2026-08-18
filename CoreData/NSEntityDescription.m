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
   return imp==(IMP)getValue || imp==(IMP)setValue || imp==(IMP)addObject ||
          imp==(IMP)removeObject || imp==(IMP)addObjectSet || imp==(IMP)removeObjectSet;
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
    _properties = [[coder decodeObjectForKey: @"NSProperties"] retain];
    _subentities = [[coder decodeObjectForKey: @"NSSubentities"] retain];
    _superentity = [[coder decodeObjectForKey: @"NSSuperentity"] retain];
    _userInfo = [[coder decodeObjectForKey: @"NSUserInfo"] retain];
    _versionHashModifier= [[coder decodeObjectForKey: @"NSVersionHashModifier"] retain];
    /* Apple's momc only writes the flag when the entity is abstract. */
    _isAbstract = [coder decodeBoolForKey: @"NSIsAbstract"];
    
    _selectorPropertyMap = [[NSMutableDictionary alloc] init];
    
    _hasBeenInstantiated = NO;
    
    if(_className) {
        Class class=NSClassFromString(_className);
        
        for(NSPropertyDescription *property in [_properties allValues]) {
            NSString *propertyName=[property name];
            NSString *upperName=[[[propertyName substringToIndex:1] uppercaseString] stringByAppendingString:[propertyName substringFromIndex: 1]];
            NSString *selectorName;
            SEL       selector;
            
            appendMethodToList(class,propertyName,(IMP) getValue,"@@:",&selector);
            [_selectorPropertyMap setObject:property forKey:keyObjectForSelector(selector)];
            
            appendMethodToList(class,[NSString stringWithFormat: @"set%@:",upperName],(IMP) setValue,"v@:@",&selector);     
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
    return self;
}


- (void) encodeWithCoder: (NSCoder *) coder {
    if(![coder allowsKeyedCoding])
	[NSException raise: NSInvalidArgumentException format: @"%@ can not encodeWithCoder:%@", [self class], [coder class]];

    if(_className!=nil)
	[coder encodeObject:_className forKey: @"NSClassNameForEntity"];
    [coder encodeObject:_name forKey: @"NSEntityName"];
    [coder encodeConditionalObject:_model forKey: @"NSManagedObjectModel"];
    [coder encodeObject:_properties forKey: @"NSProperties"];
    if([_subentities count]>0)
	[coder encodeObject:_subentities forKey: @"NSSubentities"];
    [coder encodeConditionalObject:_superentity forKey: @"NSSuperentity"];
    if(_userInfo!=nil)
	[coder encodeObject:_userInfo forKey: @"NSUserInfo"];
    if(_versionHashModifier!=nil)
	[coder encodeObject:_versionHashModifier forKey: @"NSVersionHashModifier"];
    /* Mirror Apple's momc: the flag is only written when YES. */
    if(_isAbstract)
	[coder encodeBool:YES forKey: @"NSIsAbstract"];
}


- (NSString *) description {
    return [NSString stringWithFormat: @"<NSEntityDescription %@>", _name];
}

-(NSPropertyDescription *)_propertyForSelector:(SEL) selector {
   id keyObject=keyObjectForSelector(selector);
   NSEntityDescription *entity;
   
   for(entity = self; entity; entity = [entity superentity]) {
    NSPropertyDescription *result= [entity->_selectorPropertyMap objectForKey:keyObject];
    
	if(result)
     return result;

    /* Entities built programmatically (not decoded from a model file) have
       no selector map; fall back to looking the property up by name. */
    result=[entity->_properties objectForKey:NSStringFromSelector(selector)];

    if(result)
     return result;
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
   return [_properties allValues];
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

   NSMutableDictionary *properties=[[NSMutableDictionary alloc] init];

   for(NSPropertyDescription *property in value){
    [properties setObject:property forKey:[property name]];
    [property _setEntity:self];
   }

   [_properties release];
   _properties=properties;
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
   NSUnimplementedMethod();
   return nil;
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
    return _properties;

   NSMutableDictionary *result=[NSMutableDictionary dictionary];
   NSEntityDescription *check;

   for(check=self;check!=nil;check=check->_superentity){
    for(NSString *name in check->_properties){
     if([result objectForKey:name]==nil)
      [result setObject:[check->_properties objectForKey:name] forKey:name];
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

   for(NSPropertyDescription *check in [_properties allValues]){
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

   for(NSString *propertyName in [[_properties allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    NSPropertyDescription *property=[_properties objectForKey:propertyName];
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


-(void)setVersionHashModifier:(NSString *)value {
   if(_hasBeenInstantiated) {
    NSLog(@"Attempt to modify entity after instantiating it.");
    return;
   }

   value=[value copy];
   [_versionHashModifier release];
   _versionHashModifier=value;
}


-(BOOL)_isKindOfEntity:(NSEntityDescription *)other {
   NSEntityDescription *check=self;
   
   for(;check!=nil;check=check->_superentity)
    if(check==other)
     return YES;
   
   return NO;
}

@end
