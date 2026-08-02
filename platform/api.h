#pragma once

#include <CoreGraphics/CoreGraphics.h>

int    platform_check_accessibility(void);
int    platform_request_accessibility(void);
int    platform_find_app(const char *bundle_id);
int    platform_launch_app(const char *bundle_id);
CGRect platform_screen_rect(void);
void   platform_fill_window(int pid, CGRect rect);
const char *platform_frontmost_app(void);
void   platform_show_overlay(const char **keys, const char **names, const int *states, int count, int active);
void   platform_hide_overlay(void);
