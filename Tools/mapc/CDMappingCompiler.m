/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDMappingCompiler.h"
#import <CoreData/CoreData.h>
#import "CDModelCompiler.h"

NSString * const CDMappingCompilerErrorDomain=@"CDMappingCompilerErrorDomain";
NSString * const CDMappingSourceModelKey=@"CDMappingSourceModel";
NSString * const CDMappingDestinationModelKey=@"CDMappingDestinationModel";
NSString * const CDMappingSourceModelPathKey=@"CDMappingSourceModelPath";
NSString * const CDMappingDestinationModelPathKey=@"CDMappingDestinationModelPath";

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

static NSError *compilerError(NSString *format,...){
   va_list arguments;
   va_start(arguments,format);
   NSString *message=[[NSString alloc] initWithFormat:format arguments:arguments];
   va_end(arguments);

   return [NSError errorWithDomain:CDMappingCompilerErrorDomain
                              code:1
                          userInfo:[NSDictionary dictionaryWithObject:message
                                                               forKey:NSLocalizedDescriptionKey]];
}

/* ------------------------------------------------------------------ */
#pragma mark - The source
/* ------------------------------------------------------------------ */

/* An .xcmappingmodel holds an xcmapping.xml: a Core Data XML store of
   Xcode's own editing objects - one XDDEVMAPPINGMODEL carrying an archived
   copy of each model, an XDDEVENTITYMAPPING for each mapping, and an
   XDDEVATTRIBUTEMAPPING or XDDEVRELATIONSHIPMAPPING for each property one
   fills.  Those objects belong to a model of Xcode's, not one of ours, so
   the file is read as the XML it is rather than opened as a store. */
@interface CDMappingSourceObject : NSObject
{
   @public
   NSString            *_kind;
   NSMutableDictionary *_attributes;
   NSMutableDictionary *_relationships;
}
@end

@implementation CDMappingSourceObject

-(id)init {
   if((self=[super init])==nil)
    return nil;

   _attributes=[[NSMutableDictionary alloc] init];
   _relationships=[[NSMutableDictionary alloc] init];

   return self;
}

-(NSString *)string:(NSString *)name {
   id value=[_attributes objectForKey:name];

   return [value isKindOfClass:[NSString class]]?value:nil;
}

-(NSData *)data:(NSString *)name {
   NSString *encoded=[self string:name];

   if(encoded==nil)
    return nil;

   return [[NSData alloc] initWithBase64EncodedString:encoded
                                              options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

-(NSArray *)references:(NSString *)name {
   return [_relationships objectForKey:name];
}

@end

@implementation CDMappingCompiler

+(void)setWarningHandler:(void (^)(NSString *message))handler {
   warningHandler=[handler copy];
}

/* Every object in the file, by the identifier the file gives it. */
+(NSDictionary *)_sourceObjectsAtPath:(NSString *)path error:(NSError **)error {
   NSString *xmlPath=path;
   BOOL      isDirectory=NO;

   if([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory)
    xmlPath=[path stringByAppendingPathComponent:@"xcmapping.xml"];

   NSData *data=[NSData dataWithContentsOfFile:xmlPath];

   if(data==nil){
    if(error!=NULL)
     *error=compilerError(@"cannot read %@",xmlPath);
    return nil;
   }

   NSError       *xmlError=nil;
   NSXMLDocument *document=[[NSXMLDocument alloc] initWithData:data options:0 error:&xmlError];

   if(document==nil){
    if(error!=NULL)
     *error=compilerError(@"%@ is not XML: %@",xmlPath,[xmlError localizedDescription]);
    return nil;
   }

   NSMutableDictionary *objects=[NSMutableDictionary dictionary];

   for(NSXMLElement *element in [[document rootElement] elementsForName:@"object"]){
    CDMappingSourceObject *object=[[CDMappingSourceObject alloc] init];
    NSString              *identifier=[[element attributeForName:@"id"] stringValue];

    object->_kind=[[[element attributeForName:@"type"] stringValue] uppercaseString];

    for(NSXMLElement *child in [element elementsForName:@"attribute"]){
     NSString *name=[[[child attributeForName:@"name"] stringValue] lowercaseString];

     if(name!=nil)
      [object->_attributes setObject:[child stringValue]?:@"" forKey:name];
    }

    for(NSXMLElement *child in [element elementsForName:@"relationship"]){
     NSString *name=[[[child attributeForName:@"name"] stringValue] lowercaseString];
     NSString *refs=[[child attributeForName:@"idrefs"] stringValue];

     if(name!=nil && [refs length]>0)
      [object->_relationships setObject:[refs componentsSeparatedByString:@" "] forKey:name];
    }

    if(identifier!=nil)
     [objects setObject:object forKey:identifier];
   }

   if([objects count]==0){
    if(error!=NULL)
     *error=compilerError(@"%@ holds no mapping",xmlPath);
    return nil;
   }

   return objects;
}

/* ------------------------------------------------------------------ */
#pragma mark - The expressions a mapping model is made of
/* ------------------------------------------------------------------ */

/* Which objects a mapping applies to: the request this manager builds for
   one entity, narrowed by the author's predicate, run against the context
   the migration reads from. */
+(NSExpression *)sourceExpressionForEntityNamed:(NSString *)entityName predicate:(NSString *)predicateString {
   NSArray *arguments=[NSArray arrayWithObjects:
       [NSExpression expressionForConstantValue:entityName],
       [NSExpression expressionForConstantValue:([predicateString length]>0)?predicateString:@"TRUEPREDICATE"],
       nil];
   NSExpression *request=[NSExpression expressionForFunction:[NSExpression expressionForVariable:@"manager"]
                                                selectorName:@"fetchRequestForSourceEntityNamed:predicateString:"
                                                   arguments:arguments];

   return [NSFetchRequestExpression expressionForFetch:request
                                               context:[NSExpression expressionWithFormat:@"$manager.sourceContext"]
                                             countOnly:NO];
}

/* What fills an attribute the author did not write an expression for: the
   source object's property of the same name. */
+(NSExpression *)_valueExpressionForSourceProperty:(NSString *)name {
   return [NSExpression expressionWithFormat:[NSString stringWithFormat:@"$source.%@",name]];
}

/* And a relationship: the destination objects of whatever the source
   object was related to, which only the manager can say. */
+(NSExpression *)valueExpressionForRelationshipKeyPath:(NSString *)keyPath throughMapping:(NSString *)mappingName {
   NSArray *arguments=[NSArray arrayWithObjects:
       [NSExpression expressionForConstantValue:mappingName],
       [self _valueExpressionForSourceProperty:keyPath],
       nil];

   return [NSExpression expressionForFunction:[NSExpression expressionForVariable:@"manager"]
                                 selectorName:@"destinationInstancesForEntityMappingNamed:sourceInstances:"
                                    arguments:arguments];
}

+(NSString *)defaultNameForEntityMappingFromEntityNamed:(NSString *)sourceName toEntityNamed:(NSString *)destinationName {
   if([sourceName length]>0 && [destinationName length]>0)
    return [NSString stringWithFormat:@"%@To%@",sourceName,destinationName];

   return ([destinationName length]>0)?destinationName:sourceName;
}

/* What Xcode archives into a file - an expression, a user info dictionary -
   is a keyed archive with the object at its root. */
+(id)_unarchivedObjectOfClass:(Class)cls fromData:(NSData *)data {
   if(data==nil)
    return nil;

   [NSPredicate class];
   [NSExpression class];

   id object=nil;

   @try {
    NSKeyedUnarchiver *unarchiver=[[NSKeyedUnarchiver alloc] initForReadingWithData:data];

    object=[unarchiver decodeObjectForKey:@"root"];
   }
   @catch(NSException *exception){
    object=nil;
   }

   return [object isKindOfClass:cls]?object:nil;
}

/* ------------------------------------------------------------------ */
#pragma mark - Compiling
/* ------------------------------------------------------------------ */

/* The source names the two models it maps between by path.  (It also
   carries a copy of each, but in Xcode's own editing form - XDPMModel and
   its kin - which is no use here.)  A path is as the project recorded it,
   so it is tried as given and then against the directories above the
   mapping model, which is where a project keeps its models. */
+(NSManagedObjectModel *)_modelAtRecordedPath:(NSString *)recorded relativeTo:(NSString *)mappingPath {
   if([recorded length]==0)
    return nil;

   NSFileManager  *fileManager=[NSFileManager defaultManager];
   NSMutableArray *candidates=[NSMutableArray arrayWithObject:recorded];
   NSString       *directory=[mappingPath stringByDeletingLastPathComponent];

   while([directory length]>0 && ![directory isEqualToString:@"/"]){
    [candidates addObject:[directory stringByAppendingPathComponent:recorded]];
    [candidates addObject:[directory stringByAppendingPathComponent:[recorded lastPathComponent]]];
    directory=[directory stringByDeletingLastPathComponent];
   }

   for(NSString *candidate in candidates){
    if(![fileManager fileExistsAtPath:candidate])
     continue;

    NSError              *modelError=nil;
    NSManagedObjectModel *model=[CDModelCompiler compileModelAtPath:candidate error:&modelError];

    if(model!=nil)
     return model;

    warnf(@"%@: %@",candidate,[modelError localizedDescription]);
   }

   return nil;
}

+(NSMappingModel *)mappingModelAtPath:(NSString *)path error:(NSError **)error {
   NSDictionary          *objects=[self _sourceObjectsAtPath:path error:error];
   CDMappingSourceObject *root=(objects!=nil)?[self _rootOf:objects]:nil;

   if(root==nil){
    if(objects!=nil && error!=NULL)
     *error=compilerError(@"%@ holds no mapping model",path);
    return nil;
   }

   NSManagedObjectModel *sourceModel=[self _modelAtRecordedPath:[root string:@"sourcemodelpath"] relativeTo:path];
   NSManagedObjectModel *destinationModel=[self _modelAtRecordedPath:[root string:@"destinationmodelpath"] relativeTo:path];

   if(sourceModel==nil || destinationModel==nil){
    if(error!=NULL)
     *error=compilerError(@"cannot read the models %@ maps between (%@ and %@)",
                          [path lastPathComponent],
                          [root string:@"sourcemodelpath"],[root string:@"destinationmodelpath"]);
    return nil;
   }

   return [self mappingModelAtPath:path
                       sourceModel:sourceModel
                  destinationModel:destinationModel
                             error:error];
}

+(NSDictionary *)modelsForMappingModelAtPath:(NSString *)path error:(NSError **)error {
   NSDictionary          *objects=[self _sourceObjectsAtPath:path error:error];
   CDMappingSourceObject *root=(objects!=nil)?[self _rootOf:objects]:nil;

   if(root==nil){
    if(objects!=nil && error!=NULL)
     *error=compilerError(@"%@ holds no mapping model",path);
    return nil;
   }

   NSString             *sourcePath=[root string:@"sourcemodelpath"];
   NSString             *destinationPath=[root string:@"destinationmodelpath"];
   NSManagedObjectModel *sourceModel=[self _modelAtRecordedPath:sourcePath relativeTo:path];
   NSManagedObjectModel *destinationModel=[self _modelAtRecordedPath:destinationPath relativeTo:path];
   NSMutableDictionary  *result=[NSMutableDictionary dictionary];

   if(sourceModel!=nil)
    [result setObject:sourceModel forKey:CDMappingSourceModelKey];
   if(destinationModel!=nil)
    [result setObject:destinationModel forKey:CDMappingDestinationModelKey];
   if(sourcePath!=nil)
    [result setObject:sourcePath forKey:CDMappingSourceModelPathKey];
   if(destinationPath!=nil)
    [result setObject:destinationPath forKey:CDMappingDestinationModelPathKey];

   if(sourceModel==nil || destinationModel==nil){
    if(error!=NULL)
     *error=compilerError(@"cannot read the models %@ maps between (%@ and %@)",
                          [path lastPathComponent],sourcePath,destinationPath);
   }

   return result;
}

+(CDMappingSourceObject *)_rootOf:(NSDictionary *)objects {
   for(CDMappingSourceObject *object in [objects allValues])
    if([object->_kind isEqualToString:@"XDDEVMAPPINGMODEL"])
     return object;

   return nil;
}

+(NSMappingModel *)mappingModelAtPath:(NSString *)path
                          sourceModel:(NSManagedObjectModel *)sourceModel
                     destinationModel:(NSManagedObjectModel *)destinationModel
                                error:(NSError **)error {
   NSDictionary          *objects=[self _sourceObjectsAtPath:path error:error];
   CDMappingSourceObject *root=(objects!=nil)?[self _rootOf:objects]:nil;

   if(root==nil){
    if(objects!=nil && error!=NULL)
     *error=compilerError(@"%@ holds no mapping model",path);
    return nil;
   }
   if(sourceModel==nil || destinationModel==nil){
    if(error!=NULL)
     *error=compilerError(@"a mapping model is compiled against two models");
    return nil;
   }

   /* In the order the author put them in. */
   NSMutableArray *sourceMappings=[NSMutableArray array];

   for(NSString *identifier in [root references:@"entitymappings"]){
    CDMappingSourceObject *object=[objects objectForKey:identifier];

    if(object!=nil)
     [sourceMappings addObject:object];
   }
   [sourceMappings sortUsingComparator:^NSComparisonResult(id a,id b){
     return [[a string:@"mappingnumber"] compare:[b string:@"mappingnumber"] options:NSNumericSearch];
    }];

   /* The name each mapping will be known by, needed before the mappings
      are built: a relationship mapping names the mapping that carries its
      destination entity over. */
   NSMutableDictionary *namesByDestinationEntity=[NSMutableDictionary dictionary];
   NSMutableArray      *names=[NSMutableArray array];

   for(CDMappingSourceObject *object in sourceMappings){
    NSString *sourceName=[object string:@"sourcename"];
    NSString *destinationName=[object string:@"destinationname"];
    NSString *name=[object string:@"name"];

    if([name length]==0)
     name=[self defaultNameForEntityMappingFromEntityNamed:sourceName toEntityNamed:destinationName];

    [names addObject:name?:@""];
    if([destinationName length]>0 && [namesByDestinationEntity objectForKey:destinationName]==nil)
     [namesByDestinationEntity setObject:name forKey:destinationName];
   }

   NSMutableArray *entityMappings=[NSMutableArray array];
   NSUInteger      index=0;

   for(CDMappingSourceObject *object in sourceMappings){
    NSString            *sourceName=[object string:@"sourcename"];
    NSString            *destinationName=[object string:@"destinationname"];
    NSEntityDescription *sourceEntity=([sourceName length]>0)?[[sourceModel entitiesByName] objectForKey:sourceName]:nil;
    NSEntityDescription *destinationEntity=([destinationName length]>0)?[[destinationModel entitiesByName] objectForKey:destinationName]:nil;
    NSEntityMapping     *mapping=[[NSEntityMapping alloc] init];

    if([sourceName length]>0 && sourceEntity==nil)
     warnf(@"%@: the source model has no entity named %@",[names objectAtIndex:index],sourceName);
    if([destinationName length]>0 && destinationEntity==nil)
     warnf(@"%@: the destination model has no entity named %@",[names objectAtIndex:index],destinationName);

    [mapping setName:[names objectAtIndex:index]];
    [mapping setSourceEntityName:sourceName];
    [mapping setDestinationEntityName:destinationName];
    [mapping setSourceEntityVersionHash:[sourceEntity versionHash]];
    [mapping setDestinationEntityVersionHash:[destinationEntity versionHash]];

    /* The kind of mapping is not the author's to choose: an entity with no
       source is added, one with no destination is removed, and one with
       both is copied where the two versions agree and transformed where
       they do not. */
    if(sourceEntity==nil)
     [mapping setMappingType:NSAddEntityMappingType];
    else if(destinationEntity==nil)
     [mapping setMappingType:NSRemoveEntityMappingType];
    else if([[sourceEntity versionHash] isEqual:[destinationEntity versionHash]])
     [mapping setMappingType:NSCopyEntityMappingType];
    else
     [mapping setMappingType:NSTransformEntityMappingType];

    /* Which objects it applies to: the default fetch, narrowed by the
       author's predicate, unless the author wrote a fetch of their own. */
    NSExpression *customFetch=[[object string:@"autogenerateexpression"] boolValue]?nil:
        [self _unarchivedObjectOfClass:[NSExpression class] fromData:[object data:@"sourceexpressiondata"]];

    if(customFetch!=nil)
     [mapping setSourceExpression:customFetch];
    else if(sourceEntity!=nil)
     [mapping setSourceExpression:[self sourceExpressionForEntityNamed:sourceName
                                                              predicate:[object string:@"sourcefilterpredicatestring"]]];

    if([[object string:@"migrationpolicyclassname"] length]>0)
     [mapping setEntityMigrationPolicyClassName:[object string:@"migrationpolicyclassname"]];
    [mapping setUserInfo:[self _unarchivedObjectOfClass:[NSDictionary class] fromData:[object data:@"userinfodata"]]];

    NSMutableArray *attributeMappings=[NSMutableArray array];
    NSMutableArray *relationshipMappings=[NSMutableArray array];

    for(NSString *key in [NSArray arrayWithObjects:@"attributemappings",@"relationshipmappings",nil]){
     BOOL isRelationship=[key isEqualToString:@"relationshipmappings"];

     for(NSString *identifier in [object references:key]){
      CDMappingSourceObject *property=[objects objectForKey:identifier];
      NSString              *name=[property string:@"name"];

      if(name==nil)
       continue;

      NSPropertyMapping *propertyMapping=[[NSPropertyMapping alloc] init];

      [propertyMapping setName:name];

      [propertyMapping setUserInfo:[self _unarchivedObjectOfClass:[NSDictionary class] fromData:[property data:@"userinfodata"]]];

      NSData   *written=[[property string:@"autogenerateexpression"] boolValue]?nil:[property data:@"valueexpressiondata"];
      NSString *keyPath=[property string:@"sourcekeypath"];
      NSString *throughMapping=[property string:@"sourcemappingname"];

      if(written!=nil){
       NSExpression *expression=[self _unarchivedObjectOfClass:[NSExpression class] fromData:written];

       if(expression!=nil)
        [propertyMapping setValueExpression:expression];
       else
        warnf(@"%@.%@: the value expression written here cannot be read",[mapping name],name);
      }
      /* A relationship whose key path and mapping are spelled out is
         filled through them, whatever the source entity calls things. */
      else if(isRelationship && sourceEntity!=nil && ([keyPath length]>0 || [throughMapping length]>0)){
       NSRelationshipDescription *relationship=[[sourceEntity relationshipsByName] objectForKey:([keyPath length]>0)?keyPath:name];

       if([throughMapping length]==0)
        throughMapping=[namesByDestinationEntity objectForKey:[[relationship destinationEntity] name]];

       if([throughMapping length]>0)
        [propertyMapping setValueExpression:[self valueExpressionForRelationshipKeyPath:([keyPath length]>0)?keyPath:name
                                                                         throughMapping:throughMapping]];
       else
        warnf(@"%@.%@: no entity mapping is named to fill the relationship, so it is left empty",[mapping name],name);
      }
      else if(sourceEntity!=nil && [[sourceEntity propertiesByName] objectForKey:name]!=nil){
       if(isRelationship){
        NSRelationshipDescription *relationship=[[sourceEntity relationshipsByName] objectForKey:name];

        throughMapping=[namesByDestinationEntity objectForKey:[[relationship destinationEntity] name]];

        if(throughMapping!=nil)
         [propertyMapping setValueExpression:[self valueExpressionForRelationshipKeyPath:name throughMapping:throughMapping]];
        else
         warnf(@"%@.%@: nothing maps %@ into the destination, so the relationship is left empty",
               [mapping name],name,[[relationship destinationEntity] name]);
       }
       else
        [propertyMapping setValueExpression:[self _valueExpressionForSourceProperty:name]];
      }

      [(isRelationship?relationshipMappings:attributeMappings) addObject:propertyMapping];
     }
    }

    [mapping setAttributeMappings:attributeMappings];
    [mapping setRelationshipMappings:relationshipMappings];
    [entityMappings addObject:mapping];
    index++;
   }

   NSMappingModel *model=[[NSMappingModel alloc] init];

   [model setEntityMappings:entityMappings];

   return model;
}

+(BOOL)compileMappingModelAtPath:(NSString *)path toPath:(NSString *)destination error:(NSError **)error {
   NSMappingModel *model=[self mappingModelAtPath:path error:error];

   if(model==nil)
    return NO;

   NSData *archive=[NSKeyedArchiver archivedDataWithRootObject:model];

   if(archive==nil){
    if(error!=NULL)
     *error=compilerError(@"the mapping model cannot be archived");
    return NO;
   }

   if(![archive writeToFile:destination atomically:YES]){
    if(error!=NULL)
     *error=compilerError(@"cannot write %@",destination);
    return NO;
   }

   return YES;
}

@end
