# Change this variable to your specific directory
SOURCE_DIR := private

# Recursive function to find all files in subdirectories
find_files = $(wildcard $1/*) $(foreach d, $(wildcard $1/*), $(call find_files,$d))

# Get a list of all files in the source directory and its subdirectories
FILES := $(call find_files,$(SOURCE_DIR))

# Compute the target file paths in the root directory
TARGET_FILES := $(patsubst $(SOURCE_DIR)/%,$(CURDIR)/%,$(FILES))

all: symlinks

symlinks: $(TARGET_FILES)

$(TARGET_FILES):
	@mkdir -p $(dir $@)
	@ln -sfr $(abspath $(patsubst $(CURDIR)/%, $(SOURCE_DIR)/%, $@)) $@
