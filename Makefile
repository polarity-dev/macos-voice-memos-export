PREFIX ?= $(HOME)/.local
APP_DIR ?= $(HOME)/Applications
APP := VoiceMemosExport.app
BROKER := $(APP)/Contents/MacOS/VoiceMemosExport
CLI := .build/voice-memos

.PHONY: build check clean install uninstall

build:
	./scripts/build-app.sh

check: build
	bash -n scripts/build-app.sh
	codesign --verify --deep --strict $(APP)
	$(CLI) --version
	$(CLI) --help >/dev/null

clean:
	rm -rf $(APP) .build

install: build
	mkdir -p "$(APP_DIR)" "$(PREFIX)/bin"
	rm -rf "$(APP_DIR)/$(APP)"
	cp -R "$(APP)" "$(APP_DIR)/$(APP)"
	rm -f "$(PREFIX)/bin/voice-memos"
	cp "$(CLI)" "$(PREFIX)/bin/voice-memos"
	chmod 755 "$(PREFIX)/bin/voice-memos"
	@printf 'Installed app: %s\n' "$(APP_DIR)/$(APP)"
	@printf 'Installed CLI: %s\n' "$(PREFIX)/bin/voice-memos"
	@printf 'Grant Full Disk Access to the installed app before use.\n'

uninstall:
	rm -f "$(PREFIX)/bin/voice-memos"
	rm -rf "$(APP_DIR)/$(APP)"
