// -*- Mode: objc; Coding: utf-8; indent-tabs-mode: nil; -*-
//
// This code is based on PowerKey of Peter Kamb.
// https://github.com/pkamb/PowerKey/

#import <IOKit/hidsystem/ev_keymap.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import "ClientForKernelspace.h"
#import "PowerKeyObserver.h"

@implementation PowerKeyObserver

@synthesize eventTap;
@synthesize enqueued;
@synthesize shouldBlockPowerKeyKeyCode;
@synthesize clientForKernelspace;

enum {
  POWER_KEY_TYPE_NONE,
  POWER_KEY_TYPE_SUBTYPE, // subtype == NX_SUBTYPE_POWER_KEY
  POWER_KEY_TYPE_KEYCODE, // subtype == NX_SUBTYPE_AUX_CONTROL_BUTTONS and keyCode == NX_POWER_KEY
};

// The power button sends two events.
// POWER_KEY_TYPE_SUBTYPE and POWER_KEY_TYPE_KEYCODE.
//
// A build-in keyboard of MacBook sends these events.
// - POWER_KEY_TYPE_SUBTYPE (at key down)
// - POWER_KEY_TYPE_KEYCODE (at key down)
//
// An external keyboard which has power key sends these events.
// - POWER_KEY_TYPE_SUBTYPE (at key down)
// - POWER_KEY_TYPE_KEYCODE (at key down)
// - POWER_KEY_TYPE_KEYCODE (at key up)

- (int) getPowerKeyType:(CGEventRef)cgEvent
{
  if (! cgEvent) return POWER_KEY_TYPE_NONE;

  NSEvent* event = [NSEvent eventWithCGEvent:cgEvent];
  if (! event) return POWER_KEY_TYPE_NONE;

  if ([event type] != NSSystemDefined) return POWER_KEY_TYPE_NONE;

  if ([event subtype] == NX_SUBTYPE_POWER_KEY) {
    return POWER_KEY_TYPE_SUBTYPE;
  }

  if ([event subtype] == NX_SUBTYPE_AUX_CONTROL_BUTTONS) {
    int keyCode = (([event data1] & 0xFFFF0000) >> 16);
    if (keyCode == NX_POWER_KEY) {
      return POWER_KEY_TYPE_KEYCODE;
    }
  }

  return POWER_KEY_TYPE_NONE;
}

static CGEventRef eventTapCallBack(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon)
{
  PowerKeyObserver* self = (PowerKeyObserver*)(refcon);
  if (! self) return event;

  switch (type) {
    case kCGEventTapDisabledByTimeout:
      // Re-enable the event tap if it times out.
      CGEventTapEnable([self eventTap], true);
      break;

    case NSSystemDefined:
    {
      switch ([self getPowerKeyType:event]) {
        case POWER_KEY_TYPE_SUBTYPE:
          NSLog(@"POWER_KEY_TYPE_SUBTYPE");

          // This event show a shutdown dialog.
          if (! self.enqueued) {
            NSLog(@"enqueue");
            self.enqueued = YES;
            self.shouldBlockPowerKeyKeyCode = YES;
            [[self clientForKernelspace] enqueue_power_key];
            event = NULL;

          } else {
            self.enqueued = NO;

            NSLog(@"is_power_key_changed:%d", [[self clientForKernelspace] is_power_key_changed]);

            if ([[self clientForKernelspace] is_power_key_changed]) {
              self.shouldBlockPowerKeyKeyCode = YES;
              event = NULL;
            } else {
              self.shouldBlockPowerKeyKeyCode = NO;
            }
          }
          break;

        case POWER_KEY_TYPE_KEYCODE:
          NSLog(@"POWER_KEY_TYPE_KEYCODE");

          if (self.shouldBlockPowerKeyKeyCode) {
            event = NULL;
          }
          break;

        case POWER_KEY_TYPE_NONE:
          // do nothing
          break;
      }
    }
  }

  return event;
}

- (void) start
{
  if (eventTap) return;

  // We need to grab NSSystemDefined events.
  // So, we call CGEventCreate with kCGEventMaskForAllEvents.
  eventTap = CGEventTapCreate(kCGSessionEventTap,
                              kCGHeadInsertEventTap,
                              kCGEventTapOptionDefault,
                              NSSystemDefinedMask,
                              eventTapCallBack,
                              self);
  if (! eventTap) {
    NSLog(@"CGEventTapCreate is failed");
    return;
  }

  CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
  CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);

  CGEventTapEnable(eventTap, 1);

  CFRelease(runLoopSource);
  CFRelease(eventTap);
}

@end
