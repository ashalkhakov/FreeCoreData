/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.  The change tracking approach
   follows MRTFetchedResultsController by Matteo Rattotti
   (https://github.com/matteorattotti/MRTFetchedResultsController, MIT license),
   extended with the sectioning and index path based API of Apple's
   NSFetchedResultsController.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSFetchedResultsController.h>
#import <CoreData/NSFetchRequest.h>
#import "NSFetchRequest-Private.h"
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectContext.h>
#import "NSEntityDescription-Private.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSSortDescriptor.h>
#import <Foundation/NSString.h>

@interface NSFetchedResultsSection : NSObject <NSFetchedResultsSectionInfo> {
    NSString *_name;
    NSString *_indexTitle;
    NSMutableArray *_objects;
}
- (id)initWithName:(NSString *)name indexTitle:(NSString *)indexTitle;
- (void)addObject:(id)object;
@end

@implementation NSFetchedResultsSection

- (id)initWithName:(NSString *)name indexTitle:(NSString *)indexTitle
{
    if((self=[super init])==nil)
     return nil;

    _name=[name copy];
    _indexTitle=[indexTitle copy];
    _objects=[[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc
{
    [_name release];
    [_indexTitle release];
    [_objects release];
    [super dealloc];
}

- (NSString *)name {
    return _name;
}

- (NSString *)indexTitle {
    return _indexTitle;
}

- (NSUInteger)numberOfObjects {
    return [_objects count];
}

- (NSArray *)objects {
    return _objects;
}

- (void)addObject:(id)object {
    [_objects addObject:object];
}

@end

static NSIndexPath *NSFetchedResultsIndexPath(NSUInteger section,NSUInteger row)
{
    NSUInteger indexes[2]={section,row};

    return [NSIndexPath indexPathWithIndexes:indexes length:2];
}

/* Managed objects are not copyable, so identity based lookup tables are
   keyed by the object pointer. */
static id NSFetchedResultsKeyForObject(id object)
{
    return [NSValue valueWithPointer:object];
}

@interface NSFetchedResultsController (private)
- (void)_managedObjectContextObjectsDidChange:(NSNotification *)notification;
@end

@implementation NSFetchedResultsController

+ (void)deleteCacheWithName:(NSString *)name {
    /* Section information caching is not implemented. */
}

- (id)initWithFetchRequest:(NSFetchRequest *)fetchRequest
      managedObjectContext:(NSManagedObjectContext *)context
        sectionNameKeyPath:(NSString *)sectionNameKeyPath
                 cacheName:(NSString *)name
{
    if((self=[super init])==nil)
     return nil;

    _fetchRequest=[fetchRequest retain];
    _managedObjectContext=[context retain];
    _sectionNameKeyPath=[sectionNameKeyPath copy];
    _cacheName=[name copy];
    _fetchedObjects=[[NSMutableArray alloc] init];
    _sections=[[NSMutableArray alloc] init];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                            name:NSManagedObjectContextObjectsDidChangeNotification
                                            object:_managedObjectContext];
    [_fetchRequest release];
    [_managedObjectContext release];
    [_sectionNameKeyPath release];
    [_cacheName release];
    [_fetchedObjects release];
    [_sections release];
    [super dealloc];
}

- (NSFetchRequest *)fetchRequest {
    return _fetchRequest;
}

- (NSManagedObjectContext *)managedObjectContext {
    return _managedObjectContext;
}

- (NSString *)sectionNameKeyPath {
    return _sectionNameKeyPath;
}

- (NSString *)cacheName {
    return _cacheName;
}

- (id <NSFetchedResultsControllerDelegate>)delegate {
    return _delegate;
}

- (void)setDelegate:(id <NSFetchedResultsControllerDelegate>)delegate {
    _delegate=delegate;

    _delegateHasWillChangeContent=[delegate respondsToSelector:@selector(controllerWillChangeContent:)];
    _delegateHasDidChangeContent=[delegate respondsToSelector:@selector(controllerDidChangeContent:)];
    _delegateHasDidChangeObject=[delegate respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)];
    _delegateHasDidChangeSection=[delegate respondsToSelector:@selector(controller:didChangeSection:atIndex:forChangeType:)];
    _delegateHasSectionIndexTitle=[delegate respondsToSelector:@selector(controller:sectionIndexTitleForSectionName:)];
}

#pragma mark - Fetching

- (BOOL)performFetch:(NSError **)error {
    if(_fetchRequest==nil)
     return NO;

    /* Changes accumulated so far are already reflected by the fetch. */
    [_managedObjectContext processPendingChanges];

    NSArray *fetched=[_managedObjectContext executeFetchRequest:_fetchRequest error:error];

    if(fetched==nil)
     return NO;

    [_fetchedObjects release];
    _fetchedObjects=[[self _sortedArrayFromObjects:fetched] mutableCopy];

    [_sections release];
    _sections=[[self _sectionsForObjects:_fetchedObjects] retain];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                            name:NSManagedObjectContextObjectsDidChangeNotification
                                            object:_managedObjectContext];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                          selector:@selector(_managedObjectContextObjectsDidChange:)
                                          name:NSManagedObjectContextObjectsDidChangeNotification
                                          object:_managedObjectContext];

    return YES;
}

- (NSArray *)fetchedObjects {
    return _fetchedObjects;
}

- (NSArray *)sections {
    return _sections;
}

- (id)objectAtIndexPath:(NSIndexPath *)indexPath {
    if([indexPath length]!=2)
     [NSException raise:NSInvalidArgumentException format:@"index path %@ does not have a section and a row",indexPath];

    id <NSFetchedResultsSectionInfo> section=[_sections objectAtIndex:[indexPath indexAtPosition:0]];

    return [[section objects] objectAtIndex:[indexPath indexAtPosition:1]];
}

- (NSIndexPath *)indexPathForObject:(id)object {
    NSUInteger sectionIndex,sectionCount=[_sections count];

    for(sectionIndex=0;sectionIndex<sectionCount;sectionIndex++){
     id <NSFetchedResultsSectionInfo> section=[_sections objectAtIndex:sectionIndex];
     NSUInteger row=[[section objects] indexOfObjectIdenticalTo:object];

     if(row!=NSNotFound)
      return NSFetchedResultsIndexPath(sectionIndex,row);
    }

    return nil;
}

- (NSString *)sectionIndexTitleForSectionName:(NSString *)sectionName {
    if([sectionName length]==0)
     return sectionName;

    return [[sectionName substringToIndex:1] uppercaseString];
}

- (NSArray *)sectionIndexTitles {
    NSMutableArray *result=[NSMutableArray array];

    for(id <NSFetchedResultsSectionInfo> section in _sections){
     NSString *title=[section indexTitle];

     [result addObject:(title!=nil)?title:@""];
    }

    return result;
}

- (NSUInteger)sectionForSectionIndexTitle:(NSString *)title atIndex:(NSUInteger)sectionIndex {
    NSArray *titles=[self sectionIndexTitles];

/* There is one index title per section, so the position in the index title
   array is the position of the section. */
    if(sectionIndex<[titles count])
     if([[titles objectAtIndex:sectionIndex] isEqualToString:title])
      return sectionIndex;

    NSUInteger result=[titles indexOfObject:title];

    return (result==NSNotFound)?0:result;
}

#pragma mark - Sections

- (NSString *)_sectionNameForObject:(id)object {
    if(_sectionNameKeyPath==nil)
     return nil;

    id value=[object valueForKeyPath:_sectionNameKeyPath];

    if(value==nil)
     return @"";

    if([value isKindOfClass:[NSString class]])
     return value;

    return [value description];
}

/* Objects are already sorted, sections are runs of adjacent objects sharing
   the same section name, as they are with Apple's implementation. */
- (NSMutableArray *)_sectionsForObjects:(NSArray *)objects {
    NSMutableArray *result=[NSMutableArray array];
    NSFetchedResultsSection *current=nil;
    NSString *currentName=nil;

    for(id object in objects){
     NSString *name=[self _sectionNameForObject:object];

     if(current==nil || !(name==currentName || [name isEqualToString:currentName])){
      NSString *indexTitle=nil;

      if(name!=nil){
       if(_delegateHasSectionIndexTitle)
        indexTitle=[_delegate controller:self sectionIndexTitleForSectionName:name];
       else
        indexTitle=[self sectionIndexTitleForSectionName:name];
      }

      current=[[[NSFetchedResultsSection alloc] initWithName:name indexTitle:indexTitle] autorelease];
      currentName=name;
      [result addObject:current];
     }

     [current addObject:object];
    }

    return result;
}

- (NSArray *)_sortedArrayFromObjects:(NSArray *)objects {
    NSArray *sortDescriptors=[_fetchRequest sortDescriptors];

    if([sortDescriptors count]==0)
     return objects;

    return [objects sortedArrayUsingDescriptors:sortDescriptors];
}

- (BOOL)_objectConformsToFetchRequest:(NSManagedObject *)object {
    NSEntityDescription *entity=[_fetchRequest _entityIfResolved];

    if(entity!=nil && ![[object entity] _isKindOfEntity:entity])
     return NO;

    NSPredicate *predicate=[_fetchRequest predicate];

    if(predicate!=nil && ![predicate evaluateWithObject:object])
     return NO;

    return YES;
}

#pragma mark - Change tracking

- (NSDictionary *)_indexPathsForSections:(NSArray *)sections {
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    NSUInteger sectionIndex,sectionCount=[sections count];

    for(sectionIndex=0;sectionIndex<sectionCount;sectionIndex++){
     NSArray *objects=[[sections objectAtIndex:sectionIndex] objects];
     NSUInteger row,rowCount=[objects count];

     for(row=0;row<rowCount;row++)
      [result setObject:NSFetchedResultsIndexPath(sectionIndex,row)
              forKey:NSFetchedResultsKeyForObject([objects objectAtIndex:row])];
    }

    return result;
}

- (NSUInteger)_indexOfSectionNamed:(NSString *)name inSections:(NSArray *)sections {
    NSUInteger i,count=[sections count];

    for(i=0;i<count;i++){
     NSString *check=[[sections objectAtIndex:i] name];

     if(check==name || [check isEqualToString:name])
      return i;
    }

    return NSNotFound;
}

- (void)_managedObjectContextObjectsDidChange:(NSNotification *)notification {
    NSDictionary *userInfo=[notification userInfo];
    NSSet *inserted=[userInfo objectForKey:NSInsertedObjectsKey];
    NSSet *deleted=[userInfo objectForKey:NSDeletedObjectsKey];
    NSMutableSet *changed=[NSMutableSet set];

    if([userInfo objectForKey:NSUpdatedObjectsKey]!=nil)
     [changed unionSet:[userInfo objectForKey:NSUpdatedObjectsKey]];
    if([userInfo objectForKey:NSRefreshedObjectsKey]!=nil)
     [changed unionSet:[userInfo objectForKey:NSRefreshedObjectsKey]];

    if(inserted!=nil)
     [changed minusSet:inserted];
    if(deleted!=nil)
     [changed minusSet:deleted];

    NSMutableArray *objects=[[_fetchedObjects mutableCopy] autorelease];
    NSMutableDictionary *present=[NSMutableDictionary dictionary];
    BOOL membershipChanged=NO;

    for(id object in objects)
     [present setObject:object forKey:NSFetchedResultsKeyForObject(object)];

    for(NSManagedObject *object in deleted){
     if([present objectForKey:NSFetchedResultsKeyForObject(object)]!=nil){
      [objects removeObjectIdenticalTo:object];
      [present removeObjectForKey:NSFetchedResultsKeyForObject(object)];
      membershipChanged=YES;
     }
    }

    NSMutableSet *candidates=[NSMutableSet set];

    if(inserted!=nil)
     [candidates unionSet:inserted];
    [candidates unionSet:changed];
    if(deleted!=nil)
     [candidates minusSet:deleted];

    for(NSManagedObject *object in candidates){
     BOOL contained=([present objectForKey:NSFetchedResultsKeyForObject(object)]!=nil);

     if([self _objectConformsToFetchRequest:object]){
      if(!contained){
       [objects addObject:object];
       [present setObject:object forKey:NSFetchedResultsKeyForObject(object)];
       membershipChanged=YES;
      }
     }
     else if(contained){
      [objects removeObjectIdenticalTo:object];
      [present removeObjectForKey:NSFetchedResultsKeyForObject(object)];
      membershipChanged=YES;
     }
    }

    NSMutableArray *newObjects=[[[self _sortedArrayFromObjects:objects] mutableCopy] autorelease];
    NSMutableArray *newSections=[self _sectionsForObjects:newObjects];
    NSArray *oldSections=_sections;

    NSDictionary *oldIndexPaths=[self _indexPathsForSections:oldSections];
    NSDictionary *newIndexPaths=[self _indexPathsForSections:newSections];

    /* Collect the delegate messages before touching the delegate, so the
       controller is already in its new state while the delegate is
       running. */
    NSMutableArray *objectChanges=[NSMutableArray array];
    NSMutableArray *sectionChanges=[NSMutableArray array];

    if(!membershipChanged){
     BOOL relevantUpdate=NO;

     for(NSManagedObject *object in changed){
      if([present objectForKey:NSFetchedResultsKeyForObject(object)]!=nil){
       relevantUpdate=YES;
       break;
      }
     }

     if(!relevantUpdate)
      return;
    }

    for(id object in _fetchedObjects){
     id key=NSFetchedResultsKeyForObject(object);

     if([newIndexPaths objectForKey:key]==nil)
      [objectChanges addObject:[NSArray arrayWithObjects:object,
        [NSNumber numberWithUnsignedInteger:NSFetchedResultsChangeDelete],
        [oldIndexPaths objectForKey:key],nil]];
    }

    NSUInteger sectionIndex,sectionCount=[oldSections count];

    for(sectionIndex=0;sectionIndex<sectionCount;sectionIndex++){
     NSFetchedResultsSection *section=[oldSections objectAtIndex:sectionIndex];

     if([self _indexOfSectionNamed:[section name] inSections:newSections]==NSNotFound)
      [sectionChanges addObject:[NSArray arrayWithObjects:section,
        [NSNumber numberWithUnsignedInteger:NSFetchedResultsChangeDelete],
        [NSNumber numberWithUnsignedInteger:sectionIndex],nil]];
    }

    sectionCount=[newSections count];

    for(sectionIndex=0;sectionIndex<sectionCount;sectionIndex++){
     NSFetchedResultsSection *section=[newSections objectAtIndex:sectionIndex];

     if([self _indexOfSectionNamed:[section name] inSections:oldSections]==NSNotFound)
      [sectionChanges addObject:[NSArray arrayWithObjects:section,
        [NSNumber numberWithUnsignedInteger:NSFetchedResultsChangeInsert],
        [NSNumber numberWithUnsignedInteger:sectionIndex],nil]];
    }

    for(id object in newObjects){
     id key=NSFetchedResultsKeyForObject(object);
     NSIndexPath *oldIndexPath=[oldIndexPaths objectForKey:key];
     NSIndexPath *newIndexPath=[newIndexPaths objectForKey:key];

     if(oldIndexPath==nil)
      [objectChanges addObject:[NSArray arrayWithObjects:object,
        [NSNumber numberWithUnsignedInteger:NSFetchedResultsChangeInsert],
        newIndexPath,nil]];
     else if(![oldIndexPath isEqual:newIndexPath])
      [objectChanges addObject:[NSArray arrayWithObjects:object,
        [NSNumber numberWithUnsignedInteger:NSFetchedResultsChangeMove],
        oldIndexPath,newIndexPath,nil]];
     else if([changed containsObject:object])
      [objectChanges addObject:[NSArray arrayWithObjects:object,
        [NSNumber numberWithUnsignedInteger:NSFetchedResultsChangeUpdate],
        oldIndexPath,nil]];
    }

    if([objectChanges count]==0 && [sectionChanges count]==0){
     [_fetchedObjects release];
     _fetchedObjects=[newObjects retain];
     [_sections release];
     _sections=[newSections retain];
     return;
    }

    if(_delegateHasWillChangeContent)
     [_delegate controllerWillChangeContent:self];

    [_fetchedObjects release];
    _fetchedObjects=[newObjects retain];
    [_sections release];
    _sections=[newSections retain];

    if(_delegateHasDidChangeSection){
     for(NSArray *change in sectionChanges)
      [_delegate controller:self
                 didChangeSection:[change objectAtIndex:0]
                 atIndex:[[change objectAtIndex:2] unsignedIntegerValue]
                 forChangeType:[[change objectAtIndex:1] unsignedIntegerValue]];
    }

    if(_delegateHasDidChangeObject){
     for(NSArray *change in objectChanges){
      NSFetchedResultsChangeType type=[[change objectAtIndex:1] unsignedIntegerValue];
      NSIndexPath *indexPath=[change objectAtIndex:2];
      NSIndexPath *newIndexPath=([change count]>3)?[change objectAtIndex:3]:nil;

      if(type==NSFetchedResultsChangeInsert)
       [_delegate controller:self didChangeObject:[change objectAtIndex:0]
                  atIndexPath:nil forChangeType:type newIndexPath:indexPath];
      else if(type==NSFetchedResultsChangeMove)
       [_delegate controller:self didChangeObject:[change objectAtIndex:0]
                  atIndexPath:indexPath forChangeType:type newIndexPath:newIndexPath];
      else
       [_delegate controller:self didChangeObject:[change objectAtIndex:0]
                  atIndexPath:indexPath forChangeType:type newIndexPath:nil];
     }
    }

    if(_delegateHasDidChangeContent)
     [_delegate controllerDidChangeContent:self];
}

@end
