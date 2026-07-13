# Amiberry Docker — convenience wrapper around docker compose
COMPOSE ?= docker compose

.DEFAULT_GOAL := help

IMAGE ?= ghcr.io/sidick/amiberry:latest

.PHONY: help up down start stop restart pull build logs ps shell clean prune

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}'

up: ## Start the container in the background (pulls image if needed)
	$(COMPOSE) up -d

down: ## Stop and remove the container (keeps the config volume)
	$(COMPOSE) down

start: ## Start an existing stopped container
	$(COMPOSE) start

stop: ## Stop the running container without removing it
	$(COMPOSE) stop

restart: ## Restart the container
	$(COMPOSE) restart

pull: ## Pull the latest image from the registry
	$(COMPOSE) pull

build: ## Build the image locally from this checkout
	$(COMPOSE) build

logs: ## Follow the container logs
	$(COMPOSE) logs -f

ps: ## Show container status
	$(COMPOSE) ps

shell: ## Open a shell in the running container
	$(COMPOSE) exec amiberry /bin/bash

clean: ## Stop, remove the container AND delete the config volume
	$(COMPOSE) down -v

prune: clean ## Full cleanup: clean + remove the image and prune build cache
	-docker rmi $(IMAGE)
	docker builder prune -f
