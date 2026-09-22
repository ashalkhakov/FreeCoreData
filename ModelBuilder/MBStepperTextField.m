/* See MBStepperTextField.h.

   Copyright (c) 2026 the GNUstep CoreData port contributors.
   Released under the MIT license. */
#import "MBStepperTextField.h"

static const CGFloat MBStepperWidth = 15;
static const CGFloat MBStepperHeight = 22;
static const CGFloat MBStepperGap = 3;

@implementation MBStepperTextField {
  NSStepper *_stepper;
}

- (instancetype)initWithFrame:(NSRect)frame
{
  if ((self = [super initWithFrame:frame]))
    _increment = 1;
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
  if ((self = [super initWithCoder:coder]))
    _increment = 1;
  return self;
}

- (NSStepper *)stepper { return _stepper; }

- (void)awakeFromNib
{
  [super awakeFromNib];
  [self installStepper];
}

- (void)installStepper
{
  if (_stepper != nil || self.superview == nil) return;

  NSRect f = self.frame;
  NSRect stepperFrame = NSMakeRect(NSMaxX(f) + MBStepperGap,
                                   NSMidY(f) - MBStepperHeight / 2,
                                   MBStepperWidth, MBStepperHeight);
  _stepper = [[NSStepper alloc] initWithFrame:stepperFrame];

  /* Delta emitter: value rests at 0, a click leaves -1/+1 behind and
     the action handler resets it, so the stepper's value never needs
     syncing with the text. */
  _stepper.minValue = -1;
  _stepper.maxValue = 1;
  _stepper.increment = 1;
  _stepper.valueWraps = YES;
  _stepper.autorepeat = YES;
  _stepper.doubleValue = 0;

  /* Pin to the field's right edge under resizing: keep the field's
     vertical behavior, replace horizontal flexibility with a flexible
     left margin. */
  _stepper.autoresizingMask = NSViewMinXMargin |
      (self.autoresizingMask & (NSViewMinYMargin | NSViewMaxYMargin));
  _stepper.enabled = self.isEnabled;
  _stepper.target = self;
  _stepper.action = @selector(mbStep:);
  [self.superview addSubview:_stepper];
}

- (void)mbStep:(NSStepper *)sender
{
  double delta = sender.doubleValue;
  sender.doubleValue = 0;   /* back to the rest position */
  if (delta == 0 || !self.isEnabled) return;

  double value = self.doubleValue + delta * _increment;
  if (!_allowsNegative && value < 0) value = 0;
  self.stringValue = (value == rint(value) && fabs(value) < 1e15)
      ? [NSString stringWithFormat:@"%.0f", value]
      : [NSString stringWithFormat:@"%g", value];
  if (self.action != NULL)
    [self sendAction:self.action to:self.target];
}

- (void)setEnabled:(BOOL)enabled
{
  [super setEnabled:enabled];
  _stepper.enabled = enabled;
}

- (void)removeFromSuperview
{
  [_stepper removeFromSuperview];
  [super removeFromSuperview];
}

@end
