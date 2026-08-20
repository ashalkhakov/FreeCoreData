/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSXMLPersistentStore.h"
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSRelationshipDescription.h>
#import <CoreData/NSAttributeDescription.h>
#import "NSAttributeDescription-Private.h"
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectModel.h>
#import <CoreData/NSAtomicStoreCacheNode.h>
#import <Foundation/NSXMLDocument.h>
#import <Foundation/NSXMLElement.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>

/* Apple's XML store writes entity names in uppercase in the `type' and
   `destination' attributes (e.g. type="EMPLOYEE" for an entity named
   "Employee") and property names in lowercase in the `name' attribute
   (e.g. name="hiredate" for an attribute named "hireDate").  Look up
   keys case-insensitively so that files written by Apple's CoreData can
   be loaded, while files written by older versions of this store (which
   used the exact name) keep working. */
static id caseInsensitiveLookup(NSDictionary *dictionary,NSString *name){
   id result=[dictionary objectForKey:name];

   if(result==nil){
    for(NSString *check in dictionary){
     if([check compare:name options:NSCaseInsensitiveSearch]==NSOrderedSame){
      result=[dictionary objectForKey:check];
      break;
     }
    }
   }

   return result;
}

static NSEntityDescription *entityInModelWithName(NSManagedObjectModel *model,NSString *name){
   return caseInsensitiveLookup([model entitiesByName],name);
}

/* The metadata dictionary is stored inside the <metadata> element as an
   XML property list string. */
static NSDictionary *metadataDictionaryFromElement(NSXMLElement *element){
   NSString *plistString=[element stringValue];

   if([plistString length]==0)
    return [NSDictionary dictionary];

   NSData       *plistData=[plistString dataUsingEncoding:NSUTF8StringEncoding];
   NSDictionary *result=[NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:NULL error:NULL];

   if(![result isKindOfClass:[NSDictionary class]])
    return [NSDictionary dictionary];

   return result;
}

@implementation NSXMLPersistentStore

+(NSDictionary *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error {
   NSData   *data=[[NSData alloc] initWithContentsOfURL:url options:0 error:error];
   NSInteger options=NSXMLNodePreserveCharacterReferences|NSXMLNodePreserveWhitespace;

   if([data length]==0){
    [data release];
    return nil;
   }
   
   NSXMLDocument *xml=[[[NSXMLDocument alloc] initWithContentsOfURL:url options:options error:error] autorelease];
   [data release];
   
   if(xml==nil)
    return nil;
   
   NSXMLElement *database=[[xml nodesForXPath:@"database" error:nil] lastObject];
   NSXMLElement *databaseInfo=[[database elementsForName:@"databaseInfo"] lastObject];
   NSXMLElement *uuid=[[databaseInfo elementsForName:@"UUID"] lastObject];
   NSXMLElement *metadataElement=[[databaseInfo elementsForName:@"metadata"] lastObject];

   NSMutableDictionary *result=[NSMutableDictionary dictionary];

   [result addEntriesFromDictionary:metadataDictionaryFromElement(metadataElement)];
   if([uuid stringValue]!=nil)
    [result setObject:[uuid stringValue] forKey:NSStoreUUIDKey];
   [result setObject:NSXMLStoreType forKey:NSStoreTypeKey];

   return result;
}

-(NSString *)type {
   return NSXMLStoreType;
}

-(NSXMLElement *)databaseElement {
   return [[_document nodesForXPath:@"database" error:nil] lastObject];
}

-(NSXMLElement *)databaseInfoElement {
   return [[[self databaseElement] elementsForName:@"databaseInfo"] lastObject];
}

-(NSXMLElement *)metadataElement {
   NSXMLElement *result=[[[self databaseInfoElement] elementsForName:@"metadata"] lastObject];

   /* Older files stored the metadata element directly under database. */
   if(result==nil)
    result=[[[self databaseElement] elementsForName:@"metadata"] lastObject];

   return result;
}
 
-(NSXMLElement *)identifierElement {
   return [[[self databaseInfoElement] elementsForName:@"UUID"] lastObject];
}

-(NSXMLElement *)nextObjectIDElement {
   return [[[self databaseInfoElement] elementsForName:@"nextObjectID"] lastObject];
}

-initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator configurationName:(NSString *)configurationName URL:(NSURL *)url options:(NSDictionary *)options {
   if([super initWithPersistentStoreCoordinator:coordinator configurationName:configurationName URL:url options:options]==nil)
    return nil;

   NSData   *data=[[NSData alloc] initWithContentsOfURL:[self URL] options:0 error:NULL];
   NSInteger xmlOptions=NSXMLNodePreserveCharacterReferences | NSXMLNodePreserveWhitespace;

   if([data length]!=0){   
    if((_document=[[NSXMLDocument alloc] initWithData:data options:xmlOptions error:NULL])==nil){
     [data release];
     [self release];
     return nil;
     }
   }
   else {
    NSXMLElement *database=[[NSXMLElement alloc] initWithName:@"database"];
    NSXMLElement *databaseInfo=[[NSXMLElement alloc] initWithName:@"databaseInfo"];
    NSXMLElement *versionElement=[[NSXMLElement alloc] initWithName:@"version" stringValue:@"1"];
    NSXMLElement *uuidElement=[[NSXMLElement alloc] initWithName:@"UUID" stringValue:[self identifier]];
    NSXMLElement *nextObjectID=[[NSXMLElement alloc] initWithName:@"nextObjectID" stringValue:@"1"];
    NSXMLElement *metadata=[[NSXMLElement alloc] initWithName:@"metadata"];

    _document=[[NSXMLDocument alloc] initWithRootElement:database];

    [database addChild:databaseInfo];
    [databaseInfo addChild:versionElement];
    [databaseInfo addChild:uuidElement];
    [databaseInfo addChild:nextObjectID];
    [databaseInfo addChild:metadata];
    
    [metadata release];
    [nextObjectID release];
    [uuidElement release];
    [versionElement release];
    [databaseInfo release];
    [database release];
   }

   [data release];
   
   [super setIdentifier:[[self identifierElement] stringValue]];

   NSMutableDictionary *initialMetadata=[NSMutableDictionary dictionaryWithDictionary:metadataDictionaryFromElement([self metadataElement])];

   [initialMetadata setObject:[self identifier] forKey:NSStoreUUIDKey];
   [initialMetadata setObject:[self type] forKey:NSStoreTypeKey];
   [self setMetadata:initialMetadata];

   _referenceToCacheNode=[[NSMutableDictionary alloc] init];
   _referenceToElement=[[NSMutableDictionary alloc] init];
   _usedReferences=[[NSMutableSet alloc] init];
      
   return self;
}

-(void)dealloc {
   [_document release];
   [_referenceToCacheNode release];
   [_referenceToElement release];
   [_usedReferences release];
   [super dealloc];
}


-(void)setIdentifier:(NSString *)identifier {
   [super setIdentifier:identifier];
   [[self identifierElement] setStringValue:identifier];
}

-(NSAtomicStoreCacheNode *)cacheNodeForEntity:(NSEntityDescription *)entity referenceObject:reference {
   NSAtomicStoreCacheNode *result=[_referenceToCacheNode objectForKey:reference];
    
   if(result==nil){
    NSManagedObjectID *objectID=[self objectIDForEntity:entity referenceObject:reference];
    
    result=[[NSAtomicStoreCacheNode alloc] initWithObjectID:objectID];

    [_referenceToCacheNode setObject:result forKey:reference];
    
    [result release];
   }
    
   return result;
}
  
-(NSAtomicStoreCacheNode *)loadEntityElement:(NSXMLElement *)entityElement model:(NSManagedObjectModel *)model {
   NSString  *entityName=[[entityElement attributeForName:@"type"] stringValue];
   NSString  *entityReference=[[entityElement attributeForName:@"id"] stringValue];
   NSArray   *attributeElements=[entityElement elementsForName:@"attribute"];
   NSArray   *relationshipElements=[entityElement elementsForName:@"relationship"];

   NSEntityDescription *entity=entityInModelWithName(model,entityName);

   if(entity==nil){
    NSLog(@"Unable to find entity %@ in model",entityName);
    return nil;
   }
   
   [_referenceToElement setObject:entityElement forKey:entityReference];

   NSAtomicStoreCacheNode *cacheNode=[self cacheNodeForEntity:entity referenceObject:entityReference];

   NSDictionary *attributesByName=[entity attributesByName];
   
   for(NSXMLElement *attribute in attributeElements){
    NSString               *name=[[attribute attributeForName:@"name"] stringValue];
    NSAttributeDescription *description=caseInsensitiveLookup(attributesByName,name);

    if(description==nil){
     NSLog(@"Unable to find attribute named %@ for entity named %@",name,entityName);
     continue;
    }

    /* Use the model's spelling of the name; Apple writes it lowercased. */
    name=[description name];

    NSString *stringValue=[attribute stringValue];
    id        objectValue=nil;

    switch([description attributeType]){
    
     case NSUndefinedAttributeType:
      NSLog(@"Unhandled attribute type NSUndefinedAttributeType");
      break;
      
     case NSInteger16AttributeType:
      objectValue=[NSNumber numberWithInteger:[stringValue integerValue]];
      break;
      
     case NSInteger32AttributeType:
      objectValue=[NSNumber numberWithInteger:[stringValue integerValue]];
      break;
      
     case NSInteger64AttributeType:
      objectValue=[NSNumber numberWithInteger:[stringValue integerValue]];
      break;
      
     case NSDecimalAttributeType:
      objectValue=[NSNumber numberWithDouble:[stringValue doubleValue]];
      break;
      
     case NSDoubleAttributeType:
      objectValue=[NSNumber numberWithDouble:[stringValue doubleValue]];
      break;
      
     case NSFloatAttributeType:
      objectValue=[NSNumber numberWithFloat:[stringValue floatValue]];
      break;
      
     case NSStringAttributeType:
      objectValue=stringValue;
      break;
      
     case NSBooleanAttributeType:
      objectValue=[NSNumber numberWithBool:[stringValue intValue]];
      break;
      
     case NSDateAttributeType:
      /* Apple stores dates as seconds since the reference date. */
      objectValue=[NSDate dateWithTimeIntervalSinceReferenceDate:[stringValue doubleValue]];
      break;
      
     case NSBinaryDataAttributeType:
      /* Binary values are stored base64-encoded in the element text. */
      objectValue=[[[NSData alloc] initWithBase64EncodedString:stringValue options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
      break;

     case NSTransformableAttributeType: {
      /* Transformable values are stored as the base64-encoded output of
         the attribute's value transformer (or the keyed-archiving
         default); see NSAttributeDescription. */
      NSData *data=[[[NSData alloc] initWithBase64EncodedString:stringValue options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];

      objectValue=[description _transformableValueFromData:data];
      break;
     }

    }

    if(objectValue!=nil)
     [cacheNode setValue:objectValue forKey:name];
   }
   
   NSDictionary *relationshipsByName=[entity relationshipsByName];

   for(NSXMLElement *relationship in relationshipElements){
    NSString                  *name=[[relationship attributeForName:@"name"] stringValue];
    NSRelationshipDescription *description=caseInsensitiveLookup(relationshipsByName,name);
    
    if(description==nil){
     NSLog(@"No description for relationship name %@ in %@",name,entityName);
     continue;
    }
    
    /* Use the model's spelling of the name; Apple writes it lowercased. */
    name=[description name];
    
    NSString            *destinationEntityName=[[relationship attributeForName:@"destination"] stringValue];
    NSEntityDescription *destinationEntity=entityInModelWithName(model,destinationEntityName);
    NSString            *idrefsString=[[relationship attributeForName:@"idrefs"] stringValue];
    NSArray             *idrefs=[idrefsString length]?[idrefsString componentsSeparatedByString:@" "]:nil;
    id                   objectValue=[NSMutableSet set];
        
    for(NSString *ref in idrefs){     
     NSAtomicStoreCacheNode *relCacheNode=[self cacheNodeForEntity:destinationEntity referenceObject:ref];

     [objectValue addObject:relCacheNode];
    }
    
    if(![description isToMany]){
    
     if([objectValue count]>1){
      NSLog(@"relationship description is not to many, but destination count is %lu (unsigned)",(unsigned long)[objectValue count]);
     }
     
     objectValue=[objectValue anyObject];
    }

    [cacheNode setValue:objectValue forKey:name];
   }
    
   return cacheNode;
}

- (BOOL)load:(NSError **)errorp {
   NSManagedObjectModel *model=[[self persistentStoreCoordinator] managedObjectModel];

   NSXMLElement *database=[self databaseElement];
   NSArray      *objects=[database elementsForName:@"object"];
   NSInteger     i,count=[objects count];
   NSMutableSet *newNodes=[NSMutableSet set];
   
   for(i=0;i<count;i++){
    NSXMLElement *element=[objects objectAtIndex:i];
    NSAtomicStoreCacheNode *node=[self loadEntityElement:element model:model];
    
    if(node!=nil)
     [newNodes addObject:node];
   }
   
   [self addCacheNodes:newNodes];
   
   return YES;
}
 
 
- (BOOL)save:(NSError **)error {
    NSXMLElement *metadataElement=[self metadataElement];

    if(metadataElement==nil){
     metadataElement=[[[NSXMLElement alloc] initWithName:@"metadata"] autorelease];
     [[self databaseInfoElement] addChild:metadataElement];
    }

    NSData *plistData=[NSPropertyListSerialization dataWithPropertyList:[self metadata] format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];

    if(plistData!=nil)
     [metadataElement setStringValue:[[[NSString alloc] initWithData:plistData encoding:NSUTF8StringEncoding] autorelease]];

    NSData *data=[_document XMLData];

    return [data writeToURL:[self URL] atomically:YES];
}
 
-(NSXMLElement *)entityElementForObjectID:(NSManagedObjectID *)objectID {
   id reference=[self referenceObjectForObjectID:objectID];
   
   return [_referenceToElement objectForKey:reference];
}

-(void)updateCacheNode:(NSAtomicStoreCacheNode *)node fromManagedObject:(NSManagedObject *)managedObject {
   NSXMLElement   *entityElement=[self entityElementForObjectID:[managedObject objectID]];
   NSDictionary   *attributesByName=[[managedObject entity] attributesByName];
   NSArray        *attributeKeys=[attributesByName allKeys];
   NSMutableArray *children=[NSMutableArray array];

   for(NSString *attributeName in attributeKeys){
    NSAttributeDescription *attributeDescription=[attributesByName objectForKey:attributeName];
    NSXMLElement           *attributeElement=[NSXMLNode elementWithName:@"attribute"];
    id                      value=[managedObject primitiveValueForKey:attributeName];
    NSString               *type=nil;
    NSString               *stringValue=nil;
        
    switch([attributeDescription attributeType]){
     case NSUndefinedAttributeType:
      NSLog(@"Unhandled attribute type NSUndefinedAttributeType");
      break;
      
     case NSInteger16AttributeType:
      type=@"int16";
      stringValue=[value description];
      break;
      
     case NSInteger32AttributeType:
      type=@"int32";
      stringValue=[value description];
      break;
      
     case NSInteger64AttributeType:
      type=@"int64";
      stringValue=[value description];
      break;
      
     case NSDecimalAttributeType:
      type=@"decimal";
      stringValue=[value description];
      break;
      
     case NSDoubleAttributeType:
      type=@"double";
      stringValue=[value description];
      break;
      
     case NSFloatAttributeType:
      type=@"float";
      stringValue=[value description];
      break;
      
     case NSStringAttributeType:
      type=@"string";
      stringValue=[value description];
      break;
      
     case NSBooleanAttributeType:
      type=@"bool";
      stringValue=[value description];
      break;
      
     case NSDateAttributeType:
      type=@"date";
      /* Apple stores dates as seconds since the reference date, printed
         with 20 fractional digits. */
      if(value!=nil)
       stringValue=[NSString stringWithFormat:@"%.20f",[value timeIntervalSinceReferenceDate]];
      break;
      
     case NSBinaryDataAttributeType:
      type=@"bin";
      if(value!=nil)
       stringValue=[value base64EncodedStringWithOptions:0];
      break;

     case NSTransformableAttributeType:
      type=@"transformable";
      if(value!=nil)
       stringValue=[[attributeDescription _dataFromTransformableValue:value] base64EncodedStringWithOptions:0];
      break;

    }
    
    /* Apple omits attribute elements for nil values and lowercases names. */
    if(stringValue!=nil){
     [attributeElement setStringValue:stringValue];
     [attributeElement addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:[attributeName lowercaseString]]];
     [attributeElement addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:type]];

     [children addObject:attributeElement];
    }
    
    [node setValue:value forKey:attributeName];
   }

   NSDictionary *relationshipsByName=[[managedObject entity] relationshipsByName];
   NSArray      *relationshipKeys=[relationshipsByName allKeys];

   for(NSString *relationshipName in relationshipKeys){
    NSRelationshipDescription *relationshipDescription=[relationshipsByName objectForKey:relationshipName];
    NSXMLElement              *relationshipElement=[NSXMLNode elementWithName:@"relationship"];
    NSString                  *relationshipType=[NSString stringWithFormat:@"%d/%d",[relationshipDescription minCount],[relationshipDescription maxCount]];
    NSEntityDescription       *destinationEntity=[relationshipDescription destinationEntity];
    id                         value=[managedObject primitiveValueForKey:relationshipName];
    NSSet                     *valueSet;
    NSMutableSet              *cacheNodeSet=[NSMutableSet set];
    
    if([relationshipDescription isToMany]){
     if(value!=nil && ![value isKindOfClass:[NSSet class]]){
      NSLog(@"relationship isToMany, value is not a set");
      continue;
     }
     valueSet=value;
    }
    else {
     if(value==nil){
      valueSet=[NSSet set];
     } else {
      valueSet=[NSSet setWithObject:value];
     }
    }
    
    /* Apple lowercases relationship names in the file. */
    [relationshipElement addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:[relationshipName lowercaseString]]];
    [relationshipElement addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:relationshipType]];
    [relationshipElement addAttribute:[NSXMLNode attributeWithName:@"destination" stringValue:[[destinationEntity name] uppercaseString]]];
    
    NSMutableArray *idrefArray=[NSMutableArray array];

    for(NSManagedObjectID *objectID in valueSet){
     id referenceObject=[self referenceObjectForObjectID:objectID];
     
     [idrefArray addObject:referenceObject];
     
     NSAtomicStoreCacheNode *relNode=[self cacheNodeForEntity:destinationEntity referenceObject:referenceObject];

     [cacheNodeSet addObject:relNode];
    }

    /* Apple omits the idrefs attribute entirely when the relationship
       has no destinations. */
    if([idrefArray count]>0)
     [relationshipElement addAttribute:[NSXMLNode attributeWithName:@"idrefs" stringValue:[idrefArray componentsJoinedByString:@" "]]];

    [children addObject:relationshipElement];

    if([relationshipDescription isToMany]){
     [node setValue:cacheNodeSet forKey:relationshipName];
    }
    else {
     if([cacheNodeSet count]>1){
      NSLog(@"relationship is one to one, yet cacheNodeSet count is %lu (unsigned)",(unsigned long)[cacheNodeSet count]);
      continue;
     }
     
     if([cacheNodeSet count]==0)
      [node setValue:nil forKey:relationshipName];
     else
      [node setValue:[cacheNodeSet anyObject] forKey:relationshipName];
    }
   }
   
   [entityElement setChildren:children];
}
 
-(NSAtomicStoreCacheNode *)newCacheNodeForManagedObject:(NSManagedObject *)managedObject {
   NSEntityDescription    *entity=[managedObject entity];
   NSManagedObjectID      *objectID=[managedObject objectID];
   id                      reference=[self referenceObjectForObjectID:objectID];
   NSAtomicStoreCacheNode *cacheNode=[[NSAtomicStoreCacheNode alloc] initWithObjectID:objectID];
   
   NSXMLElement           *entityElement=[[NSXMLElement alloc] initWithName:@"object"];
   NSXMLNode              *nameAttribute=[NSXMLNode attributeWithName:@"type" stringValue:[[entity name] uppercaseString]];
   NSXMLNode              *idAttribute=[NSXMLNode attributeWithName:@"id" stringValue:reference];
   
   [entityElement addAttribute:nameAttribute];
   [entityElement addAttribute:idAttribute];
   
   [_referenceToElement setObject:entityElement forKey:reference];
   [entityElement release];

   [[self databaseElement] addChild:[_referenceToElement objectForKey:reference]];
   
   [self updateCacheNode:cacheNode fromManagedObject:managedObject];

   return cacheNode;
}

-newReferenceObjectForManagedObject:(NSManagedObject *)managedObject {
   NSXMLElement *nextObjectIDElement=[self nextObjectIDElement];
   NSInteger     nextInteger=[[nextObjectIDElement stringValue] integerValue];
   NSNumber     *check;

   do{
    check=[NSNumber numberWithInteger:nextInteger];
    
    if(![_usedReferences containsObject:check])
     break;
     
    nextInteger++;
     
   }while(YES);
   
   [_usedReferences addObject:check];

   [nextObjectIDElement setStringValue:[NSString stringWithFormat:@"%ld",(long)(nextInteger+1)]];
   
   return [[NSString alloc] initWithFormat:@"z%ld",(long)nextInteger];
}

-(void)willRemoveCacheNodes:(NSSet *)cacheNodes {
   NSXMLElement *database=[self databaseElement];

   for (NSAtomicStoreCacheNode *node in cacheNodes) {
    NSManagedObjectID   *objectID=[node objectID];
    NSXMLElement        *entityElement=[self entityElementForObjectID:objectID];
    id                   entityReference=[self referenceObjectForObjectID:objectID];
    NSInteger            index=[[database children] indexOfObjectIdenticalTo:entityElement];
    
    if(index==NSNotFound)
     NSLog(@"unable to remove object %@ from database - not found",objectID);
    else
     [[self databaseElement] removeChildAtIndex:index];
    
    [_referenceToElement removeObjectForKey:entityReference];

    [_cacheNodes removeObject:node];
   }
}
 
 
-(void)willRemoveFromPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator {
   [_document release];
   _document = nil;
   [super willRemoveFromPersistentStoreCoordinator:coordinator];
}
 
@end
