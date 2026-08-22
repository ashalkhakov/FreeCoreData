/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDModelCompiler.h"
#import <CoreData/CoreData.h>

NSString * const CDModelCompilerErrorDomain=@"CDModelCompilerErrorDomain";

/* Compilation problems are raised internally so the parsing code stays
   free of error threading, and caught at the public API boundary where
   they become NSErrors. */
static NSString * const CDModelCompilerException=@"CDModelCompilerException";

static void (^warningHandler)(NSString *)=nil;

static void warnf(NSString *format,...){
   if(warningHandler==nil)
    return;

   va_list arguments;
   va_start(arguments,format);
   NSString *message=[[NSString alloc] initWithFormat:format arguments:arguments];
   va_end(arguments);
   warningHandler(message);
}

static void failf(NSString *format,...) __attribute__((noreturn));
static void failf(NSString *format,...){
   va_list arguments;
   va_start(arguments,format);
   NSString *message=[[NSString alloc] initWithFormat:format arguments:arguments];
   va_end(arguments);
   [NSException raise:CDModelCompilerException format:@"%@",message];
   abort(); /* not reached */
}

/* --- attribute types ------------------------------------------------ */

static NSAttributeType attributeTypeFromString(NSString *string,NSString *context){
   static NSDictionary *types=nil;

   if(types==nil)
    types=@{
     @"Undefined":  @(NSUndefinedAttributeType),
     @"Integer 16": @(NSInteger16AttributeType),
     @"Integer 32": @(NSInteger32AttributeType),
     @"Integer 64": @(NSInteger64AttributeType),
     @"Decimal":    @(NSDecimalAttributeType),
     @"Double":     @(NSDoubleAttributeType),
     @"Float":      @(NSFloatAttributeType),
     @"String":     @(NSStringAttributeType),
     @"Boolean":    @(NSBooleanAttributeType),
     @"Date":       @(NSDateAttributeType),
     @"Binary":     @(NSBinaryDataAttributeType),
     @"Transformable": @(NSTransformableAttributeType),
     @"UUID":       @(NSUUIDAttributeType),
     @"URI":        @(NSURIAttributeType),
    };

   NSNumber *type=[types objectForKey:string];

   if(type!=nil)
    return [type intValue];

   failf(@"%@: unknown attribute type '%@'",context,string);
}

static id defaultValueForAttribute(NSXMLElement *element,NSAttributeType type,NSString *context){
   NSString *interval=[[element attributeForName:@"defaultDateTimeInterval"] stringValue];

   if(interval!=nil)
    return [NSDate dateWithTimeIntervalSinceReferenceDate:[interval doubleValue]];

   NSString *string=[[element attributeForName:@"defaultValueString"] stringValue];

   if(string==nil)
    return nil;

   switch(type){
    case NSStringAttributeType:
     return string;
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
     return [NSNumber numberWithLongLong:[string longLongValue]];
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
     return [NSNumber numberWithDouble:[string doubleValue]];
    case NSDecimalAttributeType:
     return [NSDecimalNumber decimalNumberWithString:string];
    case NSBooleanAttributeType:
     return [NSNumber numberWithBool:[string isEqualToString:@"YES"] || [string isEqualToString:@"1"]];
    case NSDateAttributeType:
     return [NSDate dateWithTimeIntervalSinceReferenceDate:[string doubleValue]];
    case NSUUIDAttributeType:
     return [[NSUUID alloc] initWithUUIDString:string];
    case NSURIAttributeType:
     return [NSURL URLWithString:string];
    default:
     warnf(@"%@: ignoring default value '%@' (unsupported for this attribute type)",context,string);
     return nil;
   }
}

/* --- derivation expressions ---------------------------------------- */

/* Builds the derivation expression without going through
   expressionWithFormat: for function calls - gnustep-base releases
   before 6f47534 (2026-07-30) cannot parse the colon-call form and map
   colon-suffixed names to the wrong selector, while
   expressionForFunction: with a colon-less name works on every
   version. */
static NSExpression *derivationExpressionFromString(NSString *string,NSString *context){
   NSString *trimmed=[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

   if([trimmed isEqualToString:@"now()"])
    return [NSExpression expressionForFunction:@"now" arguments:[NSArray array]];

   /* name:(key.path) */
   NSRange open=[trimmed rangeOfString:@":("];

   if(open.location!=NSNotFound && [trimmed hasSuffix:@")"]){
    NSString *function=[trimmed substringToIndex:open.location];
    NSString *argument=[trimmed substringWithRange:
        NSMakeRange(open.location+2,[trimmed length]-open.location-3)];

    return [NSExpression expressionForFunction:function
                                     arguments:[NSArray arrayWithObject:
        [NSExpression expressionForKeyPath:argument]]];
   }

   NSCharacterSet *keyPathSet=[NSCharacterSet characterSetWithCharactersInString:
       @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.@"];

   if([[trimmed stringByTrimmingCharactersInSet:keyPathSet] length]==0)
    return [NSExpression expressionForKeyPath:trimmed];

   @try {
    return [NSExpression expressionWithFormat:trimmed];
   }
   @catch(NSException *exception) {
    failf(@"%@: cannot parse derivation expression '%@': %@",context,string,[exception reason]);
   }
}

/* --- XML helpers ---------------------------------------------------- */

static NSXMLElement *childNamed(NSXMLElement *element,NSString *name){
   return [[element elementsForName:name] count]>0?[[element elementsForName:name] objectAtIndex:0]:nil;
}

static NSString *attr(NSXMLElement *element,NSString *name){
   return [[element attributeForName:name] stringValue];
}

static BOOL boolAttr(NSXMLElement *element,NSString *name){
   return [attr(element,name) isEqualToString:@"YES"];
}

/* --- model compilation ---------------------------------------------- */

static NSManagedObjectModel *compileModel(NSString *xcdatamodelPath){
   NSString *contentsPath=[xcdatamodelPath stringByAppendingPathComponent:@"contents"];
   NSData   *data=[NSData dataWithContentsOfFile:contentsPath];

   if(data==nil)
    failf(@"cannot read %@",contentsPath);

   NSError       *xmlError=nil;
   NSXMLDocument *document=[[NSXMLDocument alloc] initWithData:data options:0 error:&xmlError];

   if(document==nil)
    failf(@"cannot parse %@: %@",contentsPath,[xmlError localizedDescription]);

   NSXMLElement *root=[document rootElement];

   if(![[root name] isEqualToString:@"model"])
    failf(@"%@: root element is <%@>, expected <model>",contentsPath,[root name]);

   NSMutableDictionary *entitiesByName=[NSMutableDictionary dictionary];
   NSMutableDictionary *elementsByName=[NSMutableDictionary dictionary];
   NSMutableDictionary *subentityNames=[NSMutableDictionary dictionary]; /* parent -> names */

   /* Pass 1: entities with attributes; relationships are created but
      wired in pass 2 when every entity exists. */
   for(NSXMLElement *entityElement in [root elementsForName:@"entity"]){
    NSString *entityName=attr(entityElement,@"name");

    if(entityName==nil)
     failf(@"%@: <entity> without a name",contentsPath);

    NSEntityDescription *entity=[[NSEntityDescription alloc] init];

    [entity setName:entityName];
    [entity setManagedObjectClassName:
        attr(entityElement,@"representedClassName")?:@"NSManagedObject"];
    if(boolAttr(entityElement,@"isAbstract"))
     [entity setAbstract:YES];
    if(attr(entityElement,@"versionHashModifier")!=nil)
     [entity setVersionHashModifier:attr(entityElement,@"versionHashModifier")];

    NSString *parent=attr(entityElement,@"parentEntity");

    if(parent!=nil){
     NSMutableArray *children=[subentityNames objectForKey:parent];

     if(children==nil){
      children=[NSMutableArray array];
      [subentityNames setObject:children forKey:parent];
     }
     [children addObject:entityName];
    }

    [entitiesByName setObject:entity forKey:entityName];
    [elementsByName setObject:entityElement forKey:entityName];
   }

   /* Pass 2: properties. */
   for(NSString *entityName in entitiesByName){
    NSXMLElement        *entityElement=[elementsByName objectForKey:entityName];
    NSEntityDescription *entity=[entitiesByName objectForKey:entityName];
    NSMutableArray      *properties=[NSMutableArray array];

    for(NSXMLElement *attributeElement in [entityElement elementsForName:@"attribute"]){
     NSString *attributeName=attr(attributeElement,@"name");
     NSString *context=[NSString stringWithFormat:@"%@.%@",entityName,attributeName];
     NSString *typeString=attr(attributeElement,@"attributeType");

     if(typeString==nil)
      failf(@"%@: attribute without a type",context);

     NSAttributeType type=attributeTypeFromString(typeString,context);
     NSAttributeDescription *attribute;

     if(boolAttr(attributeElement,@"derived")){
      NSDerivedAttributeDescription *derived=[[NSDerivedAttributeDescription alloc] init];
      NSString *expressionString=attr(attributeElement,@"derivationExpression");

      if(expressionString==nil)
       failf(@"%@: derived attribute without a derivation expression",context);
      [derived setDerivationExpression:
          derivationExpressionFromString(expressionString,context)];
      attribute=derived;
     }
     else
      attribute=[[NSAttributeDescription alloc] init];

     [attribute setName:attributeName];
     [attribute setAttributeType:type];
     [attribute setOptional:boolAttr(attributeElement,@"optional")];
     if(boolAttr(attributeElement,@"transient"))
      [attribute setTransient:YES];
     if(attr(attributeElement,@"valueTransformerName")!=nil)
      [attribute setValueTransformerName:attr(attributeElement,@"valueTransformerName")];
     if(attr(attributeElement,@"customClassName")!=nil)
      [attribute setAttributeValueClassName:attr(attributeElement,@"customClassName")];

     id defaultValue=defaultValueForAttribute(attributeElement,type,context);

     if(defaultValue!=nil)
      [attribute setDefaultValue:defaultValue];

     [properties addObject:attribute];
    }

    for(NSXMLElement *relationshipElement in [entityElement elementsForName:@"relationship"]){
     NSString *relationshipName=attr(relationshipElement,@"name");
     NSString *context=[NSString stringWithFormat:@"%@.%@",entityName,relationshipName];
     NSRelationshipDescription *relationship=[[NSRelationshipDescription alloc] init];

     [relationship setName:relationshipName];
     [relationship setOptional:boolAttr(relationshipElement,@"optional")];
     if(boolAttr(relationshipElement,@"transient"))
      [relationship setTransient:YES];

     if(boolAttr(relationshipElement,@"toMany")){
      [relationship setMinCount:[attr(relationshipElement,@"minCount") intValue]];
      [relationship setMaxCount:[attr(relationshipElement,@"maxCount") intValue]];
     }
     else {
      [relationship setMinCount:boolAttr(relationshipElement,@"optional")?0:1];
      [relationship setMaxCount:1];
     }

     if(boolAttr(relationshipElement,@"ordered"))
      [relationship setOrdered:YES];

     NSString *rule=attr(relationshipElement,@"deletionRule");

     if(rule==nil || [rule isEqualToString:@"Nullify"])
      [relationship setDeleteRule:NSNullifyDeleteRule];
     else if([rule isEqualToString:@"Cascade"])
      [relationship setDeleteRule:NSCascadeDeleteRule];
     else if([rule isEqualToString:@"Deny"])
      [relationship setDeleteRule:NSDenyDeleteRule];
     else if([rule isEqualToString:@"No Action"])
      [relationship setDeleteRule:NSNoActionDeleteRule];
     else
      failf(@"%@: unknown deletion rule '%@'",context,rule);

     NSString *destinationName=attr(relationshipElement,@"destinationEntity");
     NSEntityDescription *destination=[entitiesByName objectForKey:destinationName];

     if(destination==nil)
      failf(@"%@: unknown destination entity '%@'",context,destinationName);
     [relationship setDestinationEntity:destination];

     [properties addObject:relationship];
    }

    [entity setProperties:properties];
   }

   /* Pass 3: inverse relationships (every relationship now exists),
      uniqueness constraints and user info. */
   for(NSString *entityName in entitiesByName){
    NSXMLElement        *entityElement=[elementsByName objectForKey:entityName];
    NSEntityDescription *entity=[entitiesByName objectForKey:entityName];

    for(NSXMLElement *relationshipElement in [entityElement elementsForName:@"relationship"]){
     NSString *inverseName=attr(relationshipElement,@"inverseName");
     NSString *inverseEntityName=attr(relationshipElement,@"inverseEntity");

     if(inverseName==nil)
      continue;

     NSRelationshipDescription *relationship=
         [[entity relationshipsByName] objectForKey:attr(relationshipElement,@"name")];
     NSEntityDescription *inverseEntity=[entitiesByName objectForKey:inverseEntityName];
     NSRelationshipDescription *inverse=
         [[inverseEntity relationshipsByName] objectForKey:inverseName];

     if(inverse==nil)
      failf(@"%@.%@: unknown inverse relationship %@.%@",entityName,
            attr(relationshipElement,@"name"),inverseEntityName,inverseName);

     [relationship setInverseRelationship:inverse];
    }

    NSXMLElement *constraintsElement=childNamed(entityElement,@"uniquenessConstraints");

    if(constraintsElement!=nil){
     NSMutableArray *constraints=[NSMutableArray array];

     for(NSXMLElement *constraintElement in [constraintsElement elementsForName:@"uniquenessConstraint"]){
      NSMutableArray *names=[NSMutableArray array];

      for(NSXMLElement *item in [constraintElement elementsForName:@"constraint"])
       [names addObject:attr(item,@"value")];
      if([names count]>0)
       [constraints addObject:names];
     }
     if([constraints count]>0)
      [entity setUniquenessConstraints:constraints];
    }

    NSXMLElement *userInfoElement=childNamed(entityElement,@"userInfo");

    if(userInfoElement!=nil){
     NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

     for(NSXMLElement *entry in [userInfoElement elementsForName:@"entry"])
      if(attr(entry,@"key")!=nil)
       [userInfo setObject:attr(entry,@"value")?:@"" forKey:attr(entry,@"key")];
     if([userInfo count]>0)
      [entity setUserInfo:userInfo];
    }
   }

   /* Pass 4: subentity wiring. */
   for(NSString *parentName in subentityNames){
    NSEntityDescription *parent=[entitiesByName objectForKey:parentName];

    if(parent==nil)
     failf(@"unknown parent entity '%@'",parentName);

    NSMutableArray *children=[NSMutableArray array];

    for(NSString *childName in [subentityNames objectForKey:parentName])
     [children addObject:[entitiesByName objectForKey:childName]];
    [parent setSubentities:children];
   }

   NSManagedObjectModel *model=[[NSManagedObjectModel alloc] init];

   [model setEntities:[entitiesByName allValues]];

   /* Configurations. */
   for(NSXMLElement *configurationElement in [root elementsForName:@"configuration"]){
    NSString       *configurationName=attr(configurationElement,@"name");
    NSMutableArray *members=[NSMutableArray array];

    for(NSXMLElement *member in [configurationElement elementsForName:@"memberEntity"]){
     NSEntityDescription *entity=[entitiesByName objectForKey:attr(member,@"name")];

     if(entity==nil)
      failf(@"configuration %@: unknown entity '%@'",configurationName,attr(member,@"name"));
     [members addObject:entity];
    }
    [model setEntities:members forConfiguration:configurationName];
   }

   /* Fetch request templates. */
   for(NSXMLElement *fetchElement in [root elementsForName:@"fetchRequest"]){
    NSString *templateName=attr(fetchElement,@"name");
    NSEntityDescription *entity=[entitiesByName objectForKey:attr(fetchElement,@"entity")];

    if(entity==nil)
     failf(@"fetch request template %@: unknown entity '%@'",templateName,attr(fetchElement,@"entity"));

    NSFetchRequest *fetchRequest=[[NSFetchRequest alloc] init];

    [fetchRequest setEntity:entity];
    if(attr(fetchElement,@"predicateString")!=nil)
     [fetchRequest setPredicate:
         [NSPredicate predicateWithFormat:attr(fetchElement,@"predicateString")]];
    if(attr(fetchElement,@"fetchLimit")!=nil)
     [fetchRequest setFetchLimit:[attr(fetchElement,@"fetchLimit") intValue]];
    [model setFetchRequestTemplate:fetchRequest forName:templateName];
   }

   return model;
}

/* --- artifact writing ----------------------------------------------- */

static void writeMom(NSManagedObjectModel *model,NSString *path){
   NSData *data=[NSKeyedArchiver archivedDataWithRootObject:model];

   if(![data writeToFile:path atomically:YES])
    failf(@"cannot write %@",path);
}

static NSDictionary *versionHashesForModel(NSManagedObjectModel *model){
   NSMutableDictionary *hashes=[NSMutableDictionary dictionary];

   for(NSEntityDescription *entity in [model entities])
    if([entity versionHash]!=nil)
     [hashes setObject:[entity versionHash] forKey:[entity name]];
   return hashes;
}

static void compileModelBundle(NSString *source,NSString *destination){
   NSFileManager  *fileManager=[NSFileManager defaultManager];
   NSMutableArray *versions=[NSMutableArray array];

   for(NSString *name in [[fileManager contentsOfDirectoryAtPath:source error:NULL]
                             sortedArrayUsingSelector:@selector(compare:)])
    if([[name pathExtension] isEqualToString:@"xcdatamodel"])
     [versions addObject:name];

   if([versions count]==0)
    failf(@"%@ contains no .xcdatamodel versions",source);

   /* .xccurrentversion names the current version; with a single
      version (or none marked) the first one is current. */
   NSString     *currentVersion=[versions objectAtIndex:0];
   NSDictionary *currentInfo=[NSDictionary dictionaryWithContentsOfFile:
       [source stringByAppendingPathComponent:@".xccurrentversion"]];

   if([currentInfo objectForKey:@"_XCCurrentVersionName"]!=nil){
    NSString *marked=[currentInfo objectForKey:@"_XCCurrentVersionName"];

    if(![versions containsObject:marked])
     failf(@"%@: current version '%@' does not exist",source,marked);
    currentVersion=marked;
   }
   else if([versions count]>1)
    warnf(@"%@: no .xccurrentversion; using '%@' as the current version",source,currentVersion);

   if([fileManager fileExistsAtPath:destination])
    [fileManager removeItemAtPath:destination error:NULL];

   NSError *fsError=nil;

   if(![fileManager createDirectoryAtPath:destination withIntermediateDirectories:YES
                               attributes:nil error:&fsError])
    failf(@"cannot create %@: %@",destination,[fsError localizedDescription]);

   NSMutableDictionary *allHashes=[NSMutableDictionary dictionary];

   for(NSString *version in versions){
    NSString *baseName=[version stringByDeletingPathExtension];
    NSManagedObjectModel *model=compileModel([source stringByAppendingPathComponent:version]);

    writeMom(model,[destination stringByAppendingPathComponent:
        [baseName stringByAppendingPathExtension:@"mom"]]);
    [allHashes setObject:versionHashesForModel(model) forKey:baseName];
   }

   NSDictionary *versionInfo=[NSDictionary dictionaryWithObjectsAndKeys:
       [currentVersion stringByDeletingPathExtension],
       @"NSManagedObjectModel_CurrentVersionName",
       allHashes,@"NSManagedObjectModel_VersionHashes",nil];

   /* XML plist explicitly, so the bundle reads identically everywhere
      (GNUstep's default writeToFile: emits the OpenStep format). */
   NSError *plistError=nil;
   NSData  *plistData=[NSPropertyListSerialization dataWithPropertyList:versionInfo
                                                                 format:NSPropertyListXMLFormat_v1_0
                                                                options:0
                                                                  error:&plistError];

   if(plistData==nil ||
      ![plistData writeToFile:
           [destination stringByAppendingPathComponent:@"VersionInfo.plist"]
                    atomically:YES])
    failf(@"cannot write VersionInfo.plist into %@: %@",destination,
          [plistError localizedDescription]);
}

/* --- public API ------------------------------------------------------ */

@implementation CDModelCompiler

+ (void)setWarningHandler:(void (^)(NSString *message))handler {
   warningHandler=[handler copy];
}

static NSError *errorFromException(NSException *exception){
   return [NSError errorWithDomain:CDModelCompilerErrorDomain
                              code:1
                          userInfo:[NSDictionary dictionaryWithObject:[exception reason]
                                                               forKey:NSLocalizedDescriptionKey]];
}

+ (NSManagedObjectModel *)compileModelAtPath:(NSString *)xcdatamodelPath
                                       error:(NSError **)error {
   @try {
    return compileModel(xcdatamodelPath);
   }
   @catch(NSException *exception) {
    if(![[exception name] isEqualToString:CDModelCompilerException])
     @throw;
    if(error!=NULL)
     *error=errorFromException(exception);
    return nil;
   }
}

+ (BOOL)compileModelSourceAtPath:(NSString *)sourcePath
                          toPath:(NSString *)destinationPath
                           error:(NSError **)error {
   @try {
    BOOL isDirectory=NO;

    if(![[NSFileManager defaultManager] fileExistsAtPath:sourcePath
                                             isDirectory:&isDirectory] || !isDirectory)
     failf(@"no model at %@",sourcePath);

    if([[sourcePath pathExtension] isEqualToString:@"xcdatamodel"])
     writeMom(compileModel(sourcePath),destinationPath);
    else if([[sourcePath pathExtension] isEqualToString:@"xcdatamodeld"])
     compileModelBundle(sourcePath,destinationPath);
    else
     failf(@"%@ is not a .xcdatamodeld or .xcdatamodel",sourcePath);

    return YES;
   }
   @catch(NSException *exception) {
    if(![[exception name] isEqualToString:CDModelCompilerException])
     @throw;
    if(error!=NULL)
     *error=errorFromException(exception);
    return NO;
   }
}

@end
