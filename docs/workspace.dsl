workspace "Corpus Hub" "Personal AI-searchable document corpus: Pi front door + workstation GPU muscle." {

    model {
        jeff = person "Jeff" "Uploads documents to the corpus."
        agents = softwareSystem "AI Agents" "Claude Code, Codex, local LLM agents — consume the corpus over MCP." {
            tags "External"
        }

        corpusHub = softwareSystem "Corpus Hub" "Private, AI-searchable library over a mixed ebook/article corpus." {

            group "Raspberry Pi 5 — always on (state owner + L4)" {
                uploadApi   = container "Upload API" "Accepts docs, hashes them, files a job." "FastAPI / Uvicorn"
                dispatcher  = container "Job Dispatcher" "Lease-based queue + atomic merge; owns the job state machine." "Python asyncio"
                qencoder    = container "Query Encoder" "Encodes queries in the SAME vector space as documents." "bge-m3 ONNX (CPU)"
                mcp         = container "MCP Server" "corpus_search / corpus_get / corpus_list." "Python MCP SDK / FastMCP"
                catalog     = container "Catalog + Job Queue" "Doc registry, content hashes, lease-based job states." "SQLite" {
                    tags "Database"
                }
                lancedb     = container "Vector + FTS Index" "Hybrid BM25 + vector; cited chunks." "LanceDB" {
                    tags "Database"
                }
                library     = container "Library + Plaintext" "L1 canonical files + L2 normalized markdown." "Filesystem / Calibre" {
                    tags "Database"
                }
            }

            group "Workstation 'big boi' — RTX 5080, intermittent (stateless muscle)" {
                worker     = container "Ingest Worker" "Polls the Pi, leases jobs, orchestrates L2+L3, returns a bundle." "Python asyncio"
                extractor  = container "Extractor" "Raw doc to normalized markdown." "marker-pdf / pymupdf / pandoc"
                classifier = container "Classifier" "Assigns domain + tags." "centroid / Qwen2.5-3B (llama.cpp)"
                embedder   = container "Embedder" "Chunks to vectors (the heavy lift)." "bge-m3 + CUDA"
            }
        }

        # --- People / external ---
        jeff -> uploadApi "Uploads docs" "HTTPS / scp"
        agents -> mcp "Queries corpus" "MCP"

        # --- Upload / write side (Pi) ---
        uploadApi -> library "Stores canonical file"
        uploadApi -> catalog "Creates job (QUEUED)"

        # --- Pull-based worker across the offline seam ---
        worker -> dispatcher "Leases job (GET /jobs/next), heartbeats" "HTTP poll"
        worker -> dispatcher "Returns ingest bundle (POST /jobs/{id}/result)" "HTTP"

        # --- Dispatcher = single writer to the serving store ---
        dispatcher -> catalog "Polls / updates job state"
        dispatcher -> library "Writes plaintext.md"
        dispatcher -> lancedb "Merges index.parquet"

        # --- In-process pipeline stages (big boi) ---
        worker -> extractor "L2 extract"
        worker -> classifier "Classify"
        worker -> embedder "L3 embed"

        # --- Read side (Pi) ---
        mcp -> qencoder "Encode query"
        mcp -> lancedb "Hybrid search"
        mcp -> catalog "List / metadata lookups"
        mcp -> library "Fetch full sections"

        # --- Deployment topology ---
        deploymentEnvironment "Production" {
            deploymentNode "Raspberry Pi 5" "Always-on hub" "Raspberry Pi OS (arm64), 16GB, NVMe" {
                containerInstance uploadApi
                containerInstance dispatcher
                containerInstance qencoder
                containerInstance mcp
                containerInstance catalog
                containerInstance lancedb
                containerInstance library
            }
            deploymentNode "Workstation 'big boi'" "Intermittent GPU worker" "Pop!_OS 24.04, Ryzen 9800X3D, RTX 5080" {
                containerInstance worker
                containerInstance extractor
                containerInstance classifier
                containerInstance embedder
            }
        }
    }

    views {
        systemContext corpusHub "SystemContext" {
            include *
            autolayout lr
        }

        container corpusHub "Containers" {
            include *
            autolayout lr
        }

        deployment corpusHub "Production" "DeploymentView" {
            include *
            autolayout lr
        }

        dynamic corpusHub "IngestFlow" "Happy-path: a document from upload to searchable (big boi online)." {
            jeff -> uploadApi "Uploads a document (HTTPS / scp)"
            uploadApi -> library "Stores canonical file (L1)"
            uploadApi -> catalog "Creates job (QUEUED)"
            worker -> dispatcher "Leases next job (GET /jobs/next)"
            dispatcher -> catalog "Marks job LEASED (+ lease expiry)"
            worker -> extractor "Extract to markdown (L2)"
            worker -> classifier "Classify domain + tags"
            worker -> embedder "Embed chunks on CUDA (L3)"
            worker -> dispatcher "Returns ingest bundle (POST /jobs/{id}/result)"
            dispatcher -> library "Writes plaintext.md (L2)"
            dispatcher -> lancedb "Merges index.parquet (L3)"
            dispatcher -> catalog "Marks job COMPLETED"
            properties {
                "plantuml.sequenceDiagram" "true"
            }
        }

        dynamic corpusHub "QueryFlow" "An agent searches the corpus (works even when big boi is offline)." {
            agents -> mcp "corpus_search(query, domain?)"
            mcp -> qencoder "Encode query (same vector space)"
            mcp -> lancedb "Hybrid search (BM25 + vector)"
            mcp -> library "Fetch full sections (if needed)"
            mcp -> agents "Cited, scored snippets (doc + page)"
            properties {
                "plantuml.sequenceDiagram" "true"
            }
        }

        styles {
            element "Person" {
                shape person
                background #08427b
                color #ffffff
            }
            element "External" {
                background #999999
                color #ffffff
            }
            element "Container" {
                background #1168bd
                color #ffffff
            }
            element "Database" {
                shape cylinder
                background #438dd5
                color #ffffff
            }
        }
    }
}
