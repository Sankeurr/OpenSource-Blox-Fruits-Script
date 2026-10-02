-- Entry point: wires Core + modules, builds the UI, restores the last saved config.
local genv = (getgenv and getgenv()) or _G

if genv.BF then genv.BF.unload() end

local Core = genv.__BF_CORE or require(script.Parent.core)
genv.BF = Core

Core.configure({ verbose = true })
Core.info("core loaded")

local UI = genv.__BF_UI or require(script.Parent.ui)
Core.register("ui", UI)
UI.build(Core)
local TABS = {
    { "Info",     "Player and script info" },
    { "Farm",     "Level farm and quests", "Sea1" },
    { "Farm 2",   "Level farm and quests", "Sea2" },
    { "Farm 3",   "Level farm and quests", "Sea3" },
    { "PVP",      "Combat, aura, aimbot, players" },
    { "Teleport", "Move, islands and waypoints" },
    { "Sea",      "Sea travel and transitions", "Sea1,Sea2" },
    { "Fruit",    "Fruit ESP, collect and dealer" },
    { "Shop",     "Buy Sea 1 items", "Sea1" },
    { "Shop 2",   "Buy Sea 2 items", "Sea2" },
    { "Shop 3",   "Buy Sea 3 items", "Sea3" },
    { "Raids/Events", "Raids, sea events, leviathan", "Sea2,Sea3" },
    { "Extras",   "Race V4, awakening, special bosses", "Sea3" },
    { "Player",   "Player ESP and mobility" },
    { "Config",   "Save and restore settings" },
    { "Logs",     "Actions and proofs" },
}
for _, t in ipairs(TABS) do UI.addTab(t[1], t[2], t[3]) end

local Teleport = genv.__BF_TELEPORT or require(script.Parent.teleport)
Teleport.init(Core, UI)
local Combat = genv.__BF_COMBAT or require(script.Parent.combat)
Combat.init(Core, UI)
local Farm = genv.__BF_FARM or require(script.Parent.farm)
Farm.init(Core, UI)
local Player = genv.__BF_PLAYER or require(script.Parent.player)
Player.init(Core, UI)
local Fruits = genv.__BF_FRUITS or require(script.Parent.fruits)
Fruits.init(Core, UI)
local Shop = genv.__BF_SHOP or require(script.Parent.shop)
Shop.init(Core, UI)
local Events = genv.__BF_EVENTS or require(script.Parent.events)
Events.init(Core, UI)
local Extras = genv.__BF_EXTRAS or require(script.Parent.extras)
Extras.init(Core, UI)
local Info = genv.__BF_INFO or require(script.Parent.info)
Info.init(Core, UI)

do
    local page = UI.page("Config")
    local nameBox = UI.textbox(page, "Config name...")
    UI.button(page, "Save config", "Save current settings under this name", function()
        local n = (nameBox.Text ~= "" and nameBox.Text) or "default"
        UI.notify(Core.saveNamedConfig(n) and ("Saved: " .. n) or "Save failed (executor?)")
    end)
    UI.section(page, "LOAD (type the name above, or pick below)")
    local saved = Core.listConfigs()
    if #saved == 0 then saved = { "(type name above)" } end
    local dd = UI.dropdown(page, "Saved", "Existing configs (at launch)", saved, function(_) end)
    UI.button(page, "Load config", "Load the name in the box, else the dropdown", function()
        local n = (nameBox.Text ~= "" and nameBox.Text) or dd.Get()
        UI.notify(Core.loadNamedConfig(n) and ("Loaded: " .. n) or "Not found: " .. tostring(n))
    end)
    UI.section(page, "Last config auto-loads on start")
end

do
    local page = UI.page("Logs")
    local out
    UI.button(page, "Refresh", "Reload the log buffer", function() out.Text = Core.dumpLogs() end)
    UI.button(page, "Clear", "Empty the log buffer", function() Core.logs = {}; out.Text = "" end)
    out = UI.output(page)
    out.Text = Core.dumpLogs()
end

if Core.loadLastConfig() then Core.info("last config restored") end

Core.info("all modules loaded")
return Core
