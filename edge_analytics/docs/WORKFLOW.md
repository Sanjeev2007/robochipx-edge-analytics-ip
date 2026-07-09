# Team Git Workflow

Everyone works on their own **branch** and merges into `main` via a Pull Request.
`main` is always the working, integrated code — never push broken code to it directly.

## Branch naming
| Who / what | Branch |
|---|---|
| A build phase | `phase3-analytics`, `phase4-output`, … |
| Teammate B (synthesis) | `teammate-b-synth` |
| Teammate C (dashboard) | `teammate-c-dashboard` |
| Teammate D (docs/slides) | `teammate-d-docs` |

## The loop (every contributor)
```bash
git clone <repo-url>
cd Robochipx
git pull origin main            # always start from latest main
git checkout -b phase3-analytics # your branch
# ... do your work, compile/simulate ...
git add -A
git commit -m "Phase 3: analytics_engine + testbench"
git push -u origin phase3-analytics
# then open a Pull Request into main on GitHub
```

## Rules
1. **Branch off latest `main`** — `git pull origin main` before you start.
2. **One branch per phase / per person** — keeps work isolated, no collisions.
3. **Build against the frozen contract** (`docs/INTERFACES.md`) so pieces fit at merge.
4. **Simulate before you PR** — don't PR code that doesn't compile/run.
5. **RTL lead reviews + merges** PRs into `main` (checks the interface still holds).
6. **Keep `main` always-working** — the demo must be runnable from `main` at any time.
7. Update `docs/CHANGELOG.md` + `docs/memory.md` status in your branch when you finish.

## Why branches (not everyone on main)
With 4 people + per-phase agents all editing at once, working directly on `main` would
constantly collide. Branches let everyone work in parallel and integrate cleanly through
reviewed PRs — the same reason we froze the interface contract early.
