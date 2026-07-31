#pragma once

#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

typedef double              CGFloat;
typedef uint32_t            CGKeyCode;
typedef uint64_t            CGEventFlags;
typedef uint32_t            CGEventType;
typedef struct CGEvent     *CGEventRef;
typedef struct CGEventTap  *CGEventTapProxy;
typedef struct __CFMachPort *CFMachPortRef;
typedef struct __CFRunLoopSource *CFRunLoopSourceRef;
typedef struct __CFRunLoop *CFRunLoopRef;
typedef struct __CFAllocator *CFAllocatorRef;

typedef struct { CGFloat x, y; }               CGPoint;
typedef struct { CGFloat width, height; }       CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;

typedef uint32_t CGEventMask;
typedef uint32_t CGEventTapLocation;
typedef uint32_t CGEventTapPlacement;
typedef uint32_t CGEventTapOptions;
typedef int64_t  CGEventField;

typedef CGEventRef (*CGEventTapCallBack)(CGEventTapProxy, CGEventType, CGEventRef, void *);

extern CFAllocatorRef kCFAllocatorDefault;
extern CFRunLoopRef   CFRunLoopGetCurrent(void);

typedef struct { long version; void *info; } CFMachPortContext;

enum {
    kCGSessionEventTap             = 1,
    kCGHeadInsertEventTap          = 0,
    kCGEventTapOptionDefault       = 0,
    kCGEventKeyDown                = 10,
    kCGEventTapDisabledByTimeout   = 0xFFFFFFFE,
    kCGEventTapDisabledByUserInput = 0xFFFFFFFF,
    kCGKeyboardEventKeycode        = 9,
};

enum {
    kCGEventFlagMaskCommand   = 0x00100000,
    kCGEventFlagMaskShift     = 0x00020000,
    kCGEventFlagMaskControl   = 0x00040000,
    kCGEventFlagMaskAlternate = 0x00080000,
};

static inline CGEventMask CGEventMaskBit(CGEventType t) { return (CGEventMask)(1ULL << t); }

extern CFMachPortRef CGEventTapCreate(
    CGEventTapLocation, CGEventTapPlacement, CGEventTapOptions,
    CGEventMask, CGEventTapCallBack, void *);
extern void         CGEventTapEnable(CFMachPortRef, bool);
extern CGEventFlags CGEventGetFlags(CGEventRef);
extern int64_t      CGEventGetIntegerValueField(CGEventRef, CGEventField);

extern CFRunLoopSourceRef CFMachPortCreateRunLoopSource(CFAllocatorRef, CFMachPortRef, long);

typedef void *CFStringRef;
extern CFStringRef kCFRunLoopCommonModes;
extern void CFRunLoopAddSource(CFRunLoopRef, CFRunLoopSourceRef, CFStringRef);
extern void CFRunLoopRun(void);

int    platform_check_accessibility(void);
int    platform_find_app(const char *bundle_id);
int    platform_launch_app(const char *bundle_id);
void   platform_activate_app(int pid);
CGRect platform_screen_rect(void);
void   platform_fill_window(int pid, CGRect rect);
