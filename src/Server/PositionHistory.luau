-- Histórico limitado de transformações. Consulta matemática: nunca move o Model real.
local History = {}
History.__index = History

function History.Finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function History.FrameValid(frame)
	if typeof(frame) ~= "CFrame" then return false end
	for _, value in { frame:GetComponents() } do
		if not History.Finite(value) then return false end
	end
	return true
end

function History.new(config)
	return setmetatable({ Config = config, Samples = {} }, History)
end

function History:Push(time, frame)
	local samples, config = self.Samples, self.Config
	if not History.Finite(time) or not History.FrameValid(frame) then
		table.clear(samples)
		return
	end
	local last = samples[#samples]
	if last and time <= last.Time then return end
	-- Teleporte/travada longa: não inventa posições intermediárias no caminho.
	if last and (time - last.Time > config.HistoryGap
		or (frame.Position - last.Frame.Position).Magnitude > config.TeleportStep) then
		table.clear(samples)
	end
	table.insert(samples, { Time = time, Frame = frame })
	while #samples > math.ceil(config.HistoryDuration * config.HistoryRate) + 2
		or (#samples > 1 and time - samples[1].Time > config.HistoryDuration) do
		table.remove(samples, 1)
	end
end

function History:At(time)
	local samples = self.Samples
	local first, last = samples[1], samples[#samples]
	if not first or not History.Finite(time) or time < first.Time then return nil end
	if time >= last.Time then
		return if time - last.Time <= 2 / self.Config.HistoryRate then last.Frame else nil
	end
	for index = #samples - 1, 1, -1 do
		local a, b = samples[index], samples[index + 1]
		if time >= a.Time then
			return a.Frame:Lerp(b.Frame, (time - a.Time) / (b.Time - a.Time))
		end
	end
	return nil
end

return History
