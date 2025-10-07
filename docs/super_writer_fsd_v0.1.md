# Functional Specification Document (FSD)

**Project:** super_writer
**Version:** 0.1
**Date:** 2025-10-06
**Based on:** PRD v0.1
**Audience:** Developers and technical architects implementing the system.

[TOC]

## 1. Introduction

This Functional Specification Document (FSD) translates the PRD v3.1 into actionable, technical implementation details. It specifies internal architecture, module interactions, data models, CLI commands, and system behaviors for developers.

---

## 2. System Overview

### 2.1 Purpose
The system automates technical content generation via a command-line interface, orchestrating multiple AI agents using the **CrewAI** framework and the **ReAct (Reason + Act)** pattern.

### 2.2 Architecture Summary

```
CLI (Typer) - Dual Mode Support (Auto/Interactive)
  └── Workflow Orchestrator (CrewAI + SupervisorAgent)
        ├── Model Router (Multi-provider LLM abstraction)
        ├── Agents Layer (BaseReActAgent subclasses)
        │    ├── ResearchAgent
        │    ├── OutlineAgent
        │    ├── WriterAgent
        │    ├── ReviewerAgent
        │    ├── FormatterAgent
        │    └── ExporterAgent
        ├── Tools Layer (Search, CodeEval, Formatter, Validator)
        ├── Checkpoint Manager (Step interruption/resumption)
        └── Telemetry Layer (JSON + SQLite logging + topic-based storage)
```

---

## 3. Functional Modules

### 3.1 CLI Layer
Implements user interaction, workflow execution, configuration, and reporting.

**Responsibilities:**
- Parse commands via `Typer` with dual operational mode support
- Pass parameters to Workflow Orchestrator
- Manage execution modes (`--auto`, `--interactive`, `--dry-run`, `--resume`, `--budget`)
- Handle step interruption and user interaction prompts
- Display progress and results via `rich` with interactive review capabilities
- Support model profile selection and switching

**Key Commands:**

| Command | Description | Example |
|----------|--------------|----------|
| `run` | Execute a workflow (auto or interactive) | `super_writer run --workflow article_creation --mode auto` |
| `resume` | Continue from last checkpoint | `super_writer resume --mode interactive` |
| `interrupt` | Manually trigger step interruption | `super_writer interrupt --step writer` |
| `review` | Inspect intermediate outputs | `super_writer review --topic-id async-patterns-20251006` |
| `config` | Manage configurations and model profiles | `super_writer config validate` |
| `cost` | Estimate API usage by model profile | `super_writer cost article_creation --model-profile balanced` |
| `status` | Display workflow progress | `super_writer status --topic-id async-patterns-20251006` |

---

### 3.2 Workflow Orchestrator

Central controller handling step sequencing, agent dispatch, and error management.

**Core class:** `WorkflowOrchestrator`

**Responsibilities:**
- Parse workflow YAML and model profiles
- Execute steps sequentially or conditionally with checkpoint support
- Pass intermediate data between agents with topic-based organization
- Implement ReAct loop supervision with step interruption capability
- Handle retries via `tenacity` and graceful degradation
- Manage dual operational modes (auto/interactive)
- Coordinate with Model Router for dynamic LLM selection

**Key Methods:**
```python
class WorkflowOrchestrator:
    def __init__(self, workflow_path: str, model_router: ModelRouter):
        self.steps = self.load_yaml(workflow_path)
        self.model_router = model_router
        self.checkpoint_manager = CheckpointManager()
        self.topic_id = self.generate_topic_id()

    def execute(self, seed: str, mode: str = "auto", resume: bool = False):
        if resume:
            self.load_checkpoint()

        for step in self.steps:
            if mode == "interactive":
                self._handle_interactive_step(step)
            else:
                self._run_step(step)

    def _run_step(self, step):
        agent = self._get_agent(step.agent)
        output = agent.run(step.input)
        self._store_result(step.name, output)
        self.checkpoint_manager.save(self.topic_id, step.name, output)

    def _handle_interactive_step(self, step):
        # Execute step and prompt for user review/edits
        result = self._run_step(step)
        action = self.prompt_user_action(step.name, result)
        if action == "edit":
            edited_result = self.open_editor(result)
            self._store_result(step.name, edited_result)
        elif action == "retry":
            self._run_step(step)
```

---

## 4. LLM Management and Model Routing

### 4.1 Model Router Architecture

The ModelRouter provides a unified abstraction layer for all language models, enabling rapid switching between providers and cost-quality optimization.

```python
class ModelRouter:
    def __init__(self, profile_file="model_profiles.yaml"):
        self.profiles = yaml.safe_load(open(profile_file))["models"]
        self.cost_tracker = CostTracker()

    def get_client(self, profile_name: str):
        profile = self.profiles[profile_name]
        provider = profile["provider"]

        if provider == "openai":
            from openai import OpenAI
            client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
            return client, profile
        elif provider == "anthropic":
            from anthropic import Anthropic
            client = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
            return client, profile
        elif provider == "ollama":
            from ollama import Client
            client = Client(host=profile.get("host", "localhost:11434"))
            return client, profile
        else:
            raise ValueError(f"Unsupported provider: {provider}")
```

### 4.2 Model Profile Configuration (model_profiles.yaml)

```yaml
models:
  writer-high:
    provider: openai
    model: gpt-4-turbo
    temperature: 0.7
    max_tokens: 4000
    cost_estimate_per_1k: 0.03

  reviewer-lite:
    provider: openai
    model: gpt-3.5-turbo
    temperature: 0.5
    max_tokens: 2000
    cost_estimate_per_1k: 0.0015

  local-draft:
    provider: ollama
    model: mistral
    temperature: 0.8
    max_tokens: 3000
    host: localhost:11434
    cost_estimate_per_1k: 0.0
```

### 4.3 Dynamic Model Switching

CLI override example:
```bash
super_writer run --workflow article_creation --model-profile reviewer-lite
```

Runtime model switching:
```python
def switch_agent_model(self, agent_name: str, new_profile: str):
    agent = self.agents[agent_name]
    client, profile = self.model_router.get_client(new_profile)
    agent.update_model(client, profile)
```

### 4.4 Cost Monitoring and Analytics

Each model profile defines cost estimates. During execution:
```json
{
  "step": "writer",
  "model": "gpt-4-turbo",
  "tokens": 3120,
  "cost_estimate": 0.0936,
  "duration": 43.2,
  "quality_score": 8.7
}
```

### 4.5 Model Profile Strategies

| Profile | Strategy | Use Case |
|---------|----------|----------|
| low-cost | Use free/low-cost LLMs for drafts | Exploratory runs |
| balanced | Mix of GPT-3.5 + GPT-4 | Default production |
| premium | Use GPT-4 for all steps | High-value content |
| local | Use Ollama for offline work | Testing & prototyping |

---

## 5. Agent Specifications

All agents subclass `BaseReActAgent`, implementing `reason()`, `act()`, `observe()`.

### 5.1 BaseReActAgent

```python
class BaseReActAgent:
    def __init__(self, config):
        self.model = config.model
        self.max_iterations = config.get("max_iterations", 3)

    def run(self, input_data):
        observations = []
        for i in range(self.max_iterations):
            thought = self.reason(input_data, observations)
            action = self.act(thought)
            result = self.observe(action)
            observations.append(result)
            if self.should_stop(thought, observations):
                break
        return observations[-1]

    def reason(self, input_data, observations): pass
    def act(self, thought): pass
    def observe(self, action): pass
    def should_stop(self, thought, observations): return False
```

### 5.2 ResearchAgent

- **Purpose:** Generate 5–10 topic suggestions using LLM and optional search tools.
- **Inputs:** Seed keywords
- **Outputs:** JSON list of `{title, relevance_score}`
- **Tools:** WebSearchTool
- **Model:** GPT‑4

### 5.3 OutlineAgent

- Generates structured article outlines (H1–H3).
- Uses ReAct to refine structure based on research results.
- Supports custom templates in YAML.

### 5.4 WriterAgent

- Produces technical Markdown with 2–5 code examples.
- Iterates until reviewer score ≥ 8.
- Includes Mermaid diagrams when context suggests.

### 5.5 ReviewerAgent

- Analyzes draft for readability, grammar, and accuracy.
- Returns a JSON feedback structure:
```json
{
  "score": 8.7,
  "issues": ["Unclear intro", "Missing code comment"],
  "suggestions": ["Add example for async usage"]
}
```

### 5.6 FormatterAgent

- Applies consistent Markdown styling and Astro frontmatter.
- Handles title slug, publish date, and summary metadata.

### 5.7 ExporterAgent

- Writes final Markdown to `/output/YYYY-MM-DD-title.md`.
- Generates backups and version history.

---

## 6. Workflow Engine

### 6.1 Workflow Definition Schema (YAML)

```yaml
name: article_creation
type: react_workflow
steps:
  - name: research
    agent: research_agent
    input: ${seed_keywords}
  - name: outline
    agent: outline_agent
    user_approval: true
  - name: draft
    agent: writer_agent
    loop_until: review_score >= 8
  - name: review
    agent: reviewer_agent
  - name: format
    agent: formatter_agent
  - name: export
    agent: exporter_agent
```

### 6.2 Conditional and Iterative Logic

- Conditional re-entry to “draft” step if reviewer score < threshold.
- SupervisorAgent ensures loop count limit.

---

## 7. Configuration Management

### 7.1 Files

| File | Purpose |
|------|----------|
| `agents.yaml` | Define agent prompts and LLM configs |
| `model_profiles.yaml` | Define model profiles and cost estimates |
| `workflows.yaml` | Define step sequence and logic |
| `.env` | Store API keys |
| `telemetry.db` | SQLite metrics cache |
| `.super_writer/checkpoints/` | Checkpoint files for resumption |

### 7.2 YAML Schema Example

```yaml
agents:
  writer_agent:
    model: gpt-4
    temperature: 0.7
    max_tokens: 4000
    tools: [code_validator, syntax_highlighter]
```

### 7.3 Validation

- Enforced via `pydantic` models
- `super_writer config validate` checks for missing or deprecated keys
- Model profile validation ensures provider compatibility and API key availability

---

## 8. Data Flow & Storage

### 8.1 Topic-Based Output Organization

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

### 8.2 Output Metadata

Each file includes YAML frontmatter:
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

### 8.3 In-memory Objects
```python
ArticleData = {
  "topic_id": str,
  "topic": str,
  "outline": list[str],
  "draft": str,
  "feedback": dict,
  "final": str,
  "checkpoint": dict
}
```

### 8.4 SQLite Schema
```sql
CREATE TABLE telemetry (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    topic_id TEXT,
    step TEXT,
    model TEXT,
    tokens INT,
    cost FLOAT,
    duration FLOAT,
    quality_score FLOAT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE checkpoints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    topic_id TEXT,
    step TEXT,
    status TEXT,
    data TEXT, -- JSON
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

---

## 9. Security & Access Control

- Use `python-dotenv` for key loading
- Validate `.env` permissions on startup
- Never log keys or prompt contents containing sensitive data
- Enforce file-level write protection for outputs

---

## 10. Error Handling & Recovery

| Error Type | Auto Mode | Interactive Mode |
|-------------|-----------|------------------|
| APIError | Automatic retry (max 3) | Prompt user to retry/edit |
| ValidationError | Halt and display message | Prompt for correction |
| FileWriteError | Fallback to temp dir | Prompt for alternative location |
| WorkflowAbort | Save checkpoint, exit gracefully | Ask before aborting |
| ModelQualityError | Escalate to higher-tier model | Ask user to approve/model switch |
| CheckpointCorruption | Restart from last valid checkpoint | Prompt for manual recovery |

### 10.1 Checkpoint Management

```python
class CheckpointManager:
    def __init__(self, checkpoint_dir=".super_writer/checkpoints"):
        self.checkpoint_dir = checkpoint_dir

    def save(self, topic_id: str, step: str, data: dict):
        checkpoint = {
            "topic_id": topic_id,
            "step": step,
            "data": data,
            "timestamp": datetime.utcnow().isoformat()
        }
        Path(self.checkpoint_dir).mkdir(exist_ok=True)
        with open(f"{self.checkpoint_dir}/{topic_id}.json", "w") as f:
            json.dump(checkpoint, f, indent=2)

    def load(self, topic_id: str) -> dict:
        with open(f"{self.checkpoint_dir}/{topic_id}.json", "r") as f:
            return json.load(f)
```

---

## 11. Logging & Telemetry

- JSON logs written to `/output/<topic_id>/logs/telemetry.json`
- Log fields: `step`, `status`, `model`, `tokens`, `cost`, `duration`, `quality_score`, `retry_count`
- SQLite persistence for analytics and cost tracking
- Per-model cost aggregation and performance metrics
- Interactive session transcripts for reproducibility

### 11.1 Telemetry Data Structure

```json
{
  "workflow_id": "async-patterns-in-fastapi-20251006",
  "mode": "interactive",
  "steps": [
    {
      "step": "research",
      "model": "gpt-4",
      "tokens": 1200,
      "cost": 0.036,
      "duration": 12.5,
      "status": "completed",
      "quality_score": null
    },
    {
      "step": "writer",
      "model": "gpt-4",
      "tokens": 3120,
      "cost": 0.0936,
      "duration": 43.2,
      "status": "completed",
      "quality_score": 8.7,
      "iterations": 2
    }
  ],
  "total_cost": 0.1296,
  "total_duration": 55.7
}
```

---

## 12. Testing & Validation

| Test Type | Scope | Tool |
|------------|--------|------|
| Unit | Agent logic, config parsing, model routing | pytest |
| Integration | End-to-end workflow with both modes | pytest + temp dirs |
| Regression | Prompt outputs, model profile behavior | snapshot testing |
| Performance | Token/time metrics, cost tracking | custom harness |
| Interactive | Step interruption/resumption flow | CLI simulation tests |

### 12.1 Model Switching Tests

```python
def test_model_router_switching():
    router = ModelRouter("test_model_profiles.yaml")

    # Test OpenAI client creation
    client, profile = router.get_client("writer-high")
    assert profile["model"] == "gpt-4-turbo"

    # Test cost tracking
    cost = router.cost_tracker.calculate_cost("writer-high", 1000)
    assert cost == 0.03
```

---

## 13. Extensibility & Plugin Framework

### 13.1 Agent Plugin Structure

```
agents/
  writer/
    config.yaml
    prompt.txt
    tools/
      - validator.py
```

### 13.2 Adding New Agents

1. Create folder under `agents/`
2. Define config and prompt
3. Register in `agents.yaml`
4. Add to `workflows.yaml`
5. Define model profile requirements in `model_profiles.yaml`

### 13.3 Model Provider Extension

To add new LLM providers:

1. Add provider support in `ModelRouter.get_client()`
2. Define provider-specific connection logic
3. Add provider to model profile schema
4. Update cost calculation methods
5. Add provider-specific tests

---

## 14. Performance Targets & Monitoring

| Metric | Target | Measurement Method |
|---------|---------|---------------------|
| Workflow completion | <5 minutes | End-to-end timing |
| Memory footprint | <500 MB | Process monitoring |
| Average ReAct iterations | ≤3 | Step iteration tracking |
| Token cost | <$0.50/article | Cost aggregation |
| Model switching latency | <2 seconds | Provider change timing |
| Checkpoint save/restore | <1 second | File I/O timing |
| Interactive response time | <3 seconds | User prompt handling |

### 14.1 Cost Optimization Monitoring

- Track per-model cost vs quality ratios
- Monitor escalation patterns (low-cost → premium models)
- Alert on budget threshold breaches
- Generate cost reports by model profile and agent

### 14.2 Quality vs Cost Analytics

```python
def analyze_cost_quality_metrics():
    # Query SQLite for recent runs
    results = db.query("""
        SELECT model, step, quality_score, cost, tokens
        FROM telemetry
        WHERE timestamp > date('now', '-7 days')
    """)

    # Calculate cost per quality point
    for result in results:
        cost_per_quality = result.cost / result.quality_score
        # Log for optimization decisions
```

---

## 15. Appendices

### A. Agent-Tool Interface Example

```python
class CodeEvalTool:
    def execute(self, code: str) -> dict:
        try:
            result = subprocess.run(["python3", "-c", code], capture_output=True, timeout=5)
            return {"status": "success", "output": result.stdout.decode()}
        except Exception as e:
            return {"status": "error", "message": str(e)}
```

### B. CLI Exit Codes

| Code | Meaning |
|------|----------|
| 0 | Success |
| 1 | Validation failure |
| 2 | API error |
| 3 | User aborted |
| 4 | Model configuration error |
| 5 | Checkpoint corruption |

### C. Model Profile Reference

```yaml
# Complete model profile schema
models:
  profile_name:
    provider: openai|anthropic|ollama|custom
    model: string
    temperature: float (0.0-2.0)
    max_tokens: int
    cost_estimate_per_1k: float
    provider_specific:
      # Provider-specific settings
      host: string  # for Ollama
      region: string  # for cloud providers
```

### D. Checkpoint File Format

```json
{
  "topic_id": "async-patterns-in-fastapi-20251006",
  "workflow": "article_creation",
  "last_completed_step": "writer",
  "current_iteration": 2,
  "data": {
    "topic": "Async Patterns in FastAPI",
    "outline": [...],
    "draft": "# Async Patterns..."
  },
  "telemetry": {
    "total_cost": 0.1296,
    "total_tokens": 4320,
    "duration": 55.7
  },
  "timestamp": "2025-10-06T16:12:30Z"
}
```

---

_ Version 1.1 — Enhanced with dual operational modes, topic-based organization, dynamic LLM management, and interactive workflow capabilities._
