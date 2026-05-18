SHELL := bash

ENV_SETUP := test -f ".env" || { echo ".env not found"; exit 1; }; \
	set -a; source "./.env"; set +a; \
	: "$${BASE_URL:?BASE_URL not set - add it to .env}"; \
	: "$${SDK_HOME:?SDK_HOME not set - add it to .env}"; \
	: "$${DEV_KEY:?DEV_KEY not set - add it to .env}"

# --- Configuration -----------------------------------------------------------
JUNGLE   := monkey.jungle
DEVICE   := instinct2x
APP      := WindForce
APP_MANIFEST_FILE := $(abspath manifest.xml)
APP_STRINGS_FILE := $(abspath resources/strings/strings.xml)
GEN_DIR := source/gen
GEN_ENV_MC := $(GEN_DIR)/Env.mc
APP_AUTH_SECRET_NBYTES ?= 48

OUT := bin

# --- Targets -----------------------------------------------------------------

.PHONY: build dist clean info \
	app-auth-secret-ensure app-auth-secret-generate FORCE

build: $(OUT)/$(APP).prg

FORCE:

# Validate that the explicitly configured APP_AUTH_SECRET_FILE exists and is
# non-empty. Never creates a secret -- creation belongs to
# app-auth-secret-generate. A typo in .env must not silently activate a new
# secret.
app-auth-secret-ensure:
	@$(ENV_SETUP); \
	: "$${APP_AUTH_SECRET_FILE:?APP_AUTH_SECRET_FILE not set - add it to .env}"; \
	test -f "$$APP_AUTH_SECRET_FILE" || { echo "APP_AUTH_SECRET_FILE not found at $$APP_AUTH_SECRET_FILE"; exit 1; }; \
	test -s "$$APP_AUTH_SECRET_FILE" || { echo "APP_AUTH_SECRET_FILE at $$APP_AUTH_SECRET_FILE is empty"; exit 1; }

# Create a new non-overwriting timestamped candidate secret file under
# APP_AUTH_SECRET_DIR (default .keys). Prints the APP_AUTH_SECRET_FILE=<path>
# line that the operator must set in .env to activate the candidate. Never
# edits .env. Never switches the active file.
app-auth-secret-generate:
	@$(ENV_SETUP); \
	DIR="$${APP_AUTH_SECRET_DIR:-.keys}"; \
	mkdir -p "$$DIR"; \
	DAY="$$(date -u +%Y%m%d)"; \
	N=1; \
	while :; do \
		CANDIDATE="$$DIR/app_auth_$${DAY}_$$(printf '%02d' $$N).txt"; \
		[ ! -e "$$CANDIDATE" ] && break; \
		N=$$((N + 1)); \
		[ "$$N" -gt 99 ] && { echo "Too many secret rotations on $$DAY (>99)"; exit 1; }; \
	done; \
	head -c "$(APP_AUTH_SECRET_NBYTES)" /dev/urandom | base64 | tr -d '\r\n' > "$$CANDIDATE"; \
	echo "Generated candidate APP_AUTH_SECRET at $$CANDIDATE"; \
	echo "To activate, set in .env:"; \
	echo "  APP_AUTH_SECRET_FILE=$$CANDIDATE"; \
	echo "Then run: make -C proxy secret-app-auth && make build && make dist"

$(GEN_ENV_MC): .env Makefile $(APP_MANIFEST_FILE) $(APP_STRINGS_FILE) app-auth-secret-ensure FORCE
	@$(ENV_SETUP); \
	: "$${APP_AUTH_SECRET_FILE:?APP_AUTH_SECRET_FILE not set - add it to .env}"; \
	test -f "$$APP_AUTH_SECRET_FILE" || { echo "APP_AUTH_SECRET_FILE not found at $$APP_AUTH_SECRET_FILE"; exit 1; }; \
	APP_ID="$$(awk '/<iq:application / { if (match($$0, / id="([^"]+)"/, m)) { print m[1]; exit } }' "$(APP_MANIFEST_FILE)")"; \
	APP_VER="$$(awk '/<iq:application / { if (match($$0, / version="([^"]+)"/, m)) { print m[1]; exit } }' "$(APP_MANIFEST_FILE)")"; \
	APP_NAME="$$(awk '/<string id="AppName">/ { if (match($$0, />([^<]+)</, m)) { print m[1]; exit } }' "$(APP_STRINGS_FILE)")"; \
	[ -n "$$APP_ID" ] || { echo "Failed to parse APP_ID from $(APP_MANIFEST_FILE)"; exit 1; }; \
	[ -n "$$APP_VER" ] || { echo "Failed to parse APP_VER from $(APP_MANIFEST_FILE)"; exit 1; }; \
	[ -n "$$APP_NAME" ] || { echo "Failed to parse AppName from $(APP_STRINGS_FILE)"; exit 1; }; \
	APP_AUTH_SECRET="$$(tr -d '\r\n' < "$$APP_AUTH_SECRET_FILE")"; \
	[ -n "$$APP_AUTH_SECRET" ] || { echo "APP_AUTH_SECRET_FILE at $$APP_AUTH_SECRET_FILE is empty"; exit 1; }; \
	APP_AUTH_SECRET_ESCAPED="$${APP_AUTH_SECRET//\\/\\\\}"; \
	APP_AUTH_SECRET_ESCAPED="$${APP_AUTH_SECRET_ESCAPED//\"/\\\"}"; \
	APP_ID_ESCAPED="$${APP_ID//\\/\\\\}"; \
	APP_ID_ESCAPED="$${APP_ID_ESCAPED//\"/\\\"}"; \
	APP_VER_ESCAPED="$${APP_VER//\\/\\\\}"; \
	APP_VER_ESCAPED="$${APP_VER_ESCAPED//\"/\\\"}"; \
	APP_NAME_ESCAPED="$${APP_NAME//\\/\\\\}"; \
	APP_NAME_ESCAPED="$${APP_NAME_ESCAPED//\"/\\\"}"; \
	mkdir -p "$(GEN_DIR)"; \
	printf '%s\n' \
		'(:background)' \
		'module Env {' \
		"    const FORECAST_URL = \"$$BASE_URL/v1/forecast\";" \
		"    const APP_AUTH_SECRET = \"$$APP_AUTH_SECRET_ESCAPED\";" \
		"    const APP_ID = \"$$APP_ID_ESCAPED\";" \
		"    const APP_VER = \"$$APP_VER_ESCAPED\";" \
		"    const APP_NAME = \"$$APP_NAME_ESCAPED\";" \
		'}' > "$(GEN_ENV_MC)"

$(OUT)/$(APP).prg: $(wildcard source/*.mc) $(wildcard resources/**/*.xml) manifest.xml $(JUNGLE) $(GEN_ENV_MC)
	@$(ENV_SETUP); \
	MC="$$SDK_HOME/bin/monkeyc"; \
	"$$MC" -w -d "$(DEVICE)" -l 3 -f "$(JUNGLE)" -y "$$DEV_KEY" -o "$@"

dist: $(OUT)/$(APP).iq

$(OUT)/$(APP).iq: $(wildcard source/*.mc) $(wildcard resources/**/*.xml) manifest.xml $(JUNGLE) $(GEN_ENV_MC)
	@$(ENV_SETUP); \
	MC="$$SDK_HOME/bin/monkeyc"; \
	"$$MC" -e -w -r -f "$(JUNGLE)" -y "$$DEV_KEY" -o "$@"

clean:
	@rm -f $(OUT)/*.prg $(OUT)/*.prg.debug.xml $(OUT)/*-settings.json \
	      $(OUT)/*.iq $(OUT)/build_log.zip $(GEN_ENV_MC)
	@rm -rf $(OUT)/gen $(OUT)/mir $(OUT)/internal-mir $(OUT)/external-mir

info:
	@$(ENV_SETUP); \
	awk '\
	  /iq:application/  { app=1 } \
	  app && /type="/    { match($$0, /type="([^"]+)"/, t);    printf "Type:     %s\n", t[1] } \
	  app && /version="/ { match($$0, /version="([^"]+)"/, v); printf "Version:  %s\n", v[1] } \
	  /<iq:product id/   { match($$0, /id="([^"]+)"/, d);      printf "Device:   %s\n", d[1] } \
	  /<iq:language>/    { match($$0, />([^<]+)</, l);          printf "Language: %s\n", l[1] } \
	' manifest.xml; \
	echo "SDK:      $$SDK_HOME"; \
	echo "Key:      $$DEV_KEY"
