/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSManagedObjectID.h>
#import <CoreData/NSEntityDescription.h>
#import <CoreData/NSManagedObjectModel.h>
#import "CoreDataUtilities.h"
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <CoreFoundation/CFUUID.h>

@implementation NSManagedObjectID

-initWithEntity:(NSEntityDescription *)entity {
   _entity=[entity retain];
   _isTemporaryID=YES;
   _storeIdentifier=nil;
   
   CFUUIDRef uuid=CFUUIDCreate(NULL);
   _referenceObject=(NSString *)CFUUIDCreateString(NULL,uuid);
   CFRelease(uuid);
   
   return self;
}

-(void)dealloc {
   [_entity release];
   [_storeIdentifier release];
   [_referenceObject release];
   [super dealloc];
}

/* NSManagedObjectID is hashed/equal by ptr value, they are uniqued per persistent store and should be the same instance for all
   references to the same underlying NSManagedObject
 */
 
-copyWithZone:(NSZone *)zone {
   return [self retain];
}

-(NSEntityDescription *)entity {
   return _entity;
}

-(NSString *)storeIdentifier {
   return _storeIdentifier;
}

-(BOOL)isTemporaryID {
   return _isTemporaryID;
}

-referenceObject {
   return _referenceObject;
}

-(NSURL *)URIRepresentation {
   NSString *path=[[_entity name] stringByAppendingPathComponent:_referenceObject];
   NSString *host=_isTemporaryID?@"":_storeIdentifier;
   
   return [[[NSURL alloc] initWithScheme:@"x-coredata" host:host path:path] autorelease];
}

-(NSPersistentStore *)persistentStore {
   return _persistentStore;
}

-(void)setStoreIdentifier:(NSString *)value {
   value=[value copy];
   [_storeIdentifier release];
   _storeIdentifier=value;
}

-(void)setReferenceObject:value {
   _isTemporaryID=NO;
   value=[value copy];
   [_referenceObject release];
   _referenceObject=value;
}

-(void)setPersistentStore:(NSPersistentStore *)store {
   _persistentStore=store;
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<%@ %p temp=%d, ref=%@>",
           NSStringFromClass([self class]),self,_isTemporaryID,_referenceObject];
}

@end
