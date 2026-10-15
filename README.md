# SuperPlane Self-Hosted

Run [SuperPlane](https://github.com/superplanehq/superplane) with Docker Compose. Application and runner images build from the bundled source. This repository does not pull prebuilt SuperPlane images.

The upstream source is stored in [`superplane/`](superplane/) as a Git subtree. The repository root owns the self-hosting Compose stack and build wrapper.

## Requirements

- Docker Engine with Docker Compose v2
- At least 8 GB of free memory for image builds and local runners

You do not need Go, Node.js, npm, or protoc on the host.

## Start SuperPlane

```sh
git clone https://github.com/ulevitsky/superplane-selfhosted.git
cd superplane-selfhosted
cp .env.example .env
docker compose up -d --build --wait
```

Open <http://localhost:8000> and create the owner account. The first build can take several minutes. Later builds reuse BuildKit caches.

To also start the Docker Fleet Manager and build the local runner image:

```sh
docker compose --profile runners up -d --build --wait
```

This profile mounts `/var/run/docker.sock`. It lets SuperPlane start ephemeral runner containers for factory tasks.

## Common commands

```sh
docker compose up -d --build --wait
docker compose --profile runners up -d --build --wait
docker compose --profile runners ps
docker compose logs -f app
docker compose --profile runners down --remove-orphans
docker compose --profile runners config --quiet
```

The first command starts the application stack. The second command also starts the local runner stack.

PostgreSQL data, OIDC keys, blobs, and active runner logs use named Docker volumes. The `down` command keeps these volumes.

To delete all local data, run the following command only when you intend to reset the installation:

```sh
docker compose --profile runners down --volumes
```

## Configuration

Copy `.env.example` to `.env` and replace every development secret before you store real data. The default values are only for local evaluation.

The main settings are:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PUBLIC_API_PORT` | `8000` | Host port for the UI and API |
| `BASE_URL` | `http://localhost:8000` | Browser-facing SuperPlane URL |
| `WEBHOOKS_BASE_URL` | `http://app:8000` | URL used for inbound webhook configuration |
| `ALLOWED_WS_ORIGINS` | `http://localhost:8000` | Allowed browser WebSocket origin |
| `RUNNER_API_BASE_URL` | `http://app:8000` | Runner-facing API URL |

You can override settings for one command:

```sh
BASE_URL=http://localhost:8080 PUBLIC_API_PORT=8080 \
  docker compose up -d --build --wait
```

## Connect GitHub from a local machine

GitHub must reach SuperPlane to send webhooks. Use a stable public HTTPS tunnel or domain, then set the public URL before you create the GitHub App:

```sh
BASE_URL=https://superplane.example.com \
WEBHOOKS_BASE_URL=https://superplane.example.com \
ALLOWED_WS_ORIGINS=https://superplane.example.com \
  docker compose --profile runners up -d --build --wait
```

Open the same public URL in your browser and start the GitHub connection again. A GitHub App setup state is short-lived and cannot be reused after configuration changes.

Keep `RUNNER_API_BASE_URL=http://app:8000` for runners on the same Compose network. Change it only when runners execute outside this Docker host.

## SuperPlane subtree

The imported upstream revision is recorded in the subtree merge commit. Pull a newer upstream revision with:

```sh
git subtree pull \
  --prefix=superplane \
  https://github.com/superplanehq/superplane.git \
  main \
  --squash
```

Replace `main` with a branch or tag when you need a different revision.

After an update, compare upstream `Dockerfile` changes with `Dockerfile.selfhosted`, then run a full image build. The wrapper Dockerfile contains the additional code-generation and local runtime stages required by this stack.

## Scope and security

This repository packages the local Compose workflow. It is suitable for evaluation and single-host self-hosting. Review secrets, TLS termination, backups, network access, observability, and upgrades before you use it for production data.

SuperPlane retains its upstream license in [`superplane/LICENSE`](superplane/LICENSE). The root [`LICENSE`](LICENSE) applies the same license to this repository's wrapper files.
