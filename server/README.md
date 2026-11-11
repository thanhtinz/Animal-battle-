# Empire Age — P4 Relay Server

A small Go server (standard library only — the WebSocket layer is a
minimal hand-rolled RFC 6455 implementation in `ws.go`, so the module
has **zero dependencies**) that hosts Empire Age multiplayer rooms
for the Godot client (`../godot/scripts/net.gd`).

## Run

```sh
go build -o empire-relay .
./empire-relay            # listens on :8765, accounts in ./accounts.json
./empire-relay -addr 127.0.0.1:9000 -store /var/lib/empire/accounts.json
# with ranked-referee orchestration (see the ranked section below):
./empire-relay -referee-godot /path/to/godot -referee-project ../godot
```

Flags: `-addr`, `-store`, and for ranked: `-referee-godot`
(headless Godot binary used to spawn referees; empty = orchestration
off), `-referee-project` (project path handed to referees,
default `../godot`), `-referee-url` (ws URL referees connect back
to; default derived from `-addr`), `-referee-extra-args`
(space-separated, appended verbatim), `-referee-timeout` (hard cap
per ranked match, default 45 min), `-season-days` (season length
for the rank ladder, default 90 — see the ladder section below).

Endpoints: `/` (status text), `/healthz`, `/ws` (WebSocket upgrade).

Tests: `go test ./...` — room lifecycle (create / join / full /
ready / start gating), team-assignment tables for 2 / 3 / 4 players,
tick-stamped command relay, checksum desync detection, disconnect
handling, chat relay (room/team scopes, truncation, rate limit),
accounts (register/login/wrong-password/duplicate/validation,
token lifecycle + expiry, store persistence across a restart,
leaderboard ordering, host-reported result recording), resync
(source picking, majority vs host hash, snapshot relay, retry/fail
clock, source disconnect), plus a real-socket end-to-end test.
P4 stage 3 adds: Elo/MMR math (equal/underdog/high-K/floor),
matchmaking queue windows on a fake clock (expansion, cap, FIFO),
referee token gating, referee-only ranked results, ranked resync
sourced from the referee, and referee spawn-arg construction.
P4 stage 4 adds: the ladder itself (star gain/loss, streak bonus,
promotion at cap, demotion, the Tân Binh III floor, Hầu Tước
5-star divisions, Công Tước star mode), the Hoàng Đế top-50
computation, and seasons (the full reset table, MMR soft reset,
history/peak recording, idempotence) in `rank_test.go`.

End-to-end verification of the whole stack (this server + two
headless Godot clients): `../godot/tests/mp_smoke.sh`; the ranked
stack (server + spawned referee process + two queued account
clients + leaderboard probe): `../godot/tests/ranked_smoke.sh`.

## What it does

- **Rooms** — `create` returns a 5-character room code; `join` by
  code. Hard cap **4 players per room** (the game is designed for
  2–4: 1v1, 2v2, FFA 3–4 — there are no 6/8-player modes). Slots are
  assigned lowest-first; teams derive from the player count:
  2 players → teams [0, 1] (1v1), 3 → [0, 1, 2] (FFA),
  4 → [0, 0, 1, 1] (2v2 by slot pairs).
- **Lobby** — guest display names, per-player ready flags; only the
  host can start, and only with ≥ 2 players all ready. The host picks
  the match config (biome + layout); the server generates the match
  seed.
- **Match relay (lockstep)** — on start the server broadcasts
  `match_start {seed, biome, layout, players}` and runs a **10
  ticks/second** clock. Clients send game commands; the server
  relays each command to *all* clients (sender included) stamped
  with the tick at which it must be applied (**receipt tick + 2**
  input delay). Every client applies the same commands at the same
  tick in the same order — that is what keeps the simulations in
  sync.
- **Desync detection + resync** — every 30 ticks each client
  reports a state checksum (hash of entity positions/HP, wallets,
  ages). If reports for the same tick diverge, the server broadcasts
  one `desync` notice per diverging tick **and opens a resync
  cycle** (see below).
- **Chat** — relayed per room, never part of lockstep state:
  scopes `lobby` / `match` go to the whole room, `team` only to
  same-team slots (the server computes teams from its own table).
  Server truncates to 200 runes and silently drops messages beyond
  5 per 2 s per player.
- **Accounts (optional)** — register/login with PBKDF2-hashed
  passwords and token sessions; guests keep working exactly as
  before. Account players are badged in the room player list, their
  lobby name is locked to the account name, match results bank
  wins/losses, and a top-20 leaderboard is served on request.
- **Disconnects** — in the lobby the slot is freed (host passes to
  the lowest remaining slot; an empty room is deleted). Mid-match
  the server broadcasts `player_left {slot}`: the client behaviour
  is that the dropped player's units/buildings **freeze in place
  (inert — they stop acting, gathering, training and firing)** and
  the slot counts as **eliminated** for the win check. The room
  closes when every player is gone.
- **Ranked matchmaking + dedicated referees (P4 stage 3)** —
  logged-in players queue for **1v1**; the pairing loop matches
  FIFO inside an MMR window that grows with wait time. A pair
  becomes a *ranked room* owned by a **dedicated referee process**
  (the same Godot project running headless in `--referee` mode)
  that the server spawns per match: the referee runs the full
  authoritative sim, its checksums are canonical (clients that
  diverge resync *from the referee*), and only the referee's
  `match_result` banks the outcome — wins/losses **and Elo MMR
  updates**. Custom rooms behave exactly as before. Details in
  the ranked section below.

## Protocol (JSON over WebSocket)

Client → server: `create {name, biome, layout}`, `join {code, name}`,
`config {biome, layout}` (host), `ready {ready}`, `start`,
`cmd {cmd}`, `checksum {tick, hash}`, `leave`,
`chat {scope, text}` (scope: `lobby` | `match` | `team`),
`register {user, pass}`, `login {user, pass}` or `login {token}`,
`logout`, `leaderboard {mode}` (`wl` default | `ranked`),
`match_result {winner_team}` (custom rooms, host only),
`snapshot {tick, state}` (resync source only),
`queue_join {mode:"1v1"}` / `queue_leave` (ranked matchmaking),
`referee_join {code, token}` (referee processes only),
`match_result {winner_team, reason}` from a referee connection
(ranked rooms — the only ranked result channel).

Server → client: `created` / `joined {code, slot}`,
`room {code, host, in_match, biome, layout, ranked, players:[{slot, name,
ready, connected, team, account}]}`, `match_start {seed, biome, layout,
players}`, `tick {tick}`, `cmd {from, tick, cmd}`,
`player_left {slot}`, `desync {tick}`, `error {msg}`,
`chat {scope, from, name, text}`,
`auth_ok {token, profile:{user, wins, losses, matches, mmr}}`,
`auth_error {msg}`, `auth_out`,
`leaderboard {mode, rows:[{user, wins, losses, matches, mmr}]}`,
`snapshot_request {tick}` (to the chosen source),
`resync {tick, source}` (to diverged clients; `source` is -1 when
the room's referee is the source),
`resync_notice {slots}` (to everyone else),
`snapshot {tick, state}` (relayed to diverged clients only),
`resync_failed {tick}`,
`queue_joined {mode, mmr}`, `queue_left`,
`match_found {code, slot, ranked, biome, layout, opponent:{user, mmr}}`,
`referee_ok {code}`.

## Accounts & the store

- Passwords are hashed with **PBKDF2-HMAC-SHA256** (implemented
  from `crypto/hmac` + `crypto/sha256` — stdlib only), 120 000
  iterations, per-user 16-byte random salt. Plaintext passwords are
  never stored or logged.
- Session tokens are 32 random bytes (hex); only their SHA-256
  hash is stored. Tokens expire after 30 days; `logout` kills only
  the current token.
- Login errors are deliberately generic ("Sai tên đăng nhập hoặc
  mật khẩu") for both unknown users and wrong passwords — no
  user-existence leak.
- Persistence goes through a small `Store` interface
  (`accounts.go`); the shipped implementation is file-backed JSON
  (`-store` flag, default `accounts.json`), written atomically via
  temp file + rename, flushed on every mutation. **PostgreSQL is
  the Master-document endgame**: it needs an external driver (this
  module stays dependency-free), and swapping it in later means
  writing one more `Store` implementation — no protocol or hub
  changes.
- **Match-result trust model (custom rooms)**: for custom rooms
  the server cannot simulate the match, so when a match ends the
  **host client** reports `{t:"match_result", winner_team}` and
  the server trusts it, banking a win for account players on the
  winning team and a loss for the others (once per room; guests
  are skipped). A modified host client could lie about *custom*
  results — **ranked rooms close this hole**: their results are
  accepted only from the room's referee (next section), and a
  player-sent `match_result` for a ranked room is ignored.

## Ranked: matchmaking, MMR & the dedicated referee (P4 stage 3)

**Queue & pairing** (`matchmaking.go`). Ranked requires an
account — guests get `login required for ranked play`. This stage
ships **ranked 1v1 only** (`queue_join {mode:"1v1"}`; other modes
are rejected). A pairing loop (250 ms) always considers the
**oldest** queued player first (strict FIFO) and pairs them with
the earliest queued opponent whose MMR is inside a window that
grows with wait time: **±100 at join, +50 every 10 s, capped at
±600** (either player's window may authorise the pair — the longer
waiter's governs).

**The ranked room.** On pairing the server creates a room flagged
`ranked`, seats both accounts, picks biome/layout from a fixed
rotation — **grassland → desert → snow, always the plains
layout**, cycling per pairing — and sends both clients
`match_found`. Ranked rooms have **no host, no ready, no start
button**: once the referee is attached and both players are
connected, the server runs a **3-2-1 countdown as chat system
messages** (from "Hệ thống") and starts the match itself.

**The referee** (`referee.go`, `hub.go`). One dedicated process
per ranked match: the *same Godot project* run headless
(`godot --headless --fixed-fps 30 --path <project> -- --referee
--referee-room=CODE --referee-token=TOK --referee-url=URL`). The
server generates a one-time token per room, stores only its
**SHA-256 hash**, and passes the raw token solely on the spawned
command line; `referee_join` compares hashes in constant time — a
wrong token (or any referee claim on a custom room) is rejected,
and a room accepts exactly one live referee. The referee is a room
participant, not a player: every broadcast (ticks, commands,
results traffic) reaches it, so it consumes the **same
tick-stamped command stream** as the clients and applies commands
at the same exec ticks through the same `_mp_apply_*` validators
(illegal commands are dropped and counted in its log). It runs the
full simulation with no local player.

- **Canonical checksums**: in a ranked room with a live referee,
  the referee's per-30-tick checksum (keyed at slot **-1**) is the
  reference. Any connected player whose hash differs is diverged
  and enters a resync cycle **sourced from the referee** — the
  referee serves the same `"v":1` snapshot format, so diverged
  clients rebuild to the authoritative state. If the referee dies
  mid-match the room degrades to the stage-2 player-majority
  resync, and an open referee-sourced cycle fails cleanly.
- **Results**: at match end the referee sends
  `match_result {winner_team, reason}` (`reason` is `elimination`
  or `disconnect` — a ranked disconnect gives the dropped slot a
  **30 s grace** in the referee's sim before it is eliminated).
  The server banks the result **only** from the connection that
  authenticated as that room's referee, exactly once per room.
- **Lifecycle**: the referee's stdout/stderr fold into the server
  log prefixed `referee[CODE]:`. Processes are reaped when their
  room closes, exit on their own shortly after reporting, and are
  killed at `-referee-timeout`.

**MMR** (`accounts.go`). Elo on the account profile: start
**1000** (accounts with no stored rating play as 1000), **K=32**,
**K=16** at/above 2000 (each player's own K), **floor 100**.
Expected score `1/(1+10^((opp−me)/400))`, delta `round(K·(score−
expected))`. A referee report updates **both** accounts (W/L,
matches, MMR) as one serialised store operation. The leaderboard
comes in two labelled boards over the same endpoint:
`leaderboard {mode:"ranked"}` sorts by MMR (then wins, then name);
the default board keeps the stage-2 wins/winrate order. Both rows
carry `mmr`, and `auth_ok` profiles include `mmr` too. (Stage 4
re-sorts the ranked board by ladder position — see the ladder
section below.)

Verified by `ranked_test.go` (unit level) and end-to-end by
`../godot/tests/ranked_smoke.sh`: two fresh accounts queue, pair,
play against a real spawned referee; the referee's scripted TC
kill at tick 120 diverges both clients, both resync from the
referee, the referee reports, and both MMRs move by the exact Elo
delta (1000 vs 1000 → **1016 / 984**), confirmed again through a
leaderboard probe client.

## Seasonal rank ladder (P4 stage 4)

On top of MMR sits the visible ladder (`rank.go`) — the Liên Quân
(Arena of Valor) structure with Empire Age medieval titles (the
metal names were only the skeleton; Tín ordered display names
that fit the game). MMR stays the hidden matchmaking number; the
ladder is what players see and climb, season by season. Both
evolve from the same referee-reported results, independently.

**Tiers, low → high** (internal slug → display name):

| slug | display | divisions | stars/division |
|---|---|---|---|
| `tan_binh` | Tân Binh | III → II → I | 3 |
| `chien_binh` | Chiến Binh | III → II → I | 3 |
| `ky_si` | Kỵ Sĩ | III → II → I | 3 |
| `nam_tuoc` | Nam Tước | III → II → I | 3 |
| `ba_tuoc` | Bá Tước | III → II → I | 3 |
| `hau_tuoc` | Hầu Tước | III → II → I | 5 |
| `cong_tuoc` | Công Tước | — (star count only) | unbounded |
| `hoang_de` | Hoàng Đế | computed status | — |

**Hoàng Đế is not a stored tier**: it is computed over the whole
account base — the top **50 Công Tước** accounts by stars (then
MMR, then name) hold the status; it shows on the leaderboard and
in profiles (`emperor: true`).

**Star math** (per ranked result, applied by
`RecordRankedResultFull` together with W/L + Elo in ONE serialised
store operation):

- **Win: +1 star.** Winning while the current win streak is ≥ 3
  grants **+1 bonus star** (at most one bonus per match).
- **Daily bonus (13i): +1 star for the first ranked WIN of the
  day.** The winner's first victory on a given server-local
  calendar date earns one extra star, stacked on top of the
  normal (and any streak) star — a first win that is also a
  streak win banks +3. It is granted inside the same atomic
  `RecordRankedResult` operation (never separately, never
  twice), can itself trigger a promotion, and a loss never
  claims the day. The account stores the claim date
  (`daily_bonus_day`, YYYY-MM-DD); profiles report it as
  `daily_bonus_claimed` for the home lobby's daily line.
  **Day boundary = the server host's local date** — run the
  server in the timezone whose midnight should reset the
  bonus; there is no separate config knob.
- Gaining a star in a **full** division converts it into a
  **promotion**: up one division (or tier), landing with **1 star**
  in the new division.
- **Loss: −1 star**; losing at 0 stars **demotes** one division
  (or tier), landing at **cap − 1 stars** there. Hard floor: **Tân
  Binh III at 0 stars cannot drop** — the loss costs nothing.
- New accounts start at **Tân Binh III, 0 stars**. Each account
  also tracks its **season peak** (highest tier/division reached,
  updated on every promotion).
- There are **no protection cards in v1** (a future addition).

**Seasons.** Length is `-season-days` (default **90**). Season 1
starts at the store's first boot — the epoch is kept in the store
meta (`season_epoch`) — and season ids increment automatically.
On **any account touch** (login, token auth, profile lookup,
queue join, either leaderboard, result banking), an account whose
stored season is behind the current one first archives the
finished season into its history `{season, final tier/division/
stars, peak tier/division}`, then takes the **soft reset**:

| final position | next season starts at |
|---|---|
| Hoàng Đế / Công Tước | Bá Tước III |
| Hầu Tước | Nam Tước II |
| Bá Tước | Nam Tước III |
| Nam Tước | Kỵ Sĩ II |
| Kỵ Sĩ | Kỵ Sĩ III |
| Chiến Binh | Chiến Binh III |
| Tân Binh | Tân Binh III |

…with 0 stars, streak cleared, peak restarted at the reset
position, and **MMR soft-reset** as `mmr = 1000 + (mmr − 1000)/2`
(floored at 100). The reset is **idempotent** — touching an
already-current account changes nothing, and an account that
sleeps through several seasons archives exactly one record (for
its last played season). Pre-ladder accounts (stored season 0)
initialise in place at Tân Binh III with no reset and no history.

**Payload additions** (display names travel with the data;
internal keys stay English slugs):

- `auth_ok.profile.rank` and `queue_joined.rank`: a `RankView`
  `{tier, tier_slug, tier_name, division, division_name, stars,
  star_cap, streak, season, emperor, rank_text, short_text,
  peak_text, prev_season, prev_season_text}` — e.g.
  `rank_text: "Kỵ Sĩ II · 2 sao"`, `peak_text: "Bá Tước II"`,
  `prev_season_text: "Hầu Tước I"`.
- `match_found.opponent.rank_text`: the opponent's ladder text.
- `leaderboard` rows gain `rank_tier`, `rank_text`, `rank_short`,
  `rank_stars`, `rank_star_cap`, `emperor`. The **Xếp hạng board
  now sorts by ladder position** (tier → division → stars), then
  MMR, then name (stage 3 sorted by MMR alone).
- **`rank_result`** (server → each player, right after banking):
  `{won, mmr_before, mmr_after, star_delta, bonus, daily_bonus,
  promoted, demoted, before: RankView, after: RankView}` — each
  player gets only their own movement; the Godot end panel
  renders it ("+1 sao", "+2 sao (chuỗi thắng)", "+2 sao (thưởng
  ngày)", "Lên hạng Kỵ Sĩ I!", …). Match-history records carry
  the same composition as `star_bonus` / `daily_bonus` flags so
  the history panel labels old deltas truthfully.

**Profile screen fields (13l).** The profile payload also
carries everything the home profile screen renders:

- `id`: the account's immutable numeric id — assigned
  sequentially at registration; stores that predate 13l are
  backfilled at boot in registration order (`Created`, then
  username), continuing after the highest existing id (the
  sequence lives in the store meta as `account_id_seq`).
- `level`, `xp`, `xp_into_level`, `xp_for_next`: XP is
  **derived**, never stored — `xp = 10 × matches + 20 × wins`
  over **server-recorded matches only** (ranked + host-reported
  customs; offline single-player is never recorded, so level
  counts online play). Level L starts at cumulative
  `100·L·(L−1)/2` XP (Lv1 at 0, Lv2 at 100, Lv3 at 300, Lv4 at
  600…); `xp_for_next` is the span of the current level
  (`100 × level`).
- `credit` ("Uy tín"): reputation, stored on the account,
  starts at **100**; **+1 per completed ranked match** (both
  sides) and **−5 more for a ranked disconnect loss** (the
  referee's result reason), clamped to **0–100** — a ruined
  score recovers one point per completed ranked match.
- `season_stars`: gross stars **earned** this season (only
  positive deltas count; losses never subtract), reset at
  rollover and archived into the season record's
  `total_stars`.
- `prev_rank` (a `RankView` of the last finished season's
  final position, or absent), `prev_season`,
  `prev_season_stars`: the "Hạng mùa trước" card. Season
  records also keep an `emperor` flag so the card's emblem
  matches the finish.

Verified by `profile_test.go` (id sequence + backfill order,
level edges at 0/99/100/240/300/600/1000 XP, credit
floor/cap/recovery and the disconnect penalty, season-star
archiving into the previous-season card).

Verified by `rank_test.go` (ladder math, reset table row by row,
emperor cutoff, season skips, idempotence, and the daily bonus:
first win of the day grants, second doesn't, a loss doesn't
claim, the next day grants again, streak stacking, promotion
by the daily star) and by `../godot/tests/ranked_smoke.sh`,
which also asserts the floored loser's 0-delta, both
`rank_result` pushes and the board's ladder text — its scripted
winner's star expectations (+2, "Tân Binh III · 2 sao") include
the daily bonus, since the scripted win is his first of the
day.

## Resync (desync recovery)

On checksum divergence at tick T the server picks the **majority
hash** (held by more than half of the reporting clients; on a tie
the **host's hash wins**), chooses the lowest connected slot
holding it as snapshot source, and runs one cycle at a time:

1. source ← `snapshot_request {tick:T}`; diverged clients ←
   `resync {tick:T, source}` (they freeze and show a
   "Đang đồng bộ lại…" overlay; input locks); everyone else ←
   `resync_notice {slots}`.
2. The source serializes its full sim state **at a tick boundary**
   (after that tick's commands were applied) as a versioned
   payload (`"v":1`): every entity by `net_id` — units with
   position/HP/carry/task essentials, buildings with
   type/cells/complete/HP/train queue, ships + cargo, fields,
   resource-node and fish-spot amounts, beast state incl. wander
   RNG, per-slot wallets/ages/rally/elimination flags.
3. The server relays `snapshot` to the diverged clients **only**;
   they rebuild the sim at that boundary, re-apply any logged
   commands that executed after it, and resume lockstep.
4. If the source never answers, the request is retried once after
   100 ticks and the cycle fails with `resync_failed` after 200
   ticks (also if the source disconnects mid-cycle).

Restore fidelity: a unit mid-task is re-ordered onto its task
target (gather node / field / build site / attack target /
garrison); a unit mid-path restarts its path from its snapshot
position. Projectiles in flight, decorative animals, VFX and fog
are not serialized (no sim effect; fog recomputes from positions).
Verified end-to-end by `../godot/tests/mp_smoke.sh` phase 2: a
forced +1px divergence at tick 60 raises DESYNC, the host's
snapshot rebuilds the diverged client, checksums agree again at
the next report tick, and the match completes with no further
desync.

## Home Lobby support: ping, friends, mail, history, leaderboard v2 (13g)

- **Ping**: `{t:"ping", ts}` is answered with `{t:"pong", ts}`
  (echo); the client measures round-trip latency from it.
- **Presence**: the hub refcounts live sessions per account;
  `IsOnline(user)` feeds the friends list's online flags. When
  an account's LAST live session ends, the hub stamps the
  account's `last_online` (13m) for "gần đây … trước" rows.
- **Friends** (on the account record, cap 50): `{t:"friends"}`
  lists `[{user, rank_text, rank_tier, emperor, online, level,
  avatar_id, close, last_online}]` (level/avatar/close/
  last-seen added in 13m); `{t:"friend_add", user}` /
  `{t:"friend_remove", user}` mutate with clear Vietnamese
  error payloads (`friend_error`: self-add, unknown account,
  duplicate, absent, not logged in). `{t:"friend_close", user,
  close}` toggles the per-owner "bạn thân" (close friend) flag
  — stored on the flagger's record only, drives the home
  rail's portraits; removing a friend clears the flag.
- **Mail**: system letters stored per account (cap 50, newest
  kept). Generated on registration (welcome), on every promotion
  inside `RecordRankedResultFull/Meta`, and when a season reset
  is applied (old rank -> new rank summary). `{t:"mail"}` lists
  letters + unread count; `{t:"mail_read", id}` marks one letter
  (id 0 = all). The auth/profile payload carries `unread_mail`
  for the home screen's badge.
- **Match history**: at ranked-result time the server banks a
  `MatchRecord` per player (cap 20): opponent, won, rank
  before/after (short text), star delta (with `star_bonus` /
  `daily_bonus` composition flags), MMR before/after,
  timestamp, plus the referee-reported **duration in ticks**
  (the referee's `match_result` gained a `ticks` field) and the
  room's biome/layout — and the match's replay id (see below).
  `{t:"history"}` returns the caller's records.
- **Leaderboard v2**: `{t:"leaderboard", mode}` with modes
  `ranked` (seasonal ladder), `friends` (ladder filtered to the
  caller's friends + self; guests get an error), and `wl` (the
  wins/losses board). The payload is `{rows (top 20), me}` where
  `me = {pos, row}` gives the caller's position in the FULL
  ordering of that mode even when outside the top 20.

## Replays (13h)

Every relayed match (ranked and custom) is recorded: a header
`{v, game_version, seed, config (biome/layout/players with
slots/teams/names), started_at, winner_team, reason, final_tick,
duration_ticks}` plus every relayed command `{from, tick, cmd}`
in relay order. Recording starts when the match starts; the
replay is sealed when the result is recorded.

- **Storage**: behind the `ReplayStore` interface; the shipped
  implementation is a JSON file at `<store>.replays.json`
  (atomic temp+rename flush). **Global cap: newest 200 replays**,
  LRU-evicted on insert (per-account history windows reference
  ids inside that cap).
- **Linking**: ranked history records for both players carry the
  `replay_id`; custom-room participants receive
  `{t:"custom_replay", replay_id, room}` at result time so their
  client-side local history can reference it.
- **Access** `{t:"replay", id}` -> `{t:"replay_data", replay}` or
  `{t:"replay_error", msg}`: ranked replays may be fetched by any
  logged-in account; custom-room replays only by their
  participants (matched by account). **Guests cannot fetch
  custom-room replays** ("đăng nhập để xem lại") — guests have no
  durable identity to match participation against; that is a
  deliberate, documented choice.
- Current `game_version` is `"v13"`; clients warn before playing
  a replay recorded under a different version.

## Honest limits (this pass)

- **Custom rooms are still a dumb relay**: the server holds no
  game state for them and simulates nothing; correctness relies on
  every client running the same deterministic lockstep simulation.
  Ranked rooms (stage 3) are the exception — a dedicated referee
  process simulates them authoritatively (see above).
- **Match results**: custom rooms are host-reported (see the trust
  model above); ranked rooms are referee-reported only.
- **Ranked is 1v1 only** this stage; 2v2/FFA ranked comes later.
- **One referee process per match** — simple and isolated, fine at
  friends scale, but not yet a pooled/warm fleet of referees.
- **Ranked clients still simulate locally** (lockstep, as before);
  the referee is the canonical checksum + resync source and the
  sole result reporter — full thin-client state streaming from the
  server is beyond this stage.
- **File-backed account store** for now — in-memory indexes with a
  JSON flush per mutation; fine for the current scale, PostgreSQL
  drops in behind the `Store` interface later.
- Clients are expected to run `--fixed-fps 30`: the lockstep drive
  advances the simulation in fixed 1/30 s steps handed out by server
  ticks (3 steps per tick).
