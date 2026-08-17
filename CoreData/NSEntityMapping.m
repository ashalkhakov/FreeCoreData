/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSEntityMapping.h>

@implementation NSEntityMapping

-(void)dealloc {
   [_name release];
   [_sourceEntityName release];
   [_destinationEntityName release];
   [_sourceEntityVersionHash release];
   [_destinationEntityVersionHash release];
   [_attributeMappings release];
   [_relationshipMappings release];
   [_sourceExpression release];
   [_entityMigrationPolicyClassName release];
   [_userInfo release];
   [super dealloc];
}

-(NSString *)name {
   if(_name!=nil)
    return _name;

   /* Default name follows Apple's convention: Source->Destination. */
   return [NSString stringWithFormat:@"%@->%@",(_sourceEntityName!=nil)?_sourceEntityName:@"",(_destinationEntityName!=nil)?_destinationEntityName:@""];
}

-(void)setName:(NSString *)name {
   name=[name copy];
   [_name release];
   _name=name;
}

-(NSEntityMappingType)mappingType {
   return _mappingType;
}

-(void)setMappingType:(NSEntityMappingType)type {
   _mappingType=type;
}

-(NSString *)sourceEntityName {
   return _sourceEntityName;
}

-(void)setSourceEntityName:(NSString *)name {
   name=[name copy];
   [_sourceEntityName release];
   _sourceEntityName=name;
}

-(NSString *)destinationEntityName {
   return _destinationEntityName;
}

-(void)setDestinationEntityName:(NSString *)name {
   name=[name copy];
   [_destinationEntityName release];
   _destinationEntityName=name;
}

-(NSData *)sourceEntityVersionHash {
   return _sourceEntityVersionHash;
}

-(void)setSourceEntityVersionHash:(NSData *)hash {
   hash=[hash copy];
   [_sourceEntityVersionHash release];
   _sourceEntityVersionHash=hash;
}

-(NSData *)destinationEntityVersionHash {
   return _destinationEntityVersionHash;
}

-(void)setDestinationEntityVersionHash:(NSData *)hash {
   hash=[hash copy];
   [_destinationEntityVersionHash release];
   _destinationEntityVersionHash=hash;
}

-(NSArray *)attributeMappings {
   return _attributeMappings;
}

-(void)setAttributeMappings:(NSArray *)mappings {
   mappings=[mappings copy];
   [_attributeMappings release];
   _attributeMappings=mappings;
}

-(NSArray *)relationshipMappings {
   return _relationshipMappings;
}

-(void)setRelationshipMappings:(NSArray *)mappings {
   mappings=[mappings copy];
   [_relationshipMappings release];
   _relationshipMappings=mappings;
}

-(NSExpression *)sourceExpression {
   return _sourceExpression;
}

-(void)setSourceExpression:(NSExpression *)expression {
   expression=[expression retain];
   [_sourceExpression release];
   _sourceExpression=expression;
}

-(NSString *)entityMigrationPolicyClassName {
   return _entityMigrationPolicyClassName;
}

-(void)setEntityMigrationPolicyClassName:(NSString *)name {
   name=[name copy];
   [_entityMigrationPolicyClassName release];
   _entityMigrationPolicyClassName=name;
}

-(NSDictionary *)userInfo {
   return _userInfo;
}

-(void)setUserInfo:(NSDictionary *)userInfo {
   userInfo=[userInfo copy];
   [_userInfo release];
   _userInfo=userInfo;
}

@end
