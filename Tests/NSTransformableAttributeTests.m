/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/* NSTransformableAttributeTests - tests for NSTransformableAttributeType
   attributes.  These tests are written against Apple's documented behavior
   so they run identically against Apple's CoreData on macOS and against
   the GNUstep port; run them on macOS to validate assumptions about
   Apple's implementation.

   The documented behavior being verified (see the discussion of
   NSAttributeDescription.valueTransformerName and the archived
   "Non-Standard Persistent Attributes" chapter):

   - A transformable attribute holds any object conforming to NSCoding;
     CoreData converts it to NSData when saving and back when fetching.
   - With no valueTransformerName, a default transformer archives the
     value using NSCoding via keyed archiving
     (NSKeyedUnarchiveFromDataTransformerName is Apple's default).
   - A named custom transformer must return NSData from -transformedValue:
     and allow reverse transformation; it must be registered with
     +[NSValueTransformer setValueTransformer:forName:] before the store
     is used.  The built-in ...UnarchiveFromData... transformers work in
     the opposite direction and are applied in reverse.
   - The store holds an opaque blob, so a fetch predicate cannot evaluate
     the *contents* of a transformable attribute inside the store; the
     supported pattern is fetching and filtering in memory.
   - In-place mutation of a mutable transformable value is invisible to
     change tracking; the instance must be replaced for the change to be
     saved. */

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#include <string.h>

#if defined(__APPLE__)
/* On Apple the constants are provided by Foundation; asserting their
   values below documents that the literals used for GNUstep match.
   Note the runtime values are NOT the symbol names: verified on macOS,
   NSKeyedUnarchiveFromDataTransformerName is "NSKeyedUnarchiveFromData"
   (and the secure variant follows the same pattern, matching the names
   Xcode's model editor writes into the Transformer field). */
#define CDKeyedUnarchiveTransformerName NSKeyedUnarchiveFromDataTransformerName
#define CDSecureUnarchiveTransformerName NSSecureUnarchiveFromDataTransformerName
#else
#define CDKeyedUnarchiveTransformerName @"NSKeyedUnarchiveFromData"
#define CDSecureUnarchiveTransformerName @"NSSecureUnarchiveFromData"
#endif

/* ------------------------------------------------------------------ */
#pragma mark - A custom NSCoding class stored in a transformable attribute
/* ------------------------------------------------------------------ */

@interface CDTestColor : NSObject <NSSecureCoding>

@property (nonatomic, assign) double red;
@property (nonatomic, assign) double green;
@property (nonatomic, assign) double blue;

+ (instancetype)colorWithRed:(double)red green:(double)green blue:(double)blue;

@end

@implementation CDTestColor

+ (BOOL)supportsSecureCoding
{
    return YES;
}

+ (instancetype)colorWithRed:(double)red green:(double)green blue:(double)blue
{
    CDTestColor *color = [[self alloc] init];
    color.red = red;
    color.green = green;
    color.blue = blue;
    return color;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]) != nil) {
        _red = [coder decodeDoubleForKey:@"red"];
        _green = [coder decodeDoubleForKey:@"green"];
        _blue = [coder decodeDoubleForKey:@"blue"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeDouble:_red forKey:@"red"];
    [coder encodeDouble:_green forKey:@"green"];
    [coder encodeDouble:_blue forKey:@"blue"];
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[CDTestColor class]])
        return NO;
    CDTestColor *color = other;
    return _red == color.red && _green == color.green && _blue == color.blue;
}

- (NSUInteger)hash
{
    return (NSUInteger)(_red * 255) ^ (NSUInteger)(_green * 255) << 8
        ^ (NSUInteger)(_blue * 255) << 16;
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - A custom value transformer, per Apple's documented contract
/* ------------------------------------------------------------------ */

/* Marker bytes prepended by CDTestPrefixTransformer, distinctive enough
   to be located in the raw store file. */
static const char CDTestTransformerMagic[] = "CDXFORMv1";

/* Follows the contract in the valueTransformerName documentation:
   -transformedValue: converts the attribute value to NSData (called when
   saving) and -reverseTransformedValue: converts NSData back (called
   when fetching).  Invocations are counted so the tests can verify that
   CoreData actually routes values through the named transformer. */
@interface CDTestPrefixTransformer : NSValueTransformer

+ (NSUInteger)forwardCount;
+ (NSUInteger)reverseCount;
+ (void)resetCounts;

@end

static NSUInteger _prefixTransformerForwardCount = 0;
static NSUInteger _prefixTransformerReverseCount = 0;

@implementation CDTestPrefixTransformer

+ (NSUInteger)forwardCount
{
    return _prefixTransformerForwardCount;
}

+ (NSUInteger)reverseCount
{
    return _prefixTransformerReverseCount;
}

+ (void)resetCounts
{
    _prefixTransformerForwardCount = 0;
    _prefixTransformerReverseCount = 0;
}

+ (Class)transformedValueClass
{
    return [NSData class];
}

+ (BOOL)allowsReverseTransformation
{
    return YES;
}

- (id)transformedValue:(id)value
{
    if (value == nil)
        return nil;

    _prefixTransformerForwardCount++;

    NSMutableData *data =
        [NSMutableData dataWithBytes:CDTestTransformerMagic
                              length:sizeof(CDTestTransformerMagic) - 1];
    [data appendData:[NSKeyedArchiver archivedDataWithRootObject:value]];
    return data;
}

- (id)reverseTransformedValue:(id)value
{
    NSUInteger magicLength = sizeof(CDTestTransformerMagic) - 1;

    if (![value isKindOfClass:[NSData class]] || [value length] < magicLength)
        return nil;
    if (memcmp([value bytes], CDTestTransformerMagic, magicLength) != 0)
        return nil;

    _prefixTransformerReverseCount++;

    NSData *archive = [value subdataWithRange:
        NSMakeRange(magicLength, [value length] - magicLength)];
    return [NSKeyedUnarchiver unarchiveObjectWithData:archive];
}

@end

/* ------------------------------------------------------------------ */
#pragma mark - Test case
/* ------------------------------------------------------------------ */

/* Item(name: string, payload: transformable). */
static NSManagedObjectModel *transformableModel(NSString *transformerName,
                                                id defaultValue)
{
    NSAttributeDescription *name = [[NSAttributeDescription alloc] init];
    [name setName:@"name"];
    [name setAttributeType:NSStringAttributeType];
    [name setOptional:YES];

    NSAttributeDescription *payload = [[NSAttributeDescription alloc] init];
    [payload setName:@"payload"];
    [payload setAttributeType:NSTransformableAttributeType];
    [payload setOptional:YES];
    if (transformerName != nil)
        [payload setValueTransformerName:transformerName];
    if (defaultValue != nil)
        [payload setDefaultValue:defaultValue];

    NSEntityDescription *item = [[NSEntityDescription alloc] init];
    [item setName:@"Item"];
    [item setManagedObjectClassName:@"NSManagedObject"];
    [item setProperties:[NSArray arrayWithObjects:name, payload, nil]];

    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    [model setEntities:[NSArray arrayWithObject:item]];
    return model;
}

@interface NSTransformableAttributeTests : XCTestCase

@property (nonatomic, strong) NSURL *storeURL;

@end

@implementation NSTransformableAttributeTests

- (void)setUp
{
    NSString *fileName = [[[NSProcessInfo processInfo] globallyUniqueString]
                             stringByAppendingPathExtension:@"store"];
    self.storeURL = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];

    /* Apple requires custom transformers to be registered before the
       persistent store stack that uses them is set up. */
    if ([NSValueTransformer valueTransformerForName:
            @"CDTestPrefixTransformer"] == nil)
        [NSValueTransformer setValueTransformer:
                                [[CDTestPrefixTransformer alloc] init]
                                        forName:@"CDTestPrefixTransformer"];
    [CDTestPrefixTransformer resetCounts];
}

- (void)tearDown
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    [fileManager removeItemAtURL:self.storeURL error:NULL];
    /* Apple's SQLite store may leave WAL/SHM journal files behind. */
    [fileManager removeItemAtPath:[[self.storeURL path]
                                      stringByAppendingString:@"-wal"]
                            error:NULL];
    [fileManager removeItemAtPath:[[self.storeURL path]
                                      stringByAppendingString:@"-shm"]
                            error:NULL];
    self.storeURL = nil;
}

/* Builds a fresh coordinator + context stack on top of the store at
   `storeURL`, simulating an independent application run. */
- (NSManagedObjectContext *)contextWithModel:(NSManagedObjectModel *)model
                                   storeType:(NSString *)storeType
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc]
        initWithManagedObjectModel:model];
    NSError *error = nil;
    NSPersistentStore *store = [psc addPersistentStoreWithType:storeType
                                                 configuration:nil
                                                           URL:self.storeURL
                                                       options:nil
                                                         error:&error];
    XCTAssertNotNil(store, @"failed to add %@ store: %@", storeType, error);

    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] init];
    [ctx setPersistentStoreCoordinator:psc];
    return ctx;
}

- (NSManagedObject *)insertItemNamed:(NSString *)name
                             payload:(id)payload
                           inContext:(NSManagedObjectContext *)ctx
{
    NSManagedObject *item =
        [NSEntityDescription insertNewObjectForEntityForName:@"Item"
                                      inManagedObjectContext:ctx];
    [item setValue:name forKey:@"name"];
    if (payload != nil)
        [item setValue:payload forKey:@"payload"];
    return item;
}

- (NSArray *)fetchItemsInContext:(NSManagedObjectContext *)ctx
{
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    [fetch setEntity:[NSEntityDescription entityForName:@"Item"
                                 inManagedObjectContext:ctx]];
    [fetch setSortDescriptors:[NSArray arrayWithObject:
        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];

    NSError *error = nil;
    NSArray *result = [ctx executeFetchRequest:fetch error:&error];
    XCTAssertNotNil(result, @"fetch failed: %@", error);
    return result;
}

/* Round-trips one custom object and one collection through a freshly
   reopened store of the given type using the given transformer name. */
- (void)verifyRoundTripWithStoreType:(NSString *)storeType
                     transformerName:(NSString *)transformerName
{
    NSManagedObjectModel *(^model)(void) = ^{
        return transformableModel(transformerName, nil);
    };

    CDTestColor *color = [CDTestColor colorWithRed:0.25 green:0.5 blue:0.75];
    NSArray *collection = [NSArray arrayWithObjects:@"alpha",
        [NSNumber numberWithInt:42],
        [NSDate dateWithTimeIntervalSinceReferenceDate:1000], nil];

    NSManagedObjectContext *ctx = [self contextWithModel:model()
                                               storeType:storeType];
    [self insertItemNamed:@"a-color" payload:color inContext:ctx];
    [self insertItemNamed:@"b-collection" payload:collection inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* Reopen with a fresh stack so the values must come from the store. */
    NSManagedObjectContext *ctx2 = [self contextWithModel:model()
                                                storeType:storeType];
    NSArray *items = [self fetchItemsInContext:ctx2];
    XCTAssertEqual([items count], (NSUInteger)2);

    id fetchedColor = [[items objectAtIndex:0] valueForKey:@"payload"];
    XCTAssertTrue([fetchedColor isKindOfClass:[CDTestColor class]],
                  @"fetched %@", [fetchedColor class]);
    XCTAssertEqualObjects(fetchedColor, color);

    id fetchedCollection = [[items objectAtIndex:1] valueForKey:@"payload"];
    XCTAssertTrue([fetchedCollection isKindOfClass:[NSArray class]],
                  @"fetched %@", [fetchedCollection class]);
    XCTAssertEqualObjects(fetchedCollection, collection);
}

/* ------------------------------------------------------------------ */
#pragma mark - NSAttributeDescription API
/* ------------------------------------------------------------------ */

- (void)testTransformableAttributeDescriptionAPI
{
    NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];

    XCTAssertNil([attribute valueTransformerName],
                 @"a new attribute has no transformer name");

    [attribute setName:@"payload"];
    [attribute setAttributeType:NSTransformableAttributeType];
    XCTAssertEqual([attribute attributeType], NSTransformableAttributeType);
    XCTAssertEqual((int)NSTransformableAttributeType, 1800);

    [attribute setValueTransformerName:@"CDTestPrefixTransformer"];
    XCTAssertEqualObjects([attribute valueTransformerName],
                          @"CDTestPrefixTransformer");

    [attribute setAttributeValueClassName:@"CDTestColor"];
    XCTAssertEqualObjects([attribute attributeValueClassName],
                          @"CDTestColor");

#if defined(__APPLE__)
    /* Verifies on macOS that the literals used on GNUstep match Apple's
       constants (verified: the values are the short forms, without the
       "TransformerName" suffix). */
    XCTAssertEqualObjects(NSKeyedUnarchiveFromDataTransformerName,
                          @"NSKeyedUnarchiveFromData");
    XCTAssertEqualObjects(NSSecureUnarchiveFromDataTransformerName,
                          @"NSSecureUnarchiveFromData");
#endif
}

/* ------------------------------------------------------------------ */
#pragma mark - Default (NSCoding keyed archiving) transformer
/* ------------------------------------------------------------------ */

- (void)testDefaultTransformerRoundTripsThroughSQLiteStore
{
    [self verifyRoundTripWithStoreType:NSSQLiteStoreType transformerName:nil];
}

- (void)testDefaultTransformerRoundTripsThroughXMLStore
{
    [self verifyRoundTripWithStoreType:NSXMLStoreType transformerName:nil];
}

- (void)testDefaultTransformerStoresKeyedArchiveBlobInSQLite
{
    NSManagedObjectContext *ctx =
        [self contextWithModel:transformableModel(nil, nil)
                     storeType:NSSQLiteStoreType];
    CDTestColor *color = [CDTestColor colorWithRed:0.1 green:0.2 blue:0.3];

    [self insertItemNamed:@"raw" payload:color inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* The class name of the archived object appears verbatim inside the
       keyed archive, so the raw store file (or its WAL journal) must
       contain it: the store holds an NSCoding archive of the value, not
       some other representation of the object. */
    XCTAssertTrue([self storeFilesContainBytes:"CDTestColor"
                                        length:strlen("CDTestColor")],
                  @"expected a keyed archive of CDTestColor in the store file");
}

- (void)testExplicitSecureUnarchiveTransformerNameRoundTrips
{
    /* The built-in unarchiving transformers can be requested by name; they
       transform data to object, so CoreData applies them in reverse when
       saving.  The secure variant is the one Apple currently supports by
       explicit name.  Its allowedTopLevelClasses only covers the property
       list classes, so the payload here sticks to those (a custom class
       would need an NSSecureUnarchiveFromDataTransformer subclass, which
       GNUstep-base does not provide yet). */
    NSArray *collection = [NSArray arrayWithObjects:@"alpha",
        [NSNumber numberWithInt:42],
        [NSDate dateWithTimeIntervalSinceReferenceDate:1000], nil];

    NSManagedObjectContext *ctx = [self contextWithModel:
            transformableModel(CDSecureUnarchiveTransformerName, nil)
                                               storeType:NSSQLiteStoreType];
    [self insertItemNamed:@"secure" payload:collection inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:
            transformableModel(CDSecureUnarchiveTransformerName, nil)
                                                storeType:NSSQLiteStoreType];
    NSArray *items = [self fetchItemsInContext:ctx2];
    XCTAssertEqual([items count], (NSUInteger)1);
    XCTAssertEqualObjects([[items objectAtIndex:0] valueForKey:@"payload"],
                          collection);
}

#if !defined(__APPLE__)
- (void)testExplicitKeyedUnarchiveTransformerNameRoundTrips
{
    /* The legacy keyed-unarchiving transformer name also still works on
       GNUstep.  This test is skipped on Apple: verified on macOS
       (2026-08), explicitly naming the deprecated transformer makes the
       shared NSKeyedUnarchiveFromData transformer throw while encoding
       ("'NSKeyedUnarchiveFromData' should not be used to for
       un-archiving and will be removed in a future release") and the
       save fails with NSCocoaErrorDomain error 134060 - even though the
       nil default still archives the same way. */
    [self verifyRoundTripWithStoreType:NSSQLiteStoreType
                       transformerName:CDKeyedUnarchiveTransformerName];
}
#endif

/* ------------------------------------------------------------------ */
#pragma mark - Custom value transformer
/* ------------------------------------------------------------------ */

- (BOOL)storeFilesContainBytes:(const char *)bytes length:(size_t)length
{
    NSArray *paths = [NSArray arrayWithObjects:
        [self.storeURL path],
        [[self.storeURL path] stringByAppendingString:@"-wal"],
        nil];

    for (NSString *path in paths) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        const char *fileBytes = [data bytes];
        NSUInteger fileLength = [data length];
        NSUInteger i;

        if (fileLength < length)
            continue;
        for (i = 0; i + length <= fileLength; i++)
            if (memcmp(fileBytes + i, bytes, length) == 0)
                return YES;
    }
    return NO;
}

- (void)testCustomTransformerIsUsedBySQLiteStore
{
    NSString *transformerName = @"CDTestPrefixTransformer";
    CDTestColor *color = [CDTestColor colorWithRed:0.5 green:0.25 blue:1.0];

    NSManagedObjectContext *ctx =
        [self contextWithModel:transformableModel(transformerName, nil)
                     storeType:NSSQLiteStoreType];
    [self insertItemNamed:@"custom" payload:color inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* Saving must have gone through -transformedValue: (object to data),
       per the documented custom-transformer contract. */
    XCTAssertTrue([CDTestPrefixTransformer forwardCount] >= 1,
                  @"custom transformer was not asked to transform on save");

    /* The transformer's output is stored verbatim: its marker bytes are
       present in the raw store file (or its WAL journal). */
    XCTAssertTrue([self storeFilesContainBytes:CDTestTransformerMagic
                                        length:sizeof(CDTestTransformerMagic) - 1],
                  @"expected the custom transformer's bytes in the store file");

    /* Fetching from a fresh stack must go through
       -reverseTransformedValue: (data to object). */
    NSUInteger reverseBefore = [CDTestPrefixTransformer reverseCount];
    NSManagedObjectContext *ctx2 =
        [self contextWithModel:transformableModel(transformerName, nil)
                     storeType:NSSQLiteStoreType];
    NSArray *items = [self fetchItemsInContext:ctx2];

    XCTAssertEqual([items count], (NSUInteger)1);
    XCTAssertEqualObjects([[items objectAtIndex:0] valueForKey:@"payload"],
                          color);
    XCTAssertTrue([CDTestPrefixTransformer reverseCount] > reverseBefore,
                  @"custom transformer was not asked to reverse on fetch");
}

- (void)testCustomTransformerIsUsedByXMLStore
{
    NSString *transformerName = @"CDTestPrefixTransformer";
    CDTestColor *color = [CDTestColor colorWithRed:0.75 green:0.5 blue:0.25];

    NSManagedObjectContext *ctx =
        [self contextWithModel:transformableModel(transformerName, nil)
                     storeType:NSXMLStoreType];
    [self insertItemNamed:@"custom-xml" payload:color inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);
    XCTAssertTrue([CDTestPrefixTransformer forwardCount] >= 1,
                  @"custom transformer was not asked to transform on save");

    NSUInteger reverseBefore = [CDTestPrefixTransformer reverseCount];
    NSManagedObjectContext *ctx2 =
        [self contextWithModel:transformableModel(transformerName, nil)
                     storeType:NSXMLStoreType];
    NSArray *items = [self fetchItemsInContext:ctx2];

    XCTAssertEqual([items count], (NSUInteger)1);
    XCTAssertEqualObjects([[items objectAtIndex:0] valueForKey:@"payload"],
                          color);
    XCTAssertTrue([CDTestPrefixTransformer reverseCount] > reverseBefore,
                  @"custom transformer was not asked to reverse on fetch");
}

/* ------------------------------------------------------------------ */
#pragma mark - In-memory store
/* ------------------------------------------------------------------ */

- (void)testTransformableRoundTripsThroughInMemoryStore
{
    NSManagedObjectModel *model = transformableModel(nil, nil);
    NSManagedObjectContext *ctx = [self contextWithModel:model
                                               storeType:NSInMemoryStoreType];
    CDTestColor *color = [CDTestColor colorWithRed:0.3 green:0.6 blue:0.9];

    [self insertItemNamed:@"memory" payload:color inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* A second context on the same coordinator sees the saved value. */
    NSManagedObjectContext *ctx2 = [[NSManagedObjectContext alloc] init];
    [ctx2 setPersistentStoreCoordinator:[ctx persistentStoreCoordinator]];

    NSArray *items = [self fetchItemsInContext:ctx2];
    XCTAssertEqual([items count], (NSUInteger)1);
    XCTAssertEqualObjects([[items objectAtIndex:0] valueForKey:@"payload"],
                          color);
}

/* ------------------------------------------------------------------ */
#pragma mark - Predicate limitation
/* ------------------------------------------------------------------ */

- (void)testTransformableContentsAreFilteredInMemoryAfterFetching
{
    /* The store persists a transformable attribute as an opaque blob, so
       a fetch request's predicate cannot evaluate the *contents* of the
       value inside the store.  The supported pattern is to fetch the
       candidate objects and filter in memory. */
    NSManagedObjectModel *(^model)(void) = ^{
        return transformableModel(nil, nil);
    };

    NSManagedObjectContext *ctx = [self contextWithModel:model()
                                               storeType:NSSQLiteStoreType];
    [self insertItemNamed:@"a"
                  payload:[NSArray arrayWithObjects:@"red", @"green", nil]
                inContext:ctx];
    [self insertItemNamed:@"b"
                  payload:[NSArray arrayWithObjects:@"blue", nil]
                inContext:ctx];
    [self insertItemNamed:@"c" payload:nil inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:model()
                                                storeType:NSSQLiteStoreType];
    NSArray *everything = [self fetchItemsInContext:ctx2];
    XCTAssertEqual([everything count], (NSUInteger)3);

    NSPredicate *containsBlue = [NSPredicate predicateWithBlock:
        ^BOOL(id item, NSDictionary *bindings) {
            return [[item valueForKey:@"payload"] containsObject:@"blue"];
        }];
    NSArray *matches = [everything filteredArrayUsingPredicate:containsBlue];

    XCTAssertEqual([matches count], (NSUInteger)1);
    XCTAssertEqualObjects([[matches lastObject] valueForKey:@"name"], @"b");
}

/* ------------------------------------------------------------------ */
#pragma mark - Mutability caveat
/* ------------------------------------------------------------------ */

- (void)testInPlaceMutationOfMutableValueIsNotDetected
{
    NSManagedObjectModel *(^model)(void) = ^{
        return transformableModel(nil, nil);
    };

    NSManagedObjectContext *ctx = [self contextWithModel:model()
                                               storeType:NSSQLiteStoreType];
    NSMutableArray *payload =
        [NSMutableArray arrayWithObject:@"first"];
    [self insertItemNamed:@"mutable" payload:payload inContext:ctx];

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    /* Mutating the stored object in place does not go through KVC, so
       change tracking cannot see it... */
    [payload addObject:@"second"];
    XCTAssertFalse([ctx hasChanges],
                   @"in-place mutation must not register as a change");
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:model()
                                                storeType:NSSQLiteStoreType];
    NSArray *items = [self fetchItemsInContext:ctx2];
    XCTAssertEqual([[[items lastObject] valueForKey:@"payload"] count],
                   (NSUInteger)1,
                   @"the in-place mutation must not have been saved");

    /* ...so the fix is to never mutate in place and instead replace the
       value with a new instance.  This is done here on the freshly
       fetched object: verified on macOS, replacing the value in the
       ORIGINAL context after an in-place mutation is not saved either,
       because the row-cache snapshot holds the same mutated instance and
       the replacement compares equal to it, so Apple optimizes the
       update away.  In-place mutation poisons the snapshot; the only
       safe pattern is replacement from the start. */
    NSManagedObject *fresh = [items lastObject];
    [fresh setValue:[NSArray arrayWithObjects:@"first", @"second", nil]
             forKey:@"payload"];
    XCTAssertTrue([ctx2 hasChanges]);
    XCTAssertTrue([ctx2 save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx3 = [self contextWithModel:model()
                                                storeType:NSSQLiteStoreType];
    items = [self fetchItemsInContext:ctx3];
    XCTAssertEqual([[[items lastObject] valueForKey:@"payload"] count],
                   (NSUInteger)2,
                   @"replacing the value instance must be saved");
}

/* ------------------------------------------------------------------ */
#pragma mark - nil values and default values
/* ------------------------------------------------------------------ */

- (void)testNilAndDefaultTransformableValues
{
    CDTestColor *defaultColor = [CDTestColor colorWithRed:1 green:1 blue:1];
    NSManagedObjectModel *(^model)(void) = ^{
        return transformableModel(nil, defaultColor);
    };

    NSManagedObjectContext *ctx = [self contextWithModel:model()
                                               storeType:NSSQLiteStoreType];

    /* The model's default value is visible immediately after insertion. */
    NSManagedObject *withDefault = [self insertItemNamed:@"a-default"
                                                 payload:nil
                                               inContext:ctx];
    XCTAssertEqualObjects([withDefault valueForKey:@"payload"], defaultColor);

    /* An explicit nil overrides the default. */
    NSManagedObject *withNil = [self insertItemNamed:@"b-nil"
                                             payload:nil
                                           inContext:ctx];
    [withNil setValue:nil forKey:@"payload"];
    XCTAssertNil([withNil valueForKey:@"payload"]);

    NSError *error = nil;
    XCTAssertTrue([ctx save:&error], @"save failed: %@", error);

    NSManagedObjectContext *ctx2 = [self contextWithModel:model()
                                                storeType:NSSQLiteStoreType];
    NSArray *items = [self fetchItemsInContext:ctx2];
    XCTAssertEqual([items count], (NSUInteger)2);
    XCTAssertEqualObjects([[items objectAtIndex:0] valueForKey:@"payload"],
                          defaultColor);
    XCTAssertNil([[items objectAtIndex:1] valueForKey:@"payload"]);
}

@end
