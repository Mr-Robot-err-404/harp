#pragma once

#include <CoreGraphics/CoreGraphics.h>

int    platform_check_accessibility(void);
int    platform_find_app(const char *bundle_id);
int    platform_launch_app(const char *bundle_id);
void   platform_activate_app(int pid);
CGRect platform_screen_rect(void);
void   platform_fill_window(int pid, CGRect rect);
