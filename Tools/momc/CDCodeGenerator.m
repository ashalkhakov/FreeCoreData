/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDCodeGenerator.h"
#import "CDModelCompiler.h"
#import <CoreData/CoreData.h>

/* The output follows Xcode's Objective-C generator (Editor > Create
   NSManagedObject Subclass... and the class/category build-time
   codegen produce identical code apart from the header comment;
   verified against Xcode 16-era output in both forms): the same file
   pair split, the same bottom-import trick in the class header,
   @dynamic categories, generated to-many accessor declarations, and
   NSFetchRequest<ClassName *> typing.  Matching Xcode exactly:
     - object properties are always `nullable`, optional or not
       (optionality matters to Swift, not to the ObjC declarations);
     - copy for the Foundation value types (NSString, NSNumber,
       NSDecimalNumber, NSDate, NSUUID, NSURL), retain for NSData,
       transformables and relationships;
     - properties come out attributes-then-relationships, each group
       sorted by name: the .xcdatamodel XML order Xcode writes, i.e.
       Xcode's from-disk generation order (and the only ordering that
       is identical on both platforms - see ownOfKind);
     - +fetchRequest carries NS_SWIFT_NAME(fetchRequest()) except on
       entities with subentities (where the inherited class method
       would collide in Swift);
     - a subclass's class header imports Foundation and the parent's
       header only (no <CoreData/CoreData.h>, which arrives through
       the parent).
   The one deliberate difference is the header comment: Xcode stamps
   project, author and date; this generator writes a stable line so
   regenerated files only change when the model does. */

static NSString *className(NSEntityDescription *entity){
   NSString *name=[entity managedObjectClassName];
   return [name length]>0?name:@"NSManagedObject";
}

static BOOL hasCustomClass(NSEntityDescription *entity){
   return ![className(entity) isEqualToString:@"NSManagedObject"];
}

/* The header a subclass or category imports to see the class: the
   generated one for "class"-mode entities, a hand-written ClassName.h
   otherwise. */
static NSString *classHeaderName(NSEntityDescription *entity){
   if([[CDModelCompiler entityCodeGenerationType:entity] isEqualToString:@"class"])
    return [className(entity) stringByAppendingString:@"+CoreDataClass.h"];
   return [className(entity) stringByAppendingString:@".h"];
}

static NSString *capitalizedKey(NSString *key){
   if([key length]==0)
    return key;
   return [[[key substringToIndex:1] uppercaseString]
       stringByAppendingString:[key substringFromIndex:1]];
}

/* Own properties of one kind, sorted by name.  NSEntityDescription's
   -properties order is UNSPECIFIED on Apple (dictionary hash order,
   established by testPropertiesPreserveTheirOrder's macOS run), so a
   generator that wants identical output on every platform must
   impose its own ordering.  Sorted-by-name is Xcode's from-disk
   order: Xcode alphabetizes the .xcdatamodel XML per group on save,
   and its own generator works from that document.  (A live Xcode
   session generates in editing order instead - unreproducible from
   the model.) */
static NSArray *ownOfKind(NSArray *properties,Class filter){
   NSMutableArray *result=[NSMutableArray array];
   for(NSPropertyDescription *property in properties)
    if([property isKindOfClass:filter])
     [result addObject:property];
   [result sortUsingComparator:^NSComparisonResult(id a,id b){
    return [[a name] compare:[b name]];
   }];
   return result;
}

/* One @property line for an attribute; adds any custom value class to
   forwardClasses.  Scalar spellings apply only where Xcode offers a
   scalar (integers, floating point, boolean, dates). */
static NSString *propertyForAttribute(NSAttributeDescription *attribute,
                                      NSMutableSet *forwardClasses){
   BOOL scalar=[CDModelCompiler attributeUsesScalarValueType:attribute];
   NSString *type=nil,*ownership=@"copy";

   switch([attribute attributeType]){
    case NSInteger16AttributeType: type=scalar?@"int16_t":@"NSNumber *"; break;
    case NSInteger32AttributeType: type=scalar?@"int32_t":@"NSNumber *"; break;
    case NSInteger64AttributeType: type=scalar?@"int64_t":@"NSNumber *"; break;
    case NSDoubleAttributeType:    type=scalar?@"double":@"NSNumber *"; break;
    case NSFloatAttributeType:     type=scalar?@"float":@"NSNumber *"; break;
    case NSBooleanAttributeType:   type=scalar?@"BOOL":@"NSNumber *"; break;
    case NSDateAttributeType:      type=scalar?@"NSTimeInterval":@"NSDate *"; break;
    case NSDecimalAttributeType:   type=@"NSDecimalNumber *"; scalar=NO; break;
    case NSStringAttributeType:    type=@"NSString *"; scalar=NO; break;
    case NSBinaryDataAttributeType:type=@"NSData *"; ownership=@"retain"; scalar=NO; break;
    case NSUUIDAttributeType:      type=@"NSUUID *"; scalar=NO; break;
    case NSURIAttributeType:       type=@"NSURL *"; scalar=NO; break;
    case NSTransformableAttributeType:{
     NSString *valueClass=[attribute attributeValueClassName];
     if([valueClass length]>0){
      type=[valueClass stringByAppendingString:@" *"];
      [forwardClasses addObject:valueClass];
     }
     else
      type=@"NSObject *";
     ownership=@"retain";
     scalar=NO;
     break;
    }
    default:                       type=@"id"; ownership=@"retain"; scalar=NO; break;
   }

   /* Object properties are always nullable in Xcode's ObjC output,
      whatever the attribute's optionality. */
   NSString *qualifiers;
   if(![type hasSuffix:@"*"] && ![type isEqualToString:@"id"])
    qualifiers=@"(nonatomic)";   /* scalar */
   else
    qualifiers=[NSString stringWithFormat:@"(nullable, nonatomic, %@)",ownership];

   NSString *separator=[type hasSuffix:@"*"]?@"":@" ";
   return [NSString stringWithFormat:@"@property %@ %@%@%@;",
       qualifiers,type,separator,[attribute name]];
}

/* @property line for a relationship; the destination class goes into
   forwardClasses when custom. */
static NSString *propertyForRelationship(NSRelationshipDescription *relationship,
                                         NSMutableSet *forwardClasses){
   NSString *destination=className([relationship destinationEntity]);
   if(![destination isEqualToString:@"NSManagedObject"])
    [forwardClasses addObject:destination];

   NSString *type;
   if(![relationship isToMany])
    type=[destination stringByAppendingString:@" *"];
   else if([relationship isOrdered])
    type=[NSString stringWithFormat:@"NSOrderedSet<%@ *> *",destination];
   else
    type=[NSString stringWithFormat:@"NSSet<%@ *> *",destination];

   /* always nullable, like attributes */
   return [NSString stringWithFormat:@"@property (nullable, nonatomic, retain) %@%@;",
       type,[relationship name]];
}

/* Xcode's CoreDataGeneratedAccessors declarations for one to-many
   relationship. */
static void appendGeneratedAccessors(NSMutableString *out,
                                     NSRelationshipDescription *relationship){
   NSString *key=[relationship name];
   NSString *Key=capitalizedKey(key);
   NSString *destination=className([relationship destinationEntity]);

   if([relationship isOrdered]){
    [out appendFormat:@"- (void)insertObject:(%@ *)value in%@AtIndex:(NSUInteger)idx;\n",destination,Key];
    [out appendFormat:@"- (void)removeObjectFrom%@AtIndex:(NSUInteger)idx;\n",Key];
    [out appendFormat:@"- (void)insert%@:(NSArray<%@ *> *)value atIndexes:(NSIndexSet *)indexes;\n",Key,destination];
    [out appendFormat:@"- (void)remove%@AtIndexes:(NSIndexSet *)indexes;\n",Key];
    [out appendFormat:@"- (void)replaceObjectIn%@AtIndex:(NSUInteger)idx withObject:(%@ *)value;\n",Key,destination];
    [out appendFormat:@"- (void)replace%@AtIndexes:(NSIndexSet *)indexes with%@:(NSArray<%@ *> *)values;\n",Key,Key,destination];
    [out appendFormat:@"- (void)add%@Object:(%@ *)value;\n",Key,destination];
    [out appendFormat:@"- (void)remove%@Object:(%@ *)value;\n",Key,destination];
    [out appendFormat:@"- (void)add%@:(NSOrderedSet<%@ *> *)values;\n",Key,destination];
    [out appendFormat:@"- (void)remove%@:(NSOrderedSet<%@ *> *)values;\n",Key,destination];
   }
   else {
    [out appendFormat:@"- (void)add%@Object:(%@ *)value;\n",Key,destination];
    [out appendFormat:@"- (void)remove%@Object:(%@ *)value;\n",Key,destination];
    [out appendFormat:@"- (void)add%@:(NSSet<%@ *> *)values;\n",Key,destination];
    [out appendFormat:@"- (void)remove%@:(NSSet<%@ *> *)values;\n",Key,destination];
   }
}

static NSString *fileComment(NSString *filename,BOOL regenerated){
   return [NSString stringWithFormat:
       @"//\n"
       @"//  %@\n"
       @"//\n"
       @"//  %@\n"
       @"//\n\n",
       filename,
       regenerated
           ?@"Generated by momc (FreeCoreData); regenerated from the model, do not edit."
           :@"Generated by momc (FreeCoreData); generated once, yours to extend."];
}

@implementation CDCodeGenerator

+ (NSArray *)generatableEntitiesInModel:(NSManagedObjectModel *)model
                             onlyMarked:(BOOL)onlyMarked {
   NSMutableArray *result=[NSMutableArray array];

   for(NSEntityDescription *entity in [model entities]){
    if(!hasCustomClass(entity))
     continue;
    if(onlyMarked && [CDModelCompiler entityCodeGenerationType:entity]==nil)
     continue;
    [result addObject:entity];
   }
   [result sortUsingComparator:^NSComparisonResult(id a,id b){
    return [[a name] compare:[b name]];
   }];
   return result;
}

+ (NSDictionary *)sourcesForEntity:(NSEntityDescription *)entity {
   NSString *codegen=[CDModelCompiler entityCodeGenerationType:entity];
   BOOL categoryOnly=[codegen isEqualToString:@"category"];
   NSString *class=className(entity);
   NSArray *attributes=ownOfKind([entity properties],[NSAttributeDescription class]);
   NSArray *relationships=ownOfKind([entity properties],[NSRelationshipDescription class]);
   NSMutableSet *forwardClasses=[NSMutableSet set];
   NSMutableArray *propertyLines=[NSMutableArray array];
   NSMutableArray *toMany=[NSMutableArray array];

   for(NSAttributeDescription *attribute in attributes)
    [propertyLines addObject:propertyForAttribute(attribute,forwardClasses)];
   for(NSRelationshipDescription *relationship in relationships){
    [propertyLines addObject:propertyForRelationship(relationship,forwardClasses)];
    if([relationship isToMany])
     [toMany addObject:relationship];
   }
   [forwardClasses removeObject:class];

   NSEntityDescription *parent=[entity superentity];
   BOOL customParent=parent!=nil && hasCustomClass(parent);
   NSString *superclass=customParent?className(parent):@"NSManagedObject";
   [forwardClasses removeObject:superclass];

   NSArray *forwards=[[forwardClasses allObjects]
       sortedArrayUsingSelector:@selector(compare:)];
   NSMutableDictionary *files=[NSMutableDictionary dictionary];

   NSString *propertiesBase=[class stringByAppendingString:@"+CoreDataProperties"];

   if(!categoryOnly){
    /* ClassName+CoreDataClass.h — the class @interface, @class
       forwards for every destination, and Xcode's bottom import of
       the properties header (so importing the class header shows the
       whole surface, without an import cycle). */
    NSString *classBase=[class stringByAppendingString:@"+CoreDataClass"];
    NSMutableString *h=[NSMutableString string];
    [h appendString:fileComment([classBase stringByAppendingString:@".h"],NO)];
    /* A subclass imports Foundation and its parent's header only;
       <CoreData/CoreData.h> arrives through the parent (Xcode does
       the same). */
    [h appendString:@"#import <Foundation/Foundation.h>\n"];
    if(customParent)
     [h appendFormat:@"#import \"%@\"\n",classHeaderName(parent)];
    else
     [h appendString:@"#import <CoreData/CoreData.h>\n"];
    [h appendString:@"\n"];
    if([forwards count]>0)
     [h appendFormat:@"@class %@;\n\n",
         [forwards componentsJoinedByString:@", "]];
    [h appendString:@"NS_ASSUME_NONNULL_BEGIN\n\n"];
    [h appendFormat:@"@interface %@ : %@\n\n@end\n\n",class,superclass];
    [h appendString:@"NS_ASSUME_NONNULL_END\n\n"];
    [h appendFormat:@"#import \"%@.h\"\n",propertiesBase];
    [files setObject:h forKey:[classBase stringByAppendingString:@".h"]];

    NSMutableString *m=[NSMutableString string];
    [m appendString:fileComment([classBase stringByAppendingString:@".m"],NO)];
    [m appendFormat:@"#import \"%@.h\"\n\n",classBase];
    [m appendFormat:@"@implementation %@\n\n@end\n",class];
    [files setObject:m forKey:[classBase stringByAppendingString:@".m"]];
   }

   /* ClassName+CoreDataProperties.h — the @dynamic property category
      and the generated to-many accessors. */
   NSMutableString *h=[NSMutableString string];
   [h appendString:fileComment([propertiesBase stringByAppendingString:@".h"],YES)];
   [h appendFormat:@"#import \"%@\"\n\n\n",
       categoryOnly?classHeaderName(entity)
                   :[NSString stringWithFormat:@"%@+CoreDataClass.h",class]];
   if(categoryOnly && [forwards count]>0)
    [h appendFormat:@"@class %@;\n\n",
        [forwards componentsJoinedByString:@", "]];
   [h appendString:@"NS_ASSUME_NONNULL_BEGIN\n\n"];
   [h appendFormat:@"@interface %@ (CoreDataProperties)\n\n",class];
   /* NS_SWIFT_NAME collides with the inherited class method in Swift
      when the entity has subentities; Xcode omits it there. */
   [h appendFormat:@"+ (NSFetchRequest<%@ *> *)fetchRequest%@;\n\n",class,
       [[entity subentities] count]>0?@"":@" NS_SWIFT_NAME(fetchRequest())"];
   for(NSString *line in propertyLines)
    [h appendFormat:@"%@\n",line];
   [h appendString:@"\n@end\n"];
   if([toMany count]>0){
    [h appendFormat:@"\n@interface %@ (CoreDataGeneratedAccessors)\n\n",class];
    for(NSRelationshipDescription *relationship in toMany){
     appendGeneratedAccessors(h,relationship);
     [h appendString:@"\n"];
    }
    [h appendString:@"@end\n"];
   }
   [h appendString:@"\nNS_ASSUME_NONNULL_END\n"];
   [files setObject:h forKey:[propertiesBase stringByAppendingString:@".h"]];

   NSMutableString *m=[NSMutableString string];
   [m appendString:fileComment([propertiesBase stringByAppendingString:@".m"],YES)];
   [m appendFormat:@"#import \"%@.h\"\n\n",propertiesBase];
   [m appendFormat:@"@implementation %@ (CoreDataProperties)\n\n",class];
   [m appendFormat:@"+ (NSFetchRequest<%@ *> *)fetchRequest {\n",class];
   [m appendFormat:@"\treturn [NSFetchRequest fetchRequestWithEntityName:@\"%@\"];\n",[entity name]];
   [m appendString:@"}\n\n"];
   for(NSPropertyDescription *property in attributes)
    [m appendFormat:@"@dynamic %@;\n",[property name]];
   for(NSPropertyDescription *property in relationships)
    [m appendFormat:@"@dynamic %@;\n",[property name]];
   [m appendString:@"\n@end\n"];
   [files setObject:m forKey:[propertiesBase stringByAppendingString:@".m"]];

   return files;
}

+ (NSArray *)writeSourcesForEntities:(NSArray *)entities
                         toDirectory:(NSString *)directory
                               error:(NSError **)error {
   NSFileManager *fileManager=[NSFileManager defaultManager];

   if(![fileManager createDirectoryAtPath:directory
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:error])
    return nil;

   NSMutableArray *written=[NSMutableArray array];
   for(NSEntityDescription *entity in entities){
    NSDictionary *sources=[self sourcesForEntity:entity];
    for(NSString *filename in
        [[sources allKeys] sortedArrayUsingSelector:@selector(compare:)]){
     NSString *path=[directory stringByAppendingPathComponent:filename];
     if(![[sources objectForKey:filename] writeToFile:path
                                           atomically:YES
                                             encoding:NSUTF8StringEncoding
                                                error:error])
      return nil;
     [written addObject:filename];
    }
   }
   return written;
}

@end
