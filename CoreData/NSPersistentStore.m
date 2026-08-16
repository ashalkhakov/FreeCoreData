/* Copyright (c) 2008 Dan Knapp
   Portions Copyright (c) Christopher J. W. Lloyd / Cocotron Project (https://github.com/cjwl/cocotron)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <CoreData/NSPersistentStore.h>
#import <CoreData/NSPersistentStoreCoordinator.h>
#import "CoreDataUtilities.h"
#import <Foundation/NSDictionary.h>
#import <CoreFoundation/CFUUID.h>

@implementation NSPersistentStore

+(NSDictionary *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error {
   NSInvalidAbstractInvocation();
   return nil;
}

+(BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreWithURL:(NSURL *)url error:(NSError **)error {
   NSInvalidAbstractInvocation();
   return 0;
}

+(Class)migrationManagerClass {
   NSUnimplementedMethod();
   return 0;
}

-initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root configurationName:(NSString *)name URL:(NSURL *)url options:(NSDictionary *)options {
   _coordinator=root;
   _configurationName=[name copy];
   _url=[url copy];
   _options=[options copy];
   _isReadOnly=NO;
   CFUUIDRef uuid=CFUUIDCreate(NULL);
   _identifier=(NSString *)CFUUIDCreateString(NULL,uuid);
   CFRelease(uuid);
   
   return self;
}

-(void)dealloc {
   [_identifier release];
   [super dealloc];
}

-(NSString *)type {
   NSInvalidAbstractInvocation();
   return nil;
}

-(NSPersistentStoreCoordinator *)persistentStoreCoordinator {
   return _coordinator;
}

-(NSString *)configurationName {
   return _configurationName;
}

-(NSURL *)URL {
   return _url;
}

-(NSDictionary *)options {
   return _options;
}

-(BOOL)isReadOnly {
   return _isReadOnly;
}

-(NSString *)identifier {
   return _identifier;
}

-(NSDictionary *)metadata {
   return [NSDictionary dictionaryWithObjectsAndKeys:[self identifier],NSStoreUUIDKey,[self type],NSStoreTypeKey,nil];
}

-(void)setURL:(NSURL *)value {
   value=[value copy];
   [_url release];
   _url=value;
}

-(void)setReadOnly:(BOOL)value {
   NSUnimplementedMethod();
}

-(void)setIdentifier:(NSString *)value {
   value=[value copy];
   [_identifier release];
   _identifier=value;
}

-(void)setMetadata:(NSDictionary *)value {
   NSUnimplementedMethod();
}

-(BOOL)loadMetadata:(NSError **)error {
   NSUnimplementedMethod();
   return NO;
}

-(void)willRemoveFromPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator {
}

-(void)didAddToPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator {
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<%@ %p URL=%@>",NSStringFromClass([self class]),self,[self URL]];
}

@end
