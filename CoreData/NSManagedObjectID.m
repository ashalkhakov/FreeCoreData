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
#import <Foundation/NSUUID.h>

@implementation NSManagedObjectID

-initWithEntity:(NSEntityDescription *)entity {
   _entity=[entity retain];
   _isTemporaryID=YES;
   _storeIdentifier=nil;
   
   _referenceObject=[[[NSUUID UUID] UUIDString] copy];
   
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

/* The reference object may be any copyable value - Apple's stores use
   numbers and strings, and custom incremental stores may use data (an
   OData-backed store keying rows by JSON, for example).  Verified on
   macOS: Apple's URI carries "p" + the reference's -description for
   every reference type (no special hex form for NSData), escaped with
   standard URL *path* rules - so spaces and braces are percent-escaped
   while "/" survives, and a reference containing "/" therefore spans
   path components (and comes back with its escapes intact, exactly as
   Apple's does). */
static NSString *URIComponentFromReferenceObject(id reference){
   NSString *string=[@"p" stringByAppendingString:[reference description]];

   return [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
}

-(NSURL *)URIRepresentation {
   NSString *host=_isTemporaryID?@"":_storeIdentifier;
   NSString *string=[NSString stringWithFormat:@"x-coredata://%@/%@/%@",
      (host!=nil)?host:@"",
      [[_entity name] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]],
      URIComponentFromReferenceObject(_referenceObject)];

   return [NSURL URLWithString:string];
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
