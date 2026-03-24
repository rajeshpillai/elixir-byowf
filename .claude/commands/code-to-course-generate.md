---
description: "Generate course content for specific modules or flows. Phase 2: use after /code-to-course."
argument-hint: "<module-name|all|--diff> [--level beginner|intermediate|advanced] [--flows]"
---

# Code-to-Course: Phase 2 — Content Generation

You are a senior software architect and educator. Your task is to generate detailed, interactive course content for specific modules of a codebase.

**Arguments:** $ARGUMENTS

---

## BEFORE YOU BEGIN

1. Read the shared reference file for templates and conventions:
   `.claude/commands/code-to-course-reference.md`

2. Read the course index to understand the codebase structure:
   `course/00-index.json`

3. If `course/00-index.json` does not exist, tell the user:
   > "No course index found. Run `/code-to-course` first to index the codebase and generate a plan."
   Then STOP.

---

## ARGUMENT PARSING

Parse `$ARGUMENTS` to determine what to generate:

| Argument | Action |
|----------|--------|
| `all` | Generate all modules sequentially, then all flows |
| `<module-name>` | Generate only that module (match against modules in 00-index.json) |
| `--diff` | Find changed files since last generation, regenerate affected modules only |
| `--flows` | Generate only the flow trace files (course/flows/*.md) |
| `--level <level>` | If specified, emphasize that audience level throughout |

If the argument doesn't match any module name or flag, list available modules from the index and ask the user to pick one.

---

## DIFF-AWARE MODE (--diff)

When `--diff` is specified:

1. Read `course/.last-generation-sha` to get the baseline commit
2. Get the list of changed files since that SHA
3. Map changed files to modules using `course/00-index.json`
4. Regenerate only affected modules
5. Add a "What Changed" banner to updated module files (see reference file)

If `.last-generation-sha` doesn't exist, tell the user and offer to regenerate all.

---

## MODULE GENERATION

For EACH module being generated, follow this process:

### A. Deep Read

Read the module's key files to understand:
- Public API / exported interface
- Internal structure
- Dependencies (imports from other modules)
- Error handling patterns
- Configuration

Do NOT read every file in a large module. Prioritize:
1. Entry point / main file
2. Public API surface
3. Core logic files
4. Test files (they reveal intent and edge cases)

### B. Generate Module File

Write `course/modules/NN-<module-name>.md` following the Module File Template in the reference file.

The module file MUST include ALL of the following sections:

#### 1. Purpose
What this module does and WHY it exists. Not what files it contains — what problem it solves.

#### 2. Key Files Table
Real file paths with brief descriptions. Every path MUST be verified to exist.

#### 3. Internal Architecture
Use a `mermaid` block (NOT ASCII) showing how components within this module relate. Show connections to other modules. Use `click` directives to make nodes navigable.

#### 4. How It Works — Multi-Audience
Use the three-level collapsible section pattern from the reference:
- **Big Picture:** Analogy-based, anyone can follow
- **Intermediate:** Implementation details with code references
- **Advanced:** Performance, concurrency, edge cases, tradeoffs

For key functions, use a `code-walkthrough` block to provide an interactive line-by-line explanation with syntax highlighting. See the reference file for the JSON format.

For beginner-friendly explanations of complex interactions, use a `chat` block to show components talking to each other in conversational style. See the reference file for the JSON format.

#### 5. Key Flows (Trace-Based)
Pick 1-3 real flows through this module. Use `flow-trace` blocks (NOT numbered lists) for animated step-by-step walkthroughs:

````
```flow-trace
{
  "title": "Flow Name",
  "steps": [
    {"component": "ComponentName", "action": "what it does", "file": "src/path/file.ext:LINE", "detail": "explanation"}
  ]
}
```
````

Every function name and line number MUST be verified by reading the actual file.

For cross-module flows, also use a `mermaid` sequence diagram showing the full interaction.

#### 6. Hot Paths
Identify performance-critical code paths:
- Loops over large data sets
- Database queries in hot paths
- Serialization/deserialization
- Concurrent/parallel sections
- Cache-sensitive operations

Mark with: `**[HOT PATH]**` tag and explain why it matters.

#### 7. Gotchas
Non-obvious behavior, footguns, implicit assumptions, known quirks. Reference specific code.

#### 8. Practice Section
Generate AT LEAST:
- 1 `drag-match` block (interactive concept-to-description matching exercise)
- 1 `spot-the-bug` block (interactive debugging challenge with clickable code)
- 1 Markdown quiz (fallback for non-HTML viewing)

All practice items MUST reference real code locations in the repo.
See the reference file for the JSON format of each interactive block type.

### C. Write Immediately

Write each module file to disk immediately after generating it. Do NOT buffer all modules in memory. This ensures partial progress is saved if the context window fills.

### D. Update Index

After writing a module file, update the module's entry in `course/00-index.json` with:
- `"last_generated": "YYYY-MM-DD"`
- `"course_file": "modules/NN-module-name.md"`

---

## FLOW GENERATION

For each flow identified in `course/00-index.json` (or when `--flows` is specified):

Write `course/flows/<flow-name>.md` containing:

### 1. Flow Overview
What this flow accomplishes from the user/system perspective.

### 2. End-to-End Trace
Use a `flow-trace` block for an animated step-by-step walkthrough crossing module boundaries. See the reference file for the JSON format.

### 3. Beginner-Friendly Explanation
Use a `chat` block to show the same flow as a conversation between system components. This makes complex interactions accessible.

### 4. Sequence Diagram
Use a `mermaid` block with `sequenceDiagram` syntax (NOT ASCII) showing the interaction between components.

### 5. State Transitions
What changes in the system during this flow (DB writes, cache updates, side effects).

### 6. Error Paths
What happens when things go wrong at each step.

### 7. Practice
At least 1 interactive exercise (`drag-match` or `spot-the-bug`) + 1 markdown quiz.

---

## AFTER ALL GENERATION

1. Write the current git HEAD SHA to `course/.last-generation-sha`
2. Update `course/00-index.json` with generation timestamps
3. **Copy theme assets** — Copy `templates/viewer.html` and `templates/theme.css` from the code-to-course repo into `course/assets/`. If the template files are not available locally, look for them at `.claude/commands/` or generate them following the Asset Generation specs in the reference file. These provide an interactive HTML viewer with:
   - Dark/light theme toggle (persisted in localStorage)
   - Sidebar navigation from `00-index.json`
   - Interactive rendering of `mermaid`, `dep-graph`, `flow-trace`, `chat`, `code-walkthrough`, `drag-match`, `spot-the-bug`, `complexity-heatmap`, and `arch-minimap` blocks
   - Scroll progress bar, SPA navigation, syntax highlighting
4. Add a tip at the top of `course/01-overview.md`:
   ```
   > **Tip:** Open `course/assets/viewer.html` in a browser for an interactive view with dark/light theme, navigable diagrams, and animated walkthroughs.
   ```
5. Present a summary to the user:

```
## Generation Complete

### Generated:
- [x] modules/01-module-name.md (Complex, 15 files)
- [x] modules/02-module-name.md (Simple, 4 files)
- [x] flows/login-flow.md (3 modules)
- [x] assets/theme.css + viewer.html (dark/light theme viewer)
...

### Course structure:
  course/
    00-index.json          ✓ updated
    01-overview.md         (from Phase 1)
    02-architecture.md     (from Phase 1)
    modules/
      01-auth.md           ✓ generated
      02-users.md          ✓ generated
    flows/
      login-flow.md        ✓ generated
    assets/
      theme.css            ✓ generated
      viewer.html          ✓ generated
    .last-generation-sha   ✓ updated

To browse: open course/assets/viewer.html in a browser
To regenerate after code changes: /code-to-course-generate --diff
```

---

## CRITICAL RULES

1. **REAL REFERENCES ONLY:** Every file path, function name, and line number MUST be verified by actually reading the source file. NEVER fabricate or guess.

2. **WRITE INCREMENTALLY:** Write each module file immediately after generating it. Never hold all content in memory.

3. **INDEX REQUIRED:** Never run without `course/00-index.json`. Redirect to Phase 1 if missing.

4. **EXPLAIN, DON'T DUMP:** Never paste large blocks of code without explanation. Show the relevant 3-10 lines and explain what they do and WHY.

5. **LEARNING-FIRST:** Explain using:
   - First principles (build up from basics)
   - Real-world analogies (make abstract concepts concrete)
   - Step-by-step execution (trace actual code paths)
   - Visual thinking (Mermaid diagrams, flow-trace, chat blocks — NEVER ASCII art)

6. **PRACTICE IS MANDATORY:** Every module file MUST have at least 2 interactive practice items. Practice items MUST reference real code.

7. **PRESERVE EXISTING:** When regenerating a single module, do not delete or modify other module files. Only touch the target module and the index.
