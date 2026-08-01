package harp

import "core:fmt"
import "core:os"
import "core:os/os2"
import "core:strings"

PLIST_ID :: "com.mr_robot.harp"
PLIST :: `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mr_robot.harp</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/harp</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/harp.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/harp.log</string>
</dict>
</plist>`

setup :: proc() {
	fmt.println("[harp] first run :: setting up environment...")

	ok := install_plist()
	if !ok {panic("[harp] failed to write launchd plist")}
	fmt.println("[harp] launchd plist installed")

	disable_stage_manager()
	fmt.println("[harp] macos stage manager disabled")

	launchctl_load()
	fmt.println("[harp] done :: harp window manager is running")
	fmt.println("[harp] logs at /tmp/harp.log")
}

install_plist :: proc() -> bool {
	home := os.get_env("HOME")
	path := strings.concatenate({home, "/Library/LaunchAgents/", PLIST_ID, ".plist"})
	defer delete(home)
	defer delete(path)
	return os.write_entire_file(path, transmute([]byte)string(PLIST))
}

is_setup :: proc() -> bool {
	home := os.get_env("HOME")
	path := strings.concatenate({home, "/Library/LaunchAgents/", PLIST_ID, ".plist"})
	defer delete(home)
	defer delete(path)
	return os.exists(path)
}

launchctl_load :: proc() {
	home := os.get_env("HOME")
	plist := strings.concatenate({home, "/Library/LaunchAgents/", PLIST_ID, ".plist"})
	defer delete(home)
	defer delete(plist)
	run_command({"launchctl", "load", plist})
}

run_command :: proc(args: []string) {
	if process, err := os2.process_start({command = args}); err == nil {
		_, err := os2.process_wait(process)
		switch err {
		case os2.ERROR_NONE:
		case:
			panic("failed to wait for process")
		}
		err = os2.process_close(process)
		switch err {
		case os2.ERROR_NONE:
		case:
			panic("failed to close process")
		}
	}
}


disable_stage_manager :: proc() {
	_, err := os2.process_start(
		{
			command = {
				"defaults",
				"write",
				"com.apple.WindowManager",
				"GloballyEnabled",
				"-bool",
				"false",
			},
		},
	)
	switch err {
	case os2.ERROR_NONE:
	case:
		panic("failed to disable macos stage manager")
	}
}
