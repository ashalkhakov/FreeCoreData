/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* A small command line application exercising the CoreData features that
   differ most between implementations: entity inheritance, transient
   properties, validation, to-one/to-many/many-to-many relationships and
   NSFetchedResultsController change tracking, all on top of the SQLite
   store.  It builds and runs unchanged against the GNUstep port and
   against Apple's CoreData. */
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "EmployeeDirectoryModel.h"

static void print(NSString *format, ...)
{
    va_list arguments;

    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    fprintf(stdout, "%s\n", [line UTF8String]);
    fflush(stdout);
    [line release];
}

/* Index paths of a fetched results controller carry the section at
   position 0 and the row inside the section at position 1. */
static NSString *describeIndexPath(NSIndexPath *indexPath)
{
    if (indexPath == nil)
        return @"-";

    return [NSString stringWithFormat:@"%lu.%lu",
        (unsigned long)[indexPath indexAtPosition:0],
        (unsigned long)[indexPath indexAtPosition:1]];
}

static NSString *describeChangeType(NSFetchedResultsChangeType type)
{
    switch (type) {
        case NSFetchedResultsChangeInsert: return @"insert";
        case NSFetchedResultsChangeDelete: return @"delete";
        case NSFetchedResultsChangeMove: return @"move";
        case NSFetchedResultsChangeUpdate: return @"update";
    }
    return @"?";
}

@interface EDDirectoryObserver : NSObject <NSFetchedResultsControllerDelegate>
@end

@implementation EDDirectoryObserver

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller
{
    print(@"    [delegate] will change content");
}

- (void)controller:(NSFetchedResultsController *)controller
  didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex
     forChangeType:(NSFetchedResultsChangeType)type
{
    print(@"    [delegate] section '%@' %@ at %lu", [sectionInfo name],
        describeChangeType(type), (unsigned long)sectionIndex);
}

- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath
{
    print(@"    [delegate] object %@ %@ (%@ -> %@)",
        [anObject valueForKey:@"lastName"], describeChangeType(type),
        describeIndexPath(indexPath), describeIndexPath(newIndexPath));
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    print(@"    [delegate] did change content");
}

@end

static void printSections(NSFetchedResultsController *controller)
{
    for (id <NSFetchedResultsSectionInfo> section in [controller sections]) {
        print(@"  section '%@' (%lu objects)", [section name],
            (unsigned long)[section numberOfObjects]);

        for (NSManagedObject *employee in [section objects])
            print(@"    %@ — salary %@", [(EDPerson *)employee fullName],
                [employee valueForKey:@"salary"]);
    }
}

static NSManagedObjectContext *contextForStoreAtURL(NSURL *storeURL, NSManagedObjectModel *model)
{
    NSPersistentStoreCoordinator *coordinator =
        [[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model] autorelease];
    NSError *error = nil;

    if ([coordinator addPersistentStoreWithType:NSSQLiteStoreType
                     configuration:nil
                     URL:storeURL
                     options:nil
                     error:&error] == nil) {
        print(@"unable to open the store: %@", error);
        exit(1);
    }

    NSManagedObjectContext *context = [[[NSManagedObjectContext alloc] init] autorelease];

    [context setPersistentStoreCoordinator:coordinator];

    return context;
}

static NSManagedObject *insert(NSManagedObjectContext *context, NSString *entityName)
{
    return [NSEntityDescription insertNewObjectForEntityForName:entityName
                                inManagedObjectContext:context];
}

static NSArray *fetch(NSManagedObjectContext *context, NSString *entityName,
    NSPredicate *predicate, NSArray *sortDescriptors)
{
    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];

    [request setEntity:[NSEntityDescription entityForName:entityName
                                            inManagedObjectContext:context]];
    [request setPredicate:predicate];
    [request setSortDescriptors:sortDescriptors];

    NSError *error = nil;
    NSArray *result = [context executeFetchRequest:request error:&error];

    if (result == nil)
        print(@"fetch of %@ failed: %@", entityName, error);

    return result;
}

static NSArray *sortByLastName(void)
{
    return [NSArray arrayWithObjects:
        [[[NSSortDescriptor alloc] initWithKey:@"department.name" ascending:YES] autorelease],
        [[[NSSortDescriptor alloc] initWithKey:@"lastName" ascending:YES] autorelease], nil];
}

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *path = (argc > 1) ? [NSString stringWithUTF8String:argv[1]]
                                : [NSTemporaryDirectory() stringByAppendingPathComponent:@"EmployeeDirectory.sqlite"];
    NSURL *storeURL = [NSURL fileURLWithPath:path];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    /* Always start from an empty store so the demo output is stable. */
    [fileManager removeItemAtPath:path error:NULL];
    [fileManager removeItemAtPath:[path stringByAppendingString:@"-wal"] error:NULL];
    [fileManager removeItemAtPath:[path stringByAppendingString:@"-shm"] error:NULL];

    NSManagedObjectModel *model = EmployeeDirectoryModel();
    NSManagedObjectContext *context = contextForStoreAtURL(storeURL, model);
    NSError *error = nil;

    print(@"Employee directory stored at %@", path);

    /* ---------------------------------------------------------------
       Inserting objects, to-one, to-many and many-to-many relationships
       --------------------------------------------------------------- */
    NSManagedObject *engineering = insert(context, @"Department");
    [engineering setValue:@"Engineering" forKey:@"name"];

    NSManagedObject *sales = insert(context, @"Department");
    [sales setValue:@"Sales" forKey:@"name"];

    NSManagedObject *alice = insert(context, @"Employee");
    [alice setValue:@"Alice" forKey:@"firstName"];
    [alice setValue:@"Anderson" forKey:@"lastName"];
    [alice setValue:[NSNumber numberWithInt:5000] forKey:@"salary"];
    [alice setValue:engineering forKey:@"department"];

    NSManagedObject *bob = insert(context, @"Employee");
    [bob setValue:@"Bob" forKey:@"firstName"];
    [bob setValue:@"Brown" forKey:@"lastName"];
    [bob setValue:[NSNumber numberWithInt:4000] forKey:@"salary"];
    [bob setValue:engineering forKey:@"department"];

    NSManagedObject *carol = insert(context, @"Employee");
    [carol setValue:@"Carol" forKey:@"firstName"];
    [carol setValue:@"Clarke" forKey:@"lastName"];
    [carol setValue:[NSNumber numberWithInt:4500] forKey:@"salary"];
    [carol setValue:sales forKey:@"department"];

    /* Contractor is a second subentity of the abstract Person entity. */
    NSManagedObject *dave = insert(context, @"Contractor");
    [dave setValue:@"Dave" forKey:@"firstName"];
    [dave setValue:@"Doyle" forKey:@"lastName"];
    [dave setValue:@"Consulting Inc." forKey:@"agency"];

    /* Many-to-many: employees take part in several projects. */
    NSManagedObject *apollo = insert(context, @"Project");
    [apollo setValue:@"Apollo" forKey:@"name"];

    NSManagedObject *gemini = insert(context, @"Project");
    [gemini setValue:@"Gemini" forKey:@"name"];

    [[alice mutableSetValueForKey:@"projects"] addObject:apollo];
    [[alice mutableSetValueForKey:@"projects"] addObject:gemini];
    [[bob mutableSetValueForKey:@"projects"] addObject:apollo];
    [[carol mutableSetValueForKey:@"projects"] addObject:gemini];

    /* ---------------------------------------------------------------
       Validation
       --------------------------------------------------------------- */
    print(@"\n== validation ==");

    NSManagedObject *invalid = insert(context, @"Employee");
    [invalid setValue:@"Eve" forKey:@"firstName"];
    [invalid setValue:[NSNumber numberWithInt:-1] forKey:@"salary"];

    if (![context save:&error])
        print(@"  rejected (missing lastName, negative salary): %@",
            [error localizedDescription]);

    [invalid setValue:@"Evans" forKey:@"lastName"];
    [invalid setValue:[NSNumber numberWithInt:4321] forKey:@"salary"];
    error = nil;

    if (![context save:&error])
        print(@"  rejected (custom -validateSalary:error:): %@",
            [error localizedDescription]);

    [invalid setValue:[NSNumber numberWithInt:4300] forKey:@"salary"];
    [invalid setValue:sales forKey:@"department"];
    error = nil;

    if ([context save:&error])
        print(@"  accepted after fixing the values");
    else
        print(@"  unexpected save failure: %@", error);

    /* ---------------------------------------------------------------
       Inheritance and transient properties
       --------------------------------------------------------------- */
    print(@"\n== every Person (inheritance) ==");

    for (EDPerson *person in fetch(context, @"Person", nil,
             [NSArray arrayWithObject:
                 [[[NSSortDescriptor alloc] initWithKey:@"lastName" ascending:YES] autorelease]]))
        print(@"  %@", [person shortDescription]);

    print(@"\n== many-to-many ==");

    for (NSManagedObject *project in fetch(context, @"Project", nil, nil)) {
        NSMutableArray *names = [NSMutableArray array];

        for (EDPerson *member in [project valueForKey:@"members"])
            [names addObject:[member fullName]];

        [names sortUsingSelector:@selector(compare:)];
        print(@"  %@: %@", [project valueForKey:@"name"],
            [names componentsJoinedByString:@", "]);
    }

    /* ---------------------------------------------------------------
       NSFetchedResultsController
       --------------------------------------------------------------- */
    print(@"\n== fetched results controller ==");

    NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];

    [request setEntity:[NSEntityDescription entityForName:@"Employee"
                                            inManagedObjectContext:context]];
    [request setSortDescriptors:sortByLastName()];

    EDDirectoryObserver *observer = [[[EDDirectoryObserver alloc] init] autorelease];
    NSFetchedResultsController *controller =
        [[[NSFetchedResultsController alloc] initWithFetchRequest:request
                                           managedObjectContext:context
                                           sectionNameKeyPath:@"department.name"
                                           cacheName:nil] autorelease];

    [controller setDelegate:observer];
    error = nil;

    if (![controller performFetch:&error]) {
        print(@"performFetch failed: %@", error);
        return 1;
    }

    printSections(controller);

    print(@"\n  -- Bob moves to Sales --");
    [bob setValue:sales forKey:@"department"];
    [context processPendingChanges];

    print(@"\n  -- Frank joins Engineering --");
    NSManagedObject *frank = insert(context, @"Employee");
    [frank setValue:@"Frank" forKey:@"firstName"];
    [frank setValue:@"Fisher" forKey:@"lastName"];
    [frank setValue:[NSNumber numberWithInt:3900] forKey:@"salary"];
    [frank setValue:engineering forKey:@"department"];
    [context processPendingChanges];

    print(@"\n  -- Carol gets a raise --");
    [carol setValue:[NSNumber numberWithInt:4700] forKey:@"salary"];
    [context processPendingChanges];

    print(@"\n  -- Eve leaves the company --");
    [context deleteObject:invalid];
    [context processPendingChanges];

    print(@"\n  final layout:");
    printSections(controller);

    error = nil;

    if (![context save:&error])
        print(@"save failed: %@", error);

    /* ---------------------------------------------------------------
       Reopening the store
       --------------------------------------------------------------- */
    print(@"\n== reopening the store ==");

    NSManagedObjectContext *reopened = contextForStoreAtURL(storeURL, EmployeeDirectoryModel());

    for (EDPerson *person in fetch(reopened, @"Person", nil,
             [NSArray arrayWithObject:
                 [[[NSSortDescriptor alloc] initWithKey:@"lastName" ascending:YES] autorelease]]))
        print(@"  %@", [person shortDescription]);

    NSArray *engineers = fetch(reopened, @"Employee",
        [NSPredicate predicateWithFormat:@"department.name == %@", @"Engineering"],
        sortByLastName());

    print(@"  %lu employee(s) in Engineering", (unsigned long)[engineers count]);

    [pool release];
    return 0;
}
