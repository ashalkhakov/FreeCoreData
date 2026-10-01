/* Build-time code generation (coredata-model.make, <target>_COREDATA_CODEGEN):
   CodegenFixture's classes are generated as this bundle builds, and used
   here through their typed properties -- a Class Definition entity's
   whole class, and a Category/Extension entity's properties on the class
   written by hand.  On macOS, Xcode does the same from the same marks.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "CGBAuthor+CoreDataClass.h"
#import "CGBBook+CoreDataProperties.h"

@interface CodegenBuildTests : XCTestCase
@end

@implementation CodegenBuildTests

- (NSManagedObjectContext *)context
{
   NSURL *url=[[NSBundle bundleForClass:[self class]] URLForResource:@"CodegenFixture" withExtension:@"momd"];
   NSManagedObjectModel *model=[[NSManagedObjectModel alloc] initWithContentsOfURL:url];
   XCTAssertNotNil(model,@"CodegenFixture.momd in the bundle");
   NSPersistentStoreCoordinator *coordinator=[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
   NSError *error=nil;
   XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil
                                                   options:nil error:&error],@"%@",error);
   NSManagedObjectContext *context=[[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
   context.persistentStoreCoordinator=coordinator;
   return context;
}

- (void)testGeneratedClassesAreTheEntitiesClasses
{
   NSManagedObjectContext *context=[self context];
   CGBAuthor *author=[NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:context];
   CGBBook *book=[NSEntityDescription insertNewObjectForEntityForName:@"Book" inManagedObjectContext:context];
   XCTAssertTrue([author isKindOfClass:[CGBAuthor class]]);
   XCTAssertTrue([book isKindOfClass:[CGBBook class]]);

   author.name=@"Ann";
   book.title=@"Tea";
   book.pages=120;
   book.author=author;
   XCTAssertEqualObjects(author.books,[NSSet setWithObject:book],@"the inverse, through the generated accessor");
   XCTAssertEqualObjects([book summary],@"Tea, 120 pages, by Ann",@"the hand-written method sees the generated properties");

   NSError *error=nil;
   XCTAssertTrue([context save:&error],@"%@",error);
   NSFetchRequest *fetch=[CGBBook fetchRequest];
   XCTAssertEqualObjects(fetch.entityName,@"Book");
   XCTAssertEqual([[context executeFetchRequest:fetch error:&error] count],(NSUInteger)1,@"%@",error);
}

@end
