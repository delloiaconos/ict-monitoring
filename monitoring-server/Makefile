# ICT Monitoring - deployment Makefile
# Makefile lives in the GIT working copy of the monitoring-server.
# Runtime directory: /opt/monitoring-server
#
# Usage:
#   make help
#
# If /opt/monitoring-server needs root permissions:
#   make SUDO=sudo deploy
COMPOSE := docker-compose
SHELL 	:= /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

# Project root (directory containing this Makefile)
SRC_DIR := $(CURDIR)
PROJECT := monitoring-server
DST_DIR := /opt/$(PROJECT)

# Space-separated list of directories to scan
RENDER_PATHS := homer/assets nginx/conf.d

# Only render files ending with this suffix
TEMPLATE_SUFFIX := .template

# What to deploy/exlude into /opt/monitoring-server
INCLUDE_FILES := docker-compose.yml
INCLUDE_PATHS := homer nginx prometheus alertmanager grafana

EXCLUDE_FILES := .DS_Store .env .gitignore .editorconfig .prettier* .vscode
EXCLUDE_PATHS := .svn .git .venv data logs temp

# Optional: if DST_DIR requires root permissions for writing, set SUDO=sudo
SUDO ?=

# Optional: restrict envsubst to these variables (recommended)
# Example: make render VARS='${BASE_DOMAIN} ${GRAFANA_DOMAIN}'
VARS ?=

# Collect templates under the listed paths (paths are relative to repo root)
TEMPLATES := $(shell find $(RENDER_PATHS) -type f -name '*$(TEMPLATE_SUFFIX)')

# ---------- compose rsync filters ----------
RSYNC_INCLUDES := \
  $(foreach f,$(INCLUDE_FILES),--include="/$(f)") \
  $(foreach d,$(INCLUDE_PATHS),--include="/$(d)/") \
  $(foreach d,$(INCLUDE_PATHS),--include="/$(d)/***")

RSYNC_EXCLUDES := \
  $(foreach f,$(EXCLUDE_FILES),--exclude="/$(f)") \
  $(foreach d,$(EXCLUDE_PATHS),--exclude="/$(d)/") \
  $(foreach d,$(EXCLUDE_PATHS),--exclude="/$(d)/***") \
  $(foreach t,$(TEMPLATES),--exclude="/$(t)")

RSYNC_CATCHALL := --exclude="*" 

# ---------- Makefile targets ----------
.DEFAULT_GOAL := sync
.PHONY: prepare deploy sync sync-prune ensure-env up down restart logs status render help

help:
	@echo "Targets:"
	@echo "  make prepare       Create $(DST_DIR) and set ownership"
	@echo "  make render        Render templates to $(DST_DIR) (optionally VARS='${VAR1} ${VAR2}')"
	@echo "  make deploy        Sync files to $(DST_DIR), ensure .env, and $(COMPOSE) up -d"
	@echo "  make sync          Only rsync runtime files to $(DST_DIR)"
	@echo "  make sync-prune    Sync and prune runtime files to $(DST_DIR)"
	@echo "  make ensure-env    Ensure $(DST_DIR)/.env contains COMPOSE_PROJECT_NAME=$(PROJECT)"
	@echo "  make up            $(COMPOSE) up -d (project=$(PROJECT))"
	@echo "  make down          $(COMPOSE) down (project=$(PROJECT))"
	@echo "  make restart       $(COMPOSE) restart (optionally SERVICE=prometheus)"
	@echo "  make status        $(COMPOSE) ps"
	@echo "  make logs          $(COMPOSE) logs -f (optionally SERVICE=prometheus)"
	@echo ""
	@echo "Variables:"
	@echo "  SUDO=sudo          Use sudo for prepare (if needed)"
	@echo "  SERVICE=prometheus For logs/restart"
	@echo ""
	@echo "Info:"
	@echo "  SRC_DIR=$(SRC_DIR)"
	@echo "  DST_DIR=$(DST_DIR)"
	@echo "  PROJECT=$(PROJECT)"


render:
	@set -euo pipefail; \
	for src in $(TEMPLATES); do \
		rel="$$src"; \
		out="$(DST_DIR)/$${rel%$(TEMPLATE_SUFFIX)}"; \
		mkdir -p "$$(dirname "$$out")"; \
		if [ -n "$(VARS)" ]; then \
			envsubst '$(VARS)' < "$$src" > "$$out"; \
		else \
			envsubst < "$$src" > "$$out"; \
		fi; \
		echo "Rendered $$src -> $$out"; \
	done

list:
	@printf "%s\n" $(TEMPLATES)

clean:
	@rm -rf "$(DST_DIR)"

deploy: prepare sync render ensure-env up status
	@echo "Done."

prepare:
	@echo "Creating $(DST_DIR) and setting ownership to current user and docker group..."
	$(SUDO) mkdir -p "$(DST_DIR)"
	$(SUDO) chown -R $(shell id -un):docker "$(DST_DIR)"
	$(SUDO) chmod 775 "$(DST_DIR)"

sync-prune:
	@echo "Sync project runtime files from $(SRC_DIR) to $(DST_DIR)..."
	$(SUDO) rsync -a --delete \
		$(RSYNC_EXCLUDES) $(RSYNC_INCLUDES) $(RSYNC_CATCHALL) \
		"$(SRC_DIR)/" "$(DST_DIR)/"
	@echo "Done."

sync:
	@echo "Sync project runtime files from $(SRC_DIR) to $(DST_DIR)..."
	$(SUDO) rsync -a \
		$(RSYNC_EXCLUDES) $(RSYNC_INCLUDES) $(RSYNC_CATCHALL) \
		"$(SRC_DIR)/" "$(DST_DIR)/"
	@echo "Done."

ensure-env:
	@echo "Ensure project name is '$(PROJECT)'..."
	@if [ ! -f "$(DST_DIR)/.env" ]; then \
		echo "COMPOSE_PROJECT_NAME=$(PROJECT)" | $(SUDO) tee "$(DST_DIR)/.env" >/dev/null; \
	fi

up:
	@echo "Start/restart stack from $(DST_DIR)..."
	cd "$(DST_DIR)" && $(SUDO) $(COMPOSE) -p "$(PROJECT)" up -d

down:
	cd "$(DST_DIR)" && $(SUDO) $(COMPOSE) -p "$(PROJECT)" down

restart:
	cd "$(DST_DIR)" && $(SUDO) $(COMPOSE) -p "$(PROJECT)" restart $(SERVICE)

status:
	cd "$(DST_DIR)" && $(SUDO) $(COMPOSE) -p "$(PROJECT)" ps

logs:
	cd "$(DST_DIR)" && $(SUDO) $(COMPOSE) -p "$(PROJECT)" logs -f $(SERVICE)
