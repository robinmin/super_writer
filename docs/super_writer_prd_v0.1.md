# Product Requirements Document (PRD)

**Project:** super_writer
**Owner:** Robin Min
**Date:** 2025-10-06
**Version:** v0.1
**Scope:** Internal CLI tool for generating technical content in Markdown format.

[TOC]

## 1. Executive Summary

This PRD defines an internal CLI tool leveraging **CrewAI** and the **ReAct (Reason + Act)** pattern to automate technical content generation. The tool transforms manual writing processes into structured AI-driven workflows, producing publish-ready Markdown articles, code examples, diagrams, and social media content.

**Key deliverables:**
- CLI tool with dual operational modes (Auto/Interactive) and extensible multi-agent ReAct framework
- YAML-driven workflows with step interruption and resumption capabilities
- Dynamic LLM management system for cost-quality optimization
- Topic-based output organization with full markdown audit trail
- Structured logging and review loops
- Seamless integration with existing Astro publishing pipeline

---

## 2. Problem Statement

**Current State:** Content creation remains inefficient and inconsistent across technical writers.

**Pain Points:**
- Research and ideation consume excessive time
- Inconsistent outlines and formatting
- Manual insertion of code snippets and diagrams
- Lack of automated quality feedback

**Business Impact:** Slow output and inconsistent quality.

**Solution:** A modular AI-driven CLI that automates ideation, drafting, reviewing, and publishing preparation using the ReAct reasoning loop.

---

## 3. Goals & Scope

### Primary Goals
- Reduce content creation time by 70%
- Support both autonomous and human-guided content generation workflows
- Enable iterative quality loops using ReAct with step interruption capabilities
- Ensure uniform style and accuracy with flexible LLM cost-quality management
- Integrate with existing Astro workflow

### Secondary Goals
- Plugin-based extensibility with rapid model switching
- Dynamic and conditional workflows with checkpoint-based resumption
- Cost and performance monitoring with per-model analytics
- Topic-based content organization for easy navigation and versioning

### In Scope
- CLI-driven content generation with dual operational modes (Auto/Interactive)
- Topic-based markdown output organization with full audit trail
- ReAct-based agent orchestration with step interruption and resumption
- Dynamic LLM management with cost-quality optimization
- Configurable YAML workflows with checkpoint-based recovery

### Out of Scope
- Multi-user collaboration
- Full GUI or web interface
- Automated publishing
- Vector database implementation (deferred to future phase)

---

## 4. Stakeholders

| Role | Responsibility |
|------|----------------|
| Product Owner | Defines and prioritizes features |
| Technical Lead | Oversees system architecture and implementation |
| End User | Developer/content creator using CLI |
| QA Engineer | Ensures correctness and reliability |

---

## 5. User Stories & Acceptance Criteria

(Identical to v3.0 with added ReAct loop behavior — all writing, reviewing, and formatting agents must provide reasoning traces and self-evaluation.)

---

## 6. Assumptions & Constraints

**Added:**
- ReAct loops must cap iterations to prevent infinite cycles
- CLI must operate fully offline except for LLM API calls
- Each agent execution is idempotent and traceable

---

## 7. System Architecture

```text
┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────┐
│   CLI Layer     │───▶│  Workflow Orchestr. │───▶│   Agent Layer   │
│   (Typer)       │    │  (CrewAI + ReAct)   │    │   (LLM + Tools) │
└─────────────────┘    └─────────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Configuration   │    │   In-Memory     │    │   Tool Layer    │
│   (YAML)        │    │   Data Flow     │    │   (Web/API)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

**Enhancements:**
- Introduce `SupervisorAgent` for global orchestration and fallback handling.
- Implement `BaseReActAgent` providing `reason()`, `act()`, `observe()`, `loop()` hooks.
- Add optional telemetry layer for token, cost, and latency tracking.

---

## 8. System Components (Agents)

| Agent | Role | Notes |
|--------|------|------|
| `supervisor_agent` | Oversees workflow execution, error handling, and loop limits | New |
| `research_agent` | Topic ideation and trend analysis | Uses ReAct loop |
| `outline_agent` | Outline generation | Supports template injection |
| `writer_agent` | Draft generation (Markdown + code) | Implements iterative refinement |
| `reviewer_agent` | Evaluates grammar, accuracy, and structure | Uses scoring feedback |
| `formatter_agent` | Final polish and metadata generation | Adds Astro frontmatter |
| `exporter_agent` | Writes outputs to disk | Handles versioning and cleanup |

Each agent uses declarative YAML configuration (`agents.yaml`) and shares a reusable ReAct core.

---

## 9. Workflow Design

### ReAct-based Iterative Workflow

```yaml
name: article_creation
type: react_workflow
steps:
  - research
  - outline (requires: user_approval)
  - draft (loop_until: review_score >= 8)
  - review
  - format
  - export
```

- **Conditional logic:** Steps can re-run if review scores fall below threshold.
- **Observation tracking:** Each iteration logged with reason and action summaries.
- **User controls:** `--dry-run`, `--resume`, and `--budget` flags supported.

---

## 10. CLI Interface

### 10.1 Operational Modes

The CLI supports two operational modes:

| Mode | Description | Use Cases |
|------|-------------|-----------|
| Auto Mode | Fully autonomous end-to-end execution using predefined agents, thresholds, and retry logic | Batch content generation, daily automation |
| Interactive Mode | Human-in-the-loop execution allowing pause, review, and modification after specific workflow steps | Prompt tuning, quality refinement, debugging |

### 10.2 Command Structure

```bash
super_writer [COMMAND] [OPTIONS]
```

**Primary Commands:**

| Command | Description | Example |
|----------|--------------|----------|
| `run` | Execute a workflow (auto or interactive) | `super_writer run --workflow article_creation --mode auto` |
| `resume` | Continue from last checkpoint | `super_writer resume --mode interactive` |
| `interrupt` | Manually trigger step interruption or rollback | `super_writer interrupt --step writer` |
| `review` | Inspect intermediate outputs interactively | `super_writer review --topic-id async-patterns-20251006` |
| `config` | Manage YAML configurations and model profiles | `super_writer config validate` |
| `cost` | Estimate API usage and cost | `super_writer cost article_creation --model-profile balanced` |
| `status` | Display current workflow status | `super_writer status --topic-id async-patterns-20251006` |

### 10.3 Global Options

| Flag | Description |
|------|-------------|
| `--mode [auto\|interactive]` | Operational mode selection |
| `--seed <string>` | Seed keywords or topic for content |
| `--workflow <name>` | Select workflow file |
| `--threshold <float>` | Override review score threshold |
| `--budget <float>` | Set max token cost per run |
| `--model-profile <name>` | Select model profile (low-cost/balanced/premium) |
| `--dry-run` | Print workflow plan without execution |
| `--json-output` | Emit machine-readable logs |

### 10.4 Workflow Interruption and Resumption

Each major step (Research → Outline → Writer → Reviewer → Formatter → Exporter) writes a checkpoint file to `.super_writer/checkpoints/<topic_id>.json`. In interactive mode, operators can:
- Accept result → proceed
- Reject result → rerun step
- Edit intermediate file → continue
- Abort workflow → resume later via `--resume`

---

## 11. Tech Stack & Dependencies

**Core:**
- Python 3.10+
- CrewAI ≥ 0.1.0
- Typer, PyYAML, OpenAI SDK, Rich

**LLM Management:**
- Model abstraction layer for multi-provider support
- Provider adapters: OpenAI, Anthropic, Ollama (local models)
- Cost tracking and token usage analytics

**Enhancements:**
- `tenacity` for retries
- `pydantic` for config validation
- `loguru` for structured logs
- `python-dotenv` for secure key management
- `rich` for interactive CLI progress and step review

---

## 12. Functional Requirements

(Extends v3.0 — adds ReAct support, reasoning trace persistence, and conditional retries per step.)

---

## 13. Non-Functional Requirements

| Category | Requirement |
|-----------|-------------|
| **Performance** | Workflow < 5 min; individual step < 30s |
| **Extensibility** | Modular plugin agent structure |
| **Reliability** | Graceful degradation, automatic retries |
| **Security** | API key encryption via .env |
| **Usability** | CLI guided prompts and live progress |
| **Observability** | JSON logs: step, tokens, cost, latency |

---

## 14. Data Flow & Storage

### 14.1 Topic-Based Output Organization

Each article or task run is assigned a topic ID, serving as the root folder for all intermediate and final artifacts:

```
/output/
  ├── async-patterns-in-fastapi-20251006/
  │   ├── research/
  │   │   └── topics.md
  │   ├── outline/
  │   │   └── outline-v1.md
  │   ├── draft/
  │   │   ├── draft-v1.md
  │   │   └── draft-v2.md
  │   ├── review/
  │   │   └── feedback.json
  │   ├── format/
  │   │   └── formatted.md
  │   ├── export/
  │   │   └── final.md
  │   └── logs/
  │       └── telemetry.json
```

Root folder naming: `${topic_slug}-${timestamp}`

### 14.2 Output Metadata

Each file includes YAML frontmatter for traceability:
```yaml
---
topic_id: async-patterns-in-fastapi-20251006
step: writer
timestamp: 2025-10-06T16:10Z
iteration: 2
model: gpt-4
workflow: article_creation
---
```

### 14.3 Data Persistence

- SQLite database for workflow history and cost metrics
- Data formats: YAML config, Markdown output, JSON logs
- Checkpoint files for workflow resumption
- Telemetry tracking per model profile and step

### 14.4 Vector Database (Deferred)

Vector database implementation (e.g., VectorLiteDB) deferred to future phase to maintain simplicity and focus on core functionality.

---

## 15. Security Considerations

- API keys stored in `.env` file
- Input validation for prompts and parameters
- Local-only file writes
- Optional offline mode for cached operations

---

## 16. Testing Strategy

- Unit tests per agent (reason-act-observe loop behavior)
- Regression tests for prompt templates
- End-to-end validation of ReAct loop convergence
- Cost/time performance benchmarks
- CI automation with coverage >80%

---

## 17. Success Metrics & KPIs

Added metrics:
- **ReAct loop efficiency:** avg. iterations per step <3
- **Token cost per article:** <$0.50 avg.
- **Content quality:** reviewer score ≥8.5/10
- **Model cost optimization:** per-profile cost tracking and comparison
- **Interactive efficiency:** step interruption/resumption success rate
- **Topic organization effectiveness:** retrieval time for past content

---

## 18. Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|-------|--------------|---------|-------------|
| Infinite reasoning loops | Low | High | Iteration caps |
| Cost overruns | Medium | Medium | Budget flag, model profile switching |
| Workflow corruption | Low | Medium | Resume checkpoints, topic-based backup |
| LLM API downtime | Medium | High | Retry + fallback model, multi-provider support |
| Model quality inconsistency | Medium | High | Dynamic model switching, per-step quality scoring |
| Interactive workflow complexity | Medium | Medium | Clear CLI prompts, checkpoint validation |

---

## 19. Deployment & Operations

- `pip install super_writer`
- Supports `.env` for keys, YAML for config
- `super_writer config validate` to check schema
- Versioned releases via PyPI

---

## 20. Future Roadmap

### Phase 2 (Q1 2026)
- Dynamic ReAct loop orchestration
- Vector database implementation (VectorLiteDB)
- Multi-format exports (HTML, PDF)
- Agent plugin registry
- Adaptive model routing based on cost-quality metrics

### Phase 3 (Q2 2026)
- Web UI for workflow management
- Advanced cost optimization algorithms
- LLM benchmarking dashboard
- Team collaboration features

### Long-term
- Enhanced vector similarity search for content reuse
- Self-improving ReAct reasoning patterns
- Multi-modal content generation (images, diagrams)
- Enterprise-grade deployment options

---

## 21. Appendices

- **A:** BaseReActAgent interface definition
- **B:** Agent prompt schema
- **C:** YAML schema v2.0
- **D:** Logging and telemetry JSON format

---

_Version 3.2 — Enhanced with dual operational modes, topic-based organization, dynamic LLM management, and interactive workflow capabilities._
