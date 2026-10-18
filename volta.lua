--=====================================================================
--  VENICE  |  LOCK-ON + ESP + STARFIELD MENU   (v9 - projection fixed)
--  LocalScript -> StarterPlayer > StarterPlayerScripts
--  Controls:  Right Mouse = lock on   |   RightShift = toggle menu
--=====================================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local GuiService       = game:GetService("GuiService")

local LP        = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")
local Camera    = Workspace.CurrentCamera

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = Workspace.CurrentCamera
end)

--=====================================================================
-- SETTINGS
--=====================================================================
local Settings = {
	-- ESP
	ESPEnabled        = true,
	Boxes             = true,
	BoxColor          = Color3.fromRGB(255, 255, 255),
	BoxThickness      = 1,
	BoxFill           = true,
	BoxFillTrans      = 0.88,
	Names             = true,
	Distance          = true,
	Health            = true,
	Snaplines         = true,
	SnaplineColor     = Color3.fromRGB(255, 255, 255),
	SnaplineFrom      = "Bottom",
	Highlight         = true,
	HighlightColor    = Color3.fromRGB(255, 255, 255),
	HighlightTrans    = 0.70,
	HighlightOccluded = false,
	TeamCheck         = true,
	ShowLocal         = true,
	MaxDistance       = 1000,
	CandidateColor    = Color3.fromRGB(255, 215, 120),
	EspOffsetX        = 0,
	EspOffsetY        = 0,

	-- LOCK-ON
	LockEnabled       = true,
	LockKey           = Enum.UserInputType.MouseButton2,
	ToggleMode        = false,
	Orbit             = true,
	LockMouse         = true,
	Sensitivity       = 0.25,
	Zoom              = true,
	MinDistance       = 4,
	MaxLockDistance   = 80,
	LockDistance      = 14,
	FOVZoom           = true,
	BaseFOV           = 70,
	MinFOV            = 30,
	AimPart           = "Head",
	VisibleOnly       = false,
	AutoReacquire     = true,
	LockColor         = Color3.fromRGB(255, 70, 90),
	Crosshair         = true,

	-- LOCK FOV
	LockFOV           = 260,
	LockFOVUnit       = "Pixels",
	LockFOVPreset     = "Custom",
	StrictFOV         = true,
	FOVTargetMode     = "Any part",
	FOVDropOut        = false,
	Fallback3D        = true,

	-- FOV CIRCLE
	FOVCircle         = true,
	FOVCircleColor    = Color3.fromRGB(255, 255, 255),
	FOVCircleThick    = 1,
	FOVCircleTrans    = 0.45,
	FOVCircleFill     = true,
	FOVCircleMode     = "Cursor",
	FOVCircleShow     = "Always",

	-- VISUALS
	Stars             = true,
	StarSpeed         = 1,
	ScreenTint        = 0.55,
	PanelBg           = 0.06,
	Debug             = true,
}

local ACCENT = Color3.fromRGB(255, 255, 255)
local lastError = ""

--=====================================================================
-- HELPERS
--=====================================================================
local function new(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	if parent then inst.Parent = parent end
	return inst
end

local function clamp(v, a, b)
	if v < a then return a elseif v > b then return b end
	return v
end

-- --- screen space -----------------------------------------------------
-- Everything below works in SCREEN space: origin at the top-left of the
-- monitor, matching both IgnoreGuiInset GUIs and GetMouseLocation.
-- WorldToScreenPoint is the API that already returns that space, so no
-- manual topbar-inset arithmetic is needed (and none can be wrong).
local insetY = 0

local function refreshInset()
	local p = Camera.CFrame.Position + Camera.CFrame.LookVector * 100
	local s = Camera:WorldToScreenPoint(p)
	local v = Camera:WorldToViewportPoint(p)
	insetY = s.Y - v.Y

	if insetY == 0 then
		local ok, tl = pcall(function()
			return GuiService:GetGuiInset()
		end)
		if ok and typeof(tl) == "Vector2" then insetY = tl.Y end
	end
end
refreshInset()

local function screenPoint(worldPos)
	local sp = Camera:WorldToScreenPoint(worldPos)
	if sp.Z <= 0 then return nil end
	return Vector2.new(sp.X, sp.Y)
end

-- exact screen position of the point the camera is looking at
local function screenCenter()
	local p = Camera.CFrame.Position + Camera.CFrame.LookVector * 100
	local sp = Camera:WorldToScreenPoint(p)
	return Vector2.new(sp.X, sp.Y)
end

local function screenRect(char)
    local cf, size = char:GetBoundingBox()
    local half = size / 2

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local found = false

    for _, x in ipairs({-half.X, half.X}) do
        for _, y in ipairs({-half.Y, half.Y}) do
            for _, z in ipairs({-half.Z, half.Z}) do
                local worldPos = cf:PointToWorldSpace(
                    Vector3.new(x, y, z)
                )

                local screenPos, onScreen =
                    Camera:WorldToViewportPoint(worldPos)

                if screenPos.Z > 0 then
                    minX = math.min(minX, screenPos.X)
                    minY = math.min(minY, screenPos.Y)
                    maxX = math.max(maxX, screenPos.X)
                    maxY = math.max(maxY, screenPos.Y)
                    found = true
                end
            end
        end
    end

    if not found then
        return nil
    end

    return minX + Settings.EspOffsetX,
           minY + Settings.EspOffsetY,
           maxX + Settings.EspOffsetX,
           maxY + Settings.EspOffsetY
end

local function distToRect(px, py, l, t, r, b)
	local dx = math.max(l - px, 0, px - r)
	local dy = math.max(t - py, 0, py - b)
	return math.sqrt(dx * dx + dy * dy)
end

local function lockFovPixels()
	local vpH = Camera.ViewportSize.Y
	if vpH <= 0 then return Settings.LockFOV end

	if Settings.LockFOVUnit == "Degrees" then
		local camFov = math.rad(clamp(Camera.FieldOfView, 1, 179))
		local want   = math.rad(clamp(Settings.LockFOV, 1, 179))
		return (vpH / 2) * math.tan(want / 2) / math.tan(camFov / 2)
	end
	return Settings.LockFOV
end

local function pixelsToDegrees(px)
	local vpH = Camera.ViewportSize.Y
	if vpH <= 0 then return Settings.LockFOV end
	local camFov = math.rad(clamp(Camera.FieldOfView, 1, 179))
	return math.deg(2 * math.atan(math.tan(camFov / 2) * (px / (vpH / 2))))
end

--=====================================================================
-- GUIS
--=====================================================================
local StarGui = new("ScreenGui", {
	Name = "VeniceStars", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = Settings.ScreenTint, BorderSizePixel = 0,
}, StarGui)

local StarLayer = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	BorderSizePixel = 0, ClipsDescendants = true,
}, StarGui)

local EspGui = new("ScreenGui", {
	Name = "VeniceESP", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 2, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local MenuGui = new("ScreenGui", {
	Name = "VeniceMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
	DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

--=====================================================================
-- STARFIELD
--=====================================================================
local starSystems = {}

local function createStarField(container, count, zIndex)
	local stars = {}
	for i = 1, count do
		local star = new("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = math.random(10, 70) / 100,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(math.random(1, 2), math.random(1, 2)),
			ZIndex = zIndex or 2,
		}, container)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, star)
		stars[i] = {
			frame = star,
			x = math.random() * 400, y = math.random() * 400,
			speed = math.random(10, 50),
			sway = math.random(3, 16),
			phase = math.random() * math.pi * 2,
			init = false,
		}
	end
	table.insert(starSystems, stars)
	return stars
end

createStarField(StarLayer, 170, 2)

RunService.Heartbeat:Connect(function(dt)
	if not Settings.Stars then
		StarLayer.Visible = false
		return
	end
	StarLayer.Visible = true
	local t = os.clock()
	for _, stars in ipairs(starSystems) do
		for _, s in ipairs(stars) do
			local size = s.frame.Parent.AbsoluteSize
			if not s.init and size.X > 0 then
				s.x = math.random() * size.X
				s.y = math.random() * size.Y
				s.init = true
			end
			if s.init then
				s.y = s.y + s.speed * dt * Settings.StarSpeed
				s.x = s.x + math.sin(t * 0.8 + s.phase) * s.sway * dt
				if s.y > size.Y + 4 then
					s.y = -4
					s.x = math.random() * size.X
				end
				if s.x < -4 then s.x = size.X + 4 end
				if s.x > size.X + 4 then s.x = -4 end
				s.frame.Position = UDim2.fromOffset(s.x, s.y)
			end
		end
	end
end)

--=====================================================================
-- MENU PANEL
--=====================================================================
local Panel = new("Frame", {
	Name = "Panel",
	Size = UDim2.fromOffset(340, 460),
	Position = UDim2.new(0, 22, 0, 70),
	BackgroundColor3 = Color3.fromRGB(6, 6, 8),
	BackgroundTransparency = Settings.PanelBg,
	BorderSizePixel = 0,
}, MenuGui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, Panel)
new("UIStroke", { Color = Color3.fromRGB(55, 55, 65), Thickness = 1 }, Panel)

local PanelStars = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
	ClipsDescendants = true, ZIndex = 1,
}, Panel)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, PanelStars)
createStarField(PanelStars, 70, 2)

local Header = new("Frame", {
	Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, ZIndex = 4,
}, Panel)
new("TextLabel", {
	Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0, 12, 0, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 14,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "VENICE  //  LOCK-ON", ZIndex = 4,
}, Header)

local Status = new("TextLabel", {
	Size = UDim2.new(0.4, -12, 1, 0), Position = UDim2.new(0.6, 0, 0, 0),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11,
	TextColor3 = Color3.fromRGB(120, 120, 135),
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "IDLE", ZIndex = 4,
}, Header)

new("Frame", {
	Size = UDim2.new(1, -24, 0, 1), Position = UDim2.new(0, 12, 1, -1),
	BackgroundColor3 = Color3.fromRGB(45, 45, 55), BorderSizePixel = 0, ZIndex = 4,
}, Header)

local DebugBar = new("TextLabel", {
	Size = UDim2.new(1, -24, 0, 14), Position = UDim2.new(0, 12, 0, 33),
	BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11,
	TextColor3 = Color3.fromRGB(120, 200, 140),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "booting...", ZIndex = 4,
}, Panel)

local Content = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -50), Position = UDim2.new(0, 0, 0, 50),
	BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 3, ScrollBarImageColor3 = Color3.fromRGB(90, 90, 100),
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 3,
}, Panel)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
	PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 14),
}, Content)
new("UIListLayout", {
	Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder,
}, Content)

-- ------------------------- UI COMPONENTS -----------------------------
local order = 0
local function nextOrder()
	order = order + 1
	return order
end

local function makeSection(text)
	local row = new("Frame", {
		Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, Content)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = Color3.fromRGB(150, 150, 165),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = string.upper(text),
	}, row)
	new("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -2),
		BackgroundColor3 = Color3.fromRGB(32, 32, 40), BorderSizePixel = 0,
	}, row)
	return row
end

local function makeRow(h)
	return new("Frame", {
		Size = UDim2.new(1, 0, 0, h or 22), BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, Content)
end

local function makeHint(text)
	local row = makeRow(14)
	return new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 11,
		TextColor3 = Color3.fromRGB(125, 125, 140),
		TextXAlignment = Enum.TextXAlignment.Left, Text = text,
	}, row)
end

local function makeToggle(label, key, onChange)
	local row = makeRow(22)
	new("TextLabel", {
		Size = UDim2.new(0.7, 0, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 13,
		TextColor3 = Color3.fromRGB(212, 212, 220),
		TextXAlignment = Enum.TextXAlignment.Left, Text = label,
	}, row)

	local btn = new("TextButton", {
		Size = UDim2.fromOffset(38, 18), Position = UDim2.new(1, -38, 0.5, -9),
		BackgroundColor3 = Color3.fromRGB(40, 40, 48), Text = "",
		BorderSizePixel = 0, AutoButtonColor = false,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, btn)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(13, 13), BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
	}, btn)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

	local function refresh()
		local on = Settings[key]
		btn.BackgroundColor3 = on and ACCENT or Color3.fromRGB(40, 40, 48)
		knob.BackgroundColor3 = on and Color3.fromRGB(10, 10, 12) or Color3.fromRGB(150, 150, 160)
		knob.Position = on and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
	end

	btn.MouseButton1Click:Connect(function()
		Settings[key] = not Settings[key]
		refresh()
		if onChange then onChange(Settings[key]) end
	end)
	refresh()
	return row
end

local function makeSlider(label, key, min, max, step, onChange)
	local row = makeRow(30)
	local top = new("Frame", {
		Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1,
	}, row)
	new("TextLabel", {
		Size = UDim2.new(0.7, 0, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 12,
		TextColor3 = Color3.fromRGB(200, 200, 210),
		TextXAlignment = Enum.TextXAlignment.Left, Text = label,
	}, top)
	local val = new("TextLabel", {
		Size = UDim2.new(0.3, 0, 1, 0), Position = UDim2.new(0.7, 0, 0, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Right, Text = tostring(Settings[key]),
	}, top)

	local track = new("Frame", {
		Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 0, 19),
		BackgroundColor3 = Color3.fromRGB(36, 36, 44), BorderSizePixel = 0,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

	local fill = new("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ACCENT, BorderSizePixel = 0,
	}, track)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
	}, track)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

	local hit = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0.5, -10),
		BackgroundTransparency = 1, Text = "",
	}, track)

	local function render(rel)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
	end

	local function applyFromX(px)
		local rel = clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local snapped = math.floor((min + (max - min) * rel) / step + 0.5) * step
		snapped = clamp(snapped, min, max)
		Settings[key] = snapped
		val.Text = tostring(snapped)
		render((snapped - min) / (max - min))
		if onChange then onChange(snapped) end
	end

	local self = {}

	function self.refresh()
		val.Text = tostring(Settings[key])
		render((Settings[key] - min) / (max - min))
	end

	function self.setRange(newMin, newMax, newStep)
		min, max, step = newMin, newMax, newStep
		Settings[key] = clamp(Settings[key], min, max)
		self.refresh()
	end

	self.refresh()

	local dragging = false
	hit.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			applyFromX(UserInputService:GetMouseLocation().X)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
			applyFromX(UserInputService:GetMouseLocation().X)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)

	return self
end

local function makeCycle(label, key, options, onChange)
	local row = makeRow(22)
	new("TextLabel", {
		Size = UDim2.new(0.45, 0, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 13,
		TextColor3 = Color3.fromRGB(212, 212, 220),
		TextXAlignment = Enum.TextXAlignment.Left, Text = label,
	}, row)

	local btn = new("TextButton", {
		Size = UDim2.fromOffset(120, 18), Position = UDim2.new(1, -120, 0.5, -9),
		BackgroundColor3 = Color3.fromRGB(30, 30, 38), Text = "",
		BorderSizePixel = 0, AutoButtonColor = false,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, btn)
	local txt = new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 11,
		TextColor3 = Color3.fromRGB(235, 235, 240), Text = tostring(Settings[key]),
	}, btn)

	local function findIndex()
		for i, v in ipairs(options) do
			if v == Settings[key] then return i end
		end
		return 1
	end

	btn.MouseButton1Click:Connect(function()
		local idx = findIndex() % #options + 1
		Settings[key] = options[idx]
		txt.Text = tostring(options[idx])
		if onChange then onChange(Settings[key]) end
	end)
	return row
end

local function makeColor(label, key, onChange)
	local row = makeRow(22)
	new("TextLabel", {
		Size = UDim2.new(0.5, 0, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 13,
		TextColor3 = Color3.fromRGB(212, 212, 220),
		TextXAlignment = Enum.TextXAlignment.Left, Text = label,
	}, row)

	local box = new("Frame", {
		Size = UDim2.fromOffset(100, 18), Position = UDim2.new(1, -100, 0.5, -9),
		BackgroundColor3 = Settings[key], BorderSizePixel = 0,
	}, row)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, box)

	local tb = new("TextBox", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 11,
		TextColor3 = Color3.fromRGB(10, 10, 12), ClearTextOnFocus = false,
		Text = string.format("%02X%02X%02X",
			math.floor(Settings[key].R * 255),
			math.floor(Settings[key].G * 255),
			math.floor(Settings[key].B * 255)),
	}, box)

	tb.FocusLost:Connect(function()
		local hex = tb.Text:gsub("#", "")
		if #hex == 6 then
			local ok, c = pcall(Color3.fromHex, hex)
			if ok and c then
				Settings[key] = c
				box.BackgroundColor3 = c
				if onChange then onChange(c) end
			end
		end
	end)
	return row
end

-- ------------------------- MENU CONTENTS -----------------------------
makeSection("ESP")
makeToggle("Enable ESP", "ESPEnabled", function() refreshHighlights() end)
makeToggle("Boxes", "Boxes")
makeSlider("Box thickness", "BoxThickness", 1, 4, 1)
makeToggle("Box fill", "BoxFill")
makeSlider("Fill transparency", "BoxFillTrans", 0, 1, 0.02)
makeToggle("Names", "Names")
makeToggle("Distance", "Distance")
makeToggle("Health bars", "Health")
makeToggle("Snaplines", "Snaplines")
makeCycle("Snapline origin", "SnaplineFrom", { "Bottom", "Center", "Mouse" })
makeToggle("Highlight", "Highlight", function() refreshHighlights() end)
makeToggle("Team check", "TeamCheck", function() refreshHighlights() end)
makeToggle("Include local player", "ShowLocal")
makeSlider("Max distance", "MaxDistance", 50, 3000, 25)
makeSlider("Nudge X", "EspOffsetX", -80, 80, 1)
makeSlider("Nudge Y", "EspOffsetY", -80, 80, 1)
makeHint("use nudges only if boxes sit off the player")
makeColor("Box color", "BoxColor")
makeColor("Snapline color", "SnaplineColor")
makeColor("Candidate color", "CandidateColor")
makeColor("Highlight color", "HighlightColor", function() refreshHighlights() end)

makeSection("Lock-on FOV")
local fovSlider = makeSlider("Lock FOV", "LockFOV", 20, 900, 10, function()
	Settings.LockFOVPreset = "Custom"
end)
local fovHint = makeHint("")

local function applyFovUnit()
	if Settings.LockFOVUnit == "Degrees" then
		fovSlider.setRange(1, 120, 0.5)
	else
		fovSlider.setRange(20, 900, 10)
	end
	Settings.LockFOVPreset = "Custom"
end
makeCycle("FOV unit", "LockFOVUnit", { "Pixels", "Degrees" }, applyFovUnit)
applyFovUnit()

local PRESETS = { ["Tight"] = 60, ["Normal"] = 120, ["Wide"] = 260, ["Huge"] = 420 }
makeCycle("FOV preset", "LockFOVPreset",
	{ "Custom", "Tight", "Normal", "Wide", "Huge" },
	function(v)
		local px = PRESETS[v]
		if not px then return end
		if Settings.LockFOVUnit == "Degrees" then
			Settings.LockFOV = math.floor(pixelsToDegrees(px) * 2) / 2
		else
			Settings.LockFOV = px
		end
		fovSlider.refresh()
	end)

makeToggle("Strict FOV only", "StrictFOV")
makeCycle("FOV containment", "FOVTargetMode", { "Center", "Any part", "Full body" })
makeToggle("Drop lock if leaves FOV", "FOVDropOut")
makeToggle("Fallback outside FOV", "Fallback3D")

makeToggle("Show FOV circle", "FOVCircle")
makeCycle("Circle origin", "FOVCircleMode", { "Cursor", "Center" })
makeCycle("Circle visibility", "FOVCircleShow", { "Always", "While held" })
makeSlider("Circle thickness", "FOVCircleThick", 1, 4, 1)
makeSlider("Circle opacity", "FOVCircleTrans", 0, 1, 0.02)
makeToggle("Circle fill", "FOVCircleFill")
makeColor("Circle color", "FOVCircleColor")

makeSection("Lock-on")
makeToggle("Enable lock-on", "LockEnabled")
makeCycle("Lock key", "LockKey", {
	Enum.UserInputType.MouseButton2,
	Enum.UserInputType.MouseButton1,
	Enum.KeyCode.E,
	Enum.KeyCode.Q,
	Enum.KeyCode.LeftAlt,
})
makeToggle("Toggle mode (not hold)", "ToggleMode")
makeToggle("Orbit around target", "Orbit")
makeToggle("Lock mouse to center", "LockMouse")
makeSlider("Sensitivity", "Sensitivity", 0.05, 1, 0.05)
makeToggle("Scroll zoom", "Zoom")
makeSlider("Min distance", "MinDistance", 2, 20, 1)
makeSlider("Max lock distance", "MaxLockDistance", 10, 200, 5)
makeSlider("Start distance", "LockDistance", 4, 60, 1)
makeToggle("FOV zoom", "FOVZoom")
makeSlider("Camera FOV", "BaseFOV", 40, 120, 1)
makeSlider("Zoom min FOV", "MinFOV", 15, 90, 1)
makeCycle("Aim part", "AimPart", { "Head", "HumanoidRootPart", "Torso" })
makeToggle("Visible only (raycast)", "VisibleOnly")
makeToggle("Re-acquire on death", "AutoReacquire")
makeToggle("Crosshair", "Crosshair")
makeColor("Lock color", "LockColor")

makeSection("Visuals")
makeToggle("Stars", "Stars")
makeSlider("Star speed", "StarSpeed", 0.1, 4, 0.1)
makeSlider("Panel opacity", "PanelBg", 0, 1, 0.02)
makeToggle("Debug bar", "Debug")

-- ------------------------- DRAG / TOGGLE -----------------------------
local dragging, dragStart, startPos = false, nil, nil
Header.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = UserInputService:GetMouseLocation()
		startPos = Panel.Position
	end
end)
UserInputService.InputChanged:Connect(function(i)
	if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = UserInputService:GetMouseLocation() - dragStart
		Panel.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

--=====================================================================
-- FOV CIRCLE + CROSSHAIR
--=====================================================================
local FovCircle = new("Frame", {
	Size = UDim2.fromOffset(200, 200),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = 0,
}, EspGui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, FovCircle)

local fovFill = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Settings.FOVCircleColor,
	BackgroundTransparency = 0.92, BorderSizePixel = 0, ZIndex = 0,
}, FovCircle)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, fovFill)

local fovStroke = new("UIStroke", {
	Color = Settings.FOVCircleColor, Thickness = 1,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, FovCircle)

local fovDot = new("Frame", {
	Size = UDim2.fromOffset(3, 3), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Settings.FOVCircleColor,
	BorderSizePixel = 0, ZIndex = 1,
}, FovCircle)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, fovDot)

local Cross = new("Frame", {
	Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
	Visible = false, ZIndex = 5,
}, EspGui)
for _, d in ipairs({ {1, 0}, {0, 1} }) do
	new("Frame", {
		Size = UDim2.new(0, d[1] == 1 and 12 or 1, 0, d[2] == 1 and 1 or 12),
		Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0,
	}, Cross)
end

--=====================================================================
-- ESP
--=====================================================================
local espObjects = {}

local function shouldShow(player)
	if not Settings.ESPEnabled then return false end
	if player == LP and not Settings.ShowLocal then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum and hum.Health > 0) then return false end
	if Settings.TeamCheck and player ~= LP and player.Team and LP.Team
		and player.Team == LP.Team then
		return false
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	if (hrp.Position - Camera.CFrame.Position).Magnitude > Settings.MaxDistance then
		return false
	end
	return true
end

local function createESP(player)
	if espObjects[player] then return end
	local o = {}

	o.box = new("Frame", {
		Name = "Box", BackgroundTransparency = 1, BorderSizePixel = 0,
		Visible = false, ZIndex = 2,
	}, EspGui)
	o.stroke = new("UIStroke", {
		Color = Settings.BoxColor, Thickness = Settings.BoxThickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o.box)
	o.fill = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Settings.BoxColor,
		BackgroundTransparency = Settings.BoxFillTrans, BorderSizePixel = 0,
	}, o.box)

	o.name = new("TextLabel", {
		Size = UDim2.fromOffset(180, 14), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = Settings.BoxColor, TextStrokeTransparency = 0.35,
		TextStrokeColor3 = Color3.new(0, 0, 0), Visible = false, Text = "", ZIndex = 3,
	}, EspGui)

	o.hpBack = new("Frame", {
		Size = UDim2.new(0, 3, 1, 0), Position = UDim2.new(0, -6, 0, 0),
		BackgroundColor3 = Color3.fromRGB(20, 20, 20), BorderSizePixel = 0,
		Visible = false,
	}, o.box)
	o.hpFill = new("Frame", {
		Size = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(60, 220, 100), BorderSizePixel = 0,
	}, o.hpBack)

	o.line = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Settings.SnaplineColor,
		BorderSizePixel = 0, Visible = false, ZIndex = 1,
	}, EspGui)

	espObjects[player] = o
end

local function destroyESP(player)
	local o = espObjects[player]
	if not o then return end
	for _, inst in pairs(o) do
		if typeof(inst) == "Instance" then inst:Destroy() end
	end
	espObjects[player] = nil
end

local function applyHighlight(player)
	local char = player.Character
	if not char then return end
	local h = char:FindFirstChild("VeniceHighlight")
	local wanted = Settings.Highlight and shouldShow(player)

	if wanted then
		if not h then
			h = new("Highlight", { Name = "VeniceHighlight" }, char)
		end
		h.Adornee = char
		h.FillColor = Settings.HighlightColor
		h.FillTransparency = Settings.HighlightTrans
		h.OutlineColor = Settings.HighlightColor
		h.DepthMode = Settings.HighlightOccluded
			and Enum.HighlightDepthMode.Occluded
			or Enum.HighlightDepthMode.AlwaysOnTop
	elseif h then
		h:Destroy()
	end
end

function refreshHighlights()
	for _, p in ipairs(Players:GetPlayers()) do
		createESP(p)
		applyHighlight(p)
	end
end

for _, p in ipairs(Players:GetPlayers()) do
	createESP(p)
	applyHighlight(p)
end

Players.PlayerAdded:Connect(function(p)
	createESP(p)
	p.CharacterAdded:Connect(function()
		task.wait(0.2)
		applyHighlight(p)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	destroyESP(player)
end)

--=====================================================================
-- LOCK-ON
--=====================================================================
local locked       = false
local target       = nil
local candidate    = nil
local fovCount     = 0
local lockKeyHeld  = false
local yaw, pitch   = 0, 0
local lockDist     = Settings.LockDistance
local prevMouse    = nil
local prevFOV      = Camera.FieldOfView
local prevCamType  = Camera.CameraType
local statusUntil  = 0
local freeCursor   = Vector2.new(0, 0)

local function cursorIsFree()
	return UserInputService.MouseBehavior == Enum.MouseBehavior.Default
end

local function syncFreeCursor()
	if cursorIsFree() then
		freeCursor = UserInputService:GetMouseLocation()
	end
end
syncFreeCursor()

local function fovOrigin()
	if locked then return screenCenter() end
	if Settings.FOVCircleMode == "Center" then return screenCenter() end
	return freeCursor
end

local function isLockInput(input)
	local k = Settings.LockKey
	if typeof(k) ~= "EnumItem" then return false end
	if k.EnumType == Enum.UserInputType then
		return input.UserInputType == k
	elseif k.EnumType == Enum.KeyCode then
		return input.KeyCode == k
	end
	return false
end

local function setStatus(text, color, hold)
	Status.Text = text
	Status.TextColor3 = color
	statusUntil = hold and (os.clock() + hold) or 0
end

local function validForLock(player)
	if player == LP then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp and hum.Health > 0) then return false end
	if Settings.TeamCheck and player.Team and LP.Team and player.Team == LP.Team then
		return false
	end
	if (hrp.Position - Camera.CFrame.Position).Magnitude > Settings.MaxDistance then
		return false
	end
	return true
end

local function hasLineOfSight(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local aim = char:FindFirstChild("Head") or hrp
	if not aim then return false end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { char }
	if LP.Character then table.insert(ignore, LP.Character) end
	params.FilterDescendantsInstances = ignore

	local origin = Camera.CFrame.Position
	local result = Workspace:Raycast(origin, aim.Position - origin, params)
	return result == nil or result.Instance:IsDescendantOf(char)
end

local function fovTest(char, origin, radius)
	if Settings.FOVTargetMode == "Center" then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return false, math.huge end
		local sp = screenPoint(hrp.Position)
		if not sp then return false, math.huge end
		local d = (sp - origin).Magnitude
		return d <= radius, d
	end

	local l, t, r, b = screenRect(char)
	if not l then return false, math.huge end

	local d = distToRect(origin.X, origin.Y, l, t, r, b)

	if Settings.FOVTargetMode == "Full body" then
		for _, c in ipairs({ {l, t}, {r, t}, {l, b}, {r, b} }) do
			if (Vector2.new(c[1], c[2]) - origin).Magnitude > radius then
				return false, d
			end
		end
		return true, d
	end

	return d <= radius, d
end

local function scanFov(origin, radius)
	local best, bestScore, count = nil, math.huge, 0
	for _, p in ipairs(Players:GetPlayers()) do
		if validForLock(p) then
			local char = p.Character
			if char then
				local inside, score = fovTest(char, origin, radius)
				if inside then
					count = count + 1
					if score < bestScore then
						best, bestScore = p, score
					end
				end
			end
		end
	end
	return best, count
end

local function acquireTarget()
	local origin = fovOrigin()
	local center = screenCenter()
	local radius = lockFovPixels()

	local best, bestScore           = nil, math.huge
	local fallback, fallbackScore   = nil, math.huge
	local nearest3D, nearest3DScore = nil, math.huge

	for _, p in ipairs(Players:GetPlayers()) do
		if validForLock(p) then
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and (not Settings.VisibleOnly or hasLineOfSight(char)) then
				local inside, score = fovTest(char, origin, radius)
				if inside and score < bestScore then
					best, bestScore = p, score
				end

				if not Settings.StrictFOV then
					local d3 = (hrp.Position - Camera.CFrame.Position).Magnitude
					if d3 < nearest3DScore then
						nearest3D, nearest3DScore = p, d3
					end

					local sp = screenPoint(hrp.Position)
					if sp then
						local dCenter = (sp - center).Magnitude
						if dCenter < fallbackScore then
							fallback, fallbackScore = p, dCenter
						end
					end
				end
			end
		end
	end

	if best then return best end
	if Settings.StrictFOV then return nil end
	if fallback then return fallback end
	if Settings.Fallback3D then return nearest3D end
	return nil
end

local function aimPosition(player)
	local char = player.Character
	if not char then return nil end
	local part = char:FindFirstChild(Settings.AimPart) or char:FindFirstChild("HumanoidRootPart")
	return part and part.Position or nil
end

local function lockOn()
	if locked then return end

	syncFreeCursor()
	local t = acquireTarget()
	if not t then
		setStatus("NO TARGET", Color3.fromRGB(255, 90, 90), 0.8)
		return
	end

	target = t
	locked = true

	prevFOV     = Camera.FieldOfView
	prevCamType = Camera.CameraType

	local aim = aimPosition(t)
	if aim then
		local offset = Camera.CFrame.Position - aim
		lockDist = clamp(offset.Magnitude, Settings.MinDistance, Settings.MaxLockDistance)
		local dir = offset.Unit
		pitch = math.deg(math.asin(clamp(dir.Y, -1, 1)))
		yaw   = math.deg(math.atan2(dir.X, dir.Z))
	end

	if Settings.LockMouse then
		prevMouse = UserInputService.MouseBehavior
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	Camera.CameraType = Enum.CameraType.Scriptable

	setStatus(t.DisplayName, Settings.LockColor)
end

local function unlock()
	if not locked then return end
	locked = false
	target = nil
	Camera.CameraType = prevCamType
	Camera.FieldOfView = prevFOV
	if Settings.LockMouse then
		UserInputService.MouseBehavior = prevMouse or Enum.MouseBehavior.Default
	end
	syncFreeCursor()
	setStatus("IDLE", Color3.fromRGB(120, 120, 135))
end

UserInputService.InputBegan:Connect(function(input, _gp)
	local ok, err = pcall(function()
		if UserInputService:GetFocusedTextBox() then return end

		if input.KeyCode == Enum.KeyCode.RightShift then
			MenuGui.Enabled = not MenuGui.Enabled
		end

		if isLockInput(input) and Settings.LockEnabled then
			lockKeyHeld = true
			if Settings.ToggleMode then
				if locked then unlock() else lockOn() end
			else
				lockOn()
			end
		end
	end)
	if not ok then lastError = "input: " .. tostring(err) end
end)

UserInputService.InputEnded:Connect(function(input)
	if isLockInput(input) then
		lockKeyHeld = false
		if Settings.LockEnabled and not Settings.ToggleMode then
			unlock()
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		syncFreeCursor()
		if locked and Settings.Orbit then
			yaw   = yaw - input.Delta.X * Settings.Sensitivity
			pitch = clamp(pitch - input.Delta.Y * Settings.Sensitivity, -89, 89)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and locked and Settings.Zoom then
		lockDist = clamp(lockDist - input.Position.Z * 2, Settings.MinDistance, Settings.MaxLockDistance)
	end
end)

--=====================================================================
-- MAIN LOOP
--=====================================================================
local function updateFrame()
	refreshInset()
	local radius = lockFovPixels()

	if not locked then syncFreeCursor() end

	local origin = fovOrigin()
	candidate, fovCount = scanFov(origin, radius)

	local showCircle = Settings.FOVCircle and Settings.LockEnabled
	if Settings.FOVCircleShow == "While held" then
		showCircle = showCircle and lockKeyHeld
	end
	FovCircle.Visible = showCircle

	if showCircle then
		FovCircle.Size = UDim2.fromOffset(radius * 2, radius * 2)
		FovCircle.Position = UDim2.fromOffset(origin.X, origin.Y)

		local col = Settings.FOVCircleColor
		if locked then
			col = Settings.LockColor
		elseif candidate then
			col = Settings.CandidateColor
		end

		fovStroke.Color = col
		fovStroke.Thickness = Settings.FOVCircleThick
		fovStroke.Transparency = Settings.FOVCircleTrans
		fovDot.BackgroundColor3 = col
		fovFill.BackgroundColor3 = col
		fovFill.Visible = Settings.FOVCircleFill
		fovFill.BackgroundTransparency = math.min(Settings.FOVCircleTrans + 0.35, 1)
	end

	fovHint.Text = string.format("radius %dpx | in FOV %d | %s",
		math.floor(radius), fovCount, cursorIsFree() and "cursor free" or "mouse locked")

	if locked then
		local aim = target and aimPosition(target)

		if aim and Settings.FOVDropOut then
			local inside = fovTest(target.Character, fovOrigin(), radius)
			if not inside then aim = nil end
		end

		if aim then
			local camPos
			if Settings.Orbit then
				local cp = math.cos(math.rad(pitch))
				local dir = Vector3.new(
					math.sin(math.rad(yaw)) * cp,
					math.sin(math.rad(pitch)),
					math.cos(math.rad(yaw)) * cp
				)
				camPos = aim + dir * lockDist
			else
				camPos = Camera.CFrame.Position
			end
			Camera.CFrame = CFrame.lookAt(camPos, aim)
			if Settings.FOVZoom then
				Camera.FieldOfView = clamp(
					Settings.BaseFOV * (lockDist / 20),
					Settings.MinFOV, Settings.BaseFOV)
			end
		else
			if Settings.AutoReacquire then
				local t = acquireTarget()
				if t then
					target = t
					setStatus(t.DisplayName, Settings.LockColor)
				else
					unlock()
				end
			else
				unlock()
			end
		end
	end

	Cross.Visible = locked and Settings.Crosshair

	if statusUntil > 0 and os.clock() > statusUntil then
		statusUntil = 0
		Status.Text = locked and (target and target.DisplayName or "IDLE") or "IDLE"
		Status.TextColor3 = locked and Settings.LockColor or Color3.fromRGB(120, 120, 135)
	end

	local vp = Camera.ViewportSize
	local lineFrom = Vector2.new(vp.X / 2, vp.Y + insetY)
	if Settings.SnaplineFrom == "Center" then
		lineFrom = screenCenter()
	elseif Settings.SnaplineFrom == "Mouse" then
		lineFrom = freeCursor
	end

	for player, o in pairs(espObjects) do
		local char = player.Character
		local show = shouldShow(player) and char ~= nil

		if not show then
			o.box.Visible = false
			o.name.Visible = false
			o.line.Visible = false
		else
			local l, t, r, b = screenRect(char)

			if not l then
				o.box.Visible = false
				o.name.Visible = false
				o.line.Visible = false
			else
				local bw = math.max(r - l, 2)
				local bh = math.max(b - t, 4)

				local isTarget = (player == target)
				local isCand   = (player == candidate) and not isTarget
				local col = isTarget and Settings.LockColor
					or (isCand and Settings.CandidateColor)
					or Settings.BoxColor

				o.box.Visible = Settings.Boxes
				if Settings.Boxes then
					o.box.Position = UDim2.fromOffset(l, t)
					o.box.Size = UDim2.fromOffset(bw, bh)
					o.stroke.Color = col
					o.stroke.Thickness = Settings.BoxThickness
					o.fill.Visible = Settings.BoxFill
					o.fill.BackgroundColor3 = col
					o.fill.BackgroundTransparency = Settings.BoxFillTrans
				end

				o.name.Visible = Settings.Names
				if Settings.Names then
					local text = player.DisplayName
					if Settings.Distance then
						local hrp = char:FindFirstChild("HumanoidRootPart")
						if hrp then
							text = string.format("%s  [%dm]", text,
								(hrp.Position - Camera.CFrame.Position).Magnitude)
						end
					end
					o.name.Text = text
					o.name.TextColor3 = col
					o.name.Position = UDim2.fromOffset(l + bw / 2, t - 2)
				end

				local hum = char:FindFirstChildOfClass("Humanoid")
				local showHp = Settings.Health and Settings.Boxes and hum
				o.hpBack.Visible = showHp and true or false
				if showHp then
					local ratio = clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
					o.hpFill.Size = UDim2.new(1, 0, ratio, 0)
					o.hpFill.BackgroundColor3 = Color3.fromRGB(
						math.floor(255 * (1 - ratio)), math.floor(255 * ratio), 60)
				end

				o.line.Visible = Settings.Snaplines
				if Settings.Snaplines then
					local endPos = Vector2.new(l + bw / 2, b)
					local delta  = endPos - lineFrom
					o.line.Size = UDim2.new(0, delta.Magnitude, 0, 1)
					o.line.Position = UDim2.fromOffset(
						lineFrom.X + delta.X / 2, lineFrom.Y + delta.Y / 2)
					o.line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
					o.line.BackgroundColor3 = col
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(function()
	local ok, err = pcall(updateFrame)
	if not ok then
		lastError = tostring(err)
	end

	if Settings.Debug then
		DebugBar.Visible = true

		local total, valid = 0, 0
		for _, p in ipairs(Players:GetPlayers()) do
			total = total + 1
			if validForLock(p) then valid = valid + 1 end
		end

		local espOn = 0
		for _ in pairs(espObjects) do espOn = espOn + 1 end

		DebugBar.TextColor3 = (lastError ~= "")
			and Color3.fromRGB(255, 120, 120)
			or Color3.fromRGB(120, 200, 140)

		if lastError ~= "" then
			DebugBar.Text = "ERR: " .. lastError:sub(1, 52)
		else
			DebugBar.Text = string.format(
				"ply:%d valid:%d fov:%d esp:%d lock:%s tgt:%s",
				total, valid, fovCount, espOn,
				locked and "ON" or "off",
				target and target.Name or "-")
		end
	else
		DebugBar.Visible = false
	end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		for _, p in ipairs(Players:GetPlayers()) do
			applyHighlight(p)
		end
	end
end)

LP.CharacterAdded:Connect(function()
	task.wait(0.5)
	refreshHighlights()
end)

refreshHighlights()
