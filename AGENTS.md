# Rules for coding agents (Claude)

**Hullscrap** is a top-down 2D spaceship game built in **Godot 4.6.3 with GDScript**. The plan, design pillars and milestones are in `docs/PLAN.md`. Read it before starting work.

## Layout
- `scripts/ship/`, `scripts/crew/`, `scripts/sim/`: **game logic as plain `RefCounted` scripts.** No nodes and no drawing here, so it can be tested headless.
- `scripts/build/`, `scripts/space/`, `scripts/ui/`: nodes that draw and take input. Keep them thin; they call into the logic scripts.
- `scenes/`: `.tscn` files (plain text, editable by hand).
- `data/*.json`: **all content** (tiles, components, crew traits, weapons, events). Adding content should mean editing data, not code.
- `tests/test_*.gd`: tests (see Checks). `tests/base_test.gd` is the base class.
- `assets/`: art and audio. Every file's source and license goes in `ASSETS.md`.

## Conventions
- **No `class_name`.** Load scripts with `const X = preload("res://...")`. This keeps headless runs working on a fresh clone without an editor import.
- GDScript style: tabs, typed variables where it helps, short `##` doc comments on scripts and public functions, no dead code.
- **Gameplay randomness** goes through a seeded `RandomNumberGenerator` owned by the simulation, so runs can be replayed. Visual-only randomness (stars, particles) may use its own fixed seed.
- **No live AI or network calls in the game.** Crew and enemy behaviour are rules and utility scores.
- Saves are versioned JSON (`VERSION` in the owning script). Bump the version and keep loading old saves, or refuse them with a clear message.
- Placeholder art is flat shapes drawn in code until real art lands (milestone 8). Don't spend time polishing placeholders.

## Checks (all must pass before a PR; CI runs the same)
```
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd    # all tests pass
godot --headless --path . --quit-after 120                     # main scene runs with no SCRIPT ERROR
```
Add or extend tests for every logic change and every bug fix.

## Who does what
- **Lead (Opus)** owns decisions:
  - design, architecture, new ideas that need iteration;
  - reviewing results and merging.
  - It writes a precise brief for each piece of work: goal, files, rules, test cases, done-criteria.
- **Builders (Sonnet agents)** implement those briefs: clear, well-defined changes and new content.
  - They don't make design calls. If a brief is ambiguous, they stop and report the question instead of guessing.
- Keep reports short. Run every check before reporting done.

## Branches and PRs
- `main` must always be playable.
- Work on `claude/<topic>`, then open a PR into `main`. CI must be green.
- Merge with merge commits. Never force-push or rewrite history on `main`.
- One milestone step per PR. The PR description says: what changed, how to try it in the game (keys and steps), what was tested, and open questions.
- Never commit secrets, API keys or tokens. Commit only art and audio we're allowed to use, recorded in `ASSETS.md`.
