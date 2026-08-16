/* This file is part of the CoreData framework port for GNUstep.
   Ported from the Cocotron project (https://github.com/cjwl/cocotron).

   Copyright (c) 2006-2009 Christopher J. W. Lloyd <cjwl@objc.net>
   Copyright (c) 2008 Dan Knapp

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>

@class NSPersistentStoreCoordinator, NSURL, NSDictionary, NSError;

@interface NSPersistentStore : NSObject {
    NSPersistentStoreCoordinator *_coordinator;
    NSString *_configurationName;
    NSURL *_url;
    NSDictionary *_options;
    BOOL _isReadOnly;
    NSString *_identifier;
}

+ (NSDictionary *)metadataForPersistentStoreWithURL:(NSURL *)url error:(NSError **)error;
+ (BOOL)setMetadata:(NSDictionary *)metadata forPersistentStoreWithURL:(NSURL *)url error:(NSError **)error;

+ (Class)migrationManagerClass;

- initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root configurationName:(NSString *)name URL:(NSURL *)url options:(NSDictionary *)options;

- (NSString *)type;
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator;
- (NSString *)configurationName;
- (NSURL *)URL;
- (NSDictionary *)options;

- (BOOL)isReadOnly;
- (NSString *)identifier;
- (NSDictionary *)metadata;

- (void)setURL:(NSURL *)value;
- (void)setReadOnly:(BOOL)value;
- (void)setIdentifier:(NSString *)value;
- (void)setMetadata:(NSDictionary *)value;

- (BOOL)loadMetadata:(NSError **)error;

- (void)willRemoveFromPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator;
- (void)didAddToPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator;

@end
