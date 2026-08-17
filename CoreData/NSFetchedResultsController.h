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
#import <Foundation/NSObject.h>
#import <Foundation/NSIndexPath.h>
#import <CoreData/CoreDataExports.h>

@class NSArray, NSMutableArray, NSError, NSString;
@class NSFetchRequest, NSManagedObjectContext, NSFetchedResultsController;

/* Index paths vended by NSFetchedResultsController have two indexes: the
   section index at position 0 and the index of the object inside the
   section at position 1. */

@protocol NSFetchedResultsSectionInfo <NSObject>
- (NSString *)name;
- (NSString *)indexTitle;
- (NSUInteger)numberOfObjects;
- (NSArray *)objects;
@end

enum {
    NSFetchedResultsChangeInsert = 1,
    NSFetchedResultsChangeDelete = 2,
    NSFetchedResultsChangeMove = 3,
    NSFetchedResultsChangeUpdate = 4
};
typedef NSUInteger NSFetchedResultsChangeType;

@protocol NSFetchedResultsControllerDelegate <NSObject>
@optional
- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller;
- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller;
- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath;
- (void)controller:(NSFetchedResultsController *)controller
  didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex
     forChangeType:(NSFetchedResultsChangeType)type;
- (NSString *)controller:(NSFetchedResultsController *)controller
sectionIndexTitleForSectionName:(NSString *)sectionName;
@end

@interface NSFetchedResultsController : NSObject {
    NSFetchRequest *_fetchRequest;
    NSManagedObjectContext *_managedObjectContext;
    NSString *_sectionNameKeyPath;
    NSString *_cacheName;
    id <NSFetchedResultsControllerDelegate> _delegate;

    NSMutableArray *_fetchedObjects;
    NSMutableArray *_sections;

    BOOL _delegateHasWillChangeContent;
    BOOL _delegateHasDidChangeContent;
    BOOL _delegateHasDidChangeObject;
    BOOL _delegateHasDidChangeSection;
    BOOL _delegateHasSectionIndexTitle;
}

- (id)initWithFetchRequest:(NSFetchRequest *)fetchRequest
      managedObjectContext:(NSManagedObjectContext *)context
        sectionNameKeyPath:(NSString *)sectionNameKeyPath
                 cacheName:(NSString *)name;

- (NSFetchRequest *)fetchRequest;
- (NSManagedObjectContext *)managedObjectContext;
- (NSString *)sectionNameKeyPath;
- (NSString *)cacheName;

- (id <NSFetchedResultsControllerDelegate>)delegate;
- (void)setDelegate:(id <NSFetchedResultsControllerDelegate>)delegate;

- (BOOL)performFetch:(NSError **)error;

- (NSArray *)fetchedObjects;
- (NSArray *)sections;

- (id)objectAtIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)indexPathForObject:(id)object;

- (NSString *)sectionIndexTitleForSectionName:(NSString *)sectionName;
- (NSArray *)sectionIndexTitles;
- (NSUInteger)sectionForSectionIndexTitle:(NSString *)title atIndex:(NSUInteger)sectionIndex;

/* Section information caching is not implemented; the cache name is stored
   but otherwise ignored, and this method is a no-op. */
+ (void)deleteCacheWithName:(NSString *)name;

@end
