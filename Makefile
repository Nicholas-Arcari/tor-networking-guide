# Makefile — Tor Networking Guide
# Comandi rapidi per validazione, test, statistiche e manutenzione
#
# Uso: make help

.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help validate smoke test stats lint setup clean

help:  ## Mostra tutti i target disponibili
	@echo "Tor Networking Guide — Comandi disponibili:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  make %-12s %s\n", $$1, $$2}'
	@echo ""

validate:  ## Valida struttura e contenuto della documentazione
	@bash tests/validate-docs.sh

smoke:  ## Smoke test Tor (richiede Tor attivo)
	@echo "ATTENZIONE: richiede Tor in esecuzione"
	@bash tests/smoke-test-tor.sh

test: validate  ## Esegue i test offline (alias per validate)

stats:  ## Mostra statistiche del progetto
	@echo "=== Statistiche Progetto ==="
	@echo ""
	@printf "Sezioni:        %d\n" $$(find docs -mindepth 1 -maxdepth 1 -type d | wc -l)
	@printf "Documenti .md:  %d\n" $$(find docs -name '*.md' | wc -l)
	@printf "Righe totali:   %d\n" $$(find docs -name '*.md' -exec cat {} + | wc -l)
	@printf "Script:         %d\n" $$(find scripts -name '*.example' | wc -l)
	@printf "Config:         %d\n" $$(find config-examples -name '*.example' | wc -l)
	@printf "Test:           %d\n" $$(find tests -name '*.sh' | wc -l)
	@echo ""

lint:  ## Lint markdown (richiede markdownlint-cli)
	@if command -v markdownlint >/dev/null 2>&1; then \
		markdownlint 'docs/**/*.md' README.md; \
	else \
		echo "markdownlint non installato."; \
		echo "Installa con: npm install -g markdownlint-cli"; \
		echo ""; \
		echo "Eseguo validate-docs.sh come alternativa..."; \
		bash tests/validate-docs.sh; \
	fi

setup:  ## Installa e configura Tor (richiede sudo)
	@sudo bash setup.sh

clean:  ## Rimuove file temporanei
	@find . -name '*.bak' -delete 2>/dev/null || true
	@find . -name '*~' -delete 2>/dev/null || true
	@find . -name '.DS_Store' -delete 2>/dev/null || true
	@echo "Pulizia completata."
