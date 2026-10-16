ODIN       ?= odin
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
