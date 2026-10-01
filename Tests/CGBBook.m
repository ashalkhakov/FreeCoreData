/* Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */

#import "CGBBook+CoreDataProperties.h"
#import "CGBAuthor+CoreDataClass.h"

@implementation CGBBook

- (NSString *)summary
{
   return [NSString stringWithFormat:@"%@, %d pages, by %@",self.title,self.pages,self.author.name];
}

@end
