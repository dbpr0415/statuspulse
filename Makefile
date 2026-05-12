# =============================================================================
# StatusPulse — Makefile
# Shortcuts for common Docker operations
# =============================================================================

.PHONY: build up down logs test clean shell help

# Default target
help: ## Show this help message
	@echo ""
	@echo "StatusPulse — Available Commands:"
	@echo "-----------------------------------"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36mmake %-12s\033[0m %s\n", $$1, $$2}'
	@echo ""

build: ## Build the Docker image
	docker compose build

up: ## Start all services (detached)
	docker compose up -d --build

down: ## Stop all services
	docker compose down

logs: ## Tail logs from all services
	docker compose logs -f

test: ## Health check the running service via curl
	@echo "=== StatusPulse Health Check ==="
	@curl -s http://localhost:$${APP_PORT:-8000}/health | python3 -m json.tool && \
		echo "\n✅ Health check PASSED" || \
		(echo "\n❌ Health check FAILED" && exit 1)

clean: ## Remove containers, images, and volumes
	docker compose down -v --rmi all --remove-orphans
	@echo "✅ All containers, images, and volumes removed"

shell: ## Open bash inside the running app container
	docker compose exec app bash || docker compose exec app sh

restart: ## Restart all services
	docker compose restart

ps: ## Show running containers and their status
	docker compose ps
