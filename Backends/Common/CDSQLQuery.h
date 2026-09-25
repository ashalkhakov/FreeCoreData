/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/Foundation.h>

/* A SELECT statement under construction.

   The store used to build its SQL by appending to a string, which was
   enough while every fetch had the same shape: the two key columns, one
   table, a WHERE clause, an ORDER BY.  Three things change that shape -
   sorting on a value that lives in another table (a join), asking for
   columns rather than objects (a projection), and asking for an aggregate -
   and each of them has to reach a different part of the statement.  This
   holds those parts separately and writes them out in order, so the pieces
   can be assembled in any order they become known.

   It is deliberately not a relational algebra.  A fetch request can name
   one entity, a predicate, sort descriptors, a limit and a result type;
   there is no union, no derived table, nothing to plan.  What is needed is
   somewhere to put a join list and a select list, and the discipline of
   allocating aliases in one place.

   Parameters live here too, and are appended as each part is built, so
   their order matches the order the placeholders appear in the finished
   statement.  That is why the parts are built select-list first, then
   joins, then WHERE, then HAVING: the same order they are rendered. */

@interface CDSQLQuery : NSObject {
    NSMutableArray *_select;
    NSString *_fromTable;
    NSString *_fromAlias;
    NSMutableArray *_joins;
    NSMutableArray *_conditions;
    NSMutableArray *_groupBy;
    NSString *_having;
    NSMutableArray *_orderBy;
    NSMutableArray *_parameters;
    NSUInteger _limit;
    NSUInteger _offset;
    NSUInteger _nextAlias;
    BOOL _distinct;
}

+ (instancetype)queryFromTable:(NSString *)table alias:(NSString *)alias;

/* The rows this query is over. */
- (NSString *)fromAlias;

/* A fresh alias, so that two joins - or a join and a correlated subquery -
   cannot pick the same name. */
- (NSString *)nextAliasWithPrefix:(NSString *)prefix;

- (void)selectExpression:(NSString *)expression;
- (void)setDistinct:(BOOL)distinct;
- (void)addJoin:(NSString *)join;                    /* rendered, e.g. LEFT JOIN "X" s0 ON ... */
- (void)addCondition:(NSString *)condition;          /* ANDed together */
- (void)addGroupBy:(NSString *)expression;
- (void)setHaving:(NSString *)having;
- (void)addOrderBy:(NSString *)term;
- (void)setLimit:(NSUInteger)limit offset:(NSUInteger)offset;

/* Appended in the order the placeholders appear. */
- (NSMutableArray *)parameters;

- (NSString *)SQL;

@end
