APP = build/Bendy Prototype.app
SOURCES = $(wildcard Sources/*.swift)

.PHONY: build check

build:
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 $(SOURCES) -o "$(APP)/Contents/MacOS/BendyPrototype" -framework SwiftUI -framework AppKit -framework IOKit -framework AVFoundation
	cp Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/* "$(APP)/Contents/Resources/"
	codesign --force --sign - "$(APP)"

check: build
	"$(APP)/Contents/MacOS/BendyPrototype" --self-test
