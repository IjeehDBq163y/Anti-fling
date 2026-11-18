--[[
	============================================================
	 ANTI-FLING / ANTI-VOID / ANTI-TOOLKILL / ANTI-RING
	 LocalScript > StarterPlayer > StarterPlayerScripts
	============================================================
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local LocalPlayer       = Players.LocalPlayer

-- CONFIG --------------------------------------------------------
local CONFIG = {
	VoidY            = -120,   -- below this Y you're in the void
	SafeY            = 25,     -- above this Y counts as a safe anchor
	MaxDownSpeed     = 170,    -- max downward studs/sec
	MaxSideSpeed     = 220,    -- max horizontal studs/sec
	MaxUpSpeed       = 220,    -- max upward studs/sec
	MaxFrameMove     = 85,     -- max studs moved in a single frame
	KeepNetworkOwner = true,   -- stop others from shoving your rig
	BlockRagdoll     = true,   -- disable Humanoid Physics state
	ToolScanInterval = 0.5,

	-- Ring / black hole parts
	RingStrongNames = { "blackhole", "black hole", "black_hole", "black-hole", "vortex" },
	RingWeakNames   = { "ring", "magnet", "pull", "hole" },
	RingPowerAttrs  = { "PullPower", "PullStrength", "PullForce", "PullRadius", "VortexPower", "RingPower", "BlackHolePower", "Pull", "Vortex", "IsBlackHole", "IsRing" },
	RingNumAttrs    = { "Power", "PullPower", "PullStrength", "PullForce", "Strength", "VortexPower", "RingPower", "BlackHolePower", "Magnitude" },
	RingFlagAttrs   = { "Enabled", "Active", "PullEnabled", "CanPull", "IsActive", "Working", "Pulling" },
	RingScanInterval = 1.0,    -- how often the map is rescanned for new parts
	RingMaxSize     = 60,      -- "weak" named parts larger than this are ignored
	RingFallSpeed   = 25,      -- downward speed allowed while a ring is pulling
	IgnoreThroughWalls = true, -- a ring behind a wall does nothing to you

	-- GUI sizes
	PanelWidth       = 190,
	PanelHeight      = 124,
	TitleHeight      = 26,
	ToggleHeight     = 24,
	LabelHeight      = 15,
	TitleTextSize    = 12,
	ToggleTextSize   = 14,
	LabelTextSize    = 11,
}

-- STATE --------------------------------------------------------
local State = {
	Enabled = true,   -- single master switch for every feature
}

local lastSafeCF     = nil
local lastSafePos    = nil
local lastStatus     = "Active"
local lastStatusTime = os.clock()
local guiVisible     = true
local ringCount      = 0      -- threats currently affecting you
local ringsBlocked   = 0      -- distinct threats blocked so far

-- HELPERS ------------------------------------------------------
local function getCharacter() return LocalPlayer.Character end

local function getHumanoid()
	local char = getCharacter()
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function getRig()
	local char = getCharacter()
	if not char then return nil, nil end
	return char:FindFirstChildOfClass("Humanoid"),
	       char:FindFirstChild("HumanoidRootPart")
end

local function stopMotion(root)
	if not root then return end
	root.AssemblyLinearVelocity  = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function setStatus(text)
	lastStatus = text
	lastStatusTime = os.clock()
end

local function findSpawnCF()
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
	if spawn then return spawn.CFrame * CFrame.new(0, 3, 0) end
	return CFrame.new(0, 10, 0)
end

local function protectionOn()
	return State.Enabled
end

-- RING / BLACK HOLE DETECTION ----------------------------------
local threatParts = {}   -- BasePart -> "strong" | "weak"

local function hasPullEffect(part)
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("BodyVelocity") or d:IsA("BodyForce")
		or d:IsA("VectorForce") or d:IsA("BodyAngularVelocity") then
			return true
		end
	end
	for _, a in ipairs(CONFIG.RingNumAttrs) do
		local v = part:GetAttribute(a)
		if type(v) == "number" and v > 0 then return true end
	end
	return false
end

local function classify(obj)
	if not obj:IsA("BasePart") then return nil end

	local n = string.lower(obj.Name)

	for _, p in ipairs(CONFIG.RingStrongNames) do
		if string.find(n, p, 1, true) then return "strong" end
	end

	for _, a in ipairs(CONFIG.RingPowerAttrs) do
		local v = obj:GetAttribute(a)
		if type(v) == "boolean" and v then return "strong" end
		if type(v) == "number" and v > 0 then return "strong" end
		if type(v) == "string" and v ~= "" and v ~= "false" then return "strong" end
	end

	for _, p in ipairs(CONFIG.RingWeakNames) do
		if string.find(n, p, 1, true) then
			local size = math.max(obj.Size.X, math.max(obj.Size.Y, obj.Size.Z))
			if size <= CONFIG.RingMaxSize or hasPullEffect(obj) then
				return "weak"
			end
		end
	end

	return nil
end

local function registerThreat(obj)
	local kind = classify(obj)
	if kind then threatParts[obj] = kind end
end

local function scanThreats()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then registerThreat(obj) end
	end
end

workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") then registerThreat(obj) end
end)

workspace.DescendantRemoving:Connect(function(obj)
	threatParts[obj] = nil
end)

-- Locally defuse the part's own pull values
local function neutralizeThreat(part)
	for _, a in ipairs(CONFIG.RingNumAttrs) do
		local v = part:GetAttribute(a)
		if type(v) == "number" and v ~= 0 then
			pcall(function() part:SetAttribute(a, 0) end)
		end
	end
	for _, a in ipairs(CONFIG.RingFlagAttrs) do
		local v = part:GetAttribute(a)
		if type(v) == "boolean" and v then
			pcall(function() part:SetAttribute(a, false) end)
		end
	end
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("BodyVelocity") then
			pcall(function() d.Velocity = Vector3.zero end)
		elseif d:IsA("BodyForce") then
			pcall(function() d.Force = Vector3.zero end)
		elseif d:IsA("VectorForce") then
			pcall(function() d.Force = Vector3.zero end)
		elseif d:IsA("BodyAngularVelocity") then
			pcall(function() d.AngularVelocity = Vector3.zero end)
		elseif d:IsA("AlignPosition") then
			pcall(function() d.MaxForce = 0 end)
			pcall(function() d.MaxVelocity = 0 end)
		end
	end
end

local function threatRadius(part)
	for _, a in ipairs({"Radius", "Range", "PullRadius", "PullRange", "Size"}) do
		local v = part:GetAttribute(a)
		if type(v) == "number" and v > 0 then return v end
	end
	local s = part.Size
	return math.max(s.X, math.max(s.Y, s.Z)) * 1.5
end

local function wallBetween(from, to)
	local char = getCharacter()
	local filter = {}
	if char then table.insert(filter, char) end
	for p in pairs(threatParts) do
		if p and p.Parent then table.insert(filter, p) end
	end
	if #filter == 0 then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true

	local result = workspace:Raycast(from, to - from, params)
	return result ~= nil
end

-- GUI ----------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AntiFlingGUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(CONFIG.PanelWidth, CONFIG.PanelHeight)
panel.Position = UDim2.fromOffset(20, 90)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(70, 70, 90)
panelStroke.Thickness = 1
panelStroke.Transparency = 0.4
panelStroke.Parent = panel

-- TITLE BAR (also the drag handle) -----------------------------
local title = Instance.new("TextButton")
title.Name = "DragHandle"
title.Size = UDim2.new(1, 0, 0, CONFIG.TitleHeight)
title.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
title.BorderSizePixel = 0
title.AutoButtonColor = false
title.Text = ""
title.Parent = panel

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 8)
titleCorner.Parent = title

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.Gotham
titleLabel.TextSize = CONFIG.TitleTextSize
titleLabel.TextColor3 = Color3.fromRGB(240, 240, 250)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Anti fling"
titleLabel.Parent = title

local titlePad = Instance.new("UIPadding")
titlePad.PaddingLeft = UDim.new(0, 8)
titlePad.PaddingRight = UDim.new(0, 4)
titlePad.Parent = titleLabel

-- HIDE BUTTON ---------------------------------------------------
local hideBtn = Instance.new("TextButton")
hideBtn.Size = UDim2.fromOffset(18, 17)
hideBtn.Position = UDim2.new(1, -23, 0, 4)
hideBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 78)
hideBtn.BorderSizePixel = 0
hideBtn.Font = Enum.Font.Gotham
hideBtn.TextSize = 11
hideBtn.TextColor3 = Color3.fromRGB(220, 220, 235)
hideBtn.Text = "-"
hideBtn.Parent = title

Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 4)

-- RESTORE TAB ---------------------------------------------------
local restoreTab = Instance.new("TextButton")
restoreTab.Name = "Restore"
restoreTab.Size = UDim2.fromOffset(48, 22)
restoreTab.Position = UDim2.fromOffset(12, 12)
restoreTab.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
restoreTab.BorderSizePixel = 0
restoreTab.Font = Enum.Font.Gotham
restoreTab.TextSize = 11
restoreTab.TextColor3 = Color3.fromRGB(240, 240, 250)
restoreTab.Text = "AF"
restoreTab.Visible = false
restoreTab.Parent = gui

Instance.new("UICorner", restoreTab).CornerRadius = UDim.new(0, 6)

-- BODY ----------------------------------------------------------
local body = Instance.new("Frame")
body.Size = UDim2.new(1, -12, 1, -(CONFIG.TitleHeight + 8))
body.Position = UDim2.fromOffset(6, CONFIG.TitleHeight + 4)
body.BackgroundTransparency = 1
body.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.VerticalAlignment = Enum.VerticalAlignment.Top
layout.Parent = body

local function makeButton(text, order, height, textSize, bgColor)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, height)
	b.LayoutOrder = order
	b.BackgroundColor3 = bgColor or Color3.fromRGB(48, 48, 62)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.Gotham
	b.TextSize = textSize
	b.TextColor3 = Color3.fromRGB(235, 235, 245)
	b.Text = text
	b.Parent = body
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
	p.Parent = b
	return b
end

local function makeLabel(text, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, CONFIG.LabelHeight)
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = CONFIG.LabelTextSize
	l.TextColor3 = Color3.fromRGB(185, 185, 200)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = body
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
	p.Parent = l
	return l
end

-- SINGLE COMBINED TOGGLE ----------------------------------------
-- The label shows the ACTION that clicking will perform:
-- protection active -> button reads "OFF" (click to turn it off)
-- protection inactive -> button reads "ON" (click to turn it on)
local toggleBtn = makeButton("Anti fling: OFF", 1, CONFIG.ToggleHeight, CONFIG.ToggleTextSize)

local function refreshToggle()
	local actionIsOn = (not State.Enabled)
	toggleBtn.Text = "Anti fling: " .. (actionIsOn and "ON" or "OFF")
	toggleBtn.TextColor3 = actionIsOn and Color3.fromRGB(120, 255, 155)
	                          or Color3.fromRGB(255, 130, 130)
	toggleBtn.BackgroundColor3 = actionIsOn and Color3.fromRGB(40, 62, 48)
	                                or Color3.fromRGB(62, 42, 42)
end

local function setEnabled(enabled)
	State.Enabled = enabled
	refreshToggle()
	setStatus("Protection: " .. (enabled and "ON" or "OFF"))
end

toggleBtn.MouseButton1Click:Connect(function()
	setEnabled(not State.Enabled)
end)

local statusLabel = makeLabel("Status: Active", 2)
local speedLabel  = makeLabel("Speed: 0", 3)
local ringLabel   = makeLabel("Rings: 0", 4)

-- DRAG LOGIC ----------------------------------------------------
-- Hold the title bar and drag; the panel follows the cursor
-- anywhere on screen and stays fully on-screen.
local dragging = false
local dragOffset = Vector2.new()

title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
	or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragOffset = Vector2.new(
			input.Position.X - panel.AbsolutePosition.X,
			input.Position.Y - panel.AbsolutePosition.Y
		)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
	or input.UserInputType == Enum.UserInputType.Touch then
		local cam = workspace.CurrentCamera
		if not cam then return end
		local view = cam.ViewportSize
		local maxX = math.max(0, view.X - panel.AbsoluteSize.X)
		local maxY = math.max(0, view.Y - panel.AbsoluteSize.Y)
		local x = math.clamp(input.Position.X - dragOffset.X, 0, maxX)
		local y = math.clamp(input.Position.Y - dragOffset.Y, 0, maxY)
		panel.Position = UDim2.fromOffset(x, y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
	or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

-- SHOW / HIDE ----------------------------------------------------
local function setGuiVisible(visible)
	guiVisible = visible
	panel.Visible = visible
	restoreTab.Visible = not visible
end

hideBtn.MouseButton1Click:Connect(function()
	setGuiVisible(false)
end)

restoreTab.MouseButton1Click:Connect(function()
	setGuiVisible(true)
end)

-- HUD REFRESH ---------------------------------------------------
local function refreshHUD()
	statusLabel.Text = "Status: " .. lastStatus
	statusLabel.TextColor3 = (os.clock() - lastStatusTime < 2)
		and Color3.fromRGB(255, 210, 90)
	or  Color3.fromRGB(185, 185, 200)

	local _, root = getRig()
	local speed = root and math.floor(root.AssemblyLinearVelocity.Magnitude) or 0
	speedLabel.Text = string.format("Speed: %d studs/s", speed)

	ringLabel.Text = string.format("Rings: %d near / %d blocked", ringCount, ringsBlocked)
	ringLabel.TextColor3 = ringCount > 0
		and Color3.fromRGB(255, 210, 90)
		or  Color3.fromRGB(185, 185, 200)
end

RunService.RenderStepped:Connect(refreshHUD)
refreshToggle()

-- TOOL / MOVER GUARD ---------------------------------------------
local function scanTools()
	local hum = getHumanoid()
	local char = getCharacter()
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	local containers = { backpack, char }

	for _, container in ipairs(containers) do
		if container then
			for _, tool in ipairs(container:GetChildren()) do
				if tool:IsA("Tool") then
					for _, attrName in ipairs(CONFIG.SuspiciousAttrs) do
						local value = tool:GetAttribute(attrName)
						if type(value) == "number" and math.abs(value) > CONFIG.SuspiciousMax then
							tool:SetAttribute(attrName, 0)
							setStatus("Tool blocked: " .. tool.Name)
							if tool.Parent == char and hum then
								pcall(function() hum:UnequipTool(tool) end)
							end
						end
					end
				end
			end
		end
	end
end

local function scanMovers()
	local char = getCharacter()
	if not char then return end
	for _, obj in ipairs(char:GetDescendants()) do
		if obj:IsA("BodyVelocity") or obj:IsA("BodyForce") or obj:IsA("BodyAngularVelocity") then
			local magnitude = 0
			if obj:IsA("BodyVelocity") then magnitude = obj.Velocity.Magnitude end
			if obj:IsA("BodyForce") then magnitude = obj.Force.Magnitude end
			if obj:IsA("BodyAngularVelocity") then magnitude = obj.AngularVelocity.Magnitude end
			if magnitude > CONFIG.MaxSideSpeed then
				obj:Destroy()
				setStatus("Rogue mover removed")
			end
		end
	end
end

task.spawn(function()
	while LocalPlayer.Parent do
		task.wait(CONFIG.ToolScanInterval)
		if protectionOn() then
			scanTools()
			scanMovers()
		end
	end
end)

task.spawn(function()
	while LocalPlayer.Parent do
		task.wait(CONFIG.RingScanInterval)
		if protectionOn() then scanThreats() end
	end
end)

scanThreats()

-- CHARACTER SETUP -----------------------------------------------
local function onCharacter(char)
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not root then return end

	lastSafeCF  = nil
	lastSafePos = nil
	setStatus("Protection: " .. (State.Enabled and "ON" or "OFF"))

	if CONFIG.BlockRagdoll then
		pcall(function()
			hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
		end)
	end
end

LocalPlayer.CharacterAdded:Connect(onCharacter)
if LocalPlayer.Character then task.defer(onCharacter, LocalPlayer.Character) end

-- RING / BLACK HOLE COUNTER --------------------------------------
local function counterRingPull(hum, root)
	if not protectionOn() then
		ringCount = 0
		return
	end

	local pos = root.Position
	local vel = root.AssemblyLinearVelocity
	local active = 0

	for part, kind in pairs(threatParts) do
		if part and part.Parent and part:IsA("BasePart") then
			local radius = threatRadius(part)
			local toPart = part.Position - pos
			local dist = toPart.Magnitude

			if dist < radius and dist > 0.001 then
				local blockedByWall = false
				if CONFIG.IgnoreThroughWalls then
					blockedByWall = wallBetween(pos, part.Position)
				end

				if not blockedByWall then
					active += 1

					if kind == "strong" or hasPullEffect(part) then
						neutralizeThreat(part)
					end
				end
			end
		end
	end

	ringCount = active

	if active == 0 then return end

	-- Drive our own movement so the pull cannot drag us
	local intended = hum.MoveDirection * hum.WalkSpeed
	local newVel

	if hum:GetState() == Enum.HumanoidStateType.Jumping and vel.Y > 0 then
		newVel = Vector3.new(intended.X, vel.Y, intended.Z)
	else
		newVel = Vector3.new(intended.X, -CONFIG.RingFallSpeed, intended.Z)
	end

	root.AssemblyLinearVelocity = newVel
	ringsBlocked += 1
	setStatus("Ring pull blocked")
end

-- MAIN PROTECTION LOOP -------------------------------------------
RunService.Heartbeat:Connect(function()
	if not protectionOn() then return end

	local hum, root = getRig()
	if not hum or not root then return end

	if hum.Health <= 0 then
		lastSafeCF, lastSafePos = nil, nil
		return
	end

	if CONFIG.KeepNetworkOwner then
		pcall(function()
			if root:GetNetworkOwner() ~= LocalPlayer then
				root:SetNetworkOwner(LocalPlayer)
			end
		end)
	end

	local pos = root.Position
	local vel = root.AssemblyLinearVelocity
	local inVehicle = (hum.SeatPart ~= nil)

	-- 1) VELOCITY CLAMP (anti-fling) ------------------------------
	if not inVehicle then
		local horizontal = Vector3.new(vel.X, 0, vel.Z)
		local vertical  = vel.Y
		local clamped = false

		if horizontal.Magnitude > CONFIG.MaxSideSpeed then
			horizontal = horizontal.Unit * CONFIG.MaxSideSpeed
			clamped = true
		end
		if vertical < -CONFIG.MaxDownSpeed then
			vertical = -CONFIG.MaxDownSpeed
			clamped = true
		elseif vertical > CONFIG.MaxUpSpeed then
			vertical = CONFIG.MaxUpSpeed
			clamped = true
		end

		if clamped then
			root.AssemblyLinearVelocity = Vector3.new(horizontal.X, vertical, horizontal.Z)
			setStatus("Velocity clamped")
		end
	end

	-- 2) TELEPORT-FLING BLOCK (anti-fling) ------------------------
	if lastSafePos and not inVehicle then
		local moved = (pos - lastSafePos).Magnitude
		if moved > CONFIG.MaxFrameMove then
			root.CFrame = lastSafeCF
			stopMotion(root)
			pos = root.Position
			setStatus("Teleport blocked")
		end
	end

	-- 3) VOID RESCUE (anti-void) ----------------------------------
	if pos.Y < CONFIG.VoidY then
		local target = lastSafeCF
		if not target or target.Y < CONFIG.VoidY then
			target = findSpawnCF()
		end
		root.CFrame = target
		stopMotion(root)
		pos = root.Position
		setStatus("VOID RESCUE")
	end

	-- 4) RING / BLACK HOLE COUNTER --------------------------------
	if not inVehicle then
		counterRingPull(hum, root)
	end

	-- 5) SAVE SAFE ANCHOR -----------------------------------------
	local grounded = (hum.FloorMaterial ~= Enum.Material.Air)
	if grounded or pos.Y > CONFIG.SafeY then
		lastSafeCF  = root.CFrame
		lastSafePos = root.Position
	end
end)

-- KEYBOARD SHORTCUTS ---------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.KeyCode == Enum.KeyCode.F6 then
		setGuiVisible(not guiVisible)
	elseif input.KeyCode == Enum.KeyCode.F7 then
		setEnabled(not State.Enabled)
	end
end)

print("[Anti fling] loaded. F6 = hide/show GUI, F7 = toggle protection.")
Make it look like this but don't add a keybinds just if you click a button to on the protection also on no need a F7 and F6 keybinds
