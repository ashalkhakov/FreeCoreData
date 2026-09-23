/* Repro for the NSKeyedArchiver secure-coding gap
   (see gnustep-base-keyedarchiver-secure-coding.patch).

   +archivedDataWithRootObject:requiringSecureCoding:error: - the
   modern (10.13) archiving entry point, and the only non-deprecated
   one on macOS - answers nil in gnustep-base whenever secure coding is
   requested, without setting the error, even for objects that fully
   adopt NSSecureCoding.  The class method simply skips the whole
   encode when requiresSecureCoding is YES, although the archiver
   instance has carried a requiresSecureCoding flag for years.

   With the patch, the method encodes with the archiver's flag set and
   reports a root object that does not adopt NSSecureCoding through the
   error instead of silently answering nil for everything.

   Build and run (against an installed gnustep-base):

       . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
       clang repro-nskeyedarchiver-secure-coding.m -o repro \
           $(gnustep-config --objc-flags) $(gnustep-config --base-libs)
       ./repro

   Exit status 0 with the patch applied, 1 without it. */
#import <Foundation/Foundation.h>

/* A minimal, fully secure-coding class - the shape of the tokens and
   descriptors real applications archive with this API. */
@interface ReproToken : NSObject <NSSecureCoding>
{
    NSDictionary *_positions;
}
- (instancetype)initWithPositions:(NSDictionary *)positions;
- (NSDictionary *)positions;
@end

@implementation ReproToken

- (instancetype)initWithPositions:(NSDictionary *)positions
{
    _positions = [positions copy];
    return self;
}

- (void)dealloc
{
    [_positions release];
    [super dealloc];
}

- (NSDictionary *)positions
{
    return _positions;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSSet *classes = [NSSet setWithObjects:
        [NSDictionary class], [NSString class], [NSNumber class], nil];

    _positions = [[coder decodeObjectOfClasses:classes
                                        forKey:@"positions"] copy];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_positions forKey:@"positions"];
}

@end

int main(void)
{
    int failures = 0;

    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    NSDictionary *positions = [NSDictionary dictionaryWithObject:
        [NSNumber numberWithLongLong:42] forKey:@"store"];
    ReproToken *token = [[[ReproToken alloc]
        initWithPositions:positions] autorelease];

    /* 1: a secure-coding object archives through the modern API. */
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:token
                                         requiringSecureCoding:YES
                                                         error:&error];
    if (data == nil) {
        NSLog(@"FAIL: archivedDataWithRootObject:requiringSecureCoding:YES "
              @"answered nil for a fully NSSecureCoding object (error %@)",
              error);
        failures++;
    }

    /* 2: the archive round-trips through the matching unarchiver API. */
    if (data != nil) {
        ReproToken *decoded = [NSKeyedUnarchiver
            unarchivedObjectOfClass:[ReproToken class]
                           fromData:data
                              error:&error];

        if (![[decoded positions] isEqual:positions]) {
            NSLog(@"FAIL: round trip lost the payload: %@ (error %@)",
                  [decoded positions], error);
            failures++;
        }
    }

    if (failures == 0)
        NSLog(@"PASS: modern secure-coding archiving works");

    [pool drain];
    return failures ? 1 : 0;
}
