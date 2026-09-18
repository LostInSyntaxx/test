--==================================================
-- Eggs ESP Pro v2.2.0 — Rebalanced Rewrite
--==================================================
--!strict

--==================================================
-- [1] CONFIG — frozen, immutable
--==================================================
local Config = (function()
    local palette = {
        Color3.fromRGB( 80, 200, 255), Color3.fromRGB(140, 100, 255),
        Color3.fromRGB(  0, 235, 130), Color3.fromRGB(255, 130,  60),
        Color3.fromRGB(255,  80, 180), Color3.fromRGB( 60, 220, 180),
        Color3.fromRGB(200, 255,  70), Color3.fromRGB(255, 200,  60),
        Color3.fromRGB( 80, 160, 255), Color3.fromRGB(220,  90, 255),
        Color3.fromRGB(255, 100, 100), Color3.fromRGB( 60, 255, 220),
    }
    return {
        Version = "2.2.0",

        ESP = {
            FillTransparency   = 0.45,
            OutlineTransparency = 0.1,
            NameSize    = 13,
            DistanceSize = 11,
            RareColor   = Color3.fromRGB(255, 215, 0),
            Palette     = palette,
            UpdateHz    = 6,          -- billboard refresh rate
            MaxDistance = 2500,
        },

        Movement = {
            Mode            = "AutoFarm",   -- "AutoFarm" | "Teleport"
            Speed           = 350,
            TPHeight        = 3,
            AntiStuckEvery  = 2.2,
            AntiStuckMinDelta = 1.2,
            ArrivalEpsilon  = 2.8,
            MaxFlightTime   = 8.0,          -- hard cap per move
        },

        Farm = {
            BestEggName      = "cherub",
            AutoEggHoldTime  = 2.5,
            AutoFarmHoldTime = 2.0,
            AutoEggDelay     = 0.4,
            EggCooldown      = 12,
            HomeDepositWait  = 1.3,
        },

        Alerts = {
            RareKeywords      = {
                "cherub","huge","exclusive","secret","titan",
                "mythic","golden","diamond","dark","rainbow","celestial",
            },
            Duration          = 6.5,
            MaxStack          = 3,
            DedupeSeconds     = 3,
        },

        UI = {
            PC     = { W = 760, H = 480 },
            Mobile = { W = 620, H = 400 },
            Anim   = 0.18,
            Radius = { R2XL = 16, RXL = 12, RLG = 8, RMD = 6, RSM = 4 },
            Text   = { Title = 14, Header = 11, Body = 11, Caption = 9, Micro = 8 },
            Pad    = { XS = 4, SM = 6, MD = 8, LG = 12, XL = 16 },
            SidebarWidth      = 160,
            SidebarItemHeight = 40,
            MaxHistoryLogs    = 50,
        },

        Colors = {
            Bg               = Color3.fromHex("#171717"),
            BgTransparency   = 0.02,
            OuterCard        = Color3.fromHex("#1F1F1F"),
            OuterTransparency = 0.02,
            NestedCard       = Color3.fromHex("#242424"),
            NestedTransparency = 0.02,
            Recessed         = Color3.fromHex("#1A1A1A"),
            CardBorder       = Color3.fromHex("#2C2C2C"),
            BorderInner      = Color3.fromHex("#333333"),
            BorderTransparency = 0.35,

            AccentGreen = Color3.fromRGB(0, 230, 118),
            AccentBlue  = Color3.fromRGB(0, 150, 255),
            AccentGold  = Color3.fromRGB(255, 215, 0),
            AccentRed   = Color3.fromRGB(255, 61, 87),

            TextPrimary   = Color3.fromRGB(255, 255, 255),
            TextSecondary = Color3.fromRGB(163, 163, 163),
            TextMuted     = Color3.fromRGB(110, 110, 110),
        },
    }
end)()

--==================================================
-- [2] SERVICES — one-time resolve, safe getters
--==================================================
local Services = {}
do
    local function safe(name)
        local ok, svc = pcall(game.GetService, game, name)
        return ok and svc or nil
    end
    Services.Players          = safe("Players")
    Services.TweenService     = safe("TweenService")
    Services.RunService       = safe("RunService")
    Services.UserInputService = safe("UserInputService")
    Services.TeleportService  = safe("TeleportService")
    Services.GuiService       = safe("GuiService")
    Services.CoreGui          = safe("CoreGui")
    Services.Workspace        = safe("Workspace")
    Services.ReplicatedStorage= safe("ReplicatedStorage")

    Services.VirtualInputManager = safe("VirtualInputManager")
    Services.VirtualUser         = safe("VirtualUser")

    Services.LocalPlayer = Services.Players and Services.Players.LocalPlayer

    -- Target parent for the ScreenGui
    local function resolveTargetParent()
        if gethui then
            local ok, hui = pcall(gethui)
            if ok and hui then return hui end
        end
        if Services.CoreGui then return Services.CoreGui end
        if Services.LocalPlayer then
            local pg = Services.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg then return pg end
            return Services.LocalPlayer:WaitForChild("PlayerGui", 10)
        end
        return nil
    end
    Services.TargetParent = resolveTargetParent()

    Services.QueueOnTeleport =
        (syn and syn.queue_on_teleport)
        or queue_on_teleport
        or (Fluxus and Fluxus.queue_on_teleport)

    Services.RenderedEggsFolder = Services.Workspace
        and Services.Workspace:FindFirstChild("RenderedEggs")
end

--==================================================
-- [3] STATE — mutable, weak where transient
--==================================================
local State = {}
do
    -- Feature toggles
    State.mainESPActive      = false
    State.antiAFKActive      = true
    State.movementMode       = "AutoFarm"

    -- Threads (cancellable)
    State.threads = { autoFarm = nil, autoBestEgg = nil, autoRebirth = nil }

    -- Active feature flags (source of truth for UI)
    State.autoFarmActive    = false
    State.autoBestEggActive = false
    State.autoRebirthActive = false

    -- Weak-keyed maps for per-instance data
    State.eggData            = setmetatable({}, { __mode = "k" })
    State.eggCooldowns       = setmetatable({}, { __mode = "k" })
    State.autoFarmProcessed  = setmetatable({}, { __mode = "k" })
    State.autoFarmEggs       = {}  -- [eggName] = true  (strong; names persist)

    -- History (bounded)
    State.farmHistory        = {}
    State.historyDirty       = true

    -- Session
    State.sessionStartTime   = os.time()
    State.totalEggsCollected = 0

    -- UI refs
    State.screenGui          = nil
    State.windowMode         = "PC"
    State.isMinimized        = false
    State.listeningForKey    = false
    State.tpKeybind          = Enum.KeyCode.T
    State.currentSearchQuery = ""
    State.sortMode           = "Name"    -- "Name" | "Distance"

    -- Alerts
    State.recentAlerts       = {}

    -- Connection tracking
    State._connections       = {}

    -- Generation counter for thread cancellation
    State._generation        = 0
end

--==================================================
-- [4] UTILITIES
--==================================================
local Util = {}

function Util.track(conn)
    if conn then table.insert(State._connections, conn) end
    return conn
end

function Util.disconnectAll()
    for _, c in ipairs(State._connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(State._connections)
end

function Util.getCharacter()
    local lp = Services.LocalPlayer
    return lp and lp.Character
end

function Util.getRoot()
    local ch = Util.getCharacter()
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

function Util.getHumanoid()
    local ch = Util.getCharacter()
    return ch and ch:FindFirstChildOfClass("Humanoid")
end

function Util.tween(obj, props, dur, style, dir)
    if not obj or not obj.Parent then return end
    local info = TweenInfo.new(
        dur or Config.UI.Anim,
        style or Enum.EasingStyle.Quart,
        dir or Enum.EasingDirection.Out
    )
    local tw = Services.TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

function Util.resetVelocity(root)
    if not root then return end
    pcall(function()
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

function Util.getCFrame(target)
    if not target or not target.Parent then return nil end
    if target:IsA("Model") then
        if target.PrimaryPart then return target.PrimaryPart.CFrame end
        local base = target:FindFirstChildWhichIsA("BasePart")
        if base then return base.CFrame end
        local ok, pivot = pcall(function() return target:GetPivot() end)
        return ok and pivot or nil
    elseif target:IsA("BasePart") then
        return target.CFrame
    end
    return nil
end

function Util.getDistance(target)
    local root = Util.getRoot()
    local cf   = Util.getCFrame(target)
    if not root or not cf then return math.huge end
    return (root.Position - cf.Position).Magnitude
end

function Util.isValidEgg(egg)
    return egg
        and egg.Parent == Services.RenderedEggsFolder
        and (egg:IsA("Model") or egg:IsA("BasePart"))
end

function Util.isRare(name)
    local lower = name:lower()
    for _, kw in ipairs(Config.Alerts.RareKeywords) do
        if string.find(lower, kw, 1, true) then return true end
    end
    return false
end

function Util.colorFor(name)
    if Util.isRare(name) then return Config.ESP.RareColor end
    local hash = 0
    for i = 1, #name do hash = hash + string.byte(name, i) * (i + 1) end
    return Config.ESP.Palette[(hash % #Config.ESP.Palette) + 1]
end

function Util.getEggImage(name)
    local lp = Services.LocalPlayer
    local pg = lp and lp:FindFirstChild("PlayerGui")
    local main   = pg and pg:FindFirstChild("Main")
    local index  = main and main:FindFirstChild("Index")
    local holders= index and index:FindFirstChild("Holders")
    local eggsH  = holders and holders:FindFirstChild("EggsHolder")
    local frame  = eggsH and eggsH:FindFirstChild(name)
    local img    = frame and frame:FindFirstChild("ImageLabel")
    if img and img:IsA("ImageLabel") then return img.Image or "" end
    return ""
end

--==================================================
-- [5] EVENT BUS — decouple features from UI
--==================================================
local Bus = {}
do
    local listeners = {}
    function Bus.on(event, fn)
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], fn)
        return function()
            local t = listeners[event]
            for i = #t, 1, -1 do if t[i] == fn then table.remove(t, i) end end
        end
    end
    function Bus.emit(event, ...)
        for _, fn in ipairs(listeners[event] or {}) do
            local ok, err = pcall(fn, ...)
            if not ok then warn("[Bus:"..event.."] "..tostring(err)) end
        end
    end
    function Bus.clear() table.clear(listeners) end
end

--==================================================
-- [6] STABILITY — AntiAFK, AutoRejoin
--==================================================
local Stability = {}
do
    local antiAFKConn = nil

    function Stability.setAntiAFK(enable)
        State.antiAFKActive = enable
        if antiAFKConn then
            pcall(function() antiAFKConn:Disconnect() end)
            antiAFKConn = nil
        end
        if enable and Services.LocalPlayer then
            antiAFKConn = Services.LocalPlayer.Idled:Connect(function()
                if not State.antiAFKActive then return end
                pcall(function()
                    if Services.VirtualUser then
                        Services.VirtualUser:CaptureController()
                        Services.VirtualUser:ClickButton2(Vector2.zero)
                    elseif Services.VirtualInputManager then
                        Services.VirtualInputManager:SendKeyEvent(true,  Enum.KeyCode.Unknown, false, game)
                        task.wait(0.05)
                        Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Unknown, false, game)
                    end
                end)
            end)
        end
    end

    local function queueAutoRejoin()
        if not Services.QueueOnTeleport then return end
        pcall(function()
            Services.QueueOnTeleport([[
                task.wait(3)
                pcall(function()
                    loadstring(game:HttpGet("https://raw.githubusercontent.com/ThiAez/EggsESP/main/loader.lua"))()
                end)
            ]])
        end)
    end

    local function doRejoin()
        task.wait(2.5)
        pcall(function()
            if #Services.Players:GetPlayers() <= 1 then
                Services.TeleportService:Teleport(game.PlaceId, Services.LocalPlayer)
            else
                Services.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Services.LocalPlayer)
            end
        end)
    end

    function Stability.setupAutoRejoin()
        if Services.GuiService then
            Util.track(Services.GuiService.ErrorMessageChanged:Connect(function(msg)
                if msg and #msg > 0 then
                    queueAutoRejoin()
                    doRejoin()
                end
            end))
        end
        task.spawn(function()
            pcall(function()
                local cg = Services.CoreGui
                local promptGui = cg and cg:WaitForChild("RobloxPromptGui", 8)
                local overlay = promptGui and promptGui:WaitForChild("promptOverlay", 8)
                if not overlay then return end
                Util.track(overlay.ChildAdded:Connect(function(child)
                    if child.Name == "ErrorPrompt" then
                        queueAutoRejoin()
                        doRejoin()
                    end
                end))
            end)
        end)
    end
end

--==================================================
-- [7] INTERACTION — fireprompt / key events
--==================================================
local Interaction = {}
do
    function Interaction.holdE(duration)
        duration = duration or 1.5
        local vim, vu = Services.VirtualInputManager, Services.VirtualUser
        if vim then pcall(function() vim:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
        elseif vu then pcall(function() vu:SetKeyDown("e") end) end
        task.wait(duration)
        if vim then pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.E, false, game) end) end
        if vu then pcall(function() vu:SetKeyUp("e") end) end
    end

    function Interaction.trigger(target, fallback)
        if not target or not target.Parent then return false end
        local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt and prompt.Enabled and fireproximityprompt then
            pcall(fireproximityprompt, prompt)
            task.wait(0.2)
            return true
        end
        Interaction.holdE(fallback)
        return true
    end
end

--==================================================
-- [8] MOVEMENT — noclip + fly-to + TP
--==================================================
local Movement = {}
do
    local noclipConn = nil
    local flying     = false

    function Movement.setNoclip(enable)
        if noclipConn then
            pcall(function() noclipConn:Disconnect() end)
            noclipConn = nil
        end
        local ch = Util.getCharacter()
        if not ch then return end
        if enable then
            noclipConn = Services.RunService.Stepped:Connect(function()
                local c = Util.getCharacter()
                if not c then return end
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
                end
            end)
        else
            for _, p in ipairs(ch:GetDescendants()) do
                if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart"
                    and not p:IsA("Accessory") and not p.Parent:IsA("Accessory") then
                    p.CanCollide = true
                end
            end
        end
    end

    function Movement.stop()
        flying = false
        local h = State.movementHumanoid
        if h and h.Parent then h.AutoRotate = true end
        State.movementHumanoid = nil
        Movement.setNoclip(false)
        Util.resetVelocity(Util.getRoot())
    end

    function Movement.teleportTo(target)
        local root = Util.getRoot()
        local cf   = Util.getCFrame(target)
        if not root or not cf then return false end
        Util.resetVelocity(root)
        root.CFrame = cf * CFrame.new(0, Config.Movement.TPHeight, 0)
        Util.resetVelocity(root)
        return true
    end

    function Movement.moveTo(target)
        if State.movementMode == "Teleport" then
            return Movement.teleportTo(target)
        end
        if flying then return false end
        local root = Util.getRoot()
        local hum  = Util.getHumanoid()
        local cf   = Util.getCFrame(target)
        if not root or not hum or not cf or hum.Health <= 0 then return false end

        local dest = cf.Position + Vector3.new(0, Config.Movement.TPHeight, 0)
        local dist = (root.Position - dest).Magnitude
        if dist <= Config.Movement.ArrivalEpsilon then
            Util.resetVelocity(root)
            root.CFrame = cf * CFrame.new(0, Config.Movement.TPHeight, 0)
            return true
        end

        flying = true
        State.movementHumanoid = hum
        local oldRotate = hum.AutoRotate
        hum.AutoRotate = false
        Movement.setNoclip(true)

        local success  = false
        local t0       = os.clock()
        local maxTime  = math.min(Config.Movement.MaxFlightTime,
                                  math.max(3.5, dist / Config.Movement.Speed + 2.5))
        local lastPos  = root.Position
        local lastChk  = os.clock()

        while flying and (os.clock() - t0) <= maxTime do
            if not target or not target.Parent or hum.Health <= 0 then break end
            if Util.getRoot() ~= root then break end

            local curCF = Util.getCFrame(target)
            if curCF then dest = curCF.Position + Vector3.new(0, Config.Movement.TPHeight, 0) end

            local offset = dest - root.Position
            local d = offset.Magnitude
            if d <= Config.Movement.ArrivalEpsilon then
                Util.resetVelocity(root)
                root.CFrame = (curCF or cf) * CFrame.new(0, Config.Movement.TPHeight, 0)
                success = true
                break
            end

            -- Anti-stuck
            if os.clock() - lastChk >= Config.Movement.AntiStuckEvery then
                if (root.Position - lastPos).Magnitude < Config.Movement.AntiStuckMinDelta then
                    root.CFrame = root.CFrame * CFrame.new(0, 4, 0)
                    Movement.setNoclip(true)
                    Util.resetVelocity(root)
                end
                lastPos = root.Position
                lastChk = os.clock()
            end

            local dt = Services.RunService.Heartbeat:Wait()
            local step = math.min(d, Config.Movement.Speed * dt)
            Util.resetVelocity(root)
            local newPos = root.Position + offset.Unit * step
            if (dest - newPos).Magnitude > 0.08 then
                root.CFrame = CFrame.lookAt(newPos, dest)
            else
                root.CFrame = (curCF or cf) * CFrame.new(0, Config.Movement.TPHeight, 0)
                success = true
                break
            end
        end

        flying = false
        if hum and hum.Parent then hum.AutoRotate = oldRotate end
        State.movementHumanoid = nil
        Movement.setNoclip(false)
        Util.resetVelocity(root)
        return success
    end
end

--==================================================
-- [9] PLOT — ownership detection + deposit
--==================================================
local Plot = {}
do
    local function ownerMatches(value)
        local lp = Services.LocalPlayer
        if not lp then return false end
        if typeof(value) == "Instance" and value == lp then return true end
        local s = tostring(value)
        return s == lp.Name or s == lp.DisplayName or s == tostring(lp.UserId)
    end

    function Plot.isOwner(plot)
        if not plot then return false end
        local folders = {
            plot:FindFirstChild("Data"),
            plot:FindFirstChild("Owner"),
            plot:FindFirstChild("Player"),
        }
        for _, f in ipairs(folders) do
            if f then
                if f:IsA("StringValue") or f:IsA("ObjectValue") or f:IsA("IntValue") then
                    if ownerMatches(f.Value) then return true end
                end
            end
        end
        for _, attr in ipairs({"Owner","Player","OwnerId","UserId"}) do
            local v = plot:GetAttribute(attr)
            if v ~= nil and ownerMatches(v) then return true end
        end
        if plot.Name == Services.LocalPlayer.Name
            or plot.Name == tostring(Services.LocalPlayer.UserId) then return true end
        local sign = plot:FindFirstChild("Sign", true) or plot:FindFirstChild("PlotSign", true)
        if sign then
            for _, o in ipairs(sign:GetDescendants()) do
                if o:IsA("TextLabel")
                    and (o.Text:find(Services.LocalPlayer.Name, 1, true)
                      or o.Text:find(Services.LocalPlayer.DisplayName, 1, true)) then
                    return true
                end
            end
        end
        return false
    end

    function Plot.findHome()
        local ws = Services.Workspace
        if not ws then return nil end
        local containers = {
            ws:FindFirstChild("Plots"), ws:FindFirstChild("PlayerPlots"),
            ws:FindFirstChild("Bases"), ws:FindFirstChild("Islands"),
            ws:FindFirstChild("Tycoons"),
        }
        for _, folder in ipairs(containers) do
            if folder then
                for _, plot in ipairs(folder:GetChildren()) do
                    if Plot.isOwner(plot) then return plot end
                end
            end
        end
        for _, child in ipairs(ws:GetChildren()) do
            if child:IsA("Model")
                and (child.Name:find("Plot") or child.Name:find("Base"))
                and Plot.isOwner(child) then
                return child
            end
        end
        return nil
    end

    local function findDepositPoint(plot)
        local candidates = {
            "Deposit","EggDeposit","Clear","Spawn","Base","Center",
        }
        for _, n in ipairs(candidates) do
            local p = plot:FindFirstChild(n, true)
            if p then return p end
        end
        return plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart") or plot
    end

    function Plot.teleportAndDeposit()
        local plot = Plot.findHome()
        if not plot then return false end
        Movement.stop()
        Util.resetVelocity(Util.getRoot())
        local point = findDepositPoint(plot)
        local arrived = Movement.moveTo(point)
        Util.resetVelocity(Util.getRoot())
        if arrived then
            task.wait(0.25)
            Interaction.trigger(point, Config.Farm.HomeDepositWait)
        end
        return arrived
    end
end

--==================================================
-- [10] ESP — billboards + highlights
--==================================================
local ESP = {}
do
    local billboardUpdater = nil

    local function ensureBillboard(egg)
        local data = State.eggData[egg]
        if not data then
            data = { Highlight = nil, NameBillboard = nil,
                     CustomColor = nil, CustomActive = false }
            State.eggData[egg] = data
        end
        if data.NameBillboard and data.NameBillboard.Parent then return data end

        local bb = Instance.new("BillboardGui")
        bb.Name = "EggESP_Info"
        bb.Size = UDim2.new(0, 180, 0, 42)
        bb.StudsOffset = Vector3.new(0, 3.5, 0)
        bb.AlwaysOnTop = true
        bb.MaxDistance = Config.ESP.MaxDistance
        bb.Enabled = false
        bb.Parent = egg

        local col = Util.colorFor(egg.Name)

        local nameL = Instance.new("TextLabel")
        nameL.Name = "EggName"
        nameL.Size = UDim2.new(1, 0, 0, 20)
        nameL.BackgroundTransparency = 1
        nameL.Text = egg.Name
        nameL.TextColor3 = col
        nameL.TextStrokeTransparency = 0.2
        nameL.TextStrokeColor3 = Color3.new()
        nameL.TextSize = Config.ESP.NameSize
        nameL.Font = Enum.Font.GothamBold
        nameL.Parent = bb

        local distL = Instance.new("TextLabel")
        distL.Name = "Distance"
        distL.Size = UDim2.new(1, 0, 0, 16)
        distL.Position = UDim2.new(0, 0, 0, 19)
        distL.BackgroundTransparency = 1
        distL.Text = "0 studs"
        distL.TextColor3 = Color3.fromRGB(220, 225, 235)
        distL.TextStrokeTransparency = 0.4
        distL.TextStrokeColor3 = Color3.new()
        distL.TextSize = Config.ESP.DistanceSize
        distL.Font = Enum.Font.GothamMedium
        distL.Parent = bb

        data.NameBillboard = bb
        return data
    end

    function ESP.updateEgg(egg)
        if not Util.isValidEgg(egg) then return end
        local data = ensureBillboard(egg)
        local baseColor = Util.colorFor(egg.Name)
        local color = (data.CustomActive and data.CustomColor) or baseColor
        local show = State.mainESPActive or data.CustomActive

        if show then
            if not data.Highlight or not data.Highlight.Parent then
                local h = Instance.new("Highlight")
                h.Name = "EggESP_Highlight"
                h.Adornee = egg
                h.FillTransparency = Config.ESP.FillTransparency
                h.OutlineTransparency = Config.ESP.OutlineTransparency
                h.Parent = egg
                data.Highlight = h
            end
            data.Highlight.FillColor = color
            data.Highlight.OutlineColor = color
            data.Highlight.Enabled = true
            if data.NameBillboard then
                data.NameBillboard.Enabled = true
                local nameL = data.NameBillboard:FindFirstChild("EggName")
                if nameL then nameL.Text = egg.Name; nameL.TextColor3 = color end
            end
        else
            if data.Highlight then data.Highlight.Enabled = false end
            if data.NameBillboard then data.NameBillboard.Enabled = false end
        end
    end

    function ESP.updateAll()
        local folder = Services.RenderedEggsFolder
        if not folder then return end
        for _, egg in ipairs(folder:GetChildren()) do ESP.updateEgg(egg) end
    end

    function ESP.removeEgg(egg)
        local data = State.eggData[egg]
        if data then
            if data.Highlight      then pcall(function() data.Highlight:Destroy()     end) end
            if data.NameBillboard  then pcall(function() data.NameBillboard:Destroy() end) end
            State.eggData[egg] = nil
        end
        State.eggCooldowns[egg]      = nil
        State.autoFarmProcessed[egg] = nil
    end

    function ESP.bindEgg(egg)
        if not egg or not egg.Parent then return end
        local conn
        conn = egg.Destroying:Connect(function()
            ESP.removeEgg(egg)
            if conn then pcall(function() conn:Disconnect() end) end
        end)
        Util.track(conn)
    end

    -- Periodic billboard refresh (single heartbeat)
    function ESP.startUpdater()
        local interval = 1 / Config.ESP.UpdateHz
        local acc = 0
        Util.track(Services.RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < interval then return end
            acc = acc - interval
            local lp = Services.LocalPlayer
            local root = Util.getRoot()
            if not root then return end
            for egg, data in pairs(State.eggData) do
                if egg and egg.Parent then
                    if data.NameBillboard and data.NameBillboard.Enabled then
                        local distL = data.NameBillboard:FindFirstChild("Distance")
                        if distL then
                            local d = Util.getDistance(egg)
                            distL.Text = (d == math.huge) and "?"
                                or string.format("%d studs", math.floor(d + 0.5))
                        end
                    end
                else
                    ESP.removeEgg(egg)
                end
            end
        end))
    end
end

--==================================================
-- [11] FARM — automation engine (selectable / best / rebirth)
--==================================================
local Farm = {}
do
    local function readyEggs()
        local folder = Services.RenderedEggsFolder
        local out = {}
        if not folder then return out end
        local now = os.clock()
        for _, egg in ipairs(folder:GetChildren()) do
            if Util.isValidEgg(egg) and State.autoFarmEggs[egg.Name] then
                local cd = State.eggCooldowns[egg]
                if not (cd and now <= cd) and not State.autoFarmProcessed[egg] then
                    table.insert(out, egg)
                end
            end
        end
        table.sort(out, function(a, b) return a.Name:lower() < b.Name:lower() end)
        return out
    end

    local function bestEgg()
        local folder = Services.RenderedEggsFolder
        if not folder then return nil end
        local now = os.clock()
        local q = Config.Farm.BestEggName:lower()
        for _, egg in ipairs(folder:GetChildren()) do
            local cd = State.eggCooldowns[egg]
            if not (cd and now <= cd)
                and Util.isValidEgg(egg)
                and string.find(egg.Name:lower(), q, 1, true) then
                return egg
            end
        end
        return nil
    end

    local function cancelThread(key)
        local t = State.threads[key]
        if t then
            pcall(function() task.cancel(t) end)
            State.threads[key] = nil
        end
    end

    local function stopKeyInput()
        if Services.VirtualInputManager then
            pcall(function()
                Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end)
        end
    end

    -- -- Selected-eggs farm --
    function Farm.stopAutoFarm()
        State.autoFarmActive = false
        Movement.stop()
        cancelThread("autoFarm")
        stopKeyInput()
    end

    function Farm.startAutoFarm()
        Farm.stopAutoFarm()
        State.autoFarmActive = true
        local gen = State._generation
        State.threads.autoFarm = task.spawn(function()
            while State.autoFarmActive and State._generation == gen do
                local hasAny = false
                for _ in pairs(State.autoFarmEggs) do hasAny = true; break end
                if not hasAny then
                    Bus.emit("status", "No eggs selected", Config.Colors.TextSecondary)
                    break
                end
                local list = readyEggs()
                if #list == 0 then
                    Bus.emit("status", "Waiting for eggs...", Config.Colors.TextSecondary)
                    task.wait(1.0)
                else
                    for _, egg in ipairs(list) do
                        if not State.autoFarmActive then break end
                        if Util.isValidEgg(egg)
                            and not State.autoFarmProcessed[egg]
                            and not (State.eggCooldowns[egg] and os.clock() <= State.eggCooldowns[egg]) then
                            local name = egg.Name
                            Bus.emit("status", "Farming: "..name, Config.Colors.AccentGreen)
                            if Movement.moveTo(egg) and State.autoFarmActive then
                                task.wait(0.2)
                                if State.autoFarmActive and Util.isValidEgg(egg) then
                                    Bus.emit("status", "Collecting "..name.."...", Config.Colors.AccentGold)
                                    Interaction.trigger(egg, Config.Farm.AutoFarmHoldTime)
                                end
                                State.eggCooldowns[egg] = os.clock() + Config.Farm.EggCooldown
                                task.wait(0.3)
                                if State.autoFarmActive then
                                    Bus.emit("status", "Returning home...", Config.Colors.AccentBlue)
                                    Movement.stop()
                                    if Plot.teleportAndDeposit() then
                                        State.autoFarmProcessed[egg] = true
                                        Farm.recordHistory(name)
                                        Bus.emit("status", "Deposited!", Config.Colors.AccentGreen)
                                    else
                                        Bus.emit("status", "Home unreachable", Config.Colors.AccentRed)
                                    end
                                end
                                task.wait(Config.Farm.AutoEggDelay)
                            end
                        end
                    end
                end
                task.wait(0.25)
            end
            State.threads.autoFarm = nil
            State.autoFarmActive = false
            Bus.emit("status", "AutoFarm idle", Config.Colors.TextSecondary)
        end)
    end

    -- -- Best-egg farm --
    function Farm.stopAutoBestEgg()
        State.autoBestEggActive = false
        Movement.stop()
        cancelThread("autoBestEgg")
        stopKeyInput()
    end

    function Farm.startAutoBestEgg()
        Farm.stopAutoBestEgg()
        State.autoBestEggActive = true
        local gen = State._generation
        State.threads.autoBestEgg = task.spawn(function()
            while State.autoBestEggActive and State._generation == gen do
                local egg = bestEgg()
                if egg and egg.Parent then
                    local name = egg.Name
                    Bus.emit("status", "Best → "..name, Config.Colors.AccentGreen)
                    if Movement.moveTo(egg) and State.autoBestEggActive then
                        task.wait(0.2)
                        if State.autoBestEggActive and egg.Parent then
                            Bus.emit("status", "Collecting "..name.."...", Config.Colors.AccentGold)
                            Interaction.trigger(egg, Config.Farm.AutoEggHoldTime)
                        end
                        State.eggCooldowns[egg] = os.clock() + Config.Farm.EggCooldown
                        task.wait(0.3)
                        if State.autoBestEggActive then
                            Bus.emit("status", "Returning home...", Config.Colors.AccentBlue)
                            Movement.stop()
                            if Plot.teleportAndDeposit() then
                                Farm.recordHistory(name)
                                Bus.emit("status", "Deposited!", Config.Colors.AccentGreen)
                            end
                        end
                        task.wait(Config.Farm.AutoEggDelay)
                    else
                        task.wait(0.5)
                    end
                else
                    Bus.emit("status", "Searching: ["..Config.Farm.BestEggName.."]...",
                             Config.Colors.TextSecondary)
                    task.wait(1.0)
                end
            end
            State.threads.autoBestEgg = nil
            State.autoBestEggActive = false
        end)
    end

    -- -- History --
    function Farm.recordHistory(name)
        table.insert(State.farmHistory, 1, {
            name = name,
            time = os.date("%H:%M:%S"),
            isRare = Util.isRare(name),
        })
        if #State.farmHistory > Config.UI.MaxHistoryLogs then
            table.remove(State.farmHistory)
        end
        State.totalEggsCollected += 1
        State.historyDirty = true
        Bus.emit("history-changed")
    end
end

--==================================================
-- [12] REBIRTH — scan + auto-loop
--==================================================
local Rebirth = {}
do
    local function getRemote()
        local rs = Services.ReplicatedStorage
        local remotes = rs and rs:FindFirstChild("Remotes")
        local gameR   = remotes and remotes:FindFirstChild("Game")
        local ev      = gameR and gameR:FindFirstChild("Rebirth")
        if ev and ev:IsA("RemoteEvent") then return ev end
        local fb = rs and rs:FindFirstChild("Rebirth", true)
        if fb and fb:IsA("RemoteEvent") then return fb end
        return nil
    end

    function Rebirth.fire()
        local ev = getRemote()
        if not ev then return false end
        return (pcall(function() ev:FireServer() end))
    end

    function Rebirth.findEggByName(eggName)
        local folder = Services.RenderedEggsFolder
        if not folder then return nil end
        local q = eggName:lower():match("^%s*(.-)%s*$")
        local now = os.clock()
        local function match(n)
            n = n:lower()
            return n == q or string.find(n, q, 1, true) or string.find(q, n, 1, true)
        end
        for _, egg in ipairs(folder:GetChildren()) do
            local cd = State.eggCooldowns[egg]
            if not (cd and now <= cd) and Util.isValidEgg(egg) and match(egg.Name) then
                return egg
            end
        end
        for _, egg in ipairs(folder:GetChildren()) do
            if Util.isValidEgg(egg) and match(egg.Name) then return egg end
        end
        return nil
    end

    function Rebirth.scanMissing()
        local missing, seen = {}, {}
        local lp = Services.LocalPlayer
        local pg = lp and lp:FindFirstChild("PlayerGui")
        if not pg then return missing end

        local function collect(container)
            if not container then return end
            for _, item in ipairs(container:GetDescendants()) do
                if item:IsA("TextLabel") then
                    local t = item.Text
                    if string.find(t, "^%s*0%s*/%s*%d+")
                        or string.find(t, "%s+0%s*/%s*%d+") then
                        local parent = item.Parent
                        if parent then
                            local candidate
                            local pn = parent.Name
                            if string.find(pn:lower(), "egg", 1, true) then
                                candidate = pn
                            else
                                for _, sib in ipairs(parent:GetChildren()) do
                                    if sib:IsA("TextLabel") and sib ~= item then
                                        local st = sib.Text:match("^%s*(.-)%s*$")
                                        if st and #st > 0
                                            and string.find(st:lower(), "egg", 1, true) then
                                            candidate = st
                                            break
                                        end
                                    end
                                end
                            end
                            if candidate and not seen[candidate:lower()] then
                                seen[candidate:lower()] = true
                                table.insert(missing, candidate)
                            end
                        end
                    end
                end
            end
        end

        local main = pg:FindFirstChild("Main")
        if main then
            for _, c in ipairs(main:GetChildren()) do
                if string.find(c.Name:lower(), "rebirth", 1, true) then collect(c) end
            end
            local frames = main:FindFirstChild("Frames")
            if frames then
                for _, c in ipairs(frames:GetChildren()) do
                    if string.find(c.Name:lower(), "rebirth", 1, true) then collect(c) end
                end
            end
        end
        for _, g in ipairs(pg:GetChildren()) do
            if g:IsA("ScreenGui") and string.find(g.Name:lower(), "rebirth", 1, true) then
                collect(g)
            end
        end
        return missing
    end

    function Rebirth.stop()
        State.autoRebirthActive = false
        Movement.stop()
        local t = State.threads.autoRebirth
        if t then
            pcall(function() task.cancel(t) end)
            State.threads.autoRebirth = nil
        end
    end

    function Rebirth.start()
        Rebirth.stop()
        State.autoRebirthActive = true
        local gen = State._generation
        State.threads.autoRebirth = task.spawn(function()
            while State.autoRebirthActive and State._generation == gen do
                Bus.emit("status", "Checking Rebirth...", Config.Colors.AccentGold)
                Rebirth.fire()
                task.wait(0.6)
                local missing = Rebirth.scanMissing()
                if #missing == 0 then
                    Bus.emit("status", "Requirements met!", Config.Colors.AccentGreen)
                    task.wait(1.2)
                    Rebirth.fire()
                    task.wait(1.5)
                else
                    Bus.emit("status",
                             "Need: ["..table.concat(missing, ", ").."]",
                             Config.Colors.AccentBlue)
                    for _, eggName in ipairs(missing) do
                        if not State.autoRebirthActive then break end
                        local target = Rebirth.findEggByName(eggName)
                        if target then
                            Bus.emit("status", "Hunting "..target.Name, Config.Colors.AccentGreen)
                            if Movement.moveTo(target)
                                and State.autoRebirthActive
                                and Util.isValidEgg(target) then
                                Bus.emit("status", "Collecting "..target.Name.."...",
                                         Config.Colors.AccentGold)
                                Interaction.trigger(target, Config.Farm.AutoFarmHoldTime)
                                State.eggCooldowns[target] =
                                    os.clock() + Config.Farm.EggCooldown
                                task.wait(0.3)
                                Bus.emit("status", "Depositing...", Config.Colors.AccentBlue)
                                Movement.stop()
                                if Plot.teleportAndDeposit() then
                                    Farm.recordHistory(target.Name)
                                    Bus.emit("status", "Deposited! Rebirthing...",
                                             Config.Colors.AccentGreen)
                                    task.wait(0.5)
                                    Rebirth.fire()
                                    task.wait(0.8)
                                end
                            end
                        else
                            Bus.emit("status",
                                     "Waiting for "..eggName.."...",
                                     Config.Colors.TextSecondary)
                            task.wait(1.0)
                        end
                    end
                end
                task.wait(0.5)
            end
            State.threads.autoRebirth = nil
            State.autoRebirthActive = false
        end)
    end
end

--==================================================
-- [13] UI — widgets
--==================================================
local UI = {}

local C = Config.Colors
local R = Config.UI.Radius
local T = Config.UI.Text
local P = Config.UI.Pad

function UI.applyCard(frame, radius, bg, stroke, strokeTrans)
    frame.BackgroundColor3 = bg or C.OuterCard
    frame.BackgroundTransparency = Config.Colors.OuterTransparency
    frame.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or R.R2XL)
    corner.Parent = frame
    local s = Instance.new("UIStroke")
    s.Color = stroke or C.CardBorder
    s.Transparency = strokeTrans or C.BorderTransparency
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = frame
    return corner, s
end

function UI.styleButton(btn, radius, normalBg, hoverBg)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or R.RLG)
    corner.Parent = btn
    local s = Instance.new("UIStroke")
    s.Color = C.BorderInner
    s.Transparency = 0.55
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = btn
    btn.AutoButtonColor = false
    btn:SetAttribute("DefaultBg", normalBg or btn.BackgroundColor3)
    local hv = hoverBg or Color3.fromRGB(44, 44, 44)
    btn.MouseEnter:Connect(function()
        Util.tween(btn, { BackgroundColor3 = hv }, 0.12)
        Util.tween(s,   { Transparency = 0.25, Color = Color3.fromRGB(75, 75, 75) }, 0.12)
    end)
    btn.MouseLeave:Connect(function()
        local bg = btn:GetAttribute("DefaultBg") or C.NestedCard
        Util.tween(btn, { BackgroundColor3 = bg }, 0.12)
        Util.tween(s,   { Transparency = 0.55, Color = C.BorderInner }, 0.12)
    end)
end

function UI.setButtonDefault(btn, color)
    if not btn then return end
    btn:SetAttribute("DefaultBg", color)
    btn.BackgroundColor3 = color
end

-- Slider drag dispatcher (single pair of global listeners)
do
    local activeSliders = {}
    local moved = Services.UserInputService.InputChanged
    local ended = Services.UserInputService.InputEnded
    moved:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            for _, cb in pairs(activeSliders) do cb(input) end
        end
    end)
    ended:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            table.clear(activeSliders)
        end
    end)
    UI._activeSliders = activeSliders
end

function UI.createToggle(parent, titleText, descText, initialValue, onToggle)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -4, 0, 52)
    frame.BackgroundColor3 = C.NestedCard
    frame.Parent = parent
    UI.applyCard(frame, R.RXL, C.NestedCard, C.BorderInner)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -80, 0, 20)
    title.Position = UDim2.new(0, 14, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = C.TextPrimary
    title.TextSize = T.Body
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local desc = Instance.new("TextLabel")
    desc.Size = UDim2.new(1, -80, 0, 16)
    desc.Position = UDim2.new(0, 14, 0, 28)
    desc.BackgroundTransparency = 1
    desc.Text = descText or ""
    desc.TextColor3 = C.TextMuted
    desc.TextSize = T.Micro
    desc.Font = Enum.Font.GothamMedium
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.Parent = frame

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(0, 44, 0, 24)
    track.Position = UDim2.new(1, -58, 0.5, -12)
    track.BackgroundColor3 = initialValue and C.AccentGreen or Color3.fromRGB(40, 40, 40)
    track.Text = ""
    track.AutoButtonColor = false
    track.Parent = frame

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(1, 0)
    tc.Parent = track

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = initialValue and UDim2.new(1, -21, 0.5, -9)
        or UDim2.new(0, 3, 0.5, -9)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.Parent = track

    local kc = Instance.new("UICorner")
    kc.CornerRadius = UDim.new(1, 0)
    kc.Parent = knob

    local state = initialValue
    track.MouseButton1Click:Connect(function()
        state = not state
        Utils_or_localTween(track, {
            BackgroundColor3 = state and C.AccentGreen or Color3.fromRGB(40, 40, 40)
        }, 0.15)
        Utils_or_localTween(knob, {
            Position = state and UDim2.new(1, -21, 0.5, -9)
                or UDim2.new(0, 3, 0.5, -9)
        }, 0.15)
        if onToggle then onToggle(state) end
    end)
    return frame
end

-- helper: keep local binding so createToggle doesn't depend on forward decl
local function Utils_or_localTween(o, p, d) return Util.tween(o, p, d) end

function UI.createSlider(parent, titleText, minVal, maxVal, defaultVal, unitStr, onChange)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -4, 0, 60)
    frame.BackgroundColor3 = C.NestedCard
    frame.Parent = parent
    UI.applyCard(frame, R.RXL, C.NestedCard, C.BorderInner)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.6, 0, 0, 20)
    title.Position = UDim2.new(0, 14, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = C.TextPrimary
    title.TextSize = T.Body
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(0.35, -14, 0, 20)
    valLbl.Position = UDim2.new(0.65, 0, 0, 8)
    valLbl.BackgroundTransparency = 1
    valLbl.Text = tostring(defaultVal).." "..(unitStr or "")
    valLbl.TextColor3 = C.AccentBlue
    valLbl.TextSize = T.Caption
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = frame

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(1, -28, 0, 6)
    track.Position = UDim2.new(0, 14, 0, 38)
    track.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    track.Text = ""
    track.AutoButtonColor = false
    track.Parent = frame

    local tcorner = Instance.new("UICorner")
    tcorner.CornerRadius = UDim.new(1, 0)
    tcorner.Parent = track

    local pct = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(pct, 0, 1, 0)
    fill.BackgroundColor3 = C.AccentBlue
    fill.BorderSizePixel = 0
    fill.Parent = track

    local fcorner = Instance.new("UICorner")
    fcorner.CornerRadius = UDim.new(1, 0)
    fcorner.Parent = fill

    local thumb = Instance.new("Frame")
    thumb.Size = UDim2.new(0, 14, 0, 14)
    thumb.Position = UDim2.new(1, -7, 0.5, -7)
    thumb.BackgroundColor3 = Color3.new(1, 1, 1)
    thumb.Parent = fill

    local thcorner = Instance.new("UICorner")
    thcorner.CornerRadius = UDim.new(1, 0)
    thcorner.Parent = thumb

    local sliderId = tostring({})
    local function update(input)
        local pos = input.Position.X
        local tpos = track.AbsolutePosition.X
        local tw = track.AbsoluteSize.X
        if tw <= 0 then return end
        local rel = math.clamp((pos - tpos) / tw, 0, 1)
        local val = math.floor(minVal + (maxVal - minVal) * rel + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        valLbl.Text = tostring(val).." "..(unitStr or "")
        if onChange then onChange(val) end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            UI._activeSliders[sliderId] = update
            update(input)
        end
    end)
    Services.UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            UI._activeSliders[sliderId] = nil
        end
    end)
    return frame
end

--==================================================
-- [14] UI — main menu mount
--==================================================
function UI.mount()
    local parent = Services.TargetParent
    if not parent then return nil end
    local old = parent:FindFirstChild("RenderedEggsESP_Menu")
    if old then pcall(function() old:Destroy() end) end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "RenderedEggsESP_Menu"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = parent
    State.screenGui = ScreenGui

    local function updateStatus(text, color)
        Bus.emit("status", text, color)
    end

    -- Alert stack --
    local AlertStack = Instance.new("Frame")
    AlertStack.Name = "AlertStack"
    AlertStack.Size = UDim2.new(0, 320, 0, 260)
    AlertStack.Position = UDim2.new(1, -335, 0, 20)
    AlertStack.BackgroundTransparency = 1
    AlertStack.Parent = ScreenGui
    local AlertLayout = Instance.new("UIListLayout")
    AlertLayout.SortOrder = Enum.SortOrder.LayoutOrder
    AlertLayout.Padding = UDim.new(0, 8)
    AlertLayout.Parent = AlertStack

    -- Device selection --
    local DeviceFrame = Instance.new("Frame")
    DeviceFrame.Name = "DeviceSelectionFrame"
    DeviceFrame.Size = UDim2.new(0, 340, 0, 170)
    DeviceFrame.Position = UDim2.new(0.5, -170, 0.5, -85)
    DeviceFrame.BackgroundColor3 = C.Bg
    DeviceFrame.BackgroundTransparency = C.BgTransparency
    DeviceFrame.BorderSizePixel = 0
    DeviceFrame.Active = true
    DeviceFrame.Parent = ScreenGui
    UI.applyCard(DeviceFrame, R.R2XL, C.Bg, C.CardBorder)

    local DeviceInner = Instance.new("Frame")
    DeviceInner.Size = UDim2.new(1, -16, 1, -16)
    DeviceInner.Position = UDim2.new(0, 8, 0, 8)
    DeviceInner.Parent = DeviceFrame
    UI.applyCard(DeviceInner, R.RXL, C.OuterCard, C.BorderInner)

    local dTitle = Instance.new("TextLabel")
    dTitle.Size = UDim2.new(1, 0, 0, 30)
    dTitle.Position = UDim2.new(0, 0, 0, 14)
    dTitle.BackgroundTransparency = 1
    dTitle.Text = "Select Device / เลือกอุปกรณ์"
    dTitle.TextColor3 = C.TextPrimary
    dTitle.TextSize = T.Title
    dTitle.Font = Enum.Font.GothamBold
    dTitle.Parent = DeviceInner

    local dSub = Instance.new("TextLabel")
    dSub.Size = UDim2.new(1, 0, 0, 16)
    dSub.Position = UDim2.new(0, 0, 0, 40)
    dSub.BackgroundTransparency = 1
    dSub.Text = "Sidebar Navigation • Nested Card Architecture"
    dSub.TextColor3 = C.TextMuted
    dSub.TextSize = T.Caption
    dSub.Font = Enum.Font.GothamMedium
    dSub.Parent = DeviceInner

    local PCBtn = Instance.new("TextButton")
    PCBtn.Size = UDim2.new(0.5, -14, 0, 48)
    PCBtn.Position = UDim2.new(0, 10, 0, 76)
    PCBtn.BackgroundColor3 = C.NestedCard
    PCBtn.Text = "💻  PC Mode"
    PCBtn.TextColor3 = C.TextPrimary
    PCBtn.TextSize = T.Header
    PCBtn.Font = Enum.Font.GothamBold
    PCBtn.Parent = DeviceInner
    UI.styleButton(PCBtn, R.RLG, C.NestedCard)

    local MobileBtn = Instance.new("TextButton")
    MobileBtn.Size = UDim2.new(0.5, -14, 0, 48)
    MobileBtn.Position = UDim2.new(0.5, 4, 0, 76)
    MobileBtn.BackgroundColor3 = C.NestedCard
    MobileBtn.Text = "📱  Mobile"
    MobileBtn.TextColor3 = C.TextPrimary
    MobileBtn.TextSize = T.Header
    MobileBtn.Font = Enum.Font.GothamBold
    MobileBtn.Parent = DeviceInner
    UI.styleButton(MobileBtn, R.RLG, C.NestedCard)

    -- Main window --
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, Config.UI.PC.W, 0, Config.UI.PC.H)
    MainFrame.Position = UDim2.new(0.5, -Config.UI.PC.W/2, 0.5, -Config.UI.PC.H/2)
    MainFrame.BackgroundColor3 = C.Bg
    MainFrame.BackgroundTransparency = C.BgTransparency
    MainFrame.BorderSizePixel = 0
    MainFrame.Active = true
    MainFrame.Visible = false
    MainFrame.ClipsDescendants = true
    MainFrame.Parent = ScreenGui
    UI.applyCard(MainFrame, R.R2XL, C.Bg, C.CardBorder)

    local TopBar = Instance.new("Frame")
    TopBar.Name = "TopBar"
    TopBar.Size = UDim2.new(1, 0, 0, 46)
    TopBar.BackgroundTransparency = 1
    TopBar.Parent = MainFrame

    local topDiv = Instance.new("Frame")
    topDiv.Size = UDim2.new(1, -24, 0, 1)
    topDiv.Position = UDim2.new(0, 12, 1, -1)
    topDiv.BackgroundColor3 = C.BorderInner
    topDiv.BackgroundTransparency = 0.4
    topDiv.BorderSizePixel = 0
    topDiv.Parent = TopBar

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(0, 320, 0, 20)
    TitleLabel.Position = UDim2.new(0, 16, 0, 8)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = "Eggs ESP Pro"
    TitleLabel.RichText = true
    TitleLabel.TextColor3 = C.TextPrimary
    TitleLabel.TextSize = T.Title
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.Parent = TopBar

    local SubLabel = Instance.new("TextLabel")
    SubLabel.Size = UDim2.new(0, 320, 0, 14)
    SubLabel.Position = UDim2.new(0, 16, 0, 27)
    SubLabel.BackgroundTransparency = 1
    SubLabel.Text = "v"..Config.Version.." • rebalanced"
    SubLabel.TextColor3 = C.TextMuted
    SubLabel.TextSize = T.Micro
    SubLabel.Font = Enum.Font.GothamMedium
    SubLabel.TextXAlignment = Enum.TextXAlignment.Left
    SubLabel.Parent = TopBar

    local QuickStatusPill = Instance.new("Frame")
    QuickStatusPill.Size = UDim2.new(0, 160, 0, 26)
    QuickStatusPill.Position = UDim2.new(1, -300, 0.5, -13)
    QuickStatusPill.BackgroundColor3 = C.OuterCard
    QuickStatusPill.Parent = TopBar
    UI.applyCard(QuickStatusPill, R.RMD, C.OuterCard, C.BorderInner)

    local StatusDot = Instance.new("Frame")
    StatusDot.Size = UDim2.new(0, 6, 0, 6)
    StatusDot.Position = UDim2.new(0, 10, 0.5, -3)
    StatusDot.BackgroundColor3 = C.AccentGreen
    StatusDot.BorderSizePixel = 0
    StatusDot.Parent = QuickStatusPill
    local dotC = Instance.new("UICorner")
    dotC.CornerRadius = UDim.new(1, 0)
    dotC.Parent = StatusDot

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Size = UDim2.new(1, -26, 1, 0)
    StatusLabel.Position = UDim2.new(0, 22, 0, 0)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Text = "System Ready"
    StatusLabel.TextColor3 = C.AccentGreen
    StatusLabel.TextSize = T.Caption
    StatusLabel.Font = Enum.Font.GothamMedium
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
    StatusLabel.Parent = QuickStatusPill

    Bus.on("status", function(text, color)
        StatusLabel.Text = text
        StatusLabel.TextColor3 = color or C.TextPrimary
        StatusDot.BackgroundColor3 = color or C.AccentGreen
    end)

    local ClockPill = Instance.new("Frame")
    ClockPill.Size = UDim2.new(0, 86, 0, 26)
    ClockPill.Position = UDim2.new(1, -132, 0.5, -13)
    ClockPill.BackgroundColor3 = C.NestedCard
    ClockPill.Parent = TopBar
    UI.applyCard(ClockPill, R.RMD, C.NestedCard, C.BorderInner)

    local ClockLabel = Instance.new("TextLabel")
    ClockLabel.Size = UDim2.new(1, -24, 1, 0)
    ClockLabel.Position = UDim2.new(0, 22, 0, 0)
    ClockLabel.BackgroundTransparency = 1
    ClockLabel.Text = os.date("%H:%M:%S")
    ClockLabel.TextColor3 = C.AccentBlue
    ClockLabel.TextSize = T.Caption
    ClockLabel.Font = Enum.Font.GothamBold
    ClockLabel.TextXAlignment = Enum.TextXAlignment.Left
    ClockLabel.Parent = ClockPill

    local MinimizeBtn = Instance.new("TextButton")
    MinimizeBtn.Size = UDim2.new(0, 28, 0, 28)
    MinimizeBtn.Position = UDim2.new(1, -40, 0.5, -14)
    MinimizeBtn.BackgroundColor3 = C.OuterCard
    MinimizeBtn.Text = "—"
    MinimizeBtn.TextColor3 = C.TextSecondary
    MinimizeBtn.TextSize = 11
    MinimizeBtn.Font = Enum.Font.GothamBold
    MinimizeBtn.Parent = TopBar
    UI.styleButton(MinimizeBtn, R.RMD, C.OuterCard)

    -- Sidebar --
    local Sidebar = Instance.new("Frame")
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.new(0, Config.UI.SidebarWidth, 1, -58)
    Sidebar.Position = UDim2.new(0, 8, 0, 50)
    Sidebar.BackgroundColor3 = C.OuterCard
    Sidebar.Parent = MainFrame
    UI.applyCard(Sidebar, R.RXL, C.OuterCard, C.CardBorder)

    local SbLayout = Instance.new("UIListLayout")
    SbLayout.SortOrder = Enum.SortOrder.LayoutOrder
    SbLayout.Padding = UDim.new(0, 3)
    SbLayout.Parent = Sidebar

    local SbPad = Instance.new("UIPadding")
    SbPad.PaddingTop = UDim.new(0, 8)
    SbPad.PaddingBottom = UDim.new(0, 56)
    SbPad.PaddingLeft = UDim.new(0, 6)
    SbPad.PaddingRight = UDim.new(0, 6)
    SbPad.Parent = Sidebar

    -- Content --
    local ContentArea = Instance.new("Frame")
    ContentArea.Name = "ContentArea"
    ContentArea.Size = UDim2.new(1, -(Config.UI.SidebarWidth + 20), 1, -58)
    ContentArea.Position = UDim2.new(0, Config.UI.SidebarWidth + 12, 0, 50)
    ContentArea.BackgroundTransparency = 1
    ContentArea.ClipsDescendants = true
    ContentArea.Parent = MainFrame

    local Tabs = {
        { id = "Eggs",     label = "Eggs",       icon = "🥚" },
        { id = "Farm",     label = "Automation", icon = "⚡" },
        { id = "Time",     label = "Time",       icon = "⏱️" },
        { id = "History",  label = "History",    icon = "📜" },
        { id = "Settings", label = "Settings",   icon = "⚙️" },
    }
    local tabButtons, tabPanels = {}, {}
    local currentTab = "Eggs"

    local function currentSize()
        if State.windowMode == "PC" then
            return Config.UI.PC.W, Config.UI.PC.H
        end
        return Config.UI.Mobile.W, Config.UI.Mobile.H
    end

    local function toggleMinimize()
        State.isMinimized = not State.isMinimized
        local w, h = currentSize()
        if State.isMinimized then
            Sidebar.Visible = false
            ContentArea.Visible = false
            Util.tween(MainFrame, { Size = UDim2.new(0, w, 0, 46) }, 0.20)
            MinimizeBtn.Text = "+"
        else
            Util.tween(MainFrame, { Size = UDim2.new(0, w, 0, h) }, 0.20)
            task.delay(0.12, function()
                if not State.isMinimized then
                    Sidebar.Visible = true
                    ContentArea.Visible = true
                end
            end)
            MinimizeBtn.Text = "—"
        end
    end
    MinimizeBtn.MouseButton1Click:Connect(toggleMinimize)

    local function switchTab(id)
        currentTab = id
        for _, tab in ipairs(Tabs) do
            local isCur = (tab.id == id)
            local btn = tabButtons[tab.id]
            local panel = tabPanels[tab.id]
            if btn then
                local bar = btn:FindFirstChild("ActiveBar")
                local ico = btn:FindFirstChild("Icon")
                local lbl = btn:FindFirstChild("Label")
                local st  = btn:FindFirstChildWhichIsA("UIStroke")
                if isCur then
                    Util.tween(btn, { BackgroundColor3 = C.NestedCard }, 0.15)
                    if bar then Util.tween(bar, { BackgroundTransparency = 0 }, 0.15) end
                    if ico then Util.tween(ico, { TextColor3 = C.TextPrimary }, 0.15) end
                    if lbl then Util.tween(lbl, { TextColor3 = C.TextPrimary }, 0.15) end
                    if st  then Util.tween(st,  { Color = C.AccentGreen, Transparency = 0.15 }, 0.15) end
                else
                    Util.tween(btn, { BackgroundColor3 = Color3.fromRGB(25,25,25) }, 0.15)
                    if bar then Util.tween(bar, { BackgroundTransparency = 1 }, 0.15) end
                    if ico then Util.tween(ico, { TextColor3 = C.TextMuted }, 0.15) end
                    if lbl then Util.tween(lbl, { TextColor3 = C.TextSecondary }, 0.15) end
                    if st  then Util.tween(st,  { Color = C.BorderInner, Transparency = 0.7 }, 0.15) end
                end
            end
            if panel then panel.Visible = isCur end
        end
    end

    for idx, tab in ipairs(Tabs) do
        local btn = Instance.new("TextButton")
        btn.Name = "Tab_"..tab.id
        btn.Size = UDim2.new(1, 0, 0, Config.UI.SidebarItemHeight)
        btn.BackgroundColor3 = (tab.id == "Eggs") and C.NestedCard or Color3.fromRGB(25,25,25)
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.LayoutOrder = idx
        btn.Parent = Sidebar

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, R.RLG)
        c.Parent = btn
        local s = Instance.new("UIStroke")
        s.Color = (tab.id == "Eggs") and C.AccentGreen or C.BorderInner
        s.Transparency = (tab.id == "Eggs") and 0.15 or 0.7
        s.Thickness = 1
        s.Parent = btn

        local bar = Instance.new("Frame")
        bar.Name = "ActiveBar"
        bar.Size = UDim2.new(0, 3, 0, 20)
        bar.Position = UDim2.new(0, 0, 0.5, -10)
        bar.BackgroundColor3 = C.AccentGreen
        bar.BackgroundTransparency = (tab.id == "Eggs") and 0 or 1
        bar.BorderSizePixel = 0
        bar.Parent = btn
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(1, 0)
        bc.Parent = bar

        local ico = Instance.new("TextLabel")
        ico.Name = "Icon"
        ico.Size = UDim2.new(0, 24, 1, 0)
        ico.Position = UDim2.new(0, 12, 0, 0)
        ico.BackgroundTransparency = 1
        ico.Text = tab.icon
        ico.TextColor3 = (tab.id == "Eggs") and C.TextPrimary or C.TextMuted
        ico.TextSize = 14
        ico.Font = Enum.Font.GothamBold
        ico.Parent = btn

        local lbl = Instance.new("TextLabel")
        lbl.Name = "Label"
        lbl.Size = UDim2.new(1, -44, 1, 0)
        lbl.Position = UDim2.new(0, 40, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = tab.label
        lbl.TextColor3 = (tab.id == "Eggs") and C.TextPrimary or C.TextSecondary
        lbl.TextSize = T.Body
        lbl.Font = Enum.Font.GothamBold
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = btn

        btn.MouseEnter:Connect(function()
            if currentTab ~= tab.id then
                Util.tween(btn, { BackgroundColor3 = Color3.fromRGB(34,34,34) }, 0.12)
                Util.tween(ico, { TextColor3 = C.TextSecondary }, 0.12)
            end
        end)
        btn.MouseLeave:Connect(function()
            if currentTab ~= tab.id then
                Util.tween(btn, { BackgroundColor3 = Color3.fromRGB(25,25,25) }, 0.12)
                Util.tween(ico, { TextColor3 = C.TextMuted }, 0.12)
            end
        end)
        btn.MouseButton1Click:Connect(function() switchTab(tab.id) end)

        tabButtons[tab.id] = btn

        local panel = Instance.new("Frame")
        panel.Name = "Panel_"..tab.id
        panel.Size = UDim2.new(1, 0, 1, 0)
        panel.BackgroundColor3 = C.OuterCard
        panel.Visible = (tab.id == "Eggs")
        panel.Parent = ContentArea
        UI.applyCard(panel, R.R2XL, C.OuterCard, C.CardBorder)
        local pp = Instance.new("UIPadding")
        pp.PaddingTop = UDim.new(0, 10)
        pp.PaddingBottom = UDim.new(0, 10)
        pp.PaddingLeft = UDim.new(0, 10)
        pp.PaddingRight = UDim.new(0, 10)
        pp.Parent = panel
        tabPanels[tab.id] = panel
    end

    --====================================
    -- [Eggs tab]
    --====================================
    local EggsPanel = tabPanels["Eggs"]

    local function createEggRow(egg, container, updateStatus, populate)
        local itemH = 38
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, itemH)
        row.BackgroundColor3 = C.Recessed
        row.BorderSizePixel = 0
        row.Parent = container
        UI.applyCard(row, R.RLG, C.Recessed, C.BorderInner)

        local icon = Instance.new("ImageLabel")
        icon.Size = UDim2.new(0, itemH - 10, 0, itemH - 10)
        icon.Position = UDim2.new(0, 8, 0.5, -(itemH-10)/2)
        icon.BackgroundTransparency = 1
        icon.Image = Util.getEggImage(egg.Name)
        icon.ScaleType = Enum.ScaleType.Fit
        icon.Parent = row

        local nameL = Instance.new("TextLabel")
        nameL.Size = UDim2.new(1, -240, 1, 0)
        nameL.Position = UDim2.new(0, itemH + 8, 0, 0)
        nameL.BackgroundTransparency = 1
        nameL.Text = egg.Name
        nameL.TextColor3 = Util.isRare(egg.Name) and C.AccentGold or C.TextPrimary
        nameL.TextSize = T.Body
        nameL.Font = Enum.Font.GothamBold
        nameL.TextXAlignment = Enum.TextXAlignment.Left
        nameL.TextTruncate = Enum.TextTruncate.AtEnd
        nameL.Parent = row

        local distBadge = Instance.new("Frame")
        distBadge.Size = UDim2.new(0, 50, 0, 20)
        distBadge.Position = UDim2.new(1, -220, 0.5, -10)
        distBadge.BackgroundColor3 = C.NestedCard
        distBadge.Parent = row
        UI.applyCard(distBadge, R.RSM, C.NestedCard, C.BorderInner)

        local distL = Instance.new("TextLabel")
        distL.Size = UDim2.new(1, 0, 1, 0)
        distL.BackgroundTransparency = 1
        distL.TextColor3 = C.TextMuted
        distL.TextSize = T.Caption
        distL.Font = Enum.Font.Gotham
        local d = Util.getDistance(egg)
        distL.Text = (d ~= math.huge) and string.format("%dst", math.floor(d+0.5)) or "--"
        distL.Parent = distBadge

        local TPBtn = Instance.new("TextButton")
        TPBtn.Size = UDim2.new(0, 38, 0, 24)
        TPBtn.Position = UDim2.new(1, -164, 0.5, -12)
        TPBtn.BackgroundColor3 = C.NestedCard
        TPBtn.Text = "TP"
        TPBtn.TextColor3 = C.TextPrimary
        TPBtn.TextSize = T.Caption
        TPBtn.Font = Enum.Font.GothamBold
        TPBtn.Parent = row
        UI.styleButton(TPBtn, R.RSM, C.NestedCard)
        TPBtn.MouseButton1Click:Connect(function()
            if not egg or not egg.Parent then
                updateStatus("Egg despawned!", C.AccentRed); return
            end
            if Movement.teleportTo(egg) then
                updateStatus("Teleported to "..egg.Name, C.AccentGreen)
            end
        end)

        local FarmBtn = Instance.new("TextButton")
        FarmBtn.Size = UDim2.new(0, 56, 0, 24)
        FarmBtn.Position = UDim2.new(1, -122, 0.5, -12)
        local isFarming = State.autoFarmEggs[egg.Name]
        local farmBg = isFarming and C.AccentGreen or C.NestedCard
        FarmBtn.BackgroundColor3 = farmBg
        FarmBtn.Text = isFarming and "Farm ON" or "Farm"
        FarmBtn.TextColor3 = isFarming and Color3.fromRGB(10,20,15) or C.TextSecondary
        FarmBtn.TextSize = T.Caption
        FarmBtn.Font = Enum.Font.GothamBold
        FarmBtn.Parent = row
        UI.styleButton(FarmBtn, R.RSM, farmBg)
        FarmBtn.MouseButton1Click:Connect(function()
            if not egg or not egg.Parent then return end
            local name = egg.Name
            if State.autoFarmEggs[name] then
                State.autoFarmEggs[name] = nil
                UI.setButtonDefault(FarmBtn, C.NestedCard)
                FarmBtn.Text = "Farm"
                FarmBtn.TextColor3 = C.TextSecondary
                updateStatus("Removed: "..name, C.TextSecondary)
                local any = false
                for _ in pairs(State.autoFarmEggs) do any = true; break end
                if not any then Farm.stopAutoFarm() end
            else
                State.autoFarmEggs[name] = true
                UI.setButtonDefault(FarmBtn, C.AccentGreen)
                FarmBtn.Text = "Farm ON"
                FarmBtn.TextColor3 = Color3.fromRGB(10,20,15)
                updateStatus("Target: "..name, C.AccentGreen)
                if not State.autoFarmActive then Farm.startAutoFarm() end
            end
            for pe in pairs(State.autoFarmProcessed) do
                if pe and pe.Name == name then State.autoFarmProcessed[pe] = nil end
            end
        end)

        local ESPBtn = Instance.new("TextButton")
        ESPBtn.Size = UDim2.new(0, 46, 0, 24)
        ESPBtn.Position = UDim2.new(1, -62, 0.5, -12)
        ESPBtn.BackgroundColor3 = C.NestedCard
        ESPBtn.TextColor3 = C.TextSecondary
        ESPBtn.TextSize = T.Caption
        ESPBtn.Font = Enum.Font.GothamBold
        ESPBtn.Parent = row
        UI.styleButton(ESPBtn, R.RSM, C.NestedCard)

        local eggColor = Util.colorFor(egg.Name)
        local ed = State.eggData[egg]
        if ed and ed.CustomActive then
            UI.setButtonDefault(ESPBtn, eggColor)
            ESPBtn.Text = "ON"
            ESPBtn.TextColor3 = Color3.fromRGB(10,10,10)
        else
            ESPBtn.Text = "ESP"
        end

        ESPBtn.MouseButton1Click:Connect(function()
            if not State.eggData[egg] then
                State.eggData[egg] = {
                    Highlight = nil, NameBillboard = nil,
                    CustomColor = eggColor, CustomActive = false
                }
            end
            local info = State.eggData[egg]
            info.CustomActive = not info.CustomActive
            info.CustomColor = eggColor
            if info.CustomActive then
                UI.setButtonDefault(ESPBtn, eggColor)
                ESPBtn.Text = "ON"
                ESPBtn.TextColor3 = Color3.fromRGB(10,10,10)
                updateStatus("Target ESP: "..egg.Name, eggColor)
            else
                UI.setButtonDefault(ESPBtn, C.NestedCard)
                ESPBtn.Text = "ESP"
                ESPBtn.TextColor3 = C.TextSecondary
                updateStatus("Target ESP: OFF", C.TextSecondary)
            end
            ESP.updateEgg(egg)
        end)

        return row
    end

    -- Live chips card --
    local LiveCard = Instance.new("Frame")
    LiveCard.Size = UDim2.new(1, 0, 0, 56)
    LiveCard.BackgroundColor3 = C.NestedCard
    LiveCard.Parent = EggsPanel
    UI.applyCard(LiveCard, R.RXL, C.NestedCard, C.BorderInner)

    local LiveTitle = Instance.new("TextLabel")
    LiveTitle.Size = UDim2.new(0.5, 0, 0, 18)
    LiveTitle.Position = UDim2.new(0, 12, 0, 8)
    LiveTitle.BackgroundTransparency = 1
    LiveTitle.Text = "🥚  Live Eggs Realtime"
    LiveTitle.TextColor3 = C.AccentGold
    LiveTitle.TextSize = T.Header
    LiveTitle.Font = Enum.Font.GothamBold
    LiveTitle.TextXAlignment = Enum.TextXAlignment.Left
    LiveTitle.Parent = LiveCard

    local LiveCount = Instance.new("TextLabel")
    LiveCount.Size = UDim2.new(0.5, -12, 0, 18)
    LiveCount.Position = UDim2.new(0.5, 0, 0, 8)
    LiveCount.BackgroundTransparency = 1
    LiveCount.Text = "Total Live: 0"
    LiveCount.TextColor3 = C.TextMuted
    LiveCount.TextSize = T.Caption
    LiveCount.Font = Enum.Font.GothamMedium
    LiveCount.TextXAlignment = Enum.TextXAlignment.Right
    LiveCount.Parent = LiveCard

    local LiveScroll = Instance.new("ScrollingFrame")
    LiveScroll.Size = UDim2.new(1, -20, 0, 26)
    LiveScroll.Position = UDim2.new(0, 10, 0, 28)
    LiveScroll.BackgroundTransparency = 1
    LiveScroll.BorderSizePixel = 0
    LiveScroll.ScrollBarThickness = 2
    LiveScroll.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    LiveScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    LiveScroll.Parent = LiveCard

    local LiveLayout = Instance.new("UIListLayout")
    LiveLayout.SortOrder = Enum.SortOrder.LayoutOrder
    LiveLayout.FillDirection = Enum.FillDirection.Horizontal
    LiveLayout.Padding = UDim.new(0, 4)
    LiveLayout.Parent = LiveScroll

    LiveLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        LiveScroll.CanvasSize = UDim2.new(0, LiveLayout.AbsoluteContentSize.X + 6, 0, 0)
    end)

    -- Toolbar --
    local Toolbar = Instance.new("Frame")
    Toolbar.Size = UDim2.new(1, 0, 0, 42)
    Toolbar.Position = UDim2.new(0, 0, 0, 64)
    Toolbar.BackgroundColor3 = C.NestedCard
    Toolbar.Parent = EggsPanel
    UI.applyCard(Toolbar, R.RXL, C.NestedCard, C.BorderInner)

    local SearchBoxC = Instance.new("Frame")
    SearchBoxC.Size = UDim2.new(0.36, 0, 0, 28)
    SearchBoxC.Position = UDim2.new(0, 8, 0.5, -14)
    SearchBoxC.BackgroundColor3 = C.Recessed
    SearchBoxC.Parent = Toolbar
    UI.applyCard(SearchBoxC, R.RMD, C.Recessed, C.BorderInner)

    local SearchBox = Instance.new("TextBox")
    SearchBox.Size = UDim2.new(1, -28, 1, 0)
    SearchBox.Position = UDim2.new(0, 10, 0, 0)
    SearchBox.BackgroundTransparency = 1
    SearchBox.PlaceholderText = "🔍 Search egg..."
    SearchBox.PlaceholderColor3 = C.TextMuted
    SearchBox.Text = ""
    SearchBox.TextColor3 = C.TextPrimary
    SearchBox.TextSize = T.Caption
    SearchBox.Font = Enum.Font.GothamMedium
    SearchBox.TextXAlignment = Enum.TextXAlignment.Left
    SearchBox.ClearTextOnFocus = false
    SearchBox.Parent = SearchBoxC

    local ClearSearch = Instance.new("TextButton")
    ClearSearch.Size = UDim2.new(0, 22, 0, 22)
    ClearSearch.Position = UDim2.new(1, -24, 0.5, -11)
    ClearSearch.BackgroundTransparency = 1
    ClearSearch.Text = "✕"
    ClearSearch.TextColor3 = C.TextMuted
    ClearSearch.TextSize = 10
    ClearSearch.Font = Enum.Font.GothamBold
    ClearSearch.Visible = false
    ClearSearch.Parent = SearchBoxC

    local FarmAllBtn = Instance.new("TextButton")
    FarmAllBtn.Size = UDim2.new(0.19, -4, 0, 28)
    FarmAllBtn.Position = UDim2.new(0.37, 2, 0.5, -14)
    FarmAllBtn.BackgroundColor3 = C.Recessed
    FarmAllBtn.Text = "⚡ Farm All"
    FarmAllBtn.TextColor3 = C.AccentGreen
    FarmAllBtn.TextSize = T.Caption
    FarmAllBtn.Font = Enum.Font.GothamBold
    FarmAllBtn.Parent = Toolbar
    UI.styleButton(FarmAllBtn, R.RMD, C.Recessed)

    local ClearFarmBtn = Instance.new("TextButton")
    ClearFarmBtn.Size = UDim2.new(0.16, -4, 0, 28)
    ClearFarmBtn.Position = UDim2.new(0.56, 2, 0.5, -14)
    ClearFarmBtn.BackgroundColor3 = C.Recessed
    ClearFarmBtn.Text = "✕ Clear"
    ClearFarmBtn.TextColor3 = C.AccentRed
    ClearFarmBtn.TextSize = T.Caption
    ClearFarmBtn.Font = Enum.Font.GothamBold
    ClearFarmBtn.Parent = Toolbar
    UI.styleButton(ClearFarmBtn, R.RMD, C.Recessed)

    local SortBtn = Instance.new("TextButton")
    SortBtn.Size = UDim2.new(0.16, -4, 0, 28)
    SortBtn.Position = UDim2.new(0.72, 2, 0.5, -14)
    SortBtn.BackgroundColor3 = C.Recessed
    SortBtn.Text = "Sort: Name"
    SortBtn.TextColor3 = C.TextPrimary
    SortBtn.TextSize = T.Caption
    SortBtn.Font = Enum.Font.GothamBold
    SortBtn.Parent = Toolbar
    UI.styleButton(SortBtn, R.RMD, C.Recessed)

    local EggCountLbl = Instance.new("TextLabel")
    EggCountLbl.Size = UDim2.new(0.11, -4, 0, 28)
    EggCountLbl.Position = UDim2.new(0.88, 0, 0.5, -14)
    EggCountLbl.BackgroundTransparency = 1
    EggCountLbl.Text = "0/0"
    EggCountLbl.TextColor3 = C.TextMuted
    EggCountLbl.TextSize = T.Caption
    EggCountLbl.Font = Enum.Font.GothamMedium
    EggCountLbl.TextXAlignment = Enum.TextXAlignment.Center
    EggCountLbl.Parent = Toolbar

    local ListCard = Instance.new("Frame")
    ListCard.Size = UDim2.new(1, 0, 1, -114)
    ListCard.Position = UDim2.new(0, 0, 0, 114)
    ListCard.BackgroundColor3 = C.NestedCard
    ListCard.Parent = EggsPanel
    UI.applyCard(ListCard, R.RXL, C.NestedCard, C.BorderInner)

    local ScrollList = Instance.new("ScrollingFrame")
    ScrollList.Size = UDim2.new(1, -16, 1, -16)
    ScrollList.Position = UDim2.new(0, 8, 0, 8)
    ScrollList.BackgroundTransparency = 1
    ScrollList.BorderSizePixel = 0
    ScrollList.ScrollBarThickness = 3
    ScrollList.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    ScrollList.CanvasSize = UDim2.new(0, 0, 0, 0)
    ScrollList.Parent = ListCard

    local ScrollLayout = Instance.new("UIListLayout")
    ScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ScrollLayout.Padding = UDim.new(0, 4)
    ScrollLayout.Parent = ScrollList

    ScrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        ScrollList.CanvasSize = UDim2.new(0, 0, 0, ScrollLayout.AbsoluteContentSize.Y + 6)
    end)

    local renderedRows = {}
    local function populateList()
        local savedPos = ScrollList.CanvasPosition
        local folder = Services.RenderedEggsFolder
        if not folder then
            EggCountLbl.Text = "0/0"
            for egg, row in pairs(renderedRows) do
                row:Destroy(); renderedRows[egg] = nil
            end
            return
        end
        local found = {}
        for _, egg in ipairs(folder:GetChildren()) do
            if Util.isValidEgg(egg) then table.insert(found, egg) end
        end
        if State.sortMode == "Distance" then
            table.sort(found, function(a,b) return Util.getDistance(a) < Util.getDistance(b) end)
        else
            table.sort(found, function(a,b) return a.Name:lower() < b.Name:lower() end)
        end
        local q = State.currentSearchQuery:lower()
        local visible = {}
        for _, egg in ipairs(found) do
            if q == "" or string.find(egg.Name:lower(), q, 1, true) then
                table.insert(visible, egg)
            end
        end
        local visibleSet = {}
        for _, egg in ipairs(visible) do visibleSet[egg] = true end
        for egg, row in pairs(renderedRows) do
            if not visibleSet[egg] or not egg.Parent then
                row:Destroy(); renderedRows[egg] = nil
            end
        end
        for i, egg in ipairs(visible) do
            local row = renderedRows[egg]
            if not row or not row.Parent then
                row = createEggRow(egg, ScrollList,
                    function(t,c) Bus.emit("status", t, c) end,
                    populateList)
                renderedRows[egg] = row
            end
            row.LayoutOrder = i
        end
        EggCountLbl.Text = string.format("%d/%d", #visible, #found)
        local empty = ScrollList:FindFirstChild("EmptyLabel")
        if #visible == 0 then
            if not empty then
                local el = Instance.new("TextLabel")
                el.Name = "EmptyLabel"
                el.Size = UDim2.new(1, -10, 0, 40)
                el.BackgroundTransparency = 1
                el.Text = "No Eggs Found / ไม่พบไข่"
                el.TextColor3 = C.TextMuted
                el.TextSize = T.Body
                el.Font = Enum.Font.GothamMedium
                el.Parent = ScrollList
            end
        elseif empty then
            empty:Destroy()
        end
        task.defer(function()
            if ScrollList and ScrollList.Parent then ScrollList.CanvasPosition = savedPos end
        end)
    end

    local chips = {}
    local function updateLiveChips()
        local folder = Services.RenderedEggsFolder
        if not folder then return end
        local counts, total = {}, 0
        for _, egg in ipairs(folder:GetChildren()) do
            if Util.isValidEgg(egg) then
                counts[egg.Name] = (counts[egg.Name] or 0) + 1
                total += 1
            end
        end
        LiveCount.Text = "Total Live: "..total
        for name, chip in pairs(chips) do
            if not counts[name] then chip:Destroy(); chips[name] = nil end
        end
        for name, count in pairs(counts) do
            local chip = chips[name]
            if chip and chip.Parent then
                local badge = chip:FindFirstChild("CountBadge")
                if badge then badge.Text = "x"..count end
            else
                local isRare = Util.isRare(name)
                chip = Instance.new("TextButton")
                chip.Size = UDim2.new(0, 138, 0, 24)
                chip.BackgroundColor3 = isRare and Color3.fromRGB(36,30,20) or C.Recessed
                chip.Text = ""
                chip.Parent = LiveScroll
                UI.applyCard(chip, R.RSM, chip.BackgroundColor3,
                    isRare and C.AccentGold or C.BorderInner)
                local ico = Instance.new("ImageLabel")
                ico.Size = UDim2.new(0, 16, 0, 16)
                ico.Position = UDim2.new(0, 5, 0.5, -8)
                ico.BackgroundTransparency = 1
                ico.Image = Util.getEggImage(name)
                ico.ScaleType = Enum.ScaleType.Fit
                ico.Parent = chip
                local title = Instance.new("TextLabel")
                title.Size = UDim2.new(1, -50, 1, 0)
                title.Position = UDim2.new(0, 25, 0, 0)
                title.BackgroundTransparency = 1
                title.Text = name
                title.TextColor3 = isRare and C.AccentGold or C.TextPrimary
                title.TextSize = T.Caption
                title.Font = Enum.Font.GothamMedium
                title.TextXAlignment = Enum.TextXAlignment.Left
                title.TextTruncate = Enum.TextTruncate.AtEnd
                title.Parent = chip
                local badge = Instance.new("TextLabel")
                badge.Name = "CountBadge"
                badge.Size = UDim2.new(0, 22, 0, 16)
                badge.Position = UDim2.new(1, -26, 0.5, -8)
                badge.BackgroundColor3 = isRare and C.AccentGold or C.NestedCard
                badge.Text = "x"..count
                badge.TextColor3 = isRare and Color3.fromRGB(15,15,20) or C.TextSecondary
                badge.TextSize = T.Micro
                badge.Font = Enum.Font.GothamBold
                badge.Parent = chip
                local bc = Instance.new("UICorner")
                bc.CornerRadius = UDim.new(0, 4)
                bc.Parent = badge
                chip.MouseButton1Click:Connect(function()
                    if SearchBox.Text == name then
                        SearchBox.Text = ""
                        State.currentSearchQuery = ""
                        ClearSearch.Visible = false
                        Bus.emit("status", "Filter cleared", C.TextSecondary)
                    else
                        SearchBox.Text = name
                        State.currentSearchQuery = name
                        ClearSearch.Visible = true
                        Bus.emit("status", "Filtered: "..name, C.AccentGreen)
                    end
                    populateList()
                end)
                chips[name] = chip
            end
        end
    end

    FarmAllBtn.MouseButton1Click:Connect(function()
        local folder = Services.RenderedEggsFolder
        if not folder then return end
        for _, egg in ipairs(folder:GetChildren()) do
            if Util.isValidEgg(egg) then State.autoFarmEggs[egg.Name] = true end
        end
        populateList()
        Bus.emit("status", "All eggs selected", C.AccentGreen)
        if not State.autoFarmActive then Farm.startAutoFarm() end
    end)

    ClearFarmBtn.MouseButton1Click:Connect(function()
        table.clear(State.autoFarmEggs)
        table.clear(State.autoFarmProcessed)
        Farm.stopAutoFarm()
        populateList()
        Bus.emit("status", "Cleared", C.AccentRed)
    end)

    SortBtn.MouseButton1Click:Connect(function()
        if State.sortMode == "Name" then
            State.sortMode = "Distance"; SortBtn.Text = "Sort: Dist"
        else
            State.sortMode = "Name"; SortBtn.Text = "Sort: Name"
        end
        populateList()
    end)

    local searchDebounce
    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local q = SearchBox.Text:match("^%s*(.-)%s*$") or ""
        ClearSearch.Visible = (#q > 0)
        if q == State.currentSearchQuery then return end
        State.currentSearchQuery = q
        if searchDebounce then task.cancel(searchDebounce) end
        searchDebounce = task.delay(0.12, populateList)
    end)

    ClearSearch.MouseButton1Click:Connect(function()
        SearchBox.Text = ""
        State.currentSearchQuery = ""
        ClearSearch.Visible = false
        populateList()
    end)

    --====================================
    -- [Automation tab]
    --====================================
    local FarmPanel = tabPanels["Farm"]
    local FarmScroll = Instance.new("ScrollingFrame")
    FarmScroll.Size = UDim2.new(1, 0, 1, 0)
    FarmScroll.BackgroundTransparency = 1
    FarmScroll.BorderSizePixel = 0
    FarmScroll.ScrollBarThickness = 3
    FarmScroll.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    FarmScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    FarmScroll.Parent = FarmPanel
    local FarmL = Instance.new("UIListLayout")
    FarmL.SortOrder = Enum.SortOrder.LayoutOrder
    FarmL.Padding = UDim.new(0, 8)
    FarmL.Parent = FarmScroll
    FarmL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        FarmScroll.CanvasSize = UDim2.new(0, 0, 0, FarmL.AbsoluteContentSize.Y + 12)
    end)

    local StopCard = Instance.new("Frame")
    StopCard.Size = UDim2.new(1, -4, 0, 56)
    StopCard.LayoutOrder = 1
    StopCard.BackgroundColor3 = C.NestedCard
    StopCard.Parent = FarmScroll
    UI.applyCard(StopCard, R.RXL, C.NestedCard, C.BorderInner)

    local ScT = Instance.new("TextLabel")
    ScT.Size = UDim2.new(1, -120, 0, 20)
    ScT.Position = UDim2.new(0, 14, 0, 8)
    ScT.BackgroundTransparency = 1
    ScT.Text = "⚡  Farm Engine Status"
    ScT.TextColor3 = C.TextPrimary
    ScT.TextSize = T.Header
    ScT.Font = Enum.Font.GothamBold
    ScT.TextXAlignment = Enum.TextXAlignment.Left
    ScT.Parent = StopCard

    local ScS = Instance.new("TextLabel")
    ScS.Size = UDim2.new(1, -120, 0, 16)
    ScS.Position = UDim2.new(0, 14, 0, 30)
    ScS.BackgroundTransparency = 1
    ScS.Text = "Master control & quick halt"
    ScS.TextColor3 = C.TextMuted
    ScS.TextSize = T.Caption
    ScS.Font = Enum.Font.GothamMedium
    ScS.TextXAlignment = Enum.TextXAlignment.Left
    ScS.Parent = StopCard

    local StopAll = Instance.new("TextButton")
    StopAll.Size = UDim2.new(0, 96, 0, 30)
    StopAll.Position = UDim2.new(1, -110, 0.5, -15)
    StopAll.BackgroundColor3 = C.AccentRed
    StopAll.Text = "■ Stop All"
    StopAll.TextColor3 = Color3.new(1,1,1)
    StopAll.TextSize = T.Caption
    StopAll.Font = Enum.Font.GothamBold
    StopAll.Parent = StopCard
    UI.styleButton(StopAll, R.RMD, C.AccentRed)

    StopAll.MouseButton1Click:Connect(function()
        Farm.stopAutoFarm()
        Farm.stopAutoBestEgg()
        Rebirth.stop()
        Bus.emit("status", "All halted", C.AccentRed)
    end)

    UI.createToggle(FarmScroll, "Auto Selected Eggs Farm",
        "คำนวณและฟาร์มไข่เฉพาะรายการที่เลือกไว้",
        State.autoFarmActive, function(en)
            if en then Farm.startAutoFarm()
            else Farm.stopAutoFarm()
                Bus.emit("status", "AutoFarm stopped", C.TextSecondary)
            end
        end)

    UI.createToggle(FarmScroll, "Auto Best Egg Target",
        "ค้นหาและเก็บไข่ที่ดีที่สุดโดยอัตโนมัติ",
        State.autoBestEggActive, function(en)
            if en then Farm.startAutoBestEgg()
            else Farm.stopAutoBestEgg()
                Bus.emit("status", "Best egg stopped", C.TextSecondary)
            end
        end)

    UI.createToggle(FarmScroll, "Auto Rebirth & Collect",
        "เก็บไข่ที่ขาดและกด Rebirth อัตโนมัติ",
        State.autoRebirthActive, function(en)
            if en then Rebirth.start()
            else Rebirth.stop()
                Bus.emit("status", "Auto Rebirth stopped", C.TextSecondary)
            end
        end)

    UI.createSlider(FarmScroll, "Movement Speed (ความเร็ว)",
        200, 1000, Config.Movement.Speed, "studs/s",
        function(v) Config.Movement.Speed = v end)

    UI.createSlider(FarmScroll, "Auto Collect Hold (กด E)",
        0.5, 5, Config.Farm.AutoFarmHoldTime, "sec",
        function(v)
            Config.Farm.AutoFarmHoldTime = v
            Config.Farm.AutoEggHoldTime = v
        end)

    UI.createSlider(FarmScroll, "Egg Cooldown (คูลดาวน์)",
        5, 30, Config.Farm.EggCooldown, "sec",
        function(v) Config.Farm.EggCooldown = v end)

    local MoveCard = Instance.new("Frame")
    MoveCard.Size = UDim2.new(1, -4, 0, 76)
    MoveCard.LayoutOrder = 5
    MoveCard.BackgroundColor3 = C.NestedCard
    MoveCard.Parent = FarmScroll
    UI.applyCard(MoveCard, R.RXL, C.NestedCard, C.BorderInner)

    local McT = Instance.new("TextLabel")
    McT.Size = UDim2.new(1, -20, 0, 20)
    McT.Position = UDim2.new(0, 14, 0, 8)
    McT.BackgroundTransparency = 1
    McT.Text = "Movement Mode"
    McT.TextColor3 = C.TextPrimary
    McT.TextSize = T.Header
    McT.Font = Enum.Font.GothamBold
    McT.TextXAlignment = Enum.TextXAlignment.Left
    McT.Parent = MoveCard

    local ModeFly = Instance.new("TextButton")
    ModeFly.Size = UDim2.new(0.5, -18, 0, 30)
    ModeFly.Position = UDim2.new(0, 10, 0, 36)
    ModeFly.BackgroundColor3 = C.AccentGreen
    ModeFly.Text = "⚡ Glide + Noclip"
    ModeFly.TextColor3 = Color3.fromRGB(10,20,15)
    ModeFly.TextSize = T.Caption
    ModeFly.Font = Enum.Font.GothamBold
    ModeFly.Parent = MoveCard
    UI.styleButton(ModeFly, R.RMD, C.AccentGreen)

    local ModeTP = Instance.new("TextButton")
    ModeTP.Size = UDim2.new(0.5, -18, 0, 30)
    ModeTP.Position = UDim2.new(0.5, 8, 0, 36)
    ModeTP.BackgroundColor3 = C.Recessed
    ModeTP.Text = "🌀 Instant TP"
    ModeTP.TextColor3 = C.TextSecondary
    ModeTP.TextSize = T.Caption
    ModeTP.Font = Enum.Font.GothamBold
    ModeTP.Parent = MoveCard
    UI.styleButton(ModeTP, R.RMD, C.Recessed)

    local function refreshMoveUI()
        if State.movementMode == "AutoFarm" then
            UI.setButtonDefault(ModeFly, C.AccentGreen)
            ModeFly.TextColor3 = Color3.fromRGB(10,20,15)
            UI.setButtonDefault(ModeTP, C.Recessed)
            ModeTP.TextColor3 = C.TextSecondary
        else
            UI.setButtonDefault(ModeFly, C.Recessed)
            ModeFly.TextColor3 = C.TextSecondary
            UI.setButtonDefault(ModeTP, C.AccentBlue)
            ModeTP.TextColor3 = Color3.new(1,1,1)
        end
    end

    ModeFly.MouseButton1Click:Connect(function()
        Movement.stop()
        State.movementMode = "AutoFarm"
        refreshMoveUI()
        Bus.emit("status", "Movement: Glide", C.AccentGreen)
    end)
    ModeTP.MouseButton1Click:Connect(function()
        Movement.stop()
        State.movementMode = "Teleport"
        refreshMoveUI()
        Bus.emit("status", "Movement: TP", C.AccentBlue)
    end)

    local UtilCard = Instance.new("Frame")
    UtilCard.Size = UDim2.new(1, -4, 0, 76)
    UtilCard.LayoutOrder = 6
    UtilCard.BackgroundColor3 = C.NestedCard
    UtilCard.Parent = FarmScroll
    UI.applyCard(UtilCard, R.RXL, C.NestedCard, C.BorderInner)

    local UcT = Instance.new("TextLabel")
    UcT.Size = UDim2.new(1, -20, 0, 20)
    UcT.Position = UDim2.new(0, 14, 0, 8)
    UcT.BackgroundTransparency = 1
    UcT.Text = "Quick Teleport & Global ESP"
    UcT.TextColor3 = C.TextPrimary
    UcT.TextSize = T.Header
    UcT.Font = Enum.Font.GothamBold
    UcT.TextXAlignment = Enum.TextXAlignment.Left
    UcT.Parent = UtilCard

    local ESPAll = Instance.new("TextButton")
    ESPAll.Size = UDim2.new(0.33, -10, 0, 30)
    ESPAll.Position = UDim2.new(0, 10, 0, 36)
    ESPAll.BackgroundColor3 = C.Recessed
    ESPAll.Text = "👁️ ESP All: OFF"
    ESPAll.TextColor3 = C.TextSecondary
    ESPAll.TextSize = T.Caption
    ESPAll.Font = Enum.Font.GothamBold
    ESPAll.Parent = UtilCard
    UI.styleButton(ESPAll, R.RMD, C.Recessed)

    local TPHome = Instance.new("TextButton")
    TPHome.Size = UDim2.new(0.33, -10, 0, 30)
    TPHome.Position = UDim2.new(0.33, 6, 0, 36)
    TPHome.BackgroundColor3 = C.Recessed
    TPHome.Text = "🏠 TP Home"
    TPHome.TextColor3 = C.TextPrimary
    TPHome.TextSize = T.Caption
    TPHome.Font = Enum.Font.GothamBold
    TPHome.Parent = UtilCard
    UI.styleButton(TPHome, R.RMD, C.Recessed)

    local AntiAFK = Instance.new("TextButton")
    AntiAFK.Size = UDim2.new(0.34, -10, 0, 30)
    AntiAFK.Position = UDim2.new(0.66, 6, 0, 36)
    AntiAFK.BackgroundColor3 = C.Recessed
    AntiAFK.Text = "🛡️ Anti-AFK: ON"
    AntiAFK.TextColor3 = C.AccentGreen
    AntiAFK.TextSize = T.Caption
    AntiAFK.Font = Enum.Font.GothamBold
    AntiAFK.Parent = UtilCard
    UI.styleButton(AntiAFK, R.RMD, C.Recessed)

    ESPAll.MouseButton1Click:Connect(function()
        State.mainESPActive = not State.mainESPActive
        if State.mainESPActive then
            ESPAll.Text = "👁️ ESP All: ON"
            ESPAll.TextColor3 = C.AccentGreen
            Bus.emit("status", "Global ESP ON", C.AccentGreen)
        else
            ESPAll.Text = "👁️ ESP All: OFF"
            ESPAll.TextColor3 = C.TextSecondary
            Bus.emit("status", "Global ESP OFF", C.TextSecondary)
        end
        ESP.updateAll()
    end)

    TPHome.MouseButton1Click:Connect(function()
        if Plot.teleportAndDeposit() then
            Bus.emit("status", "At Home", C.AccentGreen)
        else
            Bus.emit("status", "Home unreachable", C.AccentRed)
        end
    end)

    AntiAFK.MouseButton1Click:Connect(function()
        State.antiAFKActive = not State.antiAFKActive
        Stability.setAntiAFK(State.antiAFKActive)
        if State.antiAFKActive then
            AntiAFK.Text = "🛡️ Anti-AFK: ON"
            AntiAFK.TextColor3 = C.AccentGreen
            Bus.emit("status", "Anti-AFK ON", C.AccentGreen)
        else
            AntiAFK.Text = "🛡️ Anti-AFK: OFF"
            AntiAFK.TextColor3 = C.TextMuted
            Bus.emit("status", "Anti-AFK OFF", C.TextSecondary)
        end
    end)

    --====================================
    -- [Time tab]
    --====================================
    local TimePanel = tabPanels["Time"]
    local TimeScroll = Instance.new("ScrollingFrame")
    TimeScroll.Size = UDim2.new(1, 0, 1, 0)
    TimeScroll.BackgroundTransparency = 1
    TimeScroll.BorderSizePixel = 0
    TimeScroll.ScrollBarThickness = 3
    TimeScroll.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    TimeScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    TimeScroll.Parent = TimePanel
    local TL = Instance.new("UIListLayout")
    TL.SortOrder = Enum.SortOrder.LayoutOrder
    TL.Padding = UDim.new(0, 8)
    TL.Parent = TimeScroll
    TL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        TimeScroll.CanvasSize = UDim2.new(0, 0, 0, TL.AbsoluteContentSize.Y + 12)
    end)

    local BigClockCard = Instance.new("Frame")
    BigClockCard.Size = UDim2.new(1, -4, 0, 92)
    BigClockCard.LayoutOrder = 1
    BigClockCard.BackgroundColor3 = C.Recessed
    BigClockCard.Parent = TimeScroll
    UI.applyCard(BigClockCard, R.RXL, C.Recessed, C.BorderInner)

    local BigClock = Instance.new("TextLabel")
    BigClock.Size = UDim2.new(1, -20, 0, 44)
    BigClock.Position = UDim2.new(0, 10, 0, 12)
    BigClock.BackgroundTransparency = 1
    BigClock.Text = os.date("%H:%M:%S")
    BigClock.TextColor3 = C.AccentBlue
    BigClock.TextSize = 34
    BigClock.Font = Enum.Font.GothamBold
    BigClock.TextXAlignment = Enum.TextXAlignment.Center
    BigClock.Parent = BigClockCard

    local BigDate = Instance.new("TextLabel")
    BigDate.Size = UDim2.new(1, -20, 0, 20)
    BigDate.Position = UDim2.new(0, 10, 0, 60)
    BigDate.BackgroundTransparency = 1
    BigDate.Text = os.date("%A, %B %d, %Y")
    BigDate.TextColor3 = C.TextSecondary
    BigDate.TextSize = T.Body
    BigDate.Font = Enum.Font.GothamMedium
    BigDate.TextXAlignment = Enum.TextXAlignment.Center
    BigDate.Parent = BigClockCard

    local StatsCard = Instance.new("Frame")
    StatsCard.Size = UDim2.new(1, -4, 0, 150)
    StatsCard.LayoutOrder = 2
    StatsCard.BackgroundColor3 = C.NestedCard
    StatsCard.Parent = TimeScroll
    UI.applyCard(StatsCard, R.RXL, C.NestedCard, C.BorderInner)

    local StT = Instance.new("TextLabel")
    StT.Size = UDim2.new(1, -20, 0, 20)
    StT.Position = UDim2.new(0, 14, 0, 8)
    StT.BackgroundTransparency = 1
    StT.Text = "📊  Session Statistics"
    StT.TextColor3 = C.TextPrimary
    StT.TextSize = T.Header
    StT.Font = Enum.Font.GothamBold
    StT.TextXAlignment = Enum.TextXAlignment.Left
    StT.Parent = StatsCard

    local StInner = Instance.new("Frame")
    StInner.Size = UDim2.new(1, -20, 0, 106)
    StInner.Position = UDim2.new(0, 10, 0, 34)
    StInner.BackgroundColor3 = C.Recessed
    StInner.Parent = StatsCard
    UI.applyCard(StInner, R.RLG, C.Recessed, C.BorderInner)

    local function statRow(parent, y, icon, title, color)
        local r = Instance.new("Frame")
        r.Size = UDim2.new(1, 0, 0, 26)
        r.Position = UDim2.new(0, 0, 0, y)
        r.BackgroundTransparency = 1
        r.Parent = parent
        local i = Instance.new("TextLabel")
        i.Size = UDim2.new(0, 24, 1, 0)
        i.Position = UDim2.new(0, 10, 0, 0)
        i.BackgroundTransparency = 1
        i.Text = icon
        i.TextSize = 12
        i.Font = Enum.Font.GothamBold
        i.Parent = r
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(0.5, 0, 1, 0)
        t.Position = UDim2.new(0, 34, 0, 0)
        t.BackgroundTransparency = 1
        t.Text = title
        t.TextColor3 = C.TextSecondary
        t.TextSize = T.Caption
        t.Font = Enum.Font.GothamMedium
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Parent = r
        local v = Instance.new("TextLabel")
        v.Size = UDim2.new(0.5, -10, 1, 0)
        v.Position = UDim2.new(0.5, 0, 0, 0)
        v.BackgroundTransparency = 1
        v.Text = "--"
        v.TextColor3 = color or C.TextPrimary
        v.TextSize = T.Body
        v.Font = Enum.Font.GothamBold
        v.TextXAlignment = Enum.TextXAlignment.Right
        v.Parent = r
        return v
    end

    local tmCur  = statRow(StInner, 6,  "🕐", "Current Time",    C.AccentBlue)
    local tmUp   = statRow(StInner, 32, "⏳", "Session Uptime",  C.AccentGreen)
    local tmSt   = statRow(StInner, 58, "📅", "Session Started", C.TextSecondary)
    local tmEpm  = statRow(StInner, 84, "🥚", "Eggs / Minute",   C.AccentGold)
    tmSt.Text = os.date("%H:%M:%S", State.sessionStartTime)

    local TotalsCard = Instance.new("Frame")
    TotalsCard.Size = UDim2.new(1, -4, 0, 96)
    TotalsCard.LayoutOrder = 3
    TotalsCard.BackgroundColor3 = C.NestedCard
    TotalsCard.Parent = TimeScroll
    UI.applyCard(TotalsCard, R.RXL, C.NestedCard, C.BorderInner)

    local TcT = Instance.new("TextLabel")
    TcT.Size = UDim2.new(1, -20, 0, 20)
    TcT.Position = UDim2.new(0, 14, 0, 8)
    TcT.BackgroundTransparency = 1
    TcT.Text = "🥚  Total Collected This Session"
    TcT.TextColor3 = C.TextPrimary
    TcT.TextSize = T.Header
    TcT.Font = Enum.Font.GothamBold
    TcT.TextXAlignment = Enum.TextXAlignment.Left
    TcT.Parent = TotalsCard

    local TotalCnt = Instance.new("TextLabel")
    TotalCnt.Size = UDim2.new(0.5, -20, 0, 46)
    TotalCnt.Position = UDim2.new(0, 10, 0, 36)
    TotalCnt.BackgroundTransparency = 1
    TotalCnt.Text = "0"
    TotalCnt.TextColor3 = C.AccentGold
    TotalCnt.TextSize = 34
    TotalCnt.Font = Enum.Font.GothamBold
    TotalCnt.TextXAlignment = Enum.TextXAlignment.Center
    TotalCnt.Parent = TotalsCard

    local TotalCap = Instance.new("TextLabel")
    TotalCap.Size = UDim2.new(0.5, -20, 0, 46)
    TotalCap.Position = UDim2.new(0.5, 10, 0, 36)
    TotalCap.BackgroundTransparency = 1
    TotalCap.Text = "0 rare collected"
    TotalCap.TextColor3 = C.TextSecondary
    TotalCap.TextSize = T.Body
    TotalCap.Font = Enum.Font.GothamMedium
    TotalCap.TextXAlignment = Enum.TextXAlignment.Center
    TotalCap.Parent = TotalsCard

    local CtrlCard = Instance.new("Frame")
    CtrlCard.Size = UDim2.new(1, -4, 0, 76)
    CtrlCard.LayoutOrder = 4
    CtrlCard.BackgroundColor3 = C.NestedCard
    CtrlCard.Parent = TimeScroll
    UI.applyCard(CtrlCard, R.RXL, C.NestedCard, C.BorderInner)

    local CcT = Instance.new("TextLabel")
    CcT.Size = UDim2.new(1, -20, 0, 20)
    CcT.Position = UDim2.new(0, 14, 0, 8)
    CcT.BackgroundTransparency = 1
    CcT.Text = "Session Controls"
    CcT.TextColor3 = C.TextPrimary
    CcT.TextSize = T.Header
    CcT.Font = Enum.Font.GothamBold
    CcT.TextXAlignment = Enum.TextXAlignment.Left
    CcT.Parent = CtrlCard

    local ResetT = Instance.new("TextButton")
    ResetT.Size = UDim2.new(0.5, -18, 0, 30)
    ResetT.Position = UDim2.new(0, 10, 0, 36)
    ResetT.BackgroundColor3 = C.Recessed
    ResetT.Text = "🔄 Reset Session Timer"
    ResetT.TextColor3 = C.AccentGreen
    ResetT.TextSize = T.Caption
    ResetT.Font = Enum.Font.GothamBold
    ResetT.Parent = CtrlCard
    UI.styleButton(ResetT, R.RMD, C.Recessed)

    local ResetC = Instance.new("TextButton")
    ResetC.Size = UDim2.new(0.5, -18, 0, 30)
    ResetC.Position = UDim2.new(0.5, 8, 0, 36)
    ResetC.BackgroundColor3 = C.Recessed
    ResetC.Text = "🧹 Reset Egg Counters"
    ResetC.TextColor3 = C.AccentRed
    ResetC.TextSize = T.Caption
    ResetC.Font = Enum.Font.GothamBold
    ResetC.Parent = CtrlCard
    UI.styleButton(ResetC, R.RMD, C.Recessed)

    local function refreshTime()
        local now = os.time()
        local el = now - State.sessionStartTime
        local h = math.floor(el / 3600)
        local m = math.floor((el % 3600) / 60)
        local s = el % 60
        tmCur.Text = os.date("%H:%M:%S")
        tmUp.Text  = string.format("%02d:%02d:%02d", h, m, s)
        tmEpm.Text = (el > 0)
            and string.format("%.1f eggs/min", State.totalEggsCollected / (el/60))
            or "0.0 eggs/min"
        BigClock.Text = os.date("%H:%M:%S")
        BigDate.Text  = os.date("%A, %B %d, %Y")
        TotalCnt.Text = tostring(State.totalEggsCollected)
        local rare = 0
        for _, rec in ipairs(State.farmHistory) do
            if rec.isRare then rare += 1 end
        end
        TotalCap.Text = rare.." rare collected"
        ClockLabel.Text = os.date("%H:%M:%S")
    end
    refreshTime()

    ResetT.MouseButton1Click:Connect(function()
        State.sessionStartTime = os.time()
        tmSt.Text = os.date("%H:%M:%S", State.sessionStartTime)
        refreshTime()
        Bus.emit("status", "Session reset", C.AccentGreen)
    end)
    ResetC.MouseButton1Click:Connect(function()
        State.totalEggsCollected = 0
        refreshTime()
        Bus.emit("status", "Counters reset", C.AccentRed)
    end)

    --====================================
    -- [History tab]
    --====================================
    local HistPanel = tabPanels["History"]
    local HistBar = Instance.new("Frame")
    HistBar.Size = UDim2.new(1, 0, 0, 46)
    HistBar.BackgroundColor3 = C.NestedCard
    HistBar.Parent = HistPanel
    UI.applyCard(HistBar, R.RXL, C.NestedCard, C.BorderInner)

    local HistT = Instance.new("TextLabel")
    HistT.Size = UDim2.new(1, -100, 1, 0)
    HistT.Position = UDim2.new(0, 14, 0, 0)
    HistT.BackgroundTransparency = 1
    HistT.Text = "📜  Egg Farm Collection Timeline"
    HistT.TextColor3 = C.AccentGold
    HistT.TextSize = T.Header
    HistT.Font = Enum.Font.GothamBold
    HistT.TextXAlignment = Enum.TextXAlignment.Left
    HistT.Parent = HistBar

    local ClearHist = Instance.new("TextButton")
    ClearHist.Size = UDim2.new(0, 76, 0, 28)
    ClearHist.Position = UDim2.new(1, -86, 0.5, -14)
    ClearHist.BackgroundColor3 = C.Recessed
    ClearHist.Text = "Clear All"
    ClearHist.TextColor3 = C.AccentRed
    ClearHist.TextSize = T.Caption
    ClearHist.Font = Enum.Font.GothamBold
    ClearHist.Parent = HistBar
    UI.styleButton(ClearHist, R.RMD, C.Recessed)

    local HistCard = Instance.new("Frame")
    HistCard.Size = UDim2.new(1, 0, 1, -54)
    HistCard.Position = UDim2.new(0, 0, 0, 54)
    HistCard.BackgroundColor3 = C.NestedCard
    HistCard.Parent = HistPanel
    UI.applyCard(HistCard, R.RXL, C.NestedCard, C.BorderInner)

    local HistScroll = Instance.new("ScrollingFrame")
    HistScroll.Size = UDim2.new(1, -16, 1, -16)
    HistScroll.Position = UDim2.new(0, 8, 0, 8)
    HistScroll.BackgroundTransparency = 1
    HistScroll.BorderSizePixel = 0
    HistScroll.ScrollBarThickness = 3
    HistScroll.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    HistScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    HistScroll.Parent = HistCard
    local HL = Instance.new("UIListLayout")
    HL.SortOrder = Enum.SortOrder.LayoutOrder
    HL.Padding = UDim.new(0, 4)
    HL.Parent = HistScroll
    HL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        HistScroll.CanvasSize = UDim2.new(0, 0, 0, HL.AbsoluteContentSize.Y + 6)
    end)

    local function refreshHistory()
        for _, child in ipairs(HistScroll:GetChildren()) do
            if child ~= HL then child:Destroy() end
        end
        if #State.farmHistory == 0 then
            local el = Instance.new("TextLabel")
            el.Size = UDim2.new(1, 0, 0, 40)
            el.BackgroundTransparency = 1
            el.Text = "No farm history recorded yet\nยังไม่มีประวัติการเก็บไข่"
            el.TextColor3 = C.TextMuted
            el.TextSize = T.Body
            el.Font = Enum.Font.GothamMedium
            el.Parent = HistScroll
            return
        end
        for _, item in ipairs(State.farmHistory) do
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -4, 0, 34)
            card.BackgroundColor3 = item.isRare
                and Color3.fromRGB(36,30,20) or C.Recessed
            card.Parent = HistScroll
            UI.applyCard(card, R.RMD, card.BackgroundColor3,
                item.isRare and C.AccentGold or C.BorderInner)
            local ico = Instance.new("ImageLabel")
            ico.Size = UDim2.new(0, 20, 0, 20)
            ico.Position = UDim2.new(0, 8, 0.5, -10)
            ico.BackgroundTransparency = 1
            ico.Image = Util.getEggImage(item.name)
            ico.ScaleType = Enum.ScaleType.Fit
            ico.Parent = card
            local n = Instance.new("TextLabel")
            n.Size = UDim2.new(1, -120, 1, 0)
            n.Position = UDim2.new(0, 34, 0, 0)
            n.BackgroundTransparency = 1
            n.Text = item.name
            n.TextColor3 = item.isRare and C.AccentGold or C.TextPrimary
            n.TextSize = T.Body
            n.Font = Enum.Font.GothamBold
            n.TextXAlignment = Enum.TextXAlignment.Left
            n.TextTruncate = Enum.TextTruncate.AtEnd
            n.Parent = card
            local tl = Instance.new("TextLabel")
            tl.Size = UDim2.new(0, 72, 1, 0)
            tl.Position = UDim2.new(1, -80, 0, 0)
            tl.BackgroundTransparency = 1
            tl.Text = item.time
            tl.TextColor3 = C.TextMuted
            tl.TextSize = T.Caption
            tl.Font = Enum.Font.Gotham
            tl.TextXAlignment = Enum.TextXAlignment.Right
            tl.Parent = card
        end
    end

    ClearHist.MouseButton1Click:Connect(function()
        table.clear(State.farmHistory)
        refreshHistory()
        Bus.emit("status", "History cleared", C.AccentRed)
    end)
    Bus.on("history-changed", refreshHistory)

    --====================================
    -- [Settings tab]
    --====================================
    local SettingsPanel = tabPanels["Settings"]
    local SettingsScroll = Instance.new("ScrollingFrame")
    SettingsScroll.Size = UDim2.new(1, 0, 1, 0)
    SettingsScroll.BackgroundTransparency = 1
    SettingsScroll.BorderSizePixel = 0
    SettingsScroll.ScrollBarThickness = 3
    SettingsScroll.ScrollBarImageColor3 = Color3.fromRGB(60,60,60)
    SettingsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    SettingsScroll.Parent = SettingsPanel
    local SL = Instance.new("UIListLayout")
    SL.SortOrder = Enum.SortOrder.LayoutOrder
    SL.Padding = UDim.new(0, 8)
    SL.Parent = SettingsScroll
    SL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        SettingsScroll.CanvasSize = UDim2.new(0, 0, 0, SL.AbsoluteContentSize.Y + 8)
    end)

    -- Geometry card
    local GeomCard = Instance.new("Frame")
    GeomCard.Size = UDim2.new(1, -4, 0, 76)
    GeomCard.LayoutOrder = 1
    GeomCard.BackgroundColor3 = C.NestedCard
    GeomCard.Parent = SettingsScroll
    UI.applyCard(GeomCard, R.RXL, C.NestedCard, C.BorderInner)

    local GcT = Instance.new("TextLabel")
    GcT.Size = UDim2.new(1, -20, 0, 20)
    GcT.Position = UDim2.new(0, 14, 0, 8)
    GcT.BackgroundTransparency = 1
    GcT.Text = "Display & Screen Geometry Mode"
    GcT.TextColor3 = C.TextPrimary
    GcT.TextSize = T.Header
    GcT.Font = Enum.Font.GothamBold
    GcT.TextXAlignment = Enum.TextXAlignment.Left
    GcT.Parent = GeomCard

    local SetPC = Instance.new("TextButton")
    SetPC.Size = UDim2.new(0.5, -18, 0, 30)
    SetPC.Position = UDim2.new(0, 10, 0, 36)
    SetPC.BackgroundColor3 = C.Recessed
    SetPC.Text = "💻 PC Layout (760x480)"
    SetPC.TextColor3 = C.TextPrimary
    SetPC.TextSize = T.Caption
    SetPC.Font = Enum.Font.GothamBold
    SetPC.Parent = GeomCard
    UI.styleButton(SetPC, R.RMD, C.Recessed)

    local SetMob = Instance.new("TextButton")
    SetMob.Size = UDim2.new(0.5, -18, 0, 30)
    SetMob.Position = UDim2.new(0.5, 8, 0, 36)
    SetMob.BackgroundColor3 = C.Recessed
    SetMob.Text = "📱 Mobile Layout (620x400)"
    SetMob.TextColor3 = C.TextPrimary
    SetMob.TextSize = T.Caption
    SetMob.Font = Enum.Font.GothamBold
    SetMob.Parent = GeomCard
    UI.styleButton(SetMob, R.RMD, C.Recessed)

    -- Keybind card
    local KeyCard = Instance.new("Frame")
    KeyCard.Size = UDim2.new(1, -4, 0, 76)
    KeyCard.LayoutOrder = 2
    KeyCard.BackgroundColor3 = C.NestedCard
    KeyCard.Parent = SettingsScroll
    UI.applyCard(KeyCard, R.RXL, C.NestedCard, C.BorderInner)

    local KcT = Instance.new("TextLabel")
    KcT.Size = UDim2.new(1, -20, 0, 20)
    KcT.Position = UDim2.new(0, 14, 0, 8)
    KcT.BackgroundTransparency = 1
    KcT.Text = "Teleport Home & Deposit Keybind"
    KcT.TextColor3 = C.TextPrimary
    KcT.TextSize = T.Header
    KcT.Font = Enum.Font.GothamBold
    KcT.TextXAlignment = Enum.TextXAlignment.Left
    KcT.Parent = KeyCard

    local KeyBtn = Instance.new("TextButton")
    KeyBtn.Size = UDim2.new(1, -20, 0, 30)
    KeyBtn.Position = UDim2.new(0, 10, 0, 36)
    KeyBtn.BackgroundColor3 = C.Recessed
    KeyBtn.Text = "⌨️  Current: ["..State.tpKeybind.Name.."] (Click to remap)"
    KeyBtn.TextColor3 = C.AccentGold
    KeyBtn.TextSize = T.Caption
    KeyBtn.Font = Enum.Font.GothamBold
    KeyBtn.Parent = KeyCard
    UI.styleButton(KeyBtn, R.RMD, C.Recessed)

    KeyBtn.MouseButton1Click:Connect(function()
        State.listeningForKey = true
        KeyBtn.Text = "⌨️  Press any keyboard key..."
        KeyBtn.TextColor3 = C.AccentGreen
    end)

    -- Plot diagnostic card
    local DiagCard = Instance.new("Frame")
    DiagCard.Size = UDim2.new(1, -4, 0, 76)
    DiagCard.LayoutOrder = 3
    DiagCard.BackgroundColor3 = C.NestedCard
    DiagCard.Parent = SettingsScroll
    UI.applyCard(DiagCard, R.RXL, C.NestedCard, C.BorderInner)

    local DgT = Instance.new("TextLabel")
    DgT.Size = UDim2.new(1, -20, 0, 20)
    DgT.Position = UDim2.new(0, 14, 0, 8)
    DgT.BackgroundTransparency = 1
    DgT.Text = "Home Plot Detection Diagnostic"
    DgT.TextColor3 = C.TextPrimary
    DgT.TextSize = T.Header
    DgT.Font = Enum.Font.GothamBold
    DgT.TextXAlignment = Enum.TextXAlignment.Left
    DgT.Parent = DiagCard

    local DiagBtn = Instance.new("TextButton")
    DiagBtn.Size = UDim2.new(1, -20, 0, 30)
    DiagBtn.Position = UDim2.new(0, 10, 0, 36)
    DiagBtn.BackgroundColor3 = C.Recessed
    DiagBtn.Text = "🔍 Check Home Plot Link"
    DiagBtn.TextColor3 = C.TextPrimary
    DiagBtn.TextSize = T.Caption
    DiagBtn.Font = Enum.Font.GothamBold
    DiagBtn.Parent = DiagCard
    UI.styleButton(DiagBtn, R.RMD, C.Recessed)

    DiagBtn.MouseButton1Click:Connect(function()
        local plot = Plot.findHome()
        if plot then
            Bus.emit("status", "Plot: "..plot.Name, C.AccentGreen)
            DiagBtn.Text = "✅ Linked: "..plot.Name
        else
            Bus.emit("status", "No Home Plot", C.AccentRed)
            DiagBtn.Text = "❌ No Home Plot"
        end
    end)

    --====================================
    -- Rare alert rendering
    --====================================
    Bus.on("rare-egg", function(egg)
        if not egg or not egg.Parent then return end
        local now = os.clock()
        local last = State.recentAlerts[egg.Name]
        if last and (now - last) < Config.Alerts.DedupeSeconds then return end
        State.recentAlerts[egg.Name] = now

        local existing = {}
        for _, child in ipairs(AlertStack:GetChildren()) do
            if child:IsA("Frame") then table.insert(existing, child) end
        end
        while #existing >= Config.Alerts.MaxStack do
            local old = table.remove(existing, 1)
            if old then old:Destroy() end
        end

        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, 0, 0, 70)
        card.BackgroundColor3 = C.OuterCard
        card.Position = UDim2.new(1, 60, 0, 0)
        card.Parent = AlertStack
        UI.applyCard(card, R.R2XL, C.OuterCard, C.AccentGold, 0.2)

        local inner = Instance.new("Frame")
        inner.Size = UDim2.new(1, -12, 1, -12)
        inner.Position = UDim2.new(0, 6, 0, 6)
        inner.BackgroundColor3 = C.NestedCard
        inner.Parent = card
        UI.applyCard(inner, R.RXL, C.NestedCard, C.BorderInner)

        local ico = Instance.new("ImageLabel")
        ico.Size = UDim2.new(0, 40, 0, 40)
        ico.Position = UDim2.new(0, 10, 0.5, -20)
        ico.BackgroundTransparency = 1
        ico.Image = Util.getEggImage(egg.Name)
        ico.ScaleType = Enum.ScaleType.Fit
        ico.Parent = inner

        local badge = Instance.new("TextLabel")
        badge.Size = UDim2.new(1, -120, 0, 14)
        badge.Position = UDim2.new(0, 56, 0, 8)
        badge.BackgroundTransparency = 1
        badge.Text = "✨ RARE EGG SPAWNED!"
        badge.TextColor3 = C.AccentGold
        badge.TextSize = T.Caption
        badge.Font = Enum.Font.GothamBold
        badge.TextXAlignment = Enum.TextXAlignment.Left
        badge.Parent = inner

        local n = Instance.new("TextLabel")
        n.Size = UDim2.new(1, -120, 0, 18)
        n.Position = UDim2.new(0, 56, 0, 22)
        n.BackgroundTransparency = 1
        n.Text = egg.Name
        n.TextColor3 = C.TextPrimary
        n.TextSize = T.Title
        n.Font = Enum.Font.GothamBold
        n.TextXAlignment = Enum.TextXAlignment.Left
        n.TextTruncate = Enum.TextTruncate.AtEnd
        n.Parent = inner

        local dl = Instance.new("TextLabel")
        dl.Size = UDim2.new(1, -120, 0, 14)
        dl.Position = UDim2.new(0, 56, 0, 40)
        dl.BackgroundTransparency = 1
        local d = Util.getDistance(egg)
        dl.Text = (d ~= math.huge)
            and string.format("📍 %dst away", math.floor(d + 0.5))
            or "📍 Unknown"
        dl.TextColor3 = C.TextSecondary
        dl.TextSize = T.Caption
        dl.Font = Enum.Font.GothamMedium
        dl.TextXAlignment = Enum.TextXAlignment.Left
        dl.Parent = inner

        local tp = Instance.new("TextButton")
        tp.Size = UDim2.new(0, 56, 0, 28)
        tp.Position = UDim2.new(1, -62, 0.5, -14)
        tp.BackgroundColor3 = C.AccentGold
        tp.Text = "⚡ TP"
        tp.TextColor3 = Color3.fromRGB(15,15,20)
        tp.TextSize = T.Body
        tp.Font = Enum.Font.GothamBold
        tp.Parent = inner
        UI.styleButton(tp, R.RMD, C.AccentGold)

        tp.MouseButton1Click:Connect(function()
            if egg and egg.Parent then
                Movement.teleportTo(egg)
                Bus.emit("status", "Teleported to "..egg.Name, C.AccentGold)
            end
            pcall(function() card:Destroy() end)
        end)

        Util.tween(card, { Position = UDim2.new(0,0,0,0) }, 0.25, Enum.EasingStyle.Back)

        task.delay(Config.Alerts.Duration, function()
            if card and card.Parent then
                Util.tween(card, { BackgroundTransparency = 1 }, 0.3)
                task.wait(0.32)
                pcall(function() card:Destroy() end)
            end
        end)
    end)

    --====================================
    -- Dragging
    --====================================
    local dragging, dragStart, startPos = false, nil, nil
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)
    Util.track(Services.UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    Util.track(Services.UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            local cam = Services.Workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
            local fw = MainFrame.AbsoluteSize.X
            local fh = MainFrame.AbsoluteSize.Y
            local tx = math.clamp(startPos.X.Offset + delta.X, 0, math.max(0, vp.X - fw))
            local ty = math.clamp(startPos.Y.Offset + delta.Y, 0, math.max(0, vp.Y - fh))
            MainFrame.Position = UDim2.new(0, tx, 0, ty)
        end
    end))

    --====================================
    -- Global key handler
    --====================================
    Util.track(Services.UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if State.listeningForKey then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                State.tpKeybind = input.KeyCode
                State.listeningForKey = false
                KeyBtn.Text = "⌨️  Current: ["..State.tpKeybind.Name.."] (Click to remap)"
                KeyBtn.TextColor3 = C.AccentGold
                Bus.emit("status", "Keybind: "..State.tpKeybind.Name, C.AccentGreen)
            end
            return
        end
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.Escape then
            if not State.isMinimized then toggleMinimize() end
            return
        end
        if input.KeyCode == Enum.KeyCode.Period or input.KeyCode == Enum.KeyCode.Comma then
            local ids = {}
            for _, t in ipairs(Tabs) do table.insert(ids, t.id) end
            local idx = table.find(ids, currentTab) or 1
            local nextIdx = (input.KeyCode == Enum.KeyCode.Period)
                and (idx % #ids) + 1
                or ((idx - 2) % #ids) + 1
            switchTab(ids[nextIdx])
            return
        end
        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == State.tpKeybind then
            Plot.teleportAndDeposit()
        end
    end))

    --====================================
    -- Mode application
    --====================================
    local function applyMode(mode)
        State.windowMode = mode
        local w, h
        if mode == "PC" then w, h = Config.UI.PC.W, Config.UI.PC.H
        else                  w, h = Config.UI.Mobile.W, Config.UI.Mobile.H end
        MainFrame.Size = UDim2.new(0, w, 0, h)
        MainFrame.Position = UDim2.new(0.5, -w/2, 0.5, -h/2)
        if DeviceFrame and DeviceFrame.Parent then DeviceFrame:Destroy() end
        MainFrame.Visible = true
        Sidebar.Visible = not State.isMinimized
        ContentArea.Visible = not State.isMinimized
        refreshMoveUI()
        populateList()
        updateLiveChips()
    end

    PCBtn.MouseButton1Click:Connect(function() applyMode("PC") end)
    MobileBtn.MouseButton1Click:Connect(function() applyMode("Mobile") end)
    SetPC.MouseButton1Click:Connect(function() applyMode("PC") end)
    SetMob.MouseButton1Click:Connect(function() applyMode("Mobile") end)

    if Services.UserInputService.TouchEnabled
        and not Services.UserInputService.KeyboardEnabled then
        task.defer(function() applyMode("Mobile") end)
    end

    --====================================
    -- Time heartbeat
    --====================================
    local clockAcc = 0
    Util.track(Services.RunService.Heartbeat:Connect(function(dt)
        if not (ScreenGui and ScreenGui.Parent) then return end
        clockAcc = clockAcc + dt
        if clockAcc >= 1 then
            clockAcc -= 1
            refreshTime()
        end
    end))

    task.defer(function()
        populateList()
        updateLiveChips()
        refreshHistory()
    end)

    return {
        ScreenGui = ScreenGui,
        populateList = populateList,
        updateLiveChips = updateLiveChips,
    }
end

--==================================================
-- [15] BOOTSTRAP — composition root
--==================================================
local function bootstrap()
    -- Cleanup stale globals
    local existing = getgenv and getgenv().EggsESP
    if existing and existing.API and existing.API.Cleanup then
        pcall(existing.API.Cleanup)
    end

    Bus.clear()

    local ui = UI.mount()
    if not ui then
        warn("[EggsESP] Failed to mount UI (no TargetParent).")
        return
    end

    -- Character respawn handling
    if Services.LocalPlayer then
        Util.track(Services.LocalPlayer.CharacterAdded:Connect(function()
            Movement.stop()
            task.wait(1.0)
            Util.resetVelocity(Util.getRoot())
        end))
    end

    -- ESP periodic updater
    ESP.startUpdater()

    -- Bind RenderedEggs folder
    local function bindFolder(folder)
        if not folder then return end
        local dirty = false
        local function queueRefresh()
            if dirty then return end
            dirty = true
            task.delay(0.25, function()
                dirty = false
                if ui.ScreenGui and ui.ScreenGui.Parent then
                    ui.populateList()
                    ui.updateLiveChips()
                end
            end)
        end
        Util.track(folder.ChildAdded:Connect(function(egg)
            State.autoFarmProcessed[egg] = nil
            State.eggCooldowns[egg]      = nil
            ESP.updateEgg(egg)
            ESP.bindEgg(egg)
            queueRefresh()
            if Util.isRare(egg.Name) then
                Bus.emit("rare-egg", egg)
            end
        end))
        Util.track(folder.ChildRemoved:Connect(function(egg)
            ESP.removeEgg(egg)
            queueRefresh()
        end))
        for _, egg in ipairs(folder:GetChildren()) do
            ESP.updateEgg(egg)
            ESP.bindEgg(egg)
        end
    end

    if Services.RenderedEggsFolder then
        bindFolder(Services.RenderedEggsFolder)
    else
        task.spawn(function()
            local folder = Services.Workspace
                and Services.Workspace:WaitForChild("RenderedEggs", 60)
            if folder then
                Services.RenderedEggsFolder = folder
                bindFolder(folder)
                ui.populateList()
                ui.updateLiveChips()
            end
        end)
    end

    Stability.setAntiAFK(true)
    Stability.setupAutoRejoin()

    -- -- Public API --
    local api = {
        Version  = Config.Version,
        Config   = Config,
        State    = State,
        Modules  = { Farm = Farm, Rebirth = Rebirth, ESP = ESP,
                     Movement = Movement, Plot = Plot, UI = UI },
        API = {
            FireRebirth          = Rebirth.fire,
            GetMissingRebirthEggs= Rebirth.scanMissing,
            StartAutoRebirth     = Rebirth.start,
            StopAutoRebirth      = Rebirth.stop,
            StartFarm            = Farm.startAutoFarm,
            StopFarm             = Farm.stopAutoFarm,
            Cleanup              = function()
                State._generation = State._generation + 1
                Farm.stopAutoFarm()
                Farm.stopAutoBestEgg()
                Rebirth.stop()
                Movement.stop()
                if State.screenGui then
                    pcall(function() State.screenGui:Destroy() end)
                    State.screenGui = nil
                end
                Util.disconnectAll()
                Bus.clear()
                if State.antiAFKActive then
                    -- re-enable for future runs
                end
            end,
        },
    }
    if getgenv then getgenv().EggsESP = api end

    print(("[EggsESP] v%s initialized (%d eggs tracked).")
        :format(Config.Version, #(Services.RenderedEggsFolder and
                                  Services.RenderedEggsFolder:GetChildren() or {})))
end

-- Run
bootstrap()
