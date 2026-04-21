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
PROXY_DIR := proxy
PROXY_ENV_FILE := $(abspath .env)
GEN_DIR := source/gen
GEN_ENV_MC := $(GEN_DIR)/Env.mc
APP_AUTH_SECRET_NBYTES ?= 48

OUT := bin

# --- Targets -----------------------------------------------------------------

.PHONY: build dist clean info \
	proxy-config proxy-dev proxy-deploy proxy-clean proxy-info proxy-typecheck proxy-test proxy-test-e2e proxy-secret-app-auth \
	app-auth-secret-ensure app-auth-secret-generate FORCE

build: $(OUT)/$(APP).prg

FORCE:

app-auth-secret-ensure:
	@$(ENV_SETUP); \
	: "$${APP_AUTH_SECRET_FILE:?APP_AUTH_SECRET_FILE not set - add it to .env}"; \
	if [ ! -f "$$APP_AUTH_SECRET_FILE" ] || [ ! -s "$$APP_AUTH_SECRET_FILE" ]; then \
		mkdir -p "$$(dirname "$$APP_AUTH_SECRET_FILE")"; \
		head -c "$(APP_AUTH_SECRET_NBYTES)" /dev/urandom | base64 | tr -d '\r\n' > "$$APP_AUTH_SECRET_FILE"; \
		echo "Generated APP_AUTH_SECRET_FILE at $$APP_AUTH_SECRET_FILE"; \
	fi

app-auth-secret-generate:
	@$(ENV_SETUP); \
	: "$${APP_AUTH_SECRET_FILE:?APP_AUTH_SECRET_FILE not set - add it to .env}"; \
	mkdir -p "$$(dirname "$$APP_AUTH_SECRET_FILE")"; \
	head -c "$(APP_AUTH_SECRET_NBYTES)" /dev/urandom | base64 | tr -d '\r\n' > "$$APP_AUTH_SECRET_FILE"; \
	echo "Regenerated APP_AUTH_SECRET_FILE at $$APP_AUTH_SECRET_FILE"

$(GEN_ENV_MC): .env Makefile $(APP_MANIFEST_FILE) app-auth-secret-ensure FORCE
	@$(ENV_SETUP); \
	: "$${APP_AUTH_SECRET_FILE:?APP_AUTH_SECRET_FILE not set - add it to .env}"; \
	test -f "$$APP_AUTH_SECRET_FILE" || { echo "APP_AUTH_SECRET_FILE not found at $$APP_AUTH_SECRET_FILE"; exit 1; }; \
	APP_ID="$$(awk '/<iq:application / { if (match($$0, / id="([^"]+)"/, m)) { print m[1]; exit } }' "$(APP_MANIFEST_FILE)")"; \
	APP_VER="$$(awk '/<iq:application / { if (match($$0, / version="([^"]+)"/, m)) { print m[1]; exit } }' "$(APP_MANIFEST_FILE)")"; \
	[ -n "$$APP_ID" ] || { echo "Failed to parse APP_ID from $(APP_MANIFEST_FILE)"; exit 1; }; \
	[ -n "$$APP_VER" ] || { echo "Failed to parse APP_VER from $(APP_MANIFEST_FILE)"; exit 1; }; \
	APP_AUTH_SECRET="$$(tr -d '\r\n' < "$$APP_AUTH_SECRET_FILE")"; \
	[ -n "$$APP_AUTH_SECRET" ] || { echo "APP_AUTH_SECRET_FILE at $$APP_AUTH_SECRET_FILE is empty"; exit 1; }; \
	APP_AUTH_SECRET_ESCAPED="$${APP_AUTH_SECRET//\\/\\\\}"; \
	APP_AUTH_SECRET_ESCAPED="$${APP_AUTH_SECRET_ESCAPED//\"/\\\"}"; \
	APP_ID_ESCAPED="$${APP_ID//\\/\\\\}"; \
	APP_ID_ESCAPED="$${APP_ID_ESCAPED//\"/\\\"}"; \
	APP_VER_ESCAPED="$${APP_VER//\\/\\\\}"; \
	APP_VER_ESCAPED="$${APP_VER_ESCAPED//\"/\\\"}"; \
	mkdir -p "$(GEN_DIR)"; \
	printf '%s\n' \
		'(:background)' \
		'module Env {' \
		"    const FORECAST_URL = \"$$BASE_URL/v1/forecast\";" \
		"    const APP_AUTH_SECRET = \"$$APP_AUTH_SECRET_ESCAPED\";" \
		"    const APP_ID = \"$$APP_ID_ESCAPED\";" \
		"    const APP_VER = \"$$APP_VER_ESCAPED\";" \
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

proxy-config proxy-dev proxy-deploy proxy-clean proxy-info proxy-typecheck proxy-test proxy-test-e2e proxy-secret-app-auth:
	@$(MAKE) -C "$(PROXY_DIR)" ROOT_ENV_FILE="$(PROXY_ENV_FILE)" $(patsubst proxy-%,%,$@)

proxy-secret-app-auth: app-auth-secret-ensure
