SHELL := bash

ROOT_ENV_FILE ?= ../.env
YQ ?= yq.exe
WRANGLER ?= npx --no-install wrangler
WRANGLER_TEMPLATE := wrangler.jsonc.template
WRANGLER_GEN_DIR := .wrangler/gen
WRANGLER_CONFIG := $(WRANGLER_GEN_DIR)/wrangler.jsonc
WRANGLER_COMPAT_DATE ?= 2026-04-20
WRANGLER_SCHEMA_PATH := ../../node_modules/wrangler/config-schema.json
WRANGLER_MAIN_PATH := ../../src/index.ts

ENV_SETUP := test -f "$(ROOT_ENV_FILE)" || { echo "Root .env not found at $(ROOT_ENV_FILE)"; exit 1; }; \
	set -a; source "$(ROOT_ENV_FILE)"; set +a; \
	: "$${PROXY_NAME:?PROXY_NAME not set - add it to .env}"; \
	: "$${PROXY_KV_ID:?PROXY_KV_ID not set - add it to .env}"; \
	: "$${PROXY_ZONE:?PROXY_ZONE not set - add it to .env}"; \
	: "$${BASE_NAME:?BASE_NAME not set - add it to .env}"

.PHONY: config dev deploy clean info typecheck test test-e2e secret-app-auth

config: $(WRANGLER_CONFIG)

$(WRANGLER_CONFIG): $(WRANGLER_TEMPLATE) Makefile $(ROOT_ENV_FILE)
	@$(ENV_SETUP); \
	mkdir -p "$(WRANGLER_GEN_DIR)"; \
	YQ_BIN="$(YQ)"; \
	if ! command -v "$$YQ_BIN" >/dev/null 2>&1 && [ ! -x "$$YQ_BIN" ]; then \
		echo "$$YQ_BIN not found. Install mikefarah/yq and ensure it is on PATH, or pass YQ=/full/path/to/yq.exe"; \
		exit 1; \
	fi; \
	export PROXY_ROUTE_PATTERN="$${PROXY_ROUTE_PATTERN:-$${BASE_NAME}/*}"; \
	export WRANGLER_COMPAT_DATE="$(WRANGLER_COMPAT_DATE)"; \
	"$$YQ_BIN" -p json -o json '.["$$schema"] = "$(WRANGLER_SCHEMA_PATH)" | .name = strenv(PROXY_NAME) | .main = "$(WRANGLER_MAIN_PATH)" | .compatibility_date = strenv(WRANGLER_COMPAT_DATE) | .workers_dev = false | .route.pattern = strenv(PROXY_ROUTE_PATTERN) | .route.zone_name = strenv(PROXY_ZONE) | .kv_namespaces = [{"binding": "FORECAST_CACHE", "id": strenv(PROXY_KV_ID)}] | .secrets.required = ["APP_AUTH_SECRET"] | .observability.enabled = true | .observability.logs.enabled = true | .observability.logs.invocation_logs = true' "$(WRANGLER_TEMPLATE)" > "$(WRANGLER_CONFIG)"

dev: config
	@$(WRANGLER) dev --config "$(WRANGLER_CONFIG)"

deploy: config
	@$(WRANGLER) deploy --config "$(WRANGLER_CONFIG)"

secret-app-auth: config
	@$(ENV_SETUP); \
	: "$${APP_AUTH_SECRET_FILE:?APP_AUTH_SECRET_FILE not set - add it to .env}"; \
	test -f "$$APP_AUTH_SECRET_FILE" || { echo "APP_AUTH_SECRET_FILE not found at $$APP_AUTH_SECRET_FILE"; exit 1; }; \
	$(WRANGLER) secret put APP_AUTH_SECRET --config "$(WRANGLER_CONFIG)" < "$$APP_AUTH_SECRET_FILE"

typecheck:
	@npx --no-install tsc --noEmit

test:
	@npx --no-install vitest run

test-e2e:
	@bash test/e2e.sh

info: config
	@echo "Template: $(WRANGLER_TEMPLATE)"
	@echo "Generated config: $(WRANGLER_CONFIG)"
	@echo "Root env: $(ROOT_ENV_FILE)"
	@echo "YQ: $(YQ)"

clean:
	@rm -f "$(WRANGLER_CONFIG)"
