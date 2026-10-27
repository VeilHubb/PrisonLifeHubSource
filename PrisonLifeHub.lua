--[[
Prison Life hub v3.0  (cueshut-style UI library)
Insert opens/closes the menu.

UPDATE LOG v3.0
 Combat
  + Aimbot target priority: Crosshair / Distance / Health
  + Aimbot max distance
  + Aimbot prediction (ms slider)
  + Triggerbot with delay + range
 Visuals
  + ESP: health bar, skeleton (R6 + R15), head dot, team colors, max distance
  + Radar overlay (size + range)
  + Custom crosshair (size + gap)
  + Time of day changer
  + Camera max zoom changer
 Movement
  + Jump power, gravity, bunny hop
  + Anti-void, respawn at death position
  + Teleport to nearest enemy
  + Waypoints now saved per game and reloaded
 Misc
  + Auto rejoin on kick/disconnect
  + FPS cap, copy JobId / PlaceId, reset character, player info
 Fixes
  + Walk speed / jump power restore the original value instead of a fixed number
  + Unload restores everything it touched
]]

local LIB_URL = "https://raw.githubusercontent.com/cueshut/saves/main/criminality%20paste%20ui%20library"

local ICONS = {
	combat = "rbxassetid://16405125208",
	visuals = "rbxassetid://13321848320",
	movement = "rbxassetid://9657060536",
	misc = "rbxassetid://6031280882",
}

local function svc(name)
	local s = game:GetService(name)
	if cloneref then
		local ok, c = pcall(cloneref, s)
		if ok then return c end
	end
	return s
end

local Players = svc("Players")
local RunService = svc("RunService")
local UIS = svc("UserInputService")
local Workspace = svc("Workspace")
local Lighting = svc("Lighting")
local TeleportService = svc("TeleportService")
local VirtualUser = svc("VirtualUser")
local CoreGui = svc("CoreGui")
local HttpService = svc("HttpService")
local StarterGui = svc("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local env = (getgenv and getgenv()) or _G
if env.PLHubUnload then
	pcall(env.PLHubUnload)
end

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "PL Hub", Text = text, Duration = 4 })
	end)
end

-- State ---------------------------------------------------------------

local S = {
	aimbot = false, aimPart = "Head", aimPriority = "Crosshair", fov = 120, smooth = 30, aimDist = 1000,
	teamcheck = true, visible = false, drawFov = true,
	predict = false, predictMs = 60,
	trigger = false, trigDelay = 60, trigDist = 500,
	hitbox = false, hitSize = 8, hitTransp = 70,

	esp = false, espColor = Color3.fromRGB(84, 101, 255), teamColors = true,
	names = true, dist = true, health = true, healthBar = false,
	boxes = false, skeleton = false, tracers = false, headDot = false,
	enemiesOnly = true, espDist = 2000,
	radar = false, radarSize = 90, radarRange = 300,
	crosshair = false, chSize = 8, chGap = 4,
	fullbright = false, fovOn = false, fovVal = 90,
	timeOn = false, timeVal = 14, zoomOn = false, zoom = 100,

	fly = false, flySpeed = 70, noclip = false,
	speed = false, walk = 40, infjump = false,
	jumpOn = false, jumpPower = 80, gravityOn = false, gravity = 100, bhop = false,
	antivoid = false, respawnBack = false,
	spectate = false, clicktp = false,

	antiafk = true, autoRejoin = false, fpsOn = false, fps = 144,
}

local K = { aimbot = false, fly = false, noclip = false }

local connections = {}
local function track(c)
	table.insert(connections, c)
	return c
end

local function getChar(plr)
	local char = plr.Character
	if not char or not char.Parent then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return nil end
	return char, hum, root
end

local function isEnemy(plr)
	if plr.Team == nil or LocalPlayer.Team == nil then return true end
	return plr.Team ~= LocalPlayer.Team
end

-- Load library --------------------------------------------------------

local okLib, library = pcall(function()
	return loadstring(game:HttpGet(LIB_URL))()
end)
if not okLib or type(library) ~= "table" then
	warn("PL Hub: could not load UI library")
	return
end

local before = {}
for _, c in ipairs(CoreGui:GetChildren()) do before[c] = true end

local menu = library.new('Prison Life <font color="rgb(84,101,255)">Hub</font>', "PLHub/")

local menuGui
for _, c in ipairs(CoreGui:GetChildren()) do
	if not before[c] and c:IsA("ScreenGui") then menuGui = c end
end

-- Drawing helpers -----------------------------------------------------

local hasDrawing = Drawing ~= nil and Drawing.new ~= nil

local function newDrawing(kind, props)
	if not hasDrawing then return nil end
	local ok, d = pcall(Drawing.new, kind)
	if not ok or not d then return nil end
	for k, v in pairs(props) do
		pcall(function() d[k] = v end)
	end
	return d
end

local function vis(d, v)
	if d then d.Visible = v end
end

local fovCircle = newDrawing("Circle", {
	Thickness = 1, NumSides = 64, Filled = false, Color = Color3.new(1, 1, 1), Visible = false,
})

-- ESP -----------------------------------------------------------------

local guiParent = (gethui and gethui()) or CoreGui
local espFolder = Instance.new("Folder")
espFolder.Name = "PLHubESP"
espFolder.Parent = guiParent

local esp = {}

local R6 = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
local R15 = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local function destroyESP(plr)
	local o = esp[plr]
	if not o then return end
	for _, k in ipairs({ "hl", "bb" }) do
		if o[k] then pcall(function() o[k]:Destroy() end) end
	end
	for _, k in ipairs({ "box", "line", "hpBg", "hpFill", "dot" }) do
		if o[k] then pcall(function() o[k]:Remove() end) end
	end
	for _, l in pairs(o.skel) do
		pcall(function() l:Remove() end)
	end
	esp[plr] = nil
end

local function createESP(plr, char, root)
	destroyESP(plr)
	local o = { char = char, skel = {} }

	o.hl = Instance.new("Highlight")
	o.hl.FillTransparency = 0.65
	o.hl.OutlineTransparency = 0
	o.hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	o.hl.Adornee = char
	o.hl.Parent = espFolder

	o.bb = Instance.new("BillboardGui")
	o.bb.Size = UDim2.fromOffset(200, 20)
	o.bb.StudsOffset = Vector3.new(0, 3.4, 0)
	o.bb.AlwaysOnTop = true
	o.bb.Adornee = root
	o.bb.Parent = espFolder

	o.label = Instance.new("TextLabel")
	o.label.Size = UDim2.fromScale(1, 1)
	o.label.BackgroundTransparency = 1
	o.label.Font = Enum.Font.Ubuntu
	o.label.TextSize = 14
	o.label.TextStrokeTransparency = 0.4
	o.label.Parent = o.bb

	o.box = newDrawing("Square", { Thickness = 1, Filled = false, Visible = false })
	o.line = newDrawing("Line", { Thickness = 1, Visible = false })
	o.hpBg = newDrawing("Square", { Filled = true, Color = Color3.new(0, 0, 0), Visible = false })
	o.hpFill = newDrawing("Square", { Filled = true, Visible = false })
	o.dot = newDrawing("Circle", { Filled = true, NumSides = 16, Radius = 3, Visible = false })

	esp[plr] = o
	return o
end

local function hideDrawings(o)
	vis(o.box, false)
	vis(o.line, false)
	vis(o.hpBg, false)
	vis(o.hpFill, false)
	vis(o.dot, false)
	for _, l in pairs(o.skel) do l.Visible = false end
end

local function hideESP(o)
	o.hl.Enabled = false
	o.bb.Enabled = false
	hideDrawings(o)
end

local function drawSkeleton(o, char, color)
	local bones = char:FindFirstChild("UpperTorso") and R15 or R6
	for i, pair in ipairs(bones) do
		local line = o.skel[i]
		if not line then
			line = newDrawing("Line", { Thickness = 1, Visible = false })
			if line then o.skel[i] = line end
		end
		if line then
			local a, b = char:FindFirstChild(pair[1]), char:FindFirstChild(pair[2])
			if a and b then
				local pa, oa = Camera:WorldToViewportPoint(a.Position)
				local pb, ob = Camera:WorldToViewportPoint(b.Position)
				if oa and ob then
					line.From = Vector2.new(pa.X, pa.Y)
					line.To = Vector2.new(pb.X, pb.Y)
					line.Color = color
					line.Visible = true
				else
					line.Visible = false
				end
			else
				line.Visible = false
			end
		end
	end
	for i, l in pairs(o.skel) do
		if i > #bones then l.Visible = false end
	end
end

local function stepESP()
	local _, _, myRoot = getChar(LocalPlayer)
	local vp = Camera.ViewportSize

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local char, hum, root = getChar(plr)
			local o = esp[plr]
			local dist = (char and myRoot) and (myRoot.Position - root.Position).Magnitude or 0
			local show = S.esp and char ~= nil and dist <= S.espDist and (not S.enemiesOnly or isEnemy(plr))

			if not show then
				if o then
					if char == nil then destroyESP(plr) else hideESP(o) end
				end
			else
				if not o or o.char ~= char then
					o = createESP(plr, char, root)
				end
				local color = S.teamColors and plr.TeamColor.Color or S.espColor

				o.hl.Enabled = true
				o.hl.FillColor = color
				o.hl.OutlineColor = color

				local parts = {}
				if S.names then table.insert(parts, plr.DisplayName) end
				if S.dist and myRoot then table.insert(parts, math.floor(dist) .. "m") end
				if S.health then table.insert(parts, "HP " .. math.floor(hum.Health)) end
				o.bb.Enabled = #parts > 0
				o.label.Text = table.concat(parts, " | ")
				o.label.TextColor3 = color

				local pos, onScreen = Camera:WorldToViewportPoint(root.Position)

				if onScreen then
					local top = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2.8, 0))
					local bottom = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.2, 0))
					local h = math.abs(bottom.Y - top.Y)
					local w = h * 0.55
					local left = pos.X - w / 2

					if o.box then
						if S.boxes then
							o.box.Size = Vector2.new(w, h)
							o.box.Position = Vector2.new(left, top.Y)
							o.box.Color = color
							o.box.Visible = true
						else
							o.box.Visible = false
						end
					end

					if o.hpBg and o.hpFill then
						if S.healthBar then
							local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
							o.hpBg.Position = Vector2.new(left - 6, top.Y)
							o.hpBg.Size = Vector2.new(3, h)
							o.hpBg.Visible = true
							o.hpFill.Size = Vector2.new(3, h * frac)
							o.hpFill.Position = Vector2.new(left - 6, top.Y + h * (1 - frac))
							o.hpFill.Color = Color3.fromHSV(frac * 0.33, 1, 1)
							o.hpFill.Visible = true
						else
							o.hpBg.Visible = false
							o.hpFill.Visible = false
						end
					end

					if o.dot then
						local head = char:FindFirstChild("Head")
						if S.headDot and head then
							local hp = Camera:WorldToViewportPoint(head.Position)
							o.dot.Position = Vector2.new(hp.X, hp.Y)
							o.dot.Color = color
							o.dot.Visible = true
						else
							o.dot.Visible = false
						end
					end

					if o.line then
						if S.tracers then
							o.line.From = Vector2.new(vp.X / 2, vp.Y)
							o.line.To = Vector2.new(pos.X, pos.Y)
							o.line.Color = color
							o.line.Visible = true
						else
							o.line.Visible = false
						end
					end

					if S.skeleton and hasDrawing then
						drawSkeleton(o, char, color)
					else
						for _, l in pairs(o.skel) do l.Visible = false end
					end
				else
					hideDrawings(o)
				end
			end
		end
	end
end

-- Radar / crosshair ---------------------------------------------------

local radar = {
	bg = newDrawing("Circle", { Filled = true, NumSides = 48, Color = Color3.fromRGB(10, 10, 10), Transparency = 0.6, Visible = false }),
	ring = newDrawing("Circle", { Filled = false, NumSides = 48, Thickness = 1, Color = Color3.fromRGB(84, 101, 255), Visible = false }),
	me = newDrawing("Circle", { Filled = true, NumSides = 12, Radius = 3, Color = Color3.new(1, 1, 1), Visible = false }),
	dots = {},
}

local function stepRadar()
	if not hasDrawing then return end
	local r = S.radarSize
	local center = Vector2.new(r + 20, r + 70)
	local show = S.radar

	for _, d in ipairs({ radar.bg, radar.ring }) do
		d.Visible = show
		d.Radius = r
		d.Position = center
	end
	if radar.me then
		radar.me.Visible = show
		radar.me.Position = center
	end

	local _, _, myRoot = getChar(LocalPlayer)
	local look = Camera.CFrame.LookVector
	local fwd = Vector3.new(look.X, 0, look.Z)
	if fwd.Magnitude < 0.01 then fwd = Vector3.new(0, 0, -1) else fwd = fwd.Unit end
	local right = fwd:Cross(Vector3.yAxis)
	local scale = r / S.radarRange

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local dot = radar.dots[plr]
			local char, _, root = getChar(plr)
			local visible = show and myRoot ~= nil and char ~= nil and (not S.enemiesOnly or isEnemy(plr))
			if visible then
				if not dot then
					dot = newDrawing("Circle", { Filled = true, NumSides = 12, Radius = 3, Visible = false })
					radar.dots[plr] = dot
				end
				if dot then
					local rel = root.Position - myRoot.Position
					local dx, dy = rel:Dot(right) * scale, -rel:Dot(fwd) * scale
					local mag = math.sqrt(dx * dx + dy * dy)
					local lim = r - 4
					if mag > lim then dx, dy = dx / mag * lim, dy / mag * lim end
					dot.Position = center + Vector2.new(dx, dy)
					dot.Color = S.teamColors and plr.TeamColor.Color or S.espColor
					dot.Visible = true
				end
			elseif dot then
				dot.Visible = false
			end
		end
	end
end

local crossLines = {}
for i = 1, 4 do
	crossLines[i] = newDrawing("Line", { Thickness = 1, Color = Color3.new(1, 1, 1), Visible = false })
end

local function stepCrosshair()
	local c = Camera.ViewportSize / 2
	local s, g = S.chSize, S.chGap
	local segs = {
		{ Vector2.new(-g, 0), Vector2.new(-g - s, 0) },
		{ Vector2.new(g, 0), Vector2.new(g + s, 0) },
		{ Vector2.new(0, -g), Vector2.new(0, -g - s) },
		{ Vector2.new(0, g), Vector2.new(0, g + s) },
	}
	for i = 1, 4 do
		local l = crossLines[i]
		if l then
			l.From = c + segs[i][1]
			l.To = c + segs[i][2]
			l.Visible = S.crosshair
		end
	end
end

-- Aimbot / triggerbot -------------------------------------------------

local function getAimPart(char)
	if S.aimPart == "Head" then
		return char:FindFirstChild("Head")
	elseif S.aimPart == "Torso" then
		return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	end
	return char:FindFirstChild("HumanoidRootPart")
end

local function isVisible(pos, char)
	local ignore = { char }
	if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end
	return #Camera:GetPartsObscuringTarget({ pos }, ignore) == 0
end

local function stepAimbot()
	if fovCircle then
		fovCircle.Visible = S.aimbot and S.drawFov
		fovCircle.Radius = S.fov
		fovCircle.Position = Camera.ViewportSize / 2
	end

	if not (S.aimbot and K.aimbot) then return end

	local _, _, myRoot = getChar(LocalPlayer)
	local center = Camera.ViewportSize / 2
	local best, bestScore

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and (not S.teamcheck or isEnemy(plr)) then
			local char, hum, root = getChar(plr)
			if char and hum.Health > 0 and not char:FindFirstChildOfClass("ForceField") then
				local part = getAimPart(char)
				if part then
					local aimPos = part.Position
					if S.predict then
						aimPos += root.AssemblyLinearVelocity * (S.predictMs / 1000)
					end
					local pos, onScreen = Camera:WorldToViewportPoint(aimPos)
					if onScreen then
						local screenD = (Vector2.new(pos.X, pos.Y) - center).Magnitude
						local worldD = myRoot and (myRoot.Position - root.Position).Magnitude or 0
						if screenD <= S.fov and worldD <= S.aimDist and (not S.visible or isVisible(aimPos, char)) then
							local score = screenD
							if S.aimPriority == "Distance" then
								score = worldD
							elseif S.aimPriority == "Health" then
								score = hum.Health
							end
							if bestScore == nil or score < bestScore then
								best, bestScore = aimPos, score
							end
						end
					end
				end
			end
		end
	end

	if best then
		local goal = CFrame.new(Camera.CFrame.Position, best)
		Camera.CFrame = Camera.CFrame:Lerp(goal, math.clamp(1 - S.smooth / 100, 0.03, 1))
	end
end

local lastTrigger = 0
local function stepTrigger()
	if not S.trigger or not mouse1click then return end
	if menu.IsOpen() then return end
	if os.clock() - lastTrigger < S.trigDelay / 1000 then return end

	local loc = UIS:GetMouseLocation()
	local ray = Camera:ViewportPointToRay(loc.X, loc.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * S.trigDist, params)
	if not hit then return end

	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	local plr = model and Players:GetPlayerFromCharacter(model)
	if plr and plr ~= LocalPlayer and (not S.teamcheck or isEnemy(plr)) then
		local _, hum = getChar(plr)
		if hum and hum.Health > 0 then
			lastTrigger = os.clock()
			pcall(mouse1click)
		end
	end
end

-- Hitbox --------------------------------------------------------------

local hitboxed = {}

local function restoreHitboxes()
	for plr, root in pairs(hitboxed) do
		if root and root.Parent then
			pcall(function()
				root.Size = Vector3.new(2, 2, 1)
				root.Transparency = 1
			end)
		end
		hitboxed[plr] = nil
	end
end

local function stepHitbox()
	if not S.hitbox then
		if next(hitboxed) then restoreHitboxes() end
		return
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and isEnemy(plr) then
			local char, _, root = getChar(plr)
			if char then
				root.Size = Vector3.new(S.hitSize, S.hitSize, S.hitSize)
				root.Transparency = S.hitTransp / 100
				root.CanCollide = false
				hitboxed[plr] = root
			end
		end
	end
end

-- Movement ------------------------------------------------------------

local was = { fly = false, speed = false, jump = false, walkOrig = 16, jumpOrig = 50 }
local lastSafe, lastCF, deathCF

local function stepMovement()
	local char, hum, root = getChar(LocalPlayer)
	if not char then return end

	if hum.Health > 0 then lastCF = root.CFrame end

	local flying = S.fly and K.fly
	if flying then
		local dir = Vector3.zero
		local cf = Camera.CFrame
		if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
		root.AssemblyLinearVelocity = dir.Magnitude > 0 and dir.Unit * S.flySpeed or Vector3.zero
	elseif was.fly then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	was.fly = flying

	if S.speed then
		if not was.speed then was.walkOrig = hum.WalkSpeed end
		hum.WalkSpeed = S.walk
		was.speed = true
	elseif was.speed then
		hum.WalkSpeed = was.walkOrig
		was.speed = false
	end

	if S.jumpOn then
		if not was.jump then was.jumpOrig = hum.JumpPower end
		hum.UseJumpPower = true
		hum.JumpPower = S.jumpPower
		was.jump = true
	elseif was.jump then
		hum.JumpPower = was.jumpOrig
		was.jump = false
	end

	if S.bhop and UIS:IsKeyDown(Enum.KeyCode.Space) and not UIS:GetFocusedTextBox()
		and hum.FloorMaterial ~= Enum.Material.Air then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	if S.antivoid then
		local voidY = Workspace.FallenPartsDestroyHeight + 100
		if hum.FloorMaterial ~= Enum.Material.Air and root.Position.Y > voidY then
			lastSafe = root.CFrame
		elseif root.Position.Y < voidY and lastSafe then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = lastSafe + Vector3.new(0, 5, 0)
		end
	end
end

local function stepNoclip()
	if not (S.noclip and K.noclip) then return end
	local char = LocalPlayer.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
		end
	end
end

-- World ---------------------------------------------------------------

local origLighting, origClock, origFov, origZoom
local origGravity = Workspace.Gravity
local gravityApplied = false

local function stepWorld()
	if S.fullbright then
		if not origLighting then
			origLighting = {
				Brightness = Lighting.Brightness,
				FogEnd = Lighting.FogEnd,
				GlobalShadows = Lighting.GlobalShadows,
				Ambient = Lighting.Ambient,
			}
		end
		Lighting.Brightness = 2
		Lighting.FogEnd = 1e6
		Lighting.GlobalShadows = false
		Lighting.Ambient = Color3.fromRGB(178, 178, 178)
	elseif origLighting then
		for k, v in pairs(origLighting) do Lighting[k] = v end
		origLighting = nil
	end

	if S.timeOn then
		if not origClock then origClock = Lighting.ClockTime end
		Lighting.ClockTime = S.timeVal
	elseif origClock then
		Lighting.ClockTime = origClock
		origClock = nil
	end

	if S.gravityOn then
		if not gravityApplied then origGravity = Workspace.Gravity end
		Workspace.Gravity = S.gravity
		gravityApplied = true
	elseif gravityApplied then
		Workspace.Gravity = origGravity
		gravityApplied = false
	end

	if S.zoomOn then
		if not origZoom then origZoom = LocalPlayer.CameraMaxZoomDistance end
		LocalPlayer.CameraMaxZoomDistance = S.zoom
	elseif origZoom then
		LocalPlayer.CameraMaxZoomDistance = origZoom
		origZoom = nil
	end
end

-- Teleport / spectate -------------------------------------------------

local sel = { player = nil, waypoint = "Start", wpName = "" }
local waypoints = {}

local function findPlayer(name)
	local p = name and Players:FindFirstChild(name)
	if p and p:IsA("Player") then return p end
	return nil
end

local function teleportTo(cf)
	local _, _, root = getChar(LocalPlayer)
	if root then root.CFrame = cf end
end

local function nearestEnemyRoot()
	local _, _, myRoot = getChar(LocalPlayer)
	if not myRoot then return nil end
	local best, bestD
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer and isEnemy(plr) then
			local char, hum, root = getChar(plr)
			if char and hum.Health > 0 then
				local d = (root.Position - myRoot.Position).Magnitude
				if bestD == nil or d < bestD then best, bestD = root, d end
			end
		end
	end
	return best
end

local spectating = false
local function stepSpectate()
	if S.spectate then
		local plr = findPlayer(sel.player)
		local hum
		if plr then
			local _, h = getChar(plr)
			hum = h
		end
		if hum then
			Camera.CameraSubject = hum
			spectating = true
		end
	elseif spectating then
		local _, myHum = getChar(LocalPlayer)
		if myHum then Camera.CameraSubject = myHum end
		spectating = false
	end
end

local wpFile = "PLHub/waypoints_" .. game.PlaceId .. ".json"

local function persistWaypoints()
	if not writefile then return end
	local out = {}
	for name, cf in pairs(waypoints) do
		if name ~= "Start" then
			local p = cf.Position
			out[name] = { p.X, p.Y, p.Z }
		end
	end
	pcall(function() writefile(wpFile, HttpService:JSONEncode(out)) end)
end

local function loadWaypoints()
	local names = {}
	if isfile and readfile then
		local ok, data = pcall(function()
			if isfile(wpFile) then return HttpService:JSONDecode(readfile(wpFile)) end
		end)
		if ok and type(data) == "table" then
			for name, p in pairs(data) do
				if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) and tonumber(p[3]) then
					waypoints[name] = CFrame.new(p[1], p[2], p[3])
					table.insert(names, name)
				end
			end
		end
	end
	table.sort(names)
	return names
end

-- Utility -------------------------------------------------------------

local function rejoin()
	if #Players:GetPlayers() <= 1 then
		TeleportService:Teleport(game.PlaceId, LocalPlayer)
	else
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
	end
end

local function serverHop()
	local ok, body = pcall(function()
		return game:HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId))
	end)
	if not ok then
		notify("Server list request failed")
		return
	end
	local okDecode, data = pcall(HttpService.JSONDecode, HttpService, body)
	if not okDecode or type(data) ~= "table" or not data.data then
		notify("Could not read server list")
		return
	end
	for _, s in ipairs(data.data) do
		if s.id ~= game.JobId and s.playing and s.maxPlayers and s.playing < s.maxPlayers then
			TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
			return
		end
	end
	notify("No open server found")
end

local function copyText(text, label)
	if setclipboard then
		pcall(setclipboard, tostring(text))
		notify("Copied " .. label)
	else
		notify("Clipboard not supported")
	end
end

-- Menu ----------------------------------------------------------------

local function toggle(sector, text, key, onChange)
	return sector.element("Toggle", text, { default = { Toggle = S[key] } }, function(v)
		S[key] = v.Toggle
		if onChange then onChange(v.Toggle) end
	end)
end

local function slider(sector, text, key, min, max, onChange)
	return sector.element("Slider", text, { default = { min = min, max = max, default = S[key] } }, function(v)
		S[key] = v.Slider
		if onChange then onChange(v.Slider) end
	end)
end

-- Combat
local combat = menu.new_tab(ICONS.combat)
local aimSection = combat.new_section("Aimbot")
local aimSector = aimSection.new_sector("Aimbot", "Left")

local aimToggle = toggle(aimSector, "Aimbot", "aimbot")
local aimKey = aimToggle:add_keybind(nil, function(kv) K.aimbot = kv.Active end)
aimKey:set_value({ Key = "MouseButton2", Type = "Hold", Active = false }, true)

aimSector.element("Dropdown", "Target part", { options = { "Head", "Torso", "Root" }, default = { Dropdown = "Head" } }, function(v)
	S.aimPart = v.Dropdown
end)
aimSector.element("Dropdown", "Target priority", { options = { "Crosshair", "Distance", "Health" }, default = { Dropdown = "Crosshair" } }, function(v)
	S.aimPriority = v.Dropdown
end)
slider(aimSector, "FOV radius", "fov", 20, 400)
slider(aimSector, "Smoothness", "smooth", 0, 95)
slider(aimSector, "Max distance", "aimDist", 50, 2000)
toggle(aimSector, "Team check", "teamcheck")
toggle(aimSector, "Visible check", "visible")
toggle(aimSector, "Draw FOV circle", "drawFov")

local predSector = aimSection.new_sector("Prediction", "Right")
toggle(predSector, "Prediction", "predict")
slider(predSector, "Lead time (ms)", "predictMs", 0, 200)

local assistSection = combat.new_section("Assist")
local trigSector = assistSection.new_sector("Triggerbot", "Left")
toggle(trigSector, "Triggerbot", "trigger")
slider(trigSector, "Delay (ms)", "trigDelay", 0, 300)
slider(trigSector, "Max distance", "trigDist", 50, 1500)

local hitSector = assistSection.new_sector("Hitbox", "Right")
toggle(hitSector, "Hitbox expander", "hitbox")
slider(hitSector, "Size", "hitSize", 2, 25)
slider(hitSector, "Transparency %", "hitTransp", 0, 100)

-- Visuals
local visuals = menu.new_tab(ICONS.visuals)
local espSection = visuals.new_section("ESP")
local espSector = espSection.new_sector("Players", "Left")

local espToggle = toggle(espSector, "ESP", "esp")
espToggle:add_color({ Color = S.espColor }, false, function(c) S.espColor = c.Color end)
toggle(espSector, "Names", "names")
toggle(espSector, "Distance", "dist")
toggle(espSector, "Health text", "health")
toggle(espSector, "Health bar", "healthBar")
toggle(espSector, "Boxes", "boxes")
toggle(espSector, "Skeleton", "skeleton")
toggle(espSector, "Tracers", "tracers")
toggle(espSector, "Head dot", "headDot")
toggle(espSector, "Team colors", "teamColors")
toggle(espSector, "Enemies only", "enemiesOnly")
slider(espSector, "Max distance", "espDist", 100, 3000)

local worldSector = espSection.new_sector("World", "Right")
toggle(worldSector, "Fullbright", "fullbright")
toggle(worldSector, "FOV changer", "fovOn", function(on)
	if on then
		origFov = Camera.FieldOfView
	else
		Camera.FieldOfView = origFov or 70
	end
end)
slider(worldSector, "Field of view", "fovVal", 40, 120)
toggle(worldSector, "Time of day", "timeOn")
slider(worldSector, "Hour", "timeVal", 0, 24)
toggle(worldSector, "Camera zoom", "zoomOn")
slider(worldSector, "Max zoom", "zoom", 10, 500)

local overlaySection = visuals.new_section("Overlay")
local radarSector = overlaySection.new_sector("Radar", "Left")
toggle(radarSector, "Radar", "radar")
slider(radarSector, "Radar size", "radarSize", 50, 160)
slider(radarSector, "Radar range", "radarRange", 50, 1000)

local crossSector = overlaySection.new_sector("Crosshair", "Right")
toggle(crossSector, "Custom crosshair", "crosshair")
slider(crossSector, "Line size", "chSize", 2, 30)
slider(crossSector, "Gap", "chGap", 0, 20)

-- Movement
local movement = menu.new_tab(ICONS.movement)
local moveSection = movement.new_section("Movement")
local flightSector = moveSection.new_sector("Flight", "Left")

local flyToggle = toggle(flightSector, "Fly", "fly")
local flyKey = flyToggle:add_keybind(nil, function(kv) K.fly = kv.Active end)
flyKey:set_value({ Key = "F", Type = "Toggle", Active = false }, true)
slider(flightSector, "Fly speed", "flySpeed", 10, 200)

local noclipToggle = toggle(flightSector, "Noclip", "noclip")
local noclipKey = noclipToggle:add_keybind(nil, function(kv) K.noclip = kv.Active end)
noclipKey:set_value({ Key = "N", Type = "Toggle", Active = false }, true)

local safetySector = moveSection.new_sector("Safety", "Left")
toggle(safetySector, "Anti-void", "antivoid")
toggle(safetySector, "Respawn at death spot", "respawnBack")

local groundSector = moveSection.new_sector("Ground", "Right")
toggle(groundSector, "Speed", "speed")
slider(groundSector, "Walk speed", "walk", 16, 120)
toggle(groundSector, "Jump power", "jumpOn")
slider(groundSector, "Power", "jumpPower", 50, 300)
toggle(groundSector, "Gravity", "gravityOn")
slider(groundSector, "Gravity value", "gravity", 0, 196)
toggle(groundSector, "Bunny hop (hold Space)", "bhop")
toggle(groundSector, "Infinite jump", "infjump")

local tpSection = movement.new_section("Teleport")
local plrSector = tpSection.new_sector("Players", "Left")

local initial = {}
for _, p in ipairs(Players:GetPlayers()) do
	if p ~= LocalPlayer then table.insert(initial, p.Name) end
end
if #initial == 0 then table.insert(initial, "(none)") end
sel.player = initial[1]

local playerList = plrSector.element("Scroll", "Players", { options = initial, scrollsize = 5 }, function(v)
	sel.player = v.Scroll
end)
plrSector.element("Button", "Teleport to player", {}, function()
	local plr = findPlayer(sel.player)
	local root
	if plr then
		local _, _, r = getChar(plr)
		root = r
	end
	if root then
		teleportTo(root.CFrame * CFrame.new(0, 0, 3))
	else
		notify("Player not available")
	end
end)
plrSector.element("Button", "Teleport to nearest enemy", {}, function()
	local root = nearestEnemyRoot()
	if root then
		teleportTo(root.CFrame * CFrame.new(0, 0, 3))
	else
		notify("No enemy found")
	end
end)
toggle(plrSector, "Spectate selected", "spectate")
toggle(plrSector, "Ctrl + click teleport", "clicktp")

local wpSector = tpSection.new_sector("Waypoints", "Right")
wpSector.element("TextBox", "Waypoint name", {}, function(v) sel.wpName = v.Text end)

local wpCount = 0
local function saveWaypoint(name)
	local _, _, root = getChar(LocalPlayer)
	if not root then
		notify("No character")
		return false
	end
	waypoints[name] = root.CFrame
	return true
end

local wpOptions = { "Start" }
for _, name in ipairs(loadWaypoints()) do table.insert(wpOptions, name) end
saveWaypoint("Start")

local wpList = wpSector.element("Scroll", "Waypoints", { options = wpOptions, scrollsize = 4 }, function(v)
	sel.waypoint = v.Scroll
end)
wpSector.element("Button", "Save position", {}, function()
	local name = sel.wpName
	if name == "" or name == nil then
		wpCount += 1
		name = "WP" .. wpCount
	end
	if saveWaypoint(name) then
		wpList:add_value(name)
		persistWaypoints()
		notify("Saved " .. name)
	end
end)
wpSector.element("Button", "Teleport to waypoint", {}, function()
	local cf = waypoints[sel.waypoint]
	if cf then teleportTo(cf) else notify("No such waypoint") end
end)

-- Misc
local misc = menu.new_tab(ICONS.misc)
local miscSection = misc.new_section("Misc")
local playerSector = miscSection.new_sector("Player", "Left")
toggle(playerSector, "Anti-AFK", "antiafk")
toggle(playerSector, "Auto rejoin on kick", "autoRejoin")
playerSector.element("Button", "Reset character", {}, function()
	local _, hum = getChar(LocalPlayer)
	if hum then hum.Health = 0 end
end)
playerSector.element("Button", "Selected player info", {}, function()
	local plr = findPlayer(sel.player)
	if not plr then
		notify("Player not available")
		return
	end
	local char, hum, root = getChar(plr)
	local _, _, myRoot = getChar(LocalPlayer)
	if char then
		local d = myRoot and math.floor((myRoot.Position - root.Position).Magnitude) or 0
		notify(("%s | %s | HP %d | %dm"):format(plr.DisplayName, plr.Team and plr.Team.Name or "No team", math.floor(hum.Health), d))
	else
		notify(plr.DisplayName .. " | not spawned")
	end
end)

local perfSector = miscSection.new_sector("Performance", "Left")
toggle(perfSector, "FPS cap", "fpsOn", function(on)
	if setfpscap then pcall(setfpscap, on and S.fps or 60) end
end)
slider(perfSector, "FPS limit", "fps", 30, 360, function()
	if S.fpsOn and setfpscap then pcall(setfpscap, S.fps) end
end)

local serverSector = miscSection.new_sector("Server", "Right")
serverSector.element("Button", "Rejoin", {}, rejoin)
serverSector.element("Button", "Server hop", {}, serverHop)
serverSector.element("Button", "Copy JobId", {}, function() copyText(game.JobId, "JobId") end)
serverSector.element("Button", "Copy PlaceId", {}, function() copyText(game.PlaceId, "PlaceId") end)

local cfgSector = miscSection.new_sector("Config", "Right")
local cfgName = "default"
cfgSector.element("TextBox", "Config name", { default = "default" }, function(v)
	cfgName = v.Text
end)
cfgSector.element("Button", "Save config", {}, function()
	local ok = pcall(menu.save_cfg, cfgName)
	notify(ok and ("Saved " .. cfgName) or "Save failed")
end)
cfgSector.element("Button", "Load config", {}, function()
	local ok = pcall(menu.load_cfg, cfgName)
	notify(ok and ("Loaded " .. cfgName) or "Load failed")
end)

local unload

cfgSector.element("Button", "Unload", {}, function() unload() end)

-- Wiring --------------------------------------------------------------

track(RunService.Heartbeat:Connect(function()
	pcall(stepMovement)
	pcall(stepHitbox)
	pcall(stepWorld)
	pcall(stepSpectate)
	pcall(stepTrigger)
end))

track(RunService.Stepped:Connect(function()
	pcall(stepNoclip)
end))

track(RunService.RenderStepped:Connect(function()
	Camera = Workspace.CurrentCamera
	if S.fovOn then Camera.FieldOfView = S.fovVal end
	pcall(stepESP)
	pcall(stepAimbot)
	pcall(stepRadar)
	pcall(stepCrosshair)
end))

track(UIS.JumpRequest:Connect(function()
	if not S.infjump then return end
	local _, hum = getChar(LocalPlayer)
	if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end))

track(UIS.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not S.clicktp or not UIS:IsKeyDown(Enum.KeyCode.LeftControl) then return end
	if menu.IsOpen() then return end

	local loc = UIS:GetMouseLocation()
	local ray = Camera:ViewportPointToRay(loc.X, loc.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
	if hit then
		teleportTo(CFrame.new(hit.Position + Vector3.new(0, 3, 0)))
	end
end))

track(LocalPlayer.Idled:Connect(function()
	if not S.antiafk then return end
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end))

local function hookCharacter(char)
	local cf = deathCF
	deathCF = nil

	local hum = char:WaitForChild("Humanoid", 5)
	if not hum then return end
	hum.Died:Connect(function()
		deathCF = lastCF
	end)

	if S.respawnBack and cf then
		local root = char:WaitForChild("HumanoidRootPart", 5)
		if root then
			task.wait(0.4)
			root.CFrame = cf
		end
	end
end

track(LocalPlayer.CharacterAdded:Connect(function(char)
	task.spawn(hookCharacter, char)
end))
if LocalPlayer.Character then
	task.spawn(hookCharacter, LocalPlayer.Character)
end

task.spawn(function()
	local ok = pcall(function()
		local gui = CoreGui:WaitForChild("RobloxPromptGui", 10)
		local overlay = gui and gui:WaitForChild("promptOverlay", 10)
		if overlay then
			track(overlay.ChildAdded:Connect(function(child)
				if S.autoRejoin and child.Name == "ErrorPrompt" then
					task.wait(1.5)
					pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
				end
			end))
		end
	end)
	if not ok then notify("Auto rejoin hook unavailable") end
end)

track(Players.PlayerAdded:Connect(function(plr)
	pcall(function() playerList:add_value(plr.Name) end)
end))

track(Players.PlayerRemoving:Connect(function(plr)
	destroyESP(plr)
	hitboxed[plr] = nil
	local dot = radar.dots[plr]
	if dot then
		pcall(function() dot:Remove() end)
		radar.dots[plr] = nil
	end
end))

unload = function()
	S.hitbox, S.fullbright, S.timeOn, S.gravityOn, S.zoomOn = false, false, false, false, false
	S.spectate, S.speed, S.jumpOn, S.fly, S.esp = false, false, false, false, false
	S.aimbot, S.trigger, S.radar, S.crosshair, S.bhop, S.antivoid = false, false, false, false, false, false

	pcall(restoreHitboxes)
	pcall(stepMovement)
	pcall(stepWorld)
	pcall(stepSpectate)
	pcall(stepRadar)
	pcall(stepCrosshair)

	if S.fovOn then
		S.fovOn = false
		Camera.FieldOfView = origFov or 70
	end
	if S.fpsOn and setfpscap then
		S.fpsOn = false
		pcall(setfpscap, 60)
	end

	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	connections = {}

	for plr in pairs(esp) do destroyESP(plr) end
	pcall(function() espFolder:Destroy() end)

	for _, d in pairs(radar.dots) do pcall(function() d:Remove() end) end
	for _, k in ipairs({ "bg", "ring", "me" }) do
		if radar[k] then pcall(function() radar[k]:Remove() end) end
	end
	for _, l in ipairs(crossLines) do pcall(function() l:Remove() end) end
	if fovCircle then pcall(function() fovCircle:Remove() end) end
	if menuGui then pcall(function() menuGui:Destroy() end) end

	env.PLHubUnload = nil
end

-- PL Hub v3.1 add-on
-- Paste this whole block directly ABOVE the line:   env.PLHubUnload = unload
-- It uses the locals already in your script (S, K, menu, toggle, slider, track, getChar, isEnemy, notify, ...)
-- and wraps unload so everything here is cleaned up with the rest of the hub.

do
	S.autoGuns, S.antiRagdoll, S.antiFling, S.weaponEsp, S.joinNotify = false, false, false, false, true
	S.freecam, S.freecamSpeed = false, 60
	K.freecam = false

	local ITEMS = { "M9", "Remington 870", "AK-47", "Crude Knife" }
	local TEAM_BUTTONS = {
		{ "Join guards", "Bright blue" },
		{ "Join inmates", "Bright orange" },
		{ "Go neutral", "Medium stone grey" },
	}

	-- Prison actions -------------------------------------------------

	local function giveItem(name)
		return pcall(function()
			local items = Workspace:WaitForChild("Prison_ITEMS", 2)
			local remote = Workspace:WaitForChild("Remote", 2):WaitForChild("ItemHandler", 2)
			local holder = items.giver:FindFirstChild(name) or items.single:FindFirstChild(name)
			local pickup = holder and holder:FindFirstChild("ITEMPICKUP")
			assert(pickup, "item missing")
			remote:InvokeServer(pickup)
		end)
	end

	local function giveAll()
		task.spawn(function()
			local got = 0
			for _, name in ipairs(ITEMS) do
				if giveItem(name) then got += 1 end
				task.wait(0.2)
			end
			notify(("Got %d/%d items"):format(got, #ITEMS))
		end)
	end

	local function setTeam(teamColor)
		local ok = pcall(function()
			Workspace.Remote.TeamEvent:FireServer(teamColor)
		end)
		if not ok then notify("Team change failed") end
	end

	-- Menu -----------------------------------------------------------

	local extras = menu.new_tab(ICONS.misc)
	local prison = extras.new_section("Prison")

	local gunSector = prison.new_sector("Weapons", "Left")
	for _, name in ipairs(ITEMS) do
		gunSector.element("Button", "Get " .. name, {}, function()
			task.spawn(function()
				if not giveItem(name) then notify(name .. " unavailable") end
			end)
		end)
	end
	gunSector.element("Button", "Get all weapons", {}, giveAll)
	toggle(gunSector, "Auto-give on respawn", "autoGuns")

	local teamSector = prison.new_sector("Teams", "Right")
	for _, entry in ipairs(TEAM_BUTTONS) do
		teamSector.element("Button", entry[1], {}, function() setTeam(entry[2]) end)
	end

	local defense = extras.new_section("Defense")
	local defSector = defense.new_sector("Character", "Left")
	toggle(defSector, "Anti-ragdoll", "antiRagdoll")
	toggle(defSector, "Anti-fling", "antiFling")

	local viewSector = defense.new_sector("View", "Right")
	toggle(viewSector, "Held weapon ESP", "weaponEsp")
	toggle(viewSector, "Join / leave alerts", "joinNotify")
	local fcToggle = toggle(viewSector, "Freecam", "freecam")
	local fcKey = fcToggle:add_keybind(nil, function(kv) K.freecam = kv.Active end)
	fcKey:set_value({ Key = "G", Type = "Toggle", Active = false }, true)
	slider(viewSector, "Freecam speed", "freecamSpeed", 10, 300)

	-- Anti-ragdoll / anti-fling --------------------------------------

	track(RunService.Heartbeat:Connect(function()
		local _, hum, root = getChar(LocalPlayer)
		if not hum then return end

		if S.antiRagdoll then
			local st = hum:GetState()
			if st == Enum.HumanoidStateType.FallingDown
				or st == Enum.HumanoidStateType.Ragdoll
				or st == Enum.HumanoidStateType.PlatformStanding then
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			if hum.PlatformStand then hum.PlatformStand = false end
		end

		if S.antiFling and not (S.fly and K.fly) then
			local v = root.AssemblyLinearVelocity
			local flat = Vector3.new(v.X, 0, v.Z).Magnitude
			if flat > 200 or root.AssemblyAngularVelocity.Magnitude > 60 then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end))

	-- Held weapon ESP ------------------------------------------------

	local weaponLabels = {}

	local function removeLabel(plr)
		local t = weaponLabels[plr]
		if t then pcall(function() t:Remove() end) end
		weaponLabels[plr] = nil
	end

	track(RunService.RenderStepped:Connect(function()
		if not hasDrawing then return end
		local cam = Workspace.CurrentCamera
		local _, _, myRoot = getChar(LocalPlayer)

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer then
				local char, _, root = getChar(plr)
				local tool = char and char:FindFirstChildOfClass("Tool")
				local show = S.weaponEsp and tool ~= nil and (not S.enemiesOnly or isEnemy(plr))
					and (not myRoot or (myRoot.Position - root.Position).Magnitude <= S.espDist)
				local label = weaponLabels[plr]

				if show then
					local pos, onScreen = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3.6, 0))
					if onScreen then
						if not label then
							label = newDrawing("Text", { Size = 13, Center = true, Outline = true, Visible = false })
							weaponLabels[plr] = label
						end
						if label then
							label.Text = tool.Name
							label.Position = Vector2.new(pos.X, pos.Y)
							label.Color = S.teamColors and plr.TeamColor.Color or S.espColor
							label.Visible = true
						end
					elseif label then
						label.Visible = false
					end
				elseif label then
					label.Visible = false
				end
			end
		end
	end))

	-- Freecam --------------------------------------------------------

	local fc = { on = false, yaw = 0, pitch = 0, pos = Vector3.zero, camType = nil, root = nil, anchored = false }

	local function stopFreecam()
		if not fc.on then return end
		fc.on = false
		UIS.MouseBehavior = Enum.MouseBehavior.Default
		Workspace.CurrentCamera.CameraType = fc.camType or Enum.CameraType.Custom
		if fc.root and fc.root.Parent then fc.root.Anchored = fc.anchored end
		fc.root = nil
	end

	local function startFreecam()
		local _, _, root = getChar(LocalPlayer)
		local cam = Workspace.CurrentCamera
		fc.on = true
		fc.camType = cam.CameraType
		fc.pos = cam.CFrame.Position
		fc.pitch, fc.yaw = cam.CFrame:ToOrientation()
		fc.root = root
		if root then
			fc.anchored = root.Anchored
			root.Anchored = true
		end
		cam.CameraType = Enum.CameraType.Scriptable
	end

	track(RunService.RenderStepped:Connect(function(dt)
		local want = S.freecam and K.freecam
		if want and not fc.on then
			startFreecam()
		elseif not want and fc.on then
			stopFreecam()
		end
		if not fc.on then return end

		local cam = Workspace.CurrentCamera
		if menu.IsOpen() then
			UIS.MouseBehavior = Enum.MouseBehavior.Default
		else
			UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
			local d = UIS:GetMouseDelta()
			fc.yaw -= math.rad(d.X * 0.25)
			fc.pitch = math.clamp(fc.pitch - math.rad(d.Y * 0.25), -1.5, 1.5)
		end

		local rot = CFrame.fromOrientation(fc.pitch, fc.yaw, 0)
		local dir = Vector3.zero
		if not UIS:GetFocusedTextBox() then
			if UIS:IsKeyDown(Enum.KeyCode.W) then dir += rot.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= rot.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= rot.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.D) then dir += rot.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
			if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
		end
		local boost = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1
		if dir.Magnitude > 0 then
			fc.pos += dir.Unit * S.freecamSpeed * boost * dt
		end
		cam.CFrame = CFrame.new(fc.pos) * rot
	end))

	-- Respawn / join / leave -----------------------------------------

	track(LocalPlayer.CharacterAdded:Connect(function()
		if not S.autoGuns then return end
		task.delay(2, function()
			if S.autoGuns then giveAll() end
		end)
	end))

	track(Players.PlayerAdded:Connect(function(plr)
		if S.joinNotify then notify(plr.DisplayName .. " joined") end
	end))

	track(Players.PlayerRemoving:Connect(function(plr)
		removeLabel(plr)
		if S.joinNotify then notify(plr.DisplayName .. " left") end
	end))

	-- Cleanup --------------------------------------------------------

	local baseUnload = unload
	unload = function()
		S.freecam, S.weaponEsp, S.antiRagdoll, S.antiFling, S.autoGuns = false, false, false, false, false
		pcall(stopFreecam)
		for plr in pairs(weaponLabels) do removeLabel(plr) end
		baseUnload()
	end
end

-- Paste this whole block directly ABOVE the line:   env.PLHubUnload = unload
-- No new tabs. It adds sections to Combat, Visuals, Movement and Misc using the locals your
-- script already has (S, K, menu, combat, visuals, movement, misc, toggle, slider, track, ...).
-- It wraps unload, so the Unload button cleans everything here up too.

do
	local defaults = {
		rapidFire = false, rapidCps = 12,
		targetHud = false, snapLine = false,
		weaponEsp = false, offscreen = false, arrowRadius = 180, itemEsp = false,
		noFog = false,
		freecam = false, freecamSpeed = 60,
		sprint = false, sprintSpeed = 60,
		antiRagdoll = false, antiFling = false,
		autoGuns = false, joinNotify = true,
	}
	for k, v in pairs(defaults) do S[k] = v end
	K.freecam = false

	local ITEMS = { "M9", "Remington 870", "AK-47", "Crude Knife" }
	local TEAM_BUTTONS = {
		{ "Join guards", "Bright blue" },
		{ "Join inmates", "Bright orange" },
		{ "Go neutral", "Medium stone grey" },
	}

	-- Prison actions ---------------------------------------------------

	local function giveItem(name)
		return pcall(function()
			local items = Workspace:WaitForChild("Prison_ITEMS", 2)
			local remote = Workspace:WaitForChild("Remote", 2):WaitForChild("ItemHandler", 2)
			local holder = items.giver:FindFirstChild(name) or items.single:FindFirstChild(name)
			local pickup = holder and holder:FindFirstChild("ITEMPICKUP")
			assert(pickup, "item missing")
			remote:InvokeServer(pickup)
		end)
	end

	local function giveAll()
		task.spawn(function()
			local got = 0
			for _, name in ipairs(ITEMS) do
				if giveItem(name) then got += 1 end
				task.wait(0.2)
			end
			notify(("Got %d/%d items"):format(got, #ITEMS))
		end)
	end

	local function setTeam(teamColor)
		local ok = pcall(function()
			Workspace.Remote.TeamEvent:FireServer(teamColor)
		end)
		if not ok then notify("Team change failed") end
	end

	-- Menu: Combat -----------------------------------------------------

	local combatExtra = combat.new_section("Extras")

	local rapidSector = combatExtra.new_sector("Rapid fire", "Left")
	toggle(rapidSector, "Rapid fire (hold M1)", "rapidFire")
	slider(rapidSector, "Clicks per second", "rapidCps", 2, 30)

	local hudSector = combatExtra.new_sector("Target info", "Right")
	toggle(hudSector, "Target HUD", "targetHud")
	toggle(hudSector, "Snap line to target", "snapLine")

	-- Menu: Visuals ----------------------------------------------------

	local visualsExtra = visuals.new_section("Extras")

	local espPlus = visualsExtra.new_sector("ESP+", "Left")
	toggle(espPlus, "Held weapon", "weaponEsp")
	toggle(espPlus, "Off-screen arrows", "offscreen")
	slider(espPlus, "Arrow radius", "arrowRadius", 80, 400)
	toggle(espPlus, "Pickup ESP", "itemEsp")

	local viewPlus = visualsExtra.new_sector("View", "Right")
	toggle(viewPlus, "Remove fog", "noFog")
	local fcToggle = toggle(viewPlus, "Freecam", "freecam")
	local fcKey = fcToggle:add_keybind(nil, function(kv) K.freecam = kv.Active end)
	fcKey:set_value({ Key = "G", Type = "Toggle", Active = false }, true)
	slider(viewPlus, "Freecam speed", "freecamSpeed", 10, 300)

	-- Menu: Movement ---------------------------------------------------

	local moveExtra = movement.new_section("Extras")

	local sprintSector = moveExtra.new_sector("Sprint", "Left")
	toggle(sprintSector, "Sprint (hold Shift)", "sprint")
	slider(sprintSector, "Sprint speed", "sprintSpeed", 20, 150)

	local defenseSector = moveExtra.new_sector("Defense", "Right")
	toggle(defenseSector, "Anti-ragdoll", "antiRagdoll")
	toggle(defenseSector, "Anti-fling", "antiFling")

	-- Menu: Misc -------------------------------------------------------

	local prisonSection = misc.new_section("Prison")

	local gunSector = prisonSection.new_sector("Weapons", "Left")
	for _, name in ipairs(ITEMS) do
		gunSector.element("Button", "Get " .. name, {}, function()
			task.spawn(function()
				if not giveItem(name) then notify(name .. " unavailable") end
			end)
		end)
	end
	gunSector.element("Button", "Get all weapons", {}, giveAll)
	toggle(gunSector, "Auto-give on respawn", "autoGuns")

	local teamSector = prisonSection.new_sector("Teams", "Right")
	for _, entry in ipairs(TEAM_BUTTONS) do
		teamSector.element("Button", entry[1], {}, function() setTeam(entry[2]) end)
	end

	local toolsSector = prisonSection.new_sector("Tools", "Right")
	toggle(toolsSector, "Join / leave alerts", "joinNotify")
	toolsSector.element("Button", "Copy position", {}, function()
		local _, _, root = getChar(LocalPlayer)
		if not root then
			notify("No character")
			return
		end
		local p = root.Position
		copyText(("%.1f, %.1f, %.1f"):format(p.X, p.Y, p.Z), "position")
	end)

	-- Heartbeat: rapid fire, sprint, anti-ragdoll, anti-fling ----------

	local lastShot = 0

	track(RunService.Heartbeat:Connect(function()
		if S.rapidFire and mouse1click and not menu.IsOpen() and not UIS:GetFocusedTextBox()
			and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			local now = os.clock()
			if now - lastShot >= 1 / S.rapidCps then
				lastShot = now
				pcall(mouse1click)
			end
		end

		local _, hum, root = getChar(LocalPlayer)
		if not hum then return end
		local flying = S.fly and K.fly

		if S.sprint and not flying and not UIS:GetFocusedTextBox()
			and UIS:IsKeyDown(Enum.KeyCode.LeftShift) then
			local md = hum.MoveDirection
			if md.Magnitude > 0 then
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(md.X * S.sprintSpeed, v.Y, md.Z * S.sprintSpeed)
			end
		end

		if S.antiRagdoll then
			local st = hum:GetState()
			if st == Enum.HumanoidStateType.FallingDown
				or st == Enum.HumanoidStateType.Ragdoll
				or st == Enum.HumanoidStateType.PlatformStanding then
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			if hum.PlatformStand then hum.PlatformStand = false end
		end

		if S.antiFling and not flying then
			local v = root.AssemblyLinearVelocity
			local flat = Vector3.new(v.X, 0, v.Z).Magnitude
			if flat > math.max(200, S.sprintSpeed + 60) or root.AssemblyAngularVelocity.Magnitude > 60 then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end))

	-- Fog --------------------------------------------------------------

	local fogOrig
	local atmosphereOrig

	local function restoreFog()
		if fogOrig then
			Lighting.FogEnd = fogOrig
			fogOrig = nil
		end
		local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmo and atmosphereOrig then
			atmo.Density = atmosphereOrig
		end
		atmosphereOrig = nil
	end

	local function stepFog()
		if S.noFog then
			if not fogOrig then fogOrig = Lighting.FogEnd end
			Lighting.FogEnd = 1e6
			local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
			if atmo then
				if not atmosphereOrig then atmosphereOrig = atmo.Density end
				atmo.Density = 0
			end
		elseif fogOrig or atmosphereOrig then
			restoreFog()
		end
	end

	-- Drawing objects --------------------------------------------------

	local hudText = newDrawing("Text", { Size = 15, Center = true, Outline = true, Color = Color3.new(1, 1, 1), Visible = false })
	local snapLine = newDrawing("Line", { Thickness = 1, Color = Color3.fromRGB(84, 101, 255), Visible = false })
	local weaponLabels = {}
	local arrows = {}
	local pickupLabels = {}
	local pickups = {}
	local lastPickupScan = -math.huge

	local function removeFor(plr)
		local t = weaponLabels[plr]
		if t then pcall(function() t:Remove() end) end
		weaponLabels[plr] = nil
		local a = arrows[plr]
		if a then pcall(function() a:Remove() end) end
		arrows[plr] = nil
	end

	local function closestToCrosshair(cam, myRoot)
		local center = cam.ViewportSize / 2
		local best, bestD
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer and (not S.teamcheck or isEnemy(plr)) then
				local char, hum, root = getChar(plr)
				if char and hum.Health > 0 then
					local head = char:FindFirstChild("Head") or root
					local p, on = cam:WorldToViewportPoint(head.Position)
					if on then
						local screen = Vector2.new(p.X, p.Y)
						local d = (screen - center).Magnitude
						local worldD = myRoot and (myRoot.Position - root.Position).Magnitude or 0
						if d <= S.fov and worldD <= S.aimDist and (bestD == nil or d < bestD) then
							best = { plr = plr, hum = hum, screen = screen, dist = worldD }
							bestD = d
						end
					end
				end
			end
		end
		return best
	end

	local function stepTargetInfo(cam, myRoot)
		local want = S.targetHud or S.snapLine
		local t = want and closestToCrosshair(cam, myRoot) or nil
		local center = cam.ViewportSize / 2

		if hudText then
			if t and S.targetHud then
				hudText.Text = ("%s | HP %d | %dm"):format(t.plr.DisplayName, math.floor(t.hum.Health), math.floor(t.dist))
				hudText.Position = Vector2.new(center.X, center.Y + S.fov + 12)
				hudText.Visible = true
			else
				hudText.Visible = false
			end
		end
		if snapLine then
			if t and S.snapLine then
				snapLine.From = center
				snapLine.To = t.screen
				snapLine.Visible = true
			else
				snapLine.Visible = false
			end
		end
	end

	local function stepPlayerOverlays(cam, myRoot)
		local center = cam.ViewportSize / 2

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer then
				local char, _, root = getChar(plr)
				local dist = (char and myRoot) and (myRoot.Position - root.Position).Magnitude or 0
				local allowed = char ~= nil and dist <= S.espDist and (not S.enemiesOnly or isEnemy(plr))
				local color = S.teamColors and plr.TeamColor.Color or S.espColor

				local label = weaponLabels[plr]
				local tool = (allowed and S.weaponEsp) and char:FindFirstChildOfClass("Tool") or nil
				if tool then
					local pos, on = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3.6, 0))
					if on then
						if not label then
							label = newDrawing("Text", { Size = 13, Center = true, Outline = true, Visible = false })
							weaponLabels[plr] = label
						end
						if label then
							label.Text = tool.Name
							label.Position = Vector2.new(pos.X, pos.Y)
							label.Color = color
							label.Visible = true
						end
					elseif label then
						label.Visible = false
					end
				elseif label then
					label.Visible = false
				end

				local arrow = arrows[plr]
				local showArrow = false
				if allowed and S.offscreen then
					local _, on = cam:WorldToViewportPoint(root.Position)
					if not on then
						if not arrow then
							arrow = newDrawing("Triangle", { Filled = true, Visible = false })
							arrows[plr] = arrow
						end
						if arrow then
							local rel = cam.CFrame:PointToObjectSpace(root.Position)
							local dir = Vector2.new(rel.X, rel.Z)
							dir = dir.Magnitude > 0.001 and dir.Unit or Vector2.new(0, -1)
							local perp = Vector2.new(-dir.Y, dir.X)
							local p = center + dir * S.arrowRadius
							arrow.PointA = p + dir * 12
							arrow.PointB = p - dir * 6 + perp * 8
							arrow.PointC = p - dir * 6 - perp * 8
							arrow.Color = color
							arrow.Visible = true
							showArrow = true
						end
					end
				end
				if arrow and not showArrow then arrow.Visible = false end
			end
		end
	end

	local function scanPickups()
		pickups = {}
		local ok, giver = pcall(function() return Workspace.Prison_ITEMS.giver end)
		if not ok or not giver then return end
		for _, item in ipairs(giver:GetChildren()) do
			local part = item:FindFirstChild("ITEMPICKUP")
			if part and part:IsA("BasePart") then
				table.insert(pickups, { name = item.Name, part = part })
			end
		end
	end

	local function stepPickups(cam, myRoot)
		if not S.itemEsp then
			for _, l in pairs(pickupLabels) do l.Visible = false end
			return
		end
		if os.clock() - lastPickupScan > 5 then
			lastPickupScan = os.clock()
			scanPickups()
		end
		for i, entry in ipairs(pickups) do
			local label = pickupLabels[i]
			if not label then
				label = newDrawing("Text", { Size = 13, Center = true, Outline = true, Color = Color3.fromRGB(255, 220, 90), Visible = false })
				pickupLabels[i] = label
			end
			if label then
				if entry.part.Parent then
					local pos, on = cam:WorldToViewportPoint(entry.part.Position)
					if on then
						local d = myRoot and math.floor((myRoot.Position - entry.part.Position).Magnitude) or 0
						label.Text = ("%s [%dm]"):format(entry.name, d)
						label.Position = Vector2.new(pos.X, pos.Y)
						label.Visible = true
					else
						label.Visible = false
					end
				else
					label.Visible = false
				end
			end
		end
		for i = #pickups + 1, #pickupLabels do
			if pickupLabels[i] then pickupLabels[i].Visible = false end
		end
	end

	-- Freecam ----------------------------------------------------------

	local fc = { on = false, yaw = 0, pitch = 0, pos = Vector3.zero, camType = nil, root = nil, anchored = false }

	local function stopFreecam()
		if not fc.on then return end
		fc.on = false
		UIS.MouseBehavior = Enum.MouseBehavior.Default
		Workspace.CurrentCamera.CameraType = fc.camType or Enum.CameraType.Custom
		if fc.root and fc.root.Parent then fc.root.Anchored = fc.anchored end
		fc.root = nil
	end

	local function startFreecam()
		local _, _, root = getChar(LocalPlayer)
		local cam = Workspace.CurrentCamera
		fc.on = true
		fc.camType = cam.CameraType
		fc.pos = cam.CFrame.Position
		fc.pitch, fc.yaw = cam.CFrame:ToOrientation()
		fc.root = root
		if root then
			fc.anchored = root.Anchored
			root.Anchored = true
		end
		cam.CameraType = Enum.CameraType.Scriptable
	end

	local function stepFreecam(cam, dt)
		local want = S.freecam and K.freecam
		if want and not fc.on then
			startFreecam()
		elseif not want and fc.on then
			stopFreecam()
		end
		if not fc.on then return end

		if menu.IsOpen() then
			UIS.MouseBehavior = Enum.MouseBehavior.Default
		else
			UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
			local d = UIS:GetMouseDelta()
			fc.yaw -= math.rad(d.X * 0.25)
			fc.pitch = math.clamp(fc.pitch - math.rad(d.Y * 0.25), -1.5, 1.5)
		end

		local rot = CFrame.fromOrientation(fc.pitch, fc.yaw, 0)
		local dir = Vector3.zero
		if not UIS:GetFocusedTextBox() then
			if UIS:IsKeyDown(Enum.KeyCode.W) then dir += rot.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= rot.LookVector end
			if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= rot.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.D) then dir += rot.RightVector end
			if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
			if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
		end
		local boost = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1
		if dir.Magnitude > 0 then
			fc.pos += dir.Unit * S.freecamSpeed * boost * dt
		end
		cam.CFrame = CFrame.new(fc.pos) * rot
	end

	-- Render loop ------------------------------------------------------

	track(RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		local _, _, myRoot = getChar(LocalPlayer)
		pcall(stepFog)
		if hasDrawing then
			pcall(stepTargetInfo, cam, myRoot)
			pcall(stepPlayerOverlays, cam, myRoot)
			pcall(stepPickups, cam, myRoot)
		end
		pcall(stepFreecam, cam, dt)
	end))

	-- Events -----------------------------------------------------------

	track(LocalPlayer.CharacterAdded:Connect(function()
		if not S.autoGuns then return end
		task.delay(2, function()
			if S.autoGuns then giveAll() end
		end)
	end))

	track(Players.PlayerAdded:Connect(function(plr)
		if S.joinNotify then notify(plr.DisplayName .. " joined") end
	end))

	track(Players.PlayerRemoving:Connect(function(plr)
		removeFor(plr)
		if S.joinNotify then notify(plr.DisplayName .. " left") end
	end))

	-- Cleanup ----------------------------------------------------------

	local baseUnload = unload
	unload = function()
		S.rapidFire, S.sprint, S.antiRagdoll, S.antiFling = false, false, false, false
		S.weaponEsp, S.offscreen, S.itemEsp, S.noFog, S.freecam, S.autoGuns = false, false, false, false, false, false
		S.targetHud, S.snapLine = false, false

		pcall(stopFreecam)
		pcall(restoreFog)
		for plr in pairs(weaponLabels) do removeFor(plr) end
		for plr in pairs(arrows) do removeFor(plr) end
		for _, l in pairs(pickupLabels) do pcall(function() l:Remove() end) end
		pickupLabels = {}
		if hudText then pcall(function() hudText:Remove() end) end
		if snapLine then pcall(function() snapLine:Remove() end) end

		baseUnload()
	end
end

env.PLHubUnload = unload
notify("v3.0 loaded. Press Insert for the menu")
