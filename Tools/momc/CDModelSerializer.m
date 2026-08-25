/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDModelSerializer.h"
#import <CoreData/CoreData.h>

NSString * const CDModelSerializerErrorDomain=@"CDModelSerializerErrorDomain";

static NSString * const CDModelSerializerException=@"CDModelSerializerException";

static void sfailf(NSString *format,...) __attribute__((noreturn));
static void sfailf(NSString *format,...){
   va_list arguments;
   va_start(arguments,format);
   NSString *message=[[NSString alloc] initWithFormat:format arguments:arguments];
   va_end(arguments);
   [NSException raise:CDModelSerializerException format:@"%@",message];
   abort(); /* not reached */
}

/* --- helpers -------------------------------------------------------- */

static void setAttr(NSXMLElement *element,NSString *name,NSString *value){
   if(value==nil)
    return;

   NSXMLNode *node=[NSXMLNode attributeWithName:name stringValue:value];

   [element addAttribute:node];
}

static NSString *attributeTypeName(NSAttributeType type,NSString *context){
   switch(type){
    case NSUndefinedAttributeType:     return @"Undefined";
    case NSInteger16AttributeType:     return @"Integer 16";
    case NSInteger32AttributeType:     return @"Integer 32";
    case NSInteger64AttributeType:     return @"Integer 64";
    case NSDecimalAttributeType:       return @"Decimal";
    case NSDoubleAttributeType:        return @"Double";
    case NSFloatAttributeType:         return @"Float";
    case NSStringAttributeType:        return @"String";
    case NSBooleanAttributeType:       return @"Boolean";
    case NSDateAttributeType:          return @"Date";
    case NSBinaryDataAttributeType:    return @"Binary";
    case NSTransformableAttributeType: return @"Transformable";
    case NSUUIDAttributeType:          return @"UUID";
    case NSURIAttributeType:           return @"URI";
    default:
     sfailf(@"%@: attribute type %d has no Xcode spelling",context,(int)type);
   }
}

/* Xcode writes date defaults as defaultDateTimeInterval; everything
   else as defaultValueString. */
static void writeDefaultValue(NSXMLElement *element,NSAttributeDescription *attribute,NSString *context){
   id value=[attribute defaultValue];

   if(value==nil)
    return;

   switch([attribute attributeType]){
    case NSDateAttributeType:
     setAttr(element,@"defaultDateTimeInterval",
             [[NSNumber numberWithDouble:[value timeIntervalSinceReferenceDate]] stringValue]);
     return;
    case NSStringAttributeType:
     setAttr(element,@"defaultValueString",value);
     return;
    case NSBooleanAttributeType:
     setAttr(element,@"defaultValueString",[value boolValue]?@"YES":@"NO");
     return;
    case NSInteger16AttributeType:
    case NSInteger32AttributeType:
    case NSInteger64AttributeType:
    case NSDoubleAttributeType:
    case NSFloatAttributeType:
    case NSDecimalAttributeType:
     setAttr(element,@"defaultValueString",[value stringValue]);
     return;
    case NSUUIDAttributeType:
     setAttr(element,@"defaultValueString",[value UUIDString]);
     return;
    case NSURIAttributeType:
     setAttr(element,@"defaultValueString",[value absoluteString]);
     return;
    default:
     sfailf(@"%@: cannot serialize a default value for this attribute type",context);
   }
}

/* Inverse of CDModelCompiler's derivationExpressionFromString: Xcode
   spelling - "now()", "function:(key.path)" (colon form even where
   gnustep-base stores the colon-less name), or a bare key path. */
static NSString *derivationString(NSExpression *expression,NSString *context){
   switch([expression expressionType]){

    case NSKeyPathExpressionType:
     return [expression keyPath];

    case NSFunctionExpressionType:{
     NSString *name=[expression function];

     if([name hasSuffix:@":"])
      name=[name substringToIndex:[name length]-1];

     NSArray *arguments=[expression arguments];

     if([arguments count]==0)
      return [name stringByAppendingString:@"()"];

     NSExpression *argument=[arguments objectAtIndex:0];
     NSString     *argumentString;

     if([argument expressionType]==NSKeyPathExpressionType)
      argumentString=[argument keyPath];
     else
      argumentString=[argument description];

     return [NSString stringWithFormat:@"%@:(%@)",name,argumentString];
    }

    default:
     sfailf(@"%@: cannot serialize derivation expression %@",context,expression);
   }
}

static NSString *deleteRuleName(NSDeleteRule rule){
   switch(rule){
    case NSCascadeDeleteRule:  return @"Cascade";
    case NSDenyDeleteRule:     return @"Deny";
    case NSNoActionDeleteRule: return @"No Action";
    case NSNullifyDeleteRule:
    default:                   return @"Nullify";
   }
}

static void writeUserInfo(NSXMLElement *element,NSDictionary *userInfo){
   if([userInfo count]==0)
    return;

   NSXMLElement *wrapper=[NSXMLElement elementWithName:@"userInfo"];

   for(NSString *key in [[userInfo allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    NSXMLElement *entry=[NSXMLElement elementWithName:@"entry"];

    setAttr(entry,@"key",key);
    setAttr(entry,@"value",[[userInfo objectForKey:key] description]);
    [wrapper addChild:entry];
   }
   [element addChild:wrapper];
}

static NSString *constraintMemberName(id member){
   if([member respondsToSelector:@selector(name)])
    return [member name];
   return [member description];
}

/* --- serialization -------------------------------------------------- */

static NSXMLElement *elementForAttribute(NSAttributeDescription *attribute,NSString *entityName){
   NSString     *context=[NSString stringWithFormat:@"%@.%@",entityName,[attribute name]];
   NSXMLElement *element=[NSXMLElement elementWithName:@"attribute"];

   setAttr(element,@"name",[attribute name]);
   if([attribute isOptional])
    setAttr(element,@"optional",@"YES");

   if([attribute isKindOfClass:[NSDerivedAttributeDescription class]]){
    NSExpression *expression=[(NSDerivedAttributeDescription *)attribute derivationExpression];

    setAttr(element,@"derived",@"YES");
    if(expression!=nil)
     setAttr(element,@"derivationExpression",derivationString(expression,context));
   }

   setAttr(element,@"attributeType",
           attributeTypeName([attribute attributeType],context));
   if([attribute isTransient])
    setAttr(element,@"transient",@"YES");
   if([attribute valueTransformerName]!=nil)
    setAttr(element,@"valueTransformerName",[attribute valueTransformerName]);
   if([attribute attributeValueClassName]!=nil &&
      [attribute attributeType]==NSTransformableAttributeType)
    setAttr(element,@"customClassName",[attribute attributeValueClassName]);
   writeDefaultValue(element,attribute,context);
   setAttr(element,@"usesScalarValueType",@"NO");
   writeUserInfo(element,[attribute userInfo]);
   return element;
}

static NSXMLElement *elementForRelationship(NSRelationshipDescription *relationship,NSString *entityName){
   NSXMLElement *element=[NSXMLElement elementWithName:@"relationship"];

   setAttr(element,@"name",[relationship name]);
   if([relationship isOptional])
    setAttr(element,@"optional",@"YES");
   if([relationship isTransient])
    setAttr(element,@"transient",@"YES");

   if([relationship isToMany]){
    setAttr(element,@"toMany",@"YES");
    if([relationship minCount]>0)
     setAttr(element,@"minCount",
             [NSString stringWithFormat:@"%ld",(long)[relationship minCount]]);
    if([relationship maxCount]>0)
     setAttr(element,@"maxCount",
             [NSString stringWithFormat:@"%ld",(long)[relationship maxCount]]);
    if([relationship isOrdered])
     setAttr(element,@"ordered",@"YES");
   }
   else
    setAttr(element,@"maxCount",@"1");

   setAttr(element,@"deletionRule",deleteRuleName([relationship deleteRule]));
   if([relationship destinationEntity]!=nil)
    setAttr(element,@"destinationEntity",[[relationship destinationEntity] name]);

   NSRelationshipDescription *inverse=[relationship inverseRelationship];

   if(inverse!=nil){
    setAttr(element,@"inverseName",[inverse name]);
    setAttr(element,@"inverseEntity",
            [[inverse entity] name]?:[[relationship destinationEntity] name]);
   }
   writeUserInfo(element,[relationship userInfo]);
   return element;
}

static NSXMLElement *elementForEntity(NSEntityDescription *entity){
   NSXMLElement *element=[NSXMLElement elementWithName:@"entity"];

   setAttr(element,@"name",[entity name]);
   setAttr(element,@"representedClassName",[entity managedObjectClassName]?:@"NSManagedObject");
   if([entity superentity]!=nil)
    setAttr(element,@"parentEntity",[[entity superentity] name]);
   if([entity isAbstract])
    setAttr(element,@"isAbstract",@"YES");
   if([entity versionHashModifier]!=nil)
    setAttr(element,@"versionHashModifier",[entity versionHashModifier]);
   setAttr(element,@"syncable",@"YES");

   NSDictionary *attributes=[entity attributesByName];
   NSDictionary *relationships=[entity relationshipsByName];
   NSDictionary *ownProperties=[NSDictionary dictionaryWithObjects:[entity properties]
                                                           forKeys:[[entity properties] valueForKey:@"name"]];

   /* propertiesByName includes inherited properties; the XML lists only
      the entity's own.  Sorted for deterministic output. */
   for(NSString *name in [[attributes allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    if([ownProperties objectForKey:name]==nil)
     continue;
    [element addChild:elementForAttribute([attributes objectForKey:name],[entity name])];
   }
   for(NSString *name in [[relationships allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    if([ownProperties objectForKey:name]==nil)
     continue;
    [element addChild:elementForRelationship([relationships objectForKey:name],[entity name])];
   }

   NSArray *constraints=[entity uniquenessConstraints];

   if([constraints count]>0){
    NSXMLElement *wrapper=[NSXMLElement elementWithName:@"uniquenessConstraints"];

    for(NSArray *constraint in constraints){
     NSXMLElement *constraintElement=[NSXMLElement elementWithName:@"uniquenessConstraint"];

     for(id member in constraint){
      NSXMLElement *item=[NSXMLElement elementWithName:@"constraint"];

      setAttr(item,@"value",constraintMemberName(member));
      [constraintElement addChild:item];
     }
     [wrapper addChild:constraintElement];
    }
    [element addChild:wrapper];
   }

   writeUserInfo(element,[entity userInfo]);
   return element;
}

static NSString *serializeModel(NSManagedObjectModel *model,NSDictionary *entityLayouts){
   NSXMLElement *root=[NSXMLElement elementWithName:@"model"];

   setAttr(root,@"type",@"com.apple.IDECoreDataModeler.DataModel");
   setAttr(root,@"documentVersion",@"1.0");
   setAttr(root,@"lastSavedToolsVersion",@"1");
   setAttr(root,@"systemVersion",@"11.0");
   setAttr(root,@"minimumToolsVersion",@"Automatic");
   setAttr(root,@"sourceLanguage",@"Objective-C");
   setAttr(root,@"userDefinedModelVersionIdentifier",@"");

   NSArray *entities=[[model entities] sortedArrayUsingComparator:
       ^NSComparisonResult(NSEntityDescription *a,NSEntityDescription *b){
        return [[a name] compare:[b name]];
       }];

   for(NSEntityDescription *entity in entities)
    [root addChild:elementForEntity(entity)];

   for(NSString *configuration in [[model configurations]
           sortedArrayUsingSelector:@selector(compare:)]){
    NSXMLElement *element=[NSXMLElement elementWithName:@"configuration"];

    setAttr(element,@"name",configuration);

    NSArray *members=[[model entitiesForConfiguration:configuration]
        sortedArrayUsingComparator:
        ^NSComparisonResult(NSEntityDescription *a,NSEntityDescription *b){
         return [[a name] compare:[b name]];
        }];

    for(NSEntityDescription *member in members){
     NSXMLElement *memberElement=[NSXMLElement elementWithName:@"memberEntity"];

     setAttr(memberElement,@"name",[member name]);
     [element addChild:memberElement];
    }
    [root addChild:element];
   }

   NSDictionary *templates=[model fetchRequestTemplatesByName];

   for(NSString *name in [[templates allKeys] sortedArrayUsingSelector:@selector(compare:)]){
    NSFetchRequest *request=[templates objectForKey:name];
    NSXMLElement   *element=[NSXMLElement elementWithName:@"fetchRequest"];

    setAttr(element,@"name",name);
    setAttr(element,@"entity",[[request entity] name]);
    if([request predicate]!=nil)
     setAttr(element,@"predicateString",[[request predicate] predicateFormat]);
    if([request fetchLimit]>0)
     setAttr(element,@"fetchLimit",
             [NSString stringWithFormat:@"%lu",(unsigned long)[request fetchLimit]]);
    [root addChild:element];
   }

   NSXMLElement *elements=[NSXMLElement elementWithName:@"elements"];

   for(NSEntityDescription *entity in entities){
    NSXMLElement *element=[NSXMLElement elementWithName:@"element"];
    NSDictionary *layout=[entityLayouts objectForKey:[entity name]];

    setAttr(element,@"name",[entity name]);
    setAttr(element,@"positionX",[layout objectForKey:@"positionX"]?:@"0");
    setAttr(element,@"positionY",[layout objectForKey:@"positionY"]?:@"0");
    setAttr(element,@"width",[layout objectForKey:@"width"]?:@"128");
    setAttr(element,@"height",[layout objectForKey:@"height"]?:@"128");
    [elements addChild:element];
   }
   [root addChild:elements];

   NSXMLDocument *document=[[NSXMLDocument alloc] initWithRootElement:root];

   [document setVersion:@"1.0"];
   [document setCharacterEncoding:@"UTF-8"];
   [document setStandalone:YES];
   return [document XMLStringWithOptions:NSXMLNodePrettyPrint];
}

/* --- public API ------------------------------------------------------ */

@implementation CDModelSerializer

+ (NSString *)contentsXMLForModel:(NSManagedObjectModel *)model
                    entityLayouts:(NSDictionary *)entityLayouts
                            error:(NSError **)error {
   @try {
    return serializeModel(model,entityLayouts);
   }
   @catch(NSException *exception) {
    if(![[exception name] isEqualToString:CDModelSerializerException])
     @throw;
    if(error!=NULL)
     *error=[NSError errorWithDomain:CDModelSerializerErrorDomain
                                code:1
                            userInfo:[NSDictionary dictionaryWithObject:[exception reason]
                                                                 forKey:NSLocalizedDescriptionKey]];
    return nil;
   }
}

+ (NSString *)contentsXMLForModel:(NSManagedObjectModel *)model
                            error:(NSError **)error {
   return [self contentsXMLForModel:model entityLayouts:nil error:error];
}

/* --- decompilation --------------------------------------------------- */

static NSManagedObjectModel *unarchivedModel(NSString *momPath){
   /* Force +initialize on the classes that register Apple-compatible
      archive aliases (NSKeyPathExpression, ...) before unarchiving. */
   [NSPredicate class];
   [NSExpression class];

   NSData *data=[NSData dataWithContentsOfFile:momPath];

   if(data==nil)
    sfailf(@"cannot read %@",momPath);

   NSKeyedUnarchiver *unarchiver=[[NSKeyedUnarchiver alloc] initForReadingWithData:data];
   NSManagedObjectModel *model=[unarchiver decodeObjectForKey:@"root"];

   if(model==nil)
    sfailf(@"%@ does not contain an archived model",momPath);
   return model;
}

static void writeVersionDirectory(NSManagedObjectModel *model,NSString *versionDir){
   NSError *fsError=nil;

   if(![[NSFileManager defaultManager] createDirectoryAtPath:versionDir
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&fsError])
    sfailf(@"cannot create %@: %@",versionDir,[fsError localizedDescription]);

   NSString *xml=serializeModel(model,nil);

   if(![xml writeToFile:[versionDir stringByAppendingPathComponent:@"contents"]
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:&fsError])
    sfailf(@"cannot write %@/contents: %@",versionDir,[fsError localizedDescription]);
}

static void decompileArtifact(NSString *artifactPath,NSString *destinationPath){
   NSFileManager *fileManager=[NSFileManager defaultManager];

   if([[artifactPath pathExtension] isEqualToString:@"mom"]){
    writeVersionDirectory(unarchivedModel(artifactPath),destinationPath);
    return;
   }

   if(![[artifactPath pathExtension] isEqualToString:@"momd"])
    sfailf(@"%@ is not a .momd or .mom",artifactPath);

   NSMutableArray *versions=[NSMutableArray array];

   for(NSString *name in [[fileManager contentsOfDirectoryAtPath:artifactPath error:NULL]
                             sortedArrayUsingSelector:@selector(compare:)])
    if([[name pathExtension] isEqualToString:@"mom"])
     [versions addObject:name];

   if([versions count]==0)
    sfailf(@"%@ contains no .mom versions",artifactPath);

   NSError *fsError=nil;

   if([fileManager fileExistsAtPath:destinationPath])
    [fileManager removeItemAtPath:destinationPath error:NULL];
   if(![fileManager createDirectoryAtPath:destinationPath
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&fsError])
    sfailf(@"cannot create %@: %@",destinationPath,[fsError localizedDescription]);

   for(NSString *name in versions){
    NSString *baseName=[name stringByDeletingPathExtension];

    writeVersionDirectory(
        unarchivedModel([artifactPath stringByAppendingPathComponent:name]),
        [destinationPath stringByAppendingPathComponent:
            [baseName stringByAppendingPathExtension:@"xcdatamodel"]]);
   }

   NSString *current=[[versions objectAtIndex:0] stringByDeletingPathExtension];
   NSDictionary *versionInfo=[NSDictionary dictionaryWithContentsOfFile:
       [artifactPath stringByAppendingPathComponent:@"VersionInfo.plist"]];

   if([versionInfo objectForKey:@"NSManagedObjectModel_CurrentVersionName"]!=nil)
    current=[versionInfo objectForKey:@"NSManagedObjectModel_CurrentVersionName"];

   NSDictionary *plist=[NSDictionary dictionaryWithObject:
       [current stringByAppendingPathExtension:@"xcdatamodel"]
                                                   forKey:@"_XCCurrentVersionName"];
   NSData *plistData=[NSPropertyListSerialization dataWithPropertyList:plist
                                                                format:NSPropertyListXMLFormat_v1_0
                                                               options:0
                                                                 error:NULL];

   if(plistData==nil ||
      ![plistData writeToFile:[destinationPath stringByAppendingPathComponent:@".xccurrentversion"]
                   atomically:YES])
    sfailf(@"cannot write .xccurrentversion into %@",destinationPath);
}

+ (BOOL)decompileModelArtifactAtPath:(NSString *)artifactPath
                              toPath:(NSString *)destinationPath
                               error:(NSError **)error {
   @try {
    decompileArtifact(artifactPath,destinationPath);
    return YES;
   }
   @catch(NSException *exception) {
    if(![[exception name] isEqualToString:CDModelSerializerException])
     @throw;
    if(error!=NULL)
     *error=[NSError errorWithDomain:CDModelSerializerErrorDomain
                                code:1
                            userInfo:[NSDictionary dictionaryWithObject:[exception reason]
                                                                 forKey:NSLocalizedDescriptionKey]];
    return NO;
   }
}

@end
