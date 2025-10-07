# ===============================
# 🚀 SUPER_WRITER - smart CLI tool for generating technical contents
# ===============================

.PHONY: help install setup clean lint test

# Configuration
SRC_TARGETS = main.py

# ===============================
# 📋 HELP & INFORMATION
# ===============================

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "} {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# ===============================
# 📦 ENVIRONMENT PREPARATION
# ===============================

install: ## Install all dependencies and setup environment
	@if [ -n "$$VIRTUAL_ENV" ]; then deactivate 2>/dev/null || true; fi
	@rm -rf .venv >/dev/null 2>&1 || true
	@uv venv .venv --python 3.10
	@uv sync >/dev/null 2>&1 || (echo "❌ Failed to install Python dependencies" && exit 1)
	@if ! command -v wrangler >/dev/null 2>&1; then \
		npm install -g wrangler >/dev/null 2>&1 || (echo "❌ Failed to install wrangler" && exit 1); \
	fi
	@echo "✅ Environment ready! Run 'source .venv/bin/activate' to activate"

setup: install ## Complete project setup (alias for install)

clean: ## Clean build artifacts and cache files
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@find . -name "*.pyo" -delete 2>/dev/null || true
	@rm -rf build logs .mypy_cache .pytest_cache .ruff_cache .playwright-mcp .coverage 2>/dev/null || true
	@echo "✅ Cleaned build artifacts and cache files"

# ===============================
# 🔧 LOCAL DEVELOPMENT
# ===============================

lint: ## Run all code quality checks
	uv run ruff check $(SRC_TARGETS) --fix
	uv run mypy $(SRC_TARGETS)
	uv run basedpyright $(SRC_TARGETS)


test: ## Run unit tests with coverage
	@PYTHONPATH=. uv run pytest tests/unit --cov=faster --cov-report=html:build/htmlcov -q

# test-e2e: ## Run E2E tests (shows output for debugging)
# 	@echo "🧪 Running E2E tests..."
# 	@make dev >/dev/null 2>&1 &
# 	@sleep 3
# 	@PYTHONPATH=. uv run python tests/e2e/wait_for_server.py >/dev/null 2>&1
# 	@E2E_AUTOMATED=true PYTHONPATH=. uv run pytest tests/e2e/ -v || \
# 		(echo "❌ E2E tests failed - check authentication with 'make test-e2e-check'" && pkill -f "uvicorn main:app" 2>/dev/null || true && exit 1)
# 	@pkill -f "uvicorn main:app" 2>/dev/null || true
# 	@echo "✅ E2E tests passed"

# ===============================
# 🧹 MISCELLANEOUS
# ===============================
