# Amiberry Docker — convenience wrapper around the docker CLI
DOCKER    ?= docker
IMAGE     ?= ghcr.io/sidick/amiberry:latest
NAME      ?= amiberry
VOLUME    ?= amiberry-config
PORT      ?= 8443

# Runtime settings (mirrors the previous docker-compose.yml)
RUN_ARGS = --name $(NAME) \
	--restart unless-stopped \
	-p $(PORT):8443 \
	-e VNC_GEOMETRY=1280x960 \
	-e VNC_DEPTH=24 \
	-e VNC_USER=amiberry \
	-e VNC_PASSWORD=amiberry \
	-v $(VOLUME):/config \
	--shm-size 512m

.DEFAULT_GOAL := help

.PHONY: help up down start stop restart pull build logs ps shell clean prune

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}'

up: ## Create and start the container in the background (pulls image if needed)
	$(DOCKER) run -d $(RUN_ARGS) $(IMAGE)

down: ## Stop and remove the container (keeps the config volume)
	-$(DOCKER) rm -f $(NAME)

start: ## Start an existing stopped container
	$(DOCKER) start $(NAME)

stop: ## Stop the running container without removing it
	$(DOCKER) stop $(NAME)

restart: ## Restart the container
	$(DOCKER) restart $(NAME)

pull: ## Pull the latest image from the registry
	$(DOCKER) pull $(IMAGE)

build: ## Build the image locally from this checkout
	$(DOCKER) build -t $(IMAGE) .

logs: ## Follow the container logs
	$(DOCKER) logs -f $(NAME)

ps: ## Show container status
	$(DOCKER) ps -a --filter name=^/$(NAME)$$

shell: ## Open a shell in the running container
	$(DOCKER) exec -it $(NAME) /bin/bash

clean: ## Stop, remove the container AND delete the config volume
	-$(DOCKER) rm -f $(NAME)
	-$(DOCKER) volume rm $(VOLUME)

prune: clean ## Full cleanup: clean + remove the image and prune build cache
	-$(DOCKER) rmi $(IMAGE)
	$(DOCKER) builder prune -f
