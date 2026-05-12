.PHONY: build test clean

BUILD_DIR ?= ../build

# Builds clipssh-paste via Swift Package Manager and copies it into BUILD_DIR.
# Homebrew installs the resulting binary alongside the clipssh shell script.
build:
	@mkdir -p $(BUILD_DIR)
	swift build -c release
	cp $(shell swift build -c release --show-bin-path)/clipssh-paste $(BUILD_DIR)/clipssh-paste

# Runs the Swift unit tests for the pure-Swift helpers in ClipsshPasteCore.
# Requires a macOS host (the executable target imports AppKit).
test:
	swift test

clean:
	swift package clean
	rm -rf .build $(BUILD_DIR)
