/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSDerivedAttributeDescription.h>
#import "NSDerivedAttributeDescription-Private.h"
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/CoreDataErrors.h>
#import <Foundation/Foundation.h>

@interface NSPropertyDescription(VersionHashPrivate)
- (void)_appendVersionHashComponents:(NSMutableArray *)components;
@end

@interface NSEntityDescription(Private)
- (BOOL)_hasBeenInstantiated;
@end

/* ------------------------------------------------------------------ */
#pragma mark - NSExpression function support (GNUstep-base shims)
/* ------------------------------------------------------------------ */

/* GNUstep-base's +[NSExpression expressionForFunction:arguments:] accepts
   a function name only when the expression instance responds to an
   _eval_<name>: selector.  This category supplies the derived-attribute
   functions (uppercase:, lowercase:, canonical:, now) so that models can
   be built with the same code as on Apple platforms - and makes the
   expressions evaluate correctly outside CoreData as well.  The private
   function-expression class inherits these through NSExpression; a
   future gnustep-base implementation of its own would take precedence. */

static NSString *canonicalString(NSString *value){
   /* Apple documents canonical: as the case- and diacritic-insensitive
      representation of a string. */
   return [value stringByFoldingWithOptions:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch
                                     locale:nil];
}

@implementation NSExpression (CoreDataDerivedAttributeFunctions)

- (id)_eval_uppercase:(NSArray *)arguments {
   return [[arguments objectAtIndex:0] uppercaseString];
}

- (id)_eval_lowercase:(NSArray *)arguments {
   return [[arguments objectAtIndex:0] lowercaseString];
}

- (id)_eval_canonical:(NSArray *)arguments {
   return canonicalString([arguments objectAtIndex:0]);
}

- (id)_eval_now:(NSArray *)arguments {
   return [NSDate date];
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - NSDerivedAttributeDescription
/* ------------------------------------------------------------------ */

@implementation NSDerivedAttributeDescription

-initWithCoder:(NSCoder *)coder {
   if([super initWithCoder:coder]==nil)
    return nil;

   _derivationExpression=[[coder decodeObjectForKey:@"NSDerivationExpression"] retain];

   return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
   [super encodeWithCoder:coder];

   if(_derivationExpression!=nil)
    [coder encodeObject:_derivationExpression forKey:@"NSDerivationExpression"];
}

-(void)dealloc {
   [_derivationExpression release];
   [super dealloc];
}

- (NSString *) description {
    return [NSString stringWithFormat:@"<NSDerivedAttributeDescription: %@ = %@>",_propertyName,_derivationExpression];
}

- (NSExpression *) derivationExpression {
    return _derivationExpression;
}

- (void) setDerivationExpression: (NSExpression *) value {
    if([_entity _hasBeenInstantiated]) {
	NSLog(@"Attempt to modify entity after instantiating it.");
	return;
    }

    value=[value copy];
    [_derivationExpression release];
    _derivationExpression=value;
}

- (void) _appendVersionHashComponents: (NSMutableArray *) components {
    [super _appendVersionHashComponents:components];
    [components addObject:@"derived"];
    [components addObject:(_derivationExpression!=nil)?[_derivationExpression description]:@""];
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - Derivation engine
/* ------------------------------------------------------------------ */

typedef enum {
    CDDerivationInvalid=0,
    CDDerivationCopy,            /* key path, possibly across to-one */
    CDDerivationStringTransform, /* uppercase:/lowercase:/canonical: */
    CDDerivationAggregate,       /* rel.@count or rel.attr.@sum */
    CDDerivationNow              /* now() */
} CDDerivationForm;

static NSError *derivationError(NSString *format,...){
   va_list  arguments;

   va_start(arguments,format);
   NSString *description=[[[NSString alloc] initWithFormat:format arguments:arguments] autorelease];
   va_end(arguments);

   return [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOpenError
                          userInfo:[NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey]];
}

static NSString *strippedFunctionName(NSString *name){
   if([name hasSuffix:@":"])
    return [name substringToIndex:[name length]-1];

   return name;
}

/* Classifies the derivation expression.  On success returns the form and
   fills keyPathOut (the path without any trailing operator; nil for
   now()), operatorOut (@"@count"/@"@sum" for aggregates) and
   functionOut (uppercase/lowercase/canonical for string transforms). */
static CDDerivationForm classifyDerivation(NSExpression *expression,NSString **keyPathOut,NSString **operatorOut,NSString **functionOut,NSError **error){
   if(keyPathOut!=NULL) *keyPathOut=nil;
   if(operatorOut!=NULL) *operatorOut=nil;
   if(functionOut!=NULL) *functionOut=nil;

   if(expression==nil){
    if(error!=NULL)
     *error=derivationError(@"Derived attribute has no derivation expression");
    return CDDerivationInvalid;
   }

   if([expression expressionType]==NSKeyPathExpressionType){
    NSString *path=[expression keyPath];
    NSArray  *components=[path componentsSeparatedByString:@"."];
    NSUInteger i,count=[components count];

    if([path length]==0){
     if(error!=NULL)
      *error=derivationError(@"Derivation expression has an empty key path");
     return CDDerivationInvalid;
    }

    for(i=0;i<count;i++){
     NSString *component=[components objectAtIndex:i];

     if([component length]==0){
      if(error!=NULL)
       *error=derivationError(@"Derivation expression key path '%@' has an empty component",path);
      return CDDerivationInvalid;
     }

     if([component hasPrefix:@"@"] && i!=count-1){
      /* Matching Apple: "friends.@sum.age" is rejected; the operator
         must be the terminal component, as in "friends.age.@sum". */
      if(error!=NULL)
       *error=derivationError(@"The derivation expression key path '%@' uses an operator as an intermediate component",path);
      return CDDerivationInvalid;
     }
    }

    NSString *last=[components lastObject];

    if([last hasPrefix:@"@"]){
     if(![last isEqualToString:@"@count"] && ![last isEqualToString:@"@sum"]){
      if(error!=NULL)
       *error=derivationError(@"Unsupported aggregate operator '%@' in derivation expression '%@' (supported: @count, @sum)",last,path);
      return CDDerivationInvalid;
     }
     if(count<2){
      if(error!=NULL)
       *error=derivationError(@"Aggregate derivation expression '%@' has no key path",path);
      return CDDerivationInvalid;
     }

     if(keyPathOut!=NULL)
      *keyPathOut=[[components subarrayWithRange:NSMakeRange(0,count-1)] componentsJoinedByString:@"."];
     if(operatorOut!=NULL)
      *operatorOut=last;
     return CDDerivationAggregate;
    }

    if(keyPathOut!=NULL)
     *keyPathOut=path;
    return CDDerivationCopy;
   }

   if([expression expressionType]==NSFunctionExpressionType){
    NSString *name=strippedFunctionName([expression function]);

    if([name isEqualToString:@"now"])
     return CDDerivationNow;

    if([name isEqualToString:@"uppercase"] || [name isEqualToString:@"lowercase"] ||
       [name isEqualToString:@"canonical"]){
     NSArray      *arguments=[expression arguments];
     NSExpression *argument=([arguments count]>0)?[arguments objectAtIndex:0]:nil;

     if([arguments count]!=1 || [argument expressionType]!=NSKeyPathExpressionType){
      if(error!=NULL)
       *error=derivationError(@"The %@: derivation function requires a single key path argument",name);
      return CDDerivationInvalid;
     }

     if(keyPathOut!=NULL)
      *keyPathOut=[argument keyPath];
     if(functionOut!=NULL)
      *functionOut=name;
     return CDDerivationStringTransform;
    }

    if(error!=NULL)
     *error=derivationError(@"Unsupported derivation function '%@' (supported: uppercase:, lowercase:, canonical:, now())",[expression function]);
    return CDDerivationInvalid;
   }

   if(error!=NULL)
    *error=derivationError(@"Unsupported derivation expression %@ (supported: key paths, uppercase:/lowercase:/canonical:, @count/@sum aggregates, now())",expression);
   return CDDerivationInvalid;
}

/* Resolves the components of `keyPath` against `entity`, requiring every
   intermediate component to be a to-one relationship.  Returns the final
   property description (attribute or relationship), or nil with *error
   set. */
static NSPropertyDescription *resolveKeyPath(NSEntityDescription *entity,NSString *keyPath,NSError **error){
   NSArray             *components=[keyPath componentsSeparatedByString:@"."];
   NSEntityDescription *current=entity;
   NSPropertyDescription *property=nil;
   NSUInteger           i,count=[components count];

   for(i=0;i<count;i++){
    NSString *component=[components objectAtIndex:i];

    property=[[current propertiesByName] objectForKey:component];

    if(property==nil){
     if(error!=NULL)
      *error=derivationError(@"Derivation expression key path '%@' references unknown property '%@' of entity %@",keyPath,component,[current name]);
     return nil;
    }

    if(i<count-1){
     if(![property isKindOfClass:[NSRelationshipDescription class]] ||
        [(NSRelationshipDescription *)property isToMany]){
      if(error!=NULL)
       *error=derivationError(@"Derivation expression key path '%@' component '%@' is not a to-one relationship",keyPath,component);
      return nil;
     }
     current=[(NSRelationshipDescription *)property destinationEntity];
    }
   }

   return property;
}

/* Follows `keyPath` from `object` with plain KVC, stopping at nil. */
static id valueForDerivationKeyPath(NSManagedObject *object,NSString *keyPath){
   id value=object;

   for(NSString *component in [keyPath componentsSeparatedByString:@"."]){
    if(value==nil)
     return nil;
    value=[value valueForKey:component];
   }

   return value;
}

BOOL _NSValidateDerivedAttributesInModel(NSManagedObjectModel *model,NSError **error){
   for(NSEntityDescription *entity in [[model entitiesByName] allValues]){
    for(NSPropertyDescription *property in [[entity propertiesByName] allValues]){
     if(![property isKindOfClass:[NSDerivedAttributeDescription class]])
      continue;

     if(![(NSDerivedAttributeDescription *)property _validateDerivationWithError:error])
      return NO;
    }
   }

   return YES;
}

@implementation NSDerivedAttributeDescription (DerivationPrivate)

- (BOOL) _validateDerivationWithError: (NSError **) error {
    NSString       *keyPath=nil,*operator=nil,*function=nil;
    CDDerivationForm form=classifyDerivation(_derivationExpression,&keyPath,&operator,&function,error);

    switch(form){

     case CDDerivationInvalid:
      return NO;

     case CDDerivationNow:
      if(_attributeType!=NSDateAttributeType){
       if(error!=NULL)
        *error=derivationError(@"The now() derivation requires a date attribute type on %@",_propertyName);
       return NO;
      }
      return YES;

     case CDDerivationCopy:
      return resolveKeyPath(_entity,keyPath,error)!=nil;

     case CDDerivationStringTransform: {
      NSPropertyDescription *property=resolveKeyPath(_entity,keyPath,error);

      if(property==nil)
       return NO;
      if(![property isKindOfClass:[NSAttributeDescription class]] ||
         [(NSAttributeDescription *)property attributeType]!=NSStringAttributeType){
       if(error!=NULL)
        *error=derivationError(@"The %@: derivation function requires a string attribute key path, but '%@' is not one",function,keyPath);
       return NO;
      }
      return YES;
     }

     case CDDerivationAggregate: {
      if([operator isEqualToString:@"@count"]){
       NSPropertyDescription *property=resolveKeyPath(_entity,keyPath,error);

       if(property==nil)
        return NO;
       if(![property isKindOfClass:[NSRelationshipDescription class]] ||
          ![(NSRelationshipDescription *)property isToMany]){
        if(error!=NULL)
         *error=derivationError(@"The @count derivation requires a to-many relationship key path, but '%@' is not one",keyPath);
        return NO;
       }
       return YES;
      }

      /* @sum: the path is rel[...].attribute, where the relationship
         segment ends in a to-many relationship. */
      NSArray *components=[keyPath componentsSeparatedByString:@"."];

      if([components count]<2){
       if(error!=NULL)
        *error=derivationError(@"The @sum derivation requires a to-many relationship and an attribute, as in 'items.amount.@sum'");
       return NO;
      }

      NSString *relationshipPath=[[components subarrayWithRange:NSMakeRange(0,[components count]-1)] componentsJoinedByString:@"."];
      NSString *attributeName=[components lastObject];

      /* Resolve the relationship segment leniently: intermediate
         components must be to-one, the final one to-many. */
      NSArray             *relationshipComponents=[relationshipPath componentsSeparatedByString:@"."];
      NSEntityDescription *current=_entity;
      NSRelationshipDescription *relationship=nil;
      NSUInteger           i,count=[relationshipComponents count];

      for(i=0;i<count;i++){
       NSString              *component=[relationshipComponents objectAtIndex:i];
       NSPropertyDescription *property=[[current propertiesByName] objectForKey:component];

       if(![property isKindOfClass:[NSRelationshipDescription class]]){
        if(error!=NULL)
         *error=derivationError(@"The @sum derivation key path '%@' component '%@' is not a relationship",keyPath,component);
        return NO;
       }
       relationship=(NSRelationshipDescription *)property;
       if(i<count-1 && [relationship isToMany]){
        if(error!=NULL)
         *error=derivationError(@"The derivation expression key path '%@' uses a to-many relationship as an intermediate component",keyPath);
        return NO;
       }
       current=[relationship destinationEntity];
      }

      if(![relationship isToMany]){
       if(error!=NULL)
        *error=derivationError(@"The @sum derivation requires a to-many relationship key path, but '%@' is not one",relationshipPath);
       return NO;
      }

      NSPropertyDescription *summed=[[current propertiesByName] objectForKey:attributeName];

      if(![summed isKindOfClass:[NSAttributeDescription class]]){
       if(error!=NULL)
        *error=derivationError(@"The @sum derivation key path '%@' does not end in an attribute",keyPath);
       return NO;
      }
      return YES;
     }
    }

    return NO;
}

- (id) _derivedValueForObject: (NSManagedObject *) object {
    NSString        *keyPath=nil,*operator=nil,*function=nil;
    CDDerivationForm form=classifyDerivation(_derivationExpression,&keyPath,&operator,&function,NULL);

    switch(form){

     case CDDerivationInvalid:
      return nil;

     case CDDerivationNow:
      return [NSDate date];

     case CDDerivationCopy:
      return valueForDerivationKeyPath(object,keyPath);

     case CDDerivationStringTransform: {
      NSString *value=valueForDerivationKeyPath(object,keyPath);

      if(value==nil)
       return nil;
      if([function isEqualToString:@"uppercase"])
       return [value uppercaseString];
      if([function isEqualToString:@"lowercase"])
       return [value lowercaseString];
      return canonicalString(value);
     }

     case CDDerivationAggregate: {
      if([operator isEqualToString:@"@count"]){
       id collection=valueForDerivationKeyPath(object,keyPath);

       return [NSNumber numberWithUnsignedInteger:(collection!=nil)?[collection count]:0];
      }

      NSArray  *components=[keyPath componentsSeparatedByString:@"."];
      NSString *relationshipPath=[[components subarrayWithRange:NSMakeRange(0,[components count]-1)] componentsJoinedByString:@"."];
      NSString *attributeName=[components lastObject];
      id        collection=valueForDerivationKeyPath(object,relationshipPath);
      double    sum=0;

      for(id member in collection)
       sum+=[[member valueForKey:attributeName] doubleValue];

      switch(_attributeType){
       case NSInteger16AttributeType:
       case NSInteger32AttributeType:
       case NSInteger64AttributeType:
        return [NSNumber numberWithLongLong:(long long)sum];
       default:
        return [NSNumber numberWithDouble:sum];
      }
     }
    }

    return nil;
}

- (NSString *) _generatedColumnSourceName {
    NSString        *keyPath=nil;
    CDDerivationForm form=classifyDerivation(_derivationExpression,&keyPath,NULL,NULL,NULL);

    if(form!=CDDerivationCopy)
     return nil;
    if([keyPath rangeOfString:@"."].location!=NSNotFound)
     return nil;

    NSPropertyDescription *source=[[_entity propertiesByName] objectForKey:keyPath];

    if(![source isKindOfClass:[NSAttributeDescription class]])
     return nil;
    /* A copy of another derived attribute is computed by the engine
       instead of chaining generated columns. */
    if([source isKindOfClass:[NSDerivedAttributeDescription class]])
     return nil;

    return keyPath;
}

@end
