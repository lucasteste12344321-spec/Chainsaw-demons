-- Visual-only authored templates. No gameplay code is loaded from Creator Store models.
local RS=game:GetService("ReplicatedStorage")
local Assets={}
local warned={}
local function template(name)
	local vfx=RS:FindFirstChild("VFX")
	local library=vfx and vfx:FindFirstChild("WorldActivities")
	local props=library and library:FindFirstChild("Props")
	local result=props and props:FindFirstChild(name)
	if result and result:IsA("Model") and result.PrimaryPart then return result end
	if not warned[name] then warned[name]=true;warn("[WorldPropAssets] Missing authored template: "..name) end
	return nil
end

function Assets.Clone(name)
	local source=template(name)
	return source and source:Clone()
end

function Assets.Attach(name,root,offset)
	local model=Assets.Clone(name)
	if not model then return nil end
	model:PivotTo(root.CFrame*(offset or CFrame.identity))
	local primary=model.PrimaryPart
	for _,part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored=false;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.Massless=true
			if part~=primary then
				local weld=Instance.new("WeldConstraint");weld.Part0=primary;weld.Part1=part;weld.Parent=part
			end
		end
	end
	local weld=Instance.new("WeldConstraint");weld.Part0=root;weld.Part1=primary;weld.Parent=primary
	model.Parent=root.Parent
	return model
end

return Assets
