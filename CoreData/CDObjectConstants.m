/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "CDObjectConstants-Private.h"
#import <CoreData/NSManagedObject.h>
#import <CoreData/NSManagedObjectID.h>

typedef struct {
   CDObjectIDReplacement replace;
   void *context;
} CDReplacement;

static id CDReplacedConstant(id value,CDReplacement *replacement,BOOL *changed){
   if([value isKindOfClass:[NSManagedObject class]])
    value=[(NSManagedObject *)value objectID];

   if([value isKindOfClass:[NSManagedObjectID class]]){
    id counterpart=replacement->replace((NSManagedObjectID *)value,replacement->context);

    *changed=YES;
    /* An object nothing equals: no row matches it, every row differs. */
    return (counterpart!=nil)?counterpart:[[[NSObject alloc] init] autorelease];
   }

   if([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]] ||
      [value isKindOfClass:[NSOrderedSet class]]){
    NSMutableArray *elements=[NSMutableArray array];
    BOOL any=NO;

    for(id element in value)
     [elements addObject:CDReplacedConstant(element,replacement,&any)];
    if(!any)
     return value;
    *changed=YES;
    if([value isKindOfClass:[NSSet class]])
     return [NSSet setWithArray:elements];
    if([value isKindOfClass:[NSOrderedSet class]])
     return [NSOrderedSet orderedSetWithArray:elements];
    return elements;
   }
   return value;
}

static NSPredicate *CDReplacedPredicate(NSPredicate *predicate,CDReplacement *replacement);

static NSExpression *CDReplacedExpression(NSExpression *expression,CDReplacement *replacement){
   BOOL changed=NO;

   switch([expression expressionType]){
    case NSConstantValueExpressionType:{
     id value=CDReplacedConstant([expression constantValue],replacement,&changed);

     return changed?[NSExpression expressionForConstantValue:value]:expression;
    }
    case NSAggregateExpressionType:{
     NSMutableArray *elements=[NSMutableArray array];

     for(NSExpression *element in [expression collection]){
      NSExpression *replaced=CDReplacedExpression(element,replacement);

      changed=changed || (replaced!=element);
      [elements addObject:replaced];
     }
     return changed?[NSExpression expressionForAggregate:elements]:expression;
    }
    case NSFunctionExpressionType:{
     NSMutableArray *arguments=[NSMutableArray array];

     for(NSExpression *argument in [expression arguments]){
      NSExpression *replaced=CDReplacedExpression(argument,replacement);

      changed=changed || (replaced!=argument);
      [arguments addObject:replaced];
     }
     return changed?[NSExpression expressionForFunction:[expression function] arguments:arguments]:expression;
    }
    case NSSubqueryExpressionType:{
     NSExpression *collection=CDReplacedExpression([expression collection],replacement);
     NSPredicate  *condition=CDReplacedPredicate([expression predicate],replacement);

     if(collection==[expression collection] && condition==[expression predicate])
      return expression;
     return [NSExpression expressionForSubquery:collection usingIteratorVariable:[expression variable] predicate:condition];
    }
    case NSUnionSetExpressionType:
    case NSIntersectSetExpressionType:
    case NSMinusSetExpressionType:{
     NSExpression *left=CDReplacedExpression([expression leftExpression],replacement);
     NSExpression *right=CDReplacedExpression([expression rightExpression],replacement);

     if(left==[expression leftExpression] && right==[expression rightExpression])
      return expression;
     if([expression expressionType]==NSUnionSetExpressionType)
      return [NSExpression expressionForUnionSet:left with:right];
     if([expression expressionType]==NSIntersectSetExpressionType)
      return [NSExpression expressionForIntersectSet:left with:right];
     return [NSExpression expressionForMinusSet:left with:right];
    }
    default:
     return expression;
   }
}

static NSPredicate *CDReplacedPredicate(NSPredicate *predicate,CDReplacement *replacement){
   if([predicate isKindOfClass:[NSCompoundPredicate class]]){
    NSCompoundPredicate *compound=(NSCompoundPredicate *)predicate;
    NSMutableArray *subpredicates=[NSMutableArray array];
    BOOL changed=NO;

    for(NSPredicate *subpredicate in [compound subpredicates]){
     NSPredicate *replaced=CDReplacedPredicate(subpredicate,replacement);

     changed=changed || (replaced!=subpredicate);
     [subpredicates addObject:replaced];
    }
    if(!changed)
     return predicate;
    return [[[NSCompoundPredicate alloc] initWithType:[compound compoundPredicateType] subpredicates:subpredicates] autorelease];
   }

   if([predicate isKindOfClass:[NSComparisonPredicate class]]){
    NSComparisonPredicate *comparison=(NSComparisonPredicate *)predicate;
    NSExpression *left=CDReplacedExpression([comparison leftExpression],replacement);
    NSExpression *right=CDReplacedExpression([comparison rightExpression],replacement);

    if(left==[comparison leftExpression] && right==[comparison rightExpression])
     return predicate;
    if([comparison predicateOperatorType]==NSCustomSelectorPredicateOperatorType)
     return [NSComparisonPredicate predicateWithLeftExpression:left rightExpression:right customSelector:[comparison customSelector]];
    return [NSComparisonPredicate predicateWithLeftExpression:left
                                              rightExpression:right
                                                     modifier:[comparison comparisonPredicateModifier]
                                                         type:[comparison predicateOperatorType]
                                                      options:[comparison options]];
   }
   return predicate;
}

NSPredicate *CDPredicateReplacingObjectIDs(NSPredicate *predicate,CDObjectIDReplacement replace,void *context){
   CDReplacement replacement={ replace,context };

   return (predicate!=nil)?CDReplacedPredicate(predicate,&replacement):nil;
}
