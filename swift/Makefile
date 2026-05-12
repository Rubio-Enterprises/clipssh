.PHONY: build test clean

BUILD_DIR ?= ../build

build:
	@mkdir -p $(BUILD_DIR)
	swift build -c release
	cp $(shell swift build -c release --show-bin-path)/clipssh-paste $(BUILD_DIR)/clipssh-paste

test:
	swift test

clean:
	swift package clean
	rm -rf .build $(BUILD_DIR)
