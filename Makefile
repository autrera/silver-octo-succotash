# Makefile for odin-raylib-test
#
# Compiles the project with the Odin compiler, using the raylib bindings that
# ship with Odin (import "vendor:raylib").
#
# Targets:
#   make          - build a debug binary into bin/debug/
#   make run      - build and run the game
#   make release  - build an optimized binary into bin/release/
#   make clean    - remove build output
#
# Works on macOS and Windows (w64devkit terminal). `odin` must be on PATH.

ODIN       ?= odin
# debug | release
BUILD_MODE ?= debug

BIN_DIR := bin/$(BUILD_MODE)
TARGET  := $(BIN_DIR)/odin-raylib-test$(if $(filter Windows_NT,$(OS)),.exe,)

SOURCES := $(wildcard src/*.odin)

ODIN_FLAGS := -out:$(TARGET)
ifeq ($(BUILD_MODE),release)
ODIN_FLAGS += -o:speed
else
ODIN_FLAGS += -debug
endif

# Recipes run under sh (macOS/WSL/w64devkit terminal) or cmd.exe (plain
# Windows). Detect which so mkdir/clean work in both.
ifeq ($(shell echo "test"), "test")
MKDIR_CMD := if not exist "$(subst /,\,$(BIN_DIR))" mkdir "$(subst /,\,$(BIN_DIR))"
RM_CMD    := if exist "$(subst /,\,$(BIN_DIR))" rd /s /q "$(subst /,\,$(BIN_DIR))"
else
MKDIR_CMD := mkdir -p $(BIN_DIR)
RM_CMD    := rm -rf bin
endif

.PHONY: all run release clean

all: $(TARGET)

$(TARGET): $(SOURCES)
	@$(MKDIR_CMD)
	$(ODIN) build src $(ODIN_FLAGS)
	@echo "Built $(TARGET)"

run: $(TARGET)
	$(TARGET)

release:
	$(MAKE) BUILD_MODE=release

clean:
	@$(RM_CMD)
