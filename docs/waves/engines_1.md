# Engine wave 1: the spec (lead, 2026-10-30)
This is CONTENT_PLAN section 4 A plus two families from B: **19 engines** (4 exist and get re-tuned, 15 are new).
- Art follows `docs/ART_STYLE.md` "The approved look" (tiers grow by adding parts).
- Data goes in a pack `data/packs/engines_1/`, except the 4 existing ids, which are re-tuned in core.

## Numbers
Base stats are **Standard-band values** (`data/balance.json`). The line multipliers in `data/lines.json` are applied by the game (Scrap thrust ×0.9, Neon ×1.3, and so on). Never pre-multiply.

| id | name | line | tier | thrust | power | hp | heat_per_s | outside | stats / abilities |
|---|---|---|---|---|---|---|---|---|---|
| engine_mk1 | Concord Thruster Mk1 | standard | 1 | 10 | −2 | 6 | 3 | 4×2 | fuel_mult 1.0 |
| engine_mk2 | Concord Thruster Mk2 | standard | 2 | 18 | −3 | 8 | 4 | 4×2 | fuel_mult 1.0 |
| engine_mk3 | Concord Thruster Mk3 | standard | 3 | 26 | −4 | 10 | 5 | 4×2 | fuel_mult 1.1 |
| engine_mk4 | Concord Thruster Mk4 | standard | 4 | 36 | −5 | 12 | 6 | 4×3 | fuel_mult 1.2 |
| engine_mk5 | Concord Thruster Mk5 | standard | 5 | 48 | −6 | 14 | 7 | 4×3 | fuel_mult 1.3 |
| engine_scrap_mk1 | Kickjet | scrap | 1 | 10 | −2 | 6 | 3 | 4×2 | Sputter Boost ×1.25 (as now) |
| engine_scrap_mk2 | Kickjet Deluxe | scrap | 2 | 18 | −3 | 8 | 4 | 4×2 | Sputter Boost ×1.30 |
| engine_scrap_mk3 | Double Kick | scrap | 3 | 26 | −4 | 10 | 5 | 4×2 | Sputter Boost ×1.35, fuel_mult 1.1 |
| engine_scrap_mk4 | Thunderknuckle | scrap | 4 | 36 | −5 | 12 | 6 | 4×3 | Sputter Boost ×1.40, fuel_mult 1.2 |
| engine_neon_mk1 | Ion Drive: Glimmer | neon | 1 | 10 | −2 | 6 | 3 | 4×2 | (re-tuned from 16/−3) |
| engine_neon_mk2 | Ion Drive: Halo | neon | 2 | 18 | −3 | 8 | 4 | 4×2 | — |
| engine_neon_mk3 | Ion Drive: Corona | neon | 3 | 26 | −4 | 10 | 5 | 4×2 | Ion Surge (active, engine key): thrust ×1.3 for 5 s, cooldown 20 s, side effect heat 15/s; fuel_mult 1.1 |
| engine_neon_mk4 | Ion Drive: Zenith | neon | 4 | 36 | −5 | 12 | 6 | 4×3 | Ion Surge ×1.35; fuel_mult 1.2 |
| strafe_jets_mk1 | Strafe Jets Mk1 | standard | 1 | 6 | −1 | 4 | 2 | **2×2** (inside 2×2) | `"quirk": "small side jets, mount on side walls for A/D strafe"` |
| strafe_jets_mk2 | Strafe Jets Mk2 | standard | 2 | 10 | −2 | 5 | 2 | 2×2 (inside 2×2) | same quirk |
| strafe_jets_mk3 | Strafe Jets Mk3 | standard | 3 | 14 | −2 | 6 | 3 | 2×2 (inside 2×2) | same quirk |
| longburn_mk1 | Long-Burn Drive Mk1 | standard | 1 | 6 | −2 | 6 | 2 | 4×2 | fuel_mult 0.5, `"quirk": "an explorer's engine: half the fuel, 60% thrust"` |
| longburn_mk2 | Long-Burn Drive Mk2 | standard | 2 | 11 | −3 | 8 | 3 | 4×2 | fuel_mult 0.5, same quirk |
| longburn_mk3 | Long-Burn Drive Mk3 | standard | 3 | 16 | −4 | 10 | 4 | 4×2 | fuel_mult 0.45, same quirk |

- Every engine: `family: engine`, inside `size` [4,2] (strafe jets [2,2]), `mount.outside` as in the table, `outside_hp` = 75% of hp rounded, `priority: 4`, `heat_limit: 100`, `cooling: 3`.
- **`fuel_mult`** (stats): a jump costs `1 × the thrust-weighted mean fuel_mult of the powered engines`. The campaign keeps the fraction, so 0.5 means every other jump is free. It is implemented with the Drift campaign after that merges.
- The `engine_mk2` and `engine_neon_mk1` waivers in `data/balance.json` are **removed** (both are now in band).

## Recipes (`fab_level` by tier: 1, 1, 2, 2, 3; Neon +1, max 3)
- **Standard**:
  - Mk1: scrap 20, copper 10 (as now);
  - Mk2: scrap 30, copper 16, titanium 6;
  - Mk3: scrap 40, copper 24, titanium 12, silicon 4;
  - Mk4: scrap 55, copper 32, titanium 20, silicon 8, **military_circuit 1** (a key material, CONTENT section 11);
  - Mk5: scrap 75, copper 40, titanium 30, silicon 12, crystal 2, **military_circuit 2, gate_alloy 1**.
- **Scrap** (cheap): Mk1 scrap 16 (as now); Mk2 scrap 26, copper 6; Mk3 scrap 36, copper 12, titanium 4; Mk4 scrap 50, copper 18, titanium 10, military_circuit 1.
- **Neon** (dear): the Standard recipe of the same tier, plus crystal 2 × tier and silicon 4 × tier. Mk4 adds void_crystal 1.
- The key materials (`military_circuit`, `gate_alloy`, `void_crystal`) are added to `data/materials.json` by this wave if they're missing (kind material, with a one-line blurb).
- **Strafe Jets**: half the Standard recipe of the same tier, rounded up. **Long-Burn**: the Standard recipe +50% copper.
- Known at the start: no change. The new ones are blueprints found or bought: Meridian stocks the Concord and Strafe parts, Gantry Rusthold the Kickjets, the Prism the Ion Drives, and the Long-Burn is sold at both Meridian and the Prism.

## Art (one agent, generator-based like the approved lines art)
- A core (inside half) and an `_out` (nozzles, outward = up) for every new id, each with a `_glow`. Frames: core 64×36 with offset [0,−4], or 32×36 for strafe jets; `_out` 64×32, 64×48 for 4×3, 32×32 for strafe jets.
- Anims: core `on` (pulse), `off`, `damaged`, `disabled`; out `on` (exhaust flicker), `off`, `damaged`, `disabled` (never shattered).
- **Tier growth inside each line**:
  - Mk1 is the existing art.
  - Mk2 adds a second accent: a coolant ring, a second nozzle collar.
  - Mk3 adds machinery: an extra pump, cabling, a third nozzle or a wider bell.
  - Mk4 and Mk5 get the bigger 4×3 nozzle housing: a heavy bell, heat-sink fins, a reinforced collar. Mk5 adds a Concord gold registry band.
  - Every tier of a line must read as one family.
- **Scrap** gets more patches, tape and mismatched nozzles per tier. Thunderknuckle is four mismatched nozzles welded into a fist.
- **Neon**: Glimmer → Halo (a ring of light around the bell) → Corona (crystal fins) → Zenith (a floating crystal halo in the glow layer).
- **Strafe Jets**: compact paired jets angled slightly outward, with a small core and a gyro.
- **Long-Burn**: a long, narrow, efficient-looking bell with a big pale-blue exhaust in the glow, and a fuel-efficiency gauge on the core.
- **Exhaust colour** is the family orange for Standard and Scrap, cyan-white for Neon, and pale blue for Long-Burn.
