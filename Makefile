SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

.PHONY: help android windows macos ios linux download

help:
	@echo "Targets:"
	@echo "  make download              fetch sources"
	@echo "  make android               libmpv for all Android ABIs"
	@echo "  make windows               libmpv for Windows x86_64"
	@echo "  make macos                 libmpv for macOS universal"
	@echo "  make ios                   libmpv for iOS arm64"
	@echo "  make linux                 libmpv for host Linux (Ubuntu)"
	@echo "  bash ./scripts/build.sh --help  full CLI"

download:
	bash ./scripts/download.sh

android:
	bash ./scripts/build.sh --os android --arch all

windows:
	bash ./scripts/build.sh --os windows --arch x86_64

macos:
	bash ./scripts/build.sh --os macos --arch universal

ios:
	bash ./scripts/build.sh --os ios --arch arm64

linux:
	bash ./scripts/build.sh --os linux --arch all
