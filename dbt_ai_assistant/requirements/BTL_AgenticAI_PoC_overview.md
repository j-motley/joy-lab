# Proof of Concept Overview: Agentic AI Development Workflow for the BTL Semantic Layer

## 1. Summary

This proof of concept demonstrates a lightweight, file-based agentic AI system for automating dbt data product development on the BTL (Business Translation Layer) Semantic Layer codebase.

The system consists of two types of reusable prompt files—**Foundational** and **Development**—supported by a structured context store (`.agent_context/`) that serves as the agent’s knowledge base. Together, these components enable AI agents to build dbt models, schema definitions, and source configurations that conform to established team patterns and standards—without exceeding the AI model’s context window.

The POC uses **Middle Market Americas (MMA)** as the first data product built through this system.

### Key Outcomes

- AI agents can produce production-quality dbt code by reading curated context rather than scanning the full codebase (~1,900 models)
- Context is partitioned into bounded reference files, each scoped to a specific concern, keeping any single agent session well within window limits
- The system is product-agnostic — the same prompts and context structure apply to any new data product (cyber, gmr, claim, etc.)

## 2. Problem Statement

The core challenge can be stated as follows:

> “How can a developer remain in full control of an outcome while reducing, or even removing, any remaining friction associated with the use of generative AI?”

Agentic coding assistants, such as GitHub Copilot and Claude Code, already reduce friction by integrating directly into the development experience and performing coding tasks quickly. The harder problem is enabling AI to go beyond broad assistance by providing the detailed context needed for a narrow use case, while still keeping a skilled engineer in the loop to guide the AI and ensure decisions remain aligned to team goals and enterprise standards.

Today, even with the help of an AI coding partner, this workflow is manual, knowledge-intensive, and difficult to scale. Each new data product requires a skilled engineer who understands the full architecture, conventions, and governance requirements accumulated over years of development.

The BTL Semantic Layer team maintains a dbt codebase comprising three projects, ~1,900 SQL models, a 4,500-line shared metrics macro, and strict naming, configuration, and governance standards. Building a new data product today requires:

1. Understanding the architecture (pipeline ↔ semantic flow, LPL/SPL catalog separation, cross-project source wiring)
2. Knowing the naming conventions, model templates, config patterns, and testing standards
3. Reading a product specification (typically an Excel/CSV document with column mappings and business logic)
4. Writing pipeline models, semantic models, schema YAML, source YAML, and `dbt_project.yml` entries that comply with all standards
5. Validating the output against checklists before submission

This process is manual, knowledge-intensive, and error-prone. Onboarding a new team member (human or AI) requires absorbing context that is scattered across the codebase with no single reference point.

This proof of concept demonstrates that by centrally managing and integrating the team’s knowledge, goals, and standards, agentic AI can automate much of the workflow while maintaining human control of the outcome. Given the right context infrastructure, agentic AI can drive the workflow end-to-end — from ingesting a product specification to producing deployable, standards-compliant dbt code.

AI agents cannot simply be pointed at the full codebase because:

- The codebase is too large to fit in a single context window (~1,900 models, 43K source columns)
- Patterns and conventions are implicit — embedded in existing code, not documented
- Without curated context, agents produce code that compiles but violates team standards
- The development workflow spans multiple discrete steps (intake, mapping, build, validate) that must be sequenced correctly

## 3. Solution Overview

### 3.1 Architecture

The solution has three layers:

```text
ORCHESTRATION LAYER
.github/prompts/
  Foundational Prompts         Development Prompts
  (refresh context)           (build product code)

  writes                      reads + writes
        ↓                           ↓

CONTEXT STORE
.agent_context/
├── L1_ARCHITECTURE.md        (architecture overview)
├── L2/                       (patterns & standards)
├── L3/                       (product specs)
├── schemas/                  (source index + metadata CSVs)
├── governance/               (descriptions & test index)
└── requirements/{product}/   (input specs from business)

reads (via source())
        ↓

dbt CODEBASE
BTL_SEMANTIC_LAYER/
├── pipeline/           (940 models — views, raw + intermediate)
├── semantic/           (965 models — tables, business-facing)
└── shared_governance/  (macros, tests, descriptions)
```

### 3.2 Mapping to Standard Agentic AI Components

In a strategic agentic AI platform, context is typically managed by specialized infrastructure components. This POC implements equivalent functionality using files and prompts:

- **Knowledge Base / Vector Store (RAG):** `.agent_context/` — curated, pre-indexed reference files organized by concern
- **System Instructions:** `.github/prompts/*_prompt.md` — reusable prompt files that define discrete operations
- **Tool-Based Retrieval:** terminal commands such as `Import-Csv` and `Get-Content` for large or Copilot-ignored files
- **Memory / State Store:** `L3/{product}.md` — persistent product specs written by one prompt and consumed by the next
- **Context Manifest:** prompt headers that list required files, approximate sizes, and context budget

### 3.3 Prompt Strategy

The POC separates prompts into two categories:

#### Foundational Prompts
These refresh the context store when the codebase or metadata changes.

- **F1:** Architecture Scan
- **F2:** Patterns Refresh
- **F3:** Source Index Refresh
- **F4:** Governance Index Refresh
- **F5:** Product Catalog Refresh

#### Development Prompts
These execute sequentially to build a specific data product.

- **D1:** Product Intake
- **D2:** Source Mapping
- **D3:** Pipeline Build
- **D4:** Semantic Build
- **D5:** Config Integration
- **D6:** Validation

Each development prompt is a separate agent session. The `L3` product spec acts as the persistent memory artifact that chains those sessions together.

### 3.4 Context Window Management

Each prompt is designed to stay within the AI model’s context window by:

1. Declaring a context budget so total read load is predictable
2. Reading only what is needed for the current task
3. Producing bounded outputs such as a spec, SQL file, or YAML artifact
4. Using tool-based retrieval for large files such as schema CSVs instead of loading them wholesale

## 4. Current Status

### Built

- `.agent_context/` folder structure — ✅  
  Excluded from dbt via `.dbtignore`
- L1 Architecture doc — ✅  
  18.6 KB
- L2 Patterns & Standards (10 files) — ✅  
  55.4 KB total
- Schema index + source cross-reference — ✅  
  14.3 KB
- Governance Index — ✅  
  8.5 KB
- Schema CSVs (user-provided) — ✅  
  LPL: 4.4 MB, SPL: 334 KB
- MMA requirement CSVs (user-provided) — ✅  
  3 CSVs + Excel source

### To Build

- Foundational prompt files (F1–F5) — ⬜  
  Define in `.github/prompts/`
- Development prompt files (D1–D6) — ⬜  
  Define in `.github/prompts/`
- L3 MMA spec (via D1 + D2) — ⬜  
  First product to validate the system
- MMA code output (via D3–D6) — ⬜  
  Pipeline + semantic models
- Temp file cleanup — ⬜  
  Remove `_temp_*` files from `schemas/`

## 5. Risks & Limitations

- **Context window exceeded during large product intake**  
  **Mitigation:** Context budget in prompt headers; split D1 if requirement CSV > 100 KB

- **Schema CSVs are Copilot-ignored** (`.csv` files can’t be read via `read_file`)  
  **Mitigation:** Prompts instruct agents to use terminal `Import-Csv` / `Get-Content` for CSV access

- **L2 files become stale as codebase evolves**  
  **Mitigation:** Foundational prompts (F2–F5) provide a repeatable refresh mechanism

- **`getdynamicmeasures` macro is 4,536 lines — too large to load fully**  
  **Mitigation:** `L2_06_MACRO_REFERENCE.md` documents the signature and top measures; agents grep for specific measures on demand

- **Single-agent sessions can’t share live state**  
  **Mitigation:** `L3` spec file serves as persistent memory between sessions

- **POC is model-specific (Claude/Copilot)**  
  **Mitigation:** Prompt files are plain markdown — portable to other agent frameworks

## 6. What Comes Next

### 6.1 Strategic Evolution

Beyond the POC, a strategic implementation could replace file-based components with:

- a vector store for the knowledge base
- MCP (Model Context Protocol) tools for schema lookup
- an orchestration framework such as LangGraph, AutoGen, or CrewAI
- CI/CD integration for prompt refresh and product build workflows
- multi-agent collaboration between pipeline and semantic build agents

The file-based approach is intentionally simple. It validates the decomposition, context budgets, and workflow design before investing in infrastructure.

### 6.2 Orchestration Approach

In the current POC, the human acts as the orchestrator — manually invoking each prompt in separate Copilot chat sessions. GitHub Copilot’s current agent mode is single-threaded, so there is no built-in mechanism to spawn multiple agents in parallel or chain sessions programmatically.

Even so, the decomposition is intentionally framework-agnostic. Each prompt declares its inputs and outputs explicitly, stays within context budgets, and produces a defined artifact on disk. That makes the design portable whether prompts are invoked by a human, a Copilot chat session, a LangGraph node, or a GitHub Actions workflow.

A future VS Code extension could provide a structured orchestration interface with:
- a workflow panel showing prompt sequence and status
- one-click prompt invocation
- context budget visibility
- artifact tracking
- product selection
- staleness indicators for foundational refreshes

### 6.3 Development Approach Modes

The current POC follows a single approach: the agent reads the context store and the product specification, then proceeds through D1–D6 autonomously, making design decisions based on the L2 reference files and existing codebase examples. This works, but every product specification is different, and the design choices made during intake, source mapping, and pipeline build are where the most consequential architectural decisions happen. A wrong assumption at those early stages compounds through every downstream step.

## 7. Related Detailed Specification

This overview is intended to summarize the proof of concept, its rationale, and its delivery model. Detailed requirements for context objects, prompt behavior, orchestration, VS Code extension capabilities, predictive widgets, and architecture guidance are captured separately in the functional specification.
