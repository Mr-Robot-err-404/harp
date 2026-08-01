BIN        = harp
SHIM       = platform/macos.o
FRAMEWORKS = -Wl,-framework,Cocoa,-framework,ApplicationServices,-framework,CoreGraphics,-framework,CoreFoundation,-framework,Carbon,-F/System/Library/PrivateFrameworks,-framework,SkyLight

INSTALL_BIN   = /usr/local/bin/harp
PLIST_ID      = com.mr_robot.harp
PLIST_SRC     = $(PLIST_ID).plist
PLIST_DEST    = $(HOME)/Library/LaunchAgents/$(PLIST_ID).plist

$(BIN): $(SHIM) main.odin types.odin
	odin build . -out:$(BIN) -extra-linker-flags:"$(FRAMEWORKS)"

$(SHIM): platform/macos.m platform/api.h
	clang -c -fobjc-arc -w platform/macos.m -o $(SHIM)

install: $(BIN) $(PLIST_SRC)
	cp $(BIN) $(INSTALL_BIN)
	cp $(PLIST_SRC) $(PLIST_DEST)
	launchctl load $(PLIST_DEST)
	@echo "[harp] installed and running"

uninstall:
	-launchctl unload $(PLIST_DEST)
	rm -f $(PLIST_DEST) $(INSTALL_BIN)
	@echo "[harp] uninstalled"

reinstall: uninstall install

clean:
	rm -f $(BIN) $(SHIM)

.PHONY: install uninstall reinstall clean
