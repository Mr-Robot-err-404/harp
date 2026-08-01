# commands

disable stage manager
defaults write com.apple.WindowManager GloballyEnabled -bool false

stop/start daemon
launchctl unload ~/Library/LaunchAgents/com.mr_robot.harp.plist
launchctl load ~/Library/LaunchAgents/com.mr_robot.harp.plist
launchctl bootout gui/$(id -u)/com.mr_robot.harp 2>&1

Restart the daemon:
launchctl bootout gui/501/com.mr_robot.harp && launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.mr_robot.harp.plist

logs
tail -f /tmp/harp.log
