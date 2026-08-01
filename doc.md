# commands

disable stage manager
defaults write com.apple.WindowManager GloballyEnabled -bool false

stop/start daemon
launchctl unload ~/Library/LaunchAgents/com.mr_robot.harp.plist
launchctl load ~/Library/LaunchAgents/com.mr_robot.harp.plist

logs
tail -f /tmp/harp.log
