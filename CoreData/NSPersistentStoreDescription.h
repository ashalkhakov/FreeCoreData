/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <Foundation/NSObject.h>
#import <CoreData/CoreDataExports.h>

@class NSString, NSURL, NSDictionary, NSMutableDictionary;

/* A description of a persistent store to be added to a coordinator by
   NSPersistentContainer: type, location, configuration and the option
   dictionary handed to addPersistentStoreWithType:..., plus the
   container-level loading behaviors. */
@interface NSPersistentStoreDescription : NSObject <NSCopying> {
    NSString *_type;
    NSString *_configuration;
    NSURL *_URL;
    NSMutableDictionary *_options;
    BOOL _shouldAddStoreAsynchronously;
    BOOL _shouldMigrateStoreAutomatically;
    BOOL _shouldInferMappingModelAutomatically;
}

+ (instancetype)persistentStoreDescriptionWithURL:(NSURL *)URL;
- (instancetype)initWithURL:(NSURL *)URL;

- (NSString *)type;                       /* default NSSQLiteStoreType */
- (void)setType:(NSString *)type;
- (NSString *)configuration;
- (void)setConfiguration:(NSString *)configuration;
- (NSURL *)URL;
- (void)setURL:(NSURL *)URL;

- (NSDictionary *)options;
- (void)setOption:(NSObject *)option forKey:(NSString *)key;

/* Backed by NSReadOnlyPersistentStoreOption in the options. */
- (BOOL)isReadOnly;
- (void)setReadOnly:(BOOL)flag;

/* Loading behaviors; Apple's defaults: add synchronously, migrate
   automatically, infer the mapping model automatically. */
- (BOOL)shouldAddStoreAsynchronously;
- (void)setShouldAddStoreAsynchronously:(BOOL)flag;
- (BOOL)shouldMigrateStoreAutomatically;
- (void)setShouldMigrateStoreAutomatically:(BOOL)flag;
- (BOOL)shouldInferMappingModelAutomatically;
- (void)setShouldInferMappingModelAutomatically:(BOOL)flag;

@end
