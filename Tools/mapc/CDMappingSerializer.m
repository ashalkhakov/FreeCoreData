/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDMappingSerializer.h"
#import "CDMappingCompiler.h"
#import <CoreData/CoreData.h>

/* xcmapping.xml is a Core Data XML store of Xcode's own editing objects,
   and its header says which model those objects belong to - Xcode's, whose
   version hashes are below exactly as Xcode writes them.  A file whose
   header said anything else is one Xcode's editor would refuse to open, so
   this is reproduced rather than computed, and is therefore tied to the
   Xcode that wrote it.  The test compiles what is written here with
   Xcode's own mapc, which is the reader its editor uses. */
static NSString *databaseInfoWithUUID(NSString *uuid,NSUInteger nextObjectID){
   NSString *format=
    @"<databaseInfo>\n"
    @"        <version>134481920</version>\n"
    @"        <UUID>%@</UUID>\n"
    @"        <nextObjectID>%@</nextObjectID>\n"
    @"        <metadata>\n"
    @"            <plist version=\"1.0\">\n"
    @"                <dict>\n"
    @"                    <key>NSPersistenceFrameworkVersion</key>\n"
    @"                    <integer>1448</integer>\n"
    @"                    <key>NSStoreModelVersionChecksumKey</key>\n"
    @"                    <string>bMpud663vz0bXQE24C6Rh4MvJ5jVnzsD2sI3njZkKbc=</string>\n"
    @"                    <key>NSStoreModelVersionHashes</key>\n"
    @"                    <dict>\n"
    @"                        <key>XDDevAttributeMapping</key>\n"
    @"                        <data>\n"
    @"		0plcXXRN7XHKl5CcF+fwriFmUpON3ZtcI/AfK748aWc=\n"
    @"		</data>\n"
    @"                        <key>XDDevEntityMapping</key>\n"
    @"                        <data>\n"
    @"		qeN1Ym3TkWN1G6dU9RfX6Kd2ccEvcDVWHpd3LpLgboI=\n"
    @"		</data>\n"
    @"                        <key>XDDevMappingModel</key>\n"
    @"                        <data>\n"
    @"		EqtMzvRnVZWkXwBHu4VeVGy8UyoOe+bi67KC79kphlQ=\n"
    @"		</data>\n"
    @"                        <key>XDDevPropertyMapping</key>\n"
    @"                        <data>\n"
    @"		XN33V44TTGY4JETlMoOB5yyTKxB+u4slvDIinv0rtGA=\n"
    @"		</data>\n"
    @"                        <key>XDDevRelationshipMapping</key>\n"
    @"                        <data>\n"
    @"		akYY9LhehVA/mCb4ATLWuI9XGLcjpm14wWL1oEBtIcs=\n"
    @"		</data>\n"
    @"                    </dict>\n"
    @"                    <key>NSStoreModelVersionHashesDigest</key>\n"
    @"                    <string>+Hmc2uYZK6og+Pvx5GUJ7oW75UG4V/ksQanTjfTKUnxyGWJRMtB5tIRgVwGsrd7lz/QR57++wbvWsr6nxwyS0A==</string>\n"
    @"                    <key>NSStoreModelVersionHashesVersion</key>\n"
    @"                    <integer>3</integer>\n"
    @"                    <key>NSStoreModelVersionIdentifiers</key>\n"
    @"                    <array>\n"
    @"                        <string></string>\n"
    @"                    </array>\n"
    @"                </dict>\n"
    @"            </plist>\n"
    @"        </metadata>\n"
    @"    </databaseInfo>\n";

   return [NSString stringWithFormat:format,uuid,
       [NSString stringWithFormat:@"%lu",(unsigned long)nextObjectID]];
}

static NSString *escaped(NSString *string){
   NSMutableString *result=[NSMutableString stringWithString:(string!=nil)?string:@""];

   [result replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0,[result length])];
   [result replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0,[result length])];
   [result replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0,[result length])];

   return result;
}

@implementation CDMappingSerializer

/* What Xcode puts in a file of its own and this cannot: an archive of each
   model in Xcode's editing form, which is what Apple's mapc compiles
   against - it ignores the recorded paths, where Xcode's editor reads
   them.  A file written over a file that has them keeps them, so a mapping
   model made in Xcode and edited here still compiles there. */
+(NSDictionary *)_carriedOverModelDataAtPath:(NSString *)path {
   NSData *data=[NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"xcmapping.xml"]];

   if(data==nil)
    return nil;

   NSXMLDocument       *document=[[NSXMLDocument alloc] initWithData:data options:0 error:NULL];
   NSMutableDictionary *carried=[NSMutableDictionary dictionary];

   for(NSXMLElement *element in [[document rootElement] elementsForName:@"object"]){
    if(![[[[element attributeForName:@"type"] stringValue] uppercaseString] isEqualToString:@"XDDEVMAPPINGMODEL"])
     continue;

    for(NSXMLElement *child in [element elementsForName:@"attribute"]){
     NSString *name=[[[child attributeForName:@"name"] stringValue] lowercaseString];

     if([name isEqualToString:@"sourcemodeldata"] || [name isEqualToString:@"destinationmodeldata"])
      [carried setObject:[child stringValue]?:@"" forKey:name];
    }
   }

   return ([carried count]>0)?carried:nil;
}

/* The predicate the author wrote, read back out of the expression the
   compiler built from it - FETCH(FUNCTION($manager, "fetchRequest...",
   <entity>, <predicate>), ...).  An expression of any other shape is one
   no editor wrote, and is left alone. */
+(NSString *)_predicateStringOfSourceExpression:(NSExpression *)expression {
   if(expression==nil || [expression expressionType]!=NSFetchRequestExpressionType)
    return nil;

   NSExpression *request=[(NSFetchRequestExpression *)expression requestExpression];

   if([request expressionType]!=NSFunctionExpressionType)
    return nil;
   if(![[request function] isEqualToString:@"fetchRequestForSourceEntityNamed:predicateString:"])
    return nil;

   NSArray *arguments=[request arguments];

   if([arguments count]<2)
    return nil;

   NSExpression *predicate=[arguments objectAtIndex:1];

   if([predicate expressionType]!=NSConstantValueExpressionType)
    return nil;

   NSString *string=[predicate constantValue];

   return [string isKindOfClass:[NSString class]]?string:nil;
}

/* An expression the compiler would have generated anyway is left out, so
   the file says what was chosen rather than what follows from it. */
+(BOOL)_expression:(NSExpression *)expression isGeneratedFor:(NSString *)propertyName {
   if(expression==nil)
    return YES;

   NSString *written=[expression description];

   return [written isEqualToString:[NSString stringWithFormat:@"$source.%@",propertyName]]
       || [written hasPrefix:@"FUNCTION($manager, \"destinationInstancesForEntityMappingNamed:sourceInstances:\""];
}

+(NSString *)_base64OfExpression:(NSExpression *)expression {
   return [[NSKeyedArchiver archivedDataWithRootObject:expression] base64EncodedStringWithOptions:0];
}

+(NSString *)xcmappingXMLForMappingModel:(NSMappingModel *)model
                         sourceModelPath:(NSString *)sourceModelPath
                    destinationModelPath:(NSString *)destinationModelPath
                                   error:(NSError **)error {
   return [self xcmappingXMLForMappingModel:model
                            sourceModelPath:sourceModelPath
                       destinationModelPath:destinationModelPath
                             carriedOverData:nil
                                      error:error];
}

+(NSString *)xcmappingXMLForMappingModel:(NSMappingModel *)model
                         sourceModelPath:(NSString *)sourceModelPath
                    destinationModelPath:(NSString *)destinationModelPath
                         carriedOverData:(NSDictionary *)carried
                                   error:(NSError **)error {
   NSMutableString *xml=[NSMutableString string];
   NSMutableString *objects=[NSMutableString string];
   NSArray         *entityMappings=[model entityMappings];
   NSUInteger       nextIdentifier=100;
   NSString        *modelIdentifier=[NSString stringWithFormat:@"z%lu",(unsigned long)nextIdentifier++];
   NSMutableArray  *entityIdentifiers=[NSMutableArray array];
   NSUInteger       index;

   for(index=0;index<[entityMappings count];index++)
    [entityIdentifiers addObject:[NSString stringWithFormat:@"z%lu",(unsigned long)nextIdentifier++]];

   index=0;
   for(NSEntityMapping *mapping in entityMappings){
    NSString       *identifier=[entityIdentifiers objectAtIndex:index];
    NSMutableArray *attributeIdentifiers=[NSMutableArray array];
    NSMutableArray *relationshipIdentifiers=[NSMutableArray array];
    NSString       *predicate=[self _predicateStringOfSourceExpression:[mapping sourceExpression]];
    NSUInteger      pass;

    for(pass=0;pass<2;pass++){
     BOOL     isRelationship=(pass==1);
     NSArray *properties=isRelationship?[mapping relationshipMappings]:[mapping attributeMappings];

     for(NSPropertyMapping *property in properties){
      NSString *propertyIdentifier=[NSString stringWithFormat:@"z%lu",(unsigned long)nextIdentifier++];
      BOOL      generated=[self _expression:[property valueExpression] isGeneratedFor:[property name]];

      [objects appendFormat:@"    <object type=\"XDDEV%@MAPPING\" id=\"%@\">\n",
          isRelationship?@"RELATIONSHIP":@"ATTRIBUTE",propertyIdentifier];
      [objects appendFormat:@"        <attribute name=\"name\" type=\"string\">%@</attribute>\n",
          escaped([property name])];
      if(generated)
       [objects appendString:@"        <attribute name=\"autogenerateexpression\" type=\"bool\">1</attribute>\n"];
      else
       [objects appendFormat:@"        <attribute name=\"valueexpressiondata\" type=\"binary\">%@</attribute>\n",
           [self _base64OfExpression:[property valueExpression]]];
      [objects appendFormat:@"        <relationship name=\"entitymapping\" type=\"1/1\" destination=\"XDDEVENTITYMAPPING\" idrefs=\"%@\"></relationship>\n",
          identifier];
      [objects appendString:@"    </object>\n"];

      [(isRelationship?relationshipIdentifiers:attributeIdentifiers) addObject:propertyIdentifier];
     }
    }

    [objects appendFormat:@"    <object type=\"XDDEVENTITYMAPPING\" id=\"%@\">\n",identifier];
    if([[mapping sourceEntityName] length]>0)
     [objects appendFormat:@"        <attribute name=\"sourcename\" type=\"string\">%@</attribute>\n",
         escaped([mapping sourceEntityName])];
    if([[mapping destinationEntityName] length]>0)
     [objects appendFormat:@"        <attribute name=\"destinationname\" type=\"string\">%@</attribute>\n",
         escaped([mapping destinationEntityName])];
    if([predicate length]>0 && ![predicate isEqualToString:@"TRUEPREDICATE"])
     [objects appendFormat:@"        <attribute name=\"sourcefilterpredicatestring\" type=\"string\">%@</attribute>\n",
         escaped(predicate)];
    [objects appendString:@"        <attribute name=\"mappingtypename\" type=\"string\">Undefined</attribute>\n"];
    [objects appendFormat:@"        <attribute name=\"mappingnumber\" type=\"int16\">%lu</attribute>\n",
        (unsigned long)(index+1)];
    [objects appendString:@"        <attribute name=\"autogenerateexpression\" type=\"bool\">1</attribute>\n"];
    [objects appendFormat:@"        <relationship name=\"mappingmodel\" type=\"1/1\" destination=\"XDDEVMAPPINGMODEL\" idrefs=\"%@\"></relationship>\n",
        modelIdentifier];
    [objects appendFormat:@"        <relationship name=\"attributemappings\" type=\"0/0\" destination=\"XDDEVATTRIBUTEMAPPING\" idrefs=\"%@\"></relationship>\n",
        [attributeIdentifiers componentsJoinedByString:@" "]];
    [objects appendFormat:@"        <relationship name=\"relationshipmappings\" type=\"0/0\" destination=\"XDDEVRELATIONSHIPMAPPING\" idrefs=\"%@\"></relationship>\n",
        [relationshipIdentifiers componentsJoinedByString:@" "]];
    [objects appendString:@"    </object>\n"];

    index++;
   }

   [objects appendFormat:@"    <object type=\"XDDEVMAPPINGMODEL\" id=\"%@\">\n",modelIdentifier];
   [objects appendFormat:@"        <attribute name=\"sourcemodelpath\" type=\"string\">%@</attribute>\n",
       escaped(sourceModelPath)];
   [objects appendFormat:@"        <attribute name=\"destinationmodelpath\" type=\"string\">%@</attribute>\n",
       escaped(destinationModelPath)];
   for(NSString *name in [[carried allKeys] sortedArrayUsingSelector:@selector(compare:)])
    [objects appendFormat:@"        <attribute name=\"%@\" type=\"binary\">%@</attribute>\n",
        name,[carried objectForKey:name]];
   [objects appendFormat:@"        <relationship name=\"entitymappings\" type=\"0/0\" destination=\"XDDEVENTITYMAPPING\" idrefs=\"%@\"></relationship>\n",
       [entityIdentifiers componentsJoinedByString:@" "]];
   [objects appendString:@"    </object>\n"];

   [xml appendString:@"<?xml version=\"1.0\" standalone=\"yes\"?>\n"];
   [xml appendString:@"<!DOCTYPE database SYSTEM \"file:///System/Library/DTDs/CoreData.dtd\">\n\n"];
   [xml appendString:@"<database>\n"];
   [xml appendString:@"    "];
   [xml appendString:databaseInfoWithUUID([[NSUUID UUID] UUIDString],nextIdentifier)];
   [xml appendString:@"\n"];
   [xml appendString:objects];
   [xml appendString:@"</database>\n"];

   return xml;
}

+(BOOL)writeMappingModel:(NSMappingModel *)model
                  toPath:(NSString *)path
         sourceModelPath:(NSString *)sourceModelPath
    destinationModelPath:(NSString *)destinationModelPath
                   error:(NSError **)error {
   NSString *xml=[self xcmappingXMLForMappingModel:model
                                   sourceModelPath:sourceModelPath
                              destinationModelPath:destinationModelPath
                                   carriedOverData:[self _carriedOverModelDataAtPath:path]
                                             error:error];

   if(xml==nil)
    return NO;

   if(![[NSFileManager defaultManager] createDirectoryAtPath:path
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error])
    return NO;

   return [xml writeToFile:[path stringByAppendingPathComponent:@"xcmapping.xml"]
                atomically:YES
                  encoding:NSUTF8StringEncoding
                     error:error];
}

@end
