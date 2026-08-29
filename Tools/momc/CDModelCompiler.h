/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/Foundation.h>

@class NSManagedObjectModel;
@class NSAttributeDescription;
@class NSEntityDescription;

extern NSString * const CDModelCompilerErrorDomain;

/* Compiles Xcode data model sources (.xcdatamodeld / .xcdatamodel)
   into the runtime form FreeCoreData loads (.momd / .mom).  The momc
   command-line tool is a thin wrapper around this class; it is kept
   separate so other tooling can embed the compiler.

   The compiler parses the model's `contents` XML, builds an
   NSManagedObjectModel with the framework's own description classes,
   and archives it - so what it writes is by construction what the
   runtime reads. */
@interface CDModelCompiler : NSObject

/* Non-fatal findings (an ordered relationship compiled as unordered,
   a UUID attribute compiled as String, ...) are reported here as they
   are encountered; when nil they are dropped. */
+ (void)setWarningHandler:(void (^)(NSString *message))handler;

/* One .xcdatamodel version directory -> the model it describes. */
+ (NSManagedObjectModel *)compileModelAtPath:(NSString *)xcdatamodelPath
                                       error:(NSError **)error;

/* Full source-to-artifact compilation:
     Model.xcdatamodeld -> Model.momd   (every version, VersionInfo.plist)
     Model.xcdatamodel  -> Model.mom    (single archived model)
   Returns NO with a descriptive error on any failure. */
+ (BOOL)compileModelSourceAtPath:(NSString *)sourcePath
                          toPath:(NSString *)destinationPath
                           error:(NSError **)error;

/* One .xcdatamodel contents XML string -> the model it describes.
   The editor's load path (documents arrive as file wrappers, not
   always as paths). */
+ (NSManagedObjectModel *)compileModelContentsXML:(NSString *)xml
                                            error:(NSError **)error;

/* Schema vocabulary, for tooling that presents it (the ModelBuilder
   editor): Xcode's attribute type spellings in menu order, and the
   mapping to/from NSAttributeType.  attributeTypeNamed: returns
   NSNotFound-like -1 for an unknown spelling. */
+ (NSArray *)attributeTypeNames;
+ (NSInteger)attributeTypeNamed:(NSString *)name;
+ (NSString *)nameForAttributeType:(NSInteger)type;

/* Xcode's deletion rule spellings in menu order, and the mapping to
   NSDeleteRule. */
+ (NSArray *)deleteRuleNames;

/* Validation vocabulary for tooling.  Xcode's min/max/regex fields
   compile to a small set of canonical predicate shapes; these two
   methods are the single implementation shared by the compiler, the
   serializer and the ModelBuilder inspector.  Info keys, all optional:
     @"min", @"max"             numeric bounds (strings, parsed per type)
     @"minLength", @"maxLength" string length bounds (strings)
     @"regex"                   regularExpressionString
     @"minDate", @"maxDate"     date bounds (NSDate)
   applyValidationInfo: REPLACES the attribute's validation predicates
   with the canonical shapes; validationInfoForAttribute: recognizes
   them by their paired warning codes (foreign predicates are kept but
   not reported). */
+ (NSDictionary *)validationInfoForAttribute:(NSAttributeDescription *)attribute;
+ (void)applyValidationInfo:(NSDictionary *)info
                toAttribute:(NSAttributeDescription *)attribute;

/* usesScalarValueType is codegen metadata with no Apple model API;
   it rides on the attribute via associated storage so it survives
   serialize/compile round trips identically on both platforms. */
+ (BOOL)attributeUsesScalarValueType:(NSAttributeDescription *)attribute;
+ (void)setAttribute:(NSAttributeDescription *)attribute
 usesScalarValueType:(BOOL)flag;

/* codeGenerationType is likewise codegen metadata (Xcode's Codegen
   popup): @"class" (Class Definition), @"category" (Category/
   Extension), or nil (Manual/None, absent from the XML).  Values other
   than the two known spellings are preserved verbatim. */
+ (NSString *)entityCodeGenerationType:(NSEntityDescription *)entity;
+ (void)setEntity:(NSEntityDescription *)entity
 codeGenerationType:(NSString *)type;

/* Parses Xcode's derivationExpression spelling ("uppercase:(title)",
   "now()", a bare key path) into the expression the runtime evaluates. */
+ (NSExpression *)derivationExpressionFromString:(NSString *)string
                                           error:(NSError **)error;

@end
