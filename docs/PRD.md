# Corpus Hub — Product Requirements Document

**Status:** Draft v1 · Design phase
**Author:** Jeff (adempus)
**Last updated:** 2026-07-13
**Related:** [`.hermes/plans/`](../.hermes/plans/) (implementation plan) · [`docs/`](.) (C4 diagrams)

---

## 1. Summary

Corpus Hub turns a personal pile of ebooks, papers, and articles into a **private, AI-searchable knowledge base** that any agent — local or third-party (Claude Code, Codex, local LLMs) — can query over **MCP**, with answers traceable back to the exact source page.

An always-on **Raspberry Pi 5** is the front door and the source of truth. Heavy document processing (extraction, classification, embedding) is offloaded to an intermittent **GPU workstation** ("big boi"). The two are decoupled so the system stays useful even when the workstation is asleep.

## 2. Problem statement

Jeff has a large, growing collection of documents across many domains (computer science, psychology, sociology, astronomy, and more). Today that knowledge is inert: it can't be searched semantically, can't be cited precisely, and can't be surfaced to the AI agents already embedded in his daily workflow. General-purpose LLMs don't know the contents of *his* library, and manually feeding documents into context is tedious and lossy.

There is no personal system that:
- ingests arbitrary documents and normalizes them,
- makes them searchable by meaning *and* exact term,
- returns cited, page-level provenance,
- and exposes all of this to agents through a standard interface.

## 3. Goals & non-goals

### Goals
- **G1** — Drop a document onto one always-on device and have it become searchable automatically.
- **G2** — Retrieval works 24/7, independent of whether the GPU workstation is online.
- **G3** — Every answer carries a citation (document + page range) so it's verifiable.
- **G4** — Any MCP-speaking agent can use the corpus through a single, stable interface.
- **G5** — Auto-categorize documents by domain to enable scoped, low-noise search.
- **G6** — Local embeddings: document content never leaves Jeff's hardware during indexing.
- **G7** — Convenient operation: one command per machine to bring the system up.

### Non-goals (v1)
- **NG1** — Multi-user / multi-tenant access. Single user, LAN-only.
- **NG2** — Public internet exposure or hosted SaaS.
- **NG3** — Multiple GPU workers / horizontal scale-out (noted as a future path).
- **NG4** — OCR-heavy scanned-document pipelines with visual layout analysis (most inputs are already-digital ebooks).
- **NG5** — A rich web UI. CLI + agent access is sufficient for v1 (a thin review UI is optional).

## 4. Users & use cases

**Primary user:** Jeff — engineer, researcher, lifelong reader across technical and speculative domains.

**Primary consumers:** AI agents acting on Jeff's behalf.

Representative use cases:
- *"Find where this astrophysics text explains the CNO cycle"* → cited snippet with page numbers.
- *"Search only my psychology books for material on X"* → domain-scoped retrieval.
- *"Pull the full section around this passage"* → deep read for context.
- Drop a new PDF/epub → it's classified, indexed, and queryable without manual steps.

## 5. Product principles

1. **The always-on node owns the truth; the intermittent node is disposable muscle.** All state lives on the Pi; the workstation is stateless and can vanish without data risk.
2. **Offline is a non-event.** Uploads queue, retrieval keeps serving — nothing breaks when the workstation sleeps.
3. **Citations are first-class.** Provenance (doc + page) is preserved end-to-end, never bolted on later.
4. **Do less work on the read path.** The corpus is static between ingests; cache aggressively and keep the query path lean.
5. **Privacy by default.** Indexing is fully local; only retrieved snippets ever leave the machine (and only on the third-party agent path).

## 6. Functional requirements

### Ingestion
- **FR1** — Accept document uploads (epub, mobi, PDF) via an API/endpoint on the Pi.
- **FR2** — Deduplicate by content hash; re-uploading an unchanged document is a no-op.
- **FR3** — Preserve the original file untouched (canonical library layer).
- **FR4** — Extract normalized Markdown + structural metadata (headings, page map).
- **FR5** — Auto-classify each document into a domain with a confidence score and tags.
- **FR6** — Chunk documents by structure, preserving heading path and page numbers per chunk.
- **FR7** — Generate embeddings for each chunk on the GPU workstation.
- **FR8** — Return a portable **ingest bundle** (manifest + plaintext + indexed chunks) to the Pi.

### Job / offline handling
- **FR9** — Uploads return immediately with a job status; processing is asynchronous.
- **FR10** — When the workstation is offline, jobs wait in a queue and drain automatically on reconnect.
- **FR11** — Surface a clear "workstation offline / queued" state to the user.
- **FR12** — Recover from a worker crash mid-job (lease expiry re-queues the work); reprocessing is idempotent.

### Storage / merge
- **FR13** — The Pi is the single writer; bundle merges are atomic.
- **FR14** — Maintain a catalog (document registry, hashes, job states) and a hybrid (keyword + vector) index.

### Retrieval (MCP)
- **FR15** — `corpus_search(query, domain?, k?)` → ranked, cited, scored snippets.
- **FR16** — `corpus_get(doc_id, section?)` → full-section deep read.
- **FR17** — `corpus_list(domain?)` → catalog browsing so agents know what's available.
- **FR18** — Hybrid retrieval (BM25 + vector) with rank fusion.
- **FR19** — Retrieval functions with the workstation offline (Pi has its own query encoder).

## 7. Non-functional requirements

- **NFR1 — Availability:** Retrieval available 24/7; target no dependency on workstation uptime.
- **NFR2 — Query latency:** Interactive (~sub-second to low-seconds) query encode + search on the Pi.
- **NFR3 — Privacy:** All embedding/indexing runs locally; no document content sent to third parties during ingest.
- **NFR4 — Security:** LAN-only; authenticated API surface (bearer token); secrets managed in **Doppler**, never committed.
- **NFR5 — Durability:** No data loss on workstation crash or Pi reboot; index/catalog writes are safe.
- **NFR6 — Operability:** One command per machine (`make start`) with a containerized default and an automatic local fallback.
- **NFR7 — Portability of contract:** A shared, versioned schema (bundle + job records) prevents drift between the two ends.
- **NFR8 — Resource fit:** Runs within a Pi 5 (16GB) footprint — lean dependencies, quantized query encoder, no PyTorch on the Pi.

## 8. Architecture overview

Two processes over one storage spine:

- **Raspberry Pi 5 (always on):** upload + job API, SQLite catalog + lease-based job queue, LanceDB hybrid index, CPU (ONNX) query encoder, MCP server. **Single writer.**
- **Workstation "big boi" (RTX 5080, intermittent):** stateless **pull-based** worker — polls the Pi, leases jobs, runs extract → classify → chunk → embed, returns a bundle. Nothing ever connects *to* it.

The only network boundary that crosses the "offline seam" is the worker polling the Pi's REST API.

![Container diagram](structurizr-Containers.png)
![Deployment](structurizr-DeploymentView.png)
![Ingest sequence](sequence-ingest.png)

See [`docs/`](.) for the full C4 set (context, container, deployment, ingest & query dynamic views) generated from [`workspace.dsl`](workspace.dsl).

### The four layers
| Layer | What | Where |
|-------|------|-------|
| **L1** | Canonical library (untouched originals) | Pi filesystem (Calibre-managed) |
| **L2** | Normalized plaintext (Markdown + frontmatter) | produced on workstation, stored on Pi |
| **L3** | Vector + keyword index (hybrid) | produced on workstation, merged into Pi's LanceDB |
| **L4** | MCP retrieval server | Pi — always on |

## 9. Success metrics

- **M1** — A newly dropped document is searchable end-to-end (workstation online) within one processing cycle, with correct domain classification.
- **M2** — 100% of search results include a valid document + page-range citation.
- **M3** — With the workstation offline: uploads still succeed (queued) and existing-corpus queries still return results.
- **M4** — A worker killed mid-job results in zero lost/corrupted data; the job completes after reconnect.
- **M5** — At least one third-party agent (Claude Code) successfully queries the corpus over MCP.
- **M6** — Query latency stays interactive at target corpus size (~1k+ documents).

## 10. Hardware

**Always-on hub (to acquire):** Raspberry Pi 5 (16GB), M.2 HAT (or third-party NVMe base), NVMe SSD (512GB–1TB), active cooler, 27W USB-C PD supply (own wall outlet — *not* powered from the workstation, which would break the always-on premise), wired Ethernet, case sized for the HAT.

**GPU workstation (existing):** Ryzen 9800X3D, RTX 5080, Pop!_OS — no new spend.

**Explicitly not buying:** Hailo AI module (vision NPU — wrong accelerator class for a text/transformer workload).

## 11. Milestones (phased)

1. **Foundation** — repo, shared contract package, role-aware Makefile + compose, Doppler bootstrap.
2. **Pi core** — catalog, lease queue, upload + job API.
3. **Worker** — pull loop + pipeline (mockable).
4. **Real ingestion** — extraction, chunking, classification.
5. **Embeddings + bundle** — GPU embedding, bundle assembly.
6. **Merge + retrieval** — atomic merge, query encoder, hybrid search.
7. **MCP server** — tools + agent registration + auth.
8. **Containerize + one-command bring-up** — both ends, offline-seam integration test.
9. **Docs, diagrams, performance hardening.**

## 12. Risks & open questions

- **R1 — GPU on Blackwell (sm_120):** RTX 5080 is new; CUDA/PyTorch container base must support it. *Mitigation:* automatic uv-on-host fallback if the GPU container won't start.
- **R2 — Pi query-encoder latency:** bge-m3 ONNX on ARM CPU; drop to a smaller encoder if too slow (requires corpus re-embed — provenance fields make selective re-embed tractable).
- **R3 — Extraction quality/weight:** layout-aware PDF extraction is heavy; gate it behind a "structured PDF" check.
- **R4 — Doppler availability at boot:** the always-on Pi must tolerate a Doppler outage without losing retrieval (cached secrets).
- **Q1** — Ship a thin human-in-the-loop review UI for low-confidence classifications, or CLI-only for v1?
- **Q2** — Default corpus capacity target / retention as the library grows?
- **Q3** — When (if) to graduate the SQLite queue to Redis/KeyDB for multiple workers?

## 13. Future directions (post-v1)

- Multiple GPU workers / a real broker (KeyDB) for parallel ingest.
- Central hub reachable beyond the LAN (auth hardening required).
- Additional retrieval modes (reranking at ingest, cross-domain synthesis).
- Review UI / dashboard for corpus curation and ingest monitoring.
