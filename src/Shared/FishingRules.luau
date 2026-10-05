-- Deterministic reeling simulation. The client displays server snapshots only.
local Rules = {}

function Rules.Step(state, holding, dt, elapsed, control, difficulty)
	dt = math.clamp(dt, 0, 0.15)
	local pull = (0.5 + 0.5 * math.sin(elapsed * 1.8 + state.Seed)) * 0.12 * difficulty
	state.Tension = math.clamp(state.Tension + ((if holding then 0.24 / control else -0.33 * control) + pull) * dt, 0, 1)
	local safe = state.Tension >= 0.12 and state.Tension <= 0.87
	state.Progress = math.clamp(state.Progress + (if holding and safe then 0.145 * control / difficulty else -0.035) * dt, 0, 1)
	state.Danger = if state.Tension >= 0.98 then state.Danger + dt else math.max(0, state.Danger - dt * 2)
	state.Slack = if state.Tension <= 0.025 then state.Slack + dt else 0
	if state.Danger >= 0.65 then return "Snapped" end
	if state.Slack >= 1.5 or elapsed >= 35 then return "Escaped" end
	if state.Progress >= 1 then return "Caught" end
	return nil
end

return Rules
