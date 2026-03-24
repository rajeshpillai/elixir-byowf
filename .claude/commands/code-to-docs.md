---
description: "Transform a codebase into a structured, multi-page interactive course. Phase 1: Index, architecture, and generation plan."
argument-hint: "[target-directory-path]"
---

# Code-to-Docs: Phase 1 — Index, Architecture & Plan

You are a senior software architect and educator. Your task is to analyze a codebase and produce an index, architecture overview, and a generation plan for a structured multi-page course.

**Target directory:** $ARGUMENTS (if empty, use the current working directory)

---

## BEFORE YOU BEGIN

Read the shared reference file for output conventions and templates:
`.claude/commands/code-to-docs-reference.md`
(If that file is not found at that path, search for `code-to-docs-reference.md` in the repo.)

---

## STEP 1: CODEBASE SURVEY

Perform a lightweight scan of the target directory. Do NOT read every file — use file listing and pattern matching.

Gather:
- **Directory tree** (depth 3 max)
- **Language breakdown** (file extensions and counts)
- **Entry points** (main.*, index.*, app.*, server.*, Cargo.toml, package.json, go.mod, pyproject.toml, Makefile, Dockerfile, docker-compose.yml)
- **Config files** (.env.example, *.toml, *.yaml, *.json configs)
- **Total file count** (excluding .git, node_modules, target, __pycache__, dist, build)
- **README or docs** (read these — they contain intent)

Output this as a brief "Codebase Snapshot" to the user before proceeding.

---

## STEP 2: MODULE IDENTIFICATION

Identify logical module boundaries. Modules are NOT just directories — they are cohesive units of functionality.

Look for:
- Workspace members (Cargo.toml, lerna.json, pnpm-workspace.yaml)
- Package declarations (go.mod, __init__.py, package.json)
- Service boundaries (Dockerfile per service, docker-compose services)
- Route/handler groups (route files, controller directories)
- Domain boundaries (directories that own a concept: auth, billing, users, orders)

For each module, note:
- Name
- Root path
- Estimated file count
- Key entry file
- Complexity tag (Simple / Moderate / Complex / Critical)
- Dependencies on other modules

---

## STEP 3: ARCHITECTURE RECONSTRUCTION

WITHOUT reading every file, infer the system architecture by examining:
- Entry points and how they wire things together
- Import/dependency graphs (search for import/use/require/include patterns)
- Database connections (search for DB driver usage, connection strings, migrations)
- External API calls (search for HTTP clients, SDK usage)
- Message queues / event systems (search for publish/subscribe patterns)
- Configuration structure

Determine:
- **System type:** Monolith / Microservices / Modular monolith / Library / CLI tool / Hybrid
- **Primary language(s) and frameworks**
- **Data flow:** How data enters, transforms, and exits the system
- **Control flow:** How requests are routed and processed
- **External dependencies:** Databases, APIs, queues, caches
- **Key abstractions:** The core types/interfaces that define the system's vocabulary

Produce a `mermaid` diagram block (NOT ASCII) showing the architecture. Do NOT add `click` directives to link to module pages yet — those files don't exist until Phase 2. Just show the architecture structure. The `click` directives will be added when modules are generated in Phase 2.

---

## STEP 4: KNOWLEDGE GRAPH

Build a relationship map:

```
Module → Module (depends on)
Service → Database (reads/writes)
API Endpoint → Handler → Business Logic → Storage
Config → Module (configures)
```

Express this as a structured list — NOT a visual diagram (that's the architecture diagram's job).

---

## STEP 5: TRACE IDENTIFICATION

Identify 3–5 key flows that would teach the most about the system:
- The "happy path" (most common user action)
- A CRUD operation end-to-end
- An auth/security flow
- A background/async process (if any)
- The most complex flow

For each flow, note the starting point (file:line) and list the modules it touches.

---

## STEP 6: WRITE INDEX FILES

Create the following files in `course/` (create the directory if needed):

### `course/00-index.json`

```json
{
  "generated": "YYYY-MM-DD",
  "repo": "<repo-name>",
  "system_type": "<inferred type>",
  "languages": ["<lang1>", "<lang2>"],
  "modules": [
    {
      "name": "<module>",
      "path": "<relative-path>",
      "complexity": "<Simple|Moderate|Complex|Critical>",
      "files": <count>,
      "depends_on": ["<other-module>"],
      "entry_file": "<relative-path-to-key-file>"
    }
  ],
  "flows": [
    {
      "name": "<flow-name>",
      "description": "<what it traces>",
      "modules": ["<module1>", "<module2>"],
      "start": "<file:line>"
    }
  ]
}
```

### `course/01-overview.md`

Level 1: Executive Overview. Write this for a technical leader who needs to understand the system in 5 minutes.

Include:
- What problem this system solves
- Key architectural decisions and WHY they were made
- Technology choices
- How the pieces fit together (reference the architecture diagram)
- Link to `02-architecture.md` for deeper understanding

### `course/02-architecture.md`

Level 2: Architecture Deep Dive. Write this for a developer joining the team.

Include:
- `mermaid` architecture diagram (NO `click` directives — module pages don't exist yet)
- `dep-graph` block showing module dependencies as a force-directed graph (set `"file": null` for all nodes since module pages don't exist yet)
- `complexity-heatmap` block showing codebase structure by size and complexity
- `arch-minimap` block for navigation context (use only `01-overview.md` and `02-architecture.md` as page targets — module pages will be added after Phase 2)
- Component descriptions (what each box does)
- Data flow walkthrough with real file references
- Control flow walkthrough with real file references
- External dependency map
- The knowledge graph from Step 4
- Multi-audience sections (Beginner/Intermediate/Advanced) per the reference templates

See the reference file for the JSON data format of each interactive block type.

---

## STEP 7: PRESENT THE PLAN

After writing the index files, present the generation plan to the user:

```
## Course Generation Plan

### Modules to generate:
- [ ] module-name (Complexity: X, Files: N)
- [ ] module-name (Complexity: X, Files: N)
...

### Flows to trace:
- [ ] flow-name (touches: module1, module2)
...

### Estimated course pages: N

To generate, run:
  /code-to-docs-generate all        — generate everything
  /code-to-docs-generate <module>   — generate one module
  /code-to-docs-generate --diff     — regenerate changed modules only
```

Then STOP. Do not generate module content in this phase.

---

## CRITICAL RULES

1. **REAL REFERENCES ONLY:** Every file path, function name, and line number you cite MUST be verified by actually reading the file. Never fabricate.

2. **NO SINGLE-PAGE OUTPUT:** You produce 3 files minimum (00-index.json, 01-overview.md, 02-architecture.md). Never a single dump.

3. **LIGHTWEIGHT SCANNING:** Do NOT read every file. Use directory listing, pattern matching, and targeted reads of key files only. You're building an index, not processing the full codebase.

4. **ARCHITECTURE FROM EVIDENCE:** Base all architectural claims on actual code evidence (imports, configs, entry points). Never guess system properties.

5. **STOP AFTER PLAN:** Phase 1 ends with a plan. Content generation happens in Phase 2 (`/code-to-docs-generate`).
