/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "NSPersistentStoreDescription.h"
#import <CoreData/NSPersistentStoreCoordinator.h>
#import <Foundation/Foundation.h>

@implementation NSPersistentStoreDescription

+(instancetype)persistentStoreDescriptionWithURL:(NSURL *)URL {
   return [[[self alloc] initWithURL:URL] autorelease];
}

-init {
   return [self initWithURL:nil];
}

-(instancetype)initWithURL:(NSURL *)URL {
   _type=[NSSQLiteStoreType copy];
   _configuration=nil;
   _URL=[URL retain];
   _options=[[NSMutableDictionary alloc] init];
   _shouldAddStoreAsynchronously=NO;
   _shouldMigrateStoreAutomatically=YES;
   _shouldInferMappingModelAutomatically=YES;
   return self;
}

-(void)dealloc {
   [_type release];
   [_configuration release];
   [_URL release];
   [_options release];
   [super dealloc];
}

-copyWithZone:(NSZone *)zone {
   NSPersistentStoreDescription *copy=[[NSPersistentStoreDescription allocWithZone:zone] initWithURL:_URL];

   [copy setType:_type];
   [copy setConfiguration:_configuration];
   [copy->_options addEntriesFromDictionary:_options];
   copy->_shouldAddStoreAsynchronously=_shouldAddStoreAsynchronously;
   copy->_shouldMigrateStoreAutomatically=_shouldMigrateStoreAutomatically;
   copy->_shouldInferMappingModelAutomatically=_shouldInferMappingModelAutomatically;
   return copy;
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<%@: %p type: %@, url: %@>",
       [self class],self,_type,_URL];
}

-(NSString *)type {
   return _type;
}

-(void)setType:(NSString *)type {
   type=[type copy];
   [_type release];
   _type=type;
}

-(NSString *)configuration {
   return _configuration;
}

-(void)setConfiguration:(NSString *)configuration {
   configuration=[configuration copy];
   [_configuration release];
   _configuration=configuration;
}

-(NSURL *)URL {
   return _URL;
}

-(void)setURL:(NSURL *)URL {
   URL=[URL retain];
   [_URL release];
   _URL=URL;
}

-(NSDictionary *)options {
   return [[_options copy] autorelease];
}

-(void)setOption:(NSObject *)option forKey:(NSString *)key {
   if(option==nil)
    [_options removeObjectForKey:key];
   else
    [_options setObject:option forKey:key];
}

-(BOOL)isReadOnly {
   return [[_options objectForKey:NSReadOnlyPersistentStoreOption] boolValue];
}

-(void)setReadOnly:(BOOL)flag {
   [self setOption:(flag?(NSObject *)[NSNumber numberWithBool:YES]:nil)
            forKey:NSReadOnlyPersistentStoreOption];
}

-(BOOL)shouldAddStoreAsynchronously {
   return _shouldAddStoreAsynchronously;
}

-(void)setShouldAddStoreAsynchronously:(BOOL)flag {
   _shouldAddStoreAsynchronously=flag;
}

-(BOOL)shouldMigrateStoreAutomatically {
   return _shouldMigrateStoreAutomatically;
}

-(void)setShouldMigrateStoreAutomatically:(BOOL)flag {
   _shouldMigrateStoreAutomatically=flag;
}

-(BOOL)shouldInferMappingModelAutomatically {
   return _shouldInferMappingModelAutomatically;
}

-(void)setShouldInferMappingModelAutomatically:(BOOL)flag {
   _shouldInferMappingModelAutomatically=flag;
}

@end
