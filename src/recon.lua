-- Dev-only recon dump (remotes/instances). Not bundled into dist.
local DUMP_PLACE = true
local LOG = "bf_remotes.log"
writefile(LOG, "")

local function fmt(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "Instance" then return v:GetFullName() end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        if depth >= 3 then return "{...}" end
        local parts = {}
        for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. fmt(x, depth + 1) end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return t .. "(" .. tostring(v) .. ")"
end

local function log(dir, remote, ...)
    local args = table.pack(...)
    local out = {}
    for i = 1, args.n do out[i] = fmt(args[i]) end
    appendfile(LOG, string.format("%.2f %s %s(%s)\n", os.clock(), dir, remote:GetFullName(), table.concat(out, ", ")))
end

local old
old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local m = getnamecallmethod()
    if (m == "FireServer" or m == "InvokeServer") and not checkcaller() then
        pcall(log, m == "FireServer" and ">>" or ">?", self, ...)
    end
    return old(self, ...)
end))

local function watch(obj)
    if obj:IsA("RemoteEvent") then
        obj.OnClientEvent:Connect(function(...) pcall(log, "<<", obj, ...) end)
    end
end
for _, d in ipairs(game:GetDescendants()) do pcall(watch, d) end
game.DescendantAdded:Connect(function(d) pcall(watch, d) end)

if DUMP_PLACE then saveinstance() end
print("[recon] logging to " .. LOG)
