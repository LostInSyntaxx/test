--==================================================
-- Rayvinz Tools — Diagnostic + UI + Claim + Potion
--==================================================

print("════════════════════════════════════════")
print("[Rayvinz] Script starting...")
print("════════════════════════════════════════")

-- ═══════════════════════════════════════════════
-- [STEP 1] DIAGNOSTIC
-- ═══════════════════════════════════════════════
local RS = game:GetService("ReplicatedStorage")

local remote      = RS:FindFirstChild("Remote")
local updateLog   = remote and remote:FindFirstChild("UpdateLog_Server")
local claimEvent  = updateLog and updateLog:FindFirstChild("TryClaimUPDRewardRE")
local potionSrv   = remote and remote:FindFirstChild("Potion_Server")
local potionEvent = potionSrv and potionSrv:FindFirstChild("TryUsePotionRE")

print("[DIAG] RS.Remote                 :", remote and "OK" or "nil")
print("[DIAG] -- UpdateLog_Server       :", updateLog and "OK" or "nil")
print("[DIAG]    -- TryClaimUPDRewardRE :", claimEvent and ("OK " .. claimEvent.ClassName) or "nil")
print("[DIAG] -- Potion_Server          :", potionSrv and "OK" or "nil")
print("[DIAG]    -- TryUsePotionRE      :", potionEvent and ("OK " .. potionEvent.ClassName) or "nil")

if updateLog then
    print("[DIAG] UpdateLog_Server children:")
    for _, c in ipairs(updateLog:GetChildren()) do
        print("       -", c.Name, "|", c.ClassName)
    end
end
if potionSrv then
    print("[DIAG] Potion_Server children:")
    for _, c in ipairs(potionSrv:GetChildren()) do
        print("       -", c.Name, "|", c.ClassName)
    end
end

-- ═══════════════════════════════════════════════
-- [STEP 2] DEFINITIONS
-- ═══════════════════════════════════════════════
getgenv().rayvinz = false

local targetRewards = {"4"}
local potionS = {"DamagePotion", "LuckPotion", "TrainPotion"}

local claimCount = 0
local claimError = ""
local claimRunning = false

-- ═══════════════════════════════════════════════
-- CLAIM LOOP
-- ═══════════════════════════════════════════════
local function startClaimLoop()
    if claimRunning then return end
    if not claimEvent then
        claimError = "Remote not found"
        print("[CLAIM] Cannot start: TryClaimUPDRewardRE missing")
        return
    end
    claimRunning = true
    claimError = ""

    task.spawn(function()
        print("[CLAIM] Loop started")
        while getgenv().rayvinz do
            local ok, err = pcall(function()
                for _, rewardNumber in ipairs(targetRewards) do
                    local randomPrefix = ""
                    local length = math.random(5, 15)
                    for i = 1, length do
                        if math.random(1, 2) == 1 then
                            randomPrefix = randomPrefix .. " "
                        else
                            randomPrefix = randomPrefix .. "\t"
                        end
                    end
                    claimEvent:FireServer(randomPrefix .. rewardNumber)
                end
            end)
            if ok then
                claimCount = claimCount + 1
            else
                claimError = tostring(err)
                print("[CLAIM] Error:", err)
            end
            task.wait(0.1)
        end
        print("[CLAIM] Loop stopped")
        claimRunning = false
    end)
end

-- ═══════════════════════════════════════════════
-- POTION
-- ═══════════════════════════════════════════════
local function usePotion()
    if not potionEvent then
        print("[POTION] Remote not found")
        return false
    end
    print("[POTION] -inf")
    for _, potion in ipairs(potionS) do
        local ok, err = pcall(function()
            potionEvent:FireServer(potion, -1/0)
        end)
        if not ok then print("[POTION] err", potion, err) end
    end
    task.wait(1)
    print("[POTION] +inf")
    for _, potion in ipairs(potionS) do
        local ok, err = pcall(function()
            potionEvent:FireServer(potion, 1/0)
        end)
        if not ok then print("[POTION] err", potion, err) end
    end
    print("[POTION] Done")
    return true
end

-- ═══════════════════════════════════════════════
-- [STEP 3] UI
-- ═══════════════════════════════════════════════
local Services = {
    UIS     = game:GetService("UserInputService"),
    Tween   = game:GetService("TweenService"),
    CoreGui = game:GetService("CoreGui"),
}
local PARENT = (gethui and select(2, pcall(gethui))) or Services.CoreGui

local C = {
    Bg=Color3.fromHex("#171717"), Card=Color3.fromHex("#1F1F1F"),
    Nested=Color3.fromHex("#242424"), Border=Color3.fromHex("#2C2C2C"),
    Border2=Color3.fromHex("#333333"),
    Grn=Color3.fromRGB(0,230,118), Blu=Color3.fromRGB(0,150,255),
    Red=Color3.fromRGB(255,61,87), Gld=Color3.fromRGB(255,215,0),
    T1=Color3.fromRGB(255,255,255), T2=Color3.fromRGB(163,163,163),
    T3=Color3.fromRGB(110,110,110),
}
local R = { R2=16, RX=12, RL=8, RM=6 }
local T = { Title=14, Body=11, Caption=9, Micro=8 }

local function tween(o, p, d)
    if not o or not o.Parent then return end
    Services.Tween:Create(o, TweenInfo.new(d or 0.15, Enum.EasingStyle.Quart), p):Play()
end

local function card(f, r, bg, stroke)
    f.BackgroundColor3 = bg or C.Card
    f.BackgroundTransparency = 0.02
    f.BorderSizePixel = 0
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or R.R2)
    c.Parent = f
    local s = Instance.new("UIStroke")
    s.Color = stroke or C.Border
    s.Transparency = 0.35
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f
end

local function styleBtn(b, r, normal)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or R.RL)
    c.Parent = b
    local s = Instance.new("UIStroke")
    s.Color = C.Border2
    s.Transparency = 0.55
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = b
    b.AutoButtonColor = false
    b:SetAttribute("DefaultBg", normal or b.BackgroundColor3)
    b.MouseEnter:Connect(function()
        tween(b, { BackgroundColor3 = Color3.fromRGB(44,44,44) }, 0.12)
    end)
    b.MouseLeave:Connect(function()
        tween(b, { BackgroundColor3 = b:GetAttribute("DefaultBg") or C.Nested }, 0.12)
    end)
end

local old = PARENT:FindFirstChild("RayvinzUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "RayvinzUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PARENT

-- Window
local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 340, 0, 280)
Main.Position = UDim2.new(0, 20, 0.5, -140)
Main.BackgroundColor3 = C.Bg
Main.BackgroundTransparency = 0.02
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = gui
card(Main, R.R2, C.Bg, C.Border)

-- Top bar
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 36)
TopBar.BackgroundTransparency = 1
TopBar.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -60, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Rayvinz Tools"
Title.TextColor3 = C.T1
Title.TextSize = T.Title
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.Position = UDim2.new(1, -30, 0.5, -12)
CloseBtn.BackgroundColor3 = C.Nested
CloseBtn.Text = "X"
CloseBtn.TextColor3 = C.T2
CloseBtn.TextSize = 11
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = TopBar
local cbc = Instance.new("UICorner")
cbc.CornerRadius = UDim.new(0, R.RM)
cbc.Parent = CloseBtn
CloseBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- Diagnostic card
local DiagCard = Instance.new("Frame")
DiagCard.Size = UDim2.new(1, -20, 0, 60)
DiagCard.Position = UDim2.new(0, 10, 0, 42)
DiagCard.BackgroundColor3 = C.Nested
DiagCard.Parent = Main
card(DiagCard, R.RX, C.Nested, C.Border2)

local DiagTitle = Instance.new("TextLabel")
DiagTitle.Size = UDim2.new(1, -20, 0, 16)
DiagTitle.Position = UDim2.new(0, 12, 0, 6)
DiagTitle.BackgroundTransparency = 1
DiagTitle.Text = "Remote Diagnostic"
DiagTitle.TextColor3 = C.T1
DiagTitle.TextSize = T.Body
DiagTitle.Font = Enum.Font.GothamBold
DiagTitle.TextXAlignment = Enum.TextXAlignment.Left
DiagTitle.Parent = DiagCard

local function diagLine(parent, y, label, ok)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -20, 0, 12)
    l.Position = UDim2.new(0, 12, 0, y)
    l.BackgroundTransparency = 1
    l.Text = (ok and "[OK] " or "[X] ") .. label
    l.TextColor3 = ok and C.Grn or C.Red
    l.TextSize = T.Micro
    l.Font = Enum.Font.GothamMedium
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
end

diagLine(DiagCard, 24, "TryClaimUPDRewardRE", claimEvent ~= nil)
diagLine(DiagCard, 38, "TryUsePotionRE",      potionEvent ~= nil)

-- Claim toggle card
local ToggleCard = Instance.new("Frame")
ToggleCard.Size = UDim2.new(1, -20, 0, 52)
ToggleCard.Position = UDim2.new(0, 10, 0, 108)
ToggleCard.BackgroundColor3 = C.Nested
ToggleCard.Parent = Main
card(ToggleCard, R.RX, C.Nested, C.Border2)

local Tt = Instance.new("TextLabel")
Tt.Size = UDim2.new(1, -80, 0, 20)
Tt.Position = UDim2.new(0, 14, 0, 8)
Tt.BackgroundTransparency = 1
Tt.Text = "Auto Claim Reward"
Tt.TextColor3 = C.T1
Tt.TextSize = T.Body
Tt.Font = Enum.Font.GothamBold
Tt.TextXAlignment = Enum.TextXAlignment.Left
Tt.Parent = ToggleCard

local Td = Instance.new("TextLabel")
Td.Size = UDim2.new(1, -80, 0, 16)
Td.Position = UDim2.new(0, 14, 0, 28)
Td.BackgroundTransparency = 1
Td.Text = "Fire TryClaimUPDRewardRE in loop"
Td.TextColor3 = C.T3
Td.TextSize = T.Micro
Td.Font = Enum.Font.GothamMedium
Td.TextXAlignment = Enum.TextXAlignment.Left
Td.Parent = ToggleCard

local Track = Instance.new("TextButton")
Track.Size = UDim2.new(0, 44, 0, 24)
Track.Position = UDim2.new(1, -58, 0.5, -12)
Track.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
Track.Text = ""
Track.AutoButtonColor = false
Track.Parent = ToggleCard
local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(1, 0)
tc.Parent = Track

local Knob = Instance.new("Frame")
Knob.Size = UDim2.new(0, 18, 0, 18)
Knob.Position = UDim2.new(0, 3, 0.5, -9)
Knob.BackgroundColor3 = Color3.new(1, 1, 1)
Knob.Parent = Track
local kc = Instance.new("UICorner")
kc.CornerRadius = UDim.new(1, 0)
kc.Parent = Knob

Track.MouseButton1Click:Connect(function()
    getgenv().rayvinz = not getgenv().rayvinz
    local on = getgenv().rayvinz
    tween(Track, { BackgroundColor3 = on and C.Grn or Color3.fromRGB(40,40,40) }, 0.15)
    tween(Knob, {
        Position = on and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    }, 0.15)
    if on then
        startClaimLoop()
    end
end)

-- Potion card
local PotionCard = Instance.new("Frame")
PotionCard.Size = UDim2.new(1, -20, 0, 76)
PotionCard.Position = UDim2.new(0, 10, 0, 168)
PotionCard.BackgroundColor3 = C.Nested
PotionCard.Parent = Main
card(PotionCard, R.RX, C.Nested, C.Border2)

local Pt = Instance.new("TextLabel")
Pt.Size = UDim2.new(1, -20, 0, 20)
Pt.Position = UDim2.new(0, 14, 0, 8)
Pt.BackgroundTransparency = 1
Pt.Text = "Use Potion"
Pt.TextColor3 = C.T1
Pt.TextSize = T.Body
Pt.Font = Enum.Font.GothamBold
Pt.TextXAlignment = Enum.TextXAlignment.Left
Pt.Parent = PotionCard

local Pd = Instance.new("TextLabel")
Pd.Size = UDim2.new(1, -20, 0, 14)
Pd.Position = UDim2.new(0, 14, 0, 26)
Pd.BackgroundTransparency = 1
Pd.Text = "Damage / Luck / Train"
Pd.TextColor3 = C.T3
Pd.TextSize = T.Micro
Pd.Font = Enum.Font.GothamMedium
Pd.TextXAlignment = Enum.TextXAlignment.Left
Pd.Parent = PotionCard

local PotionBtn = Instance.new("TextButton")
PotionBtn.Size = UDim2.new(1, -20, 0, 28)
PotionBtn.Position = UDim2.new(0, 10, 0, 42)
PotionBtn.BackgroundColor3 = C.Blu
PotionBtn.Text = "USE POTION"
PotionBtn.TextColor3 = Color3.new(1, 1, 1)
PotionBtn.TextSize = T.Body
PotionBtn.Font = Enum.Font.GothamBold
PotionBtn.Parent = PotionCard
styleBtn(PotionBtn, R.RM, C.Blu)

local potionBusy = false
PotionBtn.MouseButton1Click:Connect(function()
    if potionBusy then return end
    potionBusy = true
    PotionBtn.Text = "Using..."
    PotionBtn.BackgroundColor3 = C.Gld
    PotionBtn:SetAttribute("DefaultBg", C.Gld)
    task.spawn(function()
        local ok = usePotion()
        if not ok then
            PotionBtn.Text = "Remote not found"
            PotionBtn.BackgroundColor3 = C.Red
            PotionBtn:SetAttribute("DefaultBg", C.Red)
            task.wait(2)
        else
            PotionBtn.Text = "Done"
            PotionBtn.BackgroundColor3 = C.Grn
            PotionBtn:SetAttribute("DefaultBg", C.Grn)
            task.wait(1)
        end
        PotionBtn.Text = "USE POTION"
        PotionBtn.BackgroundColor3 = C.Blu
        PotionBtn:SetAttribute("DefaultBg", C.Blu)
        potionBusy = false
    end)
end)

-- Status card
local StatusCard = Instance.new("Frame")
StatusCard.Size = UDim2.new(1, -20, 0, 26)
StatusCard.Position = UDim2.new(0, 10, 0, 248)
StatusCard.BackgroundColor3 = C.Nested
StatusCard.Parent = Main
card(StatusCard, R.RX, C.Nested, C.Border2)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 1, 0)
StatusLabel.Position = UDim2.new(0, 10, 0, 0)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Fired: 0 | Idle"
StatusLabel.TextColor3 = C.T2
StatusLabel.TextSize = T.Caption
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
StatusLabel.Parent = StatusCard

task.spawn(function()
    while gui.Parent do
        local txt = "Fired: " .. tostring(claimCount)
        if getgenv().rayvinz then
            txt = txt .. " | Running"
        else
            txt = txt .. " | Idle"
        end
        if claimError ~= "" then
            txt = txt .. " | ERR: " .. claimError:sub(1, 40)
        end
        StatusLabel.Text = txt
        task.wait(0.5)
    end
end)

-- Draggable
local dragging, dragStart, startPos = false, nil, nil
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
    end
end)
Services.UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
Services.UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

print("════════════════════════════════════════")
print("[Rayvinz] Ready")
print("   Claim remote :", claimEvent ~= nil and "OK" or "MISSING")
print("   Potion remote:", potionEvent ~= nil and "OK" or "MISSING")
print("════════════════════════════════════════")
