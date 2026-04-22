COMPOSE_PROJECT_NAME ?= ftps-local
COMPOSE_ARGS = -p $(COMPOSE_PROJECT_NAME) -f docker-compose.yaml
ENV_TEMPLATE = .env.local.example
TEST_ARGS ?=

.PHONY: certs ensure-env up down test connect

certs:
	@mkdir -p certs
	@if [ -f certs/server.key ] && [ -f certs/server.crt ] && [ -f certs/ftps.pem ]; then \
		echo "Local certs already exist in app/certs"; \
	else \
		echo "Generating local self-signed FTPS certs in app/certs"; \
		openssl req -x509 -newkey rsa:2048 \
			-keyout certs/server.key \
			-out certs/server.crt \
			-sha256 -days 365 -nodes \
			-subj '/CN=ftps.local' >/dev/null 2>&1; \
		cat certs/server.key certs/server.crt > certs/ftps.pem; \
	fi


ensure-env:
	@if [ -f .env ]; then \
		echo "Local .env already exists in app/.env"; \
	else \
		cp $(ENV_TEMPLATE) .env; \
		echo "Created app/.env from $(ENV_TEMPLATE) for local manual runs"; \
	fi

up: certs ensure-env
	@docker compose $(COMPOSE_ARGS) up -d --build

down:
	@docker compose $(COMPOSE_ARGS) down -v --remove-orphans

test:
	@./test-local-ftps.sh $(TEST_ARGS)

connect:
	@container_id="$$(docker compose $(COMPOSE_ARGS) ps -q ftps)"; \
	if [ -z "$$container_id" ] || [ "$$(docker inspect -f '{{.State.Running}}' $$container_id 2>/dev/null)" != "true" ]; then \
		echo "No container running, please run make up first."; \
		exit 1; \
	fi; \
	docker exec -it "$$container_id" bash