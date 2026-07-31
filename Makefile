BIN     = harp
SHIM    = platform/macos.o
FRAMEWORKS = -Wl,-framework,Cocoa,-framework,ApplicationServices,-framework,CoreGraphics,-framework,CoreFoundation,-framework,Carbon

$(BIN): $(SHIM) main.odin
	odin build . -out:$(BIN) -extra-linker-flags:"$(FRAMEWORKS)"

$(SHIM): platform/macos.m platform/api.h
	clang -c -fobjc-arc platform/macos.m -o $(SHIM)

clean:
	rm -f $(BIN) $(SHIM)
