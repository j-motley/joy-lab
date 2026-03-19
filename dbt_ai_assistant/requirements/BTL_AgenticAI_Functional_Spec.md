# Functional Specification: AI-Assisted dbt Development Platform and VS Code Extension

## 1. Purpose and Scope

This document defines the functional specification for the file-based agentic AI system described in the proof of concept overview. It covers the context store, prompt inventory, orchestration model, VS Code extension behavior, predictive simulation widgets, foundational architecture automation, and runtime architectural guidance.

The intent is to specify how the system should behave so that an AI assistant can operate as a dbt-aware development partner rather than as a generic coding tool.

## 2. System Architecture

### 2.1 Layered Architecture

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

### 2.2 Mapping to Standard Agentic AI Components

#### Knowledge Base / Vector Store (RAG)

**Purpose:** Store and retrieve relevant context on demand without loading everything  
**POC implementation:** `.agent_context/` — curated, pre-indexed reference files organized by concern. Each prompt declares exactly which files to read.  
**Files:** `L1`, `L2/*`, `schemas/source_index.md`, `governance/*`

#### System Instructions

**Purpose:** Persistent instructions that shape agent behavior for a task  
**POC implementation:** `.github/prompts/*_prompt.md` — each prompt file is a self-contained system instruction for a discrete operation  
**Files:** Foundational + Development prompts

#### Tool-Based Retrieval

**Purpose:** Fetch specific data on demand rather than pre-loading  
**POC implementation:** Terminal commands (`Import-Csv`, `Get-Content`) to query schema CSVs and read Copilot-ignored files  
**Files:** `schemas/*.csv`, `requirements/*/*.csv`

#### Memory / State Store

**Purpose:** Persist outputs across sessions so one agent’s output feeds the next  
**POC implementation:** `L3` product specs — written by one prompt, consumed by the next in the development workflow  
**Files:** `L3/{product}.md`

#### Context Manifest

**Purpose:** Declare what an agent needs to read, with budget constraints  
**POC implementation:** Prompt headers listing input files, approximate sizes, and total read budget  
**Files:** Prompt `## Context Budget` sections

### 2.3 Context Window Management

Each prompt shall be designed to stay within the AI model’s context window by:

1. Declaring a context budget — listing input files and their sizes so the total read load is predictable
2. Reading only what is needed for the current task
3. Producing bounded outputs — such as a product spec, SQL file, or YAML artifact
4. Using tool-based retrieval for large data — for example, querying schema CSVs by terminal rather than loading them whole

## 3. Context Store Specification

### 3.1 Architecture & Patterns (always available, read selectively)

- **`L1_ARCHITECTURE.md`** — 18.6 KB  
  Three-project architecture, data flow, catalog model, cross-project wiring  
  **When referenced:** Foundational refresh; development intake

- **`L2/L2_01_QUICK_REFERENCE.md`** — 3.6 KB  
  Cheat sheet: project names, materializations, tags, LPL/SPL product lists  
  **When referenced:** Every development prompt

- **`L2/L2_02_NAMING_CONVENTIONS.md`** — 4.2 KB  
  File, alias, and column naming rules  
  **When referenced:** Pipeline + semantic build prompts

- **`L2/L2_03_MODEL_TEMPLATES.md`** — 9.4 KB  
  Six model templates (A–F) with skeleton SQL  
  **When referenced:** Pipeline + semantic build prompts

- **`L2/L2_04_SCHEMA_YML_PATTERNS.md`** — 3.2 KB  
  `_schema.yml` conventions and examples  
  **When referenced:** Pipeline + semantic build prompts

- **`L2/L2_05_SOURCE_YML_PATTERNS.md`** — 5.0 KB  
  `_source.yml` cross-project wiring patterns  
  **When referenced:** Semantic build prompt

- **`L2/L2_06_MACRO_REFERENCE.md`** — 6.9 KB  
  All macro signatures; `getdynamicmeasures` documentation  
  **When referenced:** Pipeline + semantic build (when measures are needed)

- **`L2/L2_07_GENERIC_TESTS.md`** — 3.4 KB  
  Three dimension quality tests with usage examples  
  **When referenced:** Validation prompt

- **`L2/L2_08_CONFIG_PATTERNS.md`** — 7.9 KB  
  Full `dbt_project.yml` config matrix  
  **When referenced:** Config integration prompt

- **`L2/L2_09_PRODUCT_CATALOG.md`** — 5.2 KB  
  Complete product inventory with model counts  
  **When referenced:** Foundational refresh; development intake

- **`L2/L2_10_DECISION_TREE.md`** — 6.6 KB  
  Decision trees + pre-submission checklists  
  **When referenced:** Validation prompt

### 3.2 Indexes (generated by foundational prompts)

- **`schemas/source_index.md`** — 14.3 KB  
  Cross-reference: 922 catalog tables ↔ 42 source YAML definitions, catalog summaries, product-to-catalog mapping  
  **When referenced:** Source mapping prompt

- **`governance/descriptions_index.md`** — 8.5 KB  
  38 doc blocks, 7 macros, 3 generic tests — full `shared_governance` inventory  
  **When referenced:** Development prompts (as needed)

### 3.3 Data Files (queried via terminal, not loaded into context)

- **`schemas/axiom_etl_prd_lpl_btl_src.csv`** — 4,409 KB  
  900 tables, 40,185 columns — LPL catalog metadata  
  **When referenced:** Source mapping (filtered lookup)

- **`schemas/axiom_etl_prd_spl_btl_src.csv`** — 334 KB  
  22 tables, 2,918 columns — SPL catalog metadata  
  **When referenced:** Source mapping (filtered lookup)

- **`requirements/{product}/*.csv`** — Varies  
  Product requirement specs (columns, filters, measures)  
  **When referenced:** Development intake prompt

### 3.4 Product Specs (generated by development prompts, consumed by subsequent steps)

- **`L3/{product}.md`** — ~20–40 KB  
  Complete product spec: requirements analysis, source mappings, proposed model design, column matrix  
  **When referenced:** Pipeline build, semantic build, config, validation

## 4. Prompt Inventory and Workflow

### 4.1 Foundational Prompts

These prompts refresh the context store. Run them when the codebase changes, governance docs are updated, new products are added, or schema metadata is refreshed.

- **F1: Architecture Scan**  
  **Reads:** Full codebase structure, `dbt_project.yml` files, `packages.yml`  
  **Produces:** Updated `L1_ARCHITECTURE.md`  
  **Trigger:** Major structural changes, new projects added

- **F2: Patterns Refresh**  
  **Reads:** `dbt_project.yml` configs, existing models (sampling), naming patterns in source code  
  **Produces:** Updated `L2/` files (10 files)  
  **Trigger:** New patterns emerge, config changes, macro updates

- **F3: Source Index Refresh**  
  **Reads:** Schema CSVs (via terminal), all `_source.yml` files  
  **Produces:** Updated `schemas/source_index.md`  
  **Trigger:** User drops new schema CSVs, source YAMLs added/changed

- **F4: Governance Index Refresh**  
  **Reads:** `shared_governance/macros/descriptions.md`, `_schema.yml` files for `doc()` refs, generic test files  
  **Produces:** Updated `governance/descriptions_index.md`  
  **Trigger:** Doc blocks added/changed, new tests created

- **F5: Product Catalog Refresh**  
  **Reads:** All product folders in `pipeline/models/` and `semantic/models/`, model counts  
  **Produces:** Updated `L2/L2_09_PRODUCT_CATALOG.md`  
  **Trigger:** New products deployed, products retired

### 4.2 Development Prompts

These prompts execute sequentially to build a data product. Each reads defined context files and produces an artifact consumed by the next step.

- **D1: Product Intake**  
  **Reads:** Requirement CSVs (via terminal), `L2_01` (quick ref), `L2_09` (product catalog)  
  **Produces:** `L3/{product}.md` — requirements analysis, column inventory, filter logic, source table candidates  
  **Context budget:** ~35 KB read

- **D2: Source Mapping**  
  **Reads:** `L3/{product}.md`, `schemas/source_index.md`, schema CSVs (filtered via terminal)  
  **Produces:** Updated `L3/{product}.md` — source mappings validated, column matrix with source `table.column`  
  **Context budget:** ~50 KB read

- **D3: Pipeline Build**  
  **Reads:** `L3/{product}.md` (source mapping section), `L2_02` (naming), `L2_03` (templates), `L2_04` (schema YML)  
  **Produces:** Pipeline `.sql` models + `_schema.yml`  
  **Context budget:** ~40 KB read

- **D4: Semantic Build**  
  **Reads:** `L3/{product}.md`, `L2_02`, `L2_03`, `L2_04`, `L2_05` (source patterns), `L2_06` (macros, if measures needed)  
  **Produces:** Semantic `.sql` models + `_schema.yml` + `_source.yml`  
  **Context budget:** ~45 KB read

- **D5: Config Integration**  
  **Reads:** `L3/{product}.md` (product metadata), `L2_08` (config patterns)  
  **Produces:** `dbt_project.yml` additions for both pipeline and semantic  
  **Context budget:** ~30 KB read

- **D6: Validation**  
  **Reads:** All generated files, `L2_10` (checklists), `L2_02` (naming), `L2_07` (generic tests)  
  **Produces:** Pass/fail report with issues to fix  
  **Context budget:** ~30 KB read

### 4.3 Workflow Sequence

#### Foundational (as needed)

- F1: Architecture Scan
- F2: Patterns Refresh
- F3: Source Index Refresh
- F4: Governance Refresh
- F5: Product Catalog Refresh

#### Development (per product)

- D1: Product Intake
- D2: Source Mapping
- D3: Pipeline Build
- D4: Semantic Build
- D5: Config Integration
- D6: Validation

Each `D` prompt is a separate agent session. The `L3` spec file (`D1`/`D2` output) is the persistent state that chains the sessions together — serving as the system’s memory store.

## 5. Orchestration and VS Code Extension

### 5.1 Orchestration Model

In this POC, the human acts as the orchestrator — manually invoking each prompt (`D1`, then `D2`, etc.) in separate Copilot chat sessions. The `L3` spec file on disk is what chains the sessions together: each prompt produces a defined artifact that the next prompt consumes.

GitHub Copilot’s current agent mode is single-threaded — one agent, one session, one task at a time. There is no built-in mechanism to spawn multiple agents in parallel, chain sessions programmatically (`D1` finishes → auto-trigger `D2`), or have an orchestrator agent delegate subtasks to worker agents.

### 5.2 Current Platform Capabilities

- **Copilot Agent Mode** — Available ✅  
  Single agent executes one prompt per session
- **Copilot custom instructions** (`.github/copilot-instructions.md`) — ✅ Available  
  Persistent system instructions across all sessions
- **Copilot prompt files** (`.github/prompts/`) — Available ✅  
  Reusable task-specific prompts — what this POC uses
- **MCP tools** — Rolling out 🔄  
  Could provide structured schema lookups instead of terminal CSV queries
- **Copilot Coding Agent** (async, PR-based) — Preview 🔵  
  Runs autonomously on a GitHub issue, creates a PR — could run D3–D6 unattended
- **Multi-agent orchestration** — Not in Copilot ❌  
  Would require external frameworks

### 5.3 Path to Automated Orchestration

To move beyond human-as-orchestrator, the options include:

1. **LangGraph / AutoGen / CrewAI** — Python-based multi-agent frameworks that can spawn parallel agents, each with their own context window and tool access. The foundational and development prompts translate directly into agent task definitions.
2. **GitHub Actions + Copilot Coding Agent** — Trigger the coding agent via GitHub issue creation within a CI workflow. A GitHub Action could create an issue with the D1 prompt content, the coding agent produces the L3 spec in a PR, and a subsequent action triggers D3–D6 as follow-on issues.
3. **Custom MCP server** — Expose the context store (`.agent_context/`) and dbt operations (`compile`, `run`, `test`) as structured tools that any agent framework can call, replacing the terminal-based file reads used in this POC.

### 5.4 Extension Workflow Requirements

A custom VS Code extension should provide a purpose-built orchestration interface for human-driven agent workflows.

The extension should offer:

- **Workflow panel** — A sidebar view showing the full prompt sequence (F1–F5, D1–D6) with status indicators (not started, in progress, completed) for the current product
- **One-click prompt invocation** — Each step launches a Copilot agent session pre-loaded with the correct prompt file and relevant context references
- **Context budget visibility** — Before launching a prompt, the extension calculates the total size of declared input files and indicates whether the budget fits the target model window
- **Artifact tracking** — As prompts produce outputs such as L3 specs, SQL files, or YAML files, the extension detects them and advances workflow status
- **Product management** — A selector for the active product (MMA, cyber, gmr, etc.) that updates the file paths used in prompt templates
- **Foundational prompt scheduling** — Indicators showing when foundational objects are stale so the user knows when to run the appropriate refresh

## 6. Predictive Simulation Widgets and Offline Forecasting

Beyond workflow orchestration, the VS Code extension should demonstrate an AI-native **predictive simulation mode** for dbt development. In this mode, the extension uses local project files, packaged sample datasets, and cached source metadata to estimate whether a model is likely to build, how it is likely to perform at runtime, and what a representative output might look like — all **without requiring a live connection to a warehouse, source system, or dbt execution environment**.

### 6.1 Functional Requirements

1. **Offline prediction mode**  
   The extension shall support an offline mode in which build predictions, performance forecasts, and result previews are derived exclusively from local artifacts, including dbt model files, YAML definitions, sample datasets, and cached source profile metadata.

2. **Automatic context discovery**  
   When a user opens a dbt model, the extension shall automatically identify and load relevant local context, including `ref()` dependencies, `source()` dependencies, model configuration, referenced macros, related `schema.yml` or `_source.yml` files, and any available sample data or source profile snapshots.

3. **Source metrics widgets**  
   For each referenced source object, the extension shall display a widget containing available source metrics, including source name, table name, estimated row count, sample row count, likely grain, join key candidates, null prevalence on key columns, and freshness or last-profiled timestamp. The widget shall clearly indicate that these values are derived from cached metadata or sample profiles rather than from a live system.

4. **Source health signals**  
   The extension shall evaluate each referenced source for common risks and display health indicators such as low sample coverage, possible duplicate grain, missing join keys, high null rates on critical fields, type mismatches across likely joins, or stale profile metadata.

5. **Buildability prediction**  
   Before generating any sample result, the extension shall first predict whether the active model is likely to build. This prediction shall be based on static analysis of the model and its local context, including unresolved `ref()` targets, unresolved `source()` targets, missing columns relative to available sample schemas, alias or join mismatches, missing macros or variables, schema incompatibilities in unions, and YAML-to-model inconsistencies.

6. **Build status classification**  
   The extension shall classify model buildability into one of three states: **Likely to Build**, **At Risk**, or **Unlikely to Build**.

7. **Prediction confidence and rationale**  
   For every build prediction, the extension shall display a confidence score and a concise explanation of the primary reasons for the prediction, including unresolved assumptions and the most likely failure points.

8. **Predicted failure surface**  
   If a model is classified as **Unlikely to Build**, the extension shall show a predicted failure summary identifying the most probable blockers, such as an unresolved source definition, missing column, incompatible join reference, or likely Jinja or macro issue.

9. **Performance forecast widget**  
   The extension shall provide a performance forecast widget that estimates projected output row count, likely runtime tier, memory or compute pressure, join explosion risk, aggregation complexity, materialization suitability, and expected model size class.

10. **Performance heuristics**  
    Performance predictions shall use heuristics derived from row counts, join cardinality assumptions, the number of joins, filter selectivity, grouping and windowing operations, incremental versus full-refresh patterns, and the expected fanout of one-to-many relationships.

11. **Performance driver explanation**  
    The extension shall explain the major factors driving the forecast, such as the largest input source, the highest-risk join, likely wide aggregations, repeated scans, or missing early-stage filters.

12. **Simulated result preview**  
    If a model is predicted as **Likely to Build** or **At Risk**, the extension shall generate a simulated result preview using local sample data and inferred transformation logic. The preview shall include projected output columns, sample output rows, inferred data types, and a projected output row-count range.

13. **Preview gating and warning behavior**  
    The extension shall apply the following gating logic:  
    - **Likely to Build** → generate projected sample result  
    - **At Risk** → generate projected sample result with warnings  
    - **Unlikely to Build** → suppress the preview by default and present predicted issues first, with optional user override for a partial preview

14. **Result provenance and assumptions**  
    Every projected result shall be labeled as a simulated or AI-projected output. The extension shall identify which local inputs were used to generate it, including source sample datasets, schema definitions, cached metrics, inferred transformations, and fallback assumptions where direct evidence was unavailable.

15. **Assumptions and confidence panel**  
    The extension shall provide an explainability panel showing which files were read, which metrics were known versus inferred, what missing context reduced confidence, and why the AI arrived at its build, performance, and result predictions.

16. **Scenario-based recalculation**  
    The extension should allow a user to modify one or more assumptions — such as row count, null rate, filter selectivity, or join cardinality — and immediately recalculate build and performance predictions. This would enable “what-if” analysis without any warehouse connection.

17. **Packaged demo data and synthetic fallback**  
    The prototype shall support packaged demo datasets and source profile snapshots so that the predictive experience works immediately in demonstration environments. If an explicit sample dataset is unavailable for a referenced source, the extension should be able to synthesize representative rows from schema metadata and naming conventions.

18. **Demo-mode disclosure**  
    The extension shall visibly indicate when it is operating in **Demo / Predictive Simulation Mode**, making clear that outputs are estimates intended to demonstrate AI-assisted reasoning rather than the result of actual warehouse execution.

### 6.2 Core Widgets

At minimum, the predictive simulation mode should expose five high-value widgets:

- **Build Predictor** — Displays build status, confidence, and likely blockers
- **Source Metrics Panel** — Displays row counts, grain, null rates, join readiness, and sample coverage
- **Performance Forecast** — Displays projected runtime tier, output size, and join or compute risk
- **Simulated Result Preview** — Displays projected output columns and representative sample rows
- **Assumptions & Confidence Panel** — Displays provenance, inference boundaries, and uncertainty drivers

### 6.3 Example Acceptance Criteria

- Given a dbt model with valid local `ref()` and `source()` dependencies, when the file is opened, the extension displays a build prediction without connecting to a warehouse.
- Given cached row-count metadata for the model’s referenced sources, the extension displays a projected output row-count range and performance tier.
- Given representative sample datasets for the model’s upstream sources, the extension produces a simulated result preview after first evaluating buildability.
- Given an unresolved source definition or missing column, the extension marks the model as **At Risk** or **Unlikely to Build** and explains the most likely cause.
- Given no live connection to any external data platform, the extension still renders all predictive widgets using local artifacts only.

## 7. Foundational Modeling and Architecture Automation

The foundational prompt system should do more than summarize the codebase. It should automatically derive and refresh a set of **foundational architectural objects** that describe how the dbt environment is structured, how existing models are categorized, which implementation patterns are canonical, and where architectural exceptions or drift exist.

These foundational objects should then be used by the AI assistant as a decision-support layer during development. In practice, this allows the assistant to behave less like a generic coding tool and more like a **dbt architecture advisor** that can classify models, recommend layer placement, suggest reuse, flag grain risks, and explain the rationale behind those recommendations.

### 7.1 Functional Requirements: Foundational Architectural Objects

1. **Model registry**  
   The foundational refresh process shall generate a machine-readable registry describing all existing models in the dbt codebase. At minimum, each model entry should capture project, folder path, model name, alias, materialization, tags, parent dependencies, downstream dependents, source dependencies, tests present, documentation status, inferred business domain, inferred layer role, and inferred model archetype.

2. **Model classification**  
   The foundational refresh process shall classify existing models into architectural categories. Classification dimensions should include layer role (for example staging, intermediate, pipeline, semantic, mart-support, or shared utility), model archetype (for example fact, dimension, bridge, aggregate, reporting, entity rollup), transformation shape (for example pass-through, enrichment, aggregation, fanout join, union, pivot, metric-support), and reuse status (for example product-specific, shared reusable, high-reuse dependency, or duplicate candidate).

3. **Grain and join registry**  
   The foundational refresh process shall generate a grain and join registry that attempts to infer likely model grain, candidate primary keys, candidate join keys, likely one-to-many relationships, likely fanout risk points, and common join paths across products. This registry shall be used by the assistant when evaluating new models or predicting runtime and row-growth behavior.

4. **Pattern library**  
   The foundational refresh process shall generate a pattern library of canonical model types and implementation approaches based on the existing codebase. For each recurring pattern, the system should capture the purpose of the pattern, typical upstream inputs, typical downstream consumers, common SQL structure, expected materialization, common config patterns, common tests, and representative model examples.

5. **Reuse and similarity index**  
   The foundational refresh process shall generate a reuse and similarity index that identifies models with similar structure, models serving similar business purposes, likely reusable upstream components, likely duplicated logic across products, and nearest-neighbor examples for new model design. This index shall support assistant guidance that favors reuse over duplication.

6. **Architectural rules and decision matrix**  
   The foundational refresh process shall generate a decision matrix describing architecture rules and preferred design choices. Examples include when logic belongs in pipeline versus semantic, when a source should be introduced via `_source.yml`, when a shared model should be reused rather than recreated, when a model should aggregate versus remain atomic, when specific materializations are preferred, and when semantic models should read from pipeline outputs instead of raw sources.

7. **Drift and exception catalog**  
   The foundational refresh process shall maintain a catalog of architectural exceptions, outlier models, legacy patterns, deprecated approaches, and rule violations requiring manual review. This prevents the assistant from treating every existing example as equally correct.

8. **Staleness and refresh metadata**  
   Each foundational object shall include refresh metadata such as last refreshed timestamp, source files used, inferred versus explicit fields, confidence level, and staleness indicator so that the assistant and extension UI can disclose how current and reliable the architectural guidance is.

### 7.2 Functional Requirements: Foundational Refresh Process

9. **Multi-step foundational refresh**  
   The foundational refresh workflow shall be decomposed into separate steps so that architectural intelligence can be built in layers rather than in one monolithic scan. A recommended sequence is: inventory existing models, classify models, infer grain and joins, cluster recurring patterns, identify reuse opportunities, derive decision rules, and flag drift or exceptions.

10. **Incremental refresh**  
    The system should support incremental refresh behavior so that foundational objects can be partially refreshed when models are added, moved, or removed; when YAML files change; when macros change; when `dbt_project.yml` configuration changes; or when source profiles are updated.

11. **Refresh diff reporting**  
    Each foundational refresh should produce a human-readable diff summary indicating newly discovered models, changed classifications, new or removed patterns, new reuse candidates, newly detected architecture drift, and updates to inferred rules.

12. **Verification pass**  
    The foundational refresh process shall include a verification step that checks generated architectural objects for internal consistency. Examples include confirming that model classification aligns with folder or project location, inferred grain is consistent with grouping logic, recommended archetype matches SQL shape, reuse recommendations do not point to deprecated models, and architectural rules do not conflict with explicit standards.

13. **Confidence-aware inference**  
    Where architecture metadata is inferred rather than explicitly declared, the system shall assign confidence indicators so the assistant can distinguish between an explicit known fact, a high-confidence inference, and a low-confidence heuristic guess.

### 7.3 Recommended New Foundational Prompts

In addition to the existing F1–F5 prompt set, the following foundational prompts would strengthen modeling and architecture automation:

- **F6: Model Registry and Classification Refresh** — Reads all SQL models, schema YAMLs, `dbt_project.yml`, tags, folder structure, and manifest artifacts if available. Produces `architecture/model_registry.md` or `architecture/model_registry.csv` plus `architecture/model_taxonomy.md`.
- **F7: Grain and Join Map Refresh** — Reads model SQL, source mappings, sample profiles, and schema metadata. Produces `architecture/grain_registry.md` and `architecture/join_path_map.md`.
- **F8: Pattern Library Refresh** — Reads classified models, representative examples, templates, and macros. Produces `architecture/pattern_library.md` and `architecture/template_recommendations.md`.
- **F9: Reuse and Overlap Refresh** — Reads the model registry, dependency graph, taxonomy, and similarity signals. Produces `architecture/reuse_index.md` and `architecture/duplication_candidates.md`.
- **F10: Architecture Rules and Drift Refresh** — Reads all foundational objects plus explicit standards documents. Produces `architecture/decision_matrix.md` and `architecture/drift_catalog.md`.

## 8. Runtime Architectural Guidance

The AI assistant should use the foundational architectural objects not merely as reference material, but as an active decision-support layer during development. This means it should be able to answer not only **what exists**, but also **what should be built**, **where it should live**, **which existing pattern should be followed**, **whether duplicate logic is being introduced**, and **what architectural risk a proposed model creates**.

### 8.1 Functional Requirements: Runtime Architectural Guidance

14. **Architectural classification on model open**  
    When a user opens or edits a dbt model, the assistant shall automatically classify the model against the foundational objects and display the likely layer role, likely archetype, likely grain, likely transformation shape, nearest similar existing models, and confidence level.

15. **Placement recommendation**  
    For a new or modified model, the assistant shall recommend where the model should live, including the target project, target folder, whether it belongs in pipeline or semantic, the expected materialization, and the YAML or config artifacts likely required.

16. **Reuse recommendation**  
    The assistant shall recommend reuse opportunities before suggesting net-new model creation. This may include existing upstream models that already provide the needed logic, semantically similar models, shared dimensions or facts, reusable macros, and warnings about likely duplicate logic.

17. **Grain and fanout guidance**  
    The assistant shall use the grain and join registry to warn the user about likely architectural risks such as grain mismatch, duplicate-row risk, one-to-many join expansion, accidental aggregation at the wrong level, or semantic exposure before the grain is stable.

18. **Pattern-based scaffolding**  
    The assistant shall recommend or generate model scaffolding based on the closest canonical architectural pattern identified in the pattern library. This should include suggested SQL structure, suggested tests, suggested schema documentation patterns, suggested config blocks, and suggested source wiring patterns.

19. **Architecture drift detection**  
    The assistant shall detect when a proposed model or edit appears to drift from the dominant architectural rules captured in the foundational objects. Examples include a semantic model directly pulling raw source data, a pipeline model acting like a reporting mart, duplicate business logic in multiple products, inconsistent naming or materialization, or unexpected cross-domain dependency.

20. **Decision rationale**  
    For every major architectural recommendation, the assistant shall explain the rationale using the foundational objects. Example reasoning includes: the model most closely matches a known aggregate pattern, similar models are typically implemented in pipeline or intermediate layers, semantic models in the same domain usually read from a pipeline `_source.yml`, row-growth risk suggests aggregation should happen upstream, or an existing reusable model already covers most of the required logic.

21. **Architecture guidance panel**  
    The extension should surface an **Architecture Guidance Panel** that summarizes the assistant’s current guidance for the active model. At minimum, this panel should show the recommended architectural role, recommended location, predicted grain, reuse candidates, canonical examples, architecture risks, and any rule exceptions or drift warnings.

### 8.2 Example Assistant Behaviors

With these foundational objects in place, the assistant could provide guidance such as:

- “This model looks like a pipeline enrichment model, not a semantic exposure model.”
- “A very similar model already exists in the GMR product and may be reusable.”
- “The join to policy coverage appears one-to-many and is likely to increase row count.”
- “Models of this archetype are typically materialized as views and tested with uniqueness plus referential checks.”
- “This proposed model appears to duplicate logic already handled in an upstream shared dimension.”
- “Based on existing architecture patterns, this should likely be split into an intermediate pipeline model and a thinner semantic model.”

### 8.3 Design Principle

The foundational prompts should not merely document the codebase; they should transform it into architectural objects that allow the AI assistant to classify models, infer canonical patterns, recommend reuse, detect drift, and guide developers toward standards-compliant dbt design decisions.

One important guardrail is that the assistant should learn from the codebase **without treating the codebase as uniformly correct**. That is why the drift catalog, exception catalog, and decision matrix are critical. Without them, the assistant may copy legacy or accidental patterns simply because they already exist.
