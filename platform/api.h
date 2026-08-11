#pragma once

#include <CoreGraphics/CoreGraphics.h>

int    platform_check_accessibility(void);
int    platform_request_accessibility(void);
int    platform_find_app(const char *bundle_id);
int    platform_launch_app(const char *bundle_id);
void   platform_fill_window(int pid);
void   platform_snap_window(int pid);
void   platform_show_loader(const char *bundle_id, const char *app_name);
void   platform_hide_loader(void);
void   platform_launch_app_async(const char *bundle_id, void (*cb)(int pid, void *ctx), void *ctx);
typedef void (*screen_change_cb)(void *ctx);
void   platform_register_screen_change_handler(screen_change_cb cb, void *ctx);
const char *platform_frontmost_app(void);
const char *platform_app_name(const char *bundle_id);
void   platform_show_overlay(const char **keys, const char **names, const int *states, int count, int active);
void   platform_hide_overlay(void);
void   platform_show_search(const char *query, const char **results, int count, int active);
void   platform_hide_search(void);
int    platform_get_all_apps(const char **names_out, const char **bundle_ids_out, int max_count);
int    platform_get_app_count(void);
