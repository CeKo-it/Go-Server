# ===== Config =====
# Binary-Name (ohne Endung)
BINARY       ?= myserver
# Einstiegspunkt (Main-Paket)
MAIN         ?= ./main.go       # oder z.B. ./cmd/server
# Remote-Ziel (Raspberry Pi)
PI_USER      ?= cedric-Pi
PI_HOST      ?= 192.168.188.177
PI_PATH      ?= /home/$(PI_USER)/go-project/$(BINARY)
# Go-Versionierung (optional)
VERSION      ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
COMMIT       ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
DATE         ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

# Build-Flags
GOFLAGS      ?=
LDFLAGS      ?= -s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.date=$(DATE)
# Ausgabeverzeichnis
BIN_DIR      ?= bin

# ===== Targets =====
.PHONY: all build run test clean tidy fmt vet lint \
        pi-armv6 pi-armv7 pi-arm64 deploy-pi install-service uninstall-service logs

all: build

# Lokal (deine Desktop-Architektur)
build:
	@mkdir -p $(BIN_DIR)
	go build $(GOFLAGS) -trimpath -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(BINARY) $(MAIN)

run:
	go run $(MAIN)

test:
	go test ./...

fmt:
	go fmt ./...

vet:
	go vet ./...

# Optional: wenn du golangci-lint nutzt (install: https://golangci-lint.run)
lint:
	golangci-lint run

tidy:
	go mod tidy

clean:
	rm -rf $(BIN_DIR)

# ===== Cross-Compile für Raspberry Pi =====
# Pi Zero / 1 (ARMv6, 32-bit)
pi-armv6:
	@mkdir -p $(BIN_DIR)
	GOOS=linux GOARCH=arm GOARM=6 CGO_ENABLED=0 \
	go build $(GOFLAGS) -trimpath -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(BINARY)-armv6 $(MAIN)

# Pi 2/3/4 (32-bit OS, ARMv7)
pi-armv7:
	@mkdir -p $(BIN_DIR)
	GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
	go build $(GOFLAGS) -trimpath -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(BINARY)-armv7 $(MAIN)

# Pi 3/4/5 (64-bit OS, ARM64)
pi-arm64:
	@mkdir -p $(BIN_DIR)
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
	go build $(GOFLAGS) -trimpath -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(BINARY)-arm64 $(MAIN)

# ===== Deploy auf den Pi (nimmt arm64 als Default; ändere bei Bedarf) =====
deploy-pi: pi-arm64
	scp $(BIN_DIR)/$(BINARY)-arm64 $(PI_USER)@$(PI_HOST):$(PI_PATH)
	ssh $(PI_USER)@$(PI_HOST) "chmod +x $(PI_PATH) && $(PI_PATH) &>/dev/null & disown || true"
	@echo "Deployed to $(PI_USER)@$(PI_HOST):$(PI_PATH)"

# ===== systemd Service (optional) =====
# Generiert/Installiert eine einfache systemd-Unit und startet den Dienst.
install-service:
	@echo "[Unit]\nDescription=$(BINARY)\nAfter=network-online.target\n\n[Service]\nUser=$(PI_USER)\nExecStart=$(PI_PATH)\nRestart=always\nRestartSec=2\nEnvironment=PORT=8080\n\n[Install]\nWantedBy=multi-user.target" > /tmp/$(BINARY).service
	scp /tmp/$(BINARY).service $(PI_USER)@$(PI_HOST):/tmp/$(BINARY).service
	ssh $(PI_USER)@$(PI_HOST) "\
		sudo mv /tmp/$(BINARY).service /etc/systemd/system/$(BINARY).service && \
		sudo systemctl daemon-reload && \
		sudo systemctl enable --now $(BINARY).service && \
		systemctl status --no-pa
