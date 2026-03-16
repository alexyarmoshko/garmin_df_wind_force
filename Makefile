SHELL := bash

# Load .env if present (KEY, SDK_HOME, etc.)
-include .env

# --- Configuration -----------------------------------------------------------
CIQ_HOME ?= $(error CIQ_HOME not set — add it to .env)
SDK_HOME ?= $(error SDK_HOME not set — add it to .env)
KEY      ?= $(error KEY not set — add it to .env)
JUNGLE   := monkey.jungle
DEVICE   := instinct2x
APP      := WindForce

MC  := "$(SDK_HOME)/bin/monkeyc"
OUT := bin

# --- Targets -----------------------------------------------------------------

.PHONY: build dist clean info

build: $(OUT)/$(APP).prg

$(OUT)/$(APP).prg: $(wildcard source/*.mc) $(wildcard resources/**/*.xml) manifest.xml $(JUNGLE)
	@$(MC) -w -d $(DEVICE) -l 3 -f $(JUNGLE) -y $(KEY) -o $@

dist: $(OUT)/$(APP).iq

$(OUT)/$(APP).iq: $(wildcard source/*.mc) $(wildcard resources/**/*.xml) manifest.xml $(JUNGLE)
	@$(MC) -e -w -r -f $(JUNGLE) -y $(KEY) -o $@

clean:
	@rm -f $(OUT)/*.prg $(OUT)/*.prg.debug.xml $(OUT)/*-settings.json \
	      $(OUT)/*.iq $(OUT)/build_log.zip
	@rm -rf $(OUT)/gen $(OUT)/mir $(OUT)/internal-mir $(OUT)/external-mir

info:
	@awk '\
	  /iq:application/  { app=1 } \
	  app && /type="/    { match($$0, /type="([^"]+)"/, t);    printf "Type:     %s\n", t[1] } \
	  app && /version="/ { match($$0, /version="([^"]+)"/, v); printf "Version:  %s\n", v[1] } \
	  /<iq:product id/   { match($$0, /id="([^"]+)"/, d);      printf "Device:   %s\n", d[1] } \
	  /<iq:language>/    { match($$0, />([^<]+)</, l);          printf "Language: %s\n", l[1] } \
	' manifest.xml
	@echo "SDK:      $(SDK_HOME)"
	@echo "Key:      $(KEY)"
