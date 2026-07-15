# Corpus Hub — Implementation Plan

> **For Hermes:** Use `subagent-driven-development` to implement this plan phase-by-phase. Respect Jeff's pause-and-review rhythm — ship one phase, wait for an eyeball check + corrections, then proceed. Do NOT batch phases without an explicit go-ahead.

**Goal:** A personal, AI-searchable document corpus. Drop ebooks/articles onto an always-on Raspberry Pi; heavy extract→classify→embed runs on the intermittent RTX 5080 workstation ("big boi"); results merge back to the Pi, which serves hybrid search to any agent over MCP.

**Architecture:** Two processes over one storage spine. **Pi = always-on state owner + read side** (upload API, SQLite catalog + lease queue, LanceDB, ONNX query encoder, MCP server). **big boi = stateless GPU muscle** (pull-based worker: extract/classify/chunk/embed). **Pull model** — big boi polls the Pi; nothing ever connects *to* big boi; offline = jobs sit `QUEUED`. **One REST surface, on the Pi.** The deliverable per doc is a portable **ingest bundle** (`manifest.json` + `plaintext.md` + `index.parquet`); the Pi is the **single writer** and does an atomic merge.

**Run convenience (Jeff's ask):** One `make start` on either machine. A **role-aware Makefile** auto-detects the host (Pi vs workstation) and brings up the correct **docker compose** stack. **Containerized is the default; if the container path fails (esp. GPU on big boi), `make start` auto-falls-back to a local uv run** and says so loudly. Both paths are first-class and documented in the README (`make start` = containerized, `make start-local` = uv on-host). `make start` / `make stop` / `make logs` / `make test` / `make diagrams` work identically on both ends.

**Secrets (Doppler):** All secrets live in **Doppler** (existing account), not in committed files. `.env` holds only non-secret config (ports, paths, model names, `PI_HOST`); secrets (Pi REST bearer token, any LanceDB/model-registry keys later) are injected at runtime via `doppler run --`. This gives one place to add future keys without touching the repo.

**Ingestion runtime (L2–L3):** Python 3 + **CUDA** on big boi — extraction, chunking, classification, and embedding all run under the CUDA-enabled worker (containerized by default, uv-on-host fallback).

**Tech Stack:** Python 3.12 · uv workspace · FastAPI/Uvicorn · SQLite (WAL) · LanceDB (hybrid BM25+vector) · bge-m3 (CUDA on worker, ONNX-CPU query encoder on Pi) · marker-pdf / pymupdf / pandoc · Qwen2.5-3B (llama.cpp) classifier · FastMCP · Pydantic v2 (shared contract) · Doppler (secrets) · Docker + docker compose · Make.

---

## Guiding decisions (locked earlier, do not relitigate)

- **No Hailo.** Wrong accelerator class (vision NPU) for a text/transformer workload.
- **Pull-based worker**, not push. The Pi never initiates a connection to big boi.
- **Lease-based queue** in SQLite (`lease_expires_at`) gives at-least-once + crash recovery cheaply. No Celery/RabbitMQ for a 2-node system.
- **`content_sha256`** makes reprocessing idempotent.
- **Pi carries its own query encoder** (same vector space as docs) so retrieval works with big boi offline.
- **L2/L3 stay in-process** stages inside the worker — not microservices.
- **Containerized by default, uv-on-host fallback.** `make start` tries compose first; on failure (notably GPU/CUDA container issues on big boi) it automatically retries via local uv and prints a clear notice. `make start-local` forces the uv path.
- **Doppler for all secrets.** No secrets in git or `.env`. `.env` = non-secret config only; secrets injected at runtime via `doppler run --`. Single place to add future keys (LanceDB, model registry, etc.).
- **L2–L3 ingestion runs on Python 3 + CUDA** on big boi.
- SSH GitHub remote, README + .gitignore, not a bare file dump.

---

## Target repo layout

```
corpus-hub/
├── Makefile                      # role-aware entrypoint (start/stop/logs/test/diagrams)
├── README.md
├── .gitignore
├── .env.example                  # NON-SECRET config only: ROLE, PI_HOST, ports, model names, data paths
├── doppler.yaml                  # Doppler project/config mapping (setup, non-secret)
├── pyproject.toml                # uv workspace root
├── packages/
│   └── contracts/                # SHARED Pydantic models — imported by BOTH ends
│       ├── pyproject.toml
│       └── corpus_contracts/
│           ├── __init__.py
│           ├── jobs.py           # JobState, JobRecord, LeaseResponse
│           └── bundle.py         # Manifest, ChunkRow schema, Bundle
├── pi/                           # always-on hub
│   ├── pyproject.toml
│   ├── Dockerfile                # arm64/amd64, CPU-only
│   ├── corpus_pi/
│   │   ├── __init__.py
│   │   ├── config.py
│   │   ├── db.py                 # SQLite catalog + lease queue (WAL)
│   │   ├── storage.py            # library/ + plaintext/ filesystem ops
│   │   ├── upload_api.py         # POST /documents  (human side)
│   │   ├── job_api.py            # GET /jobs/next, POST /jobs/{id}/result, /heartbeat (worker side)
│   │   ├── dispatcher.py         # atomic merge + lease-sweep loop
│   │   ├── encoder.py            # ONNX bge-m3 query encoder (CPU)
│   │   ├── search.py             # LanceDB hybrid (BM25 + vector) + rerank
│   │   ├── mcp_server.py         # FastMCP: corpus_search / corpus_get / corpus_list
│   │   └── app.py                # assembles FastAPI (upload + job api + lifespan)
│   └── tests/
├── worker/                       # big boi
│   ├── pyproject.toml
│   ├── Dockerfile                # CUDA base, --gpus all
│   ├── corpus_worker/
│   │   ├── __init__.py
│   │   ├── config.py
│   │   ├── client.py             # Pi REST client (lease/result/heartbeat)
│   │   ├── poller.py             # the ~10s poll loop + backoff
│   │   ├── pipeline.py           # orchestrates the stages → Bundle
│   │   ├── extract.py            # marker-pdf / pymupdf / pandoc
│   │   ├── classify.py           # centroid default, Qwen fallback
│   │   ├── chunk.py              # structure-aware split + page map
│   │   └── embed.py              # bge-m3 CUDA → vectors
│   └── tests/
├── deploy/
│   ├── docker-compose.pi.yml
│   ├── docker-compose.worker.yml
│   └── scripts/
│       ├── detect-role.sh        # arch/hostname → ROLE
│       └── run-local.sh          # uv-on-host launcher per role (fallback + start-local)
└── docs/
    ├── workspace.dsl             # (moved from ~/corpus-hub-diagrams)
    ├── *.puml / *.png / *.svg
    └── render.sh                 # temurin+plantuml render pipeline
```

---

## Phase 0 — Repo skeleton, tooling, one-command scaffolding

**Review gate:** `make help` prints targets; `make init` creates data dirs + `.env`; empty `make test` green. Nothing functional yet.

### Task 0.1: Init uv workspace + git

**Files:** Create `pyproject.toml`, `.gitignore`, `README.md`

**Steps:**
1. `uv init --package corpus-hub` at repo root; set workspace members `packages/*`, `pi`, `worker`.
2. Root `pyproject.toml` declares `[tool.uv.workspace] members = ["packages/*", "pi", "worker"]`.
3. `.gitignore`: `.venv/`, `__pycache__/`, `*.pyc`, `.env`, `data/`, `docs/*.png`, `docs/*.svg`, `*.lance`, `*.db`, `*.db-wal`, `*.db-shm`, models cache.
4. `git init`, first commit `chore: init uv workspace`.

**Verify:** `uv sync` resolves; `git status` clean besides tracked skeleton.

### Task 0.2: Shared contracts package

**Files:** Create `packages/contracts/pyproject.toml`, `packages/contracts/corpus_contracts/{__init__,jobs,bundle}.py`

**Step 1 — failing test** (`packages/contracts/tests/test_contracts.py`):
```python
from corpus_contracts.jobs import JobRecord, JobState
from corpus_contracts.bundle import Manifest

def test_jobrecord_defaults_to_queued():
    j = JobRecord(job_id="j1", doc_id="d1", content_sha256="abc", source_filename="x.epub")
    assert j.state is JobState.QUEUED
    assert j.lease_expires_at is None

def test_manifest_requires_embed_provenance():
    m = Manifest(doc_id="d1", content_sha256="abc", source_filename="x.epub",
                 title="T", domain="astronomy", embed_model="bge-m3", embed_dim=1024,
                 chunk_count=10, pipeline_version="0.1.0")
    assert m.embed_dim == 1024
```

**Step 2:** `uv run pytest packages/contracts -v` → FAIL (module missing).

**Step 3 — implement** `jobs.py`:
```python
from __future__ import annotations
import enum, datetime as dt
from pydantic import BaseModel, Field

class JobState(str, enum.Enum):
    QUEUED = "QUEUED"
    LEASED = "LEASED"
    PROCESSING = "PROCESSING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"

class JobRecord(BaseModel):
    job_id: str
    doc_id: str
    content_sha256: str
    source_filename: str
    state: JobState = JobState.QUEUED
    lease_expires_at: dt.datetime | None = None
    attempts: int = 0
    error: str | None = None
    created_at: dt.datetime = Field(default_factory=lambda: dt.datetime.now(dt.UTC))

class LeaseResponse(BaseModel):
    job: JobRecord
    source_url: str            # where the worker fetches the raw file
    lease_seconds: int
```
`bundle.py`:
```python
from __future__ import annotations
import datetime as dt
from pydantic import BaseModel

CHUNK_SCHEMA = ["chunk_id","doc_id","seq","text","heading_path",
                "page_start","page_end","token_count","vector"]

class Manifest(BaseModel):
    doc_id: str
    content_sha256: str
    source_filename: str
    title: str
    author: str | None = None
    year: int | None = None
    domain: str
    domain_confidence: float | None = None
    tags: list[str] = []
    page_count: int | None = None
    chunk_count: int
    embed_model: str
    embed_dim: int
    chunker_version: str = "v1"
    extractor: str | None = None
    worker_host: str | None = None
    pipeline_version: str
    processing_started: dt.datetime | None = None
    processing_finished: dt.datetime | None = None

class Bundle(BaseModel):
    """Wire contract. index.parquet ships alongside as binary, not in JSON."""
    manifest: Manifest
    plaintext_md: str
    # parquet bytes transferred as multipart file part named "index"
```

**Step 4:** `uv run pytest packages/contracts -v` → PASS. **Commit** `feat(contracts): job + bundle pydantic models`.

### Task 0.3: `.env.example` (non-secret) + Doppler wiring + config loaders

**Files:** Create `.env.example`, `doppler.yaml`, `pi/corpus_pi/config.py`, `worker/corpus_worker/config.py`

**Secret vs non-secret split:**
- **`.env` (committed as `.env.example`, git-ignored real):** non-secret config only — ROLE, host/ports, model names, data paths.
- **Doppler:** everything secret — `PI_BEARER_TOKEN` (shared token the worker presents on the job API), and future keys (`LANCEDB_API_KEY`, model-registry tokens, etc.). Injected at runtime; never written to disk.

`.env.example`:
```dotenv
# Shared (NON-SECRET)
ROLE=auto                     # auto | pi | worker  (auto → detect-role.sh)
PI_HOST=corpus-pi.local
PI_PORT=8080
MCP_PORT=8765

# Models (NON-SECRET)
EMBED_MODEL=BAAI/bge-m3
EMBED_DIM=1024
QUERY_ENCODER_ONNX=/models/bge-m3-onnx
CLASSIFIER_GGUF=/models/qwen2.5-3b-instruct-q4.gguf

# Data (Pi) (NON-SECRET)
DATA_ROOT=/data
LIBRARY_DIR=/data/library
PLAINTEXT_DIR=/data/plaintext
LANCEDB_DIR=/data/lancedb
CATALOG_DB=/data/catalog.db

# Worker (NON-SECRET)
LEASE_SECONDS=1800
POLL_INTERVAL=10

# --- SECRETS: do NOT put here. Managed in Doppler, injected via `doppler run --`.
# PI_BEARER_TOKEN=...        (Doppler)
# LANCEDB_API_KEY=...        (Doppler, future)
```

`doppler.yaml` (non-secret project/config mapping; committed):
```yaml
setup:
  - project: corpus-hub
    config: dev
```
Two Doppler configs to create in the dashboard: `corpus-hub/dev` and `corpus-hub/prd`. Both machines auth once with `doppler login` + `doppler setup` (reads `doppler.yaml`). Project creation itself is **Task 0.5** below — don't assume it pre-exists.

Config loaders = `pydantic-settings` `BaseSettings` in each package. Secrets are read from the **environment** (Doppler injects them), so `Settings` treats `PI_BEARER_TOKEN` as a normal env var — no Doppler SDK dependency in the app code, keeping it decoupled. **Commit** `feat(config): env-driven settings + Doppler mapping`.

### Task 0.4: Role-aware Makefile + compose + detect-role + local fallback

**Files:** Create `Makefile`, `deploy/docker-compose.pi.yml`, `deploy/docker-compose.worker.yml`, `deploy/scripts/detect-role.sh`, `deploy/scripts/run-local.sh`

`deploy/scripts/detect-role.sh`:
```bash
#!/usr/bin/env bash
# Resolve ROLE: explicit env wins, else detect by arch.
set -euo pipefail
if [[ "${ROLE:-auto}" != "auto" ]]; then echo "$ROLE"; exit 0; fi
case "$(uname -m)" in
  aarch64|arm64) echo "pi" ;;
  x86_64|amd64)  echo "worker" ;;
  *) echo "unknown" >&2; exit 1 ;;
esac
```

`deploy/scripts/run-local.sh` (the uv-on-host launcher — used by both the auto-fallback and `make start-local`):
```bash
#!/usr/bin/env bash
# Launch this role's services directly via uv (no containers).
# Secrets come from the already-active `doppler run --` environment.
set -euo pipefail
ROLE="$(bash deploy/scripts/detect-role.sh)"
echo "▶ Local (uv) launch for ROLE=$ROLE"
uv sync
case "$ROLE" in
  pi)
    # api (upload+job REST) + MCP; dispatcher runs in-process via app lifespan
    uv run uvicorn corpus_pi.app:app --host 0.0.0.0 --port "${PI_PORT:-8080}" &
    uv run python -m corpus_pi.mcp_server &
    wait ;;
  worker)
    uv run python -m corpus_worker.poller ;;   # CUDA on host
  *) echo "unknown role" >&2; exit 1 ;;
esac
```

`Makefile` (containerized default → automatic uv fallback; every runtime target wrapped in `doppler run` so secrets are injected):
```makefile
SHELL := /usr/bin/env bash
ROLE ?= $(shell bash deploy/scripts/detect-role.sh)
COMPOSE := docker compose -f deploy/docker-compose.$(ROLE).yml --env-file .env
DOPPLER := doppler run --

.DEFAULT_GOAL := help

help:  ## Show targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'
	@echo "  (detected ROLE = $(ROLE))"

init:  ## First-run: .env + data dirs + Doppler setup
	@test -f .env || cp .env.example .env
	@mkdir -p data/{library,plaintext,lancedb}
	@command -v doppler >/dev/null || { echo "⚠ install doppler CLI first"; exit 1; }
	@doppler setup --no-interactive 2>/dev/null || doppler setup
	@echo "init done for ROLE=$(ROLE)"

build: ## Build images for this role
	$(DOPPLER) $(COMPOSE) build

start: ## Bring up stack — CONTAINERIZED, auto-fallback to local uv on failure
	@echo "▶ Starting ROLE=$(ROLE) (containerized)…"
	@if $(DOPPLER) $(COMPOSE) up -d 2>err.log; then \
	  $(DOPPLER) $(COMPOSE) ps; \
	else \
	  echo "⚠ Container start FAILED (see err.log). Falling back to local uv…"; \
	  $(MAKE) start-local; \
	fi

start-local: ## Force the uv-on-host path (no containers)
	@$(DOPPLER) bash deploy/scripts/run-local.sh

stop:  ## Tear down containers (local mode: Ctrl-C the foreground process)
	-$(COMPOSE) down
	@pkill -f 'corpus_(pi|worker)' 2>/dev/null || true

logs:  ## Tail container logs
	$(COMPOSE) logs -f --tail=100

ps:    ## Status
	$(COMPOSE) ps

test:  ## Run unit tests (host, via uv)
	uv run pytest -q

diagrams: ## Regenerate C4 diagrams
	bash docs/render.sh

.PHONY: help init build start start-local stop logs ps test diagrams
```

**Fallback note:** `start` captures compose failure (bad GPU runtime, missing `nvidia-container-toolkit`, image build error) and transparently runs `start-local`, printing a clear ⚠ line so it's never silent. `make start-local` lets Jeff force uv directly. Both paths get Doppler-injected secrets identically.

`docker-compose.pi.yml` (services: `api` [upload+job REST], `dispatcher`, `mcp`; shared `./data` volume; CPU-only; `restart: unless-stopped`; secrets from the `doppler run` env — compose reads `PI_BEARER_TOKEN` from the wrapping environment, not a file).
`docker-compose.worker.yml` (single `worker` service; GPU reservation block below; `restart: unless-stopped`; env `PI_HOST`/`PI_PORT`; `PI_BEARER_TOKEN` from Doppler env).

GPU block for the worker service:
```yaml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

**Verify:** `make help` shows targets + detected ROLE; `make init` creates `data/` + `.env` + runs `doppler setup`; simulate a compose failure (e.g. rename the compose file) and confirm `make start` prints the ⚠ fallback line and invokes `start-local`. **Commit** `feat(ops): role-aware Makefile, compose skeleton, uv fallback, Doppler wrapping`.

### Task 0.5: Create the Doppler project + configs + seed the token

**Objective:** Stand up the `corpus-hub` Doppler project so `doppler run` works on both machines. Do NOT assume it exists.

**Prereq:** Doppler CLI installed (`curl -Ls https://cli.doppler.com/install.sh | sh` or the distro package) and `doppler login` completed once per machine (interactive; Jeff runs it in his own terminal).

**Steps:**
1. Create the project + two configs (idempotent — ignore "already exists"):
   ```bash
   doppler projects create corpus-hub || true
   doppler configs create dev --project corpus-hub || true
   doppler configs create prd --project corpus-hub || true
   ```
2. Generate + store the shared bearer token as a secret (dev config):
   ```bash
   TOKEN="$(openssl rand -hex 32)"
   doppler secrets set PI_BEARER_TOKEN="$TOKEN" --project corpus-hub --config dev
   ```
   (Repeat for `prd` with a distinct token when going to "production".)
3. Point the repo at it: from the repo root, `doppler setup --project corpus-hub --config dev` (writes local `.doppler.yaml` selection; `doppler.yaml`'s `setup:` block makes this the default).
4. Sanity check — token is reachable without ever printing it to a file:
   ```bash
   doppler run --project corpus-hub --config dev -- \
     bash -c 'test -n "$PI_BEARER_TOKEN" && echo "✓ PI_BEARER_TOKEN present"'
   ```

**Verify:** step 4 prints `✓ PI_BEARER_TOKEN present`; `doppler secrets --project corpus-hub --config dev` lists `PI_BEARER_TOKEN` (value masked). No secret ever lands in git or `.env`.

**Note:** This is a one-time bootstrap per Doppler account — it creates cloud-side state, not repo files. The worker machine (big boi) only needs steps 1's `doppler login` + step 3's `doppler setup` (same project/config); it reads the same token. **No commit** (nothing repo-local changes here beyond the git-ignored `.doppler.yaml` selection).

---

## Phase 1 — Pi core: catalog, lease queue, upload API

**Review gate:** upload a file via `curl`, see it hashed + stored in `library/`, a `QUEUED` row in SQLite; lease/heartbeat/result endpoints exist and pass unit tests against a temp DB.

### Task 1.1: SQLite schema + lease queue (`pi/corpus_pi/db.py`)
- TDD: `test_enqueue_then_lease_marks_leased`, `test_expired_lease_is_reclaimed`, `test_sha_dedupe_skips_duplicate`.
- Schema: `documents(doc_id PK, content_sha256 UNIQUE, source_filename, title, domain, …)`, `jobs(job_id PK, doc_id FK, state, lease_expires_at, attempts, error, created_at)`. WAL mode on.
- Functions: `enqueue(doc)`, `lease_next(lease_seconds) -> JobRecord|None` (atomic `UPDATE … WHERE state='QUEUED' ORDER BY created_at LIMIT 1 RETURNING *`), `complete(job_id)`, `fail(job_id, err)`, `sweep_expired()`.

### Task 1.2: Filesystem storage (`storage.py`)
- `store_canonical(file) -> (doc_id, sha)`, `write_plaintext(doc_id, md)`, `read_section(doc_id, heading?)`. TDD with tmp dirs.

### Task 1.3: Upload API (`upload_api.py`)
- `POST /documents` (multipart) → hash → dedupe check → `store_canonical` → `enqueue` → `202 {job_id, doc_id, status}`. TDD with `httpx.AsyncClient` + `ASGITransport`.

### Task 1.4: Job API (`job_api.py`)
- `GET /jobs/next` → `lease_next` → `LeaseResponse` or `204`. `POST /jobs/{id}/heartbeat` → extend lease. `POST /jobs/{id}/result` → accept multipart (`manifest` json + `plaintext` + `index` parquet), hand to dispatcher merge, `complete`. TDD each.

### Task 1.5: Wire `app.py` + lifespan
- Assemble routers; start the lease-sweep background task; graceful shutdown. Smoke test: `uv run uvicorn corpus_pi.app:app` boots.

**Commit per task.**

---

## Phase 2 — Worker: pull loop + pipeline (mockable)

**Review gate:** with a fake Pi (test double) serving one job, the worker leases → runs a stubbed pipeline → posts a valid bundle; poll loop backs off and logs "🛰️ waiting" when Pi returns 204/unreachable.

### Task 2.1: Pi REST client (`client.py`) — lease/heartbeat/result, retries w/ backoff. TDD against `respx` mocks.
### Task 2.2: Poll loop (`poller.py`) — interval, jitter, "offline/empty" logging, lease-heartbeat during long jobs. TDD with fake clock.
### Task 2.3: Pipeline orchestrator (`pipeline.py`) — `process(job) -> Bundle`, stages injected as callables so they're swappable/testable. TDD with stub stages asserting bundle shape + `CHUNK_SCHEMA`.

---

## Phase 3 — Real extraction, chunking, classification

**Review gate:** feed one real epub + one real PDF end-to-end on the workstation; inspect `plaintext.md` quality + chunk page-map + assigned domain.

### Task 3.1: Extractor (`extract.py`) — dispatch by type: pandoc/calibre (epub/mobi), pymupdf (simple pdf), marker-pdf (structured pdf). Emit markdown + page map.
### Task 3.2: Chunker (`chunk.py`) — split on heading structure, ~500–1000 tok + overlap, carry `heading_path`, `page_start/end`, `token_count`.
### Task 3.3: Classifier (`classify.py`) — embedding-centroid nearest-domain default (seed centroids from a few known docs); Qwen2.5-3B zero-shot fallback for low-confidence. Emit `domain` + `domain_confidence` + `tags`.
### Task 3.4: Seed script — `make seed` to build domain centroids from `data/seeds/<domain>/`.

---

## Phase 4 — Embeddings + bundle assembly (GPU)

**Review gate:** full doc → `index.parquet` with correct `EMBED_DIM` vectors + all `CHUNK_SCHEMA` columns; parquet opens in LanceDB without transform.

### Task 4.1: Embedder (`embed.py`) — bge-m3 on CUDA, batched; verify `torch.cuda.is_available()` at startup, log device.
### Task 4.2: Bundle writer — assemble `manifest.json` + `plaintext.md` + `index.parquet` (Arrow), stamp provenance (`embed_model`, `embed_dim`, `pipeline_version`, `worker_host`).

---

## Phase 5 — Pi merge + LanceDB + query encoder

**Review gate:** posting a real bundle merges atomically; a duplicate `content_sha256` is a no-op; LanceDB table gains rows + FTS index built.

### Task 5.1: Dispatcher merge (`dispatcher.py`) — receive bundle → `write_plaintext` → `table.add(parquet)` → build/refresh FTS index → upsert `documents` row → `complete(job)`. Single-writer; wrap in one logical txn (fs + lance + sqlite ordering with rollback on failure).
### Task 5.2: Query encoder (`encoder.py`) — ONNX bge-m3 on CPU; `encode(query) -> vector`; assert dim == `EMBED_DIM`. TDD dim + determinism.
### Task 5.3: Hybrid search (`search.py`) — LanceDB BM25 + vector, merge/rerank, return snippet + `doc_id/title/heading_path/page_start/end/score`.

---

## Phase 6 — MCP server (L4)

**Review gate:** register the MCP server in Claude Code; `corpus_search("CNO cycle")` returns cited snippets; works with the worker offline.

### Task 6.1: FastMCP server (`mcp_server.py`) — tools `corpus_search(query, domain?, k?)`, `corpus_get(doc_id, section?)`, `corpus_list(domain?)`. Follow the `native-mcp` skill for registration.
### Task 6.2: Register in Claude Code config; verify tools enumerate; run a live query. (Use the `claude-code` skill for the exact `hermes` config commands.)
### Task 6.3: Bearer-token auth on the Pi job API. Add FastAPI dependency that checks `Authorization: Bearer <PI_BEARER_TOKEN>` on `/jobs/*` and `/documents`. Token comes from the Doppler-injected env. TDD: 401 without token, 200 with. (Upload/human side can share the same token for v1.)

---

## Phase 7 — Dockerize + one-command bring-up (both ends)

**Review gate:** `make start` on the Pi brings up api+dispatcher+mcp; `make start` on big boi brings up the worker; drop a doc → it flows end-to-end → searchable over MCP. Kill big boi mid-job → lease reclaimed → job completes on next poll.

### Task 7.1: `pi/Dockerfile` — slim Python 3.12, uv-installed, CPU-only, non-root, healthcheck on `/healthz`.
### Task 7.2: `worker/Dockerfile` — CUDA base (matching driver 580/CUDA 13 → use an `nvidia/cuda:12.x`/`pytorch` base compatible w/ sm_120; pin at build), uv-installed, model cache volume.
### Task 7.3: Finalize both compose files — volumes, `restart: unless-stopped`, worker GPU reservation, env wiring, Pi service deps.
### Task 7.4: Full offline-seam integration test — scripted: stop worker, upload (expect QUEUED + "🛰️" surfaced), start worker, assert COMPLETED + searchable.

---

## Phase 8 — Docs, diagrams, polish

### Task 8.1: Move `~/corpus-hub-diagrams/*` → `docs/`; add `docs/render.sh` (temurin CLI export + plantuml render); wire `make diagrams`.
### Task 8.2: README — architecture (embed the C4 PNGs + the behavioral sequence), quickstart per end (`make init && make start`), **both run paths documented** (containerized default vs `make start-local` uv fallback, and when each kicks in), Doppler setup (`doppler login` → `doppler setup` → configs `dev`/`prd`), MCP registration, troubleshooting (incl. the sunset `structurizr/cli` image gotcha + GPU-container fallback behavior).
### Task 8.3: Push to GitHub (SSH remote, `adempus`), branch naming per convention if ticketed.

---

## Files likely to change (net-new)

All under `corpus-hub/` per the layout above — contracts (2), pi (10), worker (9), deploy (3), docs (render.sh), root (Makefile/pyproject/.env.example/.gitignore/README).

## Tests / validation

- **Unit:** `make test` (uv + pytest) per package — db lease semantics, upload/job APIs (httpx ASGI), client (respx), pipeline shape, encoder dim, hybrid search.
- **Integration:** Phase 7.4 offline-seam script.
- **Manual review gates:** one per phase (Jeff's rhythm).

## Risks / tradeoffs / open questions

1. **GPU base image + Blackwell (sm_120).** RTX 5080 is new; the CUDA/PyTorch base must support sm_120. **Open:** pin a known-good `pytorch/pytorch` CUDA tag at Phase 7.2. *Mitigation is now built in:* `make start` auto-falls-back to `start-local` (uv on host) if the GPU container won't come up, so a bad image never blocks ingestion — worker-on-host is a first-class path, not just an escape hatch.
2. **bge-m3 ONNX on Pi CPU latency.** ~1s/query expected; if too slow, drop to `bge-small` (must re-embed corpus — dims differ). Provenance fields make selective re-embed tractable.
3. **marker-pdf weight.** Heavy dep; gate behind "structured PDF" detection so most docs use pymupdf/pandoc.
4. **LanceDB FTS build cost** on large merges — build incrementally per-add, not full-rebuild.
5. **`data/` sharing** between Pi services — all three Pi containers mount the same volume; fine on one host. Multi-host later = out of scope (KeyDB graduation path noted).
6. **Auth on the Pi REST surface** — LAN-only + a shared bearer token on `/jobs/*` and `/documents` (Task 6.3). **Token lives in Doppler**, injected at runtime — never in git or `.env`. Don't expose the Pi publicly. Future keys (LanceDB, model registry) go in the same Doppler config.
7. **Doppler availability at boot.** `doppler run` wraps every runtime target, so the Doppler CLI must be installed + authed on both machines (`make init` checks + runs `doppler setup`). If a machine is offline from Doppler at boot, cached secrets (`doppler` local fallback) or a one-time `doppler secrets download` can bridge — note for the always-on Pi so a Doppler outage doesn't take retrieval down.
8. **Containerized-vs-local parity.** The uv fallback path must stay functionally identical to the container path (same env, same ports). Risk: drift between `run-local.sh` and the compose files. Mitigation: both read the same `.env` + Doppler env; keep the service list in sync when either changes.

## Execution handoff

Plan complete. Recommended: implement with `subagent-driven-development` (fresh subagent per task, two-stage review), pausing at each phase's review gate for your eyeball check before continuing.
