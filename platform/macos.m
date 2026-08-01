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
