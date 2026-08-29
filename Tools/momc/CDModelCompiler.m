/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDModelCompiler.h"
#import <CoreData/CoreData.h>
#import <objc/runtime.h>

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

#if defined(__APPLE__)
    /* Apple registers the derivation helpers under their colon-suffixed
       names (canonical:, uppercase:, ...); gnustep-base registers the
       colon-less spellings. */
    function=[function stringByAppendingString:@":"];
#endif

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

static NSDictionary *userInfoFromElement(NSXMLElement *element){
   NSXMLElement *wrapper=childNamed(element,@"userInfo");

   if(wrapper==nil)
    return nil;

   NSMutableDictionary *userInfo=[NSMutableDictionary dictionary];

   for(NSXMLElement *entry in [wrapper elementsForName:@"entry"])
    if(attr(entry,@"key")!=nil)
     [userInfo setObject:attr(entry,@"value")?:@"" forKey:attr(entry,@"key")];
   return [userInfo count]>0?userInfo:nil;
}

/* --- model compilation ---------------------------------------------- */

static NSManagedObjectModel *compileModelData(NSData *data,NSString *contentsPath){
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
    if(attr(entityElement,@"elementID")!=nil)
     [entity setRenamingIdentifier:attr(entityElement,@"elementID")];
    if(attr(entityElement,@"codeGenerationType")!=nil)
     [CDModelCompiler setEntity:entity
             codeGenerationType:attr(entityElement,@"codeGenerationType")];

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
     if(attr(attributeElement,@"versionHashModifier")!=nil)
      [attribute setVersionHashModifier:attr(attributeElement,@"versionHashModifier")];
     if(attr(attributeElement,@"valueTransformerName")!=nil)
      [attribute setValueTransformerName:attr(attributeElement,@"valueTransformerName")];
     if(attr(attributeElement,@"customClassName")!=nil)
      [attribute setAttributeValueClassName:attr(attributeElement,@"customClassName")];

     id defaultValue=defaultValueForAttribute(attributeElement,type,context);

     if(defaultValue!=nil)
      [attribute setDefaultValue:defaultValue];
     if(userInfoFromElement(attributeElement)!=nil)
      [attribute setUserInfo:userInfoFromElement(attributeElement)];
     if(attr(attributeElement,@"renamingIdentifier")!=nil)
      [attribute setRenamingIdentifier:attr(attributeElement,@"renamingIdentifier")];
     [CDModelCompiler setAttribute:attribute
               usesScalarValueType:boolAttr(attributeElement,@"usesScalarValueType")];

     /* Validation: Xcode spells numeric and string-length bounds as
        minValueString/maxValueString (lengths for strings), regexes as
        regularExpressionString, and date bounds as min/maxDateTimeInterval. */
     {
      NSMutableDictionary *validation=[NSMutableDictionary dictionary];

      switch(type){
       case NSInteger16AttributeType:
       case NSInteger32AttributeType:
       case NSInteger64AttributeType:
       case NSDecimalAttributeType:
       case NSDoubleAttributeType:
       case NSFloatAttributeType:
        if(attr(attributeElement,@"minValueString")!=nil)
         [validation setObject:attr(attributeElement,@"minValueString") forKey:@"min"];
        if(attr(attributeElement,@"maxValueString")!=nil)
         [validation setObject:attr(attributeElement,@"maxValueString") forKey:@"max"];
        break;
       case NSStringAttributeType:
        if(attr(attributeElement,@"minValueString")!=nil)
         [validation setObject:attr(attributeElement,@"minValueString") forKey:@"minLength"];
        if(attr(attributeElement,@"maxValueString")!=nil)
         [validation setObject:attr(attributeElement,@"maxValueString") forKey:@"maxLength"];
        if(attr(attributeElement,@"regularExpressionString")!=nil)
         [validation setObject:attr(attributeElement,@"regularExpressionString") forKey:@"regex"];
        break;
       case NSDateAttributeType:
        if(attr(attributeElement,@"minDateTimeInterval")!=nil)
         [validation setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:
             [attr(attributeElement,@"minDateTimeInterval") doubleValue]] forKey:@"minDate"];
        if(attr(attributeElement,@"maxDateTimeInterval")!=nil)
         [validation setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:
             [attr(attributeElement,@"maxDateTimeInterval") doubleValue]] forKey:@"maxDate"];
        break;
       default:
        break;
      }
      if([validation count]>0)
       [CDModelCompiler applyValidationInfo:validation toAttribute:attribute];
     }

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
     if(attr(relationshipElement,@"versionHashModifier")!=nil)
      [relationship setVersionHashModifier:attr(relationshipElement,@"versionHashModifier")];
     if(attr(relationshipElement,@"renamingIdentifier")!=nil)
      [relationship setRenamingIdentifier:attr(relationshipElement,@"renamingIdentifier")];

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
     if(userInfoFromElement(relationshipElement)!=nil)
      [relationship setUserInfo:userInfoFromElement(relationshipElement)];

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

    NSDictionary *entityUserInfo=userInfoFromElement(entityElement);

    if(entityUserInfo!=nil)
     [entity setUserInfo:entityUserInfo];
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
    if(attr(fetchElement,@"fetchBatchSize")!=nil)
     [fetchRequest setFetchBatchSize:[attr(fetchElement,@"fetchBatchSize") intValue]];
    /* Xcode's integer spelling: 0 objects, 1 object IDs, 2 dictionaries. */
    switch([attr(fetchElement,@"resultType") intValue]){
     case 1: [fetchRequest setResultType:NSManagedObjectIDResultType]; break;
     case 2: [fetchRequest setResultType:NSDictionaryResultType]; break;
     default: [fetchRequest setResultType:NSManagedObjectResultType]; break;
    }
    /* The template flags are explicit: like Apple's momc, an absent
       attribute compiles as NO (the NSFetchRequest runtime defaults do
       not apply to templates).  Note Xcode's inconsistent spellings. */
    [fetchRequest setIncludesSubentities:boolAttr(fetchElement,@"includeSubentities")];
    [fetchRequest setIncludesPropertyValues:boolAttr(fetchElement,@"includePropertyValues")];
    [fetchRequest setReturnsObjectsAsFaults:boolAttr(fetchElement,@"returnObjectsAsFaults")];
    [fetchRequest setIncludesPendingChanges:boolAttr(fetchElement,@"includesPendingChanges")];
    [fetchRequest setReturnsDistinctResults:boolAttr(fetchElement,@"returnDistinctResults")];
    [model setFetchRequestTemplate:fetchRequest forName:templateName];
   }

   return model;
}

static NSManagedObjectModel *compileModel(NSString *xcdatamodelPath){
   NSString *contentsPath=[xcdatamodelPath stringByAppendingPathComponent:@"contents"];
   NSData   *data=[NSData dataWithContentsOfFile:contentsPath];

   if(data==nil)
    failf(@"cannot read %@",contentsPath);

   return compileModelData(data,contentsPath);
}

/* --- artifact writing ----------------------------------------------- */

static void writeMom(NSManagedObjectModel *model,NSString *path){
   NSData *data=nil;

#if !defined(__APPLE__)
   /* gnustep-base releases up to and including 1.31.1 implement
      -[NSPredicate encodeWithCoder:] and -[NSExpression encodeWithCoder:]
      as -subclassResponsibility:.  The exception raised mid-encode leaves
      NSKeyedArchiver's internal state torn, and DEALLOCATING the archiver
      afterwards segfaults - so +archivedDataWithRootObject: cannot be
      wrapped in @try (the crash happens inside it).  Instead we drive a
      manually allocated archiver and, on failure, park it in a static
      array so it is never deallocated, then report a readable error.
      Predicate/expression archiving works on gnustep-base master as of
      2026-07-30 (libs-base PRs #716/#718). */
   static NSMutableArray *tornArchivers=nil;
   NSMutableData   *buffer=[NSMutableData data];
   NSKeyedArchiver *archiver=[[NSKeyedArchiver alloc] initForWritingWithMutableData:buffer];

   @try {
      [archiver encodeObject:model forKey:@"root"];
      [archiver finishEncoding];
      data=buffer;
   }
   @catch(NSException *exception) {
      if(tornArchivers==nil)
       tornArchivers=[[NSMutableArray alloc] init];
      [tornArchivers addObject:archiver]; // deliberate leak, see above
      failf(@"cannot archive model: %@ - this gnustep-base cannot encode "
            @"NSPredicate/NSExpression (needed for fetch request templates "
            @"and derived attributes); use gnustep-base master from "
            @"2026-07-30 or later",[exception reason]);
   }
#else
   data=[NSKeyedArchiver archivedDataWithRootObject:model];
#endif

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

+ (NSManagedObjectModel *)compileModelContentsXML:(NSString *)xml
                                            error:(NSError **)error {
   @try {
    NSData *data=[xml dataUsingEncoding:NSUTF8StringEncoding];

    if(data==nil)
     failf(@"model contents are not encodable as UTF-8");
    return compileModelData(data,@"(in-memory contents)");
   }
   @catch(NSException *exception) {
    if(![[exception name] isEqualToString:CDModelCompilerException])
     @throw;
    if(error!=NULL)
     *error=errorFromException(exception);
    return nil;
   }
}

+ (NSArray *)attributeTypeNames {
   return [NSArray arrayWithObjects:
       @"Undefined",@"Integer 16",@"Integer 32",@"Integer 64",
       @"Decimal",@"Double",@"Float",@"String",@"Boolean",
       @"Date",@"Binary",@"UUID",@"URI",@"Transformable",nil];
}

+ (NSInteger)attributeTypeNamed:(NSString *)name {
   @try {
    return attributeTypeFromString(name,@"attributeTypeNamed:");
   }
   @catch(NSException *exception) {
    if(![[exception name] isEqualToString:CDModelCompilerException])
     @throw;
    return -1;
   }
}

+ (NSString *)nameForAttributeType:(NSInteger)type {
   for(NSString *name in [self attributeTypeNames])
    if(attributeTypeFromString(name,@"nameForAttributeType:")==type)
     return name;
   return nil;
}

static char CDUsesScalarValueTypeKey;

+ (BOOL)attributeUsesScalarValueType:(NSAttributeDescription *)attribute {
   return [objc_getAssociatedObject(attribute,&CDUsesScalarValueTypeKey) boolValue];
}

+ (void)setAttribute:(NSAttributeDescription *)attribute
 usesScalarValueType:(BOOL)flag {
   objc_setAssociatedObject(attribute,&CDUsesScalarValueTypeKey,
       flag?@YES:nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static char CDCodeGenerationTypeKey;

+ (NSString *)entityCodeGenerationType:(NSEntityDescription *)entity {
   return objc_getAssociatedObject(entity,&CDCodeGenerationTypeKey);
}

+ (void)setEntity:(NSEntityDescription *)entity
 codeGenerationType:(NSString *)type {
   objc_setAssociatedObject(entity,&CDCodeGenerationTypeKey,
       [type length]>0?type:nil,OBJC_ASSOCIATION_COPY_NONATOMIC);
}

/* The canonical validation predicate shapes.  Each is paired with its
   standard warning code, which doubles as the recognizer: the shapes
   must survive a predicateFormat round trip (the GNUstep port archives
   validation predicates as format strings). */
static NSPredicate *comparison(NSString *keyPath,NSPredicateOperatorType op,id constant){
   NSExpression *left=(keyPath==nil)?[NSExpression expressionForEvaluatedObject]
                                    :[NSExpression expressionForKeyPath:keyPath];
   return [NSComparisonPredicate predicateWithLeftExpression:left
       rightExpression:[NSExpression expressionForConstantValue:constant]
       modifier:NSDirectPredicateModifier
       type:op
       options:0];
}

static NSNumber *numberFromString(NSString *string,NSAttributeType type){
   switch(type){
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
     return [NSNumber numberWithLongLong:[string longLongValue]];
    case NSDecimalAttributeType:
     return [NSDecimalNumber decimalNumberWithString:string];
    default:
     return [NSNumber numberWithDouble:[string doubleValue]];
   }
}

+ (void)applyValidationInfo:(NSDictionary *)info
                toAttribute:(NSAttributeDescription *)attribute {
   NSMutableArray *predicates=[NSMutableArray array];
   NSMutableArray *warnings=[NSMutableArray array];
   NSAttributeType type=[attribute attributeType];

   if([info objectForKey:@"min"]!=nil){
    [predicates addObject:comparison(nil,NSGreaterThanOrEqualToPredicateOperatorType,
        numberFromString([info objectForKey:@"min"],type))];
    [warnings addObject:[NSNumber numberWithInteger:NSValidationNumberTooSmallError]];
   }
   if([info objectForKey:@"max"]!=nil){
    [predicates addObject:comparison(nil,NSLessThanOrEqualToPredicateOperatorType,
        numberFromString([info objectForKey:@"max"],type))];
    [warnings addObject:[NSNumber numberWithInteger:NSValidationNumberTooLargeError]];
   }
   if([info objectForKey:@"minLength"]!=nil){
    [predicates addObject:comparison(@"length",NSGreaterThanOrEqualToPredicateOperatorType,
        [NSNumber numberWithLongLong:[[info objectForKey:@"minLength"] longLongValue]])];
    [warnings addObject:[NSNumber numberWithInteger:NSValidationStringTooShortError]];
   }
   if([info objectForKey:@"maxLength"]!=nil){
    [predicates addObject:comparison(@"length",NSLessThanOrEqualToPredicateOperatorType,
        [NSNumber numberWithLongLong:[[info objectForKey:@"maxLength"] longLongValue]])];
    [warnings addObject:[NSNumber numberWithInteger:NSValidationStringTooLongError]];
   }
   if([info objectForKey:@"regex"]!=nil){
    [predicates addObject:comparison(nil,NSMatchesPredicateOperatorType,
        [info objectForKey:@"regex"])];
    [warnings addObject:[NSNumber numberWithInteger:NSValidationStringPatternMatchingError]];
   }
   if([info objectForKey:@"minDate"]!=nil){
    [predicates addObject:comparison(@"timeIntervalSinceReferenceDate",
        NSGreaterThanOrEqualToPredicateOperatorType,
        [NSNumber numberWithDouble:
            [[info objectForKey:@"minDate"] timeIntervalSinceReferenceDate]])];
    [warnings addObject:[NSNumber numberWithInteger:NSValidationDateTooSoonError]];
   }
   if([info objectForKey:@"maxDate"]!=nil){
    [predicates addObject:comparison(@"timeIntervalSinceReferenceDate",
        NSLessThanOrEqualToPredicateOperatorType,
        [NSNumber numberWithDouble:
            [[info objectForKey:@"maxDate"] timeIntervalSinceReferenceDate]])];
    [warnings addObject:[NSNumber numberWithInteger:NSValidationDateTooLateError]];
   }

   [attribute setValidationPredicates:predicates withValidationWarnings:warnings];
}

static id constantOfComparison(NSPredicate *predicate){
   if(![predicate isKindOfClass:[NSComparisonPredicate class]])
    return nil;
   return [[(NSComparisonPredicate *)predicate rightExpression] constantValue];
}

+ (NSDictionary *)validationInfoForAttribute:(NSAttributeDescription *)attribute {
   NSMutableDictionary *info=[NSMutableDictionary dictionary];
   NSArray *predicates=[attribute validationPredicates];
   NSArray *warnings=[attribute validationWarnings];
   NSUInteger i,count=MIN([predicates count],[warnings count]);

   for(i=0;i<count;i++){
    id constant=constantOfComparison([predicates objectAtIndex:i]);
    if(constant==nil)
     continue;
    switch([[warnings objectAtIndex:i] integerValue]){
     case NSValidationNumberTooSmallError:
      [info setObject:[constant description] forKey:@"min"]; break;
     case NSValidationNumberTooLargeError:
      [info setObject:[constant description] forKey:@"max"]; break;
     case NSValidationStringTooShortError:
      [info setObject:[constant description] forKey:@"minLength"]; break;
     case NSValidationStringTooLongError:
      [info setObject:[constant description] forKey:@"maxLength"]; break;
     case NSValidationStringPatternMatchingError:
      [info setObject:[constant description] forKey:@"regex"]; break;
     case NSValidationDateTooSoonError:
      [info setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:
          [constant doubleValue]] forKey:@"minDate"]; break;
     case NSValidationDateTooLateError:
      [info setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:
          [constant doubleValue]] forKey:@"maxDate"]; break;
     default: break;
    }
   }
   return info;
}

+ (NSArray *)deleteRuleNames {
   return [NSArray arrayWithObjects:@"Nullify",@"Cascade",@"Deny",@"No Action",nil];
}

+ (NSExpression *)derivationExpressionFromString:(NSString *)string
                                           error:(NSError **)error {
   @try {
    return derivationExpressionFromString(string,@"derivation expression");
   }
   @catch(NSException *exception) {
    if(![[exception name] isEqualToString:CDModelCompilerException])
     @throw;
    if(error!=NULL)
     *error=errorFromException(exception);
    return nil;
   }
}

@end
