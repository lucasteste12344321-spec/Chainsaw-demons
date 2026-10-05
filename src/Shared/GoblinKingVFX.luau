-- VFX locais do Rei Goblin. Malhas autorais feitas no Blender; sem dano, fisica ou destruicao do mapa.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local VFX = {}
VFX.__index = VFX
local WHITE = Color3.fromRGB(252, 244, 216)
local INK = Color3.fromRGB(43, 33, 27)
local EMBER = Color3.fromRGB(244, 143, 61)
local UP = Vector3.yAxis
local function tween(obj, duration, props, style)
	local t = TweenService:Create(obj, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end
function VFX.new(assets, fastMode)
	local self = setmetatable({}, VFX)
	self.assets = assets
	self.fastMode = fastMode or function() return false end
	self.random = Random.new()
	self.active = 0
	self.jobs = {}
	local parent = workspace:FindFirstChild("CombatFX")
	if not parent then parent = Instance.new("Folder"); parent.Name = "CombatFX"; parent.Parent = workspace end
	self.folder = Instance.new("Folder")
	self.folder.Name = "GoblinKingVFX"
	self.folder.Parent = parent
	self.bloom = Instance.new("BloomEffect")
	self.bloom.Name = "GoblinKingVFXBloom"
	self.bloom.Intensity = .65; self.bloom.Size = 32; self.bloom.Threshold = 1.1
	self.bloom.Enabled = false; self.bloom.Parent = workspace.CurrentCamera
	self.connection = RunService.Heartbeat:Connect(function(dt)
		if self.bloom.Parent ~= workspace.CurrentCamera then self.bloom.Parent = workspace.CurrentCamera end
		self.bloom.Enabled = self.active > 0 and not self.fastMode()
		local now = os.clock()
		for job in self.jobs do
			if job.closed or now >= job.ends then
				self.jobs[job] = nil
				if job.finish then job.finish() end
			else job.update(now - job.start, dt) end
		end
	end)
	return self
end
function VFX:Destroy()
	self.connection:Disconnect()
	for job in self.jobs do if job.finish then job.finish() end end
	table.clear(self.jobs)
	self.bloom:Destroy()
	self.folder:Destroy()
end
function VFX:Visible(npc)
	local root = npc:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	return root and root:IsA("BasePart") and (not cam or (cam.CFrame.Position-root.Position).Magnitude < 180)
end
function VFX:Count(name)
	self.folder:SetAttribute(name, (self.folder:GetAttribute(name) or 0) + 1)
end
function VFX:Job(duration, update, finish)
	local job = {start = os.clock(), ends = os.clock() + duration, update = update, finish = finish}
	self.jobs[job] = true
	return function() job.closed = true end
end
function VFX:Part(meshName, cf, size, color, transparency, life)
	if self.active >= (if self.fastMode() then 50 else 190) then return nil end
	local template = meshName and self.assets:FindFirstChild(meshName)
	if meshName and not template then return nil end
	local p = if template then template:Clone() else Instance.new("Part")
	p.Name = meshName or "ParticleAnchor"
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false; p.Material = Enum.Material.Neon
	p.Color = color or WHITE; p.Transparency = transparency or 0
	p.Size = size; p.CFrame = cf; p.Parent = self.folder
	self.active += 1
	p.Destroying:Once(function() self.active -= 1 end)
	Debris:AddItem(p, life or 1)
	return p
end
function VFX:Ring(cf, diameter, life, color, thickness, startSize)
	local p = self:Part("ImpactRing", cf, Vector3.new(startSize or 1, startSize or 1, thickness or .06), color, .08, life + .05)
	if p then tween(p, life, {Size = Vector3.new(diameter, diameter, thickness or .06), Transparency = 1}) end
	return p
end
function VFX:Flash(cf, size, strong)
	if self.fastMode() then return end
	local glow=self:Part("StarFlash",cf*CFrame.Angles(0,0,.25),Vector3.new(size*.25,size*.25,.04),WHITE,0,.22)
	if glow then tween(glow,.19,{Size=Vector3.new(size,size,.02),Transparency=1}) end
	local halo=self:Part("StarFlash",cf*CFrame.new(0,0,.025)*CFrame.Angles(0,0,-.35),Vector3.new(size*.4,size*.4,.04),EMBER,.3,.3)
	if halo then tween(halo,.26,{Size=Vector3.new(size*1.45,size*1.45,.02),Transparency=1}) end
	local anchor=self:Part(nil,cf,Vector3.one*.1,WHITE,1,.35)
	if anchor then
		local light=Instance.new("PointLight");light.Color=EMBER;light.Range=if strong then 24 else 15
		light.Brightness=if strong then 6 else 3;light.Shadows=false;light.Parent=anchor
		tween(light,.26,{Brightness=0})
	end
end
function VFX:Sparks(cf,count,size,speed)
	if self.fastMode() then return end
	local anchor=self:Part(nil,cf,Vector3.one*.1,WHITE,1,1.15)
	if not anchor then return end
	local p=Instance.new("ParticleEmitter");p.Name="RoyalSparks"
	p.Texture="rbxasset://textures/particles/sparkles_main.dds"
	p.Rate=0;p.Enabled=false;p.LightEmission=1;p.LightInfluence=0;p.Brightness=4
	p.Color=ColorSequence.new(WHITE,EMBER);p.EmissionDirection=Enum.NormalId.Front
	p.Lifetime=NumberRange.new(.25,.8);p.Speed=NumberRange.new(speed*.45,speed);p.Drag=5
	p.SpreadAngle=Vector2.new(80,80);p.Acceleration=Vector3.new(0,-12,0)
	p.Rotation=NumberRange.new(0,180);p.RotSpeed=NumberRange.new(-100,100)
	p.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,size),NumberSequenceKeypoint.new(.22,size*.65),NumberSequenceKeypoint.new(1,0)})
	p.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.03),NumberSequenceKeypoint.new(.55,.1),NumberSequenceKeypoint.new(1,1)})
	p.Parent=anchor;p:Emit(count)
end
function VFX:Ground(position, npc)
	local ignored = {self.folder, npc}
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then table.insert(ignored, enemies) end
	local warnings = workspace:FindFirstChild("BossWarnings")
	if warnings then table.insert(ignored, warnings) end
	for _, player in Players:GetPlayers() do if player.Character then table.insert(ignored, player.Character) end end
	local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored; params.IgnoreWater = true
	local hit = workspace:Raycast(position + UP * 3, -UP * 42, params)
	if hit and hit.Normal.Y > .45 then return hit end
	return nil
end
local function groundCF(hit, offset)
	local normal = hit.Normal
	local right = normal:Cross(Vector3.zAxis)
	if right.Magnitude < .1 then right = Vector3.xAxis end
	right = right.Unit
	return CFrame.fromMatrix(hit.Position + normal * (offset or .06), right, normal:Cross(right), normal)
end
local function groundColor(hit)
	if hit.Instance:IsA("Terrain") then return workspace.Terrain:GetMaterialColor(hit.Material) end
	return hit.Instance.Color
end
function VFX:Dust(cf, color, count, size, speed)
	if self.fastMode() then return end
	local p = self:Part(nil, cf, Vector3.one * .1, color, 1, 1.7)
	if not p then return end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "GroundDust"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = 0; emitter.Enabled = false
	emitter.Color = ColorSequence.new(color:Lerp(WHITE,.15), color:Lerp(INK,.28))
	emitter.LightEmission = 0; emitter.LightInfluence = .65
	emitter.Lifetime = NumberRange.new(.5, 1.2)
	emitter.Speed = NumberRange.new(speed * .35, speed)
	emitter.Drag = 6; emitter.Acceleration = UP * 2
	emitter.SpreadAngle = Vector2.new(75,75)
	emitter.Rotation = NumberRange.new(-180,180); emitter.RotSpeed = NumberRange.new(-45,45)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,size*.3),NumberSequenceKeypoint.new(.25,size),NumberSequenceKeypoint.new(1,size*1.6)})
	emitter.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.08,.48),NumberSequenceKeypoint.new(.5,.73),NumberSequenceKeypoint.new(1,1)})
	emitter.Parent = p; emitter:Emit(count)
end
function VFX:Streaks(cf, count, size, color)
	if self.fastMode() then return end
	for i = 1,count do
		local angle = self.random:NextNumber(0,math.pi*2)
		local dir = Vector3.new(math.cos(angle), math.sin(angle), -.22)
		local start = cf:PointToWorldSpace(dir * size * .24)
		local finish = cf:PointToWorldSpace(dir * size * self.random:NextNumber(.85,1.4))
		local p = self:Part(nil, CFrame.lookAt(start,finish), Vector3.new(.045,.045,size*.23),color,.05,.22)
		if p then p.Name="KineticStreak";tween(p,.2,{CFrame=CFrame.lookAt(finish,finish+(finish-start)),Size=Vector3.new(.008,.008,size*.42),Transparency=1}) end
	end
end
function VFX:Impact(npc, side, heavy, index)
	if not self:Visible(npc) then return end
	self:Count("ImpactCount")
	local root = npc.HumanoidRootPart
	local scale = math.clamp(npc:GetScale()/2.074, .6, 2)
	local cf = root.CFrame * CFrame.new((side or 0)*.7*scale, .9*scale, -3.6*scale)
	local diameter = (if heavy then 8 else 5.7)*scale
	local accent = if npc:GetAttribute("BossPhase")==2 then EMBER else WHITE
	self:Ring(cf,diameter,.24,accent,.055,diameter*.2)
	if not self.fastMode() then
		self:Flash(cf,if heavy then 4.5 else 3.2,heavy)
		self:Sparks(cf,if heavy then 24 else 14,.55,if heavy then 26 else 19)
		self:Ring(cf*CFrame.new(0,0,.04),diameter*1.16,.28,EMBER,.04,diameter*.19)
		self:Ring(cf*CFrame.new(0,0,-.32),diameter*1.45,.36,WHITE,.018,diameter*.28)
		local cone=self:Part("ShockCone",cf*CFrame.new(0,0,.65),Vector3.new(2,2,.9),WHITE,.7,.3)
		if cone then tween(cone,.28,{Size=Vector3.new(diameter,diameter,3.3),Transparency=1,CFrame=cf*CFrame.new(0,0,-1.3)}) end
		for i=1,2 do
			local p=self:Part("AirCrescent",cf*CFrame.Angles(0,0,math.rad((index or 1)*61+i*135)),Vector3.new(2.4,2.4,.18)*scale,accent,.18,.3)
			if p then tween(p,.28,{Size=Vector3.new(diameter*1.2,diameter,.06),Transparency=1,CFrame=p.CFrame*CFrame.Angles(0,0,math.rad(30*(side or 1)))}) end
		end
		self:Streaks(cf,if heavy then 9 else 5,diameter*.52,accent)
	end
end
function VFX:Trail(npc, side, duration)
	if self.fastMode() or not self:Visible(npc) then return function() end end
	local arm=npc:FindFirstChild(if side<0 then "Left Arm" else "Right Arm")
	if not arm then return function() end end
	local a=Instance.new("Attachment");a.Name="GK_TrailA";a.Position=Vector3.new(-arm.Size.X*.42,-arm.Size.Y*.43,0);a.Parent=arm
	local b=Instance.new("Attachment");b.Name="GK_TrailB";b.Position=Vector3.new(arm.Size.X*.42,-arm.Size.Y*.43,0);b.Parent=arm
	local trail=Instance.new("Trail");trail.Name="GK_FistWind";trail.Attachment0=a;trail.Attachment1=b;trail.FaceCamera=true
	trail.Lifetime=.11;trail.MinLength=.04;trail.LightEmission=.75;trail.Color=ColorSequence.new(WHITE,EMBER)
	trail.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.2),NumberSequenceKeypoint.new(.55,.65),NumberSequenceKeypoint.new(1,1)})
	trail.WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)})
	trail.Parent=arm
	local core=trail:Clone();core.Name="GK_FistCore";core.Color=ColorSequence.new(WHITE)
	core.Lifetime=.075;core.LightEmission=1
	core.WidthScale=NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(1,0)})
	core.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)})
	core.Parent=arm
	local stopped=false
	local function stop()
		if stopped then return end;stopped=true;trail.Enabled=false;core.Enabled=false
		Debris:AddItem(trail,.15);Debris:AddItem(core,.15);Debris:AddItem(a,.16);Debris:AddItem(b,.16)
	end
	task.delay(duration or 2,stop)
	return stop
end
function VFX:Step(npc, side, running)
	if self.fastMode() or not self:Visible(npc) then return end
	local foot=npc:FindFirstChild(if side<0 then "Left Leg" else "Right Leg")
	if not foot then return end
	local hit=self:Ground(foot.Position,npc)
	if hit then self:Dust(CFrame.new(hit.Position),groundColor(hit),if running then 4 else 2,if running then 1.8 else 1.1,4) end
end
function VFX:Charge(npc)
	if not self:Visible(npc) or self.fastMode() then return function() end end
	local root=npc.HumanoidRootPart
	local p=self:Part("ImpactRing",root.CFrame,Vector3.new(2.8,2.8,.045),EMBER,.22,3)
	if not p then return function() end end
	local spirals={}
	for i=1,2 do
		local ribbon=self:Part("AirSpiral",root.CFrame,Vector3.new(3.4,3.4,5),if i==1 then WHITE else EMBER,.36,3)
		if ribbon then table.insert(spirals,ribbon) end
	end
	local light=Instance.new("PointLight");light.Color=EMBER;light.Brightness=2.5;light.Range=12;light.Parent=p
	local nextSpark=0
	return self:Job(2.8,function(t)
		if not npc.Parent or not p.Parent then return end
		local leg=npc:FindFirstChild("Right Leg")
		local pos=if leg then leg.CFrame:PointToWorldSpace(Vector3.new(0,-leg.Size.Y*.45,0)) else root.Position
		p.CFrame=CFrame.new(pos)*CFrame.Angles(math.pi/2,0,t*3)
		local size=2.7+.25*math.sin(t*13);p.Size=Vector3.new(size,size,.045)
		for i,ribbon in spirals do if ribbon.Parent then
			ribbon.CFrame=CFrame.new(pos)*CFrame.Angles(math.pi/2,0,t*(if i==1 then 7 else -5)+i*2)
			ribbon.Transparency=.3+.13*math.sin(t*14+i)
		end end
		if t>nextSpark then nextSpark=t+.12;self:Sparks(CFrame.new(pos),4,.35,6) end
	end,function()
		if p.Parent then tween(p,.1,{Transparency=1});tween(light,.1,{Brightness=0});Debris:AddItem(p,.11) end
		for _,ribbon in spirals do if ribbon.Parent then tween(ribbon,.14,{Transparency=1});Debris:AddItem(ribbon,.15) end end
	end)
end
function VFX:GroundBurst(npc, death)
	if not self:Visible(npc) then return end
	self:Count(if death then "DeathCount" else "SlamCount")
	local root=npc.HumanoidRootPart
	local hit=self:Ground(root.Position + (if death then root.CFrame.LookVector*2 else Vector3.zero),npc)
	if not hit then return end
	local cf=groundCF(hit,.12)
	local radius=if death then 8 else 16
	self:Ring(cf,radius*2,.48,WHITE,.07,3)
	if self.fastMode() then return end
	self:Flash(CFrame.lookAt(hit.Position+UP*1.7,hit.Position+UP*1.7+root.CFrame.LookVector),9,true)
	self:Sparks(CFrame.new(hit.Position+UP*.4)*CFrame.Angles(-math.pi/2,0,0),if death then 24 else 52,.65,30)
	self:Ring(cf*CFrame.new(0,0,.045),radius*1.7,.62,EMBER,.065,3)
	task.delay(.075,function() if self.folder.Parent then self:Ring(cf,radius*2.15,.5,WHITE,.035,5) end end)
	local pressure=self:Part("ShockCone",cf,Vector3.new(4,4,1),WHITE,.55,.55)
	if pressure then tween(pressure,.5,{Size=Vector3.new(radius*2,radius*2,3.5),Transparency=1}) end
	for i=1,3 do
		local arc=self:Part("AirCrescent",cf*CFrame.Angles(0,0,i*2.1),Vector3.new(3,3,.08),WHITE,.3,.42)
		if arc then tween(arc,.4,{Size=Vector3.new(radius*1.8,radius*1.8,.02),Transparency=1,CFrame=arc.CFrame*CFrame.Angles(0,0,1.2)}) end
	end
	local color=groundColor(hit)
	self:Dust(CFrame.new(hit.Position),color,if death then 12 else 20,if death then 3 else 4.4,15)
	local count=if death then 8 else 16
	for i=1,count do
		local angle=i/count*math.pi*2+self.random:NextNumber(-.1,.1)
		local radial=Vector3.new(math.cos(angle),0,math.sin(angle))
		local offset=radial*self.random:NextNumber(radius*.35,radius*.61)
		local sample=self:Ground(hit.Position+offset+UP*3,npc)
		if sample and math.abs(sample.Position.Y-hit.Position.Y)<4 then
			local size=self.random:NextNumber(.8,if death then 1.8 else 2.8)
			local pos=sample.Position-sample.Normal*size*.28
			local rotation=CFrame.Angles(self.random:NextNumber(-.4,.4),angle,self.random:NextNumber(-.5,.5))
			local rock=self:Part("RockShard",CFrame.new(pos)*rotation,Vector3.new(size,size*.8,size*1.3),groundColor(sample),0,2.1)
			if rock then
				rock.Material=sample.Material;rock.CastShadow=true
				tween(rock,.14,{CFrame=CFrame.new(sample.Position+sample.Normal*size*.25)*rotation})
				task.delay(.95+self.random:NextNumber(0,.25),function() if rock.Parent then tween(rock,.65,{CFrame=rock.CFrame-UP*size,Transparency=1}) end end)
			end
			if i%2==0 then self:Dust(CFrame.new(sample.Position),groundColor(sample),3,2.2,6) end
		end
	end
	-- Fragmentos animados por trajetoria; jamais colidem com jogadores ou alteram o terreno.
	for i=1,(if death then 5 else 10) do
		local angle=self.random:NextNumber(0,math.pi*2)
		local dir=Vector3.new(math.cos(angle),0,math.sin(angle))
		local start=hit.Position+dir*2+UP*.3
		local velocity=dir*self.random:NextNumber(8,18)+UP*self.random:NextNumber(15,23)
		local size=self.random:NextNumber(.25,.65)
		local rock=self:Part("RockShard",CFrame.new(start),Vector3.one*size,color,0,1.1)
		if rock then
			rock.Material=hit.Material
			self:Job(.9,function(t)
				if not rock.Parent then return end
				rock.CFrame=CFrame.new(start+velocity*t-UP*32*t*t)*CFrame.Angles(t*7,t*5,t*3)
				rock.Transparency=math.clamp((t-.55)/.35,0,1)
			end,function() rock:Destroy() end)
		end
	end
end
function VFX:Rush(npc, short)
	if not self:Visible(npc) then return function() end end
	self:Count("RushCount")
	local root=npc.HumanoidRootPart
	local shell=self:Part("ShockCone",root.CFrame,Vector3.new(5.8,5.8,7),WHITE,.78,3)
	local spiral
	if not self.fastMode() then spiral=self:Part("AirSpiral",root.CFrame,Vector3.new(6,6,10),WHITE,.48,3) end
	local nextDust=0
	return self:Job(if short then .38 else 2.5,function(t)
		if not npc.Parent then return end
		if shell and shell.Parent then shell.CFrame=root.CFrame*CFrame.new(0,.4,-1.8)*CFrame.Angles(0,0,t*1.7) end
		if spiral and spiral.Parent then spiral.CFrame=root.CFrame*CFrame.new(0,.2,2)*CFrame.Angles(0,0,-t*9) end
		if t>=nextDust then
			nextDust=t+.12
			if self:Visible(npc) then
				self:Sparks(root.CFrame*CFrame.Angles(0,math.pi,0),3,.4,20)
				local hit=self:Ground(root.Position,npc)
				if hit then self:Dust(CFrame.new(hit.Position),groundColor(hit),4,2.4,8) end
			end
		end
	end,function()
		if shell and shell.Parent then tween(shell,.12,{Transparency=1});Debris:AddItem(shell,.13) end
		if spiral and spiral.Parent then tween(spiral,.12,{Transparency=1});Debris:AddItem(spiral,.13) end
	end)
end
function VFX:Roar(npc)
	if not self:Visible(npc) then return end
	self:Count("RoarCount")
	local root=npc.HumanoidRootPart
	self:Flash(root.CFrame*CFrame.new(0,3,-1.4),7,true)
	self:Sparks(root.CFrame*CFrame.new(0,2,-1),36,.65,25)
	for i=1,(if self.fastMode() then 1 else 3) do task.delay((i-1)*.11,function()
		if not root.Parent or not self.folder.Parent then return end
		self:Ring(root.CFrame*CFrame.new(0,3,-1-i*.7),13+i*3,.55,if i==1 then EMBER else WHITE,.04,2)
	end) end
	local hit=self:Ground(root.Position,npc)
	if hit then self:Dust(CFrame.new(hit.Position),groundColor(hit),12,3,9) end
end
function VFX:Aura(npc)
	local ribbons={}
	local nextSpark=0
	local cancel
	cancel=self:Job(math.huge,function(t)
		local humanoid=npc:FindFirstChildOfClass("Humanoid")
		if not npc.Parent or not humanoid or humanoid.Health<=0 or npc:GetAttribute("BossPhase")~=2 then cancel();return end
		local visible=self:Visible(npc) and not self.fastMode()
		if not visible then for i,p in ribbons do p:Destroy();ribbons[i]=nil end;return end
		local root=npc.HumanoidRootPart
		for i=1,2 do
			if not ribbons[i] or not ribbons[i].Parent then
				ribbons[i]=self:Part("AirSpiral",root.CFrame,Vector3.new(6.4,6.4,9),if i==1 then EMBER else WHITE,.8,4)
			end
			local p=ribbons[i]
			if p then p.CFrame=root.CFrame*CFrame.Angles(math.pi/2,0,t*(if i==1 then 2.5 else -1.5)+i*math.pi);p.Transparency=.78+.1*math.sin(t*4+i) end
		end
		if t>=nextSpark then nextSpark=t+.28;self:Sparks(root.CFrame*CFrame.new(0,-2,0)*CFrame.Angles(math.pi/2,0,0),3,.4,7) end
	end,function() for _,p in ribbons do if p.Parent then p:Destroy() end end end)
	return cancel
end
return VFX

