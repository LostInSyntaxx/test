local AppConfig = {
    Version = "2.1.0",

    ESPFillTransparency = 0.45,
    ESPOutlineTransparency = 0.1,
    ESPNameSize = 13,
    ESPDistanceSize = 11,

    ESPPalette = {
        Color3.fromRGB( 80, 200, 255), Color3.fromRGB(140, 100, 255),
        Color3.fromRGB(  0, 235, 130), Color3.fromRGB(255, 130,  60),
        Color3.fromRGB(255,  80, 180), Color3.fromRGB( 60, 220, 180),
        Color3.fromRGB(200, 255,  70), Color3.fromRGB(255, 200,  60),
        Color3.fromRGB( 80, 160, 255), Color3.fromRGB(220,  90, 255),
        Color3.fromRGB(255, 100, 100), Color3.fromRGB( 60, 255, 220),
    },
    ESPRareColor = Color3.fromRGB(255, 215, 0),

    TPHeight = 3,
    MovementSpeed = 500,
    HomeDepositWait = 1.3,
    AntiStuckThreshold = 2.2,

    BestEggName = "cherub",
    AutoEggHoldTime = 2.5,
    AutoFarmHoldTime = 2.0,
    AutoEggDelay = 0.4,
    EggCooldownSeconds = 12,

    RareKeywords = {
        "cherub", "huge", "exclusive", "secret", "titan",
        "mythic", "golden", "diamond", "dark", "rainbow", "celestial"
    },
    AlertDuration = 6.5,
    MaxAlerts = 3,
    AlertDedupeSeconds = 3,

    PCWidth = 760,
    PCHeight = 480,
    MobileWidth = 620,
    MobileHeight = 400,
    AnimationTime = 0.18,

    Radius2XL = 16, RadiusXL = 12, RadiusLG = 8, RadiusMD = 6, RadiusSM = 4,

    TextTitle = 14,
    TextHeader = 11,
    TextBody = 11,
    TextCaption = 9,
    TextMicro = 8,

    PadXS = 4, PadSM = 6, PadMD = 8, PadLG = 12, PadXL = 16,

    SidebarWidth = 160,
    SidebarItemHeight = 40,

    MaxHistoryLogs = 50,

    BgColor = Color3.fromHex("#171717"),
    BgTransparency = 0.02,
    OuterCardBg = Color3.fromHex("#1F1F1F"),
    OuterCardTransparency = 0.02,
    NestedCardBg = Color3.fromHex("#242424"),
    NestedCardTransparency = 0.02,
    RecessedBg = Color3.fromHex("#1A1A1A"),
    CardBorder = Color3.fromHex("#2C2C2C"),
    BorderInner = Color3.fromHex("#333333"),
    BorderTransparency = 0.35,

    AccentGreen = Color3.fromRGB(0, 230, 118),
    AccentBlue = Color3.fromRGB(0, 150, 255),
    AccentGold = Color3.fromRGB(255, 215, 0),
    AccentRed = Color3.fromRGB(255, 61, 87),

    TextPrimary = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(163, 163, 163),
    TextMuted = Color3.fromRGB(110, 110, 110),
}

--==================================================
-- [2] COMPONENT: ServiceManager
--==================================================
local ServiceManager = {}
ServiceManager.Players = game:GetService("Players")
ServiceManager.TweenService = game:GetService("TweenService")
ServiceManager.RunService = game:GetService("RunService")
ServiceManager.UserInputService = game:GetService("UserInputService")
ServiceManager.TeleportService = game:GetService("TeleportService")
ServiceManager.GuiService = game:GetService("GuiService")
ServiceManager.CoreGui = game:GetService("CoreGui")
ServiceManager.Workspace = game:GetService("Workspace")
ServiceManager.ReplicatedStorage = game:GetService("ReplicatedStorage")
ServiceManager.LocalPlayer = ServiceManager.Players.LocalPlayer

ServiceManager.VirtualInputManager = nil
pcall(function() ServiceManager.VirtualInputManager = game:GetService("VirtualInputManager") end)
ServiceManager.VirtualUser = nil
pcall(function() ServiceManager.VirtualUser = game:GetService("VirtualUser") end)

local function getTargetParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok and cg then return cg end
    return ServiceManager.LocalPlayer:WaitForChild("PlayerGui")
end
ServiceManager.TargetParent = getTargetParent()

ServiceManager.QueueOnTeleport = (syn and syn.queue_on_teleport)
    or (queue_on_teleport)
    or (Fluxus and Fluxus.queue_on_teleport)

ServiceManager.RenderedEggsFolder = ServiceManager.Workspace:WaitForChild("RenderedEggs", 8)

--==================================================
-- [3] COMPONENT: StateStore
--==================================================
local StateStore = {
    mainESPActive = false,
    autoBestEggActive = false, autoBestEggThread = nil,
    autoFarmActive = false, autoFarmThread = nil,
    autoRebirthActive = false, autoRebirthThread = nil,
    missingRebirthEggs = {},
    antiAFKActive = true,
    movementActive = false,
    isMobileMode = false,
    isMinimized = false,
    listeningForKey = false,

    movementMode = "AutoFarm",
    currentSearchQuery = "",
    backpackSearchQuery = "",
    sortMode = "Name",
    tpKeybind = Enum.KeyCode.T,

    autoFarmEggs = {},
    autoFarmProcessed = setmetatable({}, { __mode = "k" }),
    eggCooldowns = setmetatable({}, { __mode = "k" }),
    eggData = setmetatable({}, { __mode = "k" }),

    farmHistory = {},
    onHistoryUpdated = nil,

    sessionStartTime = os.time(),
    totalEggsCollected = 0,
    onTimeUpdated = nil,

    movementHumanoid = nil,
    noclipConnection = nil,
    antiAFKConnection = nil,

    recentAlerts = {},
    _connections = {},
    _sliderCounter = 0,
    windowMode = "PC",
    screenGui = nil,
}

function StateStore.track(conn)
    if not conn then return conn end
    table.insert(StateStore._connections, conn)
    return conn
end

function StateStore.addHistoryRecord(eggName)
    local isRare = false
    local lower = eggName:lower()
    for _, kw in ipairs(AppConfig.RareKeywords) do
        if string.find(lower, kw, 1, true) then isRare = true break end
    end

    table.insert(StateStore.farmHistory, 1, {
        name = eggName, time = os.date("%H:%M:%S"), isRare = isRare
    })
    if #StateStore.farmHistory > AppConfig.MaxHistoryLogs then
        table.remove(StateStore.farmHistory)
    end

    StateStore.totalEggsCollected = StateStore.totalEggsCollected + 1
    if StateStore.onHistoryUpdated then StateStore.onHistoryUpdated() end
end

function StateStore.shouldAlert(eggName)
    local now = os.clock()
    local last = StateStore.recentAlerts[eggName]
    if last and (now - last) < AppConfig.AlertDedupeSeconds then return false end
    StateStore.recentAlerts[eggName] = now
    return true
end

function StateStore.reset()
    StateStore.mainESPActive = false
    StateStore.autoBestEggActive = false
    StateStore.autoFarmActive = false
    StateStore.autoRebirthActive = false
    StateStore.movementActive = false
    StateStore.isMinimized = false
    StateStore.listeningForKey = false
    StateStore.autoBestEggThread = nil
    StateStore.autoFarmThread = nil
    StateStore.autoRebirthThread = nil
    StateStore.movementHumanoid = nil
    StateStore.onHistoryUpdated = nil
    StateStore.onTimeUpdated = nil
    StateStore.screenGui = nil
    table.clear(StateStore.autoFarmEggs)
    table.clear(StateStore.farmHistory)
    table.clear(StateStore.recentAlerts)
    table.clear(StateStore.missingRebirthEggs)
end

--==================================================
-- [4] COMPONENT: Utils
--==================================================
local Utils = {}

function Utils.getCharacter() return ServiceManager.LocalPlayer.Character end
function Utils.getRootPart()
    local char = Utils.getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end
function Utils.getHumanoid()
    local char = Utils.getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

function Utils.tween(object, properties, duration, style, direction)
    if not object or not object.Parent then return end
    local info = TweenInfo.new(
        duration or AppConfig.AnimationTime,
        style or Enum.EasingStyle.Quart,
        direction or Enum.EasingDirection.Out
    )
    local tw = ServiceManager.TweenService:Create(object, info, properties)
    tw:Play()
    return tw
end

function Utils.getTargetCFrame(target)
    if not target or not target.Parent then return nil end
    if target:IsA("Model") then
        if target.PrimaryPart then return target.PrimaryPart.CFrame end
        local base = target:FindFirstChildWhichIsA("BasePart")
        if base then return base.CFrame end
        return target:GetPivot()
    elseif target:IsA("BasePart") then
        return target.CFrame
    end
    return nil
end

function Utils.getTargetPosition(target)
    local cf = Utils.getTargetCFrame(target)
    return cf and cf.Position or nil
end

function Utils.getDistanceToTarget(target)
    local root = Utils.getRootPart()
    local targetPos = Utils.getTargetPosition(target)
    if not root or not targetPos then return math.huge end
    return (root.Position - targetPos).Magnitude
end

function Utils.isValidEgg(egg)
    return egg
        and egg.Parent == ServiceManager.RenderedEggsFolder
        and (egg:IsA("Model") or egg:IsA("BasePart"))
end

function Utils.isRareEgg(eggName)
    local lower = eggName:lower()
    for _, kw in ipairs(AppConfig.RareKeywords) do
        if string.find(lower, kw, 1, true) then return true end
    end
    return false
end

function Utils.getEggImage(eggName)
    local playerGui = ServiceManager.LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return "" end
    local main = playerGui:FindFirstChild("Main")
    local index = main and main:FindFirstChild("Index")
    local holders = index and index:FindFirstChild("Holders")
    local eggsHolder = holders and holders:FindFirstChild("EggsHolder")
    if not eggsHolder then return "" end
    local eggFrame = eggsHolder:FindFirstChild(eggName)
    if not eggFrame then return "" end
    local imageLabel = eggFrame:FindFirstChild("ImageLabel")
    if imageLabel and imageLabel:IsA("ImageLabel") then return imageLabel.Image or "" end
    return ""
end

function Utils.isKnownEggName(name)
    if not name or type(name) ~= "string" or #name < 2 then return false end
    local lower = name:lower()
    if string.find(lower, "egg", 1, true) then return true end
    local playerGui = ServiceManager.LocalPlayer:FindFirstChild("PlayerGui")
    local main = playerGui and playerGui:FindFirstChild("Main")
    local index = main and main:FindFirstChild("Index")
    local holders = index and index:FindFirstChild("Holders")
    local eggsHolder = holders and holders:FindFirstChild("EggsHolder")
    if eggsHolder and eggsHolder:FindFirstChild(name) then return true end
    local folder = ServiceManager.RenderedEggsFolder
    if folder and folder:FindFirstChild(name) then return true end
    return false
end

function Utils.resetVelocity(root)
    if not root then return end
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        root.Velocity = Vector3.zero
        root.RotVelocity = Vector3.zero
    end)
end

function Utils.getBackpack()
    local lp = ServiceManager.LocalPlayer
    return (lp and lp:FindFirstChildOfClass("Backpack"))
        or (lp and lp:FindFirstChild("Backpack"))
end

function Utils.getBackpackItems()
    local items = {}
    local backpack = Utils.getBackpack()
    local char = Utils.getCharacter()
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(items, {
                    instance = child, name = child.Name, className = child.ClassName,
                    isEquipped = true, textureId = child.TextureId or "", toolTip = child.ToolTip or ""
                })
            end
        end
    end
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") or child:IsA("Instance") then
                table.insert(items, {
                    instance = child, name = child.Name, className = child.ClassName,
                    isEquipped = false,
                    textureId = child:IsA("Tool") and child.TextureId or "",
                    toolTip = child:IsA("Tool") and child.ToolTip or ""
                })
            end
        end
    end
    return items
end

function Utils.printBackpack()
    local items = Utils.getBackpackItems()
    print("═══════════════════════════════════════════════════════════════")
    print(string.format("🎒 [BACKPACK VIEWER] Total Items: %d", #items))
    print("═══════════════════════════════════════════════════════════════")
    if #items == 0 then
        print("  (Backpack is empty / ไม่มีไอเทมในกระเป๋าหรือในมือ)")
    else
        for i, item in ipairs(items) do
            local status = item.isEquipped and "[EQUIPPED]" or "[IN BAG]"
            local tip = (#item.toolTip > 0) and (" (" .. item.toolTip .. ")") or ""
            print(string.format("  [%d] %s %s | Class: %s%s", i, status, item.name, item.className, tip))
        end
    end
    print("═══════════════════════════════════════════════════════════════")
    return items
end

function Utils.equipTool(tool)
    if not tool or not tool.Parent then return false end
    local char = Utils.getCharacter()
    local hum = Utils.getHumanoid()
    if hum and tool:IsA("Tool") then hum:EquipTool(tool); return true
    elseif char then tool.Parent = char; return true end
    return false
end

function Utils.unequipTool(tool)
    if not tool or not tool.Parent then return false end
    local backpack = Utils.getBackpack()
    local hum = Utils.getHumanoid()
    if hum then hum:UnequipTools(); return true
    elseif backpack then tool.Parent = backpack; return true end
    return false
end

pcall(function()
    _G.GetBackpackItems = Utils.getBackpackItems
    _G.PrintBackpack = Utils.printBackpack
    _G.ViewBackpack = Utils.printBackpack
end)

--==================================================
-- [5] COMPONENT: StabilityComponent
--==================================================
local StabilityComponent = {}

function StabilityComponent.setupAntiAFK(enable)
    StateStore.antiAFKActive = enable
    if StateStore.antiAFKConnection then
        pcall(function() StateStore.antiAFKConnection:Disconnect() end)
        StateStore.antiAFKConnection = nil
    end
    if enable then
        StateStore.antiAFKConnection = ServiceManager.LocalPlayer.Idled:Connect(function()
            if not StateStore.antiAFKActive then return end
            pcall(function()
                if ServiceManager.VirtualUser then
                    ServiceManager.VirtualUser:CaptureController()
                    ServiceManager.VirtualUser:ClickButton2(Vector2.zero)
                elseif ServiceManager.VirtualInputManager then
                    ServiceManager.VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Unknown, false, game)
                    task.wait(0.05)
                    ServiceManager.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Unknown, false, game)
                end
            end)
        end)
    end
end

function StabilityComponent.setupAutoRejoin()
    local function queueScript()
        if ServiceManager.QueueOnTeleport then
            pcall(function()
                ServiceManager.QueueOnTeleport([[
                    task.wait(3)
                    pcall(function()
                        loadstring(game:HttpGet("https://raw.githubusercontent.com/ThiAez/EggsESP/main/loader.lua"))()
                    end)
                ]])
            end)
        end
    end

    pcall(function()
        StateStore.track(ServiceManager.GuiService.ErrorMessageChanged:Connect(function(msg)
            if msg and #msg > 0 then
                queueScript()
                task.wait(2.5)
                pcall(function()
                    if #ServiceManager.Players:GetPlayers() <= 1 then
                        ServiceManager.TeleportService:Teleport(game.PlaceId, ServiceManager.LocalPlayer)
                    else
                        ServiceManager.TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, ServiceManager.LocalPlayer)
                    end
                end)
            end
        end))
    end)

    task.spawn(function()
        pcall(function()
            local promptOverlay = ServiceManager.CoreGui:WaitForChild("RobloxPromptGui", 8)
                and ServiceManager.CoreGui.RobloxPromptGui:WaitForChild("promptOverlay", 8)
            if promptOverlay then
                StateStore.track(promptOverlay.ChildAdded:Connect(function(child)
                    if child.Name == "ErrorPrompt" then
                        queueScript()
                        task.wait(2)
                        pcall(function()
                            ServiceManager.TeleportService:Teleport(game.PlaceId, ServiceManager.LocalPlayer)
                        end)
                    end
                end))
            end
        end)
    end)
end

--==================================================
-- [6] COMPONENT: InteractionComponent
--==================================================
local InteractionComponent = {}

function InteractionComponent.holdEKey(duration)
    duration = duration or 1.5
    local vim = ServiceManager.VirtualInputManager
    local vu = ServiceManager.VirtualUser
    if vim then pcall(function() vim:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
    elseif vu then pcall(function() vu:SetKeyDown("e") end) end
    task.wait(duration)
    if vim then pcall(function() vim:SendKeyEvent(false, Enum.KeyCode.E, false, game) end) end
    if vu then pcall(function() vu:SetKeyUp("e") end) end
end

function InteractionComponent.trigger(targetObject, fallbackDuration)
    if not targetObject then return false end
    local prompt = targetObject:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and prompt.Enabled and fireproximityprompt then
        pcall(function() fireproximityprompt(prompt) end)
        task.wait(0.2)
        return true
    end
    InteractionComponent.holdEKey(fallbackDuration)
    return true
end

--==================================================
-- [7] COMPONENT: MovementComponent
--==================================================
local MovementComponent = {}

function MovementComponent.setNoclip(enabled)
    if StateStore.noclipConnection then
        pcall(function() StateStore.noclipConnection:Disconnect() end)
        StateStore.noclipConnection = nil
    end
    local character = Utils.getCharacter()
    if not character then return end
    if enabled then
        StateStore.noclipConnection = ServiceManager.RunService.Stepped:Connect(function()
            local char = Utils.getCharacter()
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end)
    else
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart"
                and not part:IsA("Accessory") and not part.Parent:IsA("Accessory") then
                part.CanCollide = true
            end
        end
    end
end

function MovementComponent.stop()
    StateStore.movementActive = false
    if StateStore.movementHumanoid and StateStore.movementHumanoid.Parent then
        StateStore.movementHumanoid.AutoRotate = true
    end
    StateStore.movementHumanoid = nil
    MovementComponent.setNoclip(false)
    Utils.resetVelocity(Utils.getRootPart())
end

function MovementComponent.teleportTo(target)
    local root = Utils.getRootPart()
    if not root then return false end
    local targetCFrame = Utils.getTargetCFrame(target)
    if not targetCFrame then return false end
    Utils.resetVelocity(root)
    root.CFrame = targetCFrame * CFrame.new(0, AppConfig.TPHeight, 0)
    Utils.resetVelocity(root)
    return true
end

function MovementComponent.moveTo(target)
    if StateStore.movementMode == "Teleport" then
        return MovementComponent.teleportTo(target)
    end
    if StateStore.movementActive then return false end

    local root = Utils.getRootPart()
    local humanoid = Utils.getHumanoid()
    local targetCFrame = Utils.getTargetCFrame(target)
    if not root or not humanoid or not targetCFrame or humanoid.Health <= 0 then return false end

    local destination = targetCFrame.Position + Vector3.new(0, AppConfig.TPHeight, 0)
    local startDistance = (root.Position - destination).Magnitude

    if startDistance <= 2.8 then
        Utils.resetVelocity(root)
        root.CFrame = targetCFrame * CFrame.new(0, AppConfig.TPHeight, 0)
        return true
    end

    StateStore.movementActive = true
    StateStore.movementHumanoid = humanoid
    local oldAutoRotate = humanoid.AutoRotate
    local success = false
    local startTime = os.clock()
    local maxTime = math.max(3.5, (startDistance / AppConfig.MovementSpeed) + 2.5)
    local lastCheckPos = root.Position
    local lastCheckTime = os.clock()

    MovementComponent.setNoclip(true)
    humanoid.AutoRotate = false

    while StateStore.movementActive and (os.clock() - startTime <= maxTime) do
        if not target or not target.Parent or humanoid.Health <= 0 then break end
        if Utils.getRootPart() ~= root then break end

        local curTargetCF = Utils.getTargetCFrame(target)
        if curTargetCF then
            destination = curTargetCF.Position + Vector3.new(0, AppConfig.TPHeight, 0)
        end

        local offset = destination - root.Position
        local distance = offset.Magnitude

        if distance <= 2.8 then
            Utils.resetVelocity(root)
            root.CFrame = (curTargetCF or targetCFrame) * CFrame.new(0, AppConfig.TPHeight, 0)
            success = true
            break
        end

        if os.clock() - lastCheckTime >= AppConfig.AntiStuckThreshold then
            if (root.Position - lastCheckPos).Magnitude < 1.2 then
                root.CFrame = root.CFrame * CFrame.new(0, 4, 0)
                MovementComponent.setNoclip(true)
                Utils.resetVelocity(root)
            end
            lastCheckPos = root.Position
            lastCheckTime = os.clock()
        end

        local dt = ServiceManager.RunService.Heartbeat:Wait()
        local step = math.min(distance, AppConfig.MovementSpeed * dt)
        Utils.resetVelocity(root)
        local newPos = root.Position + (offset.Unit * step)
        if (destination - newPos).Magnitude > 0.08 then
            root.CFrame = CFrame.lookAt(newPos, destination)
        else
            root.CFrame = (curTargetCF or targetCFrame) * CFrame.new(0, AppConfig.TPHeight, 0)
            success = true
            break
        end
    end

    StateStore.movementActive = false
    if humanoid and humanoid.Parent then humanoid.AutoRotate = oldAutoRotate end
    StateStore.movementHumanoid = nil
    MovementComponent.setNoclip(false)
    Utils.resetVelocity(root)
    return success
end

--==================================================
-- [8] COMPONENT: PlotComponent
--==================================================
local PlotComponent = {}

function PlotComponent.isOwner(plot)
    if not plot then return false end
    local lp = ServiceManager.LocalPlayer
    local dataFolder = plot:FindFirstChild("Data")
    if dataFolder then
        local ownerVal = dataFolder:FindFirstChild("Owner") or dataFolder:FindFirstChild("Player")
        if ownerVal then
            if ownerVal:IsA("StringValue") and (ownerVal.Value == lp.Name or ownerVal.Value == lp.DisplayName) then return true
            elseif ownerVal:IsA("ObjectValue") and ownerVal.Value == lp then return true
            elseif ownerVal:IsA("IntValue") and ownerVal.Value == lp.UserId then return true
            elseif tostring(ownerVal.Value) == lp.Name or tostring(ownerVal.Value) == tostring(lp.UserId) then return true end
        end
    end
    local direct = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player")
    if direct then
        if direct:IsA("StringValue") and (direct.Value == lp.Name or direct.Value == lp.DisplayName) then return true
        elseif direct:IsA("ObjectValue") and direct.Value == lp then return true
        elseif direct:IsA("IntValue") and direct.Value == lp.UserId then return true
        elseif tostring(direct.Value) == lp.Name then return true end
    end
    local attr = plot:GetAttribute("Owner") or plot:GetAttribute("Player")
    if attr and (attr == lp.Name or attr == lp.DisplayName) then return true end
    local attrId = plot:GetAttribute("OwnerId") or plot:GetAttribute("UserId")
    if attrId and (attrId == lp.UserId or tostring(attrId) == tostring(lp.UserId)) then return true end
    if plot.Name == lp.Name or plot.Name == tostring(lp.UserId) then return true end
    local sign = plot:FindFirstChild("Sign", true) or plot:FindFirstChild("PlotSign", true)
    if sign then
        for _, obj in ipairs(sign:GetDescendants()) do
            if obj:IsA("TextLabel") and (obj.Text:find(lp.Name) or obj.Text:find(lp.DisplayName)) then return true end
        end
    end
    return false
end

function PlotComponent.findHomePlot()
    local ws = ServiceManager.Workspace
    local folders = {
        ws:FindFirstChild("Plots"), ws:FindFirstChild("PlayerPlots"),
        ws:FindFirstChild("Bases"), ws:FindFirstChild("Islands"),
        ws:FindFirstChild("Tycoons")
    }
    for _, folder in ipairs(folders) do
        if folder then
            for _, plot in ipairs(folder:GetChildren()) do
                if PlotComponent.isOwner(plot) then return plot end
            end
        end
    end
    for _, child in ipairs(ws:GetChildren()) do
        if child:IsA("Model") and (child.Name:find("Plot") or child.Name:find("Base")) then
            if PlotComponent.isOwner(child) then return child end
        end
    end
    return nil
end

function PlotComponent.teleportAndDeposit()
    local plot = PlotComponent.findHomePlot()
    if not plot then return false end
    MovementComponent.stop()
    Utils.resetVelocity(Utils.getRootPart())
    local depositPoint = plot:FindFirstChild("Deposit", true)
        or plot:FindFirstChild("EggDeposit", true)
        or plot:FindFirstChild("Clear", true)
        or plot:FindFirstChild("Spawn", true)
        or plot:FindFirstChild("Base", true)
        or plot:FindFirstChild("Center", true)
        or plot.PrimaryPart
        or plot:FindFirstChildWhichIsA("BasePart")
        or plot
    local arrived = MovementComponent.moveTo(depositPoint)
    Utils.resetVelocity(Utils.getRootPart())
    if arrived then
        task.wait(0.25)
        InteractionComponent.trigger(depositPoint, AppConfig.HomeDepositWait)
    end
    return arrived
end

--==================================================
-- [9] COMPONENT: ESPComponent
--==================================================
local ESPComponent = {}

function ESPComponent.getColor(eggName)
    local lower = eggName:lower()
    for _, kw in ipairs(AppConfig.RareKeywords) do
        if string.find(lower, kw, 1, true) then return AppConfig.ESPRareColor end
    end
    local hash = 0
    for i = 1, #eggName do hash = hash + string.byte(eggName, i) * (i + 1) end
    local palette = AppConfig.ESPPalette
    return palette[(hash % #palette) + 1]
end

function ESPComponent.createBillboard(egg)
    local data = StateStore.eggData[egg]
    if not data or (data.NameBillboard and data.NameBillboard.Parent) then return end
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "EggESP_Info"
    billboard.Size = UDim2.new(0, 180, 0, 42)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 2500
    billboard.Enabled = false
    billboard.Parent = egg

    local eggColor = ESPComponent.getColor(egg.Name)
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "EggName"
    nameLabel.Size = UDim2.new(1, 0, 0, 20)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = egg.Name
    nameLabel.TextColor3 = eggColor
    nameLabel.TextStrokeTransparency = 0.2
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.TextSize = AppConfig.ESPNameSize
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Parent = billboard

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "Distance"
    distLabel.Size = UDim2.new(1, 0, 0, 16)
    distLabel.Position = UDim2.new(0, 0, 0, 19)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = "0 studs"
    distLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
    distLabel.TextStrokeTransparency = 0.4
    distLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    distLabel.TextSize = AppConfig.ESPDistanceSize
    distLabel.Font = Enum.Font.GothamMedium
    distLabel.Parent = billboard
    data.NameBillboard = billboard
end

function ESPComponent.updateBillboard(egg)
    local data = StateStore.eggData[egg]
    if not data or not data.NameBillboard or not data.NameBillboard.Parent then return end
    local billboard = data.NameBillboard
    local nameLabel = billboard:FindFirstChild("EggName")
    local distLabel = billboard:FindFirstChild("Distance")
    if nameLabel then nameLabel.Text = egg.Name end
    if distLabel then
        local d = Utils.getDistanceToTarget(egg)
        distLabel.Text = (d == math.huge) and "?" or string.format("%d studs", math.floor(d + 0.5))
    end
end

function ESPComponent.updateEgg(egg)
    if not Utils.isValidEgg(egg) then return end
    if not StateStore.eggData[egg] then
        StateStore.eggData[egg] = {
            Highlight = nil, NameBillboard = nil,
            CustomColor = ESPComponent.getColor(egg.Name),
            CustomActive = false
        }
    end
    local data = StateStore.eggData[egg]
    local eggColor = ESPComponent.getColor(egg.Name)
    local shouldShow = data.CustomActive or StateStore.mainESPActive
    local color = data.CustomActive and (data.CustomColor or eggColor) or eggColor

    if shouldShow then
        if not data.Highlight or not data.Highlight.Parent then
            local highlight = Instance.new("Highlight")
            highlight.Name = "EggESP_Highlight"
            highlight.Adornee = egg
            highlight.FillTransparency = AppConfig.ESPFillTransparency
            highlight.OutlineTransparency = AppConfig.ESPOutlineTransparency
            highlight.Parent = egg
            data.Highlight = highlight
        end
        data.Highlight.FillColor = color
        data.Highlight.OutlineColor = color
        data.Highlight.Enabled = true
        ESPComponent.createBillboard(egg)
        if data.NameBillboard then
            data.NameBillboard.Enabled = true
            ESPComponent.updateBillboard(egg)
        end
    else
        if data.Highlight then data.Highlight.Enabled = false end
        if data.NameBillboard then data.NameBillboard.Enabled = false end
    end
end

function ESPComponent.updateAll()
    local folder = ServiceManager.RenderedEggsFolder
    if not folder then return end
    for _, egg in ipairs(folder:GetChildren()) do ESPComponent.updateEgg(egg) end
end

function ESPComponent.removeEgg(egg)
    local data = StateStore.eggData[egg]
    if data then
        if data.Highlight then pcall(function() data.Highlight:Destroy() end) end
        if data.NameBillboard then pcall(function() data.NameBillboard:Destroy() end) end
        StateStore.eggData[egg] = nil
    end
    StateStore.autoFarmProcessed[egg] = nil
    StateStore.eggCooldowns[egg] = nil
end

function ESPComponent.bindEggLifecycle(egg)
    if not egg or not egg.Parent then return end
    local conn
    conn = egg.Destroying:Connect(function()
        ESPComponent.removeEgg(egg)
        if conn then pcall(function() conn:Disconnect() end) end
    end)
    StateStore.track(conn)
end

--==================================================
-- [10] COMPONENT: FarmComponent
--==================================================
local FarmComponent = {}

function FarmComponent.getReadyEggs()
    local found = {}
    local folder = ServiceManager.RenderedEggsFolder
    if not folder then return found end
    local now = os.clock()
    for _, egg in ipairs(folder:GetChildren()) do
        if Utils.isValidEgg(egg) and StateStore.autoFarmEggs[egg.Name] then
            local cd = StateStore.eggCooldowns[egg]
            local onCooldown = (cd and now <= cd)
            if not onCooldown and not StateStore.autoFarmProcessed[egg] then
                table.insert(found, egg)
            end
        end
    end
    table.sort(found, function(a, b) return a.Name:lower() < b.Name:lower() end)
    return found
end

function FarmComponent.findBestEgg()
    local folder = ServiceManager.RenderedEggsFolder
    if not folder then return nil end
    local now = os.clock()
    local query = AppConfig.BestEggName:lower()
    for _, egg in ipairs(folder:GetChildren()) do
        local cd = StateStore.eggCooldowns[egg]
        local onCooldown = (cd and now <= cd)
        if not onCooldown and Utils.isValidEgg(egg) and string.find(egg.Name:lower(), query, 1, true) then
            return egg
        end
    end
    return nil
end

function FarmComponent.stopAutoFarm()
    StateStore.autoFarmActive = false
    MovementComponent.stop()
    if StateStore.autoFarmThread then
        pcall(function() task.cancel(StateStore.autoFarmThread) end)
        StateStore.autoFarmThread = nil
    end
    pcall(function()
        if ServiceManager.VirtualInputManager then
            ServiceManager.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end
    end)
end

function FarmComponent.startAutoFarm(statusUpdater, stopButtonUpdater)
    FarmComponent.stopAutoFarm()
    StateStore.autoFarmActive = true
    if stopButtonUpdater then stopButtonUpdater(true) end

    StateStore.autoFarmThread = task.spawn(function()
        while StateStore.autoFarmActive do
            local hasAny = false
            for _, v in pairs(StateStore.autoFarmEggs) do if v then hasAny = true break end end
            if not hasAny then
                if statusUpdater then statusUpdater("No eggs selected", AppConfig.TextSecondary) end
                break
            end

            local readyEggs = FarmComponent.getReadyEggs()
            if #readyEggs == 0 then
                if statusUpdater then statusUpdater("Waiting for eggs to spawn / CD...", AppConfig.TextSecondary) end
                task.wait(1.0)
            else
                for _, egg in ipairs(readyEggs) do
                    if not StateStore.autoFarmActive then break end
                    local cd = StateStore.eggCooldowns[egg]
                    local onCooldown = (cd and os.clock() <= cd)
                    if Utils.isValidEgg(egg) and not StateStore.autoFarmProcessed[egg] and not onCooldown then
                        local currentEggName = egg.Name
                        if statusUpdater then statusUpdater("Farming: " .. currentEggName, AppConfig.AccentGreen) end

                        local arrived = MovementComponent.moveTo(egg)
                        if arrived and StateStore.autoFarmActive then
                            task.wait(0.2)
                            if StateStore.autoFarmActive and Utils.isValidEgg(egg) then
                                if statusUpdater then statusUpdater("Collecting " .. currentEggName .. "...", AppConfig.AccentGold) end
                                InteractionComponent.trigger(egg, AppConfig.AutoFarmHoldTime)
                            end
                            StateStore.eggCooldowns[egg] = os.clock() + AppConfig.EggCooldownSeconds
                            task.wait(0.3)
                            if StateStore.autoFarmActive then
                                if statusUpdater then statusUpdater("Returning Home & Depositing...", AppConfig.AccentBlue) end
                                MovementComponent.stop()
                                local homeSuccess = PlotComponent.teleportAndDeposit()
                                if homeSuccess then
                                    StateStore.autoFarmProcessed[egg] = true
                                    StateStore.addHistoryRecord(currentEggName)
                                    if statusUpdater then statusUpdater("Egg Deposited!", AppConfig.AccentGreen) end
                                else
                                    if statusUpdater then statusUpdater("Home Plot Unreachable", AppConfig.AccentRed) end
                                end
                            end
                            task.wait(AppConfig.AutoEggDelay)
                        end
                    end
                end
            end
            task.wait(0.25)
        end
        StateStore.autoFarmThread = nil
        StateStore.autoFarmActive = false
        if stopButtonUpdater then stopButtonUpdater(false) end
        if statusUpdater then statusUpdater("AutoFarm Idle", AppConfig.TextSecondary) end
    end)
end

function FarmComponent.stopAutoBestEgg()
    StateStore.autoBestEggActive = false
    MovementComponent.stop()
    if StateStore.autoBestEggThread then
        pcall(function() task.cancel(StateStore.autoBestEggThread) end)
        StateStore.autoBestEggThread = nil
    end
    pcall(function()
        if ServiceManager.VirtualInputManager then
            ServiceManager.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end
    end)
end

function FarmComponent.startAutoBestEgg(statusUpdater)
    FarmComponent.stopAutoBestEgg()
    StateStore.autoBestEggActive = true
    StateStore.autoBestEggThread = task.spawn(function()
        while StateStore.autoBestEggActive do
            local egg = FarmComponent.findBestEgg()
            if egg and egg.Parent then
                local currentEggName = egg.Name
                if statusUpdater then statusUpdater("Moving to " .. currentEggName, AppConfig.AccentGreen) end
                local arrived = MovementComponent.moveTo(egg)
                if arrived and StateStore.autoBestEggActive then
                    task.wait(0.2)
                    if StateStore.autoBestEggActive and egg.Parent then
                        if statusUpdater then statusUpdater("Collecting " .. currentEggName .. "...", AppConfig.AccentGold) end
                        InteractionComponent.trigger(egg, AppConfig.AutoEggHoldTime)
                    end
                    StateStore.eggCooldowns[egg] = os.clock() + AppConfig.EggCooldownSeconds
                    task.wait(0.3)
                    if StateStore.autoBestEggActive then
                        if statusUpdater then statusUpdater("Returning Home & Depositing...", AppConfig.AccentBlue) end
                        MovementComponent.stop()
                        local ok = PlotComponent.teleportAndDeposit()
                        if ok then
                            StateStore.addHistoryRecord(currentEggName)
                            if statusUpdater then statusUpdater("Best Egg Deposited!", AppConfig.AccentGreen) end
                        end
                    end
                    task.wait(AppConfig.AutoEggDelay)
                else
                    task.wait(0.5)
                end
            else
                if statusUpdater then statusUpdater("Searching: [" .. AppConfig.BestEggName .. "]...", AppConfig.TextSecondary) end
                task.wait(1.0)
            end
        end
        StateStore.autoBestEggThread = nil
        StateStore.autoBestEggActive = false
    end)
end

--==================================================
-- [11] COMPONENT: RebirthComponent
--==================================================
local RebirthComponent = {}

function RebirthComponent.getRebirthRemote()
    local rs = ServiceManager.ReplicatedStorage or game:GetService("ReplicatedStorage")
    local remotes = rs:FindFirstChild("Remotes")
    local gameRemotes = remotes and remotes:FindFirstChild("Game")
    local rebirthEvent = gameRemotes and gameRemotes:FindFirstChild("Rebirth")
    if rebirthEvent and rebirthEvent:IsA("RemoteEvent") then return rebirthEvent end
    local fallback = rs:FindFirstChild("Rebirth", true)
    if fallback and fallback:IsA("RemoteEvent") then return fallback end
    return nil
end

function RebirthComponent.fireRebirth()
    local remote = RebirthComponent.getRebirthRemote()
    if remote then
        local ok = pcall(function() remote:FireServer() end)
        return ok
    end
    return false
end

function RebirthComponent.findEggByName(eggName)
    local folder = ServiceManager.RenderedEggsFolder
    if not folder then return nil end
    local query = eggName:lower():match("^%s*(.-)%s*$")
    local now = os.clock()
    for _, egg in ipairs(folder:GetChildren()) do
        local cd = StateStore.eggCooldowns[egg]
        local onCooldown = (cd and now <= cd)
        if not onCooldown and Utils.isValidEgg(egg) then
            local n = egg.Name:lower()
            if n == query or string.find(n, query, 1, true) or string.find(query, n, 1, true) then return egg end
        end
    end
    for _, egg in ipairs(folder:GetChildren()) do
        if Utils.isValidEgg(egg) then
            local n = egg.Name:lower()
            if n == query or string.find(n, query, 1, true) or string.find(query, n, 1, true) then return egg end
        end
    end
    return nil
end

function RebirthComponent.scanMissingEggs()
    local missing = {}
    local seen = {}
    local playerGui = ServiceManager.LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return missing end

    local function checkRebirthContainer(container)
        if not container then return end
        for _, item in ipairs(container:GetDescendants()) do
            if item:IsA("TextLabel") then
                local text = item.Text
                if string.find(text, "^%s*0%s*/%s*%d+") or string.find(text, "%s+0%s*/%s*%d+") then
                    local parent = item.Parent
                    local eggCandidate = nil
                    if parent then
                        if Utils.isKnownEggName(parent.Name) then
                            eggCandidate = parent.Name
                        else
                            for _, sib in ipairs(parent:GetChildren()) do
                                if sib:IsA("TextLabel") and sib ~= item then
                                    local st = sib.Text:match("^%s*(.-)%s*$")
                                    if st and #st > 0 and Utils.isKnownEggName(st) then
                                        eggCandidate = st
                                        break
                                    end
                                end
                            end
                        end
                    end
                    if eggCandidate and not seen[eggCandidate:lower()] then
                        seen[eggCandidate:lower()] = true
                        table.insert(missing, eggCandidate)
                    end
                end
            end
        end
    end

    local main = playerGui:FindFirstChild("Main")
    if main then
        for _, child in ipairs(main:GetChildren()) do
            if string.find(child.Name:lower(), "rebirth", 1, true) then checkRebirthContainer(child) end
        end
        local frames = main:FindFirstChild("Frames")
        if frames then
            for _, child in ipairs(frames:GetChildren()) do
                if string.find(child.Name:lower(), "rebirth", 1, true) then checkRebirthContainer(child) end
            end
        end
    end
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and string.find(gui.Name:lower(), "rebirth", 1, true) then
            checkRebirthContainer(gui)
        end
    end

    if #missing == 0 and main then
        local rebirthFrame = main:FindFirstChild("Rebirth", true) or main:FindFirstChild("RebirthFrame", true)
        if rebirthFrame then
            for _, desc in ipairs(rebirthFrame:GetDescendants()) do
                if desc:IsA("Frame") or desc:IsA("ImageLabel") or desc:IsA("TextLabel") then
                    local n = desc.Name
                    if Utils.isKnownEggName(n) and not seen[n:lower()] then
                        local isDone = false
                        for _, child in ipairs(desc:GetDescendants()) do
                            if child:IsA("TextLabel") and string.find(child.Text, "^%s*[1-9]%d*%s*/") then
                                isDone = true break
                            end
                            if child:IsA("ImageLabel") and (string.find(child.Name:lower(), "check", 1, true) or string.find(child.Name:lower(), "done", 1, true)) and child.Visible then
                                isDone = true break
                            end
                        end
                        if not isDone then
                            seen[n:lower()] = true
                            table.insert(missing, n)
                        end
                    end
                end
            end
        end
    end
    StateStore.missingRebirthEggs = missing
    return missing
end

function RebirthComponent.stopAutoRebirth()
    StateStore.autoRebirthActive = false
    MovementComponent.stop()
    if StateStore.autoRebirthThread then
        pcall(function() task.cancel(StateStore.autoRebirthThread) end)
        StateStore.autoRebirthThread = nil
    end
end

function RebirthComponent.startAutoRebirth(statusUpdater, stopButtonUpdater)
    RebirthComponent.stopAutoRebirth()
    StateStore.autoRebirthActive = true
    if stopButtonUpdater then stopButtonUpdater(true) end

    StateStore.autoRebirthThread = task.spawn(function()
        while StateStore.autoRebirthActive do
            if statusUpdater then statusUpdater("Checking Rebirth Status...", AppConfig.AccentGold) end
            RebirthComponent.fireRebirth()
            task.wait(0.6)
            local missing = RebirthComponent.scanMissingEggs()

            if #missing == 0 then
                if statusUpdater then statusUpdater("Requirements Met / Rebirth Fired!", AppConfig.AccentGreen) end
                task.wait(1.2)
                RebirthComponent.fireRebirth()
                task.wait(1.5)
            else
                local missingSummary = table.concat(missing, ", ")
                if statusUpdater then statusUpdater("Rebirth Needs: [" .. missingSummary .. "]", AppConfig.AccentBlue) end
                for _, eggName in ipairs(missing) do
                    if not StateStore.autoRebirthActive then break end
                    local targetEgg = RebirthComponent.findEggByName(eggName)
                    if targetEgg then
                        if statusUpdater then statusUpdater("Rebirth Hunting: " .. targetEgg.Name, AppConfig.AccentGreen) end
                        local arrived = MovementComponent.moveTo(targetEgg)
                        if arrived and StateStore.autoRebirthActive and Utils.isValidEgg(targetEgg) then
                            if statusUpdater then statusUpdater("Collecting " .. targetEgg.Name .. "...", AppConfig.AccentGold) end
                            InteractionComponent.trigger(targetEgg, AppConfig.AutoFarmHoldTime)
                            StateStore.eggCooldowns[targetEgg] = os.clock() + AppConfig.EggCooldownSeconds
                            task.wait(0.3)
                            if statusUpdater then statusUpdater("Depositing Rebirth Egg at Home...", AppConfig.AccentBlue) end
                            MovementComponent.stop()
                            local ok = PlotComponent.teleportAndDeposit()
                            if ok then
                                StateStore.addHistoryRecord(targetEgg.Name)
                                if statusUpdater then statusUpdater("Deposited! Rebirthing...", AppConfig.AccentGreen) end
                                task.wait(0.5)
                                RebirthComponent.fireRebirth()
                                task.wait(0.8)
                            end
                        end
                    else
                        if statusUpdater then statusUpdater("Waiting for " .. eggName .. " to spawn...", AppConfig.TextSecondary) end
                        task.wait(1.0)
                    end
                end
            end
            task.wait(0.5)
        end
        StateStore.autoRebirthThread = nil
        StateStore.autoRebirthActive = false
    end)
end

--==================================================
-- [12] COMPONENT: UIComponent
--==================================================
local UIComponent = {}

function UIComponent.getStroke(frame)
    return frame and frame:FindFirstChildWhichIsA("UIStroke")
end

function UIComponent.applyCard(frame, cornerRadius, bgColor, strokeColor, strokeTransparency)
    frame.BackgroundColor3 = bgColor or AppConfig.OuterCardBg
    frame.BackgroundTransparency = AppConfig.OuterCardTransparency
    frame.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, cornerRadius or AppConfig.Radius2XL)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = strokeColor or AppConfig.CardBorder
    stroke.Transparency = strokeTransparency or AppConfig.BorderTransparency
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame
    return corner, stroke
end

function UIComponent.styleButton(button, customRadius, normalBg, hoverBg)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, customRadius or AppConfig.RadiusLG)
    corner.Parent = button

    local stroke = Instance.new("UIStroke")
    stroke.Color = AppConfig.BorderInner
    stroke.Transparency = 0.55
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = button

    button.AutoButtonColor = false
    button:SetAttribute("DefaultBg", normalBg or button.BackgroundColor3)
    local targetHoverBg = hoverBg or Color3.fromRGB(44, 44, 44)

    button.MouseEnter:Connect(function()
        Utils.tween(button, { BackgroundColor3 = targetHoverBg }, 0.12)
        Utils.tween(stroke, { Transparency = 0.25, Color = Color3.fromRGB(75, 75, 75) }, 0.12)
    end)
    button.MouseLeave:Connect(function()
        local bg = button:GetAttribute("DefaultBg") or AppConfig.NestedCardBg
        Utils.tween(button, { BackgroundColor3 = bg }, 0.12)
        Utils.tween(stroke, { Transparency = 0.55, Color = AppConfig.BorderInner }, 0.12)
    end)
end

function UIComponent.setButtonDefault(button, color)
    if not button then return end
    button:SetAttribute("DefaultBg", color)
    button.BackgroundColor3 = color
end

function UIComponent.styleInput(textBox, customRadius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, customRadius or AppConfig.RadiusLG)
    corner.Parent = textBox
    local stroke = Instance.new("UIStroke")
    stroke.Color = AppConfig.BorderInner
    stroke.Transparency = 0.55
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = textBox
    textBox.Focused:Connect(function()
        Utils.tween(stroke, { Color = AppConfig.AccentGreen, Transparency = 0.2 }, 0.15)
    end)
    textBox.FocusLost:Connect(function()
        Utils.tween(stroke, { Color = AppConfig.BorderInner, Transparency = 0.55 }, 0.15)
    end)
end

-- Shared slider drag dispatcher
local activeSliders = {}
ServiceManager.UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        for _, cb in pairs(activeSliders) do cb(input) end
    end
end)
ServiceManager.UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        table.clear(activeSliders)
    end
end)

function UIComponent.createToggle(parent, titleText, descText, initialValue, onToggle)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -4, 0, 52)
    frame.BackgroundColor3 = AppConfig.NestedCardBg
    frame.Parent = parent
    UIComponent.applyCard(frame, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -80, 0, 20)
    title.Position = UDim2.new(0, 14, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = AppConfig.TextPrimary
    title.TextSize = AppConfig.TextBody
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local desc = Instance.new("TextLabel")
    desc.Size = UDim2.new(1, -80, 0, 16)
    desc.Position = UDim2.new(0, 14, 0, 28)
    desc.BackgroundTransparency = 1
    desc.Text = descText or ""
    desc.TextColor3 = AppConfig.TextMuted
    desc.TextSize = AppConfig.TextMicro
    desc.Font = Enum.Font.GothamMedium
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.Parent = frame

    local toggleTrack = Instance.new("TextButton")
    toggleTrack.Size = UDim2.new(0, 44, 0, 24)
    toggleTrack.Position = UDim2.new(1, -58, 0.5, -12)
    toggleTrack.BackgroundColor3 = initialValue and AppConfig.AccentGreen or Color3.fromRGB(40, 40, 40)
    toggleTrack.Text = ""
    toggleTrack.AutoButtonColor = false
    toggleTrack.Parent = frame

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = toggleTrack

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = initialValue and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.Parent = toggleTrack

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local state = initialValue
    toggleTrack.MouseButton1Click:Connect(function()
        state = not state
        local targetTrackColor = state and AppConfig.AccentGreen or Color3.fromRGB(40, 40, 40)
        local targetKnobPos = state and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        Utils.tween(toggleTrack, { BackgroundColor3 = targetTrackColor }, 0.15)
        Utils.tween(knob, { Position = targetKnobPos }, 0.15)
        if onToggle then onToggle(state) end
    end)
    return frame
end

function UIComponent.createSlider(parent, titleText, minVal, maxVal, defaultVal, unitStr, onChange)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -4, 0, 60)
    frame.BackgroundColor3 = AppConfig.NestedCardBg
    frame.Parent = parent
    UIComponent.applyCard(frame, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.6, 0, 0, 20)
    title.Position = UDim2.new(0, 14, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = AppConfig.TextPrimary
    title.TextSize = AppConfig.TextBody
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0.35, -14, 0, 20)
    valLabel.Position = UDim2.new(0.65, 0, 0, 8)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = string.format("%s %s", tostring(defaultVal), unitStr or "")
    valLabel.TextColor3 = AppConfig.AccentBlue
    valLabel.TextSize = AppConfig.TextCaption
    valLabel.Font = Enum.Font.GothamBold
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.Parent = frame

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(1, -28, 0, 6)
    track.Position = UDim2.new(0, 14, 0, 38)
    track.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    track.Text = ""
    track.AutoButtonColor = false
    track.Parent = frame

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local pct = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(pct, 0, 1, 0)
    fill.BackgroundColor3 = AppConfig.AccentBlue
    fill.BorderSizePixel = 0
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local thumb = Instance.new("Frame")
    thumb.Size = UDim2.new(0, 14, 0, 14)
    thumb.Position = UDim2.new(1, -7, 0.5, -7)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.Parent = fill

    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = UDim.new(1, 0)
    thumbCorner.Parent = thumb

    StateStore._sliderCounter = StateStore._sliderCounter + 1
    local sliderId = "slider_" .. tostring(StateStore._sliderCounter)

    local function updateFromInput(input)
        local inputPos = input.Position.X
        local trackPos = track.AbsolutePosition.X
        local trackWidth = track.AbsoluteSize.X
        if trackWidth <= 0 then return end
        local relX = math.clamp((inputPos - trackPos) / trackWidth, 0, 1)
        local val = math.floor(minVal + (maxVal - minVal) * relX + 0.5)
        fill.Size = UDim2.new(relX, 0, 1, 0)
        valLabel.Text = string.format("%s %s", tostring(val), unitStr or "")
        if onChange then onChange(val) end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            activeSliders[sliderId] = updateFromInput
            updateFromInput(input)
        end
    end)
    ServiceManager.UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            activeSliders[sliderId] = nil
        end
    end)

    return frame
end

function UIComponent.mount()
    local old = ServiceManager.TargetParent:FindFirstChild("RenderedEggsESP_Menu")
    if old then pcall(function() old:Destroy() end) end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "RenderedEggsESP_Menu"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = ServiceManager.TargetParent
    StateStore.screenGui = ScreenGui

    -- Cleanup callbacks on destroy
    ScreenGui.Destroying:Connect(function()
        StateStore.onHistoryUpdated = nil
        StateStore.onTimeUpdated = nil
        StateStore.screenGui = nil
    end)

    -- Alert Stack
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

    -- ══════════════════════════════════════════════════════════════
    -- DEVICE SELECTION
    -- ══════════════════════════════════════════════════════════════
    local DeviceFrame = Instance.new("Frame")
    DeviceFrame.Name = "DeviceSelectionFrame"
    DeviceFrame.Size = UDim2.new(0, 340, 0, 170)
    DeviceFrame.Position = UDim2.new(0.5, -170, 0.5, -85)
    DeviceFrame.BackgroundColor3 = AppConfig.BgColor
    DeviceFrame.BackgroundTransparency = AppConfig.BgTransparency
    DeviceFrame.BorderSizePixel = 0
    DeviceFrame.Active = true
    DeviceFrame.Parent = ScreenGui
    UIComponent.applyCard(DeviceFrame, AppConfig.Radius2XL, AppConfig.BgColor, AppConfig.CardBorder)

    local DeviceInner = Instance.new("Frame")
    DeviceInner.Size = UDim2.new(1, -16, 1, -16)
    DeviceInner.Position = UDim2.new(0, 8, 0, 8)
    DeviceInner.Parent = DeviceFrame
    UIComponent.applyCard(DeviceInner, AppConfig.RadiusXL, AppConfig.OuterCardBg, AppConfig.BorderInner)

    local DeviceTitle = Instance.new("TextLabel")
    DeviceTitle.Size = UDim2.new(1, 0, 0, 30)
    DeviceTitle.Position = UDim2.new(0, 0, 0, 14)
    DeviceTitle.BackgroundTransparency = 1
    DeviceTitle.Text = "Select Device / เลือกอุปกรณ์"
    DeviceTitle.TextColor3 = AppConfig.TextPrimary
    DeviceTitle.TextSize = AppConfig.TextTitle
    DeviceTitle.Font = Enum.Font.GothamBold
    DeviceTitle.Parent = DeviceInner

    local DeviceSub = Instance.new("TextLabel")
    DeviceSub.Size = UDim2.new(1, 0, 0, 16)
    DeviceSub.Position = UDim2.new(0, 0, 0, 40)
    DeviceSub.BackgroundTransparency = 1
    DeviceSub.Text = "Sidebar Navigation • Nested Card Architecture"
    DeviceSub.TextColor3 = AppConfig.TextMuted
    DeviceSub.TextSize = AppConfig.TextCaption
    DeviceSub.Font = Enum.Font.GothamMedium
    DeviceSub.Parent = DeviceInner

    local PCBtn = Instance.new("TextButton")
    PCBtn.Size = UDim2.new(0.5, -14, 0, 48)
    PCBtn.Position = UDim2.new(0, 10, 0, 76)
    PCBtn.BackgroundColor3 = AppConfig.NestedCardBg
    PCBtn.Text = "💻  PC Mode"
    PCBtn.TextColor3 = AppConfig.TextPrimary
    PCBtn.TextSize = AppConfig.TextHeader
    PCBtn.Font = Enum.Font.GothamBold
    PCBtn.Parent = DeviceInner
    UIComponent.styleButton(PCBtn, AppConfig.RadiusLG, AppConfig.NestedCardBg)

    local MobileBtn = Instance.new("TextButton")
    MobileBtn.Size = UDim2.new(0.5, -14, 0, 48)
    MobileBtn.Position = UDim2.new(0.5, 4, 0, 76)
    MobileBtn.BackgroundColor3 = AppConfig.NestedCardBg
    MobileBtn.Text = "📱  Mobile"
    MobileBtn.TextColor3 = AppConfig.TextPrimary
    MobileBtn.TextSize = AppConfig.TextHeader
    MobileBtn.Font = Enum.Font.GothamBold
    MobileBtn.Parent = DeviceInner
    UIComponent.styleButton(MobileBtn, AppConfig.RadiusLG, AppConfig.NestedCardBg)

    -- ══════════════════════════════════════════════════════════════
    -- MAIN WINDOW
    -- ══════════════════════════════════════════════════════════════
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, AppConfig.PCWidth, 0, AppConfig.PCHeight)
    MainFrame.Position = UDim2.new(0.5, -AppConfig.PCWidth / 2, 0.5, -AppConfig.PCHeight / 2)
    MainFrame.BackgroundColor3 = AppConfig.BgColor
    MainFrame.BackgroundTransparency = AppConfig.BgTransparency
    MainFrame.BorderSizePixel = 0
    MainFrame.Active = true
    MainFrame.Visible = false
    MainFrame.ClipsDescendants = true
    MainFrame.Parent = ScreenGui
    UIComponent.applyCard(MainFrame, AppConfig.Radius2XL, AppConfig.BgColor, AppConfig.CardBorder)

    -- TopBar
    local TopBar = Instance.new("Frame")
    TopBar.Name = "TopBar"
    TopBar.Size = UDim2.new(1, 0, 0, 46)
    TopBar.BackgroundColor3 = AppConfig.BgColor
    TopBar.BackgroundTransparency = 1
    TopBar.BorderSizePixel = 0
    TopBar.Parent = MainFrame

    local TopDivider = Instance.new("Frame")
    TopDivider.Size = UDim2.new(1, -24, 0, 1)
    TopDivider.Position = UDim2.new(0, 12, 1, -1)
    TopDivider.BackgroundColor3 = AppConfig.BorderInner
    TopDivider.BackgroundTransparency = 0.4
    TopDivider.BorderSizePixel = 0
    TopDivider.Parent = TopBar

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(0, 320, 0, 20)
    TitleLabel.Position = UDim2.new(0, 16, 0, 8)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = "EGGS ESP  <font color='#00e676'>PRO</font>"
    TitleLabel.RichText = true
    TitleLabel.TextColor3 = AppConfig.TextPrimary
    TitleLabel.TextSize = AppConfig.TextTitle
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.Parent = TopBar

    local SubLabel = Instance.new("TextLabel")
    SubLabel.Size = UDim2.new(0, 320, 0, 14)
    SubLabel.Position = UDim2.new(0, 16, 0, 27)
    SubLabel.BackgroundTransparency = 1
    SubLabel.Text = "v" .. AppConfig.Version .. " • Sidebar Tabs & Nested Cards"
    SubLabel.TextColor3 = AppConfig.TextMuted
    SubLabel.TextSize = AppConfig.TextMicro
    SubLabel.Font = Enum.Font.GothamMedium
    SubLabel.TextXAlignment = Enum.TextXAlignment.Left
    SubLabel.Parent = TopBar

    local QuickStatusPill = Instance.new("Frame")
    QuickStatusPill.Size = UDim2.new(0, 160, 0, 26)
    QuickStatusPill.Position = UDim2.new(1, -300, 0.5, -13)
    QuickStatusPill.BackgroundColor3 = AppConfig.OuterCardBg
    QuickStatusPill.Parent = TopBar
    UIComponent.applyCard(QuickStatusPill, AppConfig.RadiusMD, AppConfig.OuterCardBg, AppConfig.BorderInner)

    local StatusDot = Instance.new("Frame")
    StatusDot.Size = UDim2.new(0, 6, 0, 6)
    StatusDot.Position = UDim2.new(0, 10, 0.5, -3)
    StatusDot.BackgroundColor3 = AppConfig.AccentGreen
    StatusDot.BorderSizePixel = 0
    StatusDot.Parent = QuickStatusPill

    local DotCorner = Instance.new("UICorner")
    DotCorner.CornerRadius = UDim.new(1, 0)
    DotCorner.Parent = StatusDot

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Size = UDim2.new(1, -26, 1, 0)
    StatusLabel.Position = UDim2.new(0, 22, 0, 0)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Text = "System Ready"
    StatusLabel.TextColor3 = AppConfig.AccentGreen
    StatusLabel.TextSize = AppConfig.TextCaption
    StatusLabel.Font = Enum.Font.GothamMedium
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
    StatusLabel.Parent = QuickStatusPill

    local function updateStatus(text, color)
        StatusLabel.Text = text
        StatusLabel.TextColor3 = color or AppConfig.TextPrimary
        StatusDot.BackgroundColor3 = color or AppConfig.AccentGreen
    end

    local ClockPill = Instance.new("Frame")
    ClockPill.Name = "ClockPill"
    ClockPill.Size = UDim2.new(0, 86, 0, 26)
    ClockPill.Position = UDim2.new(1, -132, 0.5, -13)
    ClockPill.BackgroundColor3 = AppConfig.NestedCardBg
    ClockPill.Parent = TopBar
    UIComponent.applyCard(ClockPill, AppConfig.RadiusMD, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local ClockIcon = Instance.new("TextLabel")
    ClockIcon.Size = UDim2.new(0, 18, 1, 0)
    ClockIcon.Position = UDim2.new(0, 6, 0, 0)
    ClockIcon.BackgroundTransparency = 1
    ClockIcon.Text = "⏱"
    ClockIcon.TextSize = 12
    ClockIcon.Font = Enum.Font.GothamBold
    ClockIcon.Parent = ClockPill

    local ClockLabel = Instance.new("TextLabel")
    ClockLabel.Name = "ClockLabel"
    ClockLabel.Size = UDim2.new(1, -24, 1, 0)
    ClockLabel.Position = UDim2.new(0, 22, 0, 0)
    ClockLabel.BackgroundTransparency = 1
    ClockLabel.Text = os.date("%H:%M:%S")
    ClockLabel.TextColor3 = AppConfig.AccentBlue
    ClockLabel.TextSize = AppConfig.TextCaption
    ClockLabel.Font = Enum.Font.GothamBold
    ClockLabel.TextXAlignment = Enum.TextXAlignment.Left
    ClockLabel.Parent = ClockPill

    local MinimizeBtn = Instance.new("TextButton")
    MinimizeBtn.Size = UDim2.new(0, 28, 0, 28)
    MinimizeBtn.Position = UDim2.new(1, -40, 0.5, -14)
    MinimizeBtn.BackgroundColor3 = AppConfig.OuterCardBg
    MinimizeBtn.Text = "—"
    MinimizeBtn.TextColor3 = AppConfig.TextSecondary
    MinimizeBtn.TextSize = 11
    MinimizeBtn.Font = Enum.Font.GothamBold
    MinimizeBtn.Parent = TopBar
    UIComponent.styleButton(MinimizeBtn, AppConfig.RadiusMD, AppConfig.OuterCardBg)

    -- ══════════════════════════════════════════════════════════════
    -- SIDEBAR
    -- ══════════════════════════════════════════════════════════════
    local Sidebar = Instance.new("Frame")
    Sidebar.Name = "Sidebar"
    Sidebar.Size = UDim2.new(0, AppConfig.SidebarWidth, 1, -58)
    Sidebar.Position = UDim2.new(0, 8, 0, 50)
    Sidebar.BackgroundColor3 = AppConfig.OuterCardBg
    Sidebar.Parent = MainFrame
    UIComponent.applyCard(Sidebar, AppConfig.RadiusXL, AppConfig.OuterCardBg, AppConfig.CardBorder)

    local SidebarLayout = Instance.new("UIListLayout")
    SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
    SidebarLayout.Padding = UDim.new(0, 3)
    SidebarLayout.Parent = Sidebar

    local SidebarPadding = Instance.new("UIPadding")
    SidebarPadding.PaddingTop = UDim.new(0, 8)
    SidebarPadding.PaddingBottom = UDim.new(0, 56)
    SidebarPadding.PaddingLeft = UDim.new(0, 6)
    SidebarPadding.PaddingRight = UDim.new(0, 6)
    SidebarPadding.Parent = Sidebar

    local SidebarFooter = Instance.new("Frame")
    SidebarFooter.Name = "SidebarFooter"
    SidebarFooter.Size = UDim2.new(1, -12, 0, 40)
    SidebarFooter.Position = UDim2.new(0, 6, 1, -48)
    SidebarFooter.BackgroundColor3 = AppConfig.NestedCardBg
    SidebarFooter.Parent = Sidebar
    UIComponent.applyCard(SidebarFooter, AppConfig.RadiusMD, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local FootPC = Instance.new("TextButton")
    FootPC.Size = UDim2.new(0.5, -3, 1, -6)
    FootPC.Position = UDim2.new(0, 3, 0, 3)
    FootPC.BackgroundColor3 = AppConfig.OuterCardBg
    FootPC.Text = "💻"
    FootPC.TextColor3 = AppConfig.TextSecondary
    FootPC.TextSize = 12
    FootPC.Font = Enum.Font.GothamBold
    FootPC.Parent = SidebarFooter
    UIComponent.styleButton(FootPC, AppConfig.RadiusSM, AppConfig.OuterCardBg)

    local FootMobile = Instance.new("TextButton")
    FootMobile.Size = UDim2.new(0.5, -3, 1, -6)
    FootMobile.Position = UDim2.new(0.5, 0, 0, 3)
    FootMobile.BackgroundColor3 = AppConfig.OuterCardBg
    FootMobile.Text = "📱"
    FootMobile.TextColor3 = AppConfig.TextSecondary
    FootMobile.TextSize = 12
    FootMobile.Font = Enum.Font.GothamBold
    FootMobile.Parent = SidebarFooter
    UIComponent.styleButton(FootMobile, AppConfig.RadiusSM, AppConfig.OuterCardBg)

    -- ══════════════════════════════════════════════════════════════
    -- CONTENT AREA
    -- ══════════════════════════════════════════════════════════════
    local ContentArea = Instance.new("Frame")
    ContentArea.Name = "ContentArea"
    ContentArea.Size = UDim2.new(1, -(AppConfig.SidebarWidth + 20), 1, -58)
    ContentArea.Position = UDim2.new(0, AppConfig.SidebarWidth + 12, 0, 50)
    ContentArea.BackgroundTransparency = 1
    ContentArea.ClipsDescendants = true
    ContentArea.Parent = MainFrame

    local Tabs = {
        { id = "Eggs",     label = "Eggs",       icon = "🥚" },
        { id = "Farm",     label = "Automation", icon = "⚡" },
        { id = "Backpack", label = "Backpack",   icon = "🎒" },
        { id = "History",  label = "History",    icon = "📜" },
        { id = "Settings", label = "Settings",   icon = "⚙️" },
    }

    local tabButtons = {}
    local tabPanels = {}
    local currentActiveTab = "Eggs"

    -- Size helper (declared early so minimize/keybind can use it)
    local function currentSize()
        if StateStore.windowMode == "PC" then
            return AppConfig.PCWidth, AppConfig.PCHeight
        else
            return AppConfig.MobileWidth, AppConfig.MobileHeight
        end
    end

    local function toggleMinimize()
        StateStore.isMinimized = not StateStore.isMinimized
        local w, h = currentSize()
        if StateStore.isMinimized then
            Sidebar.Visible = false
            ContentArea.Visible = false
            Utils.tween(MainFrame, { Size = UDim2.new(0, w, 0, 46) }, 0.20)
            MinimizeBtn.Text = "+"
        else
            Utils.tween(MainFrame, { Size = UDim2.new(0, w, 0, h) }, 0.20)
            task.delay(0.12, function()
                if not StateStore.isMinimized then
                    Sidebar.Visible = true
                    ContentArea.Visible = true
                end
            end)
            MinimizeBtn.Text = "—"
        end
    end

    MinimizeBtn.MouseButton1Click:Connect(toggleMinimize)

    local function switchTab(targetId)
        currentActiveTab = targetId
        for _, tab in ipairs(Tabs) do
            local isCurrent = (tab.id == targetId)
            local btn = tabButtons[tab.id]
            local panel = tabPanels[tab.id]
            if btn then
                local indicator = btn:FindFirstChild("ActiveBar")
                local icon = btn:FindFirstChild("Icon")
                local label = btn:FindFirstChild("Label")
                local bStroke = btn:FindFirstChildWhichIsA("UIStroke")
                if isCurrent then
                    Utils.tween(btn, { BackgroundColor3 = AppConfig.NestedCardBg }, 0.15)
                    if indicator then Utils.tween(indicator, { BackgroundTransparency = 0 }, 0.15) end
                    if icon then Utils.tween(icon, { TextColor3 = AppConfig.TextPrimary }, 0.15) end
                    if label then Utils.tween(label, { TextColor3 = AppConfig.TextPrimary }, 0.15) end
                    if bStroke then Utils.tween(bStroke, { Color = AppConfig.AccentGreen, Transparency = 0.15 }, 0.15) end
                else
                    Utils.tween(btn, { BackgroundColor3 = Color3.fromRGB(25, 25, 25) }, 0.15)
                    if indicator then Utils.tween(indicator, { BackgroundTransparency = 1 }, 0.15) end
                    if icon then Utils.tween(icon, { TextColor3 = AppConfig.TextMuted }, 0.15) end
                    if label then Utils.tween(label, { TextColor3 = AppConfig.TextSecondary }, 0.15) end
                    if bStroke then Utils.tween(bStroke, { Color = AppConfig.BorderInner, Transparency = 0.7 }, 0.15) end
                end
            end
            if panel then panel.Visible = isCurrent end
        end
    end

    for idx, tab in ipairs(Tabs) do
        local tabBtn = Instance.new("TextButton")
        tabBtn.Name = "Tab_" .. tab.id
        tabBtn.Size = UDim2.new(1, 0, 0, AppConfig.SidebarItemHeight)
        tabBtn.BackgroundColor3 = (tab.id == "Eggs") and AppConfig.NestedCardBg or Color3.fromRGB(25, 25, 25)
        tabBtn.Text = ""
        tabBtn.AutoButtonColor = false
        tabBtn.LayoutOrder = idx
        tabBtn.Parent = Sidebar

        local tc = Instance.new("UICorner")
        tc.CornerRadius = UDim.new(0, AppConfig.RadiusLG)
        tc.Parent = tabBtn

        local ts = Instance.new("UIStroke")
        ts.Color = (tab.id == "Eggs") and AppConfig.AccentGreen or AppConfig.BorderInner
        ts.Transparency = (tab.id == "Eggs") and 0.15 or 0.7
        ts.Thickness = 1
        ts.Parent = tabBtn

        local activeBar = Instance.new("Frame")
        activeBar.Name = "ActiveBar"
        activeBar.Size = UDim2.new(0, 3, 0, 20)
        activeBar.Position = UDim2.new(0, 0, 0.5, -10)
        activeBar.BackgroundColor3 = AppConfig.AccentGreen
        activeBar.BackgroundTransparency = (tab.id == "Eggs") and 0 or 1
        activeBar.BorderSizePixel = 0
        activeBar.Parent = tabBtn

        local abCorner = Instance.new("UICorner")
        abCorner.CornerRadius = UDim.new(1, 0)
        abCorner.Parent = activeBar

        local iconLbl = Instance.new("TextLabel")
        iconLbl.Name = "Icon"
        iconLbl.Size = UDim2.new(0, 24, 1, 0)
        iconLbl.Position = UDim2.new(0, 12, 0, 0)
        iconLbl.BackgroundTransparency = 1
        iconLbl.Text = tab.icon
        iconLbl.TextColor3 = (tab.id == "Eggs") and AppConfig.TextPrimary or AppConfig.TextMuted
        iconLbl.TextSize = 14
        iconLbl.Font = Enum.Font.GothamBold
        iconLbl.Parent = tabBtn

        local labelLbl = Instance.new("TextLabel")
        labelLbl.Name = "Label"
        labelLbl.Size = UDim2.new(1, -44, 1, 0)
        labelLbl.Position = UDim2.new(0, 40, 0, 0)
        labelLbl.BackgroundTransparency = 1
        labelLbl.Text = tab.label
        labelLbl.TextColor3 = (tab.id == "Eggs") and AppConfig.TextPrimary or AppConfig.TextSecondary
        labelLbl.TextSize = AppConfig.TextBody
        labelLbl.Font = Enum.Font.GothamBold
        labelLbl.TextXAlignment = Enum.TextXAlignment.Left
        labelLbl.Parent = tabBtn

        tabBtn.MouseEnter:Connect(function()
            if currentActiveTab ~= tab.id then
                Utils.tween(tabBtn, { BackgroundColor3 = Color3.fromRGB(34, 34, 34) }, 0.12)
                Utils.tween(iconLbl, { TextColor3 = AppConfig.TextSecondary }, 0.12)
            end
        end)
        tabBtn.MouseLeave:Connect(function()
            if currentActiveTab ~= tab.id then
                Utils.tween(tabBtn, { BackgroundColor3 = Color3.fromRGB(25, 25, 25) }, 0.12)
                Utils.tween(iconLbl, { TextColor3 = AppConfig.TextMuted }, 0.12)
            end
        end)
        tabBtn.MouseButton1Click:Connect(function() switchTab(tab.id) end)

        tabButtons[tab.id] = tabBtn

        local panelFrame = Instance.new("Frame")
        panelFrame.Name = "Panel_" .. tab.id
        panelFrame.Size = UDim2.new(1, 0, 1, 0)
        panelFrame.BackgroundColor3 = AppConfig.OuterCardBg
        panelFrame.Visible = (tab.id == "Eggs")
        panelFrame.Parent = ContentArea
        UIComponent.applyCard(panelFrame, AppConfig.Radius2XL, AppConfig.OuterCardBg, AppConfig.CardBorder)

        local panelPadding = Instance.new("UIPadding")
        panelPadding.PaddingTop = UDim.new(0, 10)
        panelPadding.PaddingBottom = UDim.new(0, 10)
        panelPadding.PaddingLeft = UDim.new(0, 10)
        panelPadding.PaddingRight = UDim.new(0, 10)
        panelPadding.Parent = panelFrame

        tabPanels[tab.id] = panelFrame
    end

    local populateList
    local updateLiveEggsSummary
    local updateBackpackUI
    local updateHistoryUI

    -- ══════════════════════════════════════════════════════════════
    -- [TAB 1] EGGS
    -- ══════════════════════════════════════════════════════════════
    local EggsPanel = tabPanels["Eggs"]

    local LiveChipsCard = Instance.new("Frame")
    LiveChipsCard.Size = UDim2.new(1, 0, 0, 56)
    LiveChipsCard.BackgroundColor3 = AppConfig.NestedCardBg
    LiveChipsCard.Parent = EggsPanel
    UIComponent.applyCard(LiveChipsCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local LiveTitle = Instance.new("TextLabel")
    LiveTitle.Size = UDim2.new(0.5, 0, 0, 18)
    LiveTitle.Position = UDim2.new(0, 12, 0, 8)
    LiveTitle.BackgroundTransparency = 1
    LiveTitle.Text = "🥚  Live Eggs Realtime"
    LiveTitle.TextColor3 = AppConfig.AccentGold
    LiveTitle.TextSize = AppConfig.TextHeader
    LiveTitle.Font = Enum.Font.GothamBold
    LiveTitle.TextXAlignment = Enum.TextXAlignment.Left
    LiveTitle.Parent = LiveChipsCard

    local LiveSummaryCountLabel = Instance.new("TextLabel")
    LiveSummaryCountLabel.Size = UDim2.new(0.5, -12, 0, 18)
    LiveSummaryCountLabel.Position = UDim2.new(0.5, 0, 0, 8)
    LiveSummaryCountLabel.BackgroundTransparency = 1
    LiveSummaryCountLabel.Text = "Total Live: 0"
    LiveSummaryCountLabel.TextColor3 = AppConfig.TextMuted
    LiveSummaryCountLabel.TextSize = AppConfig.TextCaption
    LiveSummaryCountLabel.Font = Enum.Font.GothamMedium
    LiveSummaryCountLabel.TextXAlignment = Enum.TextXAlignment.Right
    LiveSummaryCountLabel.Parent = LiveChipsCard

    local LiveSummaryContainer = Instance.new("ScrollingFrame")
    LiveSummaryContainer.Size = UDim2.new(1, -20, 0, 26)
    LiveSummaryContainer.Position = UDim2.new(0, 10, 0, 28)
    LiveSummaryContainer.BackgroundTransparency = 1
    LiveSummaryContainer.BorderSizePixel = 0
    LiveSummaryContainer.ScrollBarThickness = 2
    LiveSummaryContainer.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
    LiveSummaryContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    LiveSummaryContainer.Parent = LiveChipsCard

    local LiveSummaryLayout = Instance.new("UIListLayout")
    LiveSummaryLayout.SortOrder = Enum.SortOrder.LayoutOrder
    LiveSummaryLayout.FillDirection = Enum.FillDirection.Horizontal
    LiveSummaryLayout.Padding = UDim.new(0, 4)
    LiveSummaryLayout.Parent = LiveSummaryContainer

    LiveSummaryLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        LiveSummaryContainer.CanvasSize = UDim2.new(0, LiveSummaryLayout.AbsoluteContentSize.X + 6, 0, 0)
    end)

    local ToolbarCard = Instance.new("Frame")
    ToolbarCard.Size = UDim2.new(1, 0, 0, 42)
    ToolbarCard.Position = UDim2.new(0, 0, 0, 64)
    ToolbarCard.BackgroundColor3 = AppConfig.NestedCardBg
    ToolbarCard.Parent = EggsPanel
    UIComponent.applyCard(ToolbarCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local SearchBoxContainer = Instance.new("Frame")
    SearchBoxContainer.Size = UDim2.new(0.36, 0, 0, 28)
    SearchBoxContainer.Position = UDim2.new(0, 8, 0.5, -14)
    SearchBoxContainer.BackgroundColor3 = AppConfig.RecessedBg
    SearchBoxContainer.Parent = ToolbarCard
    UIComponent.applyCard(SearchBoxContainer, AppConfig.RadiusMD, AppConfig.RecessedBg, AppConfig.BorderInner)

    local SearchBox = Instance.new("TextBox")
    SearchBox.Size = UDim2.new(1, -28, 1, 0)
    SearchBox.Position = UDim2.new(0, 10, 0, 0)
    SearchBox.BackgroundTransparency = 1
    SearchBox.PlaceholderText = "🔍 Search egg..."
    SearchBox.PlaceholderColor3 = AppConfig.TextMuted
    SearchBox.Text = ""
    SearchBox.TextColor3 = AppConfig.TextPrimary
    SearchBox.TextSize = AppConfig.TextCaption
    SearchBox.Font = Enum.Font.GothamMedium
    SearchBox.TextXAlignment = Enum.TextXAlignment.Left
    SearchBox.ClearTextOnFocus = false
    SearchBox.Parent = SearchBoxContainer

    local ClearSearchBtn = Instance.new("TextButton")
    ClearSearchBtn.Size = UDim2.new(0, 22, 0, 22)
    ClearSearchBtn.Position = UDim2.new(1, -24, 0.5, -11)
    ClearSearchBtn.BackgroundTransparency = 1
    ClearSearchBtn.Text = "✕"
    ClearSearchBtn.TextColor3 = AppConfig.TextMuted
    ClearSearchBtn.TextSize = 10
    ClearSearchBtn.Font = Enum.Font.GothamBold
    ClearSearchBtn.Visible = false
    ClearSearchBtn.Parent = SearchBoxContainer

    local FarmAllBtn = Instance.new("TextButton")
    FarmAllBtn.Size = UDim2.new(0.19, -4, 0, 28)
    FarmAllBtn.Position = UDim2.new(0.37, 2, 0.5, -14)
    FarmAllBtn.BackgroundColor3 = AppConfig.RecessedBg
    FarmAllBtn.Text = "⚡ Farm All"
    FarmAllBtn.TextColor3 = AppConfig.AccentGreen
    FarmAllBtn.TextSize = AppConfig.TextCaption
    FarmAllBtn.Font = Enum.Font.GothamBold
    FarmAllBtn.Parent = ToolbarCard
    UIComponent.styleButton(FarmAllBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local ClearFarmBtn = Instance.new("TextButton")
    ClearFarmBtn.Size = UDim2.new(0.16, -4, 0, 28)
    ClearFarmBtn.Position = UDim2.new(0.56, 2, 0.5, -14)
    ClearFarmBtn.BackgroundColor3 = AppConfig.RecessedBg
    ClearFarmBtn.Text = "✕ Clear"
    ClearFarmBtn.TextColor3 = AppConfig.AccentRed
    ClearFarmBtn.TextSize = AppConfig.TextCaption
    ClearFarmBtn.Font = Enum.Font.GothamBold
    ClearFarmBtn.Parent = ToolbarCard
    UIComponent.styleButton(ClearFarmBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local SortBtn = Instance.new("TextButton")
    SortBtn.Size = UDim2.new(0.16, -4, 0, 28)
    SortBtn.Position = UDim2.new(0.72, 2, 0.5, -14)
    SortBtn.BackgroundColor3 = AppConfig.RecessedBg
    SortBtn.Text = "Sort: Name"
    SortBtn.TextColor3 = AppConfig.TextPrimary
    SortBtn.TextSize = AppConfig.TextCaption
    SortBtn.Font = Enum.Font.GothamBold
    SortBtn.Parent = ToolbarCard
    UIComponent.styleButton(SortBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local EggCountLabel = Instance.new("TextLabel")
    EggCountLabel.Size = UDim2.new(0.11, -4, 0, 28)
    EggCountLabel.Position = UDim2.new(0.88, 0, 0.5, -14)
    EggCountLabel.BackgroundTransparency = 1
    EggCountLabel.Text = "0/0"
    EggCountLabel.TextColor3 = AppConfig.TextMuted
    EggCountLabel.TextSize = AppConfig.TextCaption
    EggCountLabel.Font = Enum.Font.GothamMedium
    EggCountLabel.TextXAlignment = Enum.TextXAlignment.Center
    EggCountLabel.Parent = ToolbarCard

    local ListCard = Instance.new("Frame")
    ListCard.Size = UDim2.new(1, 0, 1, -114)
    ListCard.Position = UDim2.new(0, 0, 0, 114)
    ListCard.BackgroundColor3 = AppConfig.NestedCardBg
    ListCard.Parent = EggsPanel
    UIComponent.applyCard(ListCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local ScrollList = Instance.new("ScrollingFrame")
    ScrollList.Size = UDim2.new(1, -16, 1, -16)
    ScrollList.Position = UDim2.new(0, 8, 0, 8)
    ScrollList.BackgroundTransparency = 1
    ScrollList.BorderSizePixel = 0
    ScrollList.ScrollBarThickness = 3
    ScrollList.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
    ScrollList.CanvasSize = UDim2.new(0, 0, 0, 0)
    ScrollList.Parent = ListCard

    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    UIListLayout.Padding = UDim.new(0, 4)
    UIListLayout.Parent = ScrollList

    UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        ScrollList.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 6)
    end)

    local renderedEggRows = {}

    local function createEggItem(egg)
        local itemHeight = 38
        local ItemFrame = Instance.new("Frame")
        ItemFrame.Size = UDim2.new(1, -4, 0, itemHeight)
        ItemFrame.BackgroundColor3 = AppConfig.RecessedBg
        ItemFrame.BorderSizePixel = 0
        ItemFrame.Parent = ScrollList
        UIComponent.applyCard(ItemFrame, AppConfig.RadiusLG, AppConfig.RecessedBg, AppConfig.BorderInner)

        local eggIcon = Instance.new("ImageLabel")
        eggIcon.Size = UDim2.new(0, itemHeight - 10, 0, itemHeight - 10)
        eggIcon.Position = UDim2.new(0, 8, 0.5, -(itemHeight - 10) / 2)
        eggIcon.BackgroundTransparency = 1
        eggIcon.Image = Utils.getEggImage(egg.Name)
        eggIcon.ScaleType = Enum.ScaleType.Fit
        eggIcon.Parent = ItemFrame

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -240, 1, 0)
        nameLabel.Position = UDim2.new(0, itemHeight + 8, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = egg.Name
        nameLabel.TextColor3 = Utils.isRareEgg(egg.Name) and AppConfig.AccentGold or AppConfig.TextPrimary
        nameLabel.TextSize = AppConfig.TextBody
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = ItemFrame

        local distBadge = Instance.new("Frame")
        distBadge.Size = UDim2.new(0, 50, 0, 20)
        distBadge.Position = UDim2.new(1, -220, 0.5, -10)
        distBadge.BackgroundColor3 = AppConfig.NestedCardBg
        distBadge.Parent = ItemFrame
        UIComponent.applyCard(distBadge, AppConfig.RadiusSM, AppConfig.NestedCardBg, AppConfig.BorderInner)

        local distLabel = Instance.new("TextLabel")
        distLabel.Size = UDim2.new(1, 0, 1, 0)
        distLabel.BackgroundTransparency = 1
        distLabel.TextColor3 = AppConfig.TextMuted
        distLabel.TextSize = AppConfig.TextCaption
        distLabel.Font = Enum.Font.Gotham
        local dist = Utils.getDistanceToTarget(egg)
        distLabel.Text = (dist ~= math.huge) and string.format("%dst", math.floor(dist + 0.5)) or "--"
        distLabel.Parent = distBadge

        local TPBtn = Instance.new("TextButton")
        TPBtn.Size = UDim2.new(0, 38, 0, 24)
        TPBtn.Position = UDim2.new(1, -164, 0.5, -12)
        TPBtn.BackgroundColor3 = AppConfig.NestedCardBg
        TPBtn.Text = "TP"
        TPBtn.TextColor3 = AppConfig.TextPrimary
        TPBtn.TextSize = AppConfig.TextCaption
        TPBtn.Font = Enum.Font.GothamBold
        TPBtn.Parent = ItemFrame
        UIComponent.styleButton(TPBtn, AppConfig.RadiusSM, AppConfig.NestedCardBg)

        TPBtn.MouseButton1Click:Connect(function()
            if not egg or not egg.Parent then updateStatus("Egg despawned!", AppConfig.AccentRed) return end
            local ok = MovementComponent.teleportTo(egg)
            if ok then updateStatus("Teleported to " .. egg.Name, AppConfig.AccentGreen) end
        end)

        local AutoFarmBtn = Instance.new("TextButton")
        AutoFarmBtn.Size = UDim2.new(0, 56, 0, 24)
        AutoFarmBtn.Position = UDim2.new(1, -122, 0.5, -12)
        local isFarming = StateStore.autoFarmEggs[egg.Name]
        local farmBg = isFarming and AppConfig.AccentGreen or AppConfig.NestedCardBg
        AutoFarmBtn.BackgroundColor3 = farmBg
        AutoFarmBtn.Text = isFarming and "Farm ON" or "Farm"
        AutoFarmBtn.TextColor3 = isFarming and Color3.fromRGB(10, 20, 15) or AppConfig.TextSecondary
        AutoFarmBtn.TextSize = AppConfig.TextCaption
        AutoFarmBtn.Font = Enum.Font.GothamBold
        AutoFarmBtn.Parent = ItemFrame
        UIComponent.styleButton(AutoFarmBtn, AppConfig.RadiusSM, farmBg)

        AutoFarmBtn.MouseButton1Click:Connect(function()
            if not egg or not egg.Parent then return end
            local name = egg.Name
            if StateStore.autoFarmEggs[name] then
                StateStore.autoFarmEggs[name] = nil
                UIComponent.setButtonDefault(AutoFarmBtn, AppConfig.NestedCardBg)
                AutoFarmBtn.Text = "Farm"
                AutoFarmBtn.TextColor3 = AppConfig.TextSecondary
                updateStatus("Removed from Farm: " .. name, AppConfig.TextSecondary)
                local any = false
                for _, v in pairs(StateStore.autoFarmEggs) do if v then any = true break end end
                if not any then FarmComponent.stopAutoFarm() end
            else
                StateStore.autoFarmEggs[name] = true
                UIComponent.setButtonDefault(AutoFarmBtn, AppConfig.AccentGreen)
                AutoFarmBtn.Text = "Farm ON"
                AutoFarmBtn.TextColor3 = Color3.fromRGB(10, 20, 15)
                updateStatus("AutoFarm target: " .. name, AppConfig.AccentGreen)
                if not StateStore.autoFarmActive then
                    FarmComponent.startAutoFarm(updateStatus, nil)
                end
            end
            for pe in pairs(StateStore.autoFarmProcessed) do
                if pe and pe.Name == name then StateStore.autoFarmProcessed[pe] = nil end
            end
        end)

        local ESPBtn = Instance.new("TextButton")
        ESPBtn.Size = UDim2.new(0, 46, 0, 24)
        ESPBtn.Position = UDim2.new(1, -62, 0.5, -12)
        ESPBtn.BackgroundColor3 = AppConfig.NestedCardBg
        ESPBtn.TextColor3 = AppConfig.TextSecondary
        ESPBtn.TextSize = AppConfig.TextCaption
        ESPBtn.Font = Enum.Font.GothamBold
        ESPBtn.Parent = ItemFrame
        UIComponent.styleButton(ESPBtn, AppConfig.RadiusSM, AppConfig.NestedCardBg)

        local eggColor = ESPComponent.getColor(egg.Name)
        local ed = StateStore.eggData[egg]
        if ed and ed.CustomActive then
            UIComponent.setButtonDefault(ESPBtn, eggColor)
            ESPBtn.Text = "ON"
            ESPBtn.TextColor3 = Color3.fromRGB(10, 10, 10)
        else
            ESPBtn.Text = "ESP"
        end

        ESPBtn.MouseButton1Click:Connect(function()
            if not StateStore.eggData[egg] then
                StateStore.eggData[egg] = {
                    Highlight = nil, NameBillboard = nil,
                    CustomColor = eggColor, CustomActive = false
                }
            end
            local info = StateStore.eggData[egg]
            info.CustomActive = not info.CustomActive
            info.CustomColor = eggColor
            if info.CustomActive then
                UIComponent.setButtonDefault(ESPBtn, eggColor)
                ESPBtn.Text = "ON"
                ESPBtn.TextColor3 = Color3.fromRGB(10, 10, 10)
                updateStatus("Target ESP: " .. egg.Name, eggColor)
            else
                UIComponent.setButtonDefault(ESPBtn, AppConfig.NestedCardBg)
                ESPBtn.Text = "ESP"
                ESPBtn.TextColor3 = AppConfig.TextSecondary
                updateStatus("Target ESP: OFF", AppConfig.TextSecondary)
            end
            ESPComponent.updateEgg(egg)
        end)

        return ItemFrame
    end

    populateList = function()
        local savedPos = ScrollList.CanvasPosition
        local folder = ServiceManager.RenderedEggsFolder

        -- Always update the count label
        if not folder then
            EggCountLabel.Text = "0/0"
            for egg, row in pairs(renderedEggRows) do
                row:Destroy()
                renderedEggRows[egg] = nil
            end
            return
        end

        local found = {}
        for _, egg in ipairs(folder:GetChildren()) do
            if Utils.isValidEgg(egg) then table.insert(found, egg) end
        end

        if StateStore.sortMode == "Distance" then
            table.sort(found, function(a, b) return Utils.getDistanceToTarget(a) < Utils.getDistanceToTarget(b) end)
        else
            table.sort(found, function(a, b) return a.Name:lower() < b.Name:lower() end)
        end

        local query = StateStore.currentSearchQuery:lower()
        local visible = {}
        for _, egg in ipairs(found) do
            if query == "" or string.find(egg.Name:lower(), query, 1, true) then
                table.insert(visible, egg)
            end
        end

        local visibleSet = {}
        for _, egg in ipairs(visible) do visibleSet[egg] = true end

        for egg, row in pairs(renderedEggRows) do
            if not visibleSet[egg] or not egg.Parent then
                row:Destroy()
                renderedEggRows[egg] = nil
            end
        end

        for i, egg in ipairs(visible) do
            local row = renderedEggRows[egg]
            if not row or not row.Parent then
                row = createEggItem(egg)
                renderedEggRows[egg] = row
            end
            row.LayoutOrder = i
        end

        EggCountLabel.Text = string.format("%d/%d", #visible, #found)

        if #visible == 0 then
            if not ScrollList:FindFirstChild("EmptyLabel") then
                local emptyLabel = Instance.new("TextLabel")
                emptyLabel.Name = "EmptyLabel"
                emptyLabel.Size = UDim2.new(1, -10, 0, 40)
                emptyLabel.BackgroundTransparency = 1
                emptyLabel.Text = "No Eggs Found / ไม่พบไข่"
                emptyLabel.TextColor3 = AppConfig.TextMuted
                emptyLabel.TextSize = AppConfig.TextBody
                emptyLabel.Font = Enum.Font.GothamMedium
                emptyLabel.Parent = ScrollList
            end
        else
            local el = ScrollList:FindFirstChild("EmptyLabel")
            if el then el:Destroy() end
        end

        task.defer(function()
            if ScrollList and ScrollList.Parent then ScrollList.CanvasPosition = savedPos end
        end)
    end

    local renderedChips = {}

    updateLiveEggsSummary = function()
        local folder = ServiceManager.RenderedEggsFolder
        if not folder then return end

        local counts = {}
        local total = 0
        for _, egg in ipairs(folder:GetChildren()) do
            if Utils.isValidEgg(egg) then
                counts[egg.Name] = (counts[egg.Name] or 0) + 1
                total += 1
            end
        end

        LiveSummaryCountLabel.Text = "Total Live: " .. tostring(total)

        for name, chip in pairs(renderedChips) do
            if not counts[name] then
                chip:Destroy()
                renderedChips[name] = nil
            end
        end

        for name, count in pairs(counts) do
            local chip = renderedChips[name]
            if chip and chip.Parent then
                local badge = chip:FindFirstChild("CountBadge")
                if badge then badge.Text = "x" .. tostring(count) end
            else
                local isRare = Utils.isRareEgg(name)
                chip = Instance.new("TextButton")
                chip.Size = UDim2.new(0, 138, 0, 24)
                chip.BackgroundColor3 = isRare and Color3.fromRGB(36, 30, 20) or AppConfig.RecessedBg
                chip.Text = ""
                chip.Parent = LiveSummaryContainer
                UIComponent.applyCard(chip, AppConfig.RadiusSM, chip.BackgroundColor3, isRare and AppConfig.AccentGold or AppConfig.BorderInner)

                local icon = Instance.new("ImageLabel")
                icon.Size = UDim2.new(0, 16, 0, 16)
                icon.Position = UDim2.new(0, 5, 0.5, -8)
                icon.BackgroundTransparency = 1
                icon.Image = Utils.getEggImage(name)
                icon.ScaleType = Enum.ScaleType.Fit
                icon.Parent = chip

                local title = Instance.new("TextLabel")
                title.Size = UDim2.new(1, -50, 1, 0)
                title.Position = UDim2.new(0, 25, 0, 0)
                title.BackgroundTransparency = 1
                title.Text = name
                title.TextColor3 = isRare and AppConfig.AccentGold or AppConfig.TextPrimary
                title.TextSize = AppConfig.TextCaption
                title.Font = Enum.Font.GothamMedium
                title.TextXAlignment = Enum.TextXAlignment.Left
                title.TextTruncate = Enum.TextTruncate.AtEnd
                title.Parent = chip

                local badge = Instance.new("TextLabel")
                badge.Name = "CountBadge"
                badge.Size = UDim2.new(0, 22, 0, 16)
                badge.Position = UDim2.new(1, -26, 0.5, -8)
                badge.BackgroundColor3 = isRare and AppConfig.AccentGold or AppConfig.NestedCardBg
                badge.Text = "x" .. tostring(count)
                badge.TextColor3 = isRare and Color3.fromRGB(15, 15, 20) or AppConfig.TextSecondary
                badge.TextSize = AppConfig.TextMicro
                badge.Font = Enum.Font.GothamBold
                badge.Parent = chip

                local bc = Instance.new("UICorner")
                bc.CornerRadius = UDim.new(0, 4)
                bc.Parent = badge

                chip.MouseButton1Click:Connect(function()
                    if SearchBox.Text == name then
                        SearchBox.Text = ""
                        StateStore.currentSearchQuery = ""
                        ClearSearchBtn.Visible = false
                        updateStatus("Filter cleared", AppConfig.TextSecondary)
                    else
                        SearchBox.Text = name
                        StateStore.currentSearchQuery = name
                        ClearSearchBtn.Visible = true
                        updateStatus("Filtered: " .. name, AppConfig.AccentGreen)
                    end
                    populateList()
                end)

                renderedChips[name] = chip
            end
        end
    end

    FarmAllBtn.MouseButton1Click:Connect(function()
        local folder = ServiceManager.RenderedEggsFolder
        if not folder then return end
        for _, egg in ipairs(folder:GetChildren()) do
            if Utils.isValidEgg(egg) then StateStore.autoFarmEggs[egg.Name] = true end
        end
        populateList()
        updateStatus("All Eggs Selected for AutoFarm", AppConfig.AccentGreen)
        if not StateStore.autoFarmActive then FarmComponent.startAutoFarm(updateStatus, nil) end
    end)

    ClearFarmBtn.MouseButton1Click:Connect(function()
        table.clear(StateStore.autoFarmEggs)
        table.clear(StateStore.autoFarmProcessed)
        FarmComponent.stopAutoFarm()
        populateList()
        updateStatus("Cleared AutoFarm targets", AppConfig.AccentRed)
    end)

    SortBtn.MouseButton1Click:Connect(function()
        if StateStore.sortMode == "Name" then
            StateStore.sortMode = "Distance"
            SortBtn.Text = "Sort: Dist"
        else
            StateStore.sortMode = "Name"
            SortBtn.Text = "Sort: Name"
        end
        populateList()
    end)

    local searchDebounce = nil
    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local newQuery = SearchBox.Text:match("^%s*(.-)%s*$") or ""
        ClearSearchBtn.Visible = (#newQuery > 0)
        if newQuery == StateStore.currentSearchQuery then return end
        StateStore.currentSearchQuery = newQuery
        if searchDebounce then task.cancel(searchDebounce) end
        searchDebounce = task.delay(0.12, populateList)
    end)

    ClearSearchBtn.MouseButton1Click:Connect(function()
        SearchBox.Text = ""
        StateStore.currentSearchQuery = ""
        ClearSearchBtn.Visible = false
        populateList()
    end)

    -- ══════════════════════════════════════════════════════════════
    -- [TAB 2] AUTOMATION
    -- ══════════════════════════════════════════════════════════════
    local FarmPanel = tabPanels["Farm"]

    local FarmScroll = Instance.new("ScrollingFrame")
    FarmScroll.Size = UDim2.new(1, 0, 1, 0)
    FarmScroll.BackgroundTransparency = 1
    FarmScroll.BorderSizePixel = 0
    FarmScroll.ScrollBarThickness = 3
    FarmScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
    FarmScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    FarmScroll.Parent = FarmPanel

    local FarmScrollLayout = Instance.new("UIListLayout")
    FarmScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    FarmScrollLayout.Padding = UDim.new(0, 8)
    FarmScrollLayout.Parent = FarmScroll

    FarmScrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        FarmScroll.CanvasSize = UDim2.new(0, 0, 0, FarmScrollLayout.AbsoluteContentSize.Y + 12)
    end)

    local FarmStatusCard = Instance.new("Frame")
    FarmStatusCard.Size = UDim2.new(1, -4, 0, 56)
    FarmStatusCard.LayoutOrder = 1
    FarmStatusCard.BackgroundColor3 = AppConfig.NestedCardBg
    FarmStatusCard.Parent = FarmScroll
    UIComponent.applyCard(FarmStatusCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local FsTitle = Instance.new("TextLabel")
    FsTitle.Size = UDim2.new(1, -120, 0, 20)
    FsTitle.Position = UDim2.new(0, 14, 0, 8)
    FsTitle.BackgroundTransparency = 1
    FsTitle.Text = "⚡  Farm Engine Status"
    FsTitle.TextColor3 = AppConfig.TextPrimary
    FsTitle.TextSize = AppConfig.TextHeader
    FsTitle.Font = Enum.Font.GothamBold
    FsTitle.TextXAlignment = Enum.TextXAlignment.Left
    FsTitle.Parent = FarmStatusCard

    local FsSub = Instance.new("TextLabel")
    FsSub.Size = UDim2.new(1, -120, 0, 16)
    FsSub.Position = UDim2.new(0, 14, 0, 30)
    FsSub.BackgroundTransparency = 1
    FsSub.Text = "Master control & quick halt"
    FsSub.TextColor3 = AppConfig.TextMuted
    FsSub.TextSize = AppConfig.TextCaption
    FsSub.Font = Enum.Font.GothamMedium
    FsSub.TextXAlignment = Enum.TextXAlignment.Left
    FsSub.Parent = FarmStatusCard

    local StopFarmBtn = Instance.new("TextButton")
    StopFarmBtn.Size = UDim2.new(0, 96, 0, 30)
    StopFarmBtn.Position = UDim2.new(1, -110, 0.5, -15)
    StopFarmBtn.BackgroundColor3 = AppConfig.AccentRed
    StopFarmBtn.Text = "■ Stop All"
    StopFarmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    StopFarmBtn.TextSize = AppConfig.TextCaption
    StopFarmBtn.Font = Enum.Font.GothamBold
    StopFarmBtn.Parent = FarmStatusCard
    UIComponent.styleButton(StopFarmBtn, AppConfig.RadiusMD, AppConfig.AccentRed)

    StopFarmBtn.MouseButton1Click:Connect(function()
        FarmComponent.stopAutoFarm()
        FarmComponent.stopAutoBestEgg()
        RebirthComponent.stopAutoRebirth()
        updateStatus("Engine Halted", AppConfig.AccentRed)
    end)

    UIComponent.createToggle(FarmScroll, "Auto Selected Eggs Farm", "คำนวณและฟาร์มไข่เฉพาะรายการที่เลือกไว้", StateStore.autoFarmActive, function(enabled)
        if enabled then FarmComponent.startAutoFarm(updateStatus, nil)
        else FarmComponent.stopAutoFarm(); updateStatus("AutoFarm Stopped", AppConfig.TextSecondary) end
    end)

    UIComponent.createToggle(FarmScroll, "Auto Best Egg Target", "ค้นหาและเก็บไข่ที่ดีที่สุดโดยอัตโนมัติ", StateStore.autoBestEggActive, function(enabled)
        if enabled then FarmComponent.startAutoBestEgg(updateStatus)
        else FarmComponent.stopAutoBestEgg(); updateStatus("Best Egg Farm Stopped", AppConfig.TextSecondary) end
    end)

    UIComponent.createToggle(FarmScroll, "Auto Rebirth & Collect", "เก็บไข่ที่ขาดและกด Rebirth อัตโนมัติ", StateStore.autoRebirthActive, function(enabled)
        if enabled then RebirthComponent.startAutoRebirth(updateStatus, nil)
        else RebirthComponent.stopAutoRebirth(); updateStatus("Auto Rebirth Stopped", AppConfig.TextSecondary) end
    end)

    UIComponent.createSlider(FarmScroll, "Movement Speed (ความเร็ว)", 200, 1000, AppConfig.MovementSpeed, "studs/s", function(val)
        AppConfig.MovementSpeed = val
    end)

    UIComponent.createSlider(FarmScroll, "Auto Collect Hold (กด E)", 0.5, 5, AppConfig.AutoFarmHoldTime, "sec", function(val)
        AppConfig.AutoFarmHoldTime = val
        AppConfig.AutoEggHoldTime = val
    end)

    UIComponent.createSlider(FarmScroll, "Egg Cooldown (คูลดาวน์)", 5, 30, AppConfig.EggCooldownSeconds, "sec", function(val)
        AppConfig.EggCooldownSeconds = val
    end)

    local MovementCard = Instance.new("Frame")
    MovementCard.Size = UDim2.new(1, -4, 0, 76)
    MovementCard.LayoutOrder = 5
    MovementCard.BackgroundColor3 = AppConfig.NestedCardBg
    MovementCard.Parent = FarmScroll
    UIComponent.applyCard(MovementCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local MvTitle = Instance.new("TextLabel")
    MvTitle.Size = UDim2.new(1, -20, 0, 20)
    MvTitle.Position = UDim2.new(0, 14, 0, 8)
    MvTitle.BackgroundTransparency = 1
    MvTitle.Text = "Movement Mode"
    MvTitle.TextColor3 = AppConfig.TextPrimary
    MvTitle.TextSize = AppConfig.TextHeader
    MvTitle.Font = Enum.Font.GothamBold
    MvTitle.TextXAlignment = Enum.TextXAlignment.Left
    MvTitle.Parent = MovementCard

    local ModeAutoFarmBtn = Instance.new("TextButton")
    ModeAutoFarmBtn.Size = UDim2.new(0.5, -18, 0, 30)
    ModeAutoFarmBtn.Position = UDim2.new(0, 10, 0, 36)
    ModeAutoFarmBtn.BackgroundColor3 = AppConfig.AccentGreen
    ModeAutoFarmBtn.Text = "⚡ Glide + Noclip"
    ModeAutoFarmBtn.TextColor3 = Color3.fromRGB(10, 20, 15)
    ModeAutoFarmBtn.TextSize = AppConfig.TextCaption
    ModeAutoFarmBtn.Font = Enum.Font.GothamBold
    ModeAutoFarmBtn.Parent = MovementCard
    UIComponent.styleButton(ModeAutoFarmBtn, AppConfig.RadiusMD, AppConfig.AccentGreen)

    local ModeTeleportBtn = Instance.new("TextButton")
    ModeTeleportBtn.Size = UDim2.new(0.5, -18, 0, 30)
    ModeTeleportBtn.Position = UDim2.new(0.5, 8, 0, 36)
    ModeTeleportBtn.BackgroundColor3 = AppConfig.RecessedBg
    ModeTeleportBtn.Text = "🌀 Instant TP"
    ModeTeleportBtn.TextColor3 = AppConfig.TextSecondary
    ModeTeleportBtn.TextSize = AppConfig.TextCaption
    ModeTeleportBtn.Font = Enum.Font.GothamBold
    ModeTeleportBtn.Parent = MovementCard
    UIComponent.styleButton(ModeTeleportBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local function updateMovementModeUI()
        if StateStore.movementMode == "AutoFarm" then
            UIComponent.setButtonDefault(ModeAutoFarmBtn, AppConfig.AccentGreen)
            ModeAutoFarmBtn.TextColor3 = Color3.fromRGB(10, 20, 15)
            UIComponent.setButtonDefault(ModeTeleportBtn, AppConfig.RecessedBg)
            ModeTeleportBtn.TextColor3 = AppConfig.TextSecondary
        else
            UIComponent.setButtonDefault(ModeAutoFarmBtn, AppConfig.RecessedBg)
            ModeAutoFarmBtn.TextColor3 = AppConfig.TextSecondary
            UIComponent.setButtonDefault(ModeTeleportBtn, AppConfig.AccentBlue)
            ModeTeleportBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    end

    ModeAutoFarmBtn.MouseButton1Click:Connect(function()
        MovementComponent.stop()
        StateStore.movementMode = "AutoFarm"
        updateMovementModeUI()
        updateStatus("Movement: Glide + Noclip", AppConfig.AccentGreen)
    end)

    ModeTeleportBtn.MouseButton1Click:Connect(function()
        MovementComponent.stop()
        StateStore.movementMode = "Teleport"
        updateMovementModeUI()
        updateStatus("Movement: Instant TP", AppConfig.AccentBlue)
    end)

    local UtilCard = Instance.new("Frame")
    UtilCard.Size = UDim2.new(1, -4, 0, 76)
    UtilCard.LayoutOrder = 6
    UtilCard.BackgroundColor3 = AppConfig.NestedCardBg
    UtilCard.Parent = FarmScroll
    UIComponent.applyCard(UtilCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local UtTitle = Instance.new("TextLabel")
    UtTitle.Size = UDim2.new(1, -20, 0, 20)
    UtTitle.Position = UDim2.new(0, 14, 0, 8)
    UtTitle.BackgroundTransparency = 1
    UtTitle.Text = "Quick Teleport & Global ESP"
    UtTitle.TextColor3 = AppConfig.TextPrimary
    UtTitle.TextSize = AppConfig.TextHeader
    UtTitle.Font = Enum.Font.GothamBold
    UtTitle.TextXAlignment = Enum.TextXAlignment.Left
    UtTitle.Parent = UtilCard

    local GlobalESPToggleBtn = Instance.new("TextButton")
    GlobalESPToggleBtn.Size = UDim2.new(0.33, -10, 0, 30)
    GlobalESPToggleBtn.Position = UDim2.new(0, 10, 0, 36)
    GlobalESPToggleBtn.BackgroundColor3 = AppConfig.RecessedBg
    GlobalESPToggleBtn.Text = "👁️ ESP All: OFF"
    GlobalESPToggleBtn.TextColor3 = AppConfig.TextSecondary
    GlobalESPToggleBtn.TextSize = AppConfig.TextCaption
    GlobalESPToggleBtn.Font = Enum.Font.GothamBold
    GlobalESPToggleBtn.Parent = UtilCard
    UIComponent.styleButton(GlobalESPToggleBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local TPHomeBtn = Instance.new("TextButton")
    TPHomeBtn.Size = UDim2.new(0.33, -10, 0, 30)
    TPHomeBtn.Position = UDim2.new(0.33, 6, 0, 36)
    TPHomeBtn.BackgroundColor3 = AppConfig.RecessedBg
    TPHomeBtn.Text = "🏠 TP Home"
    TPHomeBtn.TextColor3 = AppConfig.TextPrimary
    TPHomeBtn.TextSize = AppConfig.TextCaption
    TPHomeBtn.Font = Enum.Font.GothamBold
    TPHomeBtn.Parent = UtilCard
    UIComponent.styleButton(TPHomeBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local AntiAFKToggleBtn = Instance.new("TextButton")
    AntiAFKToggleBtn.Size = UDim2.new(0.34, -10, 0, 30)
    AntiAFKToggleBtn.Position = UDim2.new(0.66, 6, 0, 36)
    AntiAFKToggleBtn.BackgroundColor3 = AppConfig.RecessedBg
    AntiAFKToggleBtn.Text = "🛡️ Anti-AFK: ON"
    AntiAFKToggleBtn.TextColor3 = AppConfig.AccentGreen
    AntiAFKToggleBtn.TextSize = AppConfig.TextCaption
    AntiAFKToggleBtn.Font = Enum.Font.GothamBold
    AntiAFKToggleBtn.Parent = UtilCard
    UIComponent.styleButton(AntiAFKToggleBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    GlobalESPToggleBtn.MouseButton1Click:Connect(function()
        StateStore.mainESPActive = not StateStore.mainESPActive
        if StateStore.mainESPActive then
            GlobalESPToggleBtn.Text = "👁️ ESP All: ON"
            GlobalESPToggleBtn.TextColor3 = AppConfig.AccentGreen
            updateStatus("Global ESP: ON", AppConfig.AccentGreen)
        else
            GlobalESPToggleBtn.Text = "👁️ ESP All: OFF"
            GlobalESPToggleBtn.TextColor3 = AppConfig.TextSecondary
            updateStatus("Global ESP: OFF", AppConfig.TextSecondary)
        end
        ESPComponent.updateAll()
    end)

    TPHomeBtn.MouseButton1Click:Connect(function()
        local ok = PlotComponent.teleportAndDeposit()
        if ok then updateStatus("At Home Plot (Egg Cleared)", AppConfig.AccentGreen)
        else updateStatus("Home Plot Not Found", AppConfig.AccentRed) end
    end)

    AntiAFKToggleBtn.MouseButton1Click:Connect(function()
        StateStore.antiAFKActive = not StateStore.antiAFKActive
        StabilityComponent.setupAntiAFK(StateStore.antiAFKActive)
        if StateStore.antiAFKActive then
            AntiAFKToggleBtn.Text = "🛡️ Anti-AFK: ON"
            AntiAFKToggleBtn.TextColor3 = AppConfig.AccentGreen
            updateStatus("Anti-AFK Active", AppConfig.AccentGreen)
        else
            AntiAFKToggleBtn.Text = "🛡️ Anti-AFK: OFF"
            AntiAFKToggleBtn.TextColor3 = AppConfig.TextMuted
            updateStatus("Anti-AFK Inactive", AppConfig.TextSecondary)
        end
    end)

    -- ══════════════════════════════════════════════════════════════
    -- [TAB 3] BACKPACK
    -- ══════════════════════════════════════════════════════════════
    local BackpackPanel = tabPanels["Backpack"]

    local BpToolbarCard = Instance.new("Frame")
    BpToolbarCard.Size = UDim2.new(1, 0, 0, 46)
    BpToolbarCard.BackgroundColor3 = AppConfig.NestedCardBg
    BpToolbarCard.Parent = BackpackPanel
    UIComponent.applyCard(BpToolbarCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local BackpackCountBadge = Instance.new("TextLabel")
    BackpackCountBadge.Size = UDim2.new(0, 120, 1, 0)
    BackpackCountBadge.Position = UDim2.new(0, 14, 0, 0)
    BackpackCountBadge.BackgroundTransparency = 1
    BackpackCountBadge.Text = "🎒 Items: (0)"
    BackpackCountBadge.TextColor3 = AppConfig.AccentBlue
    BackpackCountBadge.TextSize = AppConfig.TextHeader
    BackpackCountBadge.Font = Enum.Font.GothamBold
    BackpackCountBadge.TextXAlignment = Enum.TextXAlignment.Left
    BackpackCountBadge.Parent = BpToolbarCard

    local BpSearchBoxContainer = Instance.new("Frame")
    BpSearchBoxContainer.Size = UDim2.new(1, -230, 0, 28)
    BpSearchBoxContainer.Position = UDim2.new(0, 134, 0.5, -14)
    BpSearchBoxContainer.BackgroundColor3 = AppConfig.RecessedBg
    BpSearchBoxContainer.Parent = BpToolbarCard
    UIComponent.applyCard(BpSearchBoxContainer, AppConfig.RadiusMD, AppConfig.RecessedBg, AppConfig.BorderInner)

    local BackpackSearchBox = Instance.new("TextBox")
    BackpackSearchBox.Size = UDim2.new(1, -26, 1, 0)
    BackpackSearchBox.Position = UDim2.new(0, 10, 0, 0)
    BackpackSearchBox.BackgroundTransparency = 1
    BackpackSearchBox.PlaceholderText = "🔍 Search backpack..."
    BackpackSearchBox.PlaceholderColor3 = AppConfig.TextMuted
    BackpackSearchBox.Text = ""
    BackpackSearchBox.TextColor3 = AppConfig.TextPrimary
    BackpackSearchBox.TextSize = AppConfig.TextCaption
    BackpackSearchBox.Font = Enum.Font.GothamMedium
    BackpackSearchBox.TextXAlignment = Enum.TextXAlignment.Left
    BackpackSearchBox.ClearTextOnFocus = false
    BackpackSearchBox.Parent = BpSearchBoxContainer

    local BpClearSearchBtn = Instance.new("TextButton")
    BpClearSearchBtn.Size = UDim2.new(0, 22, 0, 22)
    BpClearSearchBtn.Position = UDim2.new(1, -24, 0.5, -11)
    BpClearSearchBtn.BackgroundTransparency = 1
    BpClearSearchBtn.Text = "✕"
    BpClearSearchBtn.TextColor3 = AppConfig.TextMuted
    BpClearSearchBtn.TextSize = 10
    BpClearSearchBtn.Font = Enum.Font.GothamBold
    BpClearSearchBtn.Visible = false
    BpClearSearchBtn.Parent = BpSearchBoxContainer

    local PrintBackpackBtn = Instance.new("TextButton")
    PrintBackpackBtn.Size = UDim2.new(0, 76, 0, 28)
    PrintBackpackBtn.Position = UDim2.new(1, -86, 0.5, -14)
    PrintBackpackBtn.BackgroundColor3 = AppConfig.RecessedBg
    PrintBackpackBtn.Text = "Dump Log"
    PrintBackpackBtn.TextColor3 = AppConfig.AccentBlue
    PrintBackpackBtn.TextSize = AppConfig.TextCaption
    PrintBackpackBtn.Font = Enum.Font.GothamBold
    PrintBackpackBtn.Parent = BpToolbarCard
    UIComponent.styleButton(PrintBackpackBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local BpListCard = Instance.new("Frame")
    BpListCard.Size = UDim2.new(1, 0, 1, -54)
    BpListCard.Position = UDim2.new(0, 0, 0, 54)
    BpListCard.BackgroundColor3 = AppConfig.NestedCardBg
    BpListCard.Parent = BackpackPanel
    UIComponent.applyCard(BpListCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local BackpackScroll = Instance.new("ScrollingFrame")
    BackpackScroll.Size = UDim2.new(1, -16, 1, -16)
    BackpackScroll.Position = UDim2.new(0, 8, 0, 8)
    BackpackScroll.BackgroundTransparency = 1
    BackpackScroll.BorderSizePixel = 0
    BackpackScroll.ScrollBarThickness = 3
    BackpackScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
    BackpackScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    BackpackScroll.Parent = BpListCard

    local BackpackLayout = Instance.new("UIListLayout")
    BackpackLayout.SortOrder = Enum.SortOrder.LayoutOrder
    BackpackLayout.Padding = UDim.new(0, 4)
    BackpackLayout.Parent = BackpackScroll

    BackpackLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        BackpackScroll.CanvasSize = UDim2.new(0, 0, 0, BackpackLayout.AbsoluteContentSize.Y + 6)
    end)

    updateBackpackUI = function()
        for _, child in ipairs(BackpackScroll:GetChildren()) do
            if child ~= BackpackLayout then child:Destroy() end
        end

        local allItems = Utils.getBackpackItems()
        local query = (StateStore.backpackSearchQuery or ""):lower():match("^%s*(.-)%s*$")
        local filteredItems = {}

        if query and #query > 0 then
            for _, it in ipairs(allItems) do
                if string.find(it.name:lower(), query, 1, true) then
                    table.insert(filteredItems, it)
                end
            end
        else
            filteredItems = allItems
        end

        BackpackCountBadge.Text = string.format("🎒 Items: (%d)", #allItems)

        if #filteredItems == 0 then
            local emptyLabel = Instance.new("TextLabel")
            emptyLabel.Size = UDim2.new(1, 0, 0, 40)
            emptyLabel.BackgroundTransparency = 1
            emptyLabel.Text = (#allItems == 0) and "Backpack is empty / ไม่มีไอเทม" or "No matching items"
            emptyLabel.TextColor3 = AppConfig.TextMuted
            emptyLabel.TextSize = AppConfig.TextBody
            emptyLabel.Font = Enum.Font.GothamMedium
            emptyLabel.Parent = BackpackScroll
            return
        end

        for _, item in ipairs(filteredItems) do
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -4, 0, 36)
            card.BackgroundColor3 = item.isEquipped and Color3.fromRGB(22, 34, 28) or AppConfig.RecessedBg
            card.Parent = BackpackScroll
            UIComponent.applyCard(card, AppConfig.RadiusMD, card.BackgroundColor3, item.isEquipped and AppConfig.AccentGreen or AppConfig.BorderInner)

            if item.textureId and #item.textureId > 0 then
                local icon = Instance.new("ImageLabel")
                icon.Size = UDim2.new(0, 22, 0, 22)
                icon.Position = UDim2.new(0, 8, 0.5, -11)
                icon.BackgroundTransparency = 1
                icon.Image = item.textureId
                icon.ScaleType = Enum.ScaleType.Fit
                icon.Parent = card
            else
                local iconFallback = Instance.new("TextLabel")
                iconFallback.Size = UDim2.new(0, 22, 0, 22)
                iconFallback.Position = UDim2.new(0, 8, 0.5, -11)
                iconFallback.BackgroundTransparency = 1
                iconFallback.Text = item.isEquipped and "⚔️" or "📦"
                iconFallback.TextSize = 12
                iconFallback.Font = Enum.Font.GothamBold
                iconFallback.Parent = card
            end

            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, -160, 1, 0)
            nameLabel.Position = UDim2.new(0, 36, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = item.name
            nameLabel.TextColor3 = item.isEquipped and AppConfig.AccentGreen or AppConfig.TextPrimary
            nameLabel.TextSize = AppConfig.TextBody
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            nameLabel.Parent = card

            local tagLabel = Instance.new("TextLabel")
            tagLabel.Size = UDim2.new(0, 56, 0, 20)
            tagLabel.Position = UDim2.new(1, -124, 0.5, -10)
            tagLabel.BackgroundColor3 = item.isEquipped and Color3.fromRGB(20, 48, 30) or AppConfig.NestedCardBg
            tagLabel.Text = item.isEquipped and "Equipped" or "In Bag"
            tagLabel.TextColor3 = item.isEquipped and AppConfig.AccentGreen or AppConfig.TextMuted
            tagLabel.TextSize = AppConfig.TextMicro
            tagLabel.Font = Enum.Font.GothamMedium
            tagLabel.Parent = card

            local tc = Instance.new("UICorner")
            tc.CornerRadius = UDim.new(0, 4)
            tc.Parent = tagLabel

            local actBtn = Instance.new("TextButton")
            actBtn.Size = UDim2.new(0, 60, 0, 24)
            actBtn.Position = UDim2.new(1, -64, 0.5, -12)
            local actBg = item.isEquipped and AppConfig.NestedCardBg or AppConfig.AccentGreen
            actBtn.BackgroundColor3 = actBg
            actBtn.Text = item.isEquipped and "Unequip" or "Equip"
            actBtn.TextColor3 = item.isEquipped and AppConfig.TextSecondary or Color3.fromRGB(10, 20, 15)
            actBtn.TextSize = AppConfig.TextCaption
            actBtn.Font = Enum.Font.GothamBold
            actBtn.Parent = card
            UIComponent.styleButton(actBtn, AppConfig.RadiusSM, actBg)

            actBtn.MouseButton1Click:Connect(function()
                if item.isEquipped then Utils.unequipTool(item.instance)
                else Utils.equipTool(item.instance) end
                task.wait(0.08)
                updateBackpackUI()
            end)
        end
    end

    BackpackSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local newQuery = BackpackSearchBox.Text:match("^%s*(.-)%s*$") or ""
        BpClearSearchBtn.Visible = (#newQuery > 0)
        if newQuery == StateStore.backpackSearchQuery then return end
        StateStore.backpackSearchQuery = newQuery
        updateBackpackUI()
    end)

    BpClearSearchBtn.MouseButton1Click:Connect(function()
        BackpackSearchBox.Text = ""
        StateStore.backpackSearchQuery = ""
        BpClearSearchBtn.Visible = false
        updateBackpackUI()
    end)

    PrintBackpackBtn.MouseButton1Click:Connect(function()
        Utils.printBackpack()
        updateStatus("Backpack dumped to console", AppConfig.AccentBlue)
    end)

    local backpackConnAdded, backpackConnRemoved
    local charConnAdded, charConnRemoved

    local function bindBackpackListeners()
        if backpackConnAdded then backpackConnAdded:Disconnect() end
        if backpackConnRemoved then backpackConnRemoved:Disconnect() end
        local bp = Utils.getBackpack()
        if bp then
            backpackConnAdded = StateStore.track(bp.ChildAdded:Connect(function()
                if currentActiveTab == "Backpack" then updateBackpackUI() end
            end))
            backpackConnRemoved = StateStore.track(bp.ChildRemoved:Connect(function()
                if currentActiveTab == "Backpack" then updateBackpackUI() end
            end))
        end
    end

    local function bindCharBackpackListeners(char)
        if charConnAdded then charConnAdded:Disconnect() end
        if charConnRemoved then charConnRemoved:Disconnect() end
        if char then
            charConnAdded = StateStore.track(char.ChildAdded:Connect(function(child)
                if child:IsA("Tool") and currentActiveTab == "Backpack" then updateBackpackUI() end
            end))
            charConnRemoved = StateStore.track(char.ChildRemoved:Connect(function(child)
                if child:IsA("Tool") and currentActiveTab == "Backpack" then updateBackpackUI() end
            end))
        end
        bindBackpackListeners()
    end

    bindCharBackpackListeners(Utils.getCharacter())
    StateStore.track(ServiceManager.LocalPlayer.CharacterAdded:Connect(bindCharBackpackListeners))

    -- ══════════════════════════════════════════════════════════════
    -- [TAB 4] HISTORY
    -- ══════════════════════════════════════════════════════════════
    local HistoryPanel = tabPanels["History"]

    local HistToolbarCard = Instance.new("Frame")
    HistToolbarCard.Size = UDim2.new(1, 0, 0, 46)
    HistToolbarCard.BackgroundColor3 = AppConfig.NestedCardBg
    HistToolbarCard.Parent = HistoryPanel
    UIComponent.applyCard(HistToolbarCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local HistTitle = Instance.new("TextLabel")
    HistTitle.Size = UDim2.new(1, -100, 1, 0)
    HistTitle.Position = UDim2.new(0, 14, 0, 0)
    HistTitle.BackgroundTransparency = 1
    HistTitle.Text = "📜  Egg Farm Collection Timeline"
    HistTitle.TextColor3 = AppConfig.AccentGold
    HistTitle.TextSize = AppConfig.TextHeader
    HistTitle.Font = Enum.Font.GothamBold
    HistTitle.TextXAlignment = Enum.TextXAlignment.Left
    HistTitle.Parent = HistToolbarCard

    local ClearHistoryBtn = Instance.new("TextButton")
    ClearHistoryBtn.Size = UDim2.new(0, 76, 0, 28)
    ClearHistoryBtn.Position = UDim2.new(1, -86, 0.5, -14)
    ClearHistoryBtn.BackgroundColor3 = AppConfig.RecessedBg
    ClearHistoryBtn.Text = "Clear All"
    ClearHistoryBtn.TextColor3 = AppConfig.AccentRed
    ClearHistoryBtn.TextSize = AppConfig.TextCaption
    ClearHistoryBtn.Font = Enum.Font.GothamBold
    ClearHistoryBtn.Parent = HistToolbarCard
    UIComponent.styleButton(ClearHistoryBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local HistListCard = Instance.new("Frame")
    HistListCard.Size = UDim2.new(1, 0, 1, -54)
    HistListCard.Position = UDim2.new(0, 0, 0, 54)
    HistListCard.BackgroundColor3 = AppConfig.NestedCardBg
    HistListCard.Parent = HistoryPanel
    UIComponent.applyCard(HistListCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local HistoryScroll = Instance.new("ScrollingFrame")
    HistoryScroll.Size = UDim2.new(1, -16, 1, -16)
    HistoryScroll.Position = UDim2.new(0, 8, 0, 8)
    HistoryScroll.BackgroundTransparency = 1
    HistoryScroll.BorderSizePixel = 0
    HistoryScroll.ScrollBarThickness = 3
    HistoryScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
    HistoryScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    HistoryScroll.Parent = HistListCard

    local HistoryLayout = Instance.new("UIListLayout")
    HistoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
    HistoryLayout.Padding = UDim.new(0, 4)
    HistoryLayout.Parent = HistoryScroll

    HistoryLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        HistoryScroll.CanvasSize = UDim2.new(0, 0, 0, HistoryLayout.AbsoluteContentSize.Y + 6)
    end)

    updateHistoryUI = function()
        for _, child in ipairs(HistoryScroll:GetChildren()) do
            if child ~= HistoryLayout then child:Destroy() end
        end

        if #StateStore.farmHistory == 0 then
            local emptyLabel = Instance.new("TextLabel")
            emptyLabel.Size = UDim2.new(1, 0, 0, 40)
            emptyLabel.BackgroundTransparency = 1
            emptyLabel.Text = "No farm history recorded yet\nยังไม่มีประวัติการเก็บไข่"
            emptyLabel.TextColor3 = AppConfig.TextMuted
            emptyLabel.TextSize = AppConfig.TextBody
            emptyLabel.Font = Enum.Font.GothamMedium
            emptyLabel.Parent = HistoryScroll
            return
        end

        for _, item in ipairs(StateStore.farmHistory) do
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -4, 0, 34)
            card.BackgroundColor3 = item.isRare and Color3.fromRGB(36, 30, 20) or AppConfig.RecessedBg
            card.Parent = HistoryScroll
            UIComponent.applyCard(card, AppConfig.RadiusMD, card.BackgroundColor3, item.isRare and AppConfig.AccentGold or AppConfig.BorderInner)

            local icon = Instance.new("ImageLabel")
            icon.Size = UDim2.new(0, 20, 0, 20)
            icon.Position = UDim2.new(0, 8, 0.5, -10)
            icon.BackgroundTransparency = 1
            icon.Image = Utils.getEggImage(item.name)
            icon.ScaleType = Enum.ScaleType.Fit
            icon.Parent = card

            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, -120, 1, 0)
            nameLabel.Position = UDim2.new(0, 34, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = item.name
            nameLabel.TextColor3 = item.isRare and AppConfig.AccentGold or AppConfig.TextPrimary
            nameLabel.TextSize = AppConfig.TextBody
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            nameLabel.Parent = card

            local timeLabel = Instance.new("TextLabel")
            timeLabel.Size = UDim2.new(0, 72, 1, 0)
            timeLabel.Position = UDim2.new(1, -80, 0, 0)
            timeLabel.BackgroundTransparency = 1
            timeLabel.Text = item.time
            timeLabel.TextColor3 = AppConfig.TextMuted
            timeLabel.TextSize = AppConfig.TextCaption
            timeLabel.Font = Enum.Font.Gotham
            timeLabel.TextXAlignment = Enum.TextXAlignment.Right
            timeLabel.Parent = card
        end
    end

    StateStore.onHistoryUpdated = updateHistoryUI

    ClearHistoryBtn.MouseButton1Click:Connect(function()
        table.clear(StateStore.farmHistory)
        updateHistoryUI()
        updateStatus("Farm history cleared", AppConfig.AccentRed)
    end)

    -- ══════════════════════════════════════════════════════════════
    -- [TAB 5] SETTINGS
    -- ══════════════════════════════════════════════════════════════
    local SettingsPanel = tabPanels["Settings"]

    local SettingsScroll = Instance.new("ScrollingFrame")
    SettingsScroll.Size = UDim2.new(1, 0, 1, 0)
    SettingsScroll.BackgroundTransparency = 1
    SettingsScroll.BorderSizePixel = 0
    SettingsScroll.ScrollBarThickness = 3
    SettingsScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
    SettingsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    SettingsScroll.Parent = SettingsPanel

    local SettingsLayout = Instance.new("UIListLayout")
    SettingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    SettingsLayout.Padding = UDim.new(0, 8)
    SettingsLayout.Parent = SettingsScroll

    SettingsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        SettingsScroll.CanvasSize = UDim2.new(0, 0, 0, SettingsLayout.AbsoluteContentSize.Y + 8)
    end)

    local DevSetCard = Instance.new("Frame")
    DevSetCard.Size = UDim2.new(1, -4, 0, 76)
    DevSetCard.LayoutOrder = 1
    DevSetCard.BackgroundColor3 = AppConfig.NestedCardBg
    DevSetCard.Parent = SettingsScroll
    UIComponent.applyCard(DevSetCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local DstTitle = Instance.new("TextLabel")
    DstTitle.Size = UDim2.new(1, -20, 0, 20)
    DstTitle.Position = UDim2.new(0, 14, 0, 8)
    DstTitle.BackgroundTransparency = 1
    DstTitle.Text = "Display & Screen Geometry Mode"
    DstTitle.TextColor3 = AppConfig.TextPrimary
    DstTitle.TextSize = AppConfig.TextHeader
    DstTitle.Font = Enum.Font.GothamBold
    DstTitle.TextXAlignment = Enum.TextXAlignment.Left
    DstTitle.Parent = DevSetCard

    local SetPCBtn = Instance.new("TextButton")
    SetPCBtn.Size = UDim2.new(0.5, -18, 0, 30)
    SetPCBtn.Position = UDim2.new(0, 10, 0, 36)
    SetPCBtn.BackgroundColor3 = AppConfig.RecessedBg
    SetPCBtn.Text = "💻 PC Layout (760x480)"
    SetPCBtn.TextColor3 = AppConfig.TextPrimary
    SetPCBtn.TextSize = AppConfig.TextCaption
    SetPCBtn.Font = Enum.Font.GothamBold
    SetPCBtn.Parent = DevSetCard
    UIComponent.styleButton(SetPCBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local SetMobileBtn = Instance.new("TextButton")
    SetMobileBtn.Size = UDim2.new(0.5, -18, 0, 30)
    SetMobileBtn.Position = UDim2.new(0.5, 8, 0, 36)
    SetMobileBtn.BackgroundColor3 = AppConfig.RecessedBg
    SetMobileBtn.Text = "📱 Mobile Layout (620x400)"
    SetMobileBtn.TextColor3 = AppConfig.TextPrimary
    SetMobileBtn.TextSize = AppConfig.TextCaption
    SetMobileBtn.Font = Enum.Font.GothamBold
    SetMobileBtn.Parent = DevSetCard
    UIComponent.styleButton(SetMobileBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    local KeybindCard = Instance.new("Frame")
    KeybindCard.Size = UDim2.new(1, -4, 0, 76)
    KeybindCard.LayoutOrder = 2
    KeybindCard.BackgroundColor3 = AppConfig.NestedCardBg
    KeybindCard.Parent = SettingsScroll
    UIComponent.applyCard(KeybindCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local KbTitle = Instance.new("TextLabel")
    KbTitle.Size = UDim2.new(1, -20, 0, 20)
    KbTitle.Position = UDim2.new(0, 14, 0, 8)
    KbTitle.BackgroundTransparency = 1
    KbTitle.Text = "Teleport Home & Deposit Keybind"
    KbTitle.TextColor3 = AppConfig.TextPrimary
    KbTitle.TextSize = AppConfig.TextHeader
    KbTitle.Font = Enum.Font.GothamBold
    KbTitle.TextXAlignment = Enum.TextXAlignment.Left
    KbTitle.Parent = KeybindCard

    local KeybindBtn = Instance.new("TextButton")
    KeybindBtn.Size = UDim2.new(1, -20, 0, 30)
    KeybindBtn.Position = UDim2.new(0, 10, 0, 36)
    KeybindBtn.BackgroundColor3 = AppConfig.RecessedBg
    KeybindBtn.Text = "⌨️  Current Keybind: [" .. StateStore.tpKeybind.Name .. "] (Click to remap)"
    KeybindBtn.TextColor3 = AppConfig.AccentGold
    KeybindBtn.TextSize = AppConfig.TextCaption
    KeybindBtn.Font = Enum.Font.GothamBold
    KeybindBtn.Parent = KeybindCard
    UIComponent.styleButton(KeybindBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    KeybindBtn.MouseButton1Click:Connect(function()
        StateStore.listeningForKey = true
        KeybindBtn.Text = "⌨️  Press any keyboard key now..."
        KeybindBtn.TextColor3 = AppConfig.AccentGreen
    end)

    local TimeCard = Instance.new("Frame")
    TimeCard.Size = UDim2.new(1, -4, 0, 170)
    TimeCard.LayoutOrder = 3
    TimeCard.BackgroundColor3 = AppConfig.NestedCardBg
    TimeCard.Parent = SettingsScroll
    UIComponent.applyCard(TimeCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.AccentBlue, 0.55)

    local TimeCardTitle = Instance.new("TextLabel")
    TimeCardTitle.Size = UDim2.new(1, -20, 0, 22)
    TimeCardTitle.Position = UDim2.new(0, 14, 0, 8)
    TimeCardTitle.BackgroundTransparency = 1
    TimeCardTitle.Text = "⏱️  Time & Session Monitor"
    TimeCardTitle.TextColor3 = AppConfig.AccentBlue
    TimeCardTitle.TextSize = AppConfig.TextHeader
    TimeCardTitle.Font = Enum.Font.GothamBold
    TimeCardTitle.TextXAlignment = Enum.TextXAlignment.Left
    TimeCardTitle.Parent = TimeCard

    local TimeInnerCard = Instance.new("Frame")
    TimeInnerCard.Size = UDim2.new(1, -20, 0, 122)
    TimeInnerCard.Position = UDim2.new(0, 10, 0, 38)
    TimeInnerCard.BackgroundColor3 = AppConfig.RecessedBg
    TimeInnerCard.Parent = TimeCard
    UIComponent.applyCard(TimeInnerCard, AppConfig.RadiusLG, AppConfig.RecessedBg, AppConfig.BorderInner)

    local function makeTimeRow(parent, yPos, icon, title, valueColor)
        local rowFrame = Instance.new("Frame")
        rowFrame.Size = UDim2.new(1, 0, 0, 28)
        rowFrame.Position = UDim2.new(0, 0, 0, yPos)
        rowFrame.BackgroundTransparency = 1
        rowFrame.Parent = parent

        local iconLbl = Instance.new("TextLabel")
        iconLbl.Size = UDim2.new(0, 24, 1, 0)
        iconLbl.Position = UDim2.new(0, 10, 0, 0)
        iconLbl.BackgroundTransparency = 1
        iconLbl.Text = icon
        iconLbl.TextSize = 12
        iconLbl.Font = Enum.Font.GothamBold
        iconLbl.Parent = rowFrame

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(0.45, 0, 1, 0)
        titleLbl.Position = UDim2.new(0, 34, 0, 0)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Text = title
        titleLbl.TextColor3 = AppConfig.TextSecondary
        titleLbl.TextSize = AppConfig.TextCaption
        titleLbl.Font = Enum.Font.GothamMedium
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.Parent = rowFrame

        local valueLbl = Instance.new("TextLabel")
        valueLbl.Size = UDim2.new(0.5, -10, 1, 0)
        valueLbl.Position = UDim2.new(0.5, 0, 0, 0)
        valueLbl.BackgroundTransparency = 1
        valueLbl.Text = "--"
        valueLbl.TextColor3 = valueColor or AppConfig.TextPrimary
        valueLbl.TextSize = AppConfig.TextBody
        valueLbl.Font = Enum.Font.GothamBold
        valueLbl.TextXAlignment = Enum.TextXAlignment.Right
        valueLbl.Parent = rowFrame

        return valueLbl
    end

    local TmCurrentTimeValue = makeTimeRow(TimeInnerCard, 6,  "🕐", "Current Time",   AppConfig.AccentBlue)
    local TmSessionTimeValue = makeTimeRow(TimeInnerCard, 34, "⏳", "Session Uptime",  AppConfig.AccentGreen)
    local TmStartTimeValue   = makeTimeRow(TimeInnerCard, 62, "📅", "Session Started", AppConfig.TextSecondary)
    local TmEggsPerMinValue  = makeTimeRow(TimeInnerCard, 90, "🥚", "Eggs / Minute",  AppConfig.AccentGold)

    TmStartTimeValue.Text = os.date("%H:%M:%S", StateStore.sessionStartTime)

    local function refreshTimeLabels()
        local now = os.time()
        local elapsed = now - StateStore.sessionStartTime
        local h = math.floor(elapsed / 3600)
        local m = math.floor((elapsed % 3600) / 60)
        local s = elapsed % 60
        TmCurrentTimeValue.Text = os.date("%H:%M:%S")
        TmSessionTimeValue.Text = string.format("%02d:%02d:%02d", h, m, s)
        local epm = (elapsed > 0) and string.format("%.1f", StateStore.totalEggsCollected / (elapsed / 60)) or "0.0"
        TmEggsPerMinValue.Text = epm .. " eggs/min"
        if ClockLabel and ClockLabel.Parent then
            ClockLabel.Text = os.date("%H:%M:%S")
        end
    end
    StateStore.onTimeUpdated = refreshTimeLabels
    refreshTimeLabels()

    local PlotCard = Instance.new("Frame")
    PlotCard.Size = UDim2.new(1, -4, 0, 76)
    PlotCard.LayoutOrder = 4
    PlotCard.BackgroundColor3 = AppConfig.NestedCardBg
    PlotCard.Parent = SettingsScroll
    UIComponent.applyCard(PlotCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

    local PltTitle = Instance.new("TextLabel")
    PltTitle.Size = UDim2.new(1, -20, 0, 20)
    PltTitle.Position = UDim2.new(0, 14, 0, 8)
    PltTitle.BackgroundTransparency = 1
    PltTitle.Text = "Home Plot Detection Diagnostic"
    PltTitle.TextColor3 = AppConfig.TextPrimary
    PltTitle.TextSize = AppConfig.TextHeader
    PltTitle.Font = Enum.Font.GothamBold
    PltTitle.TextXAlignment = Enum.TextXAlignment.Left
    PltTitle.Parent = PlotCard

    local CheckPlotBtn = Instance.new("TextButton")
    CheckPlotBtn.Size = UDim2.new(1, -20, 0, 30)
    CheckPlotBtn.Position = UDim2.new(0, 10, 0, 36)
    CheckPlotBtn.BackgroundColor3 = AppConfig.RecessedBg
    CheckPlotBtn.Text = "🔍 Check Home Plot Link"
    CheckPlotBtn.TextColor3 = AppConfig.TextPrimary
    CheckPlotBtn.TextSize = AppConfig.TextCaption
    CheckPlotBtn.Font = Enum.Font.GothamBold
    CheckPlotBtn.Parent = PlotCard
    UIComponent.styleButton(CheckPlotBtn, AppConfig.RadiusMD, AppConfig.RecessedBg)

    CheckPlotBtn.MouseButton1Click:Connect(function()
        local plot = PlotComponent.findHomePlot()
        if plot then
            updateStatus("Plot Linked: " .. plot.Name, AppConfig.AccentGreen)
            CheckPlotBtn.Text = "✅ Home Plot Linked: " .. plot.Name
        else
            updateStatus("No Home Plot Detected", AppConfig.AccentRed)
            CheckPlotBtn.Text = "❌ No Home Plot Linked (Ensure plot claimed)"
        end
    end)

    -- ══════════════════════════════════════════════════════════════
    -- RARE EGG ALERTS
    -- ══════════════════════════════════════════════════════════════
    local function showRareAlert(egg)
        if not StateStore.shouldAlert(egg.Name) then return end

        local alerts = AlertStack:GetChildren()
        local count = 0
        for _, child in ipairs(alerts) do
            if child:IsA("Frame") then
                count += 1
                if count >= AppConfig.MaxAlerts then child:Destroy() end
            end
        end

        local card = Instance.new("Frame")
        card.Size = UDim2.new(1, 0, 0, 70)
        card.BackgroundColor3 = AppConfig.OuterCardBg
        card.Position = UDim2.new(1, 60, 0, 0)
        card.Parent = AlertStack
        UIComponent.applyCard(card, AppConfig.Radius2XL, AppConfig.OuterCardBg, AppConfig.AccentGold, 0.2)

        local innerCard = Instance.new("Frame")
        innerCard.Size = UDim2.new(1, -12, 1, -12)
        innerCard.Position = UDim2.new(0, 6, 0, 6)
        innerCard.BackgroundColor3 = AppConfig.NestedCardBg
        innerCard.Parent = card
        UIComponent.applyCard(innerCard, AppConfig.RadiusXL, AppConfig.NestedCardBg, AppConfig.BorderInner)

        local eggIcon = Instance.new("ImageLabel")
        eggIcon.Size = UDim2.new(0, 40, 0, 40)
        eggIcon.Position = UDim2.new(0, 10, 0.5, -20)
        eggIcon.BackgroundTransparency = 1
        eggIcon.Image = Utils.getEggImage(egg.Name)
        eggIcon.ScaleType = Enum.ScaleType.Fit
        eggIcon.Parent = innerCard

        local badge = Instance.new("TextLabel")
        badge.Size = UDim2.new(1, -120, 0, 14)
        badge.Position = UDim2.new(0, 56, 0, 8)
        badge.BackgroundTransparency = 1
        badge.Text = "✨ RARE EGG SPAWNED!"
        badge.TextColor3 = AppConfig.AccentGold
        badge.TextSize = AppConfig.TextCaption
        badge.Font = Enum.Font.GothamBold
        badge.TextXAlignment = Enum.TextXAlignment.Left
        badge.Parent = innerCard

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -120, 0, 18)
        nameLabel.Position = UDim2.new(0, 56, 0, 22)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = egg.Name
        nameLabel.TextColor3 = AppConfig.TextPrimary
        nameLabel.TextSize = AppConfig.TextTitle
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = innerCard

        local distLabel = Instance.new("TextLabel")
        distLabel.Size = UDim2.new(1, -120, 0, 14)
        distLabel.Position = UDim2.new(0, 56, 0, 40)
        distLabel.BackgroundTransparency = 1
        local d = Utils.getDistanceToTarget(egg)
        distLabel.Text = (d ~= math.huge) and string.format("📍 %dst away", math.floor(d + 0.5)) or "📍 Unknown"
        distLabel.TextColor3 = AppConfig.TextSecondary
        distLabel.TextSize = AppConfig.TextCaption
        distLabel.Font = Enum.Font.GothamMedium
        distLabel.TextXAlignment = Enum.TextXAlignment.Left
        distLabel.Parent = innerCard

        local tpBtn = Instance.new("TextButton")
        tpBtn.Size = UDim2.new(0, 56, 0, 28)
        tpBtn.Position = UDim2.new(1, -62, 0.5, -14)
        tpBtn.BackgroundColor3 = AppConfig.AccentGold
        tpBtn.Text = "⚡ TP"
        tpBtn.TextColor3 = Color3.fromRGB(15, 15, 20)
        tpBtn.TextSize = AppConfig.TextBody
        tpBtn.Font = Enum.Font.GothamBold
        tpBtn.Parent = innerCard
        UIComponent.styleButton(tpBtn, AppConfig.RadiusMD, AppConfig.AccentGold)

        tpBtn.MouseButton1Click:Connect(function()
            if egg and egg.Parent then
                MovementComponent.teleportTo(egg)
                updateStatus("Teleported to " .. egg.Name, AppConfig.AccentGold)
            end
            pcall(function() card:Destroy() end)
        end)

        Utils.tween(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.25, Enum.EasingStyle.Back)

        task.delay(AppConfig.AlertDuration, function()
            if card and card.Parent then
                Utils.tween(card, { BackgroundTransparency = 1 }, 0.3)
                task.wait(0.32)
                pcall(function() card:Destroy() end)
            end
        end)
    end

    -- ══════════════════════════════════════════════════════════════
    -- DRAGGABLE
    -- ══════════════════════════════════════════════════════════════
    local dragging = false
    local dragStart = nil
    local startPos = nil

    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)

    StateStore.track(ServiceManager.UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    StateStore.track(ServiceManager.UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            local cam = ServiceManager.Workspace.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
            local fw = MainFrame.AbsoluteSize.X
            local fh = MainFrame.AbsoluteSize.Y
            local tx = math.clamp(startPos.X.Offset + delta.X, 0, math.max(0, vp.X - fw))
            local ty = math.clamp(startPos.Y.Offset + delta.Y, 0, math.max(0, vp.Y - fh))
            MainFrame.Position = UDim2.new(0, tx, 0, ty)
        end
    end))

    -- Keybind handler
    StateStore.track(ServiceManager.UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if StateStore.listeningForKey then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                StateStore.tpKeybind = input.KeyCode
                StateStore.listeningForKey = false
                KeybindBtn.Text = "⌨️  Current Keybind: [" .. StateStore.tpKeybind.Name .. "] (Click to remap)"
                KeybindBtn.TextColor3 = AppConfig.AccentGold
                updateStatus("Keybind Set: " .. StateStore.tpKeybind.Name, AppConfig.AccentGreen)
            end
            return
        end
        if gameProcessed then return end

        -- Escape: minimize
        if input.KeyCode == Enum.KeyCode.Escape then
            if not StateStore.isMinimized then toggleMinimize() end
            return
        end

        -- Comma / Period: cycle tabs
        if input.KeyCode == Enum.KeyCode.Period then
            local ids = {}
            for _, t in ipairs(Tabs) do table.insert(ids, t.id) end
            local idx = table.find(ids, currentActiveTab) or 1
            switchTab(ids[(idx % #ids) + 1])
            return
        end
        if input.KeyCode == Enum.KeyCode.Comma then
            local ids = {}
            for _, t in ipairs(Tabs) do table.insert(ids, t.id) end
            local idx = table.find(ids, currentActiveTab) or 1
            switchTab(ids[((idx - 2) % #ids) + 1])
            return
        end

        -- Teleport home
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == StateStore.tpKeybind then
            PlotComponent.teleportAndDeposit()
        end
    end))

    -- ══════════════════════════════════════════════════════════════
    -- DEVICE MODE
    -- ══════════════════════════════════════════════════════════════
    local function applyMode(mode)
        StateStore.windowMode = mode
        StateStore.isMobileMode = (mode == "Mobile")
        local w, h = currentSize()
        MainFrame.Size = UDim2.new(0, w, 0, h)
        MainFrame.Position = UDim2.new(0.5, -w / 2, 0.5, -h / 2)
        if DeviceFrame and DeviceFrame.Parent then DeviceFrame:Destroy() end
        MainFrame.Visible = true
        Sidebar.Visible = not StateStore.isMinimized
        ContentArea.Visible = not StateStore.isMinimized
        updateMovementModeUI()
        populateList()
        updateLiveEggsSummary()
    end

    PCBtn.MouseButton1Click:Connect(function() applyMode("PC") end)
    MobileBtn.MouseButton1Click:Connect(function() applyMode("Mobile") end)
    SetPCBtn.MouseButton1Click:Connect(function() applyMode("PC") end)
    SetMobileBtn.MouseButton1Click:Connect(function() applyMode("Mobile") end)
    FootPC.MouseButton1Click:Connect(function() applyMode("PC") end)
    FootMobile.MouseButton1Click:Connect(function() applyMode("Mobile") end)

    if ServiceManager.UserInputService.TouchEnabled and not ServiceManager.UserInputService.KeyboardEnabled then
        task.defer(function() applyMode("Mobile") end)
    end

    -- ══════════════════════════════════════════════════════════════
    -- TIME HEARTBEAT
    -- ══════════════════════════════════════════════════════════════
    local timeTick = 0
    StateStore.track(ServiceManager.RunService.Heartbeat:Connect(function(dt)
        if not (ScreenGui and ScreenGui.Parent) then return end
        timeTick = timeTick + dt
        if timeTick >= 1 then
            timeTick = timeTick - 1
            if ClockLabel and ClockLabel.Parent then
                ClockLabel.Text = os.date("%H:%M:%S")
            end
            if StateStore.onTimeUpdated then
                StateStore.onTimeUpdated()
            end
        end
    end))

    -- Initial populate
    task.defer(function()
        populateList()
        updateLiveEggsSummary()
        updateBackpackUI()
        updateHistoryUI()
    end)

    return {
        populateList = populateList,
        updateLiveEggsSummary = updateLiveEggsSummary,
        updateBackpackUI = updateBackpackUI,
        showRareAlert = showRareAlert,
        ScreenGui = ScreenGui,
    }
end

--==================================================
-- [13] COMPONENT: AppBootstrap
--==================================================
local function cleanup()
    for _, conn in ipairs(StateStore._connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(StateStore._connections)

    if StateStore.antiAFKConnection then
        pcall(function() StateStore.antiAFKConnection:Disconnect() end)
        StateStore.antiAFKConnection = nil
    end
    if StateStore.noclipConnection then
        pcall(function() StateStore.noclipConnection:Disconnect() end)
        StateStore.noclipConnection = nil
    end

    FarmComponent.stopAutoFarm()
    FarmComponent.stopAutoBestEgg()
    RebirthComponent.stopAutoRebirth()
    MovementComponent.stop()

    if StateStore.screenGui then
        pcall(function() StateStore.screenGui:Destroy() end)
        StateStore.screenGui = nil
    end

    StateStore.reset()
end

local function startApplication()
    cleanup()

    local UI = UIComponent.mount()

    StateStore.track(ServiceManager.LocalPlayer.CharacterAdded:Connect(function()
        MovementComponent.stop()
        task.wait(1.0)
        Utils.resetVelocity(Utils.getRootPart())
    end))

    task.spawn(function()
        while UI and UI.ScreenGui and UI.ScreenGui.Parent do
            for egg, data in pairs(StateStore.eggData) do
                if egg and egg.Parent then
                    if data.NameBillboard and data.NameBillboard.Enabled then
                        ESPComponent.updateBillboard(egg)
                    end
                else
                    ESPComponent.removeEgg(egg)
                end
            end
            task.wait(0.3)
        end
    end)

    local function bindEggFolder(folder)
        local debounce = false
        local function queueUpdate()
            if debounce then return end
            debounce = true
            task.delay(0.25, function()
                debounce = false
                UI.populateList()
                UI.updateLiveEggsSummary()
            end)
        end

        StateStore.track(folder.ChildAdded:Connect(function(egg)
            StateStore.autoFarmProcessed[egg] = nil
            StateStore.eggCooldowns[egg] = nil
            ESPComponent.updateEgg(egg)
            ESPComponent.bindEggLifecycle(egg)
            queueUpdate()
            if Utils.isRareEgg(egg.Name) then UI.showRareAlert(egg) end
        end))

        StateStore.track(folder.ChildRemoved:Connect(function(egg)
            ESPComponent.removeEgg(egg)
            queueUpdate()
        end))

        for _, egg in ipairs(folder:GetChildren()) do
            ESPComponent.updateEgg(egg)
            ESPComponent.bindEggLifecycle(egg)
        end
    end

    if ServiceManager.RenderedEggsFolder then
        bindEggFolder(ServiceManager.RenderedEggsFolder)
    else
        task.spawn(function()
            local folder = ServiceManager.Workspace:WaitForChild("RenderedEggs", 60)
            if folder then
                ServiceManager.RenderedEggsFolder = folder
                bindEggFolder(folder)
                UI.populateList()
                UI.updateLiveEggsSummary()
            end
        end)
    end

    StabilityComponent.setupAntiAFK(true)
    StabilityComponent.setupAutoRejoin()

    -- Merge into existing namespace
    local existing = getgenv().EggsESP or {}
    existing.Version = AppConfig.Version
    existing.Config = AppConfig
    existing.State = StateStore
    existing.Components = {
        Farm = FarmComponent,
        Rebirth = RebirthComponent,
        ESP = ESPComponent,
        Movement = MovementComponent,
        Plot = PlotComponent,
    }
    existing.API = {
        FireRebirth = RebirthComponent.fireRebirth,
        GetMissingRebirthEggs = RebirthComponent.scanMissingEggs,
        StartAutoRebirth = RebirthComponent.startAutoRebirth,
        StopAutoRebirth = RebirthComponent.stopAutoRebirth,
        Cleanup = cleanup,
    }
    getgenv().EggsESP = existing

    print("[Eggs ESP Pro v" .. AppConfig.Version .. "] Initialized successfully.")
end

-- Run App
startApplication()
