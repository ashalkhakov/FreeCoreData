/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPropertyDescription.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSAttributeDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import "CoreDataUtilities.h"
#import "CoreDataVersioning-Private.h"
#import "NSManagedObjectModel-Private.h"
#import <Foundation/NSCoder.h>
#import <Foundation/Foundation.h>

/* NSEntityDescription.m: keeps the entity's by-name table in step. */
@interface NSEntityDescription (PropertyRenaming)
- (void) _property: (NSPropertyDescription *) property didChangeNameFrom: (NSString *) oldName;
- (BOOL) _propertyIsIndexed: (NSPropertyDescription *) property;
- (void) _property: (NSPropertyDescription *) property setIndexed: (BOOL) value;
@end

@implementation NSPropertyDescription

/* Whether an archive says which attributes are indexed.  An Apple keyed
   archive does, and reading one back makes an index of each - which
   Xcode's compiled model (.omo) does not, so momc turns it off: a model
   compiled here loads as a model Xcode built does. */
static BOOL archivesIndexedFlag=YES;

+ (void) _setArchivesIndexedFlag: (BOOL) value {
   archivesIndexedFlag=value;
}

-init {
   _entity=nil;
   _propertyName=nil;
   /* Properties are optional by default, as on Apple's CoreData. */
   _optional=YES;
   return self;
}

/* Validation predicates are stored in the archive as predicate format
   strings (Apple's momc stores NSPredicate objects; both forms are
   accepted when decoding). */
static NSArray *predicatesFromArchivedObjects(NSArray *objects){
   if(objects==nil)
    return nil;

   NSMutableArray *result=[NSMutableArray arrayWithCapacity:[objects count]];

   for(id check in objects){
    if([check isKindOfClass:[NSString class]])
     [result addObject:[NSPredicate predicateWithFormat:check]];
    else {
     /* Predicates decoded from a keyed archive have evaluation disabled
        on Apple's Foundation until -allowEvaluation is sent (GNUstep's
        NSPredicate may not implement it). */
     if([check respondsToSelector:@selector(allowEvaluation)])
      [check performSelector:@selector(allowEvaluation)];
     [result addObject:check];
    }
   }

   return result;
}

-initWithCoder:(NSCoder *)coder {
   if(![coder allowsKeyedCoding])
    [NSException raise: NSInvalidArgumentException format: @"%@ can not initWithCoder:%@", [self class], [coder class]];

   _entity=[coder decodeObjectForKey: @"NSEntity"];
   _propertyName=[[coder decodeObjectForKey: @"NSPropertyName"] copy];
   /* Apple's momc only writes these flags when they are YES; an absent
      key therefore means NO. */
   _optional=[coder decodeBoolForKey: @"NSIsOptional"];
   _transient=[coder decodeBoolForKey: @"NSIsTransient"];
   _userInfo=[[coder decodeObjectForKey: @"NSUserInfo"] copy];
   _validationPredicates=[predicatesFromArchivedObjects([coder decodeObjectForKey: @"NSValidationPredicates"]) copy];
   _validationWarnings=[[coder decodeObjectForKey: @"NSValidationWarnings"] copy];
   _versionHashModifier=[[coder decodeObjectForKey: @"NSVersionHashModifier"] copy];
   _renamingIdentifier=[[coder decodeObjectForKey: @"NSRenamingIdentifier"] copy];
   /* Read by the entity, which makes an index of it. */
   _indexed=[coder decodeBoolForKey: @"NSIsIndexed"];
   
   return self;
}


- (void) encodeWithCoder: (NSCoder *) coder {
   if(![coder allowsKeyedCoding])
    [NSException raise: NSInvalidArgumentException format: @"%@ can not encodeWithCoder:%@", [self class], [coder class]];

   [coder encodeConditionalObject:_entity forKey: @"NSEntity"];
   [coder encodeObject:_propertyName forKey: @"NSPropertyName"];
   /* Mirror Apple's momc: boolean flags are only written when YES. */
   if(_optional)
    [coder encodeBool:YES forKey: @"NSIsOptional"];
   if(_transient)
    [coder encodeBool:YES forKey: @"NSIsTransient"];
   if(_userInfo!=nil)
    [coder encodeObject:_userInfo forKey: @"NSUserInfo"];
   if(_validationPredicates!=nil){
    /* NSPredicate does not support archiving on GNUstep; store the
       format strings instead (accepted on decode alongside archived
       NSPredicate objects). */
    NSMutableArray *formats=[NSMutableArray arrayWithCapacity:[_validationPredicates count]];

    for(NSPredicate *predicate in _validationPredicates)
     [formats addObject:[predicate predicateFormat]];

    [coder encodeObject:formats forKey: @"NSValidationPredicates"];
   }
   if(_validationWarnings!=nil)
    [coder encodeObject:_validationWarnings forKey: @"NSValidationWarnings"];
   if(_versionHashModifier!=nil)
    [coder encodeObject:_versionHashModifier forKey: @"NSVersionHashModifier"];
   if(_renamingIdentifier!=nil)
    [coder encodeObject:_renamingIdentifier forKey: @"NSRenamingIdentifier"];
   /* Apple writes the flag for attributes only: a relationship is always
      indexed. */
   if(archivesIndexedFlag && ![coder isKindOfClass:[CDModelCopyArchiver class]] &&
      [self isKindOfClass:[NSAttributeDescription class]] && [self isIndexed])
    [coder encodeBool:YES forKey: @"NSIsIndexed"];
}


- (BOOL) isIndexed {
   if([self isKindOfClass:[NSRelationshipDescription class]])
    return YES;
   if(_entity!=nil)
    return [_entity _propertyIsIndexed:self];

   return _indexed;
}

- (void) setIndexed: (BOOL) value {
   if([self isKindOfClass:[NSRelationshipDescription class]])
    return;
   if(_entity!=nil)
    [_entity _property:self setIndexed:value];
   else
    _indexed=value;
}

/* Taken by the entity when the property joins it. */
- (BOOL) _takeIndexedFlag {
   BOOL value=_indexed;

   _indexed=NO;
   return value;
}


- (BOOL) isEqual: (id) object {
    if(![object isKindOfClass: [NSPropertyDescription class]])
	return NO;
    NSPropertyDescription *property = (NSPropertyDescription *) object;
    if((_entity == [property entity]) &&
       [_propertyName isEqualToString: [property name]])
	return YES;
    else
	return NO;
}


- (id) copyWithZone: (NSZone *) zone {
    return [self retain];
}


- (NSEntityDescription *) entity {
    return _entity;
}

/* Private: back-reference set by -[NSEntityDescription setProperties:].
   Not retained; the entity owns its properties. */
- (void) _setEntity: (NSEntityDescription *) entity {
    _entity=entity;
}


- (NSString *) name {
    return _propertyName;
}


- (BOOL) isOptional {
    return _optional;
}


- (BOOL) isTransient {
    return _transient;
}


- (NSDictionary *) userInfo {
    return _userInfo;
}


- (NSArray *) validationPredicates {
    return _validationPredicates;
}


- (NSArray *) validationWarnings {
    return _validationWarnings;
}


/* Private: subclasses append the components that participate in the
   version hash. */
- (void) _appendVersionHashComponents: (NSMutableArray *) components {
    [components addObject:NSStringFromClass([self class])];
    [components addObject:(_propertyName!=nil)?_propertyName:@""];
    [components addObject:_optional?@"1":@"0"];
    if(_versionHashModifier!=nil)
	[components addObject:_versionHashModifier];
}


- (NSData *) versionHash {
    NSMutableArray *components=[NSMutableArray array];

    [self _appendVersionHashComponents:components];

    return _NSCoreDataDigestForComponents(components);
}


- (NSString *) versionHashModifier {
    return _versionHashModifier;
}


- (void) setVersionHashModifier: (NSString *) value {
    value=[value copy];
    [_versionHashModifier release];
    _versionHashModifier=value;
}


/* Apple semantics: an unset renaming identifier reads as the name;
   the raw value stays nil so serializers can tell "defaulted" from
   "explicitly set".  Does not participate in the version hash. */
- (NSString *) renamingIdentifier {
    return (_renamingIdentifier!=nil)?_renamingIdentifier:_propertyName;
}


- (void) setRenamingIdentifier: (NSString *) value {
    value=[value copy];
    [_renamingIdentifier release];
    _renamingIdentifier=value;
}


- (void) setName: (NSString *) value {
    NSString *old=[_propertyName retain];

    value=[value copy];
    [_propertyName release];
    _propertyName=value;
    /* The entity looks its properties up by name, and on Apple a renamed
       property is found under its new name -- so the entity has to hear of
       it, or -propertiesByName goes on answering to the old one. */
    if(_entity!=nil && ![old isEqualToString:value])
     [_entity _property:self didChangeNameFrom:old];
    [old release];
}


- (void) setOptional: (BOOL) value {
    _optional=value;
}


- (void) setTransient: (BOOL) value {
    _transient=value;
}


- (void) setUserInfo: (NSDictionary *) value {
    value=[value copy];
    [_userInfo release];
    _userInfo=value;
}


- (void) setValidationPredicates: (NSArray *) predicates
	  withValidationWarnings: (NSArray *) warnings
{
    predicates=[predicates copy];
    [_validationPredicates release];
    _validationPredicates=predicates;

    warnings=[warnings copy];
    [_validationWarnings release];
    _validationWarnings=warnings;
}


@end
