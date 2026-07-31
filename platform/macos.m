#import <ApplicationServices/ApplicationServices.h>
#import <Cocoa/Cocoa.h>

#include "api.h"

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
  cfg.activates = YES;

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

void platform_activate_app(int pid) {
  NSRunningApplication *app =
      [NSRunningApplication runningApplicationWithProcessIdentifier:(pid_t)pid];
  [app activateWithOptions:0];
}

CGRect platform_screen_rect(void) {
  NSRect r = [NSScreen mainScreen].visibleFrame;
  return CGRectMake(r.origin.x, r.origin.y, r.size.width, r.size.height);
}

void platform_fill_window(int pid, CGRect rect) {
  AXUIElementRef ax_app = AXUIElementCreateApplication((pid_t)pid);

  AXUIElementRef window = NULL;
  AXError err = AXUIElementCopyAttributeValue(ax_app, kAXFocusedWindowAttribute,
                                              (CFTypeRef *)&window);

  if (err != kAXErrorSuccess || !window) {
    CFArrayRef windows = NULL;
    AXUIElementCopyAttributeValue(ax_app, kAXWindowsAttribute,
                                  (CFTypeRef *)&windows);
    if (windows && CFArrayGetCount(windows) > 0)
      window = (AXUIElementRef)CFRetain(CFArrayGetValueAtIndex(windows, 0));
    if (windows)
      CFRelease(windows);
  }

  if (window) {
    CGPoint origin = CGPointMake(rect.origin.x, rect.origin.y);
    CGSize size = CGSizeMake(rect.size.width, rect.size.height);

    AXValueRef pos_val = AXValueCreate(kAXValueCGPointType, &origin);
    AXValueRef size_val = AXValueCreate(kAXValueCGSizeType, &size);

    AXUIElementSetAttributeValue(window, kAXPositionAttribute, pos_val);
    AXUIElementSetAttributeValue(window, kAXSizeAttribute, size_val);

    CFRelease(pos_val);
    CFRelease(size_val);
    CFRelease(window);
  }

  CFRelease(ax_app);
}
