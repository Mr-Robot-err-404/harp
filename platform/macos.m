#import <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#include <unistd.h>

#include "api.h"

// Private SkyLight symbols — available without SIP disabled.
extern int SLSMainConnectionID(void);
extern CGError SLSDisableUpdate(int cid);
extern CGError SLSReenableUpdate(int cid);
extern CGError _SLPSSetFrontProcessWithOptions(ProcessSerialNumber *psn,
                                               uint32_t wid, uint32_t mode);
extern CGError SLPSPostEventRecordTo(ProcessSerialNumber *psn, uint8_t *bytes);

#define kCPSUserGenerated 0x200

int platform_check_accessibility(void) {
  NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt : @NO};
  return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts) ? 1 : 0;
}

int platform_request_accessibility(void) {
  NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt : @YES};
  return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts) ? 1 : 0;
}

int platform_find_app(const char *bundle_id) {
  NSString *bid = [NSString stringWithUTF8String:bundle_id];
  NSArray<NSRunningApplication *> *apps =
      [NSRunningApplication runningApplicationsWithBundleIdentifier:bid];
  if (apps.count == 0)
    return -1;
  return (int)apps.firstObject.processIdentifier;
}

int platform_launch_app(const char *bundle_id) {
  NSString *bid = [NSString stringWithUTF8String:bundle_id];
  NSURL *url =
      [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bid];
  if (!url)
    return -1;

  NSWorkspaceOpenConfiguration *cfg =
      [NSWorkspaceOpenConfiguration configuration];
  cfg.activates = YES; // let OS handle initial activation; we snap on top after

  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  __block int pid = -1;

  [[NSWorkspace sharedWorkspace]
      openApplicationAtURL:url
             configuration:cfg
         completionHandler:^(NSRunningApplication *app, NSError *err) {
           if (app)
             pid = (int)app.processIdentifier;
           dispatch_semaphore_signal(sem);
         }];

  dispatch_semaphore_wait(sem,
                          dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
  return pid;
}

CGRect platform_screen_rect(void) {
  NSRect r = [NSScreen mainScreen].visibleFrame;
  return CGRectMake(r.origin.x, r.origin.y, r.size.width, r.size.height);
}

static AXUIElementRef find_window(AXUIElementRef ax_app) {
  AXUIElementRef window = NULL;
  AXError err = AXUIElementCopyAttributeValue(ax_app, kAXFocusedWindowAttribute,
                                              (CFTypeRef *)&window);
  if (err == kAXErrorSuccess && window)
    return window;

  CFArrayRef windows = NULL;
  AXUIElementCopyAttributeValue(ax_app, kAXWindowsAttribute,
                                (CFTypeRef *)&windows);
  if (windows) {
    if (CFArrayGetCount(windows) > 0)
      window = (AXUIElementRef)CFRetain(CFArrayGetValueAtIndex(windows, 0));
    CFRelease(windows);
  }
  return window;
}

const char *platform_frontmost_app(void) {
  NSRunningApplication *app = NSWorkspace.sharedWorkspace.frontmostApplication;
  return app.bundleIdentifier.UTF8String;
}

const char *platform_app_name(const char *bundle_id) {
  NSString *bid = [NSString stringWithUTF8String:bundle_id];

  NSArray<NSRunningApplication *> *apps =
      [NSRunningApplication runningApplicationsWithBundleIdentifier:bid];
  if (apps.count > 0)
    return apps.firstObject.localizedName.UTF8String;

  NSURL *url =
      [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bid];
  if (url) {
    NSBundle *bundle = [NSBundle bundleWithURL:url];
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]
                         ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    if (name)
      return name.UTF8String;
  }

  return bundle_id;
}

// ---------------------------------------------------------------------------
// Overlay
// ---------------------------------------------------------------------------

// Kanagawa palette
#define KG_BG    [NSColor colorWithRed:0x1a/255.0 green:0x1b/255.0 blue:0x26/255.0 alpha:1.0]
#define KG_HL    [NSColor colorWithRed:0x2d/255.0 green:0x4f/255.0 blue:0x67/255.0 alpha:1.0]
#define KG_FG    [NSColor colorWithRed:0xc0/255.0 green:0xca/255.0 blue:0xf5/255.0 alpha:1.0]
#define KG_DIM   [NSColor colorWithRed:0x56/255.0 green:0x5f/255.0 blue:0x89/255.0 alpha:1.0]
#define KG_ACT   [NSColor colorWithRed:0x7d/255.0 green:0xcf/255.0 blue:0xff/255.0 alpha:1.0]
#define KG_MOV   [NSColor colorWithRed:0xe6/255.0 green:0xc3/255.0 blue:0x84/255.0 alpha:1.0]  // Kanagawa yellow — moving
#define KG_DEL   [NSColor colorWithRed:0xff/255.0 green:0x5d/255.0 blue:0x62/255.0 alpha:1.0]  // Kanagawa red — deleting

// Item states — must match Odin enum order.
#define ITEM_STATE_NONE     0
#define ITEM_STATE_MOVING   1
#define ITEM_STATE_DELETING 2

// Overlay modes
#define HARP_MODE_LIST   0
#define HARP_MODE_SEARCH 1

static NSPanel  *g_overlay        = nil;
static NSArray  *g_overlay_keys   = nil;
static NSArray  *g_overlay_names  = nil;
static NSArray  *g_overlay_states = nil;
static int       g_active         = 0;
static int       g_mode           = HARP_MODE_LIST;
static NSString *g_search_query   = nil;
static NSArray  *g_search_results = nil;
static int       g_search_active  = 0;

@interface HarpOverlayView : NSView
@end

@implementation HarpOverlayView

- (void)drawRect:(NSRect)dirtyRect {
  CGFloat w = self.bounds.size.width;
  CGFloat h = self.bounds.size.height;

  // Background
  [KG_BG setFill];
  NSRectFill(self.bounds);

  // Left + right borders
  [KG_HL setFill];
  NSRectFill(NSMakeRect(0, 0, 2, h));
  NSRectFill(NSMakeRect(w - 2, 0, 2, h));

  CGFloat row_h = 36;
  CGFloat pad_x = 20;
  CGFloat pad_y = 14;

  if (g_mode == HARP_MODE_SEARCH) {
    // Search bar — full width, flush to top
    CGFloat bar_h = 40;
    CGFloat bar_y = h - bar_h;
    [KG_BG setFill];
    NSRectFill(NSMakeRect(0, bar_y, w, bar_h));

    NSString *display = g_search_query.length > 0 ? g_search_query : @"";
    NSDictionary *query_attrs = @{
      NSFontAttributeName: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular],
      NSForegroundColorAttributeName: KG_FG,
    };
    [display drawAtPoint:NSMakePoint(pad_x, bar_y + 12) withAttributes:query_attrs];

    // Cursor line at end of query text
    NSSize text_size = [display sizeWithAttributes:query_attrs];
    NSDictionary *cursor_attrs = @{
      NSFontAttributeName: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular],
      NSForegroundColorAttributeName: KG_ACT,
    };
    [@"|" drawAtPoint:NSMakePoint(pad_x + text_size.width, bar_y + 12) withAttributes:cursor_attrs];

    // Results
    if (!g_search_results.count) return;
    NSUInteger count = g_search_results.count;
    for (NSUInteger i = 0; i < count; i++) {
      CGFloat y = bar_y - (i + 1) * row_h + 8;
      BOOL cursor = ((int)i == g_search_active);

      if (cursor) {
        [KG_HL setFill];
        NSRectFill(NSMakeRect(2, y - 6, w - 4, row_h - 4));
      }

      NSDictionary *name_attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: cursor ? KG_ACT : KG_FG,
      };
      [g_search_results[i] drawAtPoint:NSMakePoint(pad_x, y) withAttributes:name_attrs];
    }
    return;
  }

  // List mode
  if (!g_overlay_keys.count) return;
  NSUInteger count = g_overlay_keys.count;

  for (NSUInteger i = 0; i < count; i++) {
    CGFloat y = h - pad_y - (i + 1) * row_h + 8;
    BOOL cursor = ((int)i == g_active);
    int state = g_overlay_states ? [g_overlay_states[i] intValue] : ITEM_STATE_NONE;

    NSColor *item_color;
    switch (state) {
      case ITEM_STATE_MOVING:   item_color = KG_MOV; break;
      case ITEM_STATE_DELETING: item_color = KG_DEL; break;
      default:                  item_color = KG_FG;  break;
    }

    if (cursor) {
      [KG_HL setFill];
      NSRectFill(NSMakeRect(2, y - 6, w - 4, row_h - 4));
    }

    if (state == ITEM_STATE_DELETING) {
      [[NSColor colorWithRed:0.6 green:0.1 blue:0.1 alpha:1.0] setFill];
      NSRectFill(NSMakeRect(2, y - 6, w - 4, row_h - 4));

      NSDictionary *del_attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.whiteColor,
      };
      [@"Press X again to confirm" drawAtPoint:NSMakePoint(pad_x + 60, y) withAttributes:del_attrs];

      NSDictionary *row_attrs_key = @{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor,
      };
      [g_overlay_keys[i] drawAtPoint:NSMakePoint(pad_x, y) withAttributes:row_attrs_key];
      continue;
    }

    NSDictionary *row_attrs_key = @{
      NSFontAttributeName: [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightBold],
      NSForegroundColorAttributeName: item_color,
    };
    NSDictionary *row_attrs_name = @{
      NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
      NSForegroundColorAttributeName: item_color,
    };

    [g_overlay_keys[i]  drawAtPoint:NSMakePoint(pad_x,      y) withAttributes:row_attrs_key];
    [g_overlay_names[i] drawAtPoint:NSMakePoint(pad_x + 60, y) withAttributes:row_attrs_name];
  }
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
  if (event.keyCode == 53) { // Escape
    [g_overlay orderOut:nil];
  }
}

@end

void platform_show_overlay(const char **keys, const char **names, const int *states, int count, int active) {
  // Copy before dispatch — caller's stack may be gone by the time block runs.
  NSMutableArray *ks = [NSMutableArray arrayWithCapacity:count];
  NSMutableArray *ns = [NSMutableArray arrayWithCapacity:count];
  NSMutableArray *ss = [NSMutableArray arrayWithCapacity:count];
  for (int i = 0; i < count; i++) {
    [ks addObject:[NSString stringWithUTF8String:keys[i]]];
    [ns addObject:[NSString stringWithUTF8String:names[i]]];
    [ss addObject:@(states[i])];
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    g_overlay_keys   = ks;
    g_overlay_names  = ns;
    g_overlay_states = ss;
    g_active         = active;

    NSRect screen = [NSScreen mainScreen].visibleFrame;
    CGFloat w = 480, h = 320;
    NSRect frame = NSMakeRect(NSMidX(screen) - w / 2, NSMidY(screen) - h / 2, w, h);

    if (!g_overlay) {
      g_overlay = [[NSPanel alloc]
          initWithContentRect:frame
                    styleMask:NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskBorderless
                      backing:NSBackingStoreBuffered
                        defer:NO];
      g_overlay.level             = NSFloatingWindowLevel;
      g_overlay.backgroundColor   = KG_BG;
      g_overlay.opaque             = YES;
      g_overlay.hasShadow          = NO;
      g_overlay.releasedWhenClosed = NO;

      HarpOverlayView *view = [[HarpOverlayView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
      g_overlay.contentView = view;
    }

    [g_overlay.contentView setNeedsDisplay:YES];
    [g_overlay orderFrontRegardless];
    [g_overlay makeFirstResponder:g_overlay.contentView];
  });
}


void platform_show_search(const char *query, const char **results, int count, int active) {
  NSString *q = [NSString stringWithUTF8String:query];
  NSMutableArray *rs = [NSMutableArray arrayWithCapacity:count];
  for (int i = 0; i < count; i++)
    [rs addObject:[NSString stringWithUTF8String:results[i]]];

  dispatch_async(dispatch_get_main_queue(), ^{
    g_search_query  = q;
    g_search_results = rs;
    g_search_active  = active;
    g_mode           = HARP_MODE_SEARCH;
    [g_overlay.contentView setNeedsDisplay:YES];
    [g_overlay orderFrontRegardless];
  });
}

void platform_hide_search(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    g_mode           = HARP_MODE_LIST;
    g_search_query   = nil;
    g_search_results = nil;
    g_search_active  = 0;
    [g_overlay.contentView setNeedsDisplay:YES];
  });
}

void platform_hide_overlay(void) {
  dispatch_async(dispatch_get_main_queue(), ^{
    g_mode = HARP_MODE_LIST;
    [g_overlay orderOut:nil];
  });
}

// ---------------------------------------------------------------------------

void platform_fill_window(int pid, CGRect rect) {
  AXUIElementRef ax_app = AXUIElementCreateApplication((pid_t)pid);

  AXUIElementRef window = find_window(ax_app);

  // App is running but has no windows (red-buttoned). Tell it to reopen.
  if (!window) {
    NSRunningApplication *app =
        [NSRunningApplication runningApplicationWithProcessIdentifier:(pid_t)pid];
    if (app) {
      NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
      cfg.activates = YES;
      [[NSWorkspace sharedWorkspace]
          openApplicationAtURL:app.bundleURL
                 configuration:cfg
             completionHandler:nil];
    }
    // Poll up to 2 seconds for the window to appear.
    for (int i = 0; i < 20 && !window; i++) {
      usleep(100000);
      window = find_window(ax_app);
    }
  }

  if (!window) {
    CFRelease(ax_app);
    return;
  }

  // Get PSN from pid — deprecated but functional on macOS 26.
  ProcessSerialNumber psn = {0, 0};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  OSStatus psn_err = GetProcessForPID((pid_t)pid, &psn);
#pragma clang diagnostic pop
  if (psn_err != 0) {
    CFRelease(window);
    CFRelease(ax_app);
    return;
  }

  CGPoint origin = CGPointMake(rect.origin.x, rect.origin.y);
  CGSize size = CGSizeMake(rect.size.width, rect.size.height);
  AXValueRef pos_val = AXValueCreate(kAXValueCGPointType, &origin);
  AXValueRef size_val = AXValueCreate(kAXValueCGSizeType, &size);

  // Freeze compositor — resize, focus, raise all land in one frame.
  int cid = SLSMainConnectionID();
  SLSDisableUpdate(cid);

  AXUIElementSetAttributeValue(window, kAXPositionAttribute, pos_val);
  AXUIElementSetAttributeValue(window, kAXSizeAttribute, size_val);

  _SLPSSetFrontProcessWithOptions(&psn, 0, kCPSUserGenerated);

  uint8_t bytes[0xf8] = {0};
  bytes[0x04] = 0xf8;
  bytes[0x3a] = 0x10;
  memset(bytes + 0x20, 0xff, 0x10);
  bytes[0x08] = 0x01;
  SLPSPostEventRecordTo(&psn, bytes);
  bytes[0x08] = 0x02;
  SLPSPostEventRecordTo(&psn, bytes);

  AXUIElementPerformAction(window, kAXRaiseAction);

  SLSReenableUpdate(cid);

  CFRelease(pos_val);
  CFRelease(size_val);
  CFRelease(window);
  CFRelease(ax_app);
}
