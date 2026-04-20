SHELL := bash

ENV_SETUP := test -f ".env" || { echo ".env not found"; exit 1; }; \
	set -a; source "./.env"; set +a; \
	: "$${SDK_HOME:?SDK_HOME not set - add it to .env}"; \
	: "$${DEV_KEY:?DEV_KEY not set - add it to .env}"

# --- Configuration -----------------------------------------------------------
JUNGLE   := monkey.jungle
DEVICE   := instinct2x
APP      := WindForce
PROXY_DIR := proxy
PROXY_ENV_FILE := $(abspath .env)

OUT := bin

# --- Targets -----------------------------------------------------------------

.PHONY: build dist clean info \
	proxy-config proxy-dev proxy-deploy proxy-clean proxy-info proxy-typecheck proxy-test proxy-test-e2e

build: $(OUT)/$(APP).prg

$(OUT)/$(APP).prg: $(wildcard source/*.mc) $(wildcard resources/**/*.xml) manifest.xml $(JUNGLE)
	@$(ENV_SETUP); \
	MC="$$SDK_HOME/bin/monkeyc"; \
	"$$MC" -w -d "$(DEVICE)" -l 3 -f "$(JUNGLE)" -y "$$DEV_KEY" -o "$@"

dist: $(OUT)/$(APP).iq

$(OUT)/$(APP).iq: $(wildcard source/*.mc) $(wildcard resources/**/*.xml) manifest.xml $(JUNGLE)
	@$(ENV_SETUP); \
	MC="$$SDK_HOME/bin/monkeyc"; \
	"$$MC" -e -w -r -f "$(JUNGLE)" -y "$$DEV_KEY" -o "$@"

clean:
	@rm -f $(OUT)/*.prg $(OUT)/*.prg.debug.xml $(OUT)/*-settings.json \
	      $(OUT)/*.iq $(OUT)/build_log.zip
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

proxy-config proxy-dev proxy-deploy proxy-clean proxy-info proxy-typecheck proxy-test proxy-test-e2e:
	@$(MAKE) -C "$(PROXY_DIR)" ROOT_ENV_FILE="$(PROXY_ENV_FILE)" $(patsubst proxy-%,%,$@)
