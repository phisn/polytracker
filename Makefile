APP    := PolyTracker
BIN     := .build/release/$(APP)
BUNDLE  := $(APP).app

.PHONY: build run app clean

build:
	swift build -c release

# Run straight from SwiftPM for development (menu bar item appears immediately).
run:
	swift run

# Assemble a proper double-clickable .app bundle (LSUIElement = menu-bar only).
app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@echo "Built ./$(BUNDLE) — double-click it or run: open ./$(BUNDLE)"

clean:
	rm -rf .build $(BUNDLE)
