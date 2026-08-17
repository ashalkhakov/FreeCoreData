/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   GNUstep port adaptations are released under the same MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/Foundation.h>

@class NSExpression;

typedef enum {
    NSUndefinedEntityMappingType = 0x00,
    NSCustomEntityMappingType    = 0x01,
    NSAddEntityMappingType       = 0x02,
    NSRemoveEntityMappingType    = 0x03,
    NSCopyEntityMappingType      = 0x04,
    NSTransformEntityMappingType = 0x05
} NSEntityMappingType;

@interface NSEntityMapping : NSObject {
    NSString *_name;
    NSEntityMappingType _mappingType;
    NSString *_sourceEntityName;
    NSString *_destinationEntityName;
    NSData *_sourceEntityVersionHash;
    NSData *_destinationEntityVersionHash;
    NSArray *_attributeMappings;
    NSArray *_relationshipMappings;
    NSExpression *_sourceExpression;
    NSString *_entityMigrationPolicyClassName;
    NSDictionary *_userInfo;
}

- (NSString *)name;
- (void)setName:(NSString *)name;

- (NSEntityMappingType)mappingType;
- (void)setMappingType:(NSEntityMappingType)type;

- (NSString *)sourceEntityName;
- (void)setSourceEntityName:(NSString *)name;

- (NSString *)destinationEntityName;
- (void)setDestinationEntityName:(NSString *)name;

- (NSData *)sourceEntityVersionHash;
- (void)setSourceEntityVersionHash:(NSData *)hash;

- (NSData *)destinationEntityVersionHash;
- (void)setDestinationEntityVersionHash:(NSData *)hash;

- (NSArray *)attributeMappings;
- (void)setAttributeMappings:(NSArray *)mappings;

- (NSArray *)relationshipMappings;
- (void)setRelationshipMappings:(NSArray *)mappings;

- (NSExpression *)sourceExpression;
- (void)setSourceExpression:(NSExpression *)expression;

- (NSString *)entityMigrationPolicyClassName;
- (void)setEntityMigrationPolicyClassName:(NSString *)name;

- (NSDictionary *)userInfo;
- (void)setUserInfo:(NSDictionary *)userInfo;

@end
