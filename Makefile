APP_NAME := FocusBlocker
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
TARGET_APP := /Applications/$(APP_NAME).app

.PHONY: build run install launch-agent clean

build:
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(MACOS_DIR)"
	cp "App/Info.plist" "$(CONTENTS_DIR)/Info.plist"
	swiftc "Sources/$(APP_NAME).swift" \
		-o "$(MACOS_DIR)/$(APP_NAME)" \
		-framework AppKit \
		-framework Carbon
	@echo "Built $(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

install: build
	@if [ -w /Applications ]; then \
		rm -rf "$(TARGET_APP)"; \
		ditto "$(APP_BUNDLE)" "$(TARGET_APP)"; \
	else \
		echo "Installing to /Applications requires administrator permission."; \
		sudo rm -rf "$(TARGET_APP)"; \
		sudo ditto "$(APP_BUNDLE)" "$(TARGET_APP)"; \
	fi
	@echo "Installed $(TARGET_APP)"

launch-agent: build
	./scripts/install-startup.sh

clean:
	rm -rf "$(BUILD_DIR)"
