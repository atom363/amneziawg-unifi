.PHONY: all build-arm64 build-tools build-go clean package

VERSION := 0.1.0
BUILD_DIR := build
DIST_DIR := dist
PACKAGE_NAME := amneziawg-unifi

# ARM64 cross-compilation
GOOS := linux
GOARCH := arm64
CC_ARM64 := aarch64-linux-gnu-gcc

all: build-arm64 package

# Clone dependencies if not present
deps:
	@if [ ! -d "$(BUILD_DIR)/amneziawg-go" ]; then \
		mkdir -p $(BUILD_DIR); \
		git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-go $(BUILD_DIR)/amneziawg-go; \
	fi
	@if [ ! -d "$(BUILD_DIR)/amneziawg-tools" ]; then \
		git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-tools $(BUILD_DIR)/amneziawg-tools; \
	fi

# Build amneziawg-go for ARM64
build-go: deps
	cd $(BUILD_DIR)/amneziawg-go && \
		GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=0 go build -o amneziawg-go .

# Build amneziawg-tools for ARM64
build-tools: deps
	cd $(BUILD_DIR)/amneziawg-tools/src && \
		make clean && \
		CC=$(CC_ARM64) LDFLAGS="-static" make

# Build all ARM64 binaries
build-arm64: build-go build-tools
	mkdir -p $(DIST_DIR)/amneziawg/bin
	cp $(BUILD_DIR)/amneziawg-go/amneziawg-go $(DIST_DIR)/amneziawg/bin/
	cp $(BUILD_DIR)/amneziawg-tools/src/wg $(DIST_DIR)/amneziawg/bin/awg
	cp $(BUILD_DIR)/amneziawg-tools/src/wg-quick/linux.bash $(DIST_DIR)/amneziawg/bin/awg-quick
	chmod +x $(DIST_DIR)/amneziawg/bin/*

# Copy scripts and configs
package: build-arm64
	mkdir -p $(DIST_DIR)/amneziawg/conf
	cp scripts/install.sh $(DIST_DIR)/amneziawg/
	cp scripts/reinstall.sh $(DIST_DIR)/amneziawg/
	cp scripts/setup.sh $(DIST_DIR)/amneziawg/
	cp scripts/amneziawg.service $(DIST_DIR)/amneziawg/
	cp configs/awg0.conf.example $(DIST_DIR)/amneziawg/conf/
	chmod +x $(DIST_DIR)/amneziawg/*.sh
	cd $(DIST_DIR) && tar czf $(PACKAGE_NAME)-$(VERSION)-arm64.tar.gz amneziawg/

# Build in Docker (alternative for cross-compilation)
docker-build:
	docker buildx build --platform linux/arm64 -t amneziawg-builder -f Containerfile.build .
	docker run --rm -v $(PWD)/$(DIST_DIR):/out amneziawg-builder

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)
