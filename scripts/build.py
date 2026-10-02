#!/usr/bin/env python3
# Assemble les modules src/ en un seul dist/BF.lua chargeable dans l'executor.
# Chaque module est enveloppé dans une IIFE et rangé dans genv.__BF_<NOM> ;
# main.lua les récupère via ses fallbacks `genv.__BF_X or require(...)`.
import pathlib

ORDER = ["core", "ui", "teleport", "combat", "farm", "player", "fruits", "shop", "events", "extras", "info"]  # deps avant main
src = pathlib.Path("src")

parts = [
    "-- BUILT FILE - do not edit. Edit src/ then run scripts/build.py",
    "local genv = (getgenv and getgenv()) or _G",
]
for name in ORDER:
    code = (src / f"{name}.lua").read_text(encoding="utf-8").rstrip()
    parts.append(f"genv.__BF_{name.upper()} = (function()\n{code}\nend)()")
parts.append((src / "main.lua").read_text(encoding="utf-8").rstrip())

dist = pathlib.Path("dist")
dist.mkdir(exist_ok=True)
out = dist / "BF.lua"
out.write_text("\n\n".join(parts) + "\n", encoding="utf-8")
print(f"wrote {out} ({out.stat().st_size} bytes)")
