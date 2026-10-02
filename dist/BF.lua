-- BUILT FILE - do not edit. Edit src/ then run scripts/build.py

local genv = (getgenv and getgenv()) or _G

genv.__BF_CORE = (function()
-- Core: config, in-memory logs, and lifecycle (connections/threads/modules) cleaned up on unload.
local Core = {}
Core.config = {}
Core.logs = {}
Core._conns = {}
Core._threads = {}
Core._cleanups = {}
Core.modules = {}

local LOG_CAP = 2000
local spawn = (task and task.spawn) or function(f, ...) return coroutine.wrap(f)(...) end
local cancel = task and task.cancel

Core.config = {
    prefix = "[BF]",
    verbose = true,
    logToFile = false,
}
function Core.configure(overrides)
    for k, v in pairs(overrides or {}) do Core.config[k] = v end
    return Core.config
end

function Core.log(level, ...)
    local n = select("#", ...)
    local parts = table.create and table.create(n) or {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    local msg = table.concat(parts, " ")
    local now = (os.clock and os.clock()) or 0
    Core.logs[#Core.logs + 1] = { t = now, level = level, msg = msg }
    if #Core.logs > LOG_CAP then table.remove(Core.logs, 1) end
    if Core.config.verbose then print(("%s %s: %s"):format(Core.config.prefix, level, msg)) end
    if Core.config.logToFile and writefile and appendfile then
        pcall(appendfile, "bf_script.log", ("%.2f %s %s\n"):format(now, level, msg))
    end
    return msg
end
function Core.info(...) return Core.log("INFO", ...) end
function Core.warn(...) return Core.log("WARN", ...) end
function Core.dumpLogs()
    local out = {}
    for i, e in ipairs(Core.logs) do out[i] = ("%.2f %s %s"):format(e.t, e.level, e.msg) end
    return table.concat(out, "\n")
end

function Core.track(conn)
    Core._conns[#Core._conns + 1] = conn
    return conn
end
function Core.spawn(fn, ...)
    local th = spawn(fn, ...)
    Core._threads[#Core._threads + 1] = th
    return th
end
function Core.onCleanup(fn)
    Core._cleanups[#Core._cleanups + 1] = fn
end
function Core.register(name, mod)
    Core.modules[name] = mod
    return mod
end

local HttpService = game:GetService("HttpService")
local CONFIG_FILE = "BF_config.json"
function Core.gatherConfig()
    local t = {}
    local ui = Core.modules.ui
    if ui and ui._controls then
        for key, c in pairs(ui._controls) do
            local ok, v = pcall(c.get)
            if ok and v ~= nil then t[key] = v end
        end
    end
    return t
end
function Core.applyConfig(data)
    local ui = Core.modules.ui
    if not (ui and ui._controls) then return end
    for key, v in pairs(data or {}) do
        local c = ui._controls[key]
        if c then pcall(c.set, v) end
    end
end
function Core.saveConfig(file)
    if not writefile then return false, "no writefile" end
    local ok, s = pcall(function() return HttpService:JSONEncode(Core.gatherConfig()) end)
    if not ok then return false, "encode failed" end
    local wok = pcall(writefile, file or CONFIG_FILE, s)
    return wok
end
function Core.loadConfig(file)
    file = file or CONFIG_FILE
    if not (isfile and readfile) then return false, "no readfile" end
    local ok = pcall(isfile, file)
    if not (ok and isfile(file)) then return false, "no file" end
    local rok, data = pcall(function() return HttpService:JSONDecode(readfile(file)) end)
    if rok and type(data) == "table" then Core.applyConfig(data); return true end
    return false, "decode failed"
end

local LAST_FILE = "BF_lastcfg.txt"
local function cfgFile(name) return "BF_cfg_" .. name .. ".json" end
function Core.listConfigs()
    local names = {}
    if not listfiles then return names end
    local ok, files = pcall(listfiles, "")
    if not ok or not files then ok, files = pcall(listfiles, ".") end
    if files then
        for _, f in ipairs(files) do
            local n = tostring(f):match("BF_cfg_(.+)%.json$")
            if n then names[#names + 1] = n end
        end
    end
    return names
end
function Core.saveNamedConfig(name)
    if not writefile or not name or name == "" then return false end
    local ok, s = pcall(function() return HttpService:JSONEncode(Core.gatherConfig()) end)
    if not ok then return false end
    local wok = pcall(writefile, cfgFile(name), s)
    if wok then pcall(writefile, LAST_FILE, name) end
    return wok
end
function Core.loadNamedConfig(name)
    if not name or name == "" or not (isfile and readfile) then return false end
    local f = cfgFile(name)
    if not (pcall(isfile, f) and isfile(f)) then return false end
    local rok, data = pcall(function() return HttpService:JSONDecode(readfile(f)) end)
    if rok and type(data) == "table" then
        Core.applyConfig(data)
        if writefile then pcall(writefile, LAST_FILE, name) end
        return true
    end
    return false
end
function Core.loadLastConfig()
    if not (isfile and readfile) then return false end
    if not (pcall(isfile, LAST_FILE) and isfile(LAST_FILE)) then return false end
    local ok, name = pcall(readfile, LAST_FILE)
    if ok and name and name ~= "" then return Core.loadNamedConfig(name) end
    return false
end

function Core.unload()
    for _, m in pairs(Core.modules) do
        if type(m) == "table" and type(m.stop) == "function" then pcall(m.stop) end
    end
    for _, fn in ipairs(Core._cleanups) do pcall(fn) end
    for _, c in ipairs(Core._conns) do pcall(function() c:Disconnect() end) end
    for _, th in ipairs(Core._threads) do if cancel then pcall(cancel, th) end end
    Core._conns, Core._threads, Core._cleanups, Core.modules = {}, {}, {}, {}
    Core.info("unloaded")
end

function Core.selfTest()
    Core.configure({ verbose = false })
    assert(Core.config.verbose == false, "configure override")
    Core.info("hello", 42)
    assert(Core.logs[#Core.logs].msg == "hello 42", "log join")
    local closed = 0
    Core.track({ Disconnect = function() closed = closed + 1 end })
    Core.onCleanup(function() closed = closed + 1 end)
    local ran = false
    Core.register("t", { stop = function() ran = true end })
    Core.unload()
    assert(ran, "module.stop called")
    assert(closed == 2, "conn + cleanup fired")
    assert(next(Core.modules) == nil and #Core._conns == 0, "state cleared")
    Core.configure({ verbose = true })
    print("core.selfTest OK")
    return true
end

return Core
end)()

genv.__BF_UI = (function()
-- UI: Dark/Red "Blox Fruits Script" window, tabs, toggles/sliders/dropdowns, config registry.
-- Tabs/sections carry a sea tag so Sea-2/Sea-3-only features stay hidden in other seas.
local UIS = game:GetService("UserInputService")

local UI = {}
UI.tabs = {}
UI._current = nil
UI._controls = {}
UI._searchQ = ""
UI._currentSea = "Sea1"
UI._seaHooks = {}

local function register(page, title, api)
    if page and title and api and api.Get and api.Set then
        UI._controls[page.Name .. "/" .. title] = { get = api.Get, set = api.Set }
    end
end

-- tag can list several seas ("Sea2,Sea3"); no tag = shown in every sea.
local function seaMatches(tag, sea)
    if not tag then return true end
    return tag == sea or (tag:find(sea, 1, true) ~= nil)
end

local C = {
    bg     = Color3.fromRGB(34, 34, 37),
    side   = Color3.fromRGB(42, 42, 46),
    panel  = Color3.fromRGB(52, 52, 57),
    line   = Color3.fromRGB(80, 80, 86),
    accent = Color3.fromRGB(214, 48, 60),
    text   = Color3.fromRGB(238, 238, 240),
    dim    = Color3.fromRGB(160, 160, 166),
}
local TOGGLE_KEY = Enum.KeyCode.RightShift

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end

function UI.build(Core)
    local host = (gethui and gethui()) or game:GetService("CoreGui")
    local gui = new("ScreenGui", {
        Name = "BloxFruitsScript", ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, host)
    UI.gui, UI._core = gui, Core
    Core.onCleanup(function() gui:Destroy() end)

    local root = new("Frame", {
        Name = "Root", Size = UDim2.fromOffset(640, 430),
        Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = C.bg, BorderSizePixel = 0,
    }, gui)
    corner(root, 10)

    local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1 }, root)
    new("TextLabel", {
        Text = "Blox Fruits Script", Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = C.accent,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -120, 0, 22), Position = UDim2.fromOffset(16, 10),
    }, header)
    new("TextLabel", {
        Text = "OpenSource", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.dim,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -120, 0, 16), Position = UDim2.fromOffset(16, 32),
    }, header)

    local function dot(color, x)
        return new("TextButton", {
            Text = "", AutoButtonColor = true, BackgroundColor3 = color, BorderSizePixel = 0,
            Size = UDim2.fromOffset(12, 12), Position = UDim2.new(1, x, 0, 16),
        }, header)
    end
    local green = dot(Color3.fromRGB(90, 90, 96), -66); corner(green, 6)
    local minBtn = dot(Color3.fromRGB(230, 190, 80), -46); corner(minBtn, 6)
    local closeBtn = dot(Color3.fromRGB(230, 90, 90), -26); corner(closeBtn, 6)

    local side = new("Frame", {
        Name = "Side", Size = UDim2.new(0, 176, 1, -56), Position = UDim2.fromOffset(0, 56),
        BackgroundColor3 = C.side, BorderSizePixel = 0,
    }, root)
    local searchWrap = new("Frame", {
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 8),
    }, side)
    corner(searchWrap, 6)
    local search = new("TextBox", {
        PlaceholderText = "Search...", Text = "", ClearTextOnFocus = false,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text, PlaceholderColor3 = C.dim,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0),
    }, searchWrap)
    local tabList = new("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, side)
    new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, tabList)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4) }, tabList)
    UI._tabList = tabList

    local content = new("Frame", {
        Name = "Content", Size = UDim2.new(1, -176, 1, -56), Position = UDim2.fromOffset(176, 56),
        BackgroundTransparency = 1,
    }, root)
    UI._pages = content

    search:GetPropertyChangedSignal("Text"):Connect(function()
        UI._searchQ = search.Text:lower()
        UI.refreshTabs()
    end)

    local dragging, ds, sp
    Core.track(header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, ds, sp = true, i.Position, root.Position
        end
    end))
    Core.track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            root.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
        end
    end))
    Core.track(UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))

    local minimized = false
    Core.track(minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        side.Visible, content.Visible = not minimized, not minimized
        root.Size = minimized and UDim2.new(0, 640, 0, 56) or UDim2.fromOffset(640, 430)
    end))
    Core.track(closeBtn.MouseButton1Click:Connect(function() Core.unload() end))
    Core.track(UIS.InputBegan:Connect(function(i, gpe)
        if not gpe and i.KeyCode == TOGGLE_KEY then gui.Enabled = not gui.Enabled end
    end))

    Core.info("UI built — toggle:", TOGGLE_KEY.Name)
    return UI
end

function UI.addTab(name, desc, sea)
    local btn = new("TextButton", {
        Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = C.side,
        BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 46),
        Visible = seaMatches(sea, UI._currentSea),
    }, UI._tabList)
    corner(btn, 6)
    new("TextLabel", {
        Name = "Name", Text = name, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(10, 5),
    }, btn)
    new("TextLabel", {
        Name = "Desc", Text = desc or "", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.dim,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd,
        Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(10, 24),
    }, btn)

    local page = new("ScrollingFrame", {
        Name = name, Visible = false, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0), CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
    }, UI._pages)
    new("UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, page)

    btn.MouseButton1Click:Connect(function() UI.select(name) end)
    UI.tabs[name] = { button = btn, page = page, sea = sea }
    if not UI._current then UI.select(name) end
    return page
end

function UI.page(name) local t = UI.tabs[name]; return t and t.page end

function UI.refreshTabs()
    local firstVisible
    for name, t in pairs(UI.tabs) do
        local seaOk = seaMatches(t.sea, UI._currentSea)
        local sOk = UI._searchQ == "" or (name:lower():find(UI._searchQ, 1, true) ~= nil)
        t.button.Visible = seaOk and sOk
        if seaOk and sOk then firstVisible = firstVisible or name end
    end
    local cur = UI.tabs[UI._current]
    if firstVisible and (not cur or not cur.button.Visible) then UI.select(firstVisible) end
end

function UI.onSea(fn)
    UI._seaHooks[#UI._seaHooks + 1] = fn
    pcall(fn, UI._currentSea)
end

function UI.setSea(sea)
    if sea and sea ~= UI._currentSea then
        UI._currentSea = sea
        UI.refreshTabs()
        for _, fn in ipairs(UI._seaHooks) do pcall(fn, sea) end
    end
end

function UI.select(name)
    for n, t in pairs(UI.tabs) do
        local on = (n == name)
        t.page.Visible = on
        t.button.BackgroundColor3 = on and C.panel or C.side
        t.button:FindFirstChild("Name").TextColor3 = on and C.accent or C.text
    end
    UI._current = name
end

local function rowBase(page, h, title, desc)
    local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, h or 50) }, page)
    new("TextLabel", {
        Name = "Title", Text = title or "", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(1, -150, 0, 18), Position = UDim2.fromOffset(2, desc and 8 or 16),
    }, f)
    if desc then
        new("TextLabel", {
            Name = "Desc", Text = desc, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.dim,
            TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd,
            Size = UDim2.new(1, -150, 0, 15), Position = UDim2.fromOffset(2, 27),
        }, f)
    end
    new("Frame", { BackgroundColor3 = C.line, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1) }, f)
    return f
end

function UI.section(page, title)
    local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28) }, page)
    new("TextLabel", {
        Text = title, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.dim,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -4),
    }, f)
    return f
end

function UI.button(page, title, desc, cb)
    local f = rowBase(page, 50, title, desc)
    new("TextLabel", {
        Text = "›", Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = C.dim,
        BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 50), Position = UDim2.new(1, -26, 0, 0),
    }, f)
    local hit = new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 }, f)
    hit.MouseButton1Click:Connect(function() if cb then cb() end end)
    return hit
end

function UI.toggle(page, title, desc, default, cb)
    local f = rowBase(page, 50, title, desc)
    local knob = new("TextButton", {
        Text = "", AutoButtonColor = false, BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Size = UDim2.fromOffset(42, 22), Position = UDim2.new(1, -50, 0.5, -11),
    }, f)
    corner(knob, 11)
    local dot = new("Frame", { BackgroundColor3 = C.dim, BorderSizePixel = 0, Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(3, 3) }, knob)
    corner(dot, 8)
    local state = default and true or false
    local api = {}
    function api.Set(v)
        state = v and true or false
        dot.Position = state and UDim2.new(1, -19, 0, 3) or UDim2.fromOffset(3, 3)
        dot.BackgroundColor3 = state and Color3.new(1, 1, 1) or C.dim
        knob.BackgroundColor3 = state and C.accent or C.panel
        if cb then cb(state) end
    end
    function api.Get() return state end
    knob.MouseButton1Click:Connect(function() api.Set(not state) end)
    if state then api.Set(true) end
    register(page, title, api)
    return api
end

function UI.slider(page, title, desc, min, max, default, cb)
    local f = rowBase(page, 62, title, desc)
    local val = new("TextLabel", {
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.accent,
        TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(60, 18), Position = UDim2.new(1, -62, 0, 8),
    }, f)
    local track = new("Frame", {
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Size = UDim2.new(1, -4, 0, 6), Position = UDim2.new(0, 2, 1, -14),
    }, f)
    corner(track, 3)
    local fill = new("Frame", { BackgroundColor3 = C.accent, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0) }, track)
    corner(fill, 3)
    local value = math.clamp(default or min, min, max)
    local api = {}
    function api.Set(v)
        value = math.clamp(math.floor(v + 0.5), min, max)
        local a = (max > min) and (value - min) / (max - min) or 0
        fill.Size = UDim2.new(a, 0, 1, 0)
        val.Text = tostring(value)
        if cb then cb(value) end
    end
    function api.Get() return value end
    local dragging = false
    local function setFromX(x)
        local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        api.Set(min + a * (max - min))
    end
    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; setFromX(i.Position.X)
        end
    end)
    UI._core.track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then setFromX(i.Position.X) end
    end))
    UI._core.track(UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    api.Set(value)
    register(page, title, api)
    return api
end

function UI.dropdown(page, title, desc, options, cb)
    local ROW, ITEM = 50, 26
    local listH = math.min(#options, 6) * ITEM
    local f = rowBase(page, ROW, title, desc)
    f.ClipsDescendants = false
    local btn = new("TextButton", {
        Text = (options[1] or "-") .. "  ▾", Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1, AutoButtonColor = false,
        Size = UDim2.fromOffset(150, ROW), Position = UDim2.new(1, -152, 0, 0), ZIndex = 3,
    }, f)
    local list = new("ScrollingFrame", {
        Visible = false, BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 6,
        Size = UDim2.new(1, -4, 0, listH), Position = UDim2.new(0, 2, 0, ROW - 4),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
    }, f)
    corner(list, 6)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, list)
    local current = options[1]
    local api = { Get = function() return current end, frame = f }
    local function setOpen(v)
        list.Visible = v
        f.Size = UDim2.new(1, 0, 0, v and (ROW + listH) or ROW)
    end
    function api.Set(opt)
        current = opt
        btn.Text = tostring(opt) .. "  ▾"
        if cb then cb(opt) end
    end
    for _, opt in ipairs(options) do
        local o = new("TextButton", {
            Text = "  " .. opt, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text,
            TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = C.panel, BorderSizePixel = 0,
            AutoButtonColor = true, Size = UDim2.new(1, 0, 0, ITEM), ZIndex = 7,
        }, list)
        o.MouseButton1Click:Connect(function() api.Set(opt); setOpen(false) end)
    end
    btn.MouseButton1Click:Connect(function() setOpen(not list.Visible) end)
    register(page, title, api)
    return api
end

function UI.stat(page, label)
    local f = new("Frame", { BackgroundColor3 = C.panel, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30) }, page)
    corner(f, 6)
    new("TextLabel", {
        Text = label, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.dim,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
        Size = UDim2.new(0.45, -12, 1, 0), Position = UDim2.fromOffset(12, 0),
    }, f)
    local v = new("TextLabel", {
        Text = "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd,
        Size = UDim2.new(0.55, -12, 1, 0), Position = UDim2.new(0.45, 0, 0, 0),
    }, f)
    new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 4) }, page)
    return v
end

function UI.textbox(page, placeholder, cb)
    local f = rowBase(page, 44)
    local box = new("TextBox", {
        PlaceholderText = placeholder or "", Text = "", ClearTextOnFocus = false,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text, PlaceholderColor3 = C.dim,
        BackgroundColor3 = C.panel, BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, -4, 0, 30), Position = UDim2.new(0, 2, 0, 7),
    }, f)
    corner(box, 6)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, box)
    box.FocusLost:Connect(function(enter) if cb then cb(box.Text, enter) end end)
    return box
end

function UI.output(page)
    local f = new("Frame", { Size = UDim2.new(1, 0, 0, 220), BackgroundColor3 = C.side, BorderSizePixel = 0 }, page)
    corner(f, 6)
    return new("TextLabel", {
        Text = "", Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true, BackgroundTransparency = 1,
        Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6),
    }, f)
end

function UI.notify(text, duration)
    if not UI.gui then return end
    local holder = UI._toasts
    if not holder then
        holder = new("Frame", {
            Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -12, 1, -12), Size = UDim2.fromOffset(260, 300),
        }, UI.gui)
        local l = new("UIListLayout", { Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Bottom }, holder)
        l.HorizontalAlignment = Enum.HorizontalAlignment.Right
        UI._toasts = holder
    end
    local t = new("TextLabel", {
        Text = "  " .. text, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 32), TextWrapped = true,
    }, holder)
    corner(t, 6)
    task.delay(duration or 3, function() if t then t:Destroy() end end)
    return t
end

function UI.stop()
    if UI.gui then UI.gui:Destroy() end
    UI.tabs, UI._current = {}, nil
end

return UI
end)()

genv.__BF_TELEPORT = (function()
-- Teleport: CFrame-tween fly, island/boss lists per sea, waypoints, auto sea travel.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local M = {}
M.config = { speed = 200 }   -- studs/s; 200 suits the huge Sea 3 map. Drop to ~100 if anti-cheat kicks/loopbacks.
M._tween = nil
M.waypoints = {}

M.islands = {
    { name = "Middle Town",        pos = Vector3.new(-1193.9, 12, -549.8) },
    { name = "Pirate Starter",     pos = Vector3.new(1038, 15, 1550) },
    { name = "Marine Starter",     pos = Vector3.new(-2674.5, 32.1, 2187.0) },
    { name = "Jungle",             pos = Vector3.new(-1866.3, 29.9, 21.6) },
    { name = "Buggy Island",       pos = Vector3.new(-981.0, 30.4, 3966.8) },
    { name = "Desert Island",      pos = Vector3.new(999.9, 7.6, 4490.3) },
    { name = "Snow Island",        pos = Vector3.new(1519.5, 78.0, -1510.9) },
    { name = "Marineford",         pos = Vector3.new(-4763.7, 13.4, 4288.8) },
    { name = "Sky Islands",        pos = Vector3.new(-4973.7, 280.7, -1119.4) },
    { name = "Mob Island (Saber)", pos = Vector3.new(-1527.2, 34.1, -33.2) },
    { name = "Impel Down",         pos = Vector3.new(5278.6, 7.1, 391.6) },
    { name = "Colosseum",          pos = Vector3.new(-1973.1, 9.0, -2744.9) },
    { name = "Volcano",            pos = Vector3.new(-5623.8, 17.0, 8314.1) },
    { name = "Fishman Island",     pos = Vector3.new(3894.3, 4.0, -1915.2) },
    { name = "Upper Sky Islands",  pos = Vector3.new(-6040.2, 5468.0, 1734.2) },
    { name = "Water 7",            pos = Vector3.new(5430.4, 78.0, 3953.6) },
}
M.islands2 = {
    { name = "Kingdom of Rose",  pos = Vector3.new(-195.1, 155.3, 279.9) },
    { name = "Café",             pos = Vector3.new(-380.4, 72.8, 303.2) },
    { name = "Mansion",          pos = Vector3.new(-393.3, 367.3, 687.5) },
    { name = "Colosseum",        pos = Vector3.new(-1836.4, 72.8, 1360.2) },
    { name = "Swan's Room",      pos = Vector3.new(2293.7, 12.5, 663.1) },
    { name = "Factory",          pos = Vector3.new(431.0, 238.4, -433.2) },
    { name = "Green Zone",       pos = Vector3.new(-2340.8, 155.3, -3396.3) },
    { name = "Dark Arena",       pos = Vector3.new(3807.1, 11.8, -3452.2) },
    { name = "Graveyard Island", pos = Vector3.new(-5577.9, 87.6, -782.2) },
    { name = "Snow Mountain",    pos = Vector3.new(856.2, 50.3, -5278.3) },
    { name = "Hot and Cold",     pos = Vector3.new(-5734.3, 49.4, -5146.4) },
    { name = "Cursed Ship",      pos = Vector3.new(900.9, 144.0, 33072.6) },
    { name = "Ice Castle",       pos = Vector3.new(6062.3, 155.3, -6880.9) },
    { name = "Forgotten Island", pos = Vector3.new(-3194.2, 155.3, -10795.3) },
}
M.bosses2 = {
    { name = "Diamond", pos = Vector3.new(-1711.4, 206.0, -97.1) },
    { name = "Jeremy", pos = Vector3.new(2338.0, 451.4, 700.1) },
    { name = "Smoke Admiral", pos = Vector3.new(-4857.4, 233.7, -5583.2) },
    { name = "Awakened Ice Admiral", pos = Vector3.new(6551.8, 325.3, -6989.9) },
    { name = "rip_indra", pos = Vector3.new(-26952.3, 21.5, 329.4) },
}
M.islands3 = {
    { name = "Port Town",              pos = Vector3.new(-610.4, 57.8, 6436.3) },
    { name = "Dragon Dojo",            pos = Vector3.new(5704.4, 1168.1, 937.0) },
    { name = "Castle on the Sea",      pos = Vector3.new(-5436.6, 815.6, -2701.7) },
    { name = "Floating Turtle",        pos = Vector3.new(-12164.6, -548.9, -8454.9) },
    { name = "Friendly Arena",         pos = Vector3.new(5012.8, 72.8, -1570.6) },
    { name = "Great Tree",             pos = Vector3.new(3036.3, 815.6, -7149.9) },
    { name = "Haunted Castle",         pos = Vector3.new(-9530.6, -132.9, 5763.1) },
    { name = "Beautiful Pirate Domain",pos = Vector3.new(5366.6, 71.2, -225.9) },
    { name = "Mansion",                pos = Vector3.new(-12547.7, 290.1, -7487.1) },
    { name = "North Pole",             pos = Vector3.new(-1141.1, 57.8, -14480.7) },
    { name = "Sea of Treats",          pos = Vector3.new(-1505.3, 57.8, -10724.1) },
    { name = "Secret Temple",          pos = Vector3.new(5226.2, 63.5, 858.8) },
    { name = "Tiki Outpost",           pos = Vector3.new(-16641.5, 213.3, 435.4) },
    { name = "Heavenly Dimension",     pos = Vector3.new(-22709.6, 5259.0, 3886.6) },
    { name = "Hell Dimension",         pos = Vector3.new(-22737.6, 5120.0, 2234.6) },
}
M.bosses3 = {
    { name = "Kilo Admiral", pos = Vector3.new(2998.3, 508.8, -7344.3) },
    { name = "Captain Elephant", pos = Vector3.new(-13365.5, 321.2, -8485.0) },
    { name = "Longma", pos = Vector3.new(-10156.2, 337.8, -9445.9) },
    { name = "Cake Queen", pos = Vector3.new(-678.5, 381.9, -11114.3) },
    { name = "Cake Prince", pos = Vector3.new(-2089.9, 4536.9, -14800.0) },
}
M.bosses = {
    { name = "Chef", pos = Vector3.new(-1120.5, 54.7, 4121.2) },
    { name = "Yeti", pos = Vector3.new(1181.7, 104.0, -1616.9) },
    { name = "Mob Boss", pos = Vector3.new(-2880.7, 6.7, 5430.9) },
    { name = "Saber Expert", pos = Vector3.new(-1527.2, 34.1, -33.2) },
    { name = "Warden", pos = Vector3.new(5623.2, 1.4, 733.8) },
    { name = "Magma General", pos = Vector3.new(-5625.7, 55.4, 8623.0) },
    { name = "Fishman Lord", pos = Vector3.new(61352.9, 67.2, 1029.1) },
    { name = "Sky Warlord", pos = Vector3.new(-6271.6, 5472.8, 1887.8) },
    { name = "Cyborg", pos = Vector3.new(6252.4, 9.3, 4941.4) },
    { name = "Ice Admiral", pos = Vector3.new(1212.4, 20.4, -1429.6) },
}

function M.hrp() local ch = LP and LP.Character; return ch and ch:FindFirstChild("HumanoidRootPart") end
function M.cancel() if M._tween then pcall(function() M._tween:Cancel() end); M._tween = nil end end

function M.go(pos)
    local hrp = M.hrp()
    if not hrp then return end
    local dist = (hrp.Position - pos).Magnitude
    local t = math.clamp(dist / math.max(M.config.speed, 1), 0.05, 90)
    M.cancel()
    local tw = TweenService:Create(hrp, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = CFrame.new(pos) })
    M._tween = tw
    tw.Completed:Connect(function() if M._tween == tw then M._tween = nil end end)
    tw:Play()
    if M._core then M._core.info("fly ->", pos) end
    return tw
end

M.secondSea = { captain = Vector3.new(-1130.2, 9.2, 1714.9), level = 700 }

local function commF()
    local r = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    return r and r:FindFirstChild("CommF_")
end
local function playerLevel()
    local ok, lv = pcall(function() return LP.Data.Level.Value end)
    return (ok and lv) or 0
end

function M.setAutoSecondSea(on)
    M._seaOn = on
    if not (on and M._core) then return end
    M._core.spawn(function()
        local function finish(msg)
            if msg and M._ui then M._ui.notify(msg) end
            M._seaOn = false
            if M._seaToggle and M._seaToggle.Get() then M._seaToggle.Set(false) end
        end
        local lv = playerLevel()
        if lv < M.secondSea.level then
            finish(("Auto Second Sea: requires level %d (you are %d)"):format(M.secondSea.level, lv))
            return
        end
        M.go(M.secondSea.captain + Vector3.new(0, 4, 0))
        for _ = 1, 80 do
            if not M._seaOn then return end
            local h = M.hrp()
            if h and (h.Position - M.secondSea.captain).Magnitude < 25 then break end
            task.wait(0.25)
        end
        local c = commF()
        if c then
            local ok, res = pcall(function() return c:InvokeServer("TravelDressrosa") end)
            if M._core then M._core.info("Auto Second Sea", "TravelDressrosa", "ok=" .. tostring(ok), tostring(res)) end
            finish("Traveling to the Second Sea...")
        else
            finish("Auto Second Sea: remote missing")
        end
    end)
end

M.thirdSea = { level = 1500 }
function M.setAutoThirdSea(on)
    M._sea3On = on
    if not (on and M._core) then return end
    M._core.spawn(function()
        local function finish(msg)
            if msg and M._ui then M._ui.notify(msg) end
            M._sea3On = false
            if M._sea3Toggle and M._sea3Toggle.Get() then M._sea3Toggle.Set(false) end
        end
        local lv = playerLevel()
        if lv < M.thirdSea.level then
            finish(("Auto Third Sea: requires level %d (you are %d)"):format(M.thirdSea.level, lv))
            return
        end
        local c = commF()
        if c then
            local ok, res = pcall(function() return c:InvokeServer("TravelZou") end)
            if M._core then M._core.info("Auto Third Sea", "TravelZou", "ok=" .. tostring(ok), tostring(res)) end
            finish("Traveling to the Third Sea...")
        else
            finish("Auto Third Sea: remote missing")
        end
    end)
end

function M.stop() M.cancel(); M._seaOn, M._sea3On = false, false end

function M.init(Core, UI)
    M._core, M._ui = Core, UI

    -- During a tween: zero velocity + noclip. Never Anchor the char — BF then rejects every hit.
    Core.track(RunService.Heartbeat:Connect(function()
        if M._tween then
            local ch = LP.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
            if ch then
                for _, part in ipairs(ch:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
                end
            end
        end
    end))

    local page = UI.page("Teleport")

    UI.button(page, "Notify current position", "Show and log your coordinates", function()
        local hrp = M.hrp()
        if not hrp then UI.notify("No character"); return end
        local p = hrp.Position
        UI.notify(("X %.1f   Y %.1f   Z %.1f"):format(p.X, p.Y, p.Z))
        Core.info("pos", ("%.1f, %.1f, %.1f"):format(p.X, p.Y, p.Z))
    end)

    UI.button(page, "Set Spawn Here", "Set your respawn point to this location", function()
        local c = commF()
        if not c then UI.notify("Remote missing"); return end
        local ok, res = pcall(function() return c:InvokeServer("SetSpawnPoint") end)
        local done = ok and res ~= 0 and res ~= nil
        UI.notify(done and "Spawn point set here" or "Set spawn failed (too far from a spawn?)")
        Core.info("SetSpawnPoint", "ok=" .. tostring(ok), tostring(res))
    end)

    local groups = {}
    local function goList(sea, section, label, hint, list)
        local g = groups[sea]; if not g then g = {}; groups[sea] = g end
        g[#g + 1] = UI.section(page, section)
        local names = {}
        for _, e in ipairs(list) do names[#names + 1] = e.name end
        local dd = UI.dropdown(page, label, hint, names, function(_) end)
        g[#g + 1] = dd.frame
        local btn = UI.button(page, "Go to " .. label:lower(), "Fly there", function()
            for _, e in ipairs(list) do if e.name == dd.Get() then M.go(e.pos + Vector3.new(0, 5, 0)); break end end
        end)
        g[#g + 1] = btn.Parent
    end

    goList("Sea1", "ISLANDS", "Island", "Fly to an island", M.islands)
    goList("Sea1", "BOSSES", "Boss", "Fly to a boss", M.bosses)
    goList("Sea2", "ISLANDS", "Island 2", "Fly to an island", M.islands2)
    goList("Sea2", "BOSSES", "Boss 2", "Fly to a boss", M.bosses2)
    goList("Sea3", "ISLANDS", "Island 3", "Fly to an island", M.islands3)
    goList("Sea3", "BOSSES", "Boss 3", "Fly to a boss", M.bosses3)

    UI.onSea(function(sea)
        for s, g in pairs(groups) do
            for _, fr in ipairs(g) do fr.Visible = (s == sea) end
        end
    end)

    UI.section(page, "WAYPOINTS")
    local function addBtn(w) UI.button(page, "Go: " .. w.name, "Saved waypoint", function() M.go(w.pos) end) end
    for _, w in ipairs(M.waypoints) do addBtn(w) end
    local nameBox = UI.textbox(page, "New waypoint name...")
    UI.button(page, "Save current position", "Store your position as a waypoint", function()
        local hrp = M.hrp()
        if not hrp then UI.notify("No character"); return end
        local name = (nameBox.Text ~= "" and nameBox.Text) or ("WP " .. (#M.waypoints + 1))
        local w = { name = name, pos = hrp.Position }
        M.waypoints[#M.waypoints + 1] = w
        addBtn(w); nameBox.Text = ""
        UI.notify("Saved: " .. name)
    end)

    local seaPage = UI.page("Sea")
    if seaPage then
        UI.section(seaPage, "SECOND SEA")
        M._seaToggle = UI.toggle(seaPage, "Auto Second Sea",
            "Fly to the Experienced Captain and sail to Sea 2 (requires Lv 700)", false,
            function(s) M.setAutoSecondSea(s) end)
        UI.button(seaPage, "Go to Experienced Captain", "Fly to the Sea 2 ferry NPC", function()
            M.go(M.secondSea.captain + Vector3.new(0, 4, 0))
        end)
        UI.section(seaPage, "THIRD SEA")
        M._sea3Toggle = UI.toggle(seaPage, "Auto Third Sea",
            "Sail from Sea 2 to Sea 3 via Mr. Captain (requires Lv 1500)", false,
            function(s) M.setAutoThirdSea(s) end)
    end

    Core.register("teleport", M)
    return M
end

return M
end)()

genv.__BF_COMBAT = (function()
-- Combat: auto-attack, kill aura, aimbot, bounty hunt.
-- Hits = RegisterAttack + RegisterHit, both need a server-validated hitId (see installCapture).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer

local M = {}
M.config = {
    range = 120, delay = 0.15,
    targetPlayers = true, playerRange = 60,
    fast = false,
    auraRange = 60, losCheck = true,
    aimSmooth = 0.15,
    clickInterval = 0.25,
    keys = { Z = true, X = true, C = false, V = false, F = false },
    followDist = 6, attack1v1 = false,
    spectate = false, aim = false,
}
M.lastHitId = nil
M._combo, M._hooked = 0, false
M._mobAuto, M._playerAuto, M._aura, M._autoClick, M._follow = false, false, false, false, false
M._wasSpectate = false

M.bounty = {
    noFriends = true, noCup = true,
    safePct = 20,
    invisKen = false,
    chatKill = false, chatMsg = "gg",
    maxTime = 20,
    team = "Both",
    method = "Nearest",
}
M._bountyOn, M._noStunOn = false, false
M._bountySkip = {}

local function net()
    local mods = RS:FindFirstChild("Modules")
    local n = mods and mods:FindFirstChild("Net")
    if not n then return end
    return n:FindFirstChild("RE/RegisterAttack"), n:FindFirstChild("RE/RegisterHit")
end
local function effDelay() return M.config.fast and 0.08 or M.config.delay end

function M.hrp() local ch = LP and LP.Character; return ch and ch:FindFirstChild("HumanoidRootPart") end

local function isFishingRod(t)
    if not t then return false end
    local tip = t.ToolTip
    return (tip and (tostring(tip):find("Fishing") or tostring(tip):find("Rod"))) or t.Name:find("Rod") ~= nil
end
-- A fishing rod hijacks the RegisterAttack hook, so hits never land: unequip it before attacking.
local function ensureNotRod()
    local ch = LP.Character
    local eq = ch and ch:FindFirstChildOfClass("Tool")
    if eq and isFishingRod(eq) then
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:UnequipTools() end) end
    end
end

local function losClear(fromPos, part, ignore)
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Exclude
    p.FilterDescendantsInstances = { LP.Character, ignore }
    return workspace:Raycast(fromPos, part.Position - fromPos, p) == nil
end

-- Steal a valid hitId from the game's own RegisterHit call. A forged id is rejected on fresh
-- accounts, so we hook __namecall and read the real one the client sends.
function M.installCapture()
    if M._hooked then return end
    if not (hookmetamethod and getnamecallmethod and checkcaller and newcclosure) then
        if M._core then M._core.warn("no hook API: hitId capture unavailable") end
        return
    end
    local _, RegisterHit = net()
    M._capturing = true
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if M._capturing and not checkcaller() and getnamecallmethod() == "FireServer" and self == RegisterHit then
            local a = table.pack(...)
            if a[4] ~= nil then M.lastHitId = a[4]
            elseif a.n == 1 and type(a[1]) == "string" then M.lastHitId = a[1] end
        end
        return old(self, ...)
    end))
    M._hooked = true
end

local function isRaidChip(t) return t.Name:find("Microchip") ~= nil end
local function reequipWeapon()
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local tool = ch:FindFirstChildOfClass("Tool")
    if tool and (isFishingRod(tool) or isRaidChip(tool)) then tool = nil end
    if not tool then
        local bp = LP:FindFirstChild("Backpack")
        if bp then for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and not isFishingRod(t) and not isRaidChip(t) then tool = t; break end
        end end
    end
    if tool then
        pcall(function() hum:UnequipTools() end)
        task.wait(0.15)
        pcall(function() hum:EquipTool(tool) end)
    end
end
function M.setupHitId()
    M.installCapture()
    task.spawn(function()
        ensureNotRod()
        reequipWeapon()
        task.wait(0.5)
        if M.lastHitId then
            if M._core then M._core.info("hitId captured", tostring(M.lastHitId)) end
            return
        end
        local _, RegisterHit = net()
        if RegisterHit then
            local id = tostring(LP.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15)
            pcall(function() RegisterHit:FireServer(id) end)
            M.lastHitId = id
            if M._core then M._core.warn("hitId fallback generated", tostring(id)) end
        end
    end)
end

function M.nearest(range)
    local hrp, folder = M.hrp(), workspace:FindFirstChild("Enemies")
    if not hrp or not folder then return end
    local best, bestD
    for _, e in ipairs(folder:GetChildren()) do
        local hum = e:FindFirstChildOfClass("Humanoid")
        local part = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
        if hum and hum.Health > 0 and part then
            local d = (part.Position - hrp.Position).Magnitude
            if d <= range and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    return best
end

function M.nearestAny(range)
    local h = M.hrp(); if not h then return end
    local best, bestD
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Humanoid") and d.Health > 0 then
            local model = d.Parent
            if model and model ~= LP.Character and not Players:GetPlayerFromCharacter(model) then
                local part = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                if part then
                    local dd = (part.Position - h.Position).Magnitude
                    if dd <= (range or 1e9) and (not bestD or dd < bestD) then best, bestD = model, dd end
                end
            end
        end
    end
    return best
end

function M.nearestPlayer(range)
    local h = M.hrp()
    if not h then return end
    local best, bestD
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = p ~= LP and p.Character
        local ph = ch and ch:FindFirstChild("HumanoidRootPart")
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if ph and hum and hum.Health > 0 then
            local d = (ph.Position - h.Position).Magnitude
            if (not range or d <= range) and (not bestD or d < bestD) then best, bestD = ch, d end
        end
    end
    return best
end

function M.attackOnce(enemy)
    ensureNotRod()
    local RegisterAttack, RegisterHit = net()
    if not (RegisterAttack and RegisterHit and enemy) then return end
    local part = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
        or enemy:FindFirstChildWhichIsA("BasePart")
    if not part then return end
    M._combo = (M._combo % 4) + 1
    RegisterAttack:FireServer(0.4, M._combo)
    RegisterHit:FireServer(part, {}, nil, M.lastHitId)   -- 4th arg = captured hitId; without it the hit is ignored
end

function M.attackMany(list)
    ensureNotRod()
    local RegisterAttack, RegisterHit = net()
    if not (RegisterAttack and RegisterHit) or #list == 0 then return end
    M._combo = (M._combo % 4) + 1
    RegisterAttack:FireServer(0.4, M._combo)
    for _, e in ipairs(list) do
        local part = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
        if part then RegisterHit:FireServer(part, {}, nil, M.lastHitId) end
    end
end

function M.playersInRange(range)
    local h, list = M.hrp(), {}
    if not h then return list end
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = p ~= LP and p.Character
        local ph = ch and ch:FindFirstChild("HumanoidRootPart")
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if ph and hum and hum.Health > 0 and (ph.Position - h.Position).Magnitude <= range then
            list[#list + 1] = ch
        end
    end
    return list
end
function M.attackPlayersInRange(range)
    for _, ch in ipairs(M.playersInRange(range)) do M.attackOnce(ch) end
end

function M.setMobAuto(on)
    M._mobAuto = on and true or false
    if M._mobAuto and M._core then
        M._core.spawn(function()
            while M._mobAuto do
                M.attackOnce(M.nearest(M.config.range))
                task.wait(effDelay())
            end
        end)
    end
end

function M.setPlayerAuto(on)
    M._playerAuto = on and true or false
    if M._playerAuto and M._core then
        M._core.spawn(function()
            while M._playerAuto do
                M.attackPlayersInRange(M.config.playerRange)
                task.wait(effDelay())
            end
        end)
    end
end

function M.setAura(on)
    M._aura = on and true or false
    if M._aura and M._core then
        M._core.spawn(function()
            while M._aura do
                local h, folder = M.hrp(), workspace:FindFirstChild("Enemies")
                if h and folder then
                    local list = {}
                    for _, e in ipairs(folder:GetChildren()) do
                        local hum = e:FindFirstChildOfClass("Humanoid")
                        local part = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
                        if hum and hum.Health > 0 and part and (part.Position - h.Position).Magnitude <= M.config.auraRange then
                            if not M.config.losCheck or losClear(h.Position, part, e) then list[#list + 1] = e end
                        end
                    end
                    M.attackMany(list)
                end
                if M.config.targetPlayers then M.attackPlayersInRange(M.config.auraRange) end
                task.wait(effDelay())
            end
        end)
    end
end

function M.pressKey(name)
    local kc = Enum.KeyCode[name]
    if not kc then return end
    pcall(function()
        VIM:SendKeyEvent(true, kc, false, game)
        task.wait(0.03)
        VIM:SendKeyEvent(false, kc, false, game)
    end)
end
function M.setAutoClick(on)
    M._autoClick = on and true or false
    if M._autoClick and M._core then
        M._core.spawn(function()
            while M._autoClick do
                for k, enabled in pairs(M.config.keys) do
                    if not M._autoClick then break end
                    if enabled then M.pressKey(k) end
                end
                task.wait(M.config.clickInterval)
            end
        end)
    end
end

function M.setFollow(on)
    M._follow = on and true or false
    if M._follow and M._core then
        M._core.spawn(function()
            while M._follow do
                local tp = M._core.modules.teleport
                local ch = M.nearestPlayer()
                local ph = ch and ch:FindFirstChild("HumanoidRootPart")
                if tp and ph then tp.go(ph.Position + ph.CFrame.LookVector * -M.config.followDist) end
                if M.config.attack1v1 and ch then M.attackOnce(ch) end
                task.wait(0.3)
            end
        end)
    end
end

local function myHealthPct()
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if hum and hum.MaxHealth > 0 then return hum.Health / hum.MaxHealth * 100 end
    return 100
end
local function holdingCup(ch)
    for _, t in ipairs(ch:GetChildren()) do if t:IsA("Tool") and t.Name == "Cup" then return true end end
    return false
end
local function bountyValid(p)
    if p == LP then return false end
    local ch = p.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local ph = ch and ch:FindFirstChild("HumanoidRootPart")
    if not (hum and ph and hum.Health > 0) then return false end
    if M.bounty.noFriends then
        local ok, f = pcall(function() return LP:IsFriendsWith(p.UserId) end)
        if ok and f then return false end
    end
    if M.bounty.noCup and holdingCup(ch) then return false end
    if M.bounty.team ~= "Both" and p.Team and p.Team.Name:lower():find(M.bounty.team:lower()) == nil then return false end
    local sk = M._bountySkip[p.UserId]
    if sk and sk > os.clock() then return false end
    return true
end
local function pickBounty()
    local h = M.hrp(); if not h then return end
    local best, bestScore
    for _, p in ipairs(Players:GetPlayers()) do
        if bountyValid(p) then
            local ch = p.Character
            local ph, hum = ch:FindFirstChild("HumanoidRootPart"), ch:FindFirstChildOfClass("Humanoid")
            local score = (M.bounty.method == "Lowest HP") and hum.Health or (ph.Position - h.Position).Magnitude
            if not bestScore or score < bestScore then best, bestScore = p, score end
        end
    end
    return best
end
function M.chat(msg)
    pcall(function()
        local TCS = game:GetService("TextChatService")
        if TCS.ChatVersion == Enum.ChatVersion.TextChatService then
            TCS.TextChannels.RBXGeneral:SendAsync(msg)
        else
            RS.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
        end
    end)
end
function M.setNoStun(on)
    M._noStunOn = on and true or false
    if M._noStunOn and M._core then
        M._core.spawn(function()
            while M._noStunOn do
                local ch = LP.Character
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if ch and hum then
                    if hum.PlatformStand then hum.PlatformStand = false end
                    for _, a in ipairs({ "Stun", "Stunned" }) do
                        if ch:GetAttribute(a) then ch:SetAttribute(a, false) end
                    end
                end
                task.wait(0.1)
            end
        end)
    end
end
function M.setBounty(on)
    M._bountyOn = on and true or false
    if not (M._bountyOn and M._core) then return end
    M._core.spawn(function()
        local tp = M._core.modules.teleport
        while M._bountyOn do
            if myHealthPct() < M.bounty.safePct then
                local h = M.hrp()
                if tp and h then tp.go(h.Position + Vector3.new(0, 220, 0)) end
                if M._ui then M._ui.notify("Safe zone: low HP, retreating") end
                task.wait(1.2)
            else
                local target = pickBounty()
                if not target then task.wait(0.5) else
                    local start = os.clock()
                    while M._bountyOn and (os.clock() - start) < M.bounty.maxTime do
                        if myHealthPct() < M.bounty.safePct then break end
                        local ch = target.Character
                        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                        local ph = ch and ch:FindFirstChild("HumanoidRootPart")
                        if not (ch and hum and ph and hum.Health > 0) then
                            if M.bounty.chatKill then M.chat(M.bounty.chatMsg) end
                            break
                        end
                        local off = M.config.followDist
                        local dest = ph.Position + ph.CFrame.LookVector * -off + Vector3.new(0, M.bounty.invisKen and 4 or 0, 0)
                        if tp then tp.go(dest) end
                        M.attackOnce(ch)
                        task.wait(effDelay())
                    end
                    if os.clock() - start >= M.bounty.maxTime then M._bountySkip[target.UserId] = os.clock() + 8 end
                end
            end
        end
    end)
end

function M.stop()
    M._mobAuto, M._playerAuto, M._aura, M._autoClick, M._follow, M._capturing = false, false, false, false, false, false
    M._bountyOn, M._noStunOn = false, false
    M.config.aim, M.config.spectate = false, false
    local cam = workspace.CurrentCamera
    local myHum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if cam and myHum then cam.CameraSubject = myHum end
end

function M.init(Core, UI)
    M._core = Core
    M.installCapture()

    Core.track(RunService.RenderStepped:Connect(function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if M.config.aim then
            local ch = M.nearestPlayer()
            local ph = ch and ch:FindFirstChild("HumanoidRootPart")
            if ph then
                cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, ph.Position), M.config.aimSmooth)
            end
        end
        if M.config.spectate then
            local ch = M.nearestPlayer()
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hum then cam.CameraSubject = hum; M._wasSpectate = true end
        elseif M._wasSpectate then
            local myHum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if myHum then cam.CameraSubject = myHum end
            M._wasSpectate = false
        end
    end))

    local page = UI.page("PVP")
    UI.toggle(page, "Auto attack players", "Attack the nearby players", false, function(s) M.setPlayerAuto(s) end)
    UI.slider(page, "Player range", "Player detection radius", 10, 200, M.config.playerRange, function(v) M.config.playerRange = v end)
    UI.toggle(page, "Fast attack", "Minimum delay between hits", M.config.fast, function(s) M.config.fast = s end)
    UI.toggle(page, "Attack players while farming", "Hit nearby players during auto-farm too", M.config.targetPlayers, function(s) M.config.targetPlayers = s end)

    UI.section(page, "KILL AURA")
    UI.toggle(page, "Kill aura", "Hit everything in range (mobs + players)", false, function(s) M.setAura(s) end)
    UI.slider(page, "Aura range", "Radius", 10, 200, M.config.auraRange, function(v) M.config.auraRange = v end)
    UI.toggle(page, "Line of sight", "Only hit visible targets", M.config.losCheck, function(s) M.config.losCheck = s end)

    UI.section(page, "AIMBOT")
    UI.toggle(page, "Aimbot", "Lock camera on the nearest player", false, function(s) M.config.aim = s end)
    UI.slider(page, "Smoothness", "Lower = smoother", 3, 100, math.floor(M.config.aimSmooth * 100), function(v) M.config.aimSmooth = v / 100 end)

    UI.section(page, "AUTO SKILLS")
    UI.toggle(page, "Auto skills", "Auto-press the skill keys", false, function(s) M.setAutoClick(s) end)
    for _, k in ipairs({ "Z", "X", "C", "V", "F" }) do
        UI.toggle(page, "Key " .. k, "Include " .. k .. " in the rotation", M.config.keys[k], function(s) M.config.keys[k] = s end)
    end
    UI.slider(page, "Skill interval (ms)", "Delay between key series", 100, 1000, math.floor(M.config.clickInterval * 1000), function(v) M.config.clickInterval = v / 1000 end)

    UI.section(page, "PLAYERS")
    UI.toggle(page, "Follow nearest", "Teleport onto the nearest player", false, function(s) M.setFollow(s) end)
    UI.toggle(page, "1v1 (attack target)", "Attack the followed player", false, function(s) M.config.attack1v1 = s end)
    UI.toggle(page, "Spectate nearest", "Camera on the nearest player", false, function(s) M.config.spectate = s end)
    UI.button(page, "Show captured hit id", "hitId from your last real M1", function()
        UI.notify(M.lastHitId and ("hitId: " .. tostring(M.lastHitId)) or "No hitId yet — do one real M1")
    end)

    UI.section(page, "AUTO BOUNTY V4")
    UI.toggle(page, "Auto Bounty", "Hunt players (fly to target, attack, guards)", false, function(s) M.setBounty(s) end)
    UI.dropdown(page, "Target team", "Which team to hunt", { "Both", "Pirates", "Marines" }, function(s) M.bounty.team = s end)
    UI.dropdown(page, "Farm method", "How to pick the target", { "Nearest", "Lowest HP" }, function(s) M.bounty.method = s end)
    UI.toggle(page, "Don't attack friends", "Skip your Roblox friends", M.bounty.noFriends, function(s) M.bounty.noFriends = s end)
    UI.toggle(page, "Don't attack Cup holders", "Skip players holding a Cup (truce)", M.bounty.noCup, function(s) M.bounty.noCup = s end)
    UI.toggle(page, "No stun", "Counter stun (PlatformStand / stun attributes)", false, function(s) M.setNoStun(s) end)
    UI.toggle(page, "Invisible from Ken", "Best-effort: strike from behind/above", M.bounty.invisKen, function(s) M.bounty.invisKen = s end)
    UI.toggle(page, "Chat after kill", "Send a message when a target dies", M.bounty.chatKill, function(s) M.bounty.chatKill = s end)
    UI.textbox(page, "Kill message (default: gg)", function(t) M.bounty.chatMsg = (t ~= "" and t) or "gg" end)
    UI.slider(page, "Safe zone HP %", "Retreat below this health", 0, 100, M.bounty.safePct, function(v) M.bounty.safePct = v end)
    UI.slider(page, "Max time on target (s)", "Switch after this many seconds", 5, 60, M.bounty.maxTime, function(v) M.bounty.maxTime = v end)

    Core.register("combat", M)
    return M
end

return M
end)()

genv.__BF_FARM = (function()
-- Farm: level auto-farm. Flies to the quest mob's spawn (not just the nearest enemy) and
-- attacks through Combat. Mob/quest lists are per-sea (currentList picks by the detected sea).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local M = {}
M.config = {
    questInterval = 5, attackInterval = 0.2, heightOffset = 12,
    hoverRange = 250,
    bring = false,
    equip = false, equipType = "Melee",
    stat = "Melee", statAmount = 1,
}
M._mobName = nil
M._anchor, M._collecting = nil, false
M._fruitSkip = setmetatable({}, { __mode = "k" })
M._fruitTries = setmetatable({}, { __mode = "k" })
M._decollided = setmetatable({}, { __mode = "k" })
M.stats = { "Melee", "Defense", "Sword", "Gun", "Blox Fruit" }

M.sea1 = {
    { id = "BanditQuest1",  tier = 1, level = 1,   mob = "Bandit",              label = "Bandit (Lv 1)" },
    { id = "JungleQuest",   tier = 1, level = 10,  mob = "Monkey",              label = "Monkey (Lv 10)" },
    { id = "JungleQuest",   tier = 2, level = 15,  mob = "Gorilla",             label = "Gorilla (Lv 15)" },
    { id = "BuggyQuest1",   tier = 1, level = 30,  mob = "Pirate",              label = "Pirate (Lv 30)" },
    { id = "BuggyQuest1",   tier = 2, level = 40,  mob = "Brute",               label = "Brute (Lv 40)" },
    { id = "DesertQuest",   tier = 1, level = 60,  mob = "Desert Bandit",       label = "Desert Bandit (Lv 60)" },
    { id = "DesertQuest",   tier = 2, level = 75,  mob = "Desert Officer",      label = "Desert Officer (Lv 75)" },
    { id = "SnowQuest",     tier = 1, level = 90,  mob = "Snow Bandit",         label = "Snow Bandit (Lv 90)" },
    { id = "SnowQuest",     tier = 2, level = 100, mob = "Snowman",             label = "Snowman (Lv 100)" },
    { id = "MarineQuest2",  tier = 1, level = 120, mob = "Chief Petty Officer", label = "Chief Petty Officer (Lv 120)" },
    { id = "MarineQuest2",  tier = 2, level = 130, mob = "Vice Admiral",        label = "Vice Admiral (Lv 130)" },
    { id = "SkyQuest",      tier = 1, level = 150, mob = "Sky Bandit",          label = "Sky Bandit (Lv 150)" },
    { id = "SkyQuest",      tier = 2, level = 175, mob = "Dark Master",         label = "Dark Master (Lv 175)" },
    { id = "PrisonerQuest", tier = 1, level = 190, mob = "Prisoner",            label = "Prisoner (Lv 190)" },
    { id = "PrisonerQuest", tier = 2, level = 210, mob = "Dangerous Prisoner",  label = "Dangerous Prisoner (Lv 210)" },
    { id = "ColosseumQuest",tier = 1, level = 250, mob = "Toga Warrior",        label = "Toga Warrior (Lv 250)" },
    { id = "ColosseumQuest",tier = 2, level = 275, mob = "Gladiator",           label = "Gladiator (Lv 275)" },
    { id = "MagmaQuest",    tier = 1, level = 300, mob = "Military Soldier",    label = "Military Soldier (Lv 300)" },
    { id = "MagmaQuest",    tier = 2, level = 325, mob = "Military Spy",        label = "Military Spy (Lv 325)" },
    { id = "FishmanQuest",  tier = 1, level = 375, mob = "Fishman Warrior",     label = "Fishman Warrior (Lv 375)" },
    { id = "FishmanQuest",  tier = 2, level = 400, mob = "Fishman Commando",    label = "Fishman Commando (Lv 400)" },
    { id = "SkyExp1Quest",  tier = 1, level = 450, mob = "God's Guard",         label = "God's Guard (Lv 450)" },
    { id = "SkyExp1Quest",  tier = 2, level = 475, mob = "Shanda",             label = "Shanda (Lv 475)" },
    { id = "SkyExp2Quest",  tier = 1, level = 525, mob = "Royal Squad",        label = "Royal Squad (Lv 525)" },
    { id = "SkyExp2Quest",  tier = 2, level = 550, mob = "Royal Soldier",      label = "Royal Soldier (Lv 550)" },
    { id = "FountainQuest", tier = 1, level = 625, mob = "Galley Pirate",      label = "Galley Pirate (Lv 625)" },
    { id = "FountainQuest", tier = 2, level = 650, mob = "Galley Captain",     label = "Galley Captain (Lv 650)" },
}
M.sea2 = {
    { id = "Area1Quest",       tier = 1, level = 700,  mob = "Raider",             label = "Raider (Lv 700)" },
    { id = "Area1Quest",       tier = 2, level = 725,  mob = "Mercenary",          label = "Mercenary (Lv 725)" },
    { id = "Area2Quest",       tier = 1, level = 775,  mob = "Swan Pirate",        label = "Swan Pirate (Lv 775)" },
    { id = "Area2Quest",       tier = 2, level = 800,  mob = "Factory Staff",      label = "Factory Staff (Lv 800)" },
    { id = "MarineQuest3",     tier = 1, level = 875,  mob = "Marine Lieutenant",  label = "Marine Lieutenant (Lv 875)" },
    { id = "MarineQuest3",     tier = 2, level = 900,  mob = "Marine Captain",     label = "Marine Captain (Lv 900)" },
    { id = "ZombieQuest",      tier = 1, level = 950,  mob = "Zombie",             label = "Zombie (Lv 950)" },
    { id = "ZombieQuest",      tier = 2, level = 975,  mob = "Vampire",            label = "Vampire (Lv 975)" },
    { id = "SnowMountainQuest",tier = 1, level = 1000, mob = "Snow Trooper",       label = "Snow Trooper (Lv 1000)" },
    { id = "SnowMountainQuest",tier = 2, level = 1050, mob = "Winter Warrior",     label = "Winter Warrior (Lv 1050)" },
    { id = "IceSideQuest",     tier = 1, level = 1100, mob = "Lab Subordinate",    label = "Lab Subordinate (Lv 1100)" },
    { id = "IceSideQuest",     tier = 2, level = 1125, mob = "Horned Warrior",     label = "Horned Warrior (Lv 1125)" },
    { id = "FireSideQuest",    tier = 1, level = 1175, mob = "Magma Ninja",        label = "Magma Ninja (Lv 1175)" },
    { id = "FireSideQuest",    tier = 2, level = 1200, mob = "Lava Pirate",        label = "Lava Pirate (Lv 1200)" },
    { id = "ShipQuest1",       tier = 1, level = 1250, mob = "Ship Deckhand",      label = "Ship Deckhand (Lv 1250)" },
    { id = "ShipQuest1",       tier = 2, level = 1275, mob = "Ship Engineer",      label = "Ship Engineer (Lv 1275)" },
    { id = "ShipQuest2",       tier = 1, level = 1300, mob = "Ship Steward",       label = "Ship Steward (Lv 1300)" },
    { id = "ShipQuest2",       tier = 2, level = 1325, mob = "Ship Officer",       label = "Ship Officer (Lv 1325)" },
    { id = "FrostQuest",       tier = 1, level = 1350, mob = "Arctic Warrior",     label = "Arctic Warrior (Lv 1350)" },
    { id = "FrostQuest",       tier = 2, level = 1375, mob = "Snow Lurker",        label = "Snow Lurker (Lv 1375)" },
    { id = "ForgottenQuest",   tier = 1, level = 1425, mob = "Sea Soldier",        label = "Sea Soldier (Lv 1425)" },
    { id = "ForgottenQuest",   tier = 2, level = 1450, mob = "Water Fighter",      label = "Water Fighter (Lv 1450)" },
    { id = "BartiloQuest",     tier = 1, level = 775,  mob = "Swan Pirate",        kills = 50, label = "Bartilo Quest (50 Swan Pirates)" },
}
M.sea3 = {
    { id = "PiratePortQuest",    tier = 1, level = 1500, mob = "Pirate Millionaire",    label = "Pirate Millionaire (Lv 1500)" },
    { id = "PiratePortQuest",    tier = 2, level = 1525, mob = "Pistol Billionaire",    label = "Pistol Billionaire (Lv 1525)" },
    { id = "DragonCrewQuest",    tier = 1, level = 1575, mob = "Dragon Crew Warrior",   label = "Dragon Crew Warrior (Lv 1575)" },
    { id = "VenomCrewQuest",     tier = 4, level = 1700, mob = "Marine Commodore",      label = "Marine Commodore (Lv 1700)" },
    { id = "VenomCrewQuest",     tier = 5, level = 1725, mob = "Marine Rear Admiral",   label = "Marine Rear Admiral (Lv 1725)" },
    { id = "VenomCrewQuest",     tier = 7, level = 1775, mob = "Fishman Raider",        label = "Fishman Raider (Lv 1775)" },
    { id = "VenomCrewQuest",     tier = 8, level = 1800, mob = "Fishman Captain",       label = "Fishman Captain (Lv 1800)" },
    { id = "VenomCrewQuest",     tier = 9, level = 1825, mob = "Forest Pirate",         label = "Forest Pirate (Lv 1825)" },
    { id = "VenomCrewQuest",     tier = 10, level = 1850, mob = "Mythological Pirate",  label = "Mythological Pirate (Lv 1850)" },
    { id = "VenomCrewQuest",     tier = 12, level = 1900, mob = "Jungle Pirate",        label = "Jungle Pirate (Lv 1900)" },
    { id = "VenomCrewQuest",     tier = 13, level = 1925, mob = "Musketeer Pirate",     label = "Musketeer Pirate (Lv 1925)" },
    { id = "HauntedQuest1",      tier = 1, level = 1975, mob = "Reborn Skeleton",       label = "Reborn Skeleton (Lv 1975)" },
    { id = "HauntedQuest1",      tier = 2, level = 2000, mob = "Living Zombie",         label = "Living Zombie (Lv 2000)" },
    { id = "HauntedQuest2",      tier = 2, level = 2050, mob = "Posessed Mummy",        label = "Posessed Mummy (Lv 2050)" },
    { id = "NutsIslandQuest",    tier = 1, level = 2075, mob = "Peanut Scout",          label = "Peanut Scout (Lv 2075)" },
    { id = "NutsIslandQuest",    tier = 2, level = 2100, mob = "Peanut President",      label = "Peanut President (Lv 2100)" },
    { id = "IceCreamIslandQuest",tier = 1, level = 2125, mob = "Ice Cream Chef",        label = "Ice Cream Chef (Lv 2125)" },
    { id = "IceCreamIslandQuest",tier = 2, level = 2150, mob = "Ice Cream Commander",   label = "Ice Cream Commander (Lv 2150)" },
    { id = "CakeQuest2",         tier = 1, level = 2250, mob = "Baking Staff",          label = "Baking Staff (Lv 2250)" },
    { id = "CakeQuest2",         tier = 2, level = 2275, mob = "Head Baker",            label = "Head Baker (Lv 2275)" },
    { id = "ChocQuest1",         tier = 1, level = 2300, mob = "Cocoa Warrior",         label = "Cocoa Warrior (Lv 2300)" },
    { id = "ChocQuest1",         tier = 2, level = 2325, mob = "Chocolate Bar Battler", label = "Chocolate Bar Battler (Lv 2325)" },
    { id = "ChocQuest2",         tier = 1, level = 2350, mob = "Sweet Thief",           label = "Sweet Thief (Lv 2350)" },
    { id = "ChocQuest2",         tier = 2, level = 2375, mob = "Candy Rebel",           label = "Candy Rebel (Lv 2375)" },
    { id = "CandyQuest1",        tier = 1, level = 2400, mob = "Candy Pirate",          label = "Candy Pirate (Lv 2400)" },
    { id = "CandyQuest1",        tier = 2, level = 2425, mob = "Snow Demon",            label = "Snow Demon (Lv 2425)" },
    { id = "TikiQuest1",         tier = 1, level = 2450, mob = "Isle Outlaw",           label = "Isle Outlaw (Lv 2450)" },
    { id = "TikiQuest1",         tier = 2, level = 2475, mob = "Island Boy",            label = "Island Boy (Lv 2475)" },
    { id = "TikiQuest2",         tier = 1, level = 2500, mob = "Sun-kissed Warrior",    label = "Sun-kissed Warrior (Lv 2500)" },
    { id = "TikiQuest2",         tier = 2, level = 2525, mob = "Isle Champion",         label = "Isle Champion (Lv 2525)" },
    { id = "TikiQuest3",         tier = 1, level = 2550, mob = "Serpent Hunter",        label = "Serpent Hunter (Lv 2550)" },
    { id = "TikiQuest3",         tier = 2, level = 2575, mob = "Skull Slayer",          label = "Skull Slayer (Lv 2575)" },
    { id = "SubmergedQuest1",    tier = 1, level = 2600, mob = "Reef Bandit",           label = "Reef Bandit (Lv 2600)" },
    { id = "SubmergedQuest1",    tier = 2, level = 2625, mob = "Coral Pirate",          label = "Coral Pirate (Lv 2625)" },
    { id = "SubmergedQuest2",    tier = 1, level = 2650, mob = "Sea Chanter",           label = "Sea Chanter (Lv 2650)" },
    { id = "SubmergedQuest2",    tier = 2, level = 2675, mob = "Ocean Prophet",         label = "Ocean Prophet (Lv 2675)" },
    { id = "SubmergedQuest3",    tier = 2, level = 2700, mob = "Grand Devotee",         label = "Grand Devotee (Lv 2700)" },
}
M.spawns = {
    ["Monkey"] = Vector3.new(-1866.3, 29.9, 21.6),
    ["Gorilla"] = Vector3.new(-1266.6, 14.5, -462.0),
    ["Pirate"] = Vector3.new(-981.0, 30.4, 3966.8),
    ["Brute"] = Vector3.new(-1085.9, 28.1, 4342.7),
    ["Desert Bandit"] = Vector3.new(999.9, 7.6, 4490.3),
    ["Desert Officer"] = Vector3.new(1523.8, 15.3, 4095.4),
    ["Snow Bandit"] = Vector3.new(1519.5, 78.0, -1510.9),
    ["Snowman"] = Vector3.new(1121.5, 98.2, -1669.0),
    ["Chief Petty Officer"] = Vector3.new(-4763.7, 13.4, 4288.8),
    ["Sky Bandit"] = Vector3.new(-4973.7, 280.7, -1119.4),
    ["Dark Master"] = Vector3.new(-5283.2, 505.1, -221.0),
    ["Prisoner"] = Vector3.new(5278.6, 7.1, 391.6),
    ["Dangerous Prisoner"] = Vector3.new(5058.3, 9.1, 900.9),
    ["Toga Warrior"] = Vector3.new(-1973.1, 9.0, -2744.9),
    ["Gladiator"] = Vector3.new(-1161.9, 11.6, -3097.2),
    ["Military Soldier"] = Vector3.new(-5623.8, 17.0, 8314.1),
    ["Military Spy"] = Vector3.new(-5952.5, 76.9, 8742.4),
    ["Fishman Warrior"] = Vector3.new(60736.8, 23.8, 1396.3),
    ["Fishman Commando"] = Vector3.new(61808.1, 24.6, 1328.6),
    ["God's Guard"] = Vector3.new(-4082.9, 1087.3, -414.1),
    ["Shanda"] = Vector3.new(-6040.2, 5468.0, 1734.2),
    ["Royal Squad"] = Vector3.new(-6706.9, 5551.4, 1155.4),
    ["Royal Soldier"] = Vector3.new(-7138.5, 5541.1, 1050.8),
    ["Galley Pirate"] = Vector3.new(5430.4, 78.0, 3953.6),
    ["Galley Captain"] = Vector3.new(5409.5, 77.7, 4687.0),
    ["Raider"] = Vector3.new(-612.4, 40.0, 2557.4),
    ["Mercenary"] = Vector3.new(-1135.9, 72.9, 1248.3),
    ["Swan Pirate"] = Vector3.new(1067.0, 72.8, 1080.9),
    ["Factory Staff"] = Vector3.new(386.1, 72.8, 91.8),
    ["Marine Lieutenant"] = Vector3.new(-2583.9, 71.0, -3039.6),
    ["Marine Captain"] = Vector3.new(-2103.9, 73.0, -3259.3),
    ["Zombie"] = Vector3.new(-5615.0, 49.3, -938.5),
    ["Vampire"] = Vector3.new(-6132.4, 9.0, -1466.2),
    ["Snow Trooper"] = Vector3.new(484.3, 400.8, -5472.4),
    ["Winter Warrior"] = Vector3.new(1226.3, 428.8, -5216.0),
    ["Lab Subordinate"] = Vector3.new(-5998.3, 90.0, -4386.5),
    ["Horned Warrior"] = Vector3.new(-6540.0, 29.2, -5718.0),
    ["Magma Ninja"] = Vector3.new(-5711.4, 47.4, -5658.5),
    ["Lava Pirate"] = Vector3.new(-5111.3, 32.2, -5115.9),
    ["Ship Deckhand"] = Vector3.new(1157.3, 125.6, 32930.1),
    ["Ship Engineer"] = Vector3.new(834.8, 43.7, 32720.9),
    ["Ship Steward"] = Vector3.new(801.4, 125.8, 33505.2),
    ["Ship Officer"] = Vector3.new(694.5, 179.9, 33112.6),
    ["Arctic Warrior"] = Vector3.new(6271.3, 27.6, -6151.5),
    ["Snow Lurker"] = Vector3.new(5524.2, 27.6, -6583.8),
    ["Sea Soldier"] = Vector3.new(-2550.9, 28.5, -9840.0),
    ["Water Fighter"] = Vector3.new(-3331.7, 239.1, -10553.4),
    ["Pirate Millionaire"] = Vector3.new(-232.9, 57.0, 5757.8),
    ["Pistol Billionaire"] = Vector3.new(-54.8, 83.8, 5947.8),
    ["Dragon Crew Warrior"] = Vector3.new(7217.8, 56.6, -680.8),
    ["Marine Commodore"] = Vector3.new(2577.3, 75.6, -7739.9),
    ["Marine Rear Admiral"] = Vector3.new(3920.1, 146.2, -7175.2),
    ["Fishman Raider"] = Vector3.new(-10223.1, 332.6, -8482.5),
    ["Fishman Captain"] = Vector3.new(-10736.7, 331.8, -8807.6),
    ["Forest Pirate"] = Vector3.new(-13105.5, 332.2, -7705.8),
    ["Mythological Pirate"] = Vector3.new(-13221.0, 519.1, -6689.0),
    ["Jungle Pirate"] = Vector3.new(-12321.3, 331.4, -10669.3),
    ["Musketeer Pirate"] = Vector3.new(-13556.1, 391.4, -9735.9),
    ["Reborn Skeleton"] = Vector3.new(-8710.1, 141.0, 6112.9),
    ["Living Zombie"] = Vector3.new(-10170.9, 141.2, 6159.6),
    ["Posessed Mummy"] = Vector3.new(-9399.6, 12.2, 6118.8),
    ["Peanut Scout"] = Vector3.new(-1924.0, 37.3, -10199.7),
    ["Peanut President"] = Vector3.new(-1993.4, 37.2, -10682.9),
    ["Ice Cream Chef"] = Vector3.new(-502.4, 64.6, -10873.8),
    ["Ice Cream Commander"] = Vector3.new(-366.8, 64.7, -11094.4),
    ["Baking Staff"] = Vector3.new(-1774.1, 34.7, -12850.5),
    ["Head Baker"] = Vector3.new(-2389.2, 51.0, -13018.3),
    ["Cocoa Warrior"] = Vector3.new(-128.7, 26.2, -12249.8),
    ["Chocolate Bar Battler"] = Vector3.new(598.8, 25.6, -12395.1),
    ["Sweet Thief"] = Vector3.new(-77.6, 25.6, -12765.6),
    ["Candy Rebel"] = Vector3.new(166.8, 25.6, -13035.3),
    ["Candy Pirate"] = Vector3.new(-1226.8, 36.3, -14777.6),
    ["Snow Demon"] = Vector3.new(-936.2, 14.0, -14552.5),
    ["Isle Outlaw"] = Vector3.new(-16351.8, 23.5, -282.5),
    ["Island Boy"] = Vector3.new(-16736.2, 22.2, -131.7),
    ["Sun-kissed Warrior"] = Vector3.new(-16413.5, 56.7, 1054.4),
    ["Isle Champion"] = Vector3.new(-16735.7, 23.3, 1110.6),
    ["Serpent Hunter"] = Vector3.new(-16536.0, 106.9, 1347.1),
    ["Skull Slayer"] = Vector3.new(-16829.4, 193.2, 1753.4),
    ["Reef Bandit"] = Vector3.new(10899.9, -2145.2, 9279.3),
    ["Coral Pirate"] = Vector3.new(10703.7, -2087.3, 9255.4),
    ["Sea Chanter"] = Vector3.new(10680.1, -2056.7, 9933.9),
    ["Ocean Prophet"] = Vector3.new(11129.8, -2007.8, 10051.5),
    ["Grand Devotee"] = Vector3.new(9559.2, -1994.4, 9798.7),
}
M.kills = {
    Bandit = 5, Monkey = 6, Gorilla = 8, Pirate = 8, Brute = 8,
    ["Desert Bandit"] = 8, ["Desert Officer"] = 6, ["Snow Bandit"] = 7, Snowman = 8,
    ["Chief Petty Officer"] = 8, ["Vice Admiral"] = 1, ["Sky Bandit"] = 7, ["Dark Master"] = 8,
    Prisoner = 8, ["Dangerous Prisoner"] = 8, ["Toga Warrior"] = 7, Gladiator = 8,
    ["Military Soldier"] = 7, ["Military Spy"] = 8, ["Fishman Warrior"] = 8, ["Fishman Commando"] = 7,
    Shanda = 9, ["Royal Squad"] = 8, ["Royal Soldier"] = 8, ["Galley Pirate"] = 8, ["Galley Captain"] = 9,
    Raider = 8, Mercenary = 8, ["Swan Pirate"] = 8, ["Factory Staff"] = 8,
    ["Marine Lieutenant"] = 8, ["Marine Captain"] = 9, Zombie = 8, Vampire = 8,
    ["Snow Trooper"] = 8, ["Winter Warrior"] = 9, ["Lab Subordinate"] = 8, ["Horned Warrior"] = 9,
    ["Magma Ninja"] = 8, ["Lava Pirate"] = 8, ["Ship Deckhand"] = 8, ["Ship Engineer"] = 8,
    ["Ship Steward"] = 8, ["Ship Officer"] = 8, ["Arctic Warrior"] = 8, ["Snow Lurker"] = 8,
    ["Sea Soldier"] = 8, ["Water Fighter"] = 8,
    ["Pirate Millionaire"] = 8, ["Pistol Billionaire"] = 8, ["Dragon Crew Warrior"] = 8,
    ["Marine Commodore"] = 8, ["Marine Rear Admiral"] = 8, ["Fishman Raider"] = 8, ["Fishman Captain"] = 8,
    ["Forest Pirate"] = 8, ["Mythological Pirate"] = 8, ["Jungle Pirate"] = 8, ["Musketeer Pirate"] = 8,
    ["Reborn Skeleton"] = 8, ["Living Zombie"] = 8, ["Posessed Mummy"] = 8, ["Peanut Scout"] = 8,
    ["Peanut President"] = 8, ["Ice Cream Chef"] = 8, ["Ice Cream Commander"] = 8, ["Baking Staff"] = 8,
    ["Head Baker"] = 8, ["Cocoa Warrior"] = 8, ["Chocolate Bar Battler"] = 8, ["Sweet Thief"] = 8,
    ["Candy Rebel"] = 8, ["Candy Pirate"] = 8, ["Snow Demon"] = 8, ["Isle Outlaw"] = 8, ["Island Boy"] = 8,
    ["Sun-kissed Warrior"] = 8, ["Isle Champion"] = 8, ["Serpent Hunter"] = 8, ["Skull Slayer"] = 8,
    ["Reef Bandit"] = 8, ["Coral Pirate"] = 8, ["Sea Chanter"] = 8, ["Ocean Prophet"] = 8, ["Grand Devotee"] = 8,
}

M.bosses = {
    { name = "Chef", level = 55, pos = Vector3.new(-1120.5, 54.7, 4121.2) },
    { name = "Yeti", level = 110, pos = Vector3.new(1181.7, 104.0, -1616.9) },
    { name = "Mob Boss", level = 120, pos = Vector3.new(-2880.7, 6.7, 5430.9) },
    { name = "Saber Expert", level = 200, pos = Vector3.new(-1527.2, 34.1, -33.2) },
    { name = "Warden", level = 230, pos = Vector3.new(5623.2, 1.4, 733.8) },
    { name = "Magma General", level = 350, pos = Vector3.new(-5625.7, 55.4, 8623.0) },
    { name = "Fishman Lord", level = 425, pos = Vector3.new(61352.9, 67.2, 1029.1) },
    { name = "Sky Warlord", level = 500, pos = Vector3.new(-6271.6, 5472.8, 1887.8) },
    { name = "Cyborg", level = 675, pos = Vector3.new(6252.4, 9.3, 4941.4) },
    { name = "Ice Admiral", level = 700, pos = Vector3.new(1212.4, 20.4, -1429.6) },
}
M.bosses2 = {
    { name = "Diamond", level = 750, pos = Vector3.new(-1711.4, 206.0, -97.1) },
    { name = "Jeremy", level = 850, pos = Vector3.new(2338.0, 451.4, 700.1) },
    { name = "Smoke Admiral", level = 1150, pos = Vector3.new(-4857.4, 233.7, -5583.2) },
    { name = "Awakened Ice Admiral", level = 1400, pos = Vector3.new(6551.8, 325.3, -6989.9) },
    { name = "rip_indra", level = 1500, pos = Vector3.new(-26952.3, 21.5, 329.4) },
}
M.bosses3 = {
    { name = "Kilo Admiral", level = 1750, pos = Vector3.new(2998.3, 508.8, -7344.3) },
    { name = "Captain Elephant", level = 1875, pos = Vector3.new(-13365.5, 321.2, -8485.0) },
    { name = "Longma", level = 2000, pos = Vector3.new(-10156.2, 337.8, -9445.9) },
    { name = "Cake Queen", level = 2175, pos = Vector3.new(-678.5, 381.9, -11114.3) },
    { name = "Cake Prince", level = 2200, pos = Vector3.new(-2089.9, 4536.9, -14800.0) },
}
M.sea3materials = {
    { mat = "Fish Tail",       mob = "Fishman Raider" },
    { mat = "Mystic Droplet",  mob = "Ocean Prophet" },
    { mat = "Ectoplasm",       mob = "Reborn Skeleton" },
    { mat = "Dragon Scale",    mob = "Dragon Crew Warrior" },
    { mat = "Gunpowder",       mob = "Pirate Millionaire" },
}
M.sea2materials = {
    { mat = "Scrap Metal",    mob = "Factory Staff" },
    { mat = "Vampire Fang",   mob = "Vampire" },
    { mat = "Magma Ore",      mob = "Magma Ninja" },
    { mat = "Conjured Cocoa", mob = "Ship Deckhand" },
    { mat = "Mystic Droplet", mob = "Water Fighter" },
}
M.selectedBoss = nil
M.selected = nil
M._statAuto, M._farmOn, M._bossOn, M._nearestOn, M._warn = false, false, false, false, 0
M._curKey, M._target = nil, nil
M._killCount, M._killReq, M._prevAlive = 0, 8, nil

local function commF() local r = RS:FindFirstChild("Remotes"); return r and r:FindFirstChild("CommF_") end
local function hrp() local ch = LP.Character; return ch and ch:FindFirstChild("HumanoidRootPart") end

function M.playerLevel()
    local ok, lv = pcall(function() return LP.Data.Level.Value end)
    return (ok and lv) or 1
end

function M.currentList()
    local info = M._core and M._core.modules.info
    local sea = info and info.sea
    if sea == "Sea3" then return M.sea3 end
    if sea == "Sea2" then return M.sea2 end
    return M.sea1
end

function M.bestForLevel()
    local list = M.currentList()
    local lv, best = M.playerLevel(), list[1]
    for _, q in ipairs(list) do if q.level <= lv then best = q else break end end
    return best
end

function M.aliveMobs(name)
    local folder, list = workspace:FindFirstChild("Enemies"), {}
    if folder then
        for _, e in ipairs(folder:GetChildren()) do
            if e.Name:lower() == name:lower() then
                local hum = e:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then list[#list + 1] = e end
            end
        end
    end
    return list
end

function M.nearestMob(name)
    local h, folder = hrp(), workspace:FindFirstChild("Enemies")
    if not h or not folder then return end
    local best, bestD
    for _, e in ipairs(folder:GetChildren()) do
        if e.Name:lower() == name:lower() then
            local hum = e:FindFirstChildOfClass("Humanoid")
            local part = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
            if hum and hum.Health > 0 and part then
                local d = (part.Position - h.Position).Magnitude
                if not bestD or d < bestD then best, bestD = e, d end
            end
        end
    end
    return best
end

function M.warnEnemies(want)
    if os.clock() - M._warn < 4 then return end
    M._warn = os.clock()
    local folder, seen, list = workspace:FindFirstChild("Enemies"), {}, {}
    if folder then for _, e in ipairs(folder:GetChildren()) do if not seen[e.Name] then seen[e.Name] = true; list[#list + 1] = e.Name end end end
    if M._core then M._core.warn("no '" .. want .. "' nearby; enemies:", table.concat(list, ", ")) end
end

local function isKind(t, kind)
    if kind == "Fruit" then
        local o = t:GetAttribute("OriginalName")
        return (o and tostring(o):find("-") ~= nil) or t.ToolTip == "Blox Fruit"
    end
    return t.ToolTip == kind
end
function M.equipWeapon(kind)
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not (ch and hum) then return end
    local eq = ch:FindFirstChildOfClass("Tool")
    if eq and isKind(eq, kind) then return end
    for _, pool in ipairs({ ch, LP:FindFirstChild("Backpack") }) do
        if pool then
            for _, t in ipairs(pool:GetChildren()) do
                if t:IsA("Tool") and isKind(t, kind) then hum:EquipTool(t); return end
            end
        end
    end
end

function M.startQuest()
    local c = commF()
    if not c then return end
    local q = M.selected or M.bestForLevel()
    pcall(function() return c:InvokeServer("StartQuest", q.id, q.tier) end)
    if M._core then M._core.info("StartQuest", q.id, q.tier, q.label) end
end

function M.addPoint(stat, amount)
    local c = commF()
    if not c then return end
    stat, amount = stat or M.config.stat, amount or M.config.statAmount
    pcall(function() return c:InvokeServer("AddPoint", stat, amount) end)
    if M._core then M._core.info("AddPoint", stat, amount) end
end

local function loop(flag, fn, interval)
    if not M._core then return end
    M._core.spawn(function() while M[flag] do fn(); task.wait(interval) end end)
end

function M.setStatAuto(on) M._statAuto = on; if on then loop("_statAuto", function() M.addPoint() end, 1) end end

function M._farmStep(combat, teleport)
    local q = M.selected or M.bestForLevel()
    M._mobName = q.mob
    local key = q.id .. "#" .. q.tier

    local fr = M._core.modules.fruits
    local ffruit, fpart = nil, nil
    if fr and fr._collect then ffruit, fpart = fr.nearestGroundFruit(M._fruitSkip) end
    if ffruit and fpart and teleport then
        M._collecting = true
        teleport.go(fpart.Position)
        M._fruitTries[ffruit] = (M._fruitTries[ffruit] or 0) + 1
        if M._fruitTries[ffruit] > 5 then M._fruitSkip[ffruit] = true end
        task.wait(0.5)
        return
    end
    M._collecting = false

    local list = M.aliveMobs(q.mob)
    local curr = {}
    for _, e in ipairs(list) do curr[e] = true end
    if M._prevAlive then
        for e in pairs(M._prevAlive) do if not curr[e] then M._killCount = M._killCount + 1 end end
    end
    M._prevAlive = curr
    if key ~= M._curKey then
        M._curKey, M._target, M._anchor = key, nil, nil
        M._killCount, M._killReq, M._prevAlive = 0, (q.kills or M.kills[q.mob] or 8), nil
        M.startQuest()
    elseif M._killCount >= M._killReq then
        M._killCount = 0
        M.startQuest()
    end

    local target = M.nearestMob(q.mob)
    if target and teleport and combat then
        if target ~= M._target then M._target = target end
        local part = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
        local h = hrp()
        if M.config.bring then
            if not M._anchor and part and h then
                if (part.Position - h.Position).Magnitude > M.config.hoverRange then
                    teleport.go(part.Position + Vector3.new(0, M.config.heightOffset, 0))
                else
                    M._anchor = part.Position
                    if teleport then teleport.cancel() end
                end
            end
        elseif part and h and (part.Position - h.Position).Magnitude > M.config.hoverRange then
            teleport.go(part.Position + Vector3.new(0, M.config.heightOffset, 0))
        end
        if M.config.equip then M.equipWeapon(M.config.equipType) end
        if M.config.bring then
            for _, e in ipairs(list) do combat.attackOnce(e) end
        else
            combat.attackOnce(target)
        end
        if combat.config.targetPlayers then combat.attackPlayersInRange(combat.config.playerRange) end
        task.wait(M.config.attackInterval)
    elseif M.config.bring and M._anchor then
        task.wait(1)
    else
        local sp, h = M.spawns[q.mob], hrp()
        if sp and teleport and h then
            local dist = (h.Position - sp).Magnitude
            if dist > 150 then
                teleport.go(sp + Vector3.new(0, M.config.heightOffset, 0))
                -- wait the actual fly time (distance / speed) + buffer, so we attack only once arrived
                task.wait(math.clamp(dist / ((teleport.config and teleport.config.speed) or 100), 0.3, 90) + 0.4)
            else
                task.wait(1.2)
            end
        else
            M.warnEnemies(q.mob)
            task.wait(M.config.attackInterval)
        end
    end
end

-- _farmGen versions the loop: a restart bumps the gen so any stale loop exits on its next check.
function M._runFarmLoop()
    local gen = M._farmGen
    M._core.spawn(function()
        local combat, teleport = M._core.modules.combat, M._core.modules.teleport
        if combat and combat.setupHitId then combat.setupHitId() end   -- re-equip weapon -> register a valid hitId
        while M._farmOn and M._farmGen == gen do
            M._lastTick = os.clock()
            local ok, err = pcall(M._farmStep, combat, teleport)
            if not ok and M._core then M._core.warn("farm step:", tostring(err)); task.wait(0.3) end
        end
    end)
end

function M.startWatchdog()
    if M._watchdogOn then return end
    M._watchdogOn = true
    M._core.spawn(function()
        while M._farmOn do
            if M._lastTick and (os.clock() - M._lastTick) > 4 then
                if M._core then M._core.warn("farm watchdog: restarting loop") end
                M._farmGen = (M._farmGen or 0) + 1
                M._lastTick = os.clock()
                M._runFarmLoop()
            end
            task.wait(2)
        end
        M._watchdogOn = false
    end)
end

function M.setFarm(on)
    M._farmOn = on
    if on then M._bossOn, M._nearestOn = false, false end
    if not M._core then return end
    M._curKey, M._target, M._collecting, M._anchor = nil, nil, false, nil
    M._killCount, M._killReq, M._prevAlive = 0, 8, nil
    M._fruitSkip = setmetatable({}, { __mode = "k" })
    M._fruitTries = setmetatable({}, { __mode = "k" })
    M._decollided = setmetatable({}, { __mode = "k" })
    if on and not M.selected and M._ui then M._ui.notify("Auto quest: " .. M.bestForLevel().label) end
    if on then
        M._farmGen = (M._farmGen or 0) + 1
        M._lastTick = os.clock()
        M._runFarmLoop()
        M.startWatchdog()
    end
    M._core.info("level farm", on and "ON" or "OFF")
end

function M.setNearestFarm(on)
    M._nearestOn = on
    if on then M._farmOn, M._bossOn = false, false end
    if not (on and M._core) then return end
    M._mobName, M._anchor, M._target = nil, nil, nil
    M._core.spawn(function()
        local combat, teleport = M._core.modules.combat, M._core.modules.teleport
        if combat and combat.setupHitId then combat.setupHitId() end
        while M._nearestOn do
            local target = combat and combat.nearest(1e9)
            if target and teleport and combat then
                M._target = target
                local part = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
                local h = hrp()
                if part and h and (part.Position - h.Position).Magnitude > M.config.hoverRange then
                    teleport.go(part.Position + Vector3.new(0, M.config.heightOffset, 0))
                end
                if M.config.equip then M.equipWeapon(M.config.equipType) end
                combat.attackOnce(target)
                if combat.config.targetPlayers then combat.attackPlayersInRange(combat.config.playerRange) end
            else
                M._target = nil
            end
            task.wait(M.config.attackInterval)
        end
    end)
    M._core.info("nearest farm", on and "ON" or "OFF")
end

function M.setBossFarm(on)
    M._bossOn = on
    if on then M._farmOn, M._nearestOn = false, false end
    if not (on and M._core) then return end
    M._target = nil
    M._core.spawn(function()
        local combat, teleport = M._core.modules.combat, M._core.modules.teleport
        if combat and combat.setupHitId then combat.setupHitId() end
        while M._bossOn do
            local b = M.selectedBoss
            if not b then task.wait(1) else
                local target = M.nearestMob(b.name)
                if target then
                    M._target = target
                    local part = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
                    local h = hrp()
                    if part and h and teleport and (part.Position - h.Position).Magnitude > M.config.hoverRange then
                        teleport.go(part.Position + Vector3.new(0, M.config.heightOffset, 0))
                    end
                    if M.config.equip then M.equipWeapon(M.config.equipType) end
                    if combat then
                        combat.attackOnce(target)
                        if combat.config.targetPlayers then combat.attackPlayersInRange(combat.config.playerRange) end
                    end
                    task.wait(M.config.attackInterval)
                else
                    M._target = nil
                    if teleport and b.pos then teleport.go(b.pos + Vector3.new(0, M.config.heightOffset, 0)) end
                    task.wait(2)
                end
            end
        end
    end)
    M._core.info("boss farm", on and ("ON " .. (M.selectedBoss and M.selectedBoss.name or "")) or "OFF")
end

local function entryByMob(list, mob)
    for _, q in ipairs(list) do if q.mob == mob then return q end end
end

function M.setMaterialFarm(on)
    if on then
        local list = M.currentList()
        local src = M._matMob or (list[1] and list[1].mob)
        local q = src and entryByMob(list, src)
        if not q then if M._ui then M._ui.notify("Pick a material first") end return end
        M.selected, M._curKey = q, nil
        if M._ui then M._ui.notify("Material farm: " .. src) end
    end
    M.setFarm(on)
end

function M.setAutoNextIsland(on)
    if on then M.selected, M._curKey = nil, nil end
    M.setFarm(on)
end

function M.stop()
    M._statAuto, M._farmOn, M._bossOn, M._nearestOn = false, false, false, false
    local h = hrp()
    if h and h.Anchored then h.Anchored = false end
end

function M.init(Core, UI)
    M._core, M._ui = Core, UI

    Core.track(RunService.RenderStepped:Connect(function()
        if not (M._farmOn or M._bossOn or M._nearestOn) then return end
        local h = hrp()
        if not h then return end
        if h.Anchored then h.Anchored = false end
        h.AssemblyLinearVelocity = Vector3.zero
        if M._collecting then return end

        if M.config.bring and M._anchor then
            h.CFrame = CFrame.new(M._anchor + Vector3.new(0, M.config.heightOffset, 0))
            h.AssemblyLinearVelocity = Vector3.zero
            if M._mobName then
                local folder = workspace:FindFirstChild("Enemies")
                if folder then
                    for _, e in ipairs(folder:GetChildren()) do
                        if e.Name:lower() == M._mobName:lower() then
                            local hum = e:FindFirstChildOfClass("Humanoid")
                            local ep = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
                            if hum and hum.Health > 0 and ep then
                                if not M._decollided[e] then
                                    for _, bp in ipairs(e:GetDescendants()) do
                                        if bp:IsA("BasePart") then bp.CanCollide = false end
                                    end
                                    M._decollided[e] = true
                                end
                                ep.CFrame = CFrame.new(M._anchor)
                                ep.AssemblyLinearVelocity = Vector3.zero
                            end
                        end
                    end
                end
            end
        else
            local t = M._target
            local part = t and (t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart)
            if part and (part.Position - h.Position).Magnitude < M.config.hoverRange then
                h.CFrame = CFrame.new(part.Position + Vector3.new(0, M.config.heightOffset, 0))
                h.AssemblyLinearVelocity = Vector3.zero
            end
        end
    end))

    local combat = Core.modules.combat

    local function buildFarm(page, mobs, bosses, saber, materials)
        UI.toggle(page, "Auto level farm", "Quest + move to quest mob + attack", false, function(s) M.setFarm(s) end)
        UI.toggle(page, "Farm Nearest", "Farm the nearest mob (any type, no quest)", false, function(s) M.setNearestFarm(s) end)
        if materials then
            UI.toggle(page, "Auto Next Island", "Auto-progress: farm the mob matching your level", false, function(s) M.setAutoNextIsland(s) end)
        end
        local labels = { "Auto (by level)" }
        for _, q in ipairs(mobs) do labels[#labels + 1] = q.label end
        UI.dropdown(page, "Quest", "Target mob (Auto = by your level)", labels, function(sel)
            if sel == "Auto (by level)" then M.selected = nil
            else for _, q in ipairs(mobs) do if q.label == sel then M.selected = q; break end end end
            M._curKey = nil
        end)
        UI.slider(page, "Height offset", "Studs above the mob", 0, 40, M.config.heightOffset, function(v) M.config.heightOffset = v end)
        UI.toggle(page, "Bring mob", "Stack mobs on one spot under you", false, function(s) M.config.bring = s end)

        UI.toggle(page, "Auto attack (mobs)", "Attack the nearest mob (standalone)", false, function(s)
            if combat then combat.setMobAuto(s) end
        end)
        UI.slider(page, "Attack range", "Mob detection radius", 1, 300, combat and combat.config.range or 120, function(v)
            if combat then combat.config.range = v end
        end)

        UI.dropdown(page, "Auto equip", "Weapon to equip while farming", { "Melee", "Sword", "Gun", "Fruit" }, function(s) M.config.equipType = s end)
        UI.toggle(page, "Auto equip on", "Equip the chosen weapon to farm with", false, function(s) M.config.equip = s end)

        UI.section(page, "BOSS")
        local bl = {}
        for _, b in ipairs(bosses) do bl[#bl + 1] = ("%s (Lv %d)"):format(b.name, b.level) end
        UI.dropdown(page, "Boss", "Boss to farm (long respawn)", bl, function(sel)
            for _, b in ipairs(bosses) do if ("%s (Lv %d)"):format(b.name, b.level) == sel then M.selectedBoss = b; break end end
        end)
        UI.toggle(page, "Farm Boss", "Go to the boss and kill it on respawn", false, function(s) M.setBossFarm(s) end)
        if saber then
            UI.toggle(page, "Auto Saber", "Farm the Saber Expert to unlock the Saber", false, function(s)
                if s then for _, b in ipairs(bosses) do if b.name == "Saber Expert" then M.selectedBoss = b; break end end end
                M.setBossFarm(s)
            end)
        end

        if materials then
            UI.section(page, "MATERIALS")
            local mlabels = {}
            for _, m in ipairs(materials) do mlabels[#mlabels + 1] = m.mat .. "  (" .. m.mob .. ")" end
            UI.dropdown(page, "Material", "Material to farm (its source mob)", mlabels, function(sel)
                for _, m in ipairs(materials) do if (m.mat .. "  (" .. m.mob .. ")") == sel then M._matMob = m.mob; break end end
            end)
            UI.toggle(page, "Material Farm", "Farm the source mob of the selected material", false, function(s) M.setMaterialFarm(s) end)
        end

        UI.section(page, "STATS")
        UI.dropdown(page, "Stat", "Stat to level up", M.stats, function(s) M.config.stat = s end)
        UI.slider(page, "Amount", "Points per add", 1, 100, M.config.statAmount, function(v) M.config.statAmount = v end)
        UI.toggle(page, "Auto add points", "Spend points continuously", false, function(s) M.setStatAuto(s) end)
    end

    buildFarm(UI.page("Farm"), M.sea1, M.bosses, true, nil)
    buildFarm(UI.page("Farm 2"), M.sea2, M.bosses2, false, M.sea2materials)
    buildFarm(UI.page("Farm 3"), M.sea3, M.bosses3, false, M.sea3materials)

    Core.register("farm", M)
    return M
end

return M
end)()

genv.__BF_PLAYER = (function()
-- Player: ESP, mobility (NoClip / Walk on Water / Speed / Jump), Haki keep-on, Anti-AFK.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local M = {}
M._esp = {}
M._espOn = false
M.config = {
    noclip = false, walkWater = false, speedOn = false, walkSpeed = 50, jumpOn = false, jumpPower = 120,
    ken = false, buso = false,
    antiAfk = true,
}
M._platform, M._hakiRunning = nil, false

local function hrp(ch) return ch and ch:FindFirstChild("HumanoidRootPart") end
local function myHrp() return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") end
local function myHum() return LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") end

local function makeEsp(ch)
    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(255, 80, 80)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.6
    hl.Adornee = ch; hl.Parent = ch
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(120, 28); bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = ch:FindFirstChild("HumanoidRootPart") or ch; bb.Parent = ch
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1; lbl.Size = UDim2.fromScale(1, 1)
    lbl.Font = Enum.Font.Gotham; lbl.TextSize = 11; lbl.TextColor3 = Color3.new(1, 1, 1)
    lbl.TextStrokeTransparency = 0.5; lbl.Parent = bb
    return { hl = hl, bb = bb, lbl = lbl, char = ch }
end

function M.others()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then t[#t + 1] = p end
    end
    return t
end

function M.setESP(on)
    M._espOn = on
    if not on then
        for _, e in pairs(M._esp) do pcall(function() e.hl:Destroy(); e.bb:Destroy() end) end
        M._esp = {}
    end
end

local function remotes() return RS:FindFirstChild("Remotes") end
function M.hakiLoop()
    if M._hakiRunning or not M._core then return end
    M._hakiRunning = true
    M._core.spawn(function()
        while M.config.ken or M.config.buso do
            local ch = LP.Character
            local r = remotes()
            if ch and r then
                local kenOn = LP:GetAttribute("KenActive") or ch:GetAttribute("KenActive")
                local busoOn = ch:GetAttribute("BusoEnabled") or LP:GetAttribute("BusoEnabled")
                if M.config.ken and not kenOn then
                    local ce = r:FindFirstChild("CommE")
                    if ce then pcall(function() ce:FireServer("Ken", true) end) end
                end
                if M.config.buso and not busoOn then
                    local cf = r:FindFirstChild("CommF_")
                    if cf then pcall(function() cf:InvokeServer("Buso") end) end
                end
            end
            task.wait(0.5)
        end
        M._hakiRunning = false
    end)
end
function M.setKen(on)
    M.config.ken = on
    if on then M.hakiLoop()
    else
        local r = remotes(); local ce = r and r:FindFirstChild("CommE")
        if ce and LP:GetAttribute("KenActive") then pcall(function() ce:FireServer("Ken", false) end) end
    end
end
function M.setBuso(on)
    M.config.buso = on
    if on then M.hakiLoop()
    else
        local ch = LP.Character; local r = remotes(); local cf = r and r:FindFirstChild("CommF_")
        if ch and cf and ch:GetAttribute("BusoEnabled") then pcall(function() cf:InvokeServer("Buso") end) end
    end
end

function M.setAntiAfk(on) M.config.antiAfk = on and true or false end

function M.stop()
    M.setESP(false)
    M.config.ken, M.config.buso = false, false
    if M._platform then M._platform:Destroy(); M._platform = nil end
    local h = myHum()
    if h then h.WalkSpeed = 16 end
end

function M.init(Core, UI)
    M._core = Core

    local VirtualUser = game:GetService("VirtualUser")
    Core.track(LP.Idled:Connect(function()
        if not M.config.antiAfk then return end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end))

    local page = UI.page("Player")

    UI.toggle(page, "Player ESP", "Highlight players and show distance", true, function(s) M.setESP(s) end)

    UI.section(page, "MOBILITY")
    UI.toggle(page, "NoClip", "Walk through walls", false, function(s) M.config.noclip = s end)
    UI.toggle(page, "Walk on Water", "Invisible platform over water", true, function(s) M.config.walkWater = s end)
    UI.toggle(page, "Speed boost", "Faster walk speed", false, function(s) M.config.speedOn = s end)
    UI.slider(page, "Walk speed", "Speed value", 16, 300, M.config.walkSpeed, function(v) M.config.walkSpeed = v end)
    UI.toggle(page, "Super jump", "Higher jump", false, function(s) M.config.jumpOn = s end)
    UI.slider(page, "Jump power", "Jump value", 50, 500, M.config.jumpPower, function(v) M.config.jumpPower = v end)

    UI.section(page, "HAKI")
    UI.toggle(page, "Auto Ken", "Keep Observation Haki on (must be unlocked)", true, function(s) M.setKen(s) end)
    UI.toggle(page, "Auto Buso", "Keep Armament Haki on (must be unlocked)", true, function(s) M.setBuso(s) end)

    UI.section(page, "UTILITY")
    UI.toggle(page, "Anti-AFK", "Prevent the 20-min idle kick (on by default)", true, function(s) M.setAntiAfk(s) end)

    Core.track(RunService.Heartbeat:Connect(function()
        if not M._espOn then return end
        local mh = myHrp()
        for _, p in ipairs(M.others()) do
            local ch = p.Character
            if ch then
                local e = M._esp[p]
                if e and e.char ~= ch then pcall(function() e.hl:Destroy(); e.bb:Destroy() end); e, M._esp[p] = nil, nil end
                if not e then e = makeEsp(ch); M._esp[p] = e end
                local h = hrp(ch)
                local d = (h and mh) and math.floor((h.Position - mh.Position).Magnitude) or 0
                e.lbl.Text = p.Name .. "\n" .. d .. "m"
            end
        end
    end))

    Core.track(RunService.Stepped:Connect(function()
        if not M.config.noclip then return end
        local ch = LP.Character
        if ch then
            for _, part in ipairs(ch:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
            end
        end
    end))

    -- RenderStepped runs after the game's own controller, so our values win the frame.
    Core.track(RunService.RenderStepped:Connect(function()
        local h = myHum()
        if h then
            if M.config.speedOn then h.WalkSpeed = M.config.walkSpeed end
            if M.config.jumpOn then h.UseJumpPower = true; h.JumpPower = M.config.jumpPower end
        end
    end))

    Core.track(RunService.Heartbeat:Connect(function()
        local hp = myHrp()
        local h = myHum()
        -- Pause the platform while farming: Sea 3 submerged islands are underwater, and the
        -- platform would shove the character back up to the surface, away from the mobs.
        local farm = M._core and M._core.modules.farm
        local farming = farm and (farm._farmOn or farm._bossOn or farm._nearestOn)
        if M.config.walkWater and not farming and hp and h then
            local swimming = (h:GetState() == Enum.HumanoidStateType.Swimming)
            if swimming and not M._platform then
                M._platform = Instance.new("Part")
                M._platform.Size = Vector3.new(30, 1, 30); M._platform.Anchored = true
                M._platform.CanCollide = true; M._platform.Transparency = 1; M._platform.Parent = workspace
                M._waterY = hp.Position.Y - 1
            end
            if M._platform then
                M._platform.Position = Vector3.new(hp.Position.X, M._waterY, hp.Position.Z)
                if hp.Position.Y < M._waterY + 1 then
                    hp.CFrame = CFrame.new(hp.Position.X, M._waterY + 3, hp.Position.Z)
                end
            end
        elseif M._platform then
            M._platform:Destroy(); M._platform = nil
        end
    end))

    Core.register("player", M)
    return M
end

return M
end)()

genv.__BF_FRUITS = (function()
-- Fruits: devil-fruit finder/teleport + gacha rolls.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local M = {}
M.config = { chestCooldown = 3.5, randomCooldown = 90, storePoll = 3, storeHandPoll = 2 }
function M._setStatus(_) end
M.FRUITS = {
    "Barrier", "Blade", "Blizzard", "Bomb", "Buddha", "Chop", "Control", "Creation", "Dark",
    "Diamond", "Door", "Dough", "Dragon", "Eagle", "Falcon", "Flame", "Gas", "Ghost", "Gravity",
    "Ice", "Kilo", "Kitsune", "Leopard", "Light", "Lightning", "Love", "Magma", "Mammoth",
    "Mochi", "Pain", "Paw", "Phoenix", "Portal", "Quake", "Revive", "Rocket", "Rubber", "Rumble",
    "Sand", "Shadow", "Smoke", "Sound", "Spider", "Spike", "Spin", "Spirit", "Spring", "String",
    "T-Rex", "Venom", "Yeti",
}
M.selectedFruit = nil
M._fruitEsp, M._collect, M._snipe, M._store, M._random = false, false, false, false, false
M._chestOn, M._chestEspOn, M._chestEsp, M._collected, M._fruitEspMap = false, false, {}, {}, {}

local fireprompt = fireproximityprompt or function() end

local function hrp() local ch = LP.Character; return ch and ch:FindFirstChild("HumanoidRootPart") end
local function teleport() return M._core and M._core.modules.teleport end
local function commF() local r = RS:FindFirstChild("Remotes"); return r and r:FindFirstChild("CommF_") end

function M.getStock()
    local c = commF()
    if not c then return {} end
    local ok, map = pcall(function() return c:InvokeServer("GetFruits", false) end)
    return (ok and type(map) == "table") and map or {}
end

function M.fruitNames()
    local names = table.clone(M.FRUITS)
    table.sort(names)
    return names
end

function M.buy(name)
    local c = commF()
    if not (c and name) then return end
    local ok, res = pcall(function() return c:InvokeServer("PurchaseRawFruit", name, false) end)
    if M._core then M._core.info("PurchaseRawFruit", name, "ok=" .. tostring(ok), "res=" .. tostring(res)) end
    return res
end

function M.setSnipe(on)
    M._snipe = on
    if not (on and M._core) then return end
    M._core.spawn(function()
        while M._snipe do
            if M.selectedFruit then
                for _, v in pairs(M.getStock()) do
                    if type(v) == "table" and v.OnSale and v.ColorName == M.selectedFruit then
                        M.buy(v.ColorName)
                        if M._ui then M._ui.notify("Sniped: " .. v.ColorName) end
                    end
                end
            end
            task.wait(M.config.storePoll)
        end
    end)
end

function M.storeHeld()
    local c = commF()
    if not c then return end
    local pools = {}
    if LP.Character then pools[#pools + 1] = LP.Character end
    local bp = LP:FindFirstChild("Backpack")
    if bp then pools[#pools + 1] = bp end
    for _, pool in ipairs(pools) do
        for _, t in ipairs(pool:GetChildren()) do
            if t:IsA("Tool") then
                local orig = t:GetAttribute("OriginalName")
                if orig and tostring(orig):find("-") then
                    pcall(function() c:InvokeServer("StoreFruit", orig, t) end)
                    if M._core then M._core.info("StoreFruit", orig) end
                end
            end
        end
    end
end

function M.setStore(on)
    M._store = on
    if not (on and M._core) then return end
    M._core.spawn(function()
        while M._store do M.storeHeld(); task.wait(M.config.storeHandPoll) end
    end)
end

local function dealerName()
    local info = M._core and M._core.modules.info
    return (info and info.sea == "Sea2") and "AdvancedFruitDealer" or "FruitDealer"
end

function M.openDealer()
    local ok, err = pcall(function()
        require(RS.Controllers.UI.FruitShop):Open(dealerName())
    end)
    if not ok and M._core then M._core.warn("openDealer failed:", tostring(err)) end
    if not ok and M._ui then M._ui.notify("Dealer menu unavailable") end
end

function M.awakenAll()
    local c = commF()
    if not c then return end
    local bought = 0
    for _ = 1, 30 do
        local ok, v = pcall(function() return c:InvokeServer("Awakener", "Awaken") end)
        if ok and v == 1 then bought = bought + 1 else break end
        task.wait(0.25)
    end
    if M._ui then M._ui.notify(bought > 0 and ("Awakened " .. bought .. " ability(ies)") or "Nothing to awaken (need fragments / equipped fruit)") end
    if M._core then M._core.info("Awaken all", "count=" .. bought) end
end

function M.openAwakening()
    local c = commF()
    if c then pcall(function() c:InvokeServer("AwakeningChanger", "Check") end) end
    local ok = pcall(function() require(RS.Controllers.UI.Awakening):Open() end)
    if M._ui then M._ui.notify(ok and "Awakening menu opened" or "Awaken needs a raid (see logs)") end
    if M._core then M._core.info("Awakening", "open ok=" .. tostring(ok)) end
end

local function gachaRF()
    local mods = RS:FindFirstChild("Modules")
    local n = mods and mods:FindFirstChild("Net")
    return n and n:FindFirstChild("RF/GachaNetworkRF")
end

function M.rollGacha()
    local rf = gachaRF()
    if not rf then if M._core then M._core.warn("GachaNetworkRF not found") end return end
    local p = table.pack(pcall(function() return rf:InvokeServer({ Context = "Purchase", BoxName = "ZiolesGacha" }) end))
    if M._core then
        local parts = {}
        for i = 2, p.n do parts[#parts + 1] = tostring(p[i]) end
        M._core.info("Gacha result:", table.concat(parts, " | "))
    end
    return p
end

function M.setRandom(on)
    M._random = on
    if not (on and M._core) then return end
    M._core.spawn(function()
        while M._random do
            local ok, p = pcall(M.rollGacha)
            if M._ui then M._ui.notify("Fruit gacha roll") end
            local cd = M.config.randomCooldown
            if ok and p then
                for i = 2, p.n do
                    if type(p[i]) == "number" and p[i] > 3 then cd = math.clamp(math.floor(p[i]), 30, 300); break end
                end
            end
            while M._random and cd > 0 do
                M._setStatus(("Gacha: next roll in %ds"):format(cd))
                task.wait(1); cd = cd - 1
            end
        end
        M._setStatus("Gacha: off")
    end)
end

local function fruitPart(f)
    return f:FindFirstChild("Handle") or f:FindFirstChildWhichIsA("BasePart")
end
function M.groundFruits()
    local t = {}
    for _, c in ipairs(workspace:GetChildren()) do
        if c:IsA("Tool") and (c:GetAttribute("OriginalName") or c.Name:find("-")) and fruitPart(c) then
            t[#t + 1] = c
        end
    end
    return t
end

function M.setFruitESP(on)
    M._fruitEsp = on
    if not on then
        for _, e in pairs(M._fruitEspMap) do pcall(function() e.hl:Destroy(); e.bb:Destroy() end) end
        M._fruitEspMap = {}
        return
    end
    if not M._core then return end
    M._core.spawn(function()
        while M._fruitEsp do
            local live, h = {}, hrp()
            for _, f in ipairs(M.groundFruits()) do
                local part = fruitPart(f)
                if part then
                    live[f] = true
                    local e = M._fruitEspMap[f]
                    if not e then
                        local hl = Instance.new("Highlight")
                        hl.FillColor = Color3.fromRGB(120, 220, 255)
                        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                        hl.Adornee = part; hl.Parent = part
                        local bb = Instance.new("BillboardGui")
                        bb.Size = UDim2.fromOffset(150, 20); bb.StudsOffset = Vector3.new(0, 2.5, 0)
                        bb.AlwaysOnTop = true; bb.Adornee = part; bb.Parent = part
                        local lbl = Instance.new("TextLabel")
                        lbl.BackgroundTransparency = 1; lbl.Size = UDim2.fromScale(1, 1)
                        lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 13
                        lbl.TextColor3 = Color3.fromRGB(120, 220, 255); lbl.TextStrokeTransparency = 0.4
                        lbl.Parent = bb
                        e = { hl = hl, bb = bb, lbl = lbl, part = part }
                        M._fruitEspMap[f] = e
                    end
                    local d = h and math.floor((part.Position - h.Position).Magnitude) or 0
                    e.lbl.Text = ("%s  %dm"):format(f.Name, d)
                end
            end
            for f, e in pairs(M._fruitEspMap) do
                if not live[f] then pcall(function() e.hl:Destroy(); e.bb:Destroy() end); M._fruitEspMap[f] = nil end
            end
            task.wait(0.5)
        end
    end)
end

function M.nearestGroundFruit(skip)
    local h = hrp()
    local best, bestPart, bestD
    for _, f in ipairs(M.groundFruits()) do
        local p = fruitPart(f)
        if p and not (skip and skip[f]) then
            local d = h and (p.Position - h.Position).Magnitude or 0
            if not bestD or d < bestD then best, bestPart, bestD = f, p, d end
        end
    end
    return best, bestPart
end

function M.collectNearestOnce()
    local tp = teleport()
    local f, part = M.nearestGroundFruit()
    if tp and part then
        tp.go(part.Position)
        if M._core then M._core.info("fruit collect", f.Name) end
        return true
    end
    return false
end

function M.setCollect(on)
    M._collect = on
    if not (on and M._core) then return end
    M._core.spawn(function()
        while M._collect do
            local farm = M._core.modules.farm
            if farm and farm._farmOn then
                task.wait(0.5)
            elseif M.collectNearestOnce() then
                task.wait(0.5)
            else
                task.wait(0.8)
            end
        end
    end)
end

function M.chests()
    local t = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Model") and (d.Name:match("^Chest%d*$") or d.Name == "SilverChest") then
            local ok, piv = pcall(function() return d:GetPivot().Position end)
            if ok then t[#t + 1] = { model = d, pos = piv } end
        end
    end
    return t
end

function M.setChestFarm(on)
    M._chestOn, M._collected = on, {}
    if not (on and M._core) then return end
    M._core.spawn(function()
        while M._chestOn do
            local tp, h = teleport(), hrp()
            if not (tp and h) then task.wait(1) else
                local pending = {}
                for _, ch in ipairs(M.chests()) do if not M._collected[ch.model] then pending[#pending + 1] = ch end end
                if #pending == 0 then
                    if M._ui then M._ui.notify("No chest to collect") end
                    M._collected = {}; task.wait(3)
                else
                    table.sort(pending, function(a, b) return (a.pos - h.Position).Magnitude < (b.pos - h.Position).Magnitude end)
                    local ch = pending[1]
                    local dist = (ch.pos - h.Position).Magnitude
                    tp.go(ch.pos + Vector3.new(0, 3, 0))
                    task.wait(math.clamp(dist / 100, 0.2, 8) + 0.3)
                    M._collected[ch.model] = true
                    if M._core then M._core.info("chest ->", ch.model.Name) end
                    task.wait(M.config.chestCooldown)
                end
            end
        end
    end)
end

function M.setChestESP(on)
    M._chestEspOn = on
    if not on then
        for _, hl in pairs(M._chestEsp) do pcall(function() hl:Destroy() end) end
        M._chestEsp = {}
        return
    end
    if not M._core then return end
    M._core.spawn(function()
        local first = true
        while M._chestEspOn do
            local list = M.chests()
            if first and M._ui then M._ui.notify(#list .. " chest(s) found"); first = false end
            for _, ch in ipairs(list) do
                if not M._chestEsp[ch.model] then
                    local hl = Instance.new("Highlight")
                    hl.FillColor = Color3.fromRGB(255, 210, 60)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.Adornee = ch.model; hl.Parent = ch.model
                    M._chestEsp[ch.model] = hl
                end
            end
            task.wait(2)
        end
    end)
end

function M.stop()
    M._fruitEsp, M._collect, M._snipe, M._store, M._random, M._chestOn = false, false, false, false, false, false
    M.setFruitESP(false); M.setChestESP(false)
end

function M.init(Core, UI)
    M._core, M._ui = Core, UI

    local fp = UI.page("Fruit")
    UI.toggle(fp, "Fruit ESP", "Highlight fruits on the ground", false, function(s) M.setFruitESP(s) end)
    UI.toggle(fp, "Grab Fruit", "Pick up the nearest ground fruit", false, function(s) M.setCollect(s) end)
    UI.toggle(fp, "Fruit Store", "Auto-store fruits in your bar", false, function(s) M.setStore(s) end)

    UI.section(fp, "DEALER")
    local names = M.fruitNames()
    if #names == 0 then names = { "(open dealer / retry)" } end
    UI.dropdown(fp, "Fruit", "Fruit to snipe in the store", names, function(sel) M.selectedFruit = sel end)
    UI.toggle(fp, "Fruit snipe", "Buy the selected fruit when on sale", false, function(s) M.setSnipe(s) end)
    UI.toggle(fp, "Auto Random Fruit", "Roll the fruit gacha (Zioles) on cooldown", false, function(s) M.setRandom(s) end)
    UI.button(fp, "Fruit stock", "Open the in-game dealer menu (sea-aware)", function() M.openDealer() end)
    UI.button(fp, "Awaken all abilities", "Buy every awakening for your held fruit (uses fragments)", function() M.awakenAll() end)
    UI.button(fp, "Awaken menu", "Open the awakening menu (full awaken needs a raid)", function() M.openAwakening() end)
    local gStat = UI.section(fp, "Gacha: off")
    local gLbl = gStat and gStat:FindFirstChildWhichIsA("TextLabel")
    function M._setStatus(t) if gLbl then gLbl.Text = t end end

    local mp = UI.page("Farm")
    UI.section(mp, "CHESTS")
    UI.toggle(mp, "Chest ESP", "Highlight chests on the map", false, function(s) M.setChestESP(s) end)
    UI.toggle(mp, "Auto collect chests", "Teleport chest to chest (nearest first)", false, function(s) M.setChestFarm(s) end)

    Core.register("fruits", M)
    return M
end

return M
end)()

genv.__BF_SHOP = (function()
-- Shop: per-sea dealers, auto-buy legendary swords (Rengoku/Oroshi/Shizu).
local RS = game:GetService("ReplicatedStorage")

local M = {}
local function commF() local r = RS:FindFirstChild("Remotes"); return r and r:FindFirstChild("CommF_") end

function M.buy(action, arg)
    local c = commF()
    if not c then return end
    local ok, res = pcall(function()
        if arg ~= nil then return c:InvokeServer(action, arg) else return c:InvokeServer(action) end
    end)
    if M._core then M._core.info("Shop", action, tostring(arg), "ok=" .. tostring(ok), "res=" .. tostring(res)) end
    if M._ui then
        M._ui.notify(ok and ("Buy " .. tostring(arg or action) .. " (res " .. tostring(res) .. ")") or "Shop error")
    end
end

M.swords = {
    "Katana", "Cutlass", "Iron Mace", "Dual Katana", "Bisento", "Pipe",
    "Dual-Headed Blade", "Soul Cane", "Dark Dagger", "Twin Hooks", "Longsword",
}
M.guns = { "Slingshot", "Refined Slingshot", "Flintlock", "Musket", "Cannon" }
M.styles = {
    { "Black Leg", "BuyBlackLeg" }, { "Electro", "BuyElectro" },
    { "Fishman Karate", "BuyFishmanKarate" }, { "Superhuman", "BuySuperhuman" },
}
M.haki = { "Buso", "Ken", "Geppo", "Soru" }
M.items = { "Black Cape", "Swordsman Hat", "Tomoe Ring" }

M.sea2 = {
    swords = { "Triple Katana" },
    guns = { "Dual Flintlock", "Refined Slingshot" },
    styles = {
        { "Death Step", "BuyDeathStep" }, { "Sharkman Karate", "BuySharkmanKarate" },
        { "Electric Claw", "BuyElectricClaw" }, { "Superhuman", "BuySuperhuman" },
    },
    haki = {},
    items = { "Swan Glasses", "Ghoul Mask", "Musketeer Hat", "Zebra Cap", "Warrior Helmet", "Marine Cap", "Black Spikey Coat" },
}

M.legendary = { "Shark Saw", "Saddi", "Pole (1st Form)" }
M._legendaryWant = "Any"

M.sea3 = {
    swords = {},
    guns = {},
    styles = {
        { "Dragon Talon", "BuyDragonTalon" }, { "Godhuman", "BuyGodhuman" }, { "Sanguine Art", "BuySanguineArt" },
    },
    haki = {},
    items = { "Ghoul Mask", "Pale Scarf", "Dark Coat", "Holy Crown", "Warrior Helmet" },
}

function M.legendaryOnSale()
    local c = commF()
    if not c then return nil end
    local ok, name = pcall(function() return c:InvokeServer("LegendarySwordDealer", "1") end)
    return ok and name or nil
end
function M.buyLegendary()
    local c = commF()
    if not c then return end
    return select(2, pcall(function() return c:InvokeServer("LegendarySwordDealer", "2") end))
end

function M.setAutoLegendary(on)
    M._legendaryOn = on
    if not (on and M._core) then return end
    M._core.spawn(function()
        while M._legendaryOn do
            local name = M.legendaryOnSale()
            if name and (M._legendaryWant == "Any" or name == M._legendaryWant) then
                local res = M.buyLegendary()
                if M._core then M._core.info("LegendarySword", name, "res=" .. tostring(res)) end
                if res == 1 then
                    if M._ui then M._ui.notify("Bought legendary: " .. name) end
                elseif res == 2 then
                    if M._ui then M._ui.notify("Already own: " .. name) end
                    M._legendaryOn = false
                    if M._legendaryToggle then M._legendaryToggle.Set(false) end
                end
            end
            task.wait(4)
        end
    end)
end

M.iceCastle = Vector3.new(6062.3, 155.3, -6880.9)
M._rengokuOn = false

local function rengokuDetection()
    local chest = workspace:FindFirstChild("RengokuChest", true)
    if not chest then
        local ice = workspace:FindFirstChild("IceCastle", true) or workspace:FindFirstChild("Ice Castle", true)
        chest = ice and ice:FindFirstChild("RengokuChest", true)
    end
    if not chest then return nil end
    local det = chest:FindFirstChild("Detection", true)
    local part = det or (chest:IsA("BasePart") and chest) or chest:FindFirstChildWhichIsA("BasePart")
    return part
end

function M.setRengoku(on)
    M._rengokuOn = on and true or false
    if not (M._rengokuOn and M._core) then return end
    local c = commF()
    if not c then if M._ui then M._ui.notify("Remote missing") end return end
    M._core.spawn(function()
        local tp = M._core.modules.teleport
        while M._rengokuOn do
            local part = rengokuDetection()
            if part then
                if tp then tp.go(part.Position + Vector3.new(0, 2, 0)) end
                task.wait(0.8)
                local ok, res = pcall(function() return c:InvokeServer("OpenRengoku") end)
                if M._core then M._core.info("OpenRengoku", "ok=" .. tostring(ok), tostring(res)) end
                if ok and res then
                    if M._ui then M._ui.notify("Rengoku chest opened") end
                    M._rengokuOn = false
                    if M._rengokuToggle then M._rengokuToggle.Set(false) end
                    return
                end
            else
                if tp then tp.go(M.iceCastle + Vector3.new(0, 40, 0)) end
                if M._ui then M._ui.notify("Locating Rengoku chest...") end
            end
            task.wait(1.5)
        end
    end)
end

function M.init(Core, UI)
    M._core, M._ui = Core, UI

    local function buildShop(page, d)
        if #d.swords > 0 then
            UI.section(page, "SWORDS")
            for _, s in ipairs(d.swords) do UI.button(page, s, "Buy this sword", function() M.buy("BuyItem", s) end) end
        end
        if #d.guns > 0 then
            UI.section(page, "GUNS")
            for _, g in ipairs(d.guns) do UI.button(page, g, "Buy this gun", function() M.buy("BuyItem", g) end) end
        end
        if #d.styles > 0 then
            UI.section(page, "FIGHTING STYLES")
            for _, st in ipairs(d.styles) do UI.button(page, st[1], "Buy this style", function() M.buy(st[2], true) end) end
        end
        if #d.haki > 0 then
            UI.section(page, "HAKI & MOVEMENT")
            for _, h in ipairs(d.haki) do UI.button(page, h, "Buy " .. h, function() M.buy("BuyHaki", h) end) end
        end
        if #d.items > 0 then
            UI.section(page, "ACCESSORIES")
            for _, it in ipairs(d.items) do UI.button(page, it, "Buy this item", function() M.buy("BuyItem", it) end) end
        end
    end

    local function buildLegendary(page)
        UI.section(page, "LEGENDARY SWORD (random dealer)")
        local want = { "Any" }
        for _, s in ipairs(M.legendary) do want[#want + 1] = s end
        UI.dropdown(page, "Legendary target", "Which sword to buy (Any = whatever is on sale)", want, function(sel) M._legendaryWant = sel end)
        UI.button(page, "Buy now (if present)", "Buy the sword on sale right now", function()
            local name = M.legendaryOnSale()
            if not name then UI.notify("Legendary dealer not available"); return end
            if M._legendaryWant ~= "Any" and name ~= M._legendaryWant then UI.notify("On sale: " .. name .. " (not your target)"); return end
            local res = M.buyLegendary()
            UI.notify(res == 1 and ("Bought: " .. name) or res == 0 and "Not enough money" or res == 2 and "Already owned" or "Gone")
        end)
        M._legendaryToggle = UI.toggle(page, "Auto Buy Legendary Sword", "Poll the random dealer and buy when it appears", false, function(s) M.setAutoLegendary(s) end)
    end

    buildShop(UI.page("Shop"), { swords = M.swords, guns = M.guns, styles = M.styles, haki = M.haki, items = M.items })

    local shop2 = UI.page("Shop 2")
    if shop2 then
        buildShop(shop2, M.sea2)
        buildLegendary(shop2)
        UI.section(shop2, "SPECIAL SWORDS")
        M._rengokuToggle = UI.toggle(shop2, "Auto Rengoku", "Go to the Ice Castle chest and open it (auto-off when done)", false, function(s) M.setRengoku(s) end)
    end

    local shop3 = UI.page("Shop 3")
    if shop3 then
        buildShop(shop3, M.sea3)
        buildLegendary(shop3)
    end

    Core.register("shop", M)
    return M
end

return M
end)()

genv.__BF_EVENTS = (function()
-- Events: raid automation + sea events (Sea 2 / Sea 3).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TPS = game:GetService("TeleportService")
local LP = Players.LocalPlayer

local M = {}
M.config = { element = "Flame" }
M._raidOn, M._inRaid, M._clearing = false, false, false
M.raidLoc = {
    Sea2 = { tube = Vector3.new(-6546.1, 310.5, -4767.7), button = Vector3.new(-6530.7, 304.8, -4798.4) },
    Sea3 = { tube = Vector3.new(-5010.1, 315.0, -2816.5), button = Vector3.new(-5010.1, 315.0, -2816.5) },
}
function M.currentRaidLoc()
    local info = M._core and M._core.modules.info
    return M.raidLoc[(info and info.sea) or "Sea2"] or M.raidLoc.Sea2
end
M.elements = {
    "Flame", "Ice", "Quake", "Dark", "Light", "Sand", "Magma", "Rumble", "Buddha", "Paw",
    "Gravity", "Dough", "Shadow", "Venom", "Control", "Spirit", "Bomb", "Spike", "Blizzard", "Phoenix",
}

function M._status(_) end
local fireprompt = fireproximityprompt or function() end
local fireclick = fireclickdetector or function() end
local firetouch = firetouchinterest or function() end
local function commF() local r = RS:FindFirstChild("Remotes"); return r and r:FindFirstChild("CommF_") end
local function spiritTree() local r = RS:FindFirstChild("Remotes"); return r and r:FindFirstChild("SpiritTree") end
local function raidsEvent() local r = RS:FindFirstChild("Remotes"); return r and r:FindFirstChild("Raids") end
local function hintRF()
    local mods = RS:FindFirstChild("Modules"); local n = mods and mods:FindFirstChild("Net")
    return n and n:FindFirstChild("RF/RequestNextRaidHint")
end
local function hrp() local ch = LP.Character; return ch and ch:FindFirstChild("HumanoidRootPart") end

function M.raidHint()
    local rf = hintRF(); if not rf then return end
    local ok, res = pcall(function() return rf:InvokeServer() end)
    return ok and type(res) == "table" and res or nil
end
local function isChip(t)
    return t:IsA("Tool") and (t.Name:find("Microchip") or tostring(t:GetAttribute("OriginalName") or ""):find("Microchip"))
end
local function chipTool()
    for _, pool in ipairs({ LP.Character, LP:FindFirstChild("Backpack") }) do
        if pool then for _, t in ipairs(pool:GetChildren()) do if isChip(t) then return t end end end
    end
end
local function chipEquipped()
    local ch = LP.Character
    if ch then for _, t in ipairs(ch:GetChildren()) do if isChip(t) then return true end end end
    return false
end
local function equipChip()
    if chipEquipped() then return true end
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local chip = chipTool()
    if not (hum and chip) then return false end
    for _ = 1, 4 do
        pcall(function() hum:EquipTool(chip) end)
        if not chipEquipped() then pcall(function() chip.Parent = ch end) end
        task.wait(0.15)
        if chipEquipped() then return true end
    end
    return chipEquipped()
end
local function firePromptsNear(pos, radius)
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            local part = d.Parent
            local pp = part and part:IsA("BasePart") and part.Position
            if pp and (pp - pos).Magnitude <= (radius or 30) then pcall(fireprompt, d); n = n + 1 end
        end
    end
    return n
end
local function triggerAround(pos, radius)
    radius = radius or 30
    local h = hrp()
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        local ok = false
        if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("TouchTransmitter") then
            local part = d:FindFirstAncestorWhichIsA("BasePart") or (d.Parent and d.Parent:IsA("BasePart") and d.Parent)
            if part and (part.Position - pos).Magnitude <= radius then ok = true
                if d:IsA("ProximityPrompt") then pcall(fireprompt, d)
                elseif d:IsA("ClickDetector") then pcall(fireclick, d)
                elseif d:IsA("TouchTransmitter") and h then
                    pcall(firetouch, part, h, 0); task.wait(0.05); pcall(firetouch, part, h, 1)
                end
                n = n + 1
            end
        end
    end
    return n
end
function M.raidCheck()
    local c = commF(); if not c then return end
    local ok, v = pcall(function() return c:InvokeServer("RaidsNpc", "Check") end)
    if M._core then M._core.info("RaidsNpc Check", "ok=" .. tostring(ok), tostring(v)) end
    return ok and v
end
function M.buyChip()
    local c = commF(); if not c then return end
    local ok, v = pcall(function() return c:InvokeServer("RaidsNpc", "Select", M.config.element) end)
    if M._core then M._core.info("RaidsNpc Select", M.config.element, "ok=" .. tostring(ok), tostring(v)) end
    return v
end

local function setClearing(on)
    if M._clearing == on then return end
    M._clearing = on
    local combat = M._core and M._core.modules.combat
    local farm = M._core and M._core.modules.farm
    if combat then combat.setAura(on) end
    if farm then farm.setNearestFarm(on) end
end

function M.setAutoRaid(on)
    M._raidOn = on and true or false
    if not M._raidOn then
        M._raidClearInit = false
        local combat = M._core and M._core.modules.combat
        if combat then combat.setAura(false) end
        setClearing(false); return
    end
    if not M._core then return end
    M._core.spawn(function()
        local tp = M._core.modules.teleport
        while M._raidOn do
            if M._inRaid then
                setClearing(false)
                local combat = M._core.modules.combat
                if not M._raidClearInit then
                    M._raidClearInit = true
                    if combat and combat.setupHitId then combat.setupHitId() end
                    if combat then combat.setAura(true) end
                end
                local target = combat and combat.nearestAny(1e9)
                if target and combat then
                    local part = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
                    local h = hrp()
                    if part and h and (part.Position - h.Position).Magnitude > 60 and tp then
                        tp.go(part.Position + Vector3.new(0, 12, 0))
                    end
                    combat.attackOnce(target)
                    M._status("Raid: clearing")
                else
                    M._status("Raid: waiting for next wave")
                end
                task.wait(0.35)
            else
                setClearing(false)
                if not chipTool() then M.buyChip(); task.wait(0.8) end
                local eq = equipChip()
                if not eq then
                    M._status("Raid: no Microchip — buy/hold one")
                    if M._core then M._core.warn("auto raid: chip not equipped (found=" .. tostring(chipTool() ~= nil) .. ")") end
                    task.wait(1.5)
                else
                    local loc = M.currentRaidLoc()
                    if tp then tp.go(loc.tube + Vector3.new(0, 3, 0)) end
                    task.wait(1.6)
                    equipChip()
                    local n = triggerAround(loc.button, 60)
                    M._status(("Raid: pressing button... chip=%s fired=%d"):format(tostring(chipEquipped()), n))
                    if M._core then M._core.info("auto raid", "tube button", "chip=" .. tostring(chipEquipped()), "n=" .. n) end
                    task.wait(2.5)
                end
            end
        end
    end)
    if M._core then M._core.info("auto raid", "ON " .. M.config.element) end
end

function M.teleportEvent()
    local st = spiritTree()
    if not st then if M._ui then M._ui.notify("Event remote missing") end return end
    local ok = pcall(function() return st:InvokeServer("TeleportToEvent") end)
    if M._ui then M._ui.notify(ok and "Teleporting to event..." or "No active event") end
end
function M.eliteHunter()
    local c = commF(); if not c then return end
    local ok, v = pcall(function() return c:InvokeServer("EliteHunter") end)
    if M._core then M._core.info("EliteHunter", "ok=" .. tostring(ok), tostring(v)) end
    if M._ui then M._ui.notify(ok and "Elite Hunter claimed" or "Elite Hunter error") end
end
function M.eliteProgress()
    local c = commF(); if not c then return end
    local ok, v = pcall(function() return c:InvokeServer("EliteHunter", "Progress") end)
    if M._ui then M._ui.notify(ok and ("Elite progress: " .. tostring(v)) or "Elite Hunter error") end
end
function M.leviathanGate()
    local c = commF(); if not c then return end
    local ok, v = pcall(function() return c:InvokeServer("OpenLeviathanGate") end)
    if M._core then M._core.info("OpenLeviathanGate", "ok=" .. tostring(ok), tostring(v)) end
    if M._ui then M._ui.notify(ok and v and "Leviathan gate opened" or "Leviathan unavailable") end
end
function M.serverHop()
    if M._ui then M._ui.notify("Server hopping...") end
    pcall(function() TPS:Teleport(game.PlaceId, LP) end)
end
function M.pullLevers()
    local h = hrp(); if not h then return end
    local n = firePromptsNear(h.Position, 60)
    if M._ui then M._ui.notify(n .. " prompt(s) fired nearby") end
end

function M.stop()
    M._raidOn, M._raidClearInit = false, false
    local combat = M._core and M._core.modules.combat
    if combat then combat.setAura(false) end
    setClearing(false)
end

function M.init(Core, UI)
    M._core, M._ui = Core, UI

    local ev = raidsEvent()
    if ev then
        Core.track(ev.OnClientEvent:Connect(function(kind)
            if kind == "StartTimer" then M._inRaid = true; M._raidClearInit = false; Core.info("raid started")
            elseif kind == "Finished" then
                M._inRaid, M._raidClearInit = false, false
                local combat = M._core and M._core.modules.combat
                if combat then combat.setAura(false) end
                setClearing(false); Core.info("raid finished")
            end
        end))
    end

    local page = UI.page("Raids/Events")
    if not page then return M end

    UI.section(page, "AUTO RAID")
    UI.dropdown(page, "Raid element", "Microchip element (your fruit to awaken)", M.elements, function(s) M.config.element = s end)
    UI.toggle(page, "Auto Raid", "Buy chip, start the raid, then clear all waves", false, function(s) M.setAutoRaid(s) end)
    UI.button(page, "Check raid status", "Query the raid NPC", function() local v = M.raidCheck(); if M._ui then M._ui.notify("Raid check: " .. tostring(v)) end end)
    local statFrame = UI.section(page, "Raid: idle")
    M._statusLbl = statFrame and statFrame:FindFirstChildWhichIsA("TextLabel")
    function M._status(t) if M._statusLbl then M._statusLbl.Text = t end end

    UI.section(page, "SEA EVENTS")
    UI.button(page, "Teleport to event", "Go to the active sea event", function() M.teleportEvent() end)
    UI.button(page, "Pull nearby levers / prompts", "Fire ProximityPrompts within 60 studs", function() M.pullLevers() end)
    UI.button(page, "Server hop", "Rejoin the game (find another server)", function() M.serverHop() end)

    UI.section(page, "ELITE HUNTER")
    UI.button(page, "Claim Elite Hunter", "Trigger the elite hunter reward/quest", function() M.eliteHunter() end)
    UI.button(page, "Elite progress", "Show elite hunter progress", function() M.eliteProgress() end)

    UI.section(page, "LEVIATHAN")
    UI.button(page, "Open Leviathan gate", "Open the leviathan gate (if active)", function() M.leviathanGate() end)

    Core.register("events", M)
    return M
end

return M
end)()

genv.__BF_EXTRAS = (function()
-- Extras: Sea 3 misc (Race V4, Cake Prince, Rip Indra).
local RS = game:GetService("ReplicatedStorage")

local M = {}
local function commF() local r = RS:FindFirstChild("Remotes"); return r and r:FindFirstChild("CommF_") end
local function call(action, ...)
    local c = commF(); if not c then return end
    local args = table.pack(...)
    local ok, res = pcall(function() return c:InvokeServer(action, table.unpack(args, 1, args.n)) end)
    if M._core then M._core.info("Extras", action, "ok=" .. tostring(ok), tostring(res)) end
    return ok, res
end

local function farmBoss(name)
    local farm = M._core and M._core.modules.farm
    if not farm then return false end
    for _, list in ipairs({ farm.bosses3 or {}, farm.bosses2 or {}, farm.bosses or {} }) do
        for _, b in ipairs(list) do
            if b.name == name then farm.selectedBoss = b; farm.setBossFarm(true); return true end
        end
    end
    return false
end

function M.init(Core, UI)
    M._core, M._ui = Core, UI
    local page = UI.page("Extras")
    if not page then return M end

    UI.section(page, "RACE V4")
    UI.button(page, "Check V4 progress", "Show your Race V4 progress", function()
        local ok, v = call("RaceV4Progress", "Check")
        UI.notify(ok and ("V4 progress: " .. tostring(v)) or "Race remote error")
    end)
    UI.button(page, "V4 trial teleport", "Teleport to your Race V4 trial", function() call("RaceV4Progress", "Teleport") end)
    UI.button(page, "Upgrade / Awaken race", "Buy the next race upgrade (V2/V3)", function()
        call("UpgradeRace", "Buy", 2); UI.notify("Race upgrade requested")
    end)
    UI.button(page, "Reroll race", "Reroll your race (needs a reroll item)", function()
        call("RerollRace"); UI.notify("Race reroll requested")
    end)

    UI.section(page, "SPECIAL BOSSES")
    UI.button(page, "Spawn Cake Prince", "Summon the Cake Prince boss", function()
        local ok = call("CakePrinceSpawner", true)
        UI.notify(ok and "Cake Prince summoned" or "Cake Prince error")
    end)
    UI.toggle(page, "Auto Cake Prince", "Summon Cake Prince then farm it", false, function(s)
        if s then call("CakePrinceSpawner", true); task.wait(0.5); if not farmBoss("Cake Prince") then UI.notify("Cake Prince not in boss list") end
        else local farm = Core.modules.farm; if farm then farm.setBossFarm(false) end end
    end)
    UI.button(page, "Talk to Indra", "Trigger rip_indra (raid boss)", function()
        call("IndraTalk"); UI.notify("Indra triggered")
    end)
    UI.toggle(page, "Auto Rip Indra", "Talk to Indra then farm rip_indra", false, function(s)
        if s then call("IndraTalk"); task.wait(0.5); if not farmBoss("rip_indra") then UI.notify("rip_indra not in boss list") end
        else local farm = Core.modules.farm; if farm then farm.setBossFarm(false) end end
    end)

    Core.register("extras", M)
    return M
end

return M
end)()

genv.__BF_INFO = (function()
-- Info: status tab (executor, sea, player, logs).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local M = {}
M.VERSION = "1.0.0"
M._start = os.clock()
M.sea = "Sea1"

local function dataVal(name)
    local ok, v = pcall(function() return LP.Data[name].Value end)
    return ok and v or nil
end

local function equipped(tip)
    for _, pool in ipairs({ LP.Character, LP:FindFirstChild("Backpack") }) do
        if pool then
            for _, t in ipairs(pool:GetChildren()) do
                if t:IsA("Tool") and t.ToolTip == tip then return t.Name end
            end
        end
    end
    return "-"
end

local function comma(n)
    if type(n) ~= "number" then return tostring(n) end
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function uptime()
    local s = math.floor(os.clock() - M._start)
    return ("%02d:%02d:%02d"):format(math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60)
end

local function executorName()
    local ok, name, ver = pcall(function() return identifyexecutor() end)
    if ok and name then return (ver and ver ~= "") and (tostring(name) .. " " .. tostring(ver)) or tostring(name) end
    local ok2, n2 = pcall(function() return getexecutorname() end)
    if ok2 and n2 then return tostring(n2) end
    return "Unknown"
end

function M.init(Core, UI)
    M._core, M._ui = Core, UI
    local page = UI.page("Info")
    local v = {}

    UI.section(page, "SCRIPT")
    v.sea = UI.stat(page, "Sea")
    v.version = UI.stat(page, "Version")
    v.executor = UI.stat(page, "Executor")
    v.uptime = UI.stat(page, "Uptime")

    UI.section(page, "PLAYER")
    v.level = UI.stat(page, "Level")
    v.beli = UI.stat(page, "Beli")
    v.frag = UI.stat(page, "Fragments")
    v.race = UI.stat(page, "Race")

    UI.section(page, "LOADOUT")
    v.fruit = UI.stat(page, "Fruit")
    v.sword = UI.stat(page, "Sword")
    v.gun = UI.stat(page, "Gun")
    v.melee = UI.stat(page, "Melee")

    v.version.Text = M.VERSION
    v.executor.Text = executorName()

    Core.spawn(function()
        while true do
            local ok, sea = pcall(function() return require(RS.Util.Realm).getCurrentSeaAsync() end)
            if ok and sea then M.sea = sea; UI.setSea(sea) end
            v.sea.Text = M.sea
            v.uptime.Text = uptime()
            v.level.Text = tostring(dataVal("Level") or "?")
            v.beli.Text = comma(dataVal("Beli") or 0)
            v.frag.Text = comma(dataVal("Fragments") or 0)
            v.race.Text = tostring(dataVal("Race") or "?")
            v.fruit.Text = tostring(dataVal("DevilFruit") or "None")
            v.sword.Text = equipped("Sword")
            v.gun.Text = equipped("Gun")
            v.melee.Text = equipped("Melee")
            task.wait(2)
        end
    end)

    Core.register("info", M)
    return M
end

return M
end)()

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
