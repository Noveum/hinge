APP = build/Hinge.app
SOURCES = $(wildcard Sources/*.swift)

.PHONY: build

build:
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 $(SOURCES) -o "$(APP)/Contents/MacOS/Hinge" -framework SwiftUI -framework AppKit -framework IOKit -framework ScreenCaptureKit -framework MetalKit -framework MetalPerformanceShaders
	cp Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/* "$(APP)/Contents/Resources/"
	codesign --force --sign - "$(APP)"
