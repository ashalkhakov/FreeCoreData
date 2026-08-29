/* A text field that owns its stepper.

   Drop-in replacement for the inspector's numeric fields: set the
   field's custom class to MBStepperTextField in Interface Builder and
   it creates, places and wires an NSStepper at its own right edge
   when the nib loads - no outlet, no action, no controller code.  An
   up/down click steps the field's value by `increment` and then sends
   the FIELD's own action to its target, so a step applies exactly
   like typing the value and tabbing out.

   The stepper mirrors the field's enabled state, and is configured as
   a delta emitter internally (it reports each click as -1/+1 and
   rests at 0), so it never has to be kept in sync with the text.

   Values clamp at zero unless allowsNegative is set (the number
   page's default/min/max fields, where numeric attributes may have
   negative bounds - set in code: GNUstep's xib loader does not apply
   IB user-defined runtime attributes to nested subviews).

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import <AppKit/AppKit.h>

@interface MBStepperTextField : NSTextField

@property (nonatomic, assign) BOOL allowsNegative;    /* default NO  */
@property (nonatomic, assign) double increment;       /* default 1   */
@property (nonatomic, strong, readonly) NSStepper *stepper;

@end
