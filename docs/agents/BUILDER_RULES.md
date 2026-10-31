# Hullscrap: common rules for builder agents (read fully before starting)

You are a builder on **Hullscrap**, a top-down 2D spaceship game in **Godot 4.6.3 / GDScript**.
- The repo is at `/home/user/hullscrap` (GitHub `merttureli/hullscrap`, default branch `main`).
- Read `AGENTS.md` and `docs/PLAN.md` in the repo first. Their rules apply. In particular: **no `class_name`** (use `const X = preload("res://...")`), logic in `RefCounted` scripts with no nodes, content in `data/*.json`, tabs, short `##` doc comments.
- The lead made the design decisions in your brief. **Do not make other design calls.** If something truly isn't covered, pick the simplest option, write it under "Decisions" in your report, and keep going. Stop only if you're blocked.

## Setup: your own worktree, so parallel agents never collide
```
cd /home/user/hullscrap && git fetch -q origin main
git worktree add /home/user/hs/<topic> -b claude/<topic> origin/main
cd /home/user/hs/<topic>
G=/tmp/claude-0/-home-user-earth-sim/2fe481dc-7c04-5e24-b286-37a000ee4cff/scratchpad/godot/Godot_v4.6.3-stable_linux.x86_64
# if that path is gone: curl -sSL -o /tmp/godot.zip https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.x86_64.zip && unzip -o -q /tmp/godot.zip -d /tmp && G=/tmp/Godot_v4.6.3-stable_linux.x86_64
$G --headless --path . --import
```
- Work **only** inside your worktree.
- Touch **only** the files your brief lists. Other agents are editing other files at the same time.

## Checks (all must pass before you report done)
```
$G --headless --path . --import
$G --headless --path . --script res://tests/run_tests.gd          # all pass (also grep the output for SCRIPT ERROR)
$G --headless --path . --quit-after 120 2>&1 | grep -E "SCRIPT ERROR|Parse Error" && echo FAIL || echo OK
```
- Add tests in `tests/test_<area>.gd`, extending `res://tests/base_test.gd` and using `check()` / `eq()`. Look at `tests/test_ship_grid.gd` for the pattern.
- Godot creates `*.gd.uid` files for new scripts. Commit them.
- For UI work you can't see the screen. Drive the node in a throwaway headless script (call its methods and feed it `InputEvent`s) and print state. Delete the throwaway script before committing.

## Commit and push
- Small, clear commits. Each message ends with these two lines exactly:
```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013c7XcjREWKUsXeesNxoYEV
```
- `git push -u origin claude/<topic>`. If the network fails, retry up to 4 times with backoff (2, 4, 8, 16 s).
- **Do not open a PR, do not merge, and do not touch `main`.** The lead reviews and merges.
- Never force-push.

## Report (your final message, at most about 200 words)
Branch and last commit; files changed; the test summary line ("N passed, 0 failed") and the smoke result; what to try in-game (keys and steps); Decisions (anything you chose); open questions.

## Stop rule
When the lead sends **STOP**, finish the piece you're on, commit and push your branch, and report. Don't start anything new.

## Screenshots of the real window
Use `xvfb-run -a $G --path . --script <throwaway.gd>` (not `--headless`): load `res://scenes/main.tscn`, drive it with input events, wait some frames, then save `get_viewport().get_texture().get_image()` as a PNG. Delete the throwaway script before committing.
