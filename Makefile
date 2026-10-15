.PHONY: up up-runners down logs ps config pull subtree-pull

LOCAL_BASE_URL ?=
DISPLAY_BASE_URL = $(if $(LOCAL_BASE_URL),$(LOCAL_BASE_URL),http://localhost:8000)
COMPOSE = $(if $(LOCAL_BASE_URL),BASE_URL=$(LOCAL_BASE_URL) )docker compose
COMPOSE_RUNNERS = $(COMPOSE) --profile runners
SUPERPLANE_REMOTE ?= https://github.com/superplanehq/superplane.git
SUPERPLANE_REF ?= main

up:
	$(COMPOSE) up -d --build --wait
	@echo "SuperPlane is ready at $(DISPLAY_BASE_URL)."

up-runners:
	$(COMPOSE_RUNNERS) up -d --build --wait
	@echo "SuperPlane and the local runner fleet are ready at $(DISPLAY_BASE_URL)."

down:
	$(COMPOSE_RUNNERS) down --remove-orphans

logs:
	$(COMPOSE) logs -f app

ps:
	$(COMPOSE_RUNNERS) ps

config:
	$(COMPOSE_RUNNERS) config --quiet

pull:
	docker compose pull db rabbitmq init fleet-seed

subtree-pull:
	git subtree pull --prefix=superplane $(SUPERPLANE_REMOTE) $(SUPERPLANE_REF) --squash
