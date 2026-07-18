# Amiga emulator Docker images — convenience wrapper around the docker CLI.
# Per-app targets require APP to be named explicitly (no default), e.g.:
#   make up APP=amiberry       # port 8443
#   make up APP=copperline     # port 8444
DOCKER    ?= docker
APPS      := amiberry copperline
IMAGE     ?= ghcr.io/sidick/$(APP):latest
NAME      ?= $(APP)
VOLUME    ?= $(APP)-config

# Default ports don't collide, so both emulators can run side by side.
ifeq ($(APP),copperline)
PORT      ?= 8444
else
PORT      ?= 8443
endif

# Runtime settings. VNC_USER defaults to $(APP) inside the image; the
# password defaults to the username unless overridden here.
VNC_PASSWORD ?= $(APP)
RUN_ARGS = --name $(NAME) \
	--restart unless-stopped \
	-p $(PORT):8443 \
	-e VNC_GEOMETRY=1280x960 \
	-e VNC_DEPTH=24 \
	-e VNC_PASSWORD=$(VNC_PASSWORD) \
	-v $(VOLUME):/config \
	--shm-size 512m

.DEFAULT_GOAL := help

.PHONY: help require-app up down start stop restart pull build build-all logs ps shell clean prune

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v '^require-app' | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}'
	@echo "\nPer-app targets need APP set, e.g. 'make up APP=amiberry' or 'make up APP=copperline'"

require-app:
	@if [ -z "$(APP)" ]; then \
		echo "APP is not set. Use e.g. 'make $(word 1,$(MAKECMDGOALS)) APP=amiberry' (valid: $(APPS))" >&2; exit 1; \
	fi
	@case " $(APPS) " in *" $(APP) "*) ;; *) \
		echo "Unknown APP '$(APP)' (valid: $(APPS))" >&2; exit 1;; esac

up: require-app ## Create and start the container in the background (pulls image if needed)
	$(DOCKER) run -d $(RUN_ARGS) $(IMAGE)

down: require-app ## Stop and remove the container (keeps the config volume)
	-$(DOCKER) rm -f $(NAME)

start: require-app ## Start an existing stopped container
	$(DOCKER) start $(NAME)

stop: require-app ## Stop the running container without removing it
	$(DOCKER) stop $(NAME)

restart: require-app ## Restart the container
	$(DOCKER) restart $(NAME)

pull: require-app ## Pull the latest image from the registry
	$(DOCKER) pull $(IMAGE)

build: require-app ## Build the image locally from this checkout
	$(DOCKER) build --target $(APP) -t $(IMAGE) .

build-all: ## Build every app image locally
	$(MAKE) build APP=amiberry
	$(MAKE) build APP=copperline

logs: require-app ## Follow the container logs
	$(DOCKER) logs -f $(NAME)

ps: require-app ## Show container status
	$(DOCKER) ps -a --filter name=^/$(NAME)$$

shell: require-app ## Open a shell in the running container
	$(DOCKER) exec -it $(NAME) /bin/bash

clean: require-app ## Stop, remove the container AND delete the config volume
	-$(DOCKER) rm -f $(NAME)
	-$(DOCKER) volume rm $(VOLUME)

prune: clean ## Full cleanup: clean + remove the image and prune build cache
	-$(DOCKER) rmi $(IMAGE)
	$(DOCKER) builder prune -f
