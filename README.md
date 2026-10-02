<div align="center">

### ⭐ Before you read on — drop a star at the top of this page. It takes a second and it genuinely helps.

# 🩸 Blox Fruits Script

**A full-featured, multi-executor automation & combat suite for Blox Fruits.**
Clean modular Lua, built to behave like the game's own client traffic.

*An open-source script made by a member of the community.*

`Sea 1` · `Sea 2` · `Sea 3` — *everything scales with where you are.*

</div>

---

> **Disclaimer.** This project is developed and used strictly for **testing and
> educational purposes**. Use it only
> where you have the right to. You are responsible for how you use it.

---

## ✨ Overview

This is a single-file script you load into your executor. It opens a clean dark/red GUI
with per-sea tabs — features that only exist in Sea 2 or Sea 3 stay hidden until you're there, so
the menu never shows you things you can't use.

Everything is **auto from A to Z**: pick *Auto level farm* and it flies to the right quest mob,
attacks, collects, and moves to the next island on its own. The same philosophy applies to raids,
bosses, bounty hunting and sea travel.

---

## 🚀 How to use

1. Open your executor and inject into Blox Fruits.
2. Run the loader (grabs the latest `dist/BF.lua`):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Sankeurr/OpenSource-Blox-Fruits-Script/main/dist/BF.lua"))()
```

> Using the raw loader means you always get the newest version — no need to re-paste anything when
> the script updates.

### Compatible executors

The script guards every exploit API it touches, so it runs on **any executor with standard
functions**. Tested examples:

- **Potassium**
- **Wave**

---

## 🧩 Features

### 🌾 Farming (`Farm` / `Farm 2` / `Farm 3`)
- **Auto level farm** — flies to the correct quest mob for your level and farms it, island by island.
- **Auto Next Island** — advances automatically when the current mobs are cleared.
- **Farm Boss** / **Farm Nearest** — lock onto a specific boss, or just hit whatever is around.
- **Material Farm** — farm the materials needed for upgrades (per sea).
- **Bring mob** — pull mobs to a single point under you.
- **Auto equip** + **Auto add points** — keep your weapon out and spend stat points automatically.

### ⚔️ Combat (`PVP`)
- **Kill aura** with **Line of sight** (never hits through walls).
- **Auto attack** (mobs and/or players), **Fast attack**, **Auto skills** (Z/X/C/V/F rotation).
- **Aimbot** (smooth camera lerp), **Follow nearest**, **1v1**, **Spectate nearest**.
- **Auto Bounty V4** — hunt players for bounty with safeguards: don't attack friends, don't attack
  Cup holders (truce), **No stun**, **Invisible from Ken**, and an optional chat message after a kill.
- **Elite Hunter** — claim and track elite hunter progress.

### 🧍 Player (`Player`)
- **Player ESP** (highlight + distance), **NoClip**, **Walk on Water**, **Speed boost**, **Super jump**.
- **Auto Ken** / **Auto Buso** — keep your Haki on (re-enables it if the game turns it off).
- **Anti-AFK** — never get hit by the 20-minute idle kick while farming.

### 🗺️ Teleport & Travel (`Teleport` / `Sea`)
- Island & boss teleports for **every sea**, plus a boss list and special-boss list.
- **Waypoints** — save your current position and fly back to it anytime.
- **Set Spawn Here** and **Notify current position**.
- **Auto Second Sea** (Lv 700) and **Auto Third Sea** (Lv 1500) — travels for you via the right NPC.

### 🍈 Fruits (`Fruit`)
- **Fruit ESP** + **Fruit snipe** + **Grab Fruit** — spot fruits on the map and grab them.
- **Auto Random Fruit** — roll the gacha automatically.
- **Fruit Store** / stock viewer.

### 🛒 Shops (`Shop` / `Shop 2` / `Shop 3`)
- Per-sea dealers: swords, guns, fighting styles, accessories.
- **Auto Buy Legendary Sword** — grabs the random-dealer legendary swords (Rengoku / Oroshi / Shizu) when he's around.
- **Auto Rengoku** — opens the Ice Castle chest route for Rengoku.

### 🐉 Raids & Events (`Raids/Events`)
- **Auto Raid** — buys the right Microchip, travels to the raid tube, starts it, clears every room, and detects the finish.
- **Sea Events** — teleport to events, **Open Leviathan gate**, pull nearby levers/prompts.
- **Server hop** utility.

### 🎁 Extras — Sea 3 (`Extras`)
- **Race V4** — upgrade/awaken, reroll race, V4 trial teleport, progress check.
- **Auto Cake Prince**, **Auto Rip Indra**.

### ⚙️ Quality of life (`Config` / `Info` / `Logs`)
- **Save / Load config** — your settings are stored and the last config auto-loads on start.
- **Info** tab shows your executor, current sea and status; **Logs** tab keeps an in-memory trace.

---

## 🛡️ Anti-cheat aware by design

The script is written to stay inside the kind of traffic the real client already sends, instead of
doing obviously-flagged things:

- **Movement is tween-based** — no raw `CFrame` snapping. During a fly the character's velocity is
  zeroed and NoClip is applied, and the character is **never anchored** (Blox Fruits rejects hits
  from anchored characters).
- **Hits use a real, server-validated `hitId`** — captured from the game's *own* `RegisterHit`
  call via a metamethod hook, rather than a forged id (forged ids get rejected on fresh accounts).
- **Fishing rod auto-unequip** before attacking — a rod hijacks the attack remote, so hits wouldn't land.
- **Kill aura line-of-sight** raycast — no attacking through walls.
- **Aimbot uses a smooth camera lerp** (factor < 0.2), not memory manipulation.
- **Attack debounce** kept realistic (fast attack ≈ 0.08s, not zero cooldown).
- **Farm positioning** keeps a height offset above the mob and pauses the water platform on Sea 3's
  submerged islands.
- **Anti-AFK** via `VirtualUser` so long farms don't trigger the idle kick.

> A "lower the fly speed if the anti-cheat loopbacks" note is baked into the config — the defaults are
> tuned for the huge Sea 3 map, and every automated action is throttled rather than spammed.

---

## 🏗️ Architecture

The script is **modular** and compiled into one file:

```
src/            one Lua module per area (edit here)
  core.lua        config, logs, lifecycle (clean unload)
  ui.lua          dark/red GUI, tabs, per-sea visibility
  combat.lua      attacks, kill aura, aimbot, bounty
  farm.lua        level/boss/material auto-farm
  player.lua      ESP, mobility, haki, anti-afk
  teleport.lua    fly, island/boss lists, waypoints, sea travel
  fruits.lua      fruit finder + gacha
  shop.lua        per-sea dealers + auto-buy
  events.lua      raids + sea events
  extras.lua      Sea 3 misc (Race V4, Cake Prince, Rip Indra)
  info.lua        status tab
scripts/
  build.py        bundles src/ → dist/BF.lua (one IIFE per module under getgenv())
dist/
  BF.lua          ← the built, ready-to-run script
```

Each module registers itself with `Core`, which handles config persistence and a full cleanup on
unload. Sea detection drives which tabs are visible. **You run `dist/BF.lua`; you edit `src/`.**

To rebuild after editing a module:

```bash
python scripts/build.py
```

---

## 🔍 `recon.lua` — developer dump tool

`src/recon.lua` is a standalone developer utility (it is **not** bundled into `dist/BF.lua`). It
dumps a Roblox game's RemoteEvents / RemoteFunctions and instance tree to a log file — it was used to
map Blox Fruits while building this script.

> ⚠️ **Be careful: this tool can dump Blox Fruits *or any other Roblox game*.** Use it only on games
> you are allowed to inspect, and entirely **at your own risk**. The author is **not responsible** for
> how you use it or for any consequences that follow.

---

## 🔄 Maintenance

This script is **actively maintained and kept up to date** with Blox Fruits. Because the loader
pulls `dist/BF.lua` from raw, every fix and new feature reaches you **instantly** — just re-run the
loader.

---

<div align="center">

### ⭐ If this was useful to you, drop a star — it genuinely helps.

</div>
