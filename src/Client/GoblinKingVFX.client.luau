-- Integra os VFX as animacoes replicadas do chefe. Nao cria remotes nem altera dano/IA.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local FastMode = require(script.Parent:WaitForChild("FastMode"))
local Renderer = require(ReplicatedStorage:WaitForChild("GoblinKingVFX"))
local assets = ReplicatedStorage:WaitForChild("VFX"):WaitForChild("GoblinKing")
local fx = Renderer.new(assets, FastMode.IsEnabled)
task.spawn(function() pcall(function() ContentProvider:PreloadAsync(assets:GetChildren()) end) end)

-- Os tempos servem apenas como reserva do marcador e acompanham TimePosition, inclusive pausas no Charge.
local clips = {
	[93468668046583] = {kind="Attack", side=1, events={{"Hitframe1",.25,"Impact"}}},
	[132226941758894] = {kind="Attack", side=-1, events={{"Hitframe1",.17,"Impact"}}},
	[115173943864342] = {kind="Attack", side=0, heavy=true, events={{"Hitframe1",.25,"Impact"}}},
	[97997804028159] = {kind="Attack", side=1, heavy=true, events={{"Hitframe1",.23,"Impact"}}},
	[86561393184958] = {kind="Slam", events={{"Charge",.28,"Charge"},{"Power",.64,"Slam"}}},
	[135026883273212] = {kind="Dash",events={}},
	[90630684692933] = {kind="Rush",events={}},
	[135794360022292] = {kind="Fury",events={}},
	[108032274433784] = {kind="Roar",events={{"Roar",.48,"Roar"}}},
	[83778916363984] = {kind="Death",events={{"Land",1.2,"Death"}}},
	[112559274057133] = {kind="Walk",loop=true,events={{"FootstepRight",0,"RightStep"},{"FootstepLeft",.58,"LeftStep"}}},
	[123505920591956] = {kind="Run",loop=true,events={{"FootstepRight",0,"RightStep"},{"FootstepLeft",.35,"LeftStep"}}},
}
for i=1,8 do table.insert(clips[135794360022292].events,{"Hitframe1",(i-1)*.13,"FuryImpact",i}) end
local bound = {}
local playing = {}
local globalConnections = {}
local function disconnect(list)
	for _, connection in list do connection:Disconnect() end
	table.clear(list)
end
local function stopCosmetics(ctx)
	for _, cancel in ctx.cancel do cancel() end
	table.clear(ctx.cancel)
	if ctx.charge then ctx.charge(); ctx.charge=nil end
end
local function closeTrack(ctx)
	if ctx.closed then return end
	ctx.closed=true;playing[ctx.track]=nil
	disconnect(ctx.connections)
	stopCosmetics(ctx)
end
local function dispatch(ctx,eventIndex)
	if ctx.fired[eventIndex] or ctx.closed then return end
	ctx.fired[eventIndex]=true
	local npc, definition = ctx.npc,ctx.definition
	if not npc.Parent then return end
	if npc:GetAttribute("Stunned")==true and definition.kind~="Death" then return end
	local e=definition.events[eventIndex]
	local action=e[3]
	if action=="Impact" then fx:Impact(npc,definition.side,definition.heavy,eventIndex)
	elseif action=="FuryImpact" then
		local i=e[4];fx:Impact(npc,if i%2==0 then -1 else 1,i==8,i)
	elseif action=="Charge" then ctx.charge=fx:Charge(npc)
	elseif action=="Slam" then if ctx.charge then ctx.charge();ctx.charge=nil end;fx:GroundBurst(npc,false)
	elseif action=="Roar" then fx:Roar(npc)
	elseif action=="Death" then fx:GroundBurst(npc,true)
	elseif action=="RightStep" then fx:Step(npc,1,definition.kind=="Run")
	elseif action=="LeftStep" then fx:Step(npc,-1,definition.kind=="Run") end
end
local function observeTrack(npc,track,joining)
	if playing[track] then return end
	local id=tonumber(track.Animation.AnimationId:match("%d+"))
	local definition=clips[id]
	if not definition then return end
	local ctx={npc=npc,track=track,definition=definition,fired={},connections={},cancel={},lastPosition=track.TimePosition}
	playing[track]=ctx
	-- Ao entrar na distancia de streaming, nao repetir impactos que ja aconteceram.
	if joining then for i,e in definition.events do if e[2] < track.TimePosition-.05 then ctx.fired[i]=true end end end
	local markers={}
	for _,e in definition.events do markers[e[1]]=true end
	for marker in markers do
		table.insert(ctx.connections,track:GetMarkerReachedSignal(marker):Connect(function()
			local best, distance=nil,math.huge
			for i,e in definition.events do
				local delta=math.abs(track.TimePosition-e[2])
				if e[1]==marker and not ctx.fired[i] and delta<distance and delta<.09 then best,distance=i,delta end
			end
			if best then dispatch(ctx,best) end
		end))
	end
	table.insert(ctx.connections,track.Stopped:Connect(function() closeTrack(ctx) end))
	if definition.kind=="Attack" or definition.kind=="Fury" then
		if definition.side~= -1 then table.insert(ctx.cancel,fx:Trail(npc,1,1.6)) end
		if definition.side~=1 then table.insert(ctx.cancel,fx:Trail(npc,-1,1.6)) end
	elseif definition.kind=="Rush" or definition.kind=="Dash" then
		table.insert(ctx.cancel,fx:Rush(npc,definition.kind=="Dash"))
	end
	-- Fury aplica o primeiro golpe em zero; nao depender do disparo de um marcador no primeiro quadro.
	if not joining and track.TimePosition<.08 then
		for i,e in definition.events do if e[2]==0 then dispatch(ctx,i) end end
	end
end
local function unbind(npc)
	local state=bound[npc]
	if not state then return end
	bound[npc]=nil;disconnect(state.connections)
	if state.aura then state.aura() end
	for _,ctx in playing do if ctx.npc==npc then closeTrack(ctx) end end
end
local function bind(npc)
	if not npc:IsA("Model") or bound[npc] then return end
	if npc:GetAttribute("EnemyType")~="ReiGoblin" and not (npc.Name=="King Goblin" and npc:GetAttribute("Boss")==true) then return end
	local state={connections={}}
	bound[npc]=state
	local function updateAura()
		if state.aura then state.aura();state.aura=nil end
		local humanoid=npc:FindFirstChildOfClass("Humanoid")
		if npc:GetAttribute("BossPhase")==2 and humanoid and humanoid.Health>0 then state.aura=fx:Aura(npc) end
	end
	updateAura()
	table.insert(state.connections,npc:GetAttributeChangedSignal("BossPhase"):Connect(updateAura))
	local function attach(animator)
		if state.animator or not animator:IsA("Animator") then return end
		state.animator=animator
		table.insert(state.connections,animator.AnimationPlayed:Connect(function(track) observeTrack(npc,track,false) end))
		for _,track in animator:GetPlayingAnimationTracks() do observeTrack(npc,track,true) end
	end
	local animator=npc:FindFirstChildWhichIsA("Animator",true)
	if animator then attach(animator) end
	table.insert(state.connections,npc.DescendantAdded:Connect(function(d) if d:IsA("Animator") then attach(d) end end))
	table.insert(state.connections,npc:GetAttributeChangedSignal("Stunned"):Connect(function()
		if npc:GetAttribute("Stunned")==true then for _,ctx in playing do if ctx.npc==npc and ctx.definition.kind~="Death" then stopCosmetics(ctx) end end end
	end))
	table.insert(state.connections,npc.AncestryChanged:Connect(function() if not npc:IsDescendantOf(workspace) then unbind(npc) end end))
	table.insert(state.connections,npc.Destroying:Connect(function() unbind(npc) end))
end
local watchedFolders={}
local function watchEnemies(folder)
	if folder.Name~="Enemies" or watchedFolders[folder] then return end
	watchedFolders[folder]=true
	for _,npc in folder:GetChildren() do bind(npc) end
	table.insert(globalConnections,folder.ChildAdded:Connect(function(npc)
		-- Atributos sao definidos durante SpawnEnemy antes de entrar no loop da IA.
		task.defer(function()
			bind(npc)
			if not bound[npc] and npc:IsA("Model") then
				local c;c=npc:GetAttributeChangedSignal("EnemyType"):Connect(function() bind(npc);if bound[npc] then c:Disconnect() end end)
				task.delay(5,function() c:Disconnect() end)
			end
		end)
	end))
end
for _,d in workspace:GetChildren() do watchEnemies(d) end
table.insert(globalConnections,workspace.ChildAdded:Connect(watchEnemies))
table.insert(globalConnections,RunService.Heartbeat:Connect(function()
	for _,ctx in playing do
		local track=ctx.track
		if not ctx.npc.Parent or not track.IsPlaying then closeTrack(ctx);continue end
		local position=track.TimePosition
		if ctx.definition.loop and position<ctx.lastPosition-.05 then table.clear(ctx.fired) end
		ctx.lastPosition=position
		for i,e in ctx.definition.events do
			if not ctx.fired[i] and position>=e[2]+.045 then
				if position-e[2]<.23 then dispatch(ctx,i) else ctx.fired[i]=true end
			end
		end
	end
end))
table.insert(globalConnections,script.Destroying:Connect(function()
	disconnect(globalConnections)
	for npc in bound do unbind(npc) end
	fx:Destroy()
end))

