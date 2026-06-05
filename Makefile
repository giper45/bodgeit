ifeq ($(OS),Windows_NT)
SETUP_CMD = powershell -ExecutionPolicy Bypass -File .\scripts\windows\setup-portable-tomcat.ps1
START_CMD = powershell -ExecutionPolicy Bypass -File .\scripts\windows\start-portable-tomcat.ps1
STOP_CMD = powershell -ExecutionPolicy Bypass -File .\scripts\windows\stop-portable-tomcat.ps1
BUNDLE_CMD = powershell -ExecutionPolicy Bypass -File .\scripts\windows\bundle-portable-tomcat.ps1
PLATFORM_LABEL = windows
else
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
SCRIPT_DIR = scripts/darwin
PLATFORM_LABEL = darwin
else
SCRIPT_DIR = scripts/linux
PLATFORM_LABEL = linux
endif
SETUP_CMD = ./$(SCRIPT_DIR)/setup-portable-tomcat.sh
START_CMD = ./$(SCRIPT_DIR)/start-portable-tomcat.sh
STOP_CMD = ./$(SCRIPT_DIR)/stop-portable-tomcat.sh
BUNDLE_CMD = ./$(SCRIPT_DIR)/bundle-portable-tomcat.sh
endif

.PHONY: help setup start stop bundle platform

help:
	@echo "Platform: $(PLATFORM_LABEL)"
	@echo "Targets:"
	@echo "  make setup"
	@echo "  make start"
	@echo "  make stop"
	@echo "  make bundle"

platform:
	@echo "$(PLATFORM_LABEL)"

setup:
	$(SETUP_CMD)

start:
	$(START_CMD)

stop:
	$(STOP_CMD)

bundle:
	$(BUNDLE_CMD)
