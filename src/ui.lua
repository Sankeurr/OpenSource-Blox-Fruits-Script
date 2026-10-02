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
