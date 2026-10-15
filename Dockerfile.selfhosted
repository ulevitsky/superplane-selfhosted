ARG UBUNTU_VERSION=22.04
ARG GO_VERSION=1.26.2
ARG PLAYWRIGHT_GO_VERSION=v0.6100.0
ARG RUNNER_IMAGE="ubuntu:${UBUNTU_VERSION}"

# Optional CI module caches. `make image.build` replaces these with
# --build-context when tmp/go and tmp/go-build exist. Release builds keep
# the empty stages and download modules as before.
FROM scratch AS ci-go-mod
FROM scratch AS ci-go-build

# ----------------------------------------------------------------------------------------------------------------------
# Development stage with tools installed.
# Used for local development and testing.
# ----------------------------------------------------------------------------------------------------------------------

FROM ubuntu:${UBUNTU_VERSION} AS dev-base

ARG GO_VERSION
ARG PLAYWRIGHT_GO_VERSION

WORKDIR /opt/install
COPY scripts/docker /opt/install-scripts

ENV GO_VERSION=${GO_VERSION}
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/go"
ENV GOBIN="/go/bin"
ENV PATH="${GOBIN}:${PATH}"
ENV GOPROXY="https://proxy.golang.org|direct"
ENV PLAYWRIGHT_BROWSERS_PATH="/ms-playwright"

RUN apt-get update && \
  apt-get install -y --no-install-recommends bash ca-certificates git make unzip && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN bash /opt/install-scripts/install-go.sh "${GO_VERSION}"
RUN bash /opt/install-scripts/install-nodejs.sh
RUN bash /opt/install-scripts/install-postgresql-client.sh
RUN bash /opt/install-scripts/install-gomigrate.sh
RUN bash /opt/install-scripts/install-protoc.sh

RUN export GOMODCACHE=/tmp/go-mod GOCACHE=/tmp/go-build && \
  go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.6 && \
  go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.6.0 && \
  go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@v2.26.3 && \
  go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@v2.26.3 && \
  go install github.com/air-verse/air@latest && \
  go install github.com/mgechev/revive@v1.8.0 && \
  go install gotest.tools/gotestsum@v1.12.3 && \
  go install github.com/mxschmitt/playwright-go/cmd/playwright@"${PLAYWRIGHT_GO_VERSION}" && \
  rm -rf /tmp/go-mod /tmp/go-build /go/pkg/* /root/.cache/* /root/.config/go/telemetry

WORKDIR /app

RUN mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"
RUN playwright install chromium-headless-shell --with-deps
RUN rm -rf /opt/install /opt/install-scripts /tmp/*

COPY scripts/docker/install-bun.sh /tmp/install-bun.sh
RUN bash /tmp/install-bun.sh && rm /tmp/install-bun.sh

CMD [ "/bin/bash",  "-c", "sleep infinity" ]

# ----------------------------------------------------------------------------------------------------------------------
# Builder stage to create production artifacts.
# Used to build the final runner image.
# ----------------------------------------------------------------------------------------------------------------------

FROM dev-base AS builder

ARG BASE_URL=https://app.superplane.com
ARG VITE_ASSET_BASE_URL=
ARG FRONTEND_PREBUILT=0

WORKDIR /app
COPY pkg /app/pkg
COPY ee /app/ee
COPY LICENSE NOTICE /app/
COPY cmd /app/cmd
COPY go.mod /app/go.mod
COPY go.sum /app/go.sum
COPY db/migrations /app/db/migrations
COPY db/data_migrations /app/db/data_migrations
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
COPY web_src /app/web_src
COPY protos /app/protos
COPY api/swagger /app/api/swagger
COPY rbac /app/rbac
COPY templates /app/templates
ENV GOMODCACHE=/go/pkg/mod
ENV GOCACHE=/go/go-build-cache
RUN --mount=from=ci-go-mod,target=/mnt/ci-go-mod \
    --mount=from=ci-go-build,target=/mnt/ci-go-build \
    mkdir -p "${GOMODCACHE}" "${GOCACHE}" && \
    if [ -n "$(ls -A /mnt/ci-go-mod 2>/dev/null)" ]; then \
      cp -a /mnt/ci-go-mod/. "${GOMODCACHE}/"; \
    fi && \
    if [ -n "$(ls -A /mnt/ci-go-build 2>/dev/null)" ]; then \
      cp -a /mnt/ci-go-build/. "${GOCACHE}/"; \
    fi && \
    rm -rf build && go build -o build/superplane cmd/server/main.go

WORKDIR /app/web_src
RUN if [ "$FRONTEND_PREBUILT" = "1" ]; then \
      echo "Using prebuilt frontend assets from build context"; \
    else \
      npm install && \
      if [ -n "$VITE_ASSET_BASE_URL" ]; then \
        NODE_OPTIONS=--max-old-space-size=4096 VITE_BASE_URL=$BASE_URL VITE_ASSET_BASE_URL=$VITE_ASSET_BASE_URL npm run build; \
      else \
        NODE_OPTIONS=--max-old-space-size=4096 VITE_BASE_URL=$BASE_URL npm run build; \
      fi; \
    fi

# ----------------------------------------------------------------------------------------------------------------------
# Demo runner: single-container image with embedded Postgres and RabbitMQ.
# Used to build the demo image.
# ----------------------------------------------------------------------------------------------------------------------

FROM ${RUNNER_IMAGE} AS demo

ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="superplane-demo" \
  org.opencontainers.image.description="SuperPlane demo image with embedded PostgreSQL and RabbitMQ for local trials." \
  org.opencontainers.image.vendor="SuperPlane" \
  org.opencontainers.image.source="https://github.com/superplanehq/superplane" \
  org.opencontainers.image.url="https://superplane.com" \
  org.opencontainers.image.documentation="https://docs.superplane.com"

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  postgresql \
  postgresql-contrib \
  rabbitmq-server \
  ca-certificates \
  curl \
  git && \
  ln -s /usr/lib/postgresql/*/bin/* /usr/local/bin/ && \
  rm -rf /var/lib/apt/lists/*

# Install Node.js for localtunnel.
COPY scripts/docker/install-nodejs.sh /tmp/install-nodejs.sh
RUN bash /tmp/install-nodejs.sh && rm /tmp/install-nodejs.sh

# We still need the PostgreSQL client tools (createdb/migrate) as in the main runner.
COPY scripts/docker/install-postgresql-client.sh /tmp/install-postgresql-client.sh
RUN bash /tmp/install-postgresql-client.sh && rm /tmp/install-postgresql-client.sh

WORKDIR /app

COPY --from=builder /usr/bin/createdb /usr/bin/createdb
COPY --from=builder /usr/bin/migrate /usr/bin/migrate
COPY --from=builder /app/build/superplane /app/build/superplane
COPY --from=builder /app/docker-entrypoint.sh /app/docker-entrypoint.sh
COPY --from=builder /app/db/migrations /app/db/migrations
COPY --from=builder /app/db/data_migrations /app/db/data_migrations
COPY --from=builder /app/pkg/web/assets/dist /app/pkg/web/assets/dist
COPY --from=builder /app/api/swagger /app/api/swagger
COPY --from=builder /app/rbac /app/rbac
COPY --from=builder /app/templates /app/templates
COPY --from=builder /app/LICENSE /app/NOTICE /app/
COPY --from=builder /app/ee/LICENSE /app/ee/LICENSE

# Trial entrypoint that runs embedded Postgres and RabbitMQ and then SuperPlane.
COPY release/superplane-demo-image/entrypoint.sh /app/entrypoint.sh
COPY release/superplane-demo-image/gen-superplane-env.sh /app/gen-superplane-env.sh
COPY release/superplane-demo-image/spinner.sh /app/spinner.sh
RUN chmod +x /app/entrypoint.sh /app/docker-entrypoint.sh /app/gen-superplane-env.sh /app/spinner.sh

EXPOSE 8000

ENTRYPOINT ["/app/entrypoint.sh"]

# ----------------------------------------------------------------------------------------------------------------------
# Local release builder: generates code that Git ignores, builds the server,
# and builds the frontend.
# Used by the `local` target for the self-hosted Compose stack.
# ----------------------------------------------------------------------------------------------------------------------

FROM dev-base AS local-codegen

WORKDIR /app

# Copy only the inputs to protoc and the frontend client generation first, so
# this layer is cached across backend-only edits.
COPY protos /app/protos
COPY scripts/protoc.sh /app/scripts/protoc.sh
COPY scripts/protoc_gateway.sh /app/scripts/protoc_gateway.sh
COPY scripts/protoc_openapi_spec.sh /app/scripts/protoc_openapi_spec.sh

# Keep the module lists in sync with MODULES and REST_API_MODULES in the
# Makefile. Gateway and OpenAPI generation excludes the modules that only
# define component payloads.
RUN MODULES="authorization,organizations,integrations,factories,secrets,users,groups,roles,me,configuration,components,actions,triggers,widgets,canvases,api_keys,agents,files,admin/fleets" && \
  REST_API_MODULES="authorization,organizations,integrations,factories,secrets,users,groups,roles,me,configuration,actions,triggers,widgets,canvases,api_keys,agents,files,admin/fleets" && \
  ./scripts/protoc.sh "$MODULES" && \
  ./scripts/protoc_gateway.sh "$REST_API_MODULES" && \
  ./scripts/protoc_openapi_spec.sh "$REST_API_MODULES"

WORKDIR /app/web_src
COPY web_src/package.json web_src/package-lock.json /app/web_src/
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
  npm install --no-audit --no-fund --loglevel error

# openapi-ts reads the generated swagger spec at ../api/swagger. Copy the
# config with only the inputs it needs, then generate the frontend SDK.
COPY web_src/openapi-ts.config.ts /app/web_src/openapi-ts.config.ts
RUN npm -s run generate:api

# protoc output is not gofmt-clean by default.
RUN find /app/pkg/protos -name '*.go' -print0 | xargs -0 gofmt -s -w

FROM dev-base AS local-build

ARG BASE_URL=http://localhost:8000
ARG VITE_ASSET_BASE_URL=
ARG FRONTEND_PREBUILT=0

WORKDIR /app

COPY pkg /app/pkg
COPY ee /app/ee
COPY LICENSE NOTICE /app/
COPY cmd /app/cmd
COPY go.mod /app/go.mod
COPY go.sum /app/go.sum
COPY db/migrations /app/db/migrations
COPY db/data_migrations /app/db/data_migrations
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
COPY web_src /app/web_src
COPY protos /app/protos
# swagger-ui.html is tracked while the generated spec is not; keep the UI page.
COPY api/swagger/swagger-ui.html /app/api/swagger/swagger-ui.html
COPY rbac /app/rbac
COPY templates /app/templates

# The generated code overlays the tracked sources. Clear the stale generated
# trees from the context first, then copy the freshly generated ones from the
# codegen stage.
RUN rm -rf /app/pkg/protos /app/api/swagger/superplane.swagger.json /app/web_src/src/api-client
COPY --from=local-codegen /app/pkg/protos /app/pkg/protos
COPY --from=local-codegen /app/api/swagger /app/api/swagger
COPY --from=local-codegen /app/web_src/src/api-client /app/web_src/src/api-client

ENV GOMODCACHE=/go/pkg/mod
ENV GOCACHE=/go/go-build-cache
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked \
    --mount=type=cache,target=/go/go-build-cache,sharing=locked \
    mkdir -p "${GOMODCACHE}" "${GOCACHE}" && \
  rm -rf build && go build -o build/superplane cmd/server/main.go

WORKDIR /app/web_src
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
  if [ "$FRONTEND_PREBUILT" = "1" ]; then \
      echo "Using prebuilt frontend assets from build context"; \
    else \
      npm install && \
      if [ -n "$VITE_ASSET_BASE_URL" ]; then \
        NODE_OPTIONS=--max-old-space-size=4096 VITE_BASE_URL=$BASE_URL VITE_ASSET_BASE_URL=$VITE_ASSET_BASE_URL npm run build; \
      else \
        NODE_OPTIONS=--max-old-space-size=4096 VITE_BASE_URL=$BASE_URL npm run build; \
      fi; \
    fi

# ----------------------------------------------------------------------------------------------------------------------
# Runner stage to run the application.
# Used as the final image.
# ----------------------------------------------------------------------------------------------------------------------

FROM ${RUNNER_IMAGE} AS runner

LABEL org.opencontainers.image.title="superplane" \
  org.opencontainers.image.description="SuperPlane" \
  org.opencontainers.image.vendor="SuperPlane" \
  org.opencontainers.image.source="https://github.com/superplanehq/superplane" \
  org.opencontainers.image.url="https://superplane.com" \
  org.opencontainers.image.documentation="https://docs.superplane.com"

# postgresql-client needs to be installed here too,
# otherwise the createdb command won't work.
COPY scripts/docker/install-postgresql-client.sh install-postgresql-client.sh
RUN bash install-postgresql-client.sh

# We don't need Docker health checks, since these containers
# are intended to run in Kubernetes pods, which have probes.
HEALTHCHECK NONE

WORKDIR /app
RUN chown nobody /app

# Copy every artifact needed to run the application from previous stages
COPY --from=builder --chown=nobody:root /usr/bin/createdb /usr/bin/createdb
COPY --from=builder --chown=nobody:root /usr/bin/migrate /usr/bin/migrate
COPY --from=builder --chown=nobody:root /app/build/superplane /app/build/superplane
COPY --from=builder --chown=nobody:root /app/docker-entrypoint.sh /app/docker-entrypoint.sh
COPY --from=builder --chown=nobody:root /app/db/migrations /app/db/migrations
COPY --from=builder --chown=nobody:root /app/db/data_migrations /app/db/data_migrations
COPY --from=builder --chown=nobody:root /app/pkg/web/assets/dist /app/pkg/web/assets/dist
COPY --from=builder --chown=nobody:root /app/api/swagger /app/api/swagger
COPY --from=builder --chown=nobody:root /app/rbac /app/rbac
COPY --from=builder --chown=nobody:root /app/templates /app/templates
COPY --from=builder --chown=nobody:root /app/LICENSE /app/NOTICE /app/
COPY --from=builder --chown=nobody:root /app/ee/LICENSE /app/ee/LICENSE

USER nobody

CMD ["bash", "/app/docker-entrypoint.sh"]

# ----------------------------------------------------------------------------------------------------------------------
# Local runtime image: same layout as `runner`, but built entirely from this
# checkout, including the generated code and frontend assets.
# Used by `docker compose up` in superplane-selfhosted.
# ----------------------------------------------------------------------------------------------------------------------

FROM ${RUNNER_IMAGE} AS local

LABEL org.opencontainers.image.title="superplane-selfhosted" \
  org.opencontainers.image.description="SuperPlane built from the bundled source subtree" \
  org.opencontainers.image.vendor="SuperPlane" \
  org.opencontainers.image.source="https://github.com/ulevitsky/superplane-selfhosted" \
  org.opencontainers.image.url="https://superplane.com" \
  org.opencontainers.image.documentation="https://docs.superplane.com"

# postgresql-client provides createdb for docker-entrypoint.sh.
COPY scripts/docker/install-postgresql-client.sh install-postgresql-client.sh
RUN bash install-postgresql-client.sh

HEALTHCHECK NONE

WORKDIR /app
RUN chown nobody /app

COPY --from=local-build --chown=nobody:root /usr/bin/createdb /usr/bin/createdb
COPY --from=local-build --chown=nobody:root /usr/bin/migrate /usr/bin/migrate
COPY --from=local-build --chown=nobody:root /app/build/superplane /app/build/superplane
COPY --from=local-build --chown=nobody:root /app/docker-entrypoint.sh /app/docker-entrypoint.sh
COPY --from=local-build --chown=nobody:root /app/db/migrations /app/db/migrations
COPY --from=local-build --chown=nobody:root /app/db/data_migrations /app/db/data_migrations
COPY --from=local-build --chown=nobody:root /app/pkg/web/assets/dist /app/pkg/web/assets/dist
COPY --from=local-build --chown=nobody:root /app/api/swagger /app/api/swagger
COPY --from=local-build --chown=nobody:root /app/rbac /app/rbac
COPY --from=local-build --chown=nobody:root /app/templates /app/templates
COPY --from=local-build --chown=nobody:root /app/LICENSE /app/NOTICE /app/
COPY --from=local-build --chown=nobody:root /app/ee/LICENSE /app/ee/LICENSE

USER nobody

CMD ["bash", "/app/docker-entrypoint.sh"]
