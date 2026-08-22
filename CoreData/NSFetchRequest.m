/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSFetchRequest.h>
#import "NSFetchRequest-Private.h"
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectContext.h>
#import <CoreData/NSEntityDescription.h>
#import "CoreDataUtilities.h"

@implementation NSFetchRequest

+ (NSFetchRequest *)fetchRequestWithEntityName:(NSString *)entityName {
   /* [self alloc], not [NSFetchRequest alloc], so subclasses get
      instances of themselves. */
   return [[[self alloc] initWithEntityName:entityName] autorelease];
}

-init {
   _entity=nil;
   _entityName=nil;
   _predicate=nil;
   _sortDescriptors=nil;
   _affectedStores=nil;
   _fetchLimit=0;
   /* Apple's defaults. */
   _includesSubentities=YES;
   _includesPendingChanges=YES;
   _includesPropertyValues=YES;
   _returnsObjectsAsFaults=YES;
   _shouldRefreshRefetchedObjects=NO;
   return self;
}

-(instancetype)initWithEntityName:(NSString *)entityName {
   if((self=[self init])==nil)
    return nil;

   /* Only the name is stored; the entity is resolved against the
      coordinator's model when the request is executed, matching Apple
      (no model is available here). */
   _entityName=[entityName copy];

   return self;
}

-(NSString *)entityName {
   return _entityName;
}

-(NSEntityDescription *)_entityIfResolved {
   return _entity;
}

/* Keyed archiving carries what a fetch request template needs: the
   entity rides along as an object reference, so unarchiving a model
   resolves a template's entity to the same NSEntityDescription
   instance the model owns. */
-initWithCoder: (NSCoder *) coder {
   if((self=[self init])==nil)
    return nil;

   _entity=[[coder decodeObjectForKey:@"NSEntity"] retain];
   _entityName=[[coder decodeObjectForKey:@"NSEntityName"] copy];
   _predicate=[[coder decodeObjectForKey:@"NSPredicate"] retain];
   _sortDescriptors=[[coder decodeObjectForKey:@"NSSortDescriptors"] retain];
   _fetchLimit=(NSUInteger)[coder decodeInt64ForKey:@"NSFetchLimit"];
   _fetchOffset=(NSUInteger)[coder decodeInt64ForKey:@"NSFetchOffset"];
   _resultType=(NSFetchRequestResultType)[coder decodeInt64ForKey:@"NSResultType"];
   if([coder containsValueForKey:@"NSIncludesSubentities"])
    _includesSubentities=[coder decodeBoolForKey:@"NSIncludesSubentities"];
   if([coder containsValueForKey:@"NSIncludesPendingChanges"])
    _includesPendingChanges=[coder decodeBoolForKey:@"NSIncludesPendingChanges"];
   if([coder containsValueForKey:@"NSIncludesPropertyValues"])
    _includesPropertyValues=[coder decodeBoolForKey:@"NSIncludesPropertyValues"];
   if([coder containsValueForKey:@"NSReturnsObjectsAsFaults"])
    _returnsObjectsAsFaults=[coder decodeBoolForKey:@"NSReturnsObjectsAsFaults"];
   _returnsDistinctResults=[coder decodeBoolForKey:@"NSReturnsDistinctResults"];
   _propertiesToFetch=[[coder decodeObjectForKey:@"NSPropertiesToFetch"] retain];
   _relationshipKeyPathsForPrefetching=[[coder decodeObjectForKey:@"NSRelationshipKeyPathsForPrefetching"] retain];
   _propertiesToGroupBy=[[coder decodeObjectForKey:@"NSPropertiesToGroupBy"] retain];
   _havingPredicate=[[coder decodeObjectForKey:@"NSHavingPredicate"] retain];
   _shouldRefreshRefetchedObjects=[coder decodeBoolForKey:@"NSShouldRefreshRefetchedObjects"];

   return self;
}

-(void)encodeWithCoder:(NSCoder *)coder {
   if(_entity!=nil)
    [coder encodeObject:_entity forKey:@"NSEntity"];
   if(_entityName!=nil)
    [coder encodeObject:_entityName forKey:@"NSEntityName"];
   if(_predicate!=nil)
    [coder encodeObject:_predicate forKey:@"NSPredicate"];
   if(_sortDescriptors!=nil)
    [coder encodeObject:_sortDescriptors forKey:@"NSSortDescriptors"];
   [coder encodeInt64:(int64_t)_fetchLimit forKey:@"NSFetchLimit"];
   [coder encodeInt64:(int64_t)_fetchOffset forKey:@"NSFetchOffset"];
   [coder encodeInt64:(int64_t)_resultType forKey:@"NSResultType"];
   [coder encodeBool:_includesSubentities forKey:@"NSIncludesSubentities"];
   [coder encodeBool:_includesPendingChanges forKey:@"NSIncludesPendingChanges"];
   [coder encodeBool:_includesPropertyValues forKey:@"NSIncludesPropertyValues"];
   [coder encodeBool:_returnsObjectsAsFaults forKey:@"NSReturnsObjectsAsFaults"];
   [coder encodeBool:_returnsDistinctResults forKey:@"NSReturnsDistinctResults"];
   if(_propertiesToFetch!=nil)
    [coder encodeObject:_propertiesToFetch forKey:@"NSPropertiesToFetch"];
   if(_relationshipKeyPathsForPrefetching!=nil)
    [coder encodeObject:_relationshipKeyPathsForPrefetching forKey:@"NSRelationshipKeyPathsForPrefetching"];
   if(_propertiesToGroupBy!=nil)
    [coder encodeObject:_propertiesToGroupBy forKey:@"NSPropertiesToGroupBy"];
   if(_havingPredicate!=nil)
    [coder encodeObject:_havingPredicate forKey:@"NSHavingPredicate"];
   [coder encodeBool:_shouldRefreshRefetchedObjects forKey:@"NSShouldRefreshRefetchedObjects"];
}

-copyWithZone:(NSZone *)zone {
   NSFetchRequest *result=NSCopyObject(self,0,zone);
   
   result->_entity=[_entity retain];
   result->_entityName=[_entityName copy];
   result->_predicate=[_predicate copy];
   result->_sortDescriptors=[_sortDescriptors copy];
   result->_affectedStores=[_affectedStores copy];
   result->_propertiesToFetch=[_propertiesToFetch copy];
   result->_relationshipKeyPathsForPrefetching=[_relationshipKeyPathsForPrefetching copy];
   result->_propertiesToGroupBy=[_propertiesToGroupBy copy];
   result->_havingPredicate=[_havingPredicate retain];

   return result;
}

-(void)dealloc {
   [_entity release];
   [_entityName release];
   [_predicate release];
   [_sortDescriptors release];
   /* _affectedStores is released by NSPersistentStoreRequest. */
   [_propertiesToFetch release];
   [_relationshipKeyPathsForPrefetching release];
   [_propertiesToGroupBy release];
   [_havingPredicate release];
   [super dealloc];
}

-(NSFetchRequestResultType)resultType {
   return _resultType;
}

-(NSEntityDescription *)entity {
   /* Matching Apple (verified on macOS): a request created with an
      entity name raises until it has been used by a context, e.g.
      "This fetch request (0x...) was created with a string name
      (Employee), and cannot respond to -entity until used by an
      NSManagedObjectContext". */
   if(_entity==nil && _entityName!=nil)
    [NSException raise:NSObjectInaccessibleException
                format:@"This fetch request (%p) was created with a string name (%@), and cannot respond to -entity until used by an NSManagedObjectContext",self,_entityName];

   return _entity;
}

-(NSPredicate *)predicate {
   return _predicate;
}

-(NSArray *)sortDescriptors {
   return _sortDescriptors;
}

-(NSUInteger)fetchLimit {
   return _fetchLimit;
}

-(NSUInteger)fetchBatchSize {
   return _fetchBatchSize;
}

-(NSUInteger)fetchOffset {
   return _fetchOffset;
}

-(BOOL)includesPendingChanges {
   return _includesPendingChanges;
}

-(BOOL)includesPropertyValues {
   return _includesPropertyValues;
}

-(BOOL)includesSubentities {
   return _includesSubentities;
}

-(BOOL)returnsDistinctResults {
   return _returnsDistinctResults;
}

-(BOOL)returnsObjectsAsFaults {
   return _returnsObjectsAsFaults;
}

-(NSArray *)propertiesToFetch {
   return _propertiesToFetch;
}

-(NSArray *)relationshipKeyPathsForPrefetching {
   return _relationshipKeyPathsForPrefetching;
}

-(NSArray *)propertiesToGroupBy {
   return _propertiesToGroupBy;
}

-(NSPredicate *)havingPredicate {
   return _havingPredicate;
}

-(BOOL)shouldRefreshRefetchedObjects {
   return _shouldRefreshRefetchedObjects;
}

-(void)setResultType:(NSFetchRequestResultType)type {
   _resultType=type;
}

-(void)setEntity:(NSEntityDescription *)value {
   value=[value retain];
   [_entity release];
   _entity=value;
}

-(void)setPredicate:(NSPredicate *)value {
   value=[value retain];
   [_predicate release];
   _predicate=value;
}

-(void)setSortDescriptors:(NSArray *)value {
   value=[value copy];
   [_sortDescriptors release];
   _sortDescriptors=value;
}

-(void)setFetchLimit:(NSUInteger)value {
   _fetchLimit=value;
}

-(void)setFetchBatchSize:(NSUInteger)value {
   _fetchBatchSize=value;
}

-(void)setFetchOffset:(NSUInteger)value {
   _fetchOffset=value;
}

-(void)setIncludesPendingChanges:(BOOL)value {
   _includesPendingChanges=value;
}

-(void)setIncludesPropertyValues:(BOOL)value {
   _includesPropertyValues=value;
}

-(void)setIncludesSubentities:(BOOL)value {
   _includesSubentities=value;
}

-(void)setReturnsDistinctResults:(BOOL)value {
   _returnsDistinctResults=value;
}

-(void)setReturnsObjectsAsFaults:(BOOL)value {
   _returnsObjectsAsFaults=value;
}

-(void)setPropertiesToFetch:(NSArray *)value {
   value=[value copy];
   [_propertiesToFetch release];
   _propertiesToFetch=value;
}

-(void)setRelationshipKeyPathsForPrefetching:(NSArray *)value {
   value=[value copy];
   [_relationshipKeyPathsForPrefetching release];
   _relationshipKeyPathsForPrefetching=value;
}

-(void)setPropertiesToGroupBy:(NSArray *)value {
   value=[value copy];
   [_propertiesToGroupBy release];
   _propertiesToGroupBy=value;
}

-(void)setHavingPredicate:(NSPredicate *)value {
   value=[value retain];
   [_havingPredicate release];
   _havingPredicate=value;
}

-(void)setShouldRefreshRefetchedObjects:(BOOL)value {
   _shouldRefreshRefetchedObjects=value;
}

@end
