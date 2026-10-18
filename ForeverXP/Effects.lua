local addonName, addon = ...

local ASSETS = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
local PARTICLES = 20
local TAU = math.pi * 2
local sin, cos, min, max = math.sin, math.cos, math.min, math.max

local themes = {
    flame = { low = { 0.62, 0.035, 0.002 }, high = { 1, 0.69, 0.10 }, edge = { 1, 0.38, 0.04 }, stripes = 2.5, flow = -2 },
    frost = { low = { 0.025, 0.34, 0.55 }, high = { 0.73, 0.98, 1 }, edge = { 0.38, 0.91, 1 }, stripes = 5, flow = 1 },
    arcane = { low = { 0.18, 0.025, 0.43 }, high = { 0.95, 0.34, 1 }, edge = { 0.77, 0.23, 1 }, stripes = 2, flow = 1 },
    void = { low = { 0.009, 0.003, 0.025 }, high = { 0.36, 0.055, 0.58 }, edge = { 0.54, 0.12, 0.94 }, stripes = 3, flow = -1 },
}

local classModes = {
    MAGE = "arcane", DEATHKNIGHT = "frost", WARLOCK = "void", PRIEST = "void",
}

local function clamp(value, low, high)
    return max(low, min(high, value))
end

local function hideParticles(effects)
    effects.frame:Hide()
    for _, particle in ipairs(effects.particles) do particle:Hide() end
end

local function gradient(theme, mode, position, phase, brightness)
    local heat = (sin((position * theme.stripes + phase * theme.flow) * TAU) + 1) / 2
    if mode == "void" then
        heat = heat ^ 4
    elseif mode == "frost" then
        heat = 0.15 + 0.85 * heat ^ 6
    else
        heat = 0.2 + 0.8 * heat
    end
    local low, high = theme.low, theme.high
    return (low[1] + (high[1] - low[1]) * heat) * brightness,
        (low[2] + (high[2] - low[2]) * heat) * brightness,
        (low[3] + (high[3] - low[3]) * heat) * brightness
end

local function particle(texture, kind, asset, blend, track, x, y, width, height, rotation, red, green, blue, alpha)
    if texture.effectKind ~= kind then
        texture.effectKind = kind
        texture:SetTexture(ASSETS .. asset .. ".tga")
        texture:SetBlendMode(blend)
    end
    texture:ClearAllPoints()
    texture:SetPoint("CENTER", track, "BOTTOMLEFT", x, y)
    texture:SetSize(width, height)
    texture:SetRotation(rotation)
    texture:SetVertexColor(red, green, blue, 1)
    texture:SetAlpha(clamp(alpha, 0, 1))
    texture:Show()
end

function addon:ResolveClassEffectMode()
    local mode = self:GetSettings().mode
    if mode == "class" then
        local class
        if UnitClass then
            local _, classToken = UnitClass("player")
            class = classToken
        end
        return classModes[class] or "flame"
    end
    return themes[mode] and mode or nil
end

function addon:CreateClassEffects()
    if self.classEffects then return self.classEffects end
    if not self.bar or not self.track then return end
    local frame = CreateFrame("Frame", nil, self.bar)
    frame:SetAllPoints(self.track)
    -- This frame has no clipping: flames and smoke may rise above the bar.
    -- Its level keeps particles over the fill and underneath the XP text.
    local level = self.overlay and self.overlay:GetFrameLevel() - 1 or self.fill:GetFrameLevel() + 1
    frame:SetFrameLevel(max(self.fill:GetFrameLevel() + 1, level))
    local effects = { frame = frame, track = self.track, particles = {} }
    for index = 1, PARTICLES do
        local texture = frame:CreateTexture(nil, "ARTWORK", nil, (index + 1) % 2)
        texture:Hide()
        effects.particles[index] = texture
    end
    frame:Hide()
    self.classEffects = effects
    self.classParticleFrame = frame
    self.classParticles = effects.particles
    return effects
end

function addon:PaintClassEffect()
    local mode = self:ResolveClassEffectMode()
    local effects = self.classEffects
    if not mode then
        if effects then
            effects.mode = nil
            hideParticles(effects)
        end
        return nil
    end
    effects = effects or self:CreateClassEffects()
    if not effects then return nil end

    local settings, state = self:GetSettings(), self.state
    local theme = themes[mode]
    local phase = settings.reducedMotion and 0 or state.phase
    local brightness = settings.brightness
    effects.mode, effects.phase = mode, phase
    if effects.track ~= self.track or effects.frame:GetParent() ~= self.bar then
        effects.frame:SetParent(self.bar)
        effects.frame:ClearAllPoints()
        effects.frame:SetAllPoints(self.track)
        effects.track = self.track
    end

    local segments = self.rainbowSegments
    for index, segment in ipairs(segments) do
        local r1, g1, b1 = gradient(theme, mode, (index - 1) / #segments, phase, brightness)
        local r2, g2, b2 = gradient(theme, mode, index / #segments, phase, brightness)
        segment:SetGradient("HORIZONTAL", CreateColor(r1, g1, b1, 1), CreateColor(r2, g2, b2, 1))
        segment:Show()
    end

    local red, green, blue = theme.edge[1] * brightness, theme.edge[2] * brightness, theme.edge[3] * brightness
    local fillWidth = max(0, self.trackWidth * state.ratio)
    if settings.reducedMotion or fillWidth <= 0 or settings.glow <= 0 then
        hideParticles(effects)
        return red, green, blue
    end

    effects.frame:Show()
    local height = max(4, self.trackHeight)
    local strength = brightness * settings.glow
    for index, texture in ipairs(effects.particles) do
        local seed = (index * 0.61803398875) % 1
        local life = (phase * 2 + seed) % 1
        local x = seed * fillWidth
        local y, width, particleHeight, rotation, alpha

        if mode == "flame" then
            local ember = index % 3 == 0
            life = (phase * (ember and 3 or 2) + seed) % 1
            local fade = sin(life * math.pi) ^ 0.7
            width = min(fillWidth, ember and 4 or max(8, height * (0.65 + seed * 0.45)))
            particleHeight = ember and (5 + seed * 4) or max(20, height * (1.6 + seed)) * (1 - life * 0.4)
            x = clamp(x + sin(life * TAU + seed * TAU) * height * 0.35, width / 2, fillWidth - width / 2)
            y = height * 0.35 + life * max(24, height * (ember and 3.2 or 1.7))
            rotation = sin((phase + seed) * TAU) * 0.18
            alpha = fade * strength * (ember and 0.95 or 0.8)
            particle(texture, ember and "ember" or "flame", ember and "Glow" or "Flame", "ADD", self.track,
                x, y, width, particleHeight, rotation, 1, ember and 0.78 or 0.32 + seed * 0.32, 0.04, alpha)
        elseif mode == "frost" then
            local shard = index % 2 == 0
            width = min(fillWidth, shard and max(6, height * 0.5) or max(9, height * 0.7))
            particleHeight = shard and max(15, height * 1.7) or width
            x = clamp(x + sin((life + seed) * TAU) * height * 0.6, width / 2, fillWidth - width / 2)
            y = height * 0.5 + sin((life + seed) * TAU) * height * 0.5 + life * height * 0.9
            rotation = (phase * 2 + seed) * TAU * (shard and 1 or -1)
            alpha = sin(life * math.pi) ^ 2 * strength * 0.85
            particle(texture, shard and "frostshard" or "frostspark", shard and "FrostShard" or "FrostSpark", "ADD", self.track,
                x, y, width, particleHeight, rotation, 0.58 + seed * 0.3, 0.91, 1, alpha)
        elseif mode == "arcane" then
            if index <= 12 then
                local rune = index % 2 == 0
                life = (phase + seed) % 1
                width = min(fillWidth, rune and max(18, height * 1.8) or max(5, height * 0.55))
                particleHeight = width
                x = clamp(x + cos(life * TAU + seed * TAU) * height, width / 2, fillWidth - width / 2)
                y = height * 0.7 + sin(life * TAU + seed * TAU) * height * 0.75
                rotation = (phase + seed) * TAU * (rune and 1 or -1)
                alpha = sin(life * math.pi) ^ 0.7 * strength * (rune and 0.65 or 0.9)
                particle(texture, rune and "arcanerune" or "arcaneorb", rune and "ArcaneRune" or "Glow", "ADD", self.track,
                    x, y, width, particleHeight, rotation, 0.85, 0.42 + seed * 0.2, 1, alpha)
            else
                texture:Hide()
            end
        else
            -- Each dark BLEND cloud has a matching, separate luminous rim.
            -- Pairing preserves a heavy shadow center rather than washing it out.
            local pair = math.ceil(index / 2)
            seed = (pair * 0.61803398875) % 1
            life = (phase + seed) % 1
            local rim = index % 2 == 0
            width = min(fillWidth, max(28, height * (2.8 + seed)))
            particleHeight = max(20, height * (1.8 + seed))
            x = clamp(seed * fillWidth + sin((life + seed) * TAU) * height * 0.5, width / 2, fillWidth - width / 2)
            y = height * 0.4 + life * height * 1.5
            rotation = (phase + seed) * TAU
            alpha = sin(life * math.pi) ^ 0.7 * strength * (rim and 0.5 or 0.95)
            particle(texture, rim and "voidrim" or "voidsmoke", rim and "SmokeRim" or "Smoke", rim and "ADD" or "BLEND", self.track,
                x, y, width, particleHeight, rotation, rim and 0.55 or 0.012, rim and 0.12 or 0.004, rim and 0.9 or 0.025, alpha)
        end
    end
    return red, green, blue
end
