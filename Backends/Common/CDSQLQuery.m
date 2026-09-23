/* This file is part of the CoreData framework port for GNUstep.
   Original file — not derived from Cocotron.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CDSQLQuery.h"

@implementation CDSQLQuery

+(instancetype)queryFromTable:(NSString *)table alias:(NSString *)alias {
   CDSQLQuery *query=[[[self alloc] init] autorelease];

   query->_select=[[NSMutableArray alloc] init];
   query->_fromTable=[table copy];
   query->_fromAlias=[alias copy];
   query->_joins=[[NSMutableArray alloc] init];
   query->_conditions=[[NSMutableArray alloc] init];
   query->_groupBy=[[NSMutableArray alloc] init];
   query->_orderBy=[[NSMutableArray alloc] init];
   query->_parameters=[[NSMutableArray alloc] init];

   return query;
}

-(void)dealloc {
   [_select release];
   [_fromTable release];
   [_fromAlias release];
   [_joins release];
   [_conditions release];
   [_groupBy release];
   [_having release];
   [_orderBy release];
   [_parameters release];
   [super dealloc];
}

-(NSString *)fromAlias {
   return _fromAlias;
}

-(NSString *)nextAliasWithPrefix:(NSString *)prefix {
   return [NSString stringWithFormat:@"%@%lu",prefix,(unsigned long)(_nextAlias++)];
}

-(void)selectExpression:(NSString *)expression {
   [_select addObject:expression];
}

-(void)setDistinct:(BOOL)distinct {
   _distinct=distinct;
}

-(void)addJoin:(NSString *)join {
   [_joins addObject:join];
}

-(void)addCondition:(NSString *)condition {
   if([condition length]>0)
    [_conditions addObject:condition];
}

-(void)addGroupBy:(NSString *)expression {
   [_groupBy addObject:expression];
}

-(void)setHaving:(NSString *)having {
   if(having!=_having){
    [_having release];
    _having=[having copy];
   }
}

-(void)addOrderBy:(NSString *)term {
   [_orderBy addObject:term];
}

-(void)setLimit:(NSUInteger)limit offset:(NSUInteger)offset {
   _limit=limit;
   _offset=offset;
}

-(NSMutableArray *)parameters {
   return _parameters;
}

-(NSString *)SQL {
   NSMutableString *sql=[NSMutableString stringWithFormat:@"SELECT %@%@ FROM %@ %@",
                                                          _distinct?@"DISTINCT ":@"",
                                                          ([_select count]>0)?[_select componentsJoinedByString:@", "]:@"*",
                                                          _fromTable,_fromAlias];

   for(NSString *join in _joins)
    [sql appendFormat:@" %@",join];

   if([_conditions count]>0)
    [sql appendFormat:@" WHERE %@",[_conditions componentsJoinedByString:@" AND "]];

   if([_groupBy count]>0)
    [sql appendFormat:@" GROUP BY %@",[_groupBy componentsJoinedByString:@", "]];

   if([_having length]>0)
    [sql appendFormat:@" HAVING %@",_having];

   if([_orderBy count]>0)
    [sql appendFormat:@" ORDER BY %@",[_orderBy componentsJoinedByString:@", "]];

   /* Both dialects spell these the same way. */
   if(_limit>0)
    [sql appendFormat:@" LIMIT %llu",(unsigned long long)_limit];
   if(_offset>0)
    [sql appendFormat:@" OFFSET %llu",(unsigned long long)_offset];

   return sql;
}

@end
