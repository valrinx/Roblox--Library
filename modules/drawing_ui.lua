-- ============================================================
--   RAVEN HUB  |  MacLib macOS Edition (100% Drawing API Engine)
--   Authentic Apple macOS Aesthetic | 1:1 MacLib Visual Fidelity
--   High-Contrast Bold Typography | macOS Section Container Cards
--   Apple Capsule Switches | 100% BAC / Frog Anti-Cheat Compliant
-- ============================================================

local DrawingUI = {}
DrawingUI.__index = DrawingUI
DrawingUI.Flags = {}
DrawingUI._allDrawings = {}
DrawingUI._activeWindows = {}

local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")

local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

local function safeDrawing(drawingType)
    if not hasDrawing then return nil end
    local ok, obj = pcall(Drawing.new, drawingType)
    if ok and obj then
        table.insert(DrawingUI._allDrawings, obj)
        return obj
    end
    return nil
end

local function pointInBox(pt, boxPos, boxSize)
    return pt.X >= boxPos.X and pt.X <= (boxPos.X + boxSize.X)
       and pt.Y >= boxPos.Y and pt.Y <= (boxPos.Y + boxSize.Y)
end

local function pointInCircle(pt, center, radius)
    local dx = pt.X - center.X
    local dy = pt.Y - center.Y
    return (dx * dx + dy * dy) <= (radius * radius)
end

local function sanitizeText(str)
    if type(str) ~= "string" then return tostring(str or "") end
    local clean = str:gsub("[^ -~]", "")
    clean = clean:gsub("%s+", " ")
    clean = clean:gsub("^%s*[:%-]%s*", "")
    local res = clean:gsub("^%s+", ""):gsub("%s+$", "")
    return res
end

local function truncateText(str, maxChars)
    local s = sanitizeText(tostring(str or ""))
    maxChars = maxChars or 32
    if #s > maxChars then
        return s:sub(1, math.max(1, maxChars - 3)) .. "..."
    end
    return s
end

local function setObjVisible(obj, visible)
    if obj and (type(obj) == "userdata" or type(obj) == "table") then
        pcall(function()
            obj.Visible = visible
        end)
    end
end

local function wrapText(str, maxChars)
    maxChars = maxChars or 44
    local lines = {}
    local current = ""
    for word in tostring(str or ""):gmatch("%S+") do
        while #word > maxChars do
            local part = word:sub(1, maxChars)
            word = word:sub(maxChars + 1)
            if #current > 0 then
                table.insert(lines, current)
                current = ""
            end
            table.insert(lines, part)
        end
        if #word > 0 then
            if #current == 0 then
                current = word
            elseif #current + 1 + #word <= maxChars then
                current = current .. " " .. word
            else
                table.insert(lines, current)
                current = word
            end
        end
    end
    if #current > 0 then
        table.insert(lines, current)
    end
    if #lines == 0 then
        table.insert(lines, "")
    end
    return lines
end

local function removeObj(obj)
    if not obj then return end
    pcall(function()
        obj.Visible = false
    end)
    pcall(function()
        if type(obj.Remove) == "function" then
            obj:Remove()
        elseif type(obj.Destroy) == "function" then
            obj:Destroy()
        end
    end)
end

-- ============================================================
--   CRISP HIGH-CONTRAST TYPOGRAPHY (Native Drawing API Engine)
--   Font 2 = IBM Plex Sans: Naturally bold, thick, zero blur
-- ============================================================
local function createBoldText(baseZIndex, isHeavy)
    baseZIndex = baseZIndex or 6
    local t = safeDrawing("Text")
    if t then
        t.Font = 2 -- IBM Plex Sans: Solid stem geometry, zero subpixel blur
        t.Outline = false
        t.Color = Color3.fromRGB(255, 255, 255)
        pcall(function() t.ZIndex = baseZIndex end)
    end
    return t
end

-- ============================================================
--   ROUNDED GEOMETRY HELPERS (Drawing API Smooth macOS Shapes)
-- ============================================================
local function createRoundedCard(baseZIndex, isNeumorphic)
    baseZIndex = baseZIndex or 1
    local card = {
        -- Specular Top-Left Bevel Line (Light Highlight)
        neuLightTop  = safeDrawing("Line"),
        neuLightLeft = safeDrawing("Line"),

        -- Ambient Bottom-Right Shadow Line (Deep Occlusion)
        neuDarkBot   = safeDrawing("Line"),
        neuDarkRight = safeDrawing("Line"),

        -- Outer border stroke (optional)
        borderMid   = safeDrawing("Square"),
        borderLeft  = safeDrawing("Square"),
        borderRight = safeDrawing("Square"),
        borderTL    = safeDrawing("Circle"),
        borderTR    = safeDrawing("Circle"),
        borderBL    = safeDrawing("Circle"),
        borderBR    = safeDrawing("Circle"),

        -- Inner card fill
        bgMid       = safeDrawing("Square"),
        bgLeft      = safeDrawing("Square"),
        bgRight     = safeDrawing("Square"),
        bgTL        = safeDrawing("Circle"),
        bgTR        = safeDrawing("Circle"),
        bgBL        = safeDrawing("Circle"),
        bgBR        = safeDrawing("Circle"),
    }

    for k, obj in pairs(card) do
        if obj then
            obj.Filled = true
            obj.Thickness = 1
            obj.Visible = false
            if k == "neuDropMid" or k == "neuDropBR" then
                pcall(function() obj.ZIndex = math.max(0, baseZIndex - 1) end)
            elseif k == "neuLightTop" or k == "neuLightLeft" or k == "neuDarkBot" or k == "neuDarkRight" then
                pcall(function() obj.ZIndex = baseZIndex + 1 end)
            else
                pcall(function() obj.ZIndex = baseZIndex end)
            end
        end
    end

    function card:Update(pos, size, radius, bgColor, borderColor, visible, neuStyle)
        if not visible or size.X <= 0 or size.Y <= 0 then
            for _, o in pairs(self) do
                if type(o) == "userdata" or type(o) == "table" then
                    setObjVisible(o, false)
                end
            end
            return
        end

        local r = math.clamp(radius or 8, 1, math.floor(math.min(size.X, size.Y) / 2))

        -- Neumorphic clean borders (no harsh offset drop slabs)
        setObjVisible(self.neuDropMid, false)
        setObjVisible(self.neuDropBR, false)

        -- 2. Outer Border Stroke (when borderColor provided)
        if borderColor then
            if self.borderMid then
                self.borderMid.Position = Vector2.new(pos.X + r, pos.Y)
                self.borderMid.Size = Vector2.new(math.max(1, size.X - 2 * r), size.Y)
                self.borderMid.Color = borderColor
                self.borderMid.Visible = true
            end
            if self.borderLeft then
                self.borderLeft.Position = Vector2.new(pos.X, pos.Y + r)
                self.borderLeft.Size = Vector2.new(r, math.max(1, size.Y - 2 * r))
                self.borderLeft.Color = borderColor
                self.borderLeft.Visible = true
            end
            if self.borderRight then
                self.borderRight.Position = Vector2.new(pos.X + size.X - r, pos.Y + r)
                self.borderRight.Size = Vector2.new(r, math.max(1, size.Y - 2 * r))
                self.borderRight.Color = borderColor
                self.borderRight.Visible = true
            end
            if self.borderTL then
                self.borderTL.Radius = r
                self.borderTL.Position = Vector2.new(pos.X + r, pos.Y + r)
                self.borderTL.Color = borderColor
                self.borderTL.Visible = true
            end
            if self.borderTR then
                self.borderTR.Radius = r
                self.borderTR.Position = Vector2.new(pos.X + size.X - r, pos.Y + r)
                self.borderTR.Color = borderColor
                self.borderTR.Visible = true
            end
            if self.borderBL then
                self.borderBL.Radius = r
                self.borderBL.Position = Vector2.new(pos.X + r, pos.Y + size.Y - r)
                self.borderBL.Color = borderColor
                self.borderBL.Visible = true
            end
            if self.borderBR then
                self.borderBR.Radius = r
                self.borderBR.Position = Vector2.new(pos.X + size.X - r, pos.Y + size.Y - r)
                self.borderBR.Color = borderColor
                self.borderBR.Visible = true
            end
        else
            setObjVisible(self.borderMid, false)
            setObjVisible(self.borderLeft, false)
            setObjVisible(self.borderRight, false)
            setObjVisible(self.borderTL, false)
            setObjVisible(self.borderTR, false)
            setObjVisible(self.borderBL, false)
            setObjVisible(self.borderBR, false)
        end

        -- 3. Inner Card Fill (1px inset if border is present)
        local inset = borderColor and 1 or 0
        local innerPos = pos + Vector2.new(inset, inset)
        local innerSize = size - Vector2.new(inset * 2, inset * 2)
        local innerR = math.max(1, r - inset)

        if self.bgMid then
            self.bgMid.Position = Vector2.new(innerPos.X + innerR, innerPos.Y)
            self.bgMid.Size = Vector2.new(math.max(1, innerSize.X - 2 * innerR), innerSize.Y)
            self.bgMid.Color = bgColor
            self.bgMid.Visible = true
        end
        if self.bgLeft then
            self.bgLeft.Position = Vector2.new(innerPos.X, innerPos.Y + innerR)
            self.bgLeft.Size = Vector2.new(innerR, math.max(1, innerSize.Y - 2 * innerR))
            self.bgLeft.Color = bgColor
            self.bgLeft.Visible = true
        end
        if self.bgRight then
            self.bgRight.Position = Vector2.new(innerPos.X + innerSize.X - innerR, innerPos.Y + innerR)
            self.bgRight.Size = Vector2.new(innerR, math.max(1, innerSize.Y - 2 * innerR))
            self.bgRight.Color = bgColor
            self.bgRight.Visible = true
        end
        if self.bgTL then
            self.bgTL.Radius = innerR
            self.bgTL.Position = Vector2.new(innerPos.X + innerR, innerPos.Y + innerR)
            self.bgTL.Color = bgColor
            self.bgTL.Visible = true
        end
        if self.bgTR then
            self.bgTR.Radius = innerR
            self.bgTR.Position = Vector2.new(innerPos.X + innerSize.X - innerR, innerPos.Y + innerR)
            self.bgTR.Color = bgColor
            self.bgTR.Visible = true
        end
        if self.bgBL then
            self.bgBL.Radius = innerR
            self.bgBL.Position = Vector2.new(innerPos.X + innerR, innerPos.Y + innerSize.Y - innerR)
            self.bgBL.Color = bgColor
            self.bgBL.Visible = true
        end
        if self.bgBR then
            self.bgBR.Radius = innerR
            self.bgBR.Position = Vector2.new(innerPos.X + innerSize.X - innerR, innerPos.Y + innerSize.Y - innerR)
            self.bgBR.Color = bgColor
            self.bgBR.Visible = true
        end

        -- 4. Neumorphic Dual-Bevel Lighting (Soft Light Top-Left, Dark Shadow Bottom-Right)
        if neuStyle == "raised" then
            local highlightCol = Color3.fromRGB(48, 56, 76)
            local shadowCol = Color3.fromRGB(10, 12, 16)

            if self.neuLightTop then
                self.neuLightTop.From = Vector2.new(pos.X + r, pos.Y)
                self.neuLightTop.To = Vector2.new(pos.X + size.X - r, pos.Y)
                self.neuLightTop.Color = highlightCol
                self.neuLightTop.Visible = true
            end
            if self.neuLightLeft then
                self.neuLightLeft.From = Vector2.new(pos.X, pos.Y + r)
                self.neuLightLeft.To = Vector2.new(pos.X, pos.Y + size.Y - r)
                self.neuLightLeft.Color = highlightCol
                self.neuLightLeft.Visible = true
            end
            if self.neuDarkBot then
                self.neuDarkBot.From = Vector2.new(pos.X + r, pos.Y + size.Y)
                self.neuDarkBot.To = Vector2.new(pos.X + size.X - r, pos.Y + size.Y)
                self.neuDarkBot.Color = shadowCol
                self.neuDarkBot.Visible = true
            end
            if self.neuDarkRight then
                self.neuDarkRight.From = Vector2.new(pos.X + size.X, pos.Y + r)
                self.neuDarkRight.To = Vector2.new(pos.X + size.X, pos.Y + size.Y - r)
                self.neuDarkRight.Color = shadowCol
                self.neuDarkRight.Visible = true
            end
        elseif neuStyle == "inset" then
            -- Pressed / Debossed Cavity: Inverted Lighting (Dark Top-Left, Soft Light Bottom-Right)
            local shadowCol = Color3.fromRGB(10, 12, 16)
            local highlightCol = Color3.fromRGB(42, 50, 68)

            if self.neuLightTop then
                self.neuLightTop.From = Vector2.new(pos.X + r, pos.Y + 1)
                self.neuLightTop.To = Vector2.new(pos.X + size.X - r, pos.Y + 1)
                self.neuLightTop.Color = shadowCol
                self.neuLightTop.Visible = true
            end
            if self.neuLightLeft then
                self.neuLightLeft.From = Vector2.new(pos.X + 1, pos.Y + r)
                self.neuLightLeft.To = Vector2.new(pos.X + 1, pos.Y + size.Y - r)
                self.neuLightLeft.Color = shadowCol
                self.neuLightLeft.Visible = true
            end
            if self.neuDarkBot then
                self.neuDarkBot.From = Vector2.new(pos.X + r, pos.Y + size.Y - 1)
                self.neuDarkBot.To = Vector2.new(pos.X + size.X - r, pos.Y + size.Y - 1)
                self.neuDarkBot.Color = highlightCol
                self.neuDarkBot.Visible = true
            end
            if self.neuDarkRight then
                self.neuDarkRight.From = Vector2.new(pos.X + size.X - 1, pos.Y + r)
                self.neuDarkRight.To = Vector2.new(pos.X + size.X - 1, pos.Y + size.Y - r)
                self.neuDarkRight.Color = highlightCol
                self.neuDarkRight.Visible = true
            end
        else
            setObjVisible(self.neuLightTop, false)
            setObjVisible(self.neuLightLeft, false)
            setObjVisible(self.neuDarkBot, false)
            setObjVisible(self.neuDarkRight, false)
        end
    end

    function card:Remove()
        for _, o in pairs(self) do
            if type(o) == "userdata" or type(o) == "table" then
                removeObj(o)
            end
        end
    end

    return card
end

-- ============================================================
--   APPLE iOS CAPSULE SWITCH (1:1 iOS Design System)
--   Container: 51x31px • Radius: 16px • Background: #34C759 on / #383C4A off
--   Slider: 27x27px • Background: #FFFFFF • Dual Drop Shadows
-- ============================================================
local function createPillSwitch(baseZIndex)
    baseZIndex = baseZIndex or 5
    local pill = {
        -- 1. Outer ambient contact shadow
        shadowL      = safeDrawing("Circle"),
        shadowR      = safeDrawing("Circle"),
        shadowM      = safeDrawing("Square"),

        -- 2. Capsule Track (51x31px, radius 16px)
        trackLeft    = safeDrawing("Circle"),
        trackRight   = safeDrawing("Circle"),
        trackMid     = safeDrawing("Square"),

        -- 3. Inset Track Bevel (when OFF)
        trackBevelT  = safeDrawing("Line"),
        trackBevelL  = safeDrawing("Circle"),

        -- 4. Slider Drop Shadows (box-shadow: 0px 3px 8px rgba(0,0,0,.15), 0px 3px 1px rgba(0,0,0,.06))
        knobShadow2  = safeDrawing("Circle"),
        knobShadow1  = safeDrawing("Circle"),

        -- 5. Solid White Slider Knob (#FFFFFF, 27x27px, radius 13.5px)
        knob         = safeDrawing("Circle"),
        knobRim      = safeDrawing("Circle"),
    }

    if pill.shadowL then pill.shadowL.Filled = true; pill.shadowL.Visible = false; pcall(function() pill.shadowL.ZIndex = baseZIndex end) end
    if pill.shadowR then pill.shadowR.Filled = true; pill.shadowR.Visible = false; pcall(function() pill.shadowR.ZIndex = baseZIndex end) end
    if pill.shadowM then pill.shadowM.Filled = true; pill.shadowM.Thickness = 1; pill.shadowM.Visible = false; pcall(function() pill.shadowM.ZIndex = baseZIndex end) end

    if pill.trackLeft then pill.trackLeft.Filled = true; pill.trackLeft.Visible = false; pcall(function() pill.trackLeft.ZIndex = baseZIndex + 1 end) end
    if pill.trackRight then pill.trackRight.Filled = true; pill.trackRight.Visible = false; pcall(function() pill.trackRight.ZIndex = baseZIndex + 1 end) end
    if pill.trackMid then pill.trackMid.Filled = true; pill.trackMid.Thickness = 1; pill.trackMid.Visible = false; pcall(function() pill.trackMid.ZIndex = baseZIndex + 1 end) end

    if pill.trackBevelT then pill.trackBevelT.Thickness = 1; pill.trackBevelT.Visible = false; pcall(function() pill.trackBevelT.ZIndex = baseZIndex + 2 end) end
    if pill.trackBevelL then pill.trackBevelL.Filled = false; pill.trackBevelL.Thickness = 1; pill.trackBevelL.Visible = false; pcall(function() pill.trackBevelL.ZIndex = baseZIndex + 2 end) end

    if pill.knobShadow2 then pill.knobShadow2.Filled = true; pill.knobShadow2.Visible = false; pcall(function() pill.knobShadow2.ZIndex = baseZIndex + 3 end) end
    if pill.knobShadow1 then pill.knobShadow1.Filled = true; pill.knobShadow1.Visible = false; pcall(function() pill.knobShadow1.ZIndex = baseZIndex + 4 end) end

    if pill.knob then pill.knob.Filled = true; pill.knob.Visible = false; pcall(function() pill.knob.ZIndex = baseZIndex + 5 end) end
    if pill.knobRim then pill.knobRim.Filled = false; pill.knobRim.Thickness = 1; pill.knobRim.Visible = false; pcall(function() pill.knobRim.ZIndex = baseZIndex + 6 end) end

    function pill:Update(pos, size, value, colorOn, colorOff, borderColor, knobColor, visible)
        if not visible or size.X <= 0 or size.Y <= 0 then
            for _, o in pairs(self) do
                if type(o) == "userdata" or type(o) == "table" then
                    setObjVisible(o, false)
                end
            end
            return
        end

        local w = size.X
        local h = size.Y
        local r = h / 2
        local leftCenter = Vector2.new(pos.X + r, pos.Y + r)
        local rightCenter = Vector2.new(pos.X + w - r, pos.Y + r)

        -- CSS transition: all 0.3s ease-out (knob slider) & 0.2s ease-out (track)
        local targetVal = value and 1 or 0
        local now = tick()
        if self.lastTarget == nil then
            self.lastTarget = value
            self.animProgress = targetVal
            self.animStartProgress = targetVal
            self.animStartTime = now
        elseif self.lastTarget ~= value then
            self.lastTarget = value
            self.animStartProgress = self.animProgress or (value and 0 or 1)
            self.animStartTime = now
        end

        local animElapsed = now - (self.animStartTime or now)
        local sliderDuration = 0.3 -- transition: all 0.3s ease-out
        local trackDuration  = 0.2 -- transition: all 0.2s ease-out

        local sliderT = math.clamp(animElapsed / sliderDuration, 0, 1)
        local sliderEase = 1 - (1 - sliderT) * (1 - sliderT) * (1 - sliderT)
        self.animProgress = self.animStartProgress + (targetVal - self.animStartProgress) * sliderEase

        local trackT = math.clamp(animElapsed / trackDuration, 0, 1)
        local trackEase = 1 - (1 - trackT) * (1 - trackT) * (1 - trackT)
        local trackProgress = self.animStartProgress + (targetVal - self.animStartProgress) * trackEase

        -- 1. Ambient Contact Shadow
        local shadowCol = Color3.fromRGB(8, 10, 14)
        if self.shadowL then
            self.shadowL.Radius = r + 1.2
            self.shadowL.Position = leftCenter + Vector2.new(0, 1)
            self.shadowL.Color = shadowCol
            self.shadowL.Visible = true
        end
        if self.shadowR then
            self.shadowR.Radius = r + 1.2
            self.shadowR.Position = rightCenter + Vector2.new(0, 1)
            self.shadowR.Color = shadowCol
            self.shadowR.Visible = true
        end
        if self.shadowM then
            self.shadowM.Position = Vector2.new(pos.X + r, pos.Y + 1)
            self.shadowM.Size = Vector2.new(math.max(1, w - 2 * r), h + 1)
            self.shadowM.Color = shadowCol
            self.shadowM.Visible = true
        end

        -- 2. Capsule Track (smooth 0.2s ease-out color interpolation: #363A46 -> #34C759)
        local colOff = Color3.fromRGB(54, 58, 70)
        local colOn = Color3.fromRGB(52, 199, 89)
        local trackCol = colOff:Lerp(colOn, trackProgress)
        if self.trackLeft then
            self.trackLeft.Radius = r
            self.trackLeft.Position = leftCenter
            self.trackLeft.Color = trackCol
            self.trackLeft.Visible = true
        end
        if self.trackRight then
            self.trackRight.Radius = r
            self.trackRight.Position = rightCenter
            self.trackRight.Color = trackCol
            self.trackRight.Visible = true
        end
        if self.trackMid then
            self.trackMid.Position = Vector2.new(pos.X + r, pos.Y)
            self.trackMid.Size = Vector2.new(math.max(1, w - 2 * r), h)
            self.trackMid.Color = trackCol
            self.trackMid.Visible = true
        end

        -- 3. Inset Track Bevel (when OFF / transitioning)
        if trackProgress < 0.99 then
            local darkBevel = Color3.fromRGB(24, 26, 32)
            local bevelAlpha = math.clamp(1 - trackProgress, 0, 1)
            if self.trackBevelT then
                self.trackBevelT.From = Vector2.new(pos.X + r, pos.Y + 1)
                self.trackBevelT.To = Vector2.new(pos.X + w - r, pos.Y + 1)
                self.trackBevelT.Color = darkBevel
                pcall(function() self.trackBevelT.Transparency = bevelAlpha end)
                self.trackBevelT.Visible = true
            end
            if self.trackBevelL then
                self.trackBevelL.Radius = math.max(1, r - 1)
                self.trackBevelL.Position = leftCenter
                self.trackBevelL.Color = darkBevel
                pcall(function() self.trackBevelL.Transparency = bevelAlpha end)
                self.trackBevelL.Visible = true
            end
        else
            setObjVisible(self.trackBevelT, false)
            setObjVisible(self.trackBevelL, false)
        end

        -- 4. White Circular Slider / Knob (#FFFFFF 27x27px, smooth 0.3s cubic ease-out slide)
        local knobR = (h - 4) / 2
        local leftX = pos.X + 2 + knobR
        local rightX = pos.X + w - 2 - knobR
        local knobX = leftX + (rightX - leftX) * self.animProgress
        local knobY = pos.Y + r
        local knobCenter = Vector2.new(knobX, knobY)

        -- Knob Drop Shadows (box-shadow: 0px 2px 5px rgba(0, 0, 0, 0.15))
        if self.knobShadow2 then
            self.knobShadow2.Radius = knobR + 1.2
            self.knobShadow2.Position = knobCenter + Vector2.new(0, 1.2)
            self.knobShadow2.Color = Color3.fromRGB(12, 14, 18)
            self.knobShadow2.Visible = true
        end
        if self.knobShadow1 then
            self.knobShadow1.Radius = knobR + 0.6
            self.knobShadow1.Position = knobCenter + Vector2.new(0, 0.6)
            self.knobShadow1.Color = Color3.fromRGB(6, 8, 11)
            self.knobShadow1.Visible = true
        end

        -- Solid #FFFFFF Knob
        if self.knob then
            self.knob.Radius = knobR
            self.knob.Position = knobCenter
            self.knob.Color = Color3.fromRGB(255, 255, 255)
            self.knob.Visible = true
        end

        -- Crisp specular edge around knob
        if self.knobRim then
            self.knobRim.Radius = knobR
            self.knobRim.Position = knobCenter
            self.knobRim.Color = Color3.fromRGB(244, 245, 248)
            self.knobRim.Visible = true
        end
    end

    function pill:Remove()
        for _, o in pairs(self) do
            if type(o) == "userdata" or type(o) == "table" then
                removeObj(o)
            end
        end
    end

    return pill
end

-- ============================================================
--   DEBOSSED CAPSULE PILL INPUT (border-radius: 9999px)
--   CSS: background: none; border: none; outline: none;
--        border-radius: 9999px; box-shadow: inset 2px 5px 10px rgb(5, 5, 5);
--        color: #fff;
--   Zero Wireframe Circles • Layered Masked Glow • Deep Inset Falloff
-- ============================================================
local function createPillInput(baseZIndex)
    baseZIndex = baseZIndex or 5
    local pInput = {
        -- 1. Outer Focus Halo (Filled slightly larger capsule underneath; masked by cavity fill)
        focusL         = safeDrawing("Circle"),
        focusR         = safeDrawing("Circle"),
        focusM         = safeDrawing("Square"),

        -- 2. Base Debossed Cavity (border-radius: 9999px, Filled = true)
        bgLeft         = safeDrawing("Circle"),
        bgRight        = safeDrawing("Circle"),
        bgMid          = safeDrawing("Square"),

        -- 3. Inset Shadow: box-shadow: inset 2px 5px 10px rgb(5, 5, 5)
        -- Horizontal lines spanning ONLY the center straight section [x + r, x + w - r]
        -- Zero unfilled circles cutting into center!
        insetTop1      = safeDrawing("Line"),
        insetTop2      = safeDrawing("Line"),
        insetTop3      = safeDrawing("Line"),
        insetTop4      = safeDrawing("Line"),

        -- 4. Bottom subtle reflection line (carved trench floor)
        insetBotRim    = safeDrawing("Line"),
    }

    -- Layer 1: Focus halo sits at baseZIndex (underneath)
    if pInput.focusL then pInput.focusL.Filled = true; pInput.focusL.Visible = false; pcall(function() pInput.focusL.ZIndex = baseZIndex end) end
    if pInput.focusR then pInput.focusR.Filled = true; pInput.focusR.Visible = false; pcall(function() pInput.focusR.ZIndex = baseZIndex end) end
    if pInput.focusM then pInput.focusM.Filled = true; pInput.focusM.Thickness = 1; pInput.focusM.Visible = false; pcall(function() pInput.focusM.ZIndex = baseZIndex end) end

    -- Layer 2: Debossed Cavity sits at baseZIndex + 1 (masks the focus halo center completely!)
    if pInput.bgLeft then pInput.bgLeft.Filled = true; pInput.bgLeft.Visible = false; pcall(function() pInput.bgLeft.ZIndex = baseZIndex + 1 end) end
    if pInput.bgRight then pInput.bgRight.Filled = true; pInput.bgRight.Visible = false; pcall(function() pInput.bgRight.ZIndex = baseZIndex + 1 end) end
    if pInput.bgMid then pInput.bgMid.Filled = true; pInput.bgMid.Thickness = 1; pInput.bgMid.Visible = false; pcall(function() pInput.bgMid.ZIndex = baseZIndex + 1 end) end

    -- Layer 3: Inset Top Shadows sit at baseZIndex + 2
    if pInput.insetTop1 then pInput.insetTop1.Thickness = 1; pInput.insetTop1.Visible = false; pcall(function() pInput.insetTop1.ZIndex = baseZIndex + 2 end) end
    if pInput.insetTop2 then pInput.insetTop2.Thickness = 1; pInput.insetTop2.Visible = false; pcall(function() pInput.insetTop2.ZIndex = baseZIndex + 2 end) end
    if pInput.insetTop3 then pInput.insetTop3.Thickness = 1; pInput.insetTop3.Visible = false; pcall(function() pInput.insetTop3.ZIndex = baseZIndex + 2 end) end
    if pInput.insetTop4 then pInput.insetTop4.Thickness = 1; pInput.insetTop4.Visible = false; pcall(function() pInput.insetTop4.ZIndex = baseZIndex + 2 end) end
    if pInput.insetBotRim then pInput.insetBotRim.Thickness = 1; pInput.insetBotRim.Visible = false; pcall(function() pInput.insetBotRim.ZIndex = baseZIndex + 2 end) end

    function pInput:Update(pos, size, isFocused, visible)
        if not visible or size.X <= 0 or size.Y <= 0 then
            for _, o in pairs(self) do
                if type(o) == "userdata" or type(o) == "table" then
                    setObjVisible(o, false)
                end
            end
            return
        end

        local w = size.X
        local h = size.Y
        local x = pos.X
        local y = pos.Y
        local r = h / 2

        local leftCenter = Vector2.new(x + r, y + r)
        local rightCenter = Vector2.new(x + w - r, y + r)

        -- 1. Outer Focus Halo (when isFocused is true: 1.2px outer glow cleanly masked)
        if isFocused then
            local haloCol = Color3.fromRGB(56, 139, 253)
            local haloR = r + 1.2
            if self.focusL then
                self.focusL.Radius = haloR
                self.focusL.Position = leftCenter
                self.focusL.Color = haloCol
                self.focusL.Visible = true
            end
            if self.focusR then
                self.focusR.Radius = haloR
                self.focusR.Position = rightCenter
                self.focusR.Color = haloCol
                self.focusR.Visible = true
            end
            if self.focusM then
                self.focusM.Position = Vector2.new(x + r, y - 1.2)
                self.focusM.Size = Vector2.new(math.max(1, w - 2 * r), h + 2.4)
                self.focusM.Color = haloCol
                self.focusM.Visible = true
            end
        else
            setObjVisible(self.focusL, false)
            setObjVisible(self.focusR, false)
            setObjVisible(self.focusM, false)
        end

        -- 2. Base Debossed Cavity (border-radius: 9999px)
        -- Seamless dark sunken matte well (background: none carved into chassis)
        local cavityCol = isFocused and Color3.fromRGB(12, 14, 19) or Color3.fromRGB(16, 18, 25)
        if self.bgLeft then
            self.bgLeft.Radius = r
            self.bgLeft.Position = leftCenter
            self.bgLeft.Color = cavityCol
            self.bgLeft.Visible = true
        end
        if self.bgRight then
            self.bgRight.Radius = r
            self.bgRight.Position = rightCenter
            self.bgRight.Color = cavityCol
            self.bgRight.Visible = true
        end
        if self.bgMid then
            self.bgMid.Position = Vector2.new(x + r, y)
            self.bgMid.Size = Vector2.new(math.max(1, w - 2 * r), h)
            self.bgMid.Color = cavityCol
            self.bgMid.Visible = true
        end

        -- 3. Inset Shadow: box-shadow: inset 2px 5px 10px rgb(5, 5, 5)
        -- Spans strictly [x + r, x + w - r] to keep the capsule ends 100% clean
        local shadowDark = Color3.fromRGB(5, 5, 5)
        local shadowMid  = Color3.fromRGB(7, 8, 11)
        local shadowSoft = Color3.fromRGB(10, 11, 16)
        local shadowHazy = Color3.fromRGB(13, 15, 21)
        local rimLight   = isFocused and Color3.fromRGB(38, 46, 62) or Color3.fromRGB(28, 32, 42)

        if self.insetTop1 then
            self.insetTop1.From = Vector2.new(x + r, y + 1)
            self.insetTop1.To = Vector2.new(x + w - r, y + 1)
            self.insetTop1.Color = shadowDark
            self.insetTop1.Visible = true
        end
        if self.insetTop2 then
            self.insetTop2.From = Vector2.new(x + r + 1, y + 2)
            self.insetTop2.To = Vector2.new(x + w - r - 1, y + 2)
            self.insetTop2.Color = shadowMid
            self.insetTop2.Visible = true
        end
        if self.insetTop3 then
            self.insetTop3.From = Vector2.new(x + r + 2, y + 3)
            self.insetTop3.To = Vector2.new(x + w - r - 2, y + 3)
            self.insetTop3.Color = shadowSoft
            self.insetTop3.Visible = true
        end
        if self.insetTop4 then
            self.insetTop4.From = Vector2.new(x + r + 4, y + 4)
            self.insetTop4.To = Vector2.new(x + w - r - 4, y + 4)
            self.insetTop4.Color = shadowHazy
            self.insetTop4.Visible = true
        end

        if self.insetBotRim then
            self.insetBotRim.From = Vector2.new(x + r, y + h - 1)
            self.insetBotRim.To = Vector2.new(x + w - r, y + h - 1)
            self.insetBotRim.Color = rimLight
            self.insetBotRim.Visible = true
        end
    end

    function pInput:Remove()
        for _, o in pairs(self) do
            if type(o) == "userdata" or type(o) == "table" then
                removeObj(o)
            end
        end
    end

    return pInput
end

local function hideItem(item)
    if item.pill then
        pcall(function() item.pill:Update(Vector2.zero, Vector2.zero, false, Color3.new(), Color3.new(), Color3.new(), Color3.new(), false) end)
    end
    if item.pillInput then
        pcall(function() item.pillInput:Update(Vector2.zero, Vector2.zero, false, false) end)
    end
    if item.valBadgeCapsule then
        pcall(function() item.valBadgeCapsule:Update(Vector2.zero, Vector2.zero, false, false) end)
    end
    if item.badgeCapsule then
        pcall(function() item.badgeCapsule:Update(Vector2.zero, Vector2.zero, false, false) end)
    end
    if item.card then
        pcall(function() item.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end)
    end
    if item.buttonCard then
        pcall(function() item.buttonCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end)
    end
    if item.descLines then
        for _, dt in ipairs(item.descLines) do
            setObjVisible(dt, false)
        end
    end
    for k, prop in pairs(item) do
        if k ~= "pill" and k ~= "pillInput" and k ~= "card" and k ~= "buttonCard" and k ~= "descLines" and type(prop) ~= "function" then
            setObjVisible(prop, false)
        end
    end
    item.hitBox = nil
end

local function removeItem(item)
    if item.pill then
        pcall(function() item.pill:Remove() end)
    end
    if item.pillInput then
        pcall(function() item.pillInput:Remove() end)
    end
    if item.valBadgeCapsule then
        pcall(function() item.valBadgeCapsule:Remove() end)
    end
    if item.badgeCapsule then
        pcall(function() item.badgeCapsule:Remove() end)
    end
    if item.card then
        pcall(function() item.card:Remove() end)
    end
    if item.buttonCard then
        pcall(function() item.buttonCard:Remove() end)
    end
    if item.descLines then
        for _, dt in ipairs(item.descLines) do
            removeObj(dt)
        end
        table.clear(item.descLines)
    end
    for k, prop in pairs(item) do
        if k ~= "pill" and k ~= "pillInput" and k ~= "card" and k ~= "buttonCard" and k ~= "descLines" and type(prop) ~= "function" then
            removeObj(prop)
        end
    end
end

-- ============================================================
--   PURE NEUMORPHIC (SOFT UI) PALETTE (100% Surface Fidelity)
--   Uniform Matte Surface • Dual Soft Shadows • Zero Hard Borders
-- ============================================================
local NEU_MATTE = Color3.fromRGB(24, 27, 36) -- Exact uniform matte surface color (#181B24)

local MAC_THEME = {
    -- 1. Uniform Continuous Matte Surfaces (Controls share exact background color)
    bg             = NEU_MATTE,                        -- Main Chassis Base Surface
    bgSidebar      = NEU_MATTE,                        -- Sidebar shares exact base matte color
    bgHeader       = NEU_MATTE,                        -- Header shares exact base matte color
    border         = Color3.fromRGB(36, 42, 56),       -- Subtle Non-Hard Edge
    divider        = Color3.fromRGB(12, 14, 18),       -- Deep Carved Seam Shadow
    dividerLight   = Color3.fromRGB(36, 42, 56),       -- Subtle Bevel Seam Reflection

    -- 2. Dual Soft Lighting Modeling (Light Top-Left, Dark Bottom-Right)
    neuHighlight   = Color3.fromRGB(48, 56, 76),       -- Top-Left Specular Light (Soft Diffuse Rim)
    neuShadow      = Color3.fromRGB(10, 12, 16),       -- Bottom-Right Deep Ambient Shadow
    neuRaisedBg    = NEU_MATTE,                        -- Raised Controls Share Exact Base Matte!
    neuRaisedHover = Color3.fromRGB(28, 32, 44),       -- Soft Tactile Hover Glow
    neuInsetBg     = Color3.fromRGB(18, 20, 27),       -- Debossed Sunken Cavity (Tracks & Wells)
    neuDropShadow  = Color3.fromRGB(6, 7, 10),

    -- 3. macOS Window Traffic Lights (Soft Neumorphic Sockets)
    trafficRed     = Color3.fromRGB(255, 95, 87),
    trafficYellow  = Color3.fromRGB(255, 189, 46),
    trafficGreen   = Color3.fromRGB(39, 201, 63),
    trafficSocket  = Color3.fromRGB(14, 16, 22),       -- Recessed Socket Ring

    -- 4. Typography (WCAG AAA High-Contrast, Razor-Sharp 13px)
    title          = Color3.fromRGB(255, 255, 255),    -- Pure White Window Header
    subtitle       = Color3.fromRGB(168, 180, 204),    -- High-Contrast Slate Grey Subtitle
    outline        = Color3.fromRGB(8, 9, 13),
    tabInactive    = Color3.fromRGB(168, 180, 204),    -- High-Legibility Inactive Tab
    tabActive      = Color3.fromRGB(255, 255, 255),    -- Pure White Active Tab
    tabActiveBg    = NEU_MATTE,                        -- Active Tab Pill Shares Exact Base Matte!
    tabActiveBar   = Color3.fromRGB(56, 139, 253),     -- One Saturated Accent Cue (Electric Blue)

    -- 5. Section Container Cards (Raised Neumorphic Surface - Zero Borders)
    sectionTitle   = Color3.fromRGB(88, 166, 255),     -- Saturated Vivid Apple Blue Section Header
    cardBg         = NEU_MATTE,                        -- Section Cards Share Exact Base Color!
    cardBorder     = Color3.fromRGB(32, 36, 48),       -- Soft Ambient Edge
    cardShadow     = Color3.fromRGB(10, 12, 16),       -- Bottom-Right Soft Shadow
    rowDivider     = Color3.fromRGB(30, 34, 46),       -- Subtle Inner Row Separator
    rowHover       = Color3.fromRGB(28, 32, 44),       -- Smooth Row Hover Highlight

    -- 6. Controls & Badges (Raised / Inset Matte - Zero Borders)
    text           = Color3.fromRGB(248, 250, 255),    -- Crisp Apple High-Contrast White
    textMuted      = Color3.fromRGB(168, 176, 196),    -- Secondary Values & Descriptions
    controlBg      = NEU_MATTE,                        -- Buttons & Badges Share Exact Base Color!
    controlBorder  = Color3.fromRGB(32, 36, 48),       -- Soft Inset Rim
    controlShadow  = Color3.fromRGB(10, 12, 16),       -- Ambient Shadow

    -- 7. Switches & Sliders (Inset Wells + Raised Matte Thumb)
    toggleOn       = Color3.fromRGB(52, 199, 89),      -- Saturated Apple Green Accent (#34C759)
    toggleOff      = Color3.fromRGB(18, 20, 27),       -- Sunken Inset Cavity Track
    toggleBorder   = Color3.fromRGB(32, 36, 48),       -- Soft Inset Rim
    knob           = Color3.fromRGB(250, 252, 255),    -- Pure White Solid Knob
    knobShadow     = Color3.fromRGB(8, 9, 12),         -- Drop Shadow for Knob
    sliderTrack    = Color3.fromRGB(18, 20, 27),       -- Inset Groove Track
    sliderFill     = Color3.fromRGB(56, 139, 253),     -- Saturated Electric Blue Fill
    accent         = Color3.fromRGB(56, 139, 253),     -- Saturated Electric Blue Accent
}

-- ============================================================
--   NOTIFICATIONS
-- ============================================================
function DrawingUI.Notify(options)
    options = options or {}
    local title = sanitizeText(tostring(options.Title or "RAVEN HUB"))
    local content = sanitizeText(tostring(options.Content or options.Description or options.Text or ""))
    print(string.format("[RAVEN HUB] %s: %s", title, content))
end

-- ============================================================
--   WINDOW CONSTRUCTOR
-- ============================================================
function DrawingUI:CreateWindow(config)
    config = config or {}

    local env = (type(getgenv) == "function" and getgenv()) or _G
    if env and env.__RAVEN_DRAWING_WINDOW and type(env.__RAVEN_DRAWING_WINDOW.Destroy) == "function" then
        pcall(function() env.__RAVEN_DRAWING_WINDOW:Destroy() end)
    end

    local self = setmetatable({}, DrawingUI)
    if env then
        env.__RAVEN_DRAWING_WINDOW = self
    end
    DrawingUI._activeWindows = DrawingUI._activeWindows or {}
    table.insert(DrawingUI._activeWindows, self)

    self.title = sanitizeText(tostring(config.Title or config.Name or "RAVEN HUB"))
    self.subtitle = sanitizeText(tostring(config.Subtitle or config.SubTitle or "MacLib macOS Edition"))
    self.size = config.Size or Vector2.new(680, 480)
    self.toggleKey = config.Keybind or config.ToggleKey or Enum.KeyCode.RightShift
    local cfgSaving = (type(config.ConfigurationSaving) == "table" and config.ConfigurationSaving) or (type(config.ConfigSaving) == "table" and config.ConfigSaving) or {}
    self.folder = tostring(cfgSaving.FolderName or config.Folder or DrawingUI.Folder or "RAVENHUB")
    self.defaultConfigFile = tostring(cfgSaving.FileName or "default")
    self.itemsByFlag = {}
    self.openDropdown = nil
    self.dropdownOptionsPool = {}

    local vpSize = Vector2.new(1920, 1080)
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then
            vpSize = cam.ViewportSize
        end
    end)

    self.pos = Vector2.new(
        math.clamp((vpSize.X - self.size.X) / 2, 40, 1400),
        math.clamp((vpSize.Y - self.size.Y) / 2, 40, 900)
    )

    self.visible = true
    self.running = true
    self.theme = MAC_THEME
    self.tabs = {}
    self.activeTabIndex = 1
    self.headerHeight = 44
    self.sidebarWidth = 190

    self.drawings = {}

    -- Clean window geometry without offset black shadow slab
    self.windowShadow = nil

    -- Main Window 12px Rounded Chassis with Specular Rim (Layer 1)
    self.windowCard = createRoundedCard(1)

    -- Left Sidebar Debossed Cavity Surface (Layer 2)
    self.drawings.sidebarBg = safeDrawing("Square")
    if self.drawings.sidebarBg then
        self.drawings.sidebarBg.Filled = true
        self.drawings.sidebarBg.Color = self.theme.bgSidebar
        self.drawings.sidebarBg.Thickness = 1
        self.drawings.sidebarBg.Visible = false
        pcall(function() self.drawings.sidebarBg.ZIndex = 2 end)
    end

    -- Carved Dual-Line Vertical Seam (Layer 2)
    self.drawings.sidebarLine = safeDrawing("Line")
    if self.drawings.sidebarLine then
        self.drawings.sidebarLine.Thickness = 1
        self.drawings.sidebarLine.Color = self.theme.divider
        self.drawings.sidebarLine.Visible = false
        pcall(function() self.drawings.sidebarLine.ZIndex = 2 end)
    end

    self.drawings.sidebarLineLight = safeDrawing("Line")
    if self.drawings.sidebarLineLight then
        self.drawings.sidebarLineLight.Thickness = 1
        self.drawings.sidebarLineLight.Color = self.theme.dividerLight
        self.drawings.sidebarLineLight.Visible = false
        pcall(function() self.drawings.sidebarLineLight.ZIndex = 2 end)
    end

    -- Carved Dual-Line Header Trench (Layer 10)
    self.drawings.headerLine = safeDrawing("Line")
    if self.drawings.headerLine then
        self.drawings.headerLine.Thickness = 1
        self.drawings.headerLine.Color = self.theme.divider
        self.drawings.headerLine.Visible = false
        pcall(function() self.drawings.headerLine.ZIndex = 10 end)
    end

    self.drawings.headerLineLight = safeDrawing("Line")
    if self.drawings.headerLineLight then
        self.drawings.headerLineLight.Thickness = 1
        self.drawings.headerLineLight.Color = self.theme.dividerLight
        self.drawings.headerLineLight.Visible = false
        pcall(function() self.drawings.headerLineLight.ZIndex = 10 end)
    end

    -- Traffic Lights Recessed Sockets (Neumorphic Inset Rings)
    self.drawings.socketRed = safeDrawing("Circle")
    if self.drawings.socketRed then
        self.drawings.socketRed.Filled = true
        self.drawings.socketRed.Color = self.theme.trafficSocket
        self.drawings.socketRed.Radius = 7.5
        self.drawings.socketRed.Visible = false
        pcall(function() self.drawings.socketRed.ZIndex = 9 end)
    end

    self.drawings.socketYellow = safeDrawing("Circle")
    if self.drawings.socketYellow then
        self.drawings.socketYellow.Filled = true
        self.drawings.socketYellow.Color = self.theme.trafficSocket
        self.drawings.socketYellow.Radius = 7.5
        self.drawings.socketYellow.Visible = false
        pcall(function() self.drawings.socketYellow.ZIndex = 9 end)
    end

    self.drawings.socketGreen = safeDrawing("Circle")
    if self.drawings.socketGreen then
        self.drawings.socketGreen.Filled = true
        self.drawings.socketGreen.Color = self.theme.trafficSocket
        self.drawings.socketGreen.Radius = 7.5
        self.drawings.socketGreen.Visible = false
        pcall(function() self.drawings.socketGreen.ZIndex = 9 end)
    end

    -- Traffic Lights: Red (Close/Destroy) (Layer 10)
    self.drawings.trafficRed = safeDrawing("Circle")
    if self.drawings.trafficRed then
        self.drawings.trafficRed.Filled = true
        self.drawings.trafficRed.Color = self.theme.trafficRed
        self.drawings.trafficRed.Radius = 6.5
        self.drawings.trafficRed.Visible = false
        pcall(function() self.drawings.trafficRed.ZIndex = 10 end)
    end

    -- Traffic Lights: Yellow (Minimize/Hide)
    self.drawings.trafficYellow = safeDrawing("Circle")
    if self.drawings.trafficYellow then
        self.drawings.trafficYellow.Filled = true
        self.drawings.trafficYellow.Color = self.theme.trafficYellow
        self.drawings.trafficYellow.Radius = 6.5
        self.drawings.trafficYellow.Visible = false
        pcall(function() self.drawings.trafficYellow.ZIndex = 10 end)
    end

    -- Traffic Lights: Green (Expand/Active)
    self.drawings.trafficGreen = safeDrawing("Circle")
    if self.drawings.trafficGreen then
        self.drawings.trafficGreen.Filled = true
        self.drawings.trafficGreen.Color = self.theme.trafficGreen
        self.drawings.trafficGreen.Radius = 6.5
        self.drawings.trafficGreen.Visible = false
        pcall(function() self.drawings.trafficGreen.ZIndex = 10 end)
    end

    -- Header Title & Subtitle (Double-Strike Bold Vector Typography, Layer 10)
    self.drawings.title = createBoldText(10, true)
    if self.drawings.title then
        self.drawings.title.Size = 13
        self.drawings.title.Color = self.theme.title
        self.drawings.title.Text = self.title
        self.drawings.title.Visible = false
    end

    self.drawings.subtitle = createBoldText(10)
    if self.drawings.subtitle then
        self.drawings.subtitle.Size = 13
        self.drawings.subtitle.Color = self.theme.subtitle
        self.drawings.subtitle.Text = self.subtitle
        self.drawings.subtitle.Visible = false
    end

    -- Keybind Badge on Top-Right (Layer 10)
    self.keyBadgeCard = createRoundedCard(10)

    self.drawings.hint = createBoldText(11)
    if self.drawings.hint then
        self.drawings.hint.Size = 13
        self.drawings.hint.Color = Color3.fromRGB(225, 232, 245)
        self.drawings.hint.Text = "[RShift] Toggle"
        self.drawings.hint.Center = true
        self.drawings.hint.Visible = false
    end

    -- Active Tab Rounded Pill Highlight
    self.activeTabPill = createRoundedCard(3)

    -- Shared Smooth Rounded Row Hover Highlight (replaces sharp rectangle hover)
    self.rowHoverCard = createRoundedCard(3)

    -- Active Tab Accent Left Line
    self.activeTabBar = safeDrawing("Square")
    if self.activeTabBar then
        self.activeTabBar.Filled = true
        self.activeTabBar.Color = self.theme.tabActiveBar
        self.activeTabBar.Thickness = 1
        self.activeTabBar.Visible = false
        pcall(function() self.activeTabBar.ZIndex = 4 end)
    end

    -- User Info Profile Card (Bottom of Sidebar)
    self.userCardPill = createRoundedCard(2)

    self.drawings.userDot = safeDrawing("Circle")
    if self.drawings.userDot then
        self.drawings.userDot.Filled = true
        self.drawings.userDot.Color = self.theme.toggleOn
        self.drawings.userDot.Radius = 4.5
        self.drawings.userDot.Visible = false
        pcall(function() self.drawings.userDot.ZIndex = 4 end)
    end

    self.drawings.userName = createBoldText(4, true)
    if self.drawings.userName then
        self.drawings.userName.Size = 13
        self.drawings.userName.Color = self.theme.text
        local lp = Players.LocalPlayer
        self.drawings.userName.Text = lp and (lp.DisplayName or lp.Name) or "User"
        self.drawings.userName.Visible = false
    end

    self.drawings.userStatus = createBoldText(4)
    if self.drawings.userStatus then
        self.drawings.userStatus.Size = 13
        self.drawings.userStatus.Color = Color3.fromRGB(168, 178, 198)
        self.drawings.userStatus.Text = "100% Drawing Safe"
        self.drawings.userStatus.Visible = false
    end

    -- Vertical Content Scrollbar (Apple Soft UI Scroller Track & Thumb)
    self.drawings.scrollTrack = safeDrawing("Square")
    if self.drawings.scrollTrack then
        self.drawings.scrollTrack.Filled = true
        self.drawings.scrollTrack.Color = Color3.fromRGB(16, 18, 24)
        self.drawings.scrollTrack.Thickness = 1
        self.drawings.scrollTrack.Visible = false
        pcall(function() self.drawings.scrollTrack.ZIndex = 8 end)
    end
    self.scrollThumbPill = createRoundedCard(9)
    self.dropdownPopupCard = createRoundedCard(25)
    self.dropdownOptionsPool = {}
    self.openDropdown = nil
    self.draggingScroller = false
    self.scrollerDragStartY = 0
    self.scrollerStartOffset = 0
    self.scrollerTravel = 0

    self.dragging = false
    self.dragStart = Vector2.zero
    self.posStart = Vector2.zero
    self.connections = {}
    self.activeSlider = nil
    self.activeKeybindListener = nil
    self._unloadCallbacks = {}

    self:InitInputHandlers()

    return self
end

function DrawingUI:OnUnload(callback)
    if type(callback) == "function" then
        table.insert(self._unloadCallbacks, callback)
    end
end

DrawingUI.Folder = "RAVENHUB"

local function resolveTargetWindow(target)
    if target and target ~= DrawingUI and target.tabs then
        return target
    end
    if DrawingUI._activeWindows and #DrawingUI._activeWindows > 0 then
        return DrawingUI._activeWindows[#DrawingUI._activeWindows]
    end
    local env = (type(getgenv) == "function" and getgenv()) or _G
    if env and env.__RAVEN_DRAWING_WINDOW then
        return env.__RAVEN_DRAWING_WINDOW
    end
    return target
end

function DrawingUI:SetFolder(folder)
    local target = resolveTargetWindow(self)
    target.folder = tostring(folder or "RAVENHUB")
    local settingsFolder = target.folder .. "/settings"
    if type(isfolder) == "function" and type(makefolder) == "function" then
        if not isfolder(target.folder) then pcall(makefolder, target.folder) end
        if not isfolder(settingsFolder) then pcall(makefolder, settingsFolder) end
    end
end

function DrawingUI:RefreshConfigList()
    local target = resolveTargetWindow(self)
    local folder = target.folder or DrawingUI.Folder or "RAVENHUB"
    local settingsFolder = folder .. "/settings"

    if type(isfolder) == "function" and type(makefolder) == "function" then
        if not isfolder(folder) then pcall(makefolder, folder) end
        if not isfolder(settingsFolder) then pcall(makefolder, settingsFolder) end
    end

    local configs = {}
    local seen = {}

    local function scanDir(dir)
        if type(listfiles) == "function" and type(isfolder) == "function" and isfolder(dir) then
            local ok, files = pcall(listfiles, dir)
            if ok and type(files) == "table" then
                for _, f in ipairs(files) do
                    local name = tostring(f):match("([^/\\]+)%.json$")
                    if name and not seen[name] then
                        seen[name] = true
                        table.insert(configs, name)
                    end
                end
            end
        end
    end

    scanDir(settingsFolder)
    if #configs == 0 and settingsFolder ~= "RAVENHUB/settings" then
        scanDir("RAVENHUB/settings")
    end

    if #configs == 0 then
        table.insert(configs, target.defaultConfigFile or "default")
    end
    table.sort(configs)
    return configs
end

function DrawingUI:SaveConfig(configName)
    local target = resolveTargetWindow(self)
    if type(configName) ~= "string" or configName:gsub("%s+", "") == "" then
        return false, "Config name cannot be empty."
    end
    local folder = target.folder or DrawingUI.Folder or "RAVENHUB"
    local settingsFolder = folder .. "/settings"

    if type(isfolder) == "function" and type(makefolder) == "function" then
        if not isfolder(folder) then pcall(makefolder, folder) end
        if not isfolder(settingsFolder) then pcall(makefolder, settingsFolder) end
    end

    local saveTable = {
        objects = {},
        flags = {},
        version = "1.0",
        timestamp = os.time()
    }

    for flag, item in pairs(target.itemsByFlag or {}) do
        local val = nil
        local entry = nil
        if item.type == "toggle" then
            val = item.value
            entry = { type = "Toggle", flag = tostring(flag), state = item.value }
        elseif item.type == "slider" then
            val = item.value
            entry = { type = "Slider", flag = tostring(flag), value = tostring(item.value) }
        elseif item.type == "dropdown" then
            val = item.multiple and (item.selectedOptions or {}) or item.current
            entry = { type = "Dropdown", flag = tostring(flag), value = val }
        elseif item.type == "keybind" then
            val = item.key
            entry = { type = "Keybind", flag = tostring(flag), bind = tostring(item.key) }
        elseif item.type == "input" then
            val = item.text
            entry = { type = "Input", flag = tostring(flag), text = tostring(item.text) }
        end
        if entry then
            table.insert(saveTable.objects, entry)
        end
        saveTable.flags[tostring(flag)] = val
    end

    for flag, val in pairs(DrawingUI.Flags or {}) do
        if saveTable.flags[flag] == nil then
            saveTable.flags[flag] = val
        end
    end

    local HttpService = game:GetService("HttpService")
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(saveTable)
    end)
    if not ok or not encoded then
        return false, "Failed to encode config to JSON."
    end

    if type(writefile) == "function" then
        local filePath = settingsFolder .. "/" .. configName .. ".json"
        local writeOk, writeErr = pcall(writefile, filePath, encoded)
        if not writeOk then
            return false, "Failed to write config file: " .. tostring(writeErr)
        end
        return true, string.format("Config '%s' saved.", configName)
    else
        return false, "writefile is not supported by executor."
    end
end

function DrawingUI:LoadConfig(configName)
    local target = resolveTargetWindow(self)
    if type(configName) ~= "string" or configName:gsub("%s+", "") == "" then
        return false, "Config name cannot be empty."
    end
    local folder = target.folder or DrawingUI.Folder or "RAVENHUB"
    local settingsFolder = folder .. "/settings"
    local filePath = settingsFolder .. "/" .. configName .. ".json"

    if (type(isfile) ~= "function" or not isfile(filePath)) and isfile("RAVENHUB/settings/" .. configName .. ".json") then
        filePath = "RAVENHUB/settings/" .. configName .. ".json"
    end

    if type(isfile) ~= "function" or not isfile(filePath) then
        return false, "Config file does not exist: " .. tostring(configName)
    end

    if type(readfile) ~= "function" then
        return false, "readfile is not supported by executor."
    end

    local readOk, content = pcall(readfile, filePath)
    if not readOk or not content then
        return false, "Failed to read config file."
    end

    local HttpService = game:GetService("HttpService")
    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if not decodeOk or type(data) ~= "table" then
        return false, "Invalid JSON data in config file."
    end

    local flagsData = {}

    -- 1. Parse MacLib / DrawingUI objects table (both array and dictionary format)
    if type(data.objects) == "table" then
        for key, entry in pairs(data.objects) do
            if type(entry) == "table" then
                local flag = entry.flag or key
                local entryType = tostring(entry.type or ""):lower()
                local val = nil
                if entryType == "toggle" then
                    val = (entry.state ~= nil) and entry.state or entry.value
                elseif entryType == "slider" then
                    val = tonumber(entry.value) or entry.value
                elseif entryType == "keybind" then
                    val = entry.bind or entry.value or entry.key
                elseif entryType == "input" then
                    val = entry.text or entry.value
                elseif entryType == "dropdown" then
                    val = (entry.value ~= nil) and entry.value or entry.current
                else
                    val = (entry.value ~= nil) and entry.value or entry.state
                end
                if flag and val ~= nil then
                    flagsData[tostring(flag)] = val
                end
            elseif entry ~= nil and type(key) == "string" then
                flagsData[key] = entry
            end
        end
    end

    -- 2. Parse flags dictionary
    if type(data.flags) == "table" then
        for k, v in pairs(data.flags) do
            if flagsData[tostring(k)] == nil then
                flagsData[tostring(k)] = v
            end
        end
    end

    -- Apply loaded flags
    for flag, val in pairs(flagsData) do
        DrawingUI.Flags[flag] = val
        local item = target.itemsByFlag and target.itemsByFlag[flag]
        if item and type(item.Set) == "function" then
            pcall(function() item:Set(val) end)
        end
    end

    return true, string.format("Config '%s' loaded.", configName)
end

function DrawingUI:SetAutoLoad(configName)
    local target = resolveTargetWindow(self)
    local folder = target.folder or DrawingUI.Folder or "RAVENHUB"
    local settingsFolder = folder .. "/settings"
    if type(isfolder) == "function" and type(makefolder) == "function" then
        if not isfolder(folder) then pcall(makefolder, folder) end
        if not isfolder(settingsFolder) then pcall(makefolder, settingsFolder) end
    end
    if type(writefile) == "function" then
        pcall(writefile, settingsFolder .. "/autoload.txt", tostring(configName))
        return true
    end
    return false
end

function DrawingUI:GetAutoLoad()
    local target = resolveTargetWindow(self)
    local folder = target.folder or DrawingUI.Folder or "RAVENHUB"
    local settingsFolder = folder .. "/settings"
    local path = settingsFolder .. "/autoload.txt"
    if type(isfile) == "function" and isfile(path) and type(readfile) == "function" then
        local ok, val = pcall(readfile, path)
        if ok and val and #val > 0 then
            return val
        end
    end
    if type(isfile) == "function" and isfile("RAVENHUB/settings/autoload.txt") and type(readfile) == "function" then
        local ok, val = pcall(readfile, "RAVENHUB/settings/autoload.txt")
        if ok and val and #val > 0 then
            return val
        end
    end
    return nil
end

function DrawingUI:LoadAutoLoadConfig()
    local target = resolveTargetWindow(self)
    local auto = target:GetAutoLoad()
    if auto and auto ~= "" then
        return target:LoadConfig(auto)
    end
    if target.defaultConfigFile and target.defaultConfigFile ~= "" then
        local ok = target:LoadConfig(target.defaultConfigFile)
        if ok then return ok end
    end
    return false, "No autoload config found."
end

function DrawingUI:SetToggleKey(newKey)
    if typeof(newKey) == "EnumItem" then
        self.toggleKey = newKey
    elseif type(newKey) == "string" then
        local found = Enum.KeyCode[newKey]
        self.toggleKey = found or newKey
    else
        self.toggleKey = Enum.KeyCode.RightShift
    end

    local keyName = (typeof(self.toggleKey) == "EnumItem") and self.toggleKey.Name or tostring(self.toggleKey)
    local displayKey = keyName
    if displayKey == "RightShift" then displayKey = "RShift"
    elseif displayKey == "LeftShift" then displayKey = "LShift"
    elseif displayKey == "RightControl" then displayKey = "RCtrl"
    elseif displayKey == "LeftControl" then displayKey = "LCtrl"
    elseif displayKey == "RightAlt" then displayKey = "RAlt"
    elseif displayKey == "LeftAlt" then displayKey = "LAlt"
    end

    if self.drawings and self.drawings.hint then
        self.drawings.hint.Text = string.format("[%s] Toggle", displayKey)
    end
end

-- ============================================================
--   TAB & SECTION ARCHITECTURE (Sidebar Navigation)
-- ============================================================
-- ============================================================
--   PROCEDURAL VECTOR ICON ENGINE (100% Drawing API, Zero Emojis)
--   Authentic Apple macOS SF Symbols rendered in Direct3D Primitives
-- ============================================================
local function resolveIconType(name, icon)
    local str = tostring(icon or ""):lower()
    local nameStr = tostring(name or ""):lower()

    if str:find("combat") or str:find("shoot") or str:find("aim") or nameStr:find("shoot") or nameStr:find("combat") then
        return "combat"
    elseif str:find("move") or str:find("def") or str:find("shield") or nameStr:find("def") or nameStr:find("move") then
        return "defense"
    elseif str:find("esp") or str:find("vis") or str:find("eye") or nameStr:find("vis") or nameStr:find("esp") then
        return "visuals"
    elseif str:find("tool") or str:find("safe") or str:find("lock") or nameStr:find("safe") then
        return "safety"
    elseif str:find("set") or str:find("pref") or str:find("gear") or nameStr:find("set") then
        return "settings"
    elseif str:find("over") or str:find("home") or str:find("dash") or nameStr:find("over") or nameStr:find("home") then
        return "overview"
    end
    return "overview"
end

local function createVectorIcon(iconType, baseZIndex, window)
    baseZIndex = baseZIndex or 5
    local icon = {
        type = iconType,
        drawings = {},
        window = window,
    }

    local function line()
        local l = safeDrawing("Line")
        if l then
            l.Thickness = 1.2
            l.Visible = false
            pcall(function() l.ZIndex = baseZIndex end)
            table.insert(icon.drawings, l)
            if window and window._trackedDrawings then
                table.insert(window._trackedDrawings, l)
            end
        end
        return l
    end

    local function circle(filled, r)
        local c = safeDrawing("Circle")
        if c then
            c.Filled = (filled == true)
            c.Radius = r or 3
            c.Thickness = 1.2
            c.Visible = false
            pcall(function() c.ZIndex = baseZIndex end)
            table.insert(icon.drawings, c)
            if window and window._trackedDrawings then
                table.insert(window._trackedDrawings, c)
            end
        end
        return c
    end

    local function square(filled)
        local s = safeDrawing("Square")
        if s then
            s.Filled = (filled == true)
            s.Thickness = 1.2
            s.Visible = false
            pcall(function() s.ZIndex = baseZIndex end)
            table.insert(icon.drawings, s)
            if window and window._trackedDrawings then
                table.insert(window._trackedDrawings, s)
            end
        end
        return s
    end

    if iconType == "combat" then
        -- Tactical Precision Reticle (Outer Ring + Center Dot + 4 Crosshair Ticks)
        icon.ring = circle(false, 5)
        icon.dot = circle(true, 1.5)
        icon.t = line()
        icon.b = line()
        icon.l = line()
        icon.r = line()

    elseif iconType == "defense" then
        -- Tactical Armor Shield (Top + 2 Sides + 2 Diagonal Bevels + Core Dot)
        icon.top = line()
        icon.left = line()
        icon.right = line()
        icon.diagL = line()
        icon.diagR = line()
        icon.dot = circle(true, 1.5)

    elseif iconType == "visuals" then
        -- Sensor Aperture Eye (Iris Ring + Pupil Dot + 4 Eye Arch Rays)
        icon.iris = circle(false, 4)
        icon.pupil = circle(true, 2)
        icon.archT1 = line()
        icon.archT2 = line()
        icon.archB1 = line()
        icon.archB2 = line()

    elseif iconType == "safety" then
        -- Security Padlock (U-Shackle + Solid Rect Body + Keyhole Dot)
        icon.body = square(false)
        icon.shackle = circle(false, 3.5)
        icon.keyhole = circle(true, 1.5)

    elseif iconType == "settings" then
        -- Control Center Sliders (2 Horizontal Rails + 2 Tactile Slider Knobs)
        icon.rail1 = line()
        icon.knob1 = circle(true, 2)
        icon.rail2 = line()
        icon.knob2 = circle(true, 2)

    else -- "overview" (Launchpad 2x2 App Grid)
        icon.b1 = square(true)
        icon.b2 = square(true)
        icon.b3 = square(true)
        icon.b4 = square(true)
    end

    function icon:Update(center, color, visible)
        if not visible then
            for _, d in ipairs(self.drawings or {}) do
                pcall(function() d.Visible = false end)
            end
            for k, v in pairs(self) do
                if k ~= "drawings" and k ~= "window" and type(v) ~= "function" then
                    pcall(function() v.Visible = false end)
                end
            end
            return
        end

        local cx = center.X
        local cy = center.Y

        if self.type == "combat" then
            if self.ring then self.ring.Position = center; self.ring.Color = color; self.ring.Visible = true end
            if self.dot then self.dot.Position = center; self.dot.Color = color; self.dot.Visible = true end
            if self.t then self.t.From = Vector2.new(cx, cy - 7); self.t.To = Vector2.new(cx, cy - 4); self.t.Color = color; self.t.Visible = true end
            if self.b then self.b.From = Vector2.new(cx, cy + 4); self.b.To = Vector2.new(cx, cy + 7); self.b.Color = color; self.b.Visible = true end
            if self.l then self.l.From = Vector2.new(cx - 7, cy); self.l.To = Vector2.new(cx - 4, cy); self.l.Color = color; self.l.Visible = true end
            if self.r then self.r.From = Vector2.new(cx + 4, cy); self.r.To = Vector2.new(cx + 7, cy); self.r.Color = color; self.r.Visible = true end

        elseif self.type == "defense" then
            if self.top then self.top.From = Vector2.new(cx - 5, cy - 5); self.top.To = Vector2.new(cx + 5, cy - 5); self.top.Color = color; self.top.Visible = true end
            if self.left then self.left.From = Vector2.new(cx - 5, cy - 5); self.left.To = Vector2.new(cx - 5, cy); self.left.Color = color; self.left.Visible = true end
            if self.right then self.right.From = Vector2.new(cx + 5, cy - 5); self.right.To = Vector2.new(cx + 5, cy); self.right.Color = color; self.right.Visible = true end
            if self.diagL then self.diagL.From = Vector2.new(cx - 5, cy); self.diagL.To = Vector2.new(cx, cy + 6); self.diagL.Color = color; self.diagL.Visible = true end
            if self.diagR then self.diagR.From = Vector2.new(cx + 5, cy); self.diagR.To = Vector2.new(cx, cy + 6); self.diagR.Color = color; self.diagR.Visible = true end
            if self.dot then self.dot.Position = Vector2.new(cx, cy - 1); self.dot.Color = color; self.dot.Visible = true end

        elseif self.type == "visuals" then
            if self.iris then self.iris.Position = center; self.iris.Color = color; self.iris.Visible = true end
            if self.pupil then self.pupil.Position = center; self.pupil.Color = color; self.pupil.Visible = true end
            if self.archT1 then self.archT1.From = Vector2.new(cx - 7, cy); self.archT1.To = Vector2.new(cx, cy - 4); self.archT1.Color = color; self.archT1.Visible = true end
            if self.archT2 then self.archT2.From = Vector2.new(cx, cy - 4); self.archT2.To = Vector2.new(cx + 7, cy); self.archT2.Color = color; self.archT2.Visible = true end
            if self.archB1 then self.archB1.From = Vector2.new(cx - 7, cy); self.archB1.To = Vector2.new(cx, cy + 4); self.archB1.Color = color; self.archB1.Visible = true end
            if self.archB2 then self.archB2.From = Vector2.new(cx, cy + 4); self.archB2.To = Vector2.new(cx + 7, cy); self.archB2.Color = color; self.archB2.Visible = true end

        elseif self.type == "safety" then
            if self.body then self.body.Position = Vector2.new(cx - 5, cy - 1); self.body.Size = Vector2.new(10, 7); self.body.Color = color; self.body.Visible = true end
            if self.shackle then self.shackle.Position = Vector2.new(cx, cy - 2); self.shackle.Color = color; self.shackle.Visible = true end
            if self.keyhole then self.keyhole.Position = Vector2.new(cx, cy + 2.5); self.keyhole.Color = color; self.keyhole.Visible = true end

        elseif self.type == "settings" then
            if self.rail1 then self.rail1.From = Vector2.new(cx - 6, cy - 3); self.rail1.To = Vector2.new(cx + 6, cy - 3); self.rail1.Color = color; self.rail1.Visible = true end
            if self.knob1 then self.knob1.Position = Vector2.new(cx - 2, cy - 3); self.knob1.Color = color; self.knob1.Visible = true end
            if self.rail2 then self.rail2.From = Vector2.new(cx - 6, cy + 3); self.rail2.To = Vector2.new(cx + 6, cy + 3); self.rail2.Color = color; self.rail2.Visible = true end
            if self.knob2 then self.knob2.Position = Vector2.new(cx + 2, cy + 3); self.knob2.Color = color; self.knob2.Visible = true end

        elseif self.type == "overview" then
            local sz = Vector2.new(4, 4)
            if self.b1 then self.b1.Position = Vector2.new(cx - 5, cy - 5); self.b1.Size = sz; self.b1.Color = color; self.b1.Visible = true end
            if self.b2 then self.b2.Position = Vector2.new(cx + 1, cy - 5); self.b2.Size = sz; self.b2.Color = color; self.b2.Visible = true end
            if self.b3 then self.b3.Position = Vector2.new(cx - 5, cy + 1); self.b3.Size = sz; self.b3.Color = color; self.b3.Visible = true end
            if self.b4 then self.b4.Position = Vector2.new(cx + 1, cy + 1); self.b4.Size = sz; self.b4.Color = color; self.b4.Visible = true end
        end
    end

    function icon:Remove()
        for _, d in ipairs(self.drawings or {}) do
            removeObj(d)
        end
        for k, v in pairs(self) do
            if k ~= "drawings" and k ~= "window" and type(v) ~= "function" then
                removeObj(v)
            end
        end
        table.clear(self.drawings or {})
    end

    return icon
end

local SectionMethods = {}
SectionMethods.__index = SectionMethods

local TabMethods = {}
TabMethods.__index = TabMethods

function TabMethods:_ensureSection()
    if self._currentSection then
        return self._currentSection
    end
    return self:CreateSection("General")
end

function TabMethods:CreateToggle(cfg) return self:_ensureSection():CreateToggle(cfg) end
function TabMethods:CreateSlider(cfg) return self:_ensureSection():CreateSlider(cfg) end
function TabMethods:CreateButton(cfg) return self:_ensureSection():CreateButton(cfg) end
function TabMethods:CreateLabel(cfg) return self:_ensureSection():CreateLabel(cfg) end
function TabMethods:CreateStatus(cfg) return self:_ensureSection():CreateStatus(cfg) end
function TabMethods:CreateParagraph(cfg) return self:_ensureSection():CreateParagraph(cfg) end
function TabMethods:CreateDivider() return self:_ensureSection():CreateDivider() end
function TabMethods:CreateDropdown(cfg) return self:_ensureSection():CreateDropdown(cfg) end
function TabMethods:CreateKeybind(cfg) return self:_ensureSection():CreateKeybind(cfg) end
function TabMethods:CreateInput(cfg) return self:_ensureSection():CreateInput(cfg) end
function TabMethods:InsertConfigSection(side)
    local win = self.window
    if not win then return end

    -- Section 1: Configuration (1:1 MacLib Drop-in Engine)
    local configSec = self:CreateSection("Configuration")

    local configNameInput = configSec:CreateInput({
        Name = "Config Name",
        Placeholder = "Enter config name...",
        CurrentValue = "default",
        Flag = "Raven_ConfigName",
    })

    local configList = (win.RefreshConfigList and win:RefreshConfigList()) or {"default"}
    local configDropdown = configSec:CreateDropdown({
        Name = "Select Config",
        Options = configList,
        CurrentOption = configList[1] or "default",
        Flag = "Raven_SelectedConfig",
    })

    configSec:CreateButton({
        Name = "Create Config",
        Callback = function()
            local cfgName = (configNameInput and configNameInput.text and configNameInput.text ~= "") and configNameInput.text or "default"
            local ok, msg = win:SaveConfig(cfgName)
            if ok then
                local newList = win:RefreshConfigList()
                if configDropdown and type(configDropdown.SetOptions) == "function" then
                    configDropdown:SetOptions(newList)
                    configDropdown:Set(cfgName)
                end
                DrawingUI.Notify({ Title = "Config Saved", Content = "Created config '" .. cfgName .. "'." })
            else
                DrawingUI.Notify({ Title = "Config Error", Content = tostring(msg) })
            end
        end,
    })

    configSec:CreateButton({
        Name = "Load Config",
        Callback = function()
            local selected = (configDropdown and configDropdown.current) or "default"
            local ok, msg = win:LoadConfig(selected)
            if ok then
                DrawingUI.Notify({ Title = "Config Loaded", Content = "Loaded config '" .. selected .. "'." })
            else
                DrawingUI.Notify({ Title = "Config Error", Content = tostring(msg) })
            end
        end,
    })

    configSec:CreateButton({
        Name = "Overwrite Config",
        Callback = function()
            local selected = (configDropdown and configDropdown.current) or "default"
            local ok, msg = win:SaveConfig(selected)
            if ok then
                DrawingUI.Notify({ Title = "Config Overwritten", Content = "Overwrote config '" .. selected .. "'." })
            else
                DrawingUI.Notify({ Title = "Config Error", Content = tostring(msg) })
            end
        end,
    })

    configSec:CreateButton({
        Name = "Refresh Config List",
        Callback = function()
            local newList = win:RefreshConfigList()
            if configDropdown and type(configDropdown.SetOptions) == "function" then
                configDropdown:SetOptions(newList)
            end
            DrawingUI.Notify({ Title = "Config List", Content = "Config list refreshed." })
        end,
    })

    local autoloadLabel = nil
    configSec:CreateButton({
        Name = "Set as Autoload",
        Callback = function()
            local selected = (configDropdown and configDropdown.current) or "default"
            win:SetAutoLoad(selected)
            if autoloadLabel and type(autoloadLabel.Set) == "function" then
                autoloadLabel:Set("Autoload config: " .. selected)
            end
            DrawingUI.Notify({ Title = "Autoload Set", Content = "Set '" .. selected .. "' as autoload." })
        end,
    })

    local curAuto = (win.GetAutoLoad and win:GetAutoLoad()) or "None"
    autoloadLabel = configSec:CreateLabel("Autoload config: " .. tostring(curAuto))

    -- Section 2: Hub Configuration (Visuals & Keybind)
    local hubSec = self:CreateSection("Hub Configuration")
    hubSec:CreateKeybind({
        Name = "Menu Toggle Keybind",
        CurrentKeybind = win.toggleKey or "RightShift",
        Flag = "Raven_ToggleKeybind",
        Callback = function(key)
            if win then
                if type(win.SetToggleKey) == "function" then
                    win:SetToggleKey(key)
                else
                    win.toggleKey = key
                end
            end
        end,
    })
    hubSec:CreateToggle({
        Name = "Performance Mode (Low FX)",
        CurrentValue = win.performanceMode or false,
        Flag = "Raven_PerfMode",
        Callback = function(val)
            if win then win.performanceMode = val end
        end,
    })
    hubSec:CreateToggle({
        Name = "Show Status Tag & Watermark",
        CurrentValue = win.showUserCard ~= false,
        Flag = "Raven_ShowWatermark",
        Callback = function(val)
            if win and win.userCardPill then
                win.showUserCard = val
            end
        end,
    })

    -- Section 3: Hub Lifecycle (Clean Teardown - only if not already added)
    local hasDestroy = false
    for _, s in ipairs(self.sections) do
        for _, it in ipairs(s.items) do
            local nm = (it.name or ""):lower()
            if nm:find("destroy") or nm:find("unload") then
                hasDestroy = true
                break
            end
        end
        if hasDestroy then break end
    end

    if not hasDestroy then
        local lifeSec = self:CreateSection("Lifecycle")
        lifeSec:CreateButton({
            Name = "Unload / Destroy Hub",
            Callback = function()
                if win and type(win.Destroy) == "function" then
                    win:Destroy()
                end
            end,
        })
    end
end

function TabMethods:Select()
    for idx, t in ipairs(self.window.tabs) do
        if t == self then
            self.window.activeTabIndex = idx
            break
        end
    end
end

function DrawingUI:CreateTab(name, icon)
    local existing = self:GetTab(name)
    if existing then
        return existing
    end

    local resolvedIcon = resolveIconType(name, icon)
    local tab = setmetatable({
        name = sanitizeText(tostring(name or "Tab")),
        icon = icon,
        iconType = resolvedIcon,
        iconObject = createVectorIcon(resolvedIcon, 5, self),
        sections = {},
        window = self,
        scrollOffset = 0,
        targetScroll = 0,
        maxScroll = 0,
        _currentSection = nil,
        tabText = createBoldText(4, true),
    }, TabMethods)

    if tab.tabText then
        tab.tabText.Size = 13
        tab.tabText.Color = self.theme.tabInactive
        tab.tabText.Text = tab.name
        tab.tabText.Visible = false
    end

    table.insert(self.tabs, tab)
    return tab
end

function DrawingUI:GetTab(name)
    local target = sanitizeText(tostring(name or "")):lower()
    for _, tab in ipairs(self.tabs) do
        if tab.name and tab.name:lower() == target then
            return tab
        end
    end
    return nil
end

function DrawingUI:SortTabs(orderedNames)
    if type(orderedNames) ~= "table" or #orderedNames == 0 then return end
    local orderMap = {}
    for idx, name in ipairs(orderedNames) do
        orderMap[tostring(name):lower()] = idx
    end

    local currentActiveTab = self.tabs[self.activeTabIndex]

    table.sort(self.tabs, function(a, b)
        local rankA = orderMap[a.name:lower()] or 999
        local rankB = orderMap[b.name:lower()] or 999
        if rankA == rankB then
            return a.name < b.name
        end
        return rankA < rankB
    end)

    if currentActiveTab then
        for idx, t in ipairs(self.tabs) do
            if t == currentActiveTab then
                self.activeTabIndex = idx
                break
            end
        end
    end
end

function DrawingUI:CreatePlaceholderTab(name, icon, message)
    local tab = self:CreateTab(name, icon)
    local sec = tab:CreateSection("Information")
    sec:CreateParagraph({
        Title = name,
        Content = message or "This section is currently being updated for zero-injection."
    })
    return tab
end

function TabMethods:CreateSection(secName)
    local sec = setmetatable({
        name = sanitizeText(tostring(secName or "Section")),
        items = {},
        tab = self,
        window = self.window,
        accentBar = safeDrawing("Square"),
        titleDrawing = createBoldText(5, true),
        card = createRoundedCard(3),
    }, SectionMethods)

    if sec.accentBar then
        sec.accentBar.Filled = true
        sec.accentBar.Thickness = 1
        sec.accentBar.Color = self.window.theme.sectionTitle
        sec.accentBar.Visible = false
        pcall(function() sec.accentBar.ZIndex = 5 end)
    end

    if sec.titleDrawing then
        sec.titleDrawing.Size = 13
        sec.titleDrawing.Color = self.window.theme.sectionTitle
        sec.titleDrawing.Text = string.upper(sec.name)
        sec.titleDrawing.Visible = false
    end

    self._currentSection = sec
    table.insert(self.sections, sec)
    return sec
end

-- ============================================================
--   SECTION CONTROLS (1:1 MacLib High-Contrast Controls)
-- ============================================================
function SectionMethods:CreateToggle(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local item = {
        type = "toggle",
        name = sanitizeText(tostring(cfg.Name or "Toggle")),
        value = cfg.CurrentValue == true or cfg.Default == true,
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        -- Layering: Backgrounds created first, then foreground text and switch
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        label = createBoldText(6, true),
        pill = createPillSwitch(5),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    function item:Set(val)
        item.value = (val == true)
        if item.flag then
            DrawingUI.Flags[item.flag] = item.value
        end
        pcall(item.callback, item.value)
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.value
        if tab and tab.window and tab.window.itemsByFlag then
            tab.window.itemsByFlag[item.flag] = item
        end
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateSlider(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local minVal = (cfg.Range and tonumber(cfg.Range[1])) or tonumber(cfg.Min) or 0
    local maxVal = (cfg.Range and tonumber(cfg.Range[2])) or tonumber(cfg.Max) or 100
    local currentVal = tonumber(cfg.CurrentValue or cfg.Default or minVal) or minVal

    local item = {
        type = "slider",
        name = sanitizeText(tostring(cfg.Name or "Slider")),
        min = minVal,
        max = maxVal,
        increment = tonumber(cfg.Increment) or 1,
        suffix = sanitizeText(tostring(cfg.Suffix or "")),
        value = math.clamp(currentVal, minVal, maxVal),
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        -- Layering: Backgrounds first
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        valBadgeBg = safeDrawing("Square"),
        valBadgeBorder = safeDrawing("Square"),
        valBadgeCapsule = createPillInput(5),
        track = safeDrawing("Square"),
        fill = safeDrawing("Square"),
        knob = safeDrawing("Circle"),
        label = createBoldText(6, true),
        valText = createBoldText(6, true),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.valBadgeBg then
        item.valBadgeBg.Filled = true
        item.valBadgeBg.Color = tab.window.theme.controlBg
        item.valBadgeBg.Thickness = 1
        item.valBadgeBg.Visible = false
        pcall(function() item.valBadgeBg.ZIndex = 5 end)
    end

    if item.valBadgeBorder then
        item.valBadgeBorder.Filled = false
        item.valBadgeBorder.Color = tab.window.theme.controlBorder
        item.valBadgeBorder.Thickness = 1
        item.valBadgeBorder.Visible = false
        pcall(function() item.valBadgeBorder.ZIndex = 5 end)
    end

    if item.track then
        item.track.Thickness = 1
        item.track.Filled = true
        item.track.Color = tab.window.theme.sliderTrack
        item.track.Visible = false
        pcall(function() item.track.ZIndex = 5 end)
    end

    if item.fill then
        item.fill.Thickness = 1
        item.fill.Filled = true
        item.fill.Color = tab.window.theme.sliderFill
        item.fill.Visible = false
        pcall(function() item.fill.ZIndex = 5 end)
    end

    if item.knob then
        item.knob.Filled = true
        item.knob.Color = tab.window.theme.knob
        item.knob.Radius = 8
        item.knob.Visible = false
        pcall(function() item.knob.ZIndex = 6 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.valText then
        item.valText.Size = 13
        item.valText.Color = tab.window.theme.accent
        item.valText.Center = true
        item.valText.Visible = false
    end

    function item:Set(val)
        local num = tonumber(val) or item.min
        item.value = math.clamp(num, item.min, item.max)
        if item.flag then
            DrawingUI.Flags[item.flag] = item.value
        end
        pcall(item.callback, item.value)
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.value
        if tab and tab.window and tab.window.itemsByFlag then
            tab.window.itemsByFlag[item.flag] = item
        end
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateButton(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local btnName = sanitizeText(tostring(cfg.Name or "Button"))

    -- Prevent duplicate Destroy Hub / Unload buttons within the same tab
    local lowerName = btnName:lower()
    if lowerName:find("destroy hub") or lowerName:find("unload / destroy") then
        if tab and tab.sections then
            for _, sec in ipairs(tab.sections) do
                for _, it in ipairs(sec.items) do
                    local itName = (it.name or ""):lower()
                    if itName:find("destroy hub") or itName:find("unload / destroy") then
                        if cfg.Callback then
                            local oldCb = it.callback
                            it.callback = function()
                                pcall(oldCb)
                                pcall(cfg.Callback)
                            end
                        end
                        return it
                    end
                end
            end
        end
    end

    local item = {
        type = "button",
        name = btnName,
        callback = cfg.Callback or function() end,
        hoverBg = safeDrawing("Square"),
        buttonCard = createRoundedCard(5),
        label = createBoldText(6, true),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Center = true
        item.label.Visible = false
    end

    function item:Click()
        pcall(item.callback)
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateLabel(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local text = sanitizeText(tostring(type(cfg) == "table" and (cfg.Text or cfg.Name) or cfg))
    local item = {
        type = "label",
        text = text,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        label = createBoldText(6, true),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    local maxLabelChars = 52
    local disp = truncateText(text, maxLabelChars)

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.textMuted
        item.label.Text = disp
        item.label.Visible = false
    end

    function item:Set(newText)
        item.text = sanitizeText(tostring(type(newText) == "table" and (newText.Text or newText.Name) or newText or ""))
        local newDisp = truncateText(item.text, maxLabelChars)
        if item.label then
            item.label.Text = newDisp
        end
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateStatus(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local title = sanitizeText(tostring(cfg.Title or cfg.Name or "Status"))
    local desc = sanitizeText(tostring(cfg.Description or cfg.Content or cfg.Value or "Ready"))

    local item = {
        type = "paragraph",
        title = title,
        content = desc,
        lines = wrapText(desc, 44),
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        titleText = createBoldText(6, true),
        descLines = {},
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.titleText then
        item.titleText.Size = 13
        item.titleText.Color = tab.window.theme.sectionTitle
        item.titleText.Text = item.title
        item.titleText.Visible = false
    end

    local maxAlloc = math.max(4, #item.lines)
    for i = 1, maxAlloc do
        local dt = createBoldText(6)
        if dt then
            dt.Size = 13
            dt.Color = tab.window.theme.text
            dt.Text = item.lines[i] or ""
            dt.Visible = false
            table.insert(item.descLines, dt)
        end
    end
    item.descText = item.descLines[1]

    function item:Set(newDesc)
        item.content = sanitizeText(tostring(newDesc or ""))
        item.lines = wrapText(item.content, 44)
        while #item.descLines < #item.lines do
            local dt = createBoldText(6)
            if dt then
                dt.Size = 13
                dt.Color = tab.window.theme.text
                dt.Visible = false
                table.insert(item.descLines, dt)
            end
        end
        for idx, dt in ipairs(item.descLines) do
            if item.lines[idx] then
                dt.Text = item.lines[idx]
            else
                dt.Text = ""
                setObjVisible(dt, false)
            end
        end
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateParagraph(cfg)
    return self:CreateStatus(cfg)
end

function SectionMethods:CreateDivider()
    local item = {
        type = "divider",
        line = safeDrawing("Line"),
    }
    if item.line then
        item.line.Thickness = 1
        item.line.Color = self.tab.window.theme.rowDivider
        item.line.Visible = false
        pcall(function() item.line.ZIndex = 4 end)
    end
    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateDropdown(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local rawOptions = cfg.Options or {"Option 1"}
    local options = {}
    for _, opt in ipairs(rawOptions) do
        table.insert(options, tostring(opt))
    end
    if #options == 0 then table.insert(options, "Default") end

    local isMultiple = (cfg.MultipleOptions == true or cfg.Multiple == true)
    local selectedMap = {}
    local selectedList = {}

    local defaultVal = cfg.CurrentOption or cfg.Default or (options[1] or "")
    if isMultiple then
        if type(defaultVal) == "table" then
            for _, o in ipairs(defaultVal) do
                local s = tostring(o)
                selectedMap[s] = true
                table.insert(selectedList, s)
            end
        elseif defaultVal and tostring(defaultVal) ~= "" then
            local s = tostring(defaultVal)
            selectedMap[s] = true
            table.insert(selectedList, s)
        end
    else
        if type(defaultVal) == "table" then
            defaultVal = defaultVal[1] or options[1] or ""
        end
        defaultVal = tostring(defaultVal)
    end

    local item = {
        type = "dropdown",
        name = sanitizeText(tostring(cfg.Name or "Dropdown")),
        options = options,
        multiple = isMultiple,
        selectedMap = selectedMap,
        selectedOptions = selectedList,
        current = defaultVal,
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        badgeCapsule = createPillInput(5),
        label = createBoldText(6, true),
        valText = createBoldText(6, true),
        arrow = createBoldText(6),
        tab = tab,
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.valText then
        item.valText.Size = 13
        item.valText.Color = tab.window.theme.accent
        item.valText.Visible = false
    end

    if item.arrow then
        item.arrow.Size = 13
        item.arrow.Color = tab.window.theme.textMuted
        item.arrow.Text = "v"
        item.arrow.Visible = false
    end

    function item:GetDisplayValue()
        if self.multiple then
            if #self.selectedOptions == 0 then
                return "None"
            elseif #self.selectedOptions == 1 then
                return self.selectedOptions[1]
            else
                return string.format("%d Selected", #self.selectedOptions)
            end
        else
            return tostring(self.current or "")
        end
    end

    function item:IsSelected(opt)
        local s = tostring(opt)
        if self.multiple then
            return self.selectedMap[s] == true
        else
            return tostring(self.current) == s
        end
    end

    function item:Set(val)
        if self.multiple then
            table.clear(self.selectedOptions)
            table.clear(self.selectedMap)
            if type(val) == "table" then
                for _, opt in ipairs(val) do
                    local s = tostring(opt)
                    self.selectedMap[s] = true
                    table.insert(self.selectedOptions, s)
                end
            elseif val ~= nil and tostring(val) ~= "" then
                local s = tostring(val)
                self.selectedMap[s] = true
                table.insert(self.selectedOptions, s)
            end
            if self.flag then
                DrawingUI.Flags[self.flag] = self.selectedOptions
            end
            pcall(self.callback, self.selectedOptions)
        else
            if type(val) == "table" then val = val[1] end
            self.current = tostring(val or "")
            if self.flag then
                DrawingUI.Flags[self.flag] = self.current
            end
            pcall(self.callback, self.current)
        end
    end

    function item:ToggleOption(opt)
        if not self.multiple then
            self:Set(opt)
            return
        end
        local s = tostring(opt)
        if self.selectedMap[s] then
            self.selectedMap[s] = nil
            for idx, v in ipairs(self.selectedOptions) do
                if v == s then
                    table.remove(self.selectedOptions, idx)
                    break
                end
            end
        else
            self.selectedMap[s] = true
            table.insert(self.selectedOptions, s)
        end
        if self.flag then
            DrawingUI.Flags[self.flag] = self.selectedOptions
        end
        pcall(self.callback, self.selectedOptions)
    end

    function item:SetOptions(newOptions, keepSelection)
        local opts = {}
        for _, opt in ipairs(newOptions or {}) do
            table.insert(opts, tostring(opt))
        end
        if #opts == 0 then table.insert(opts, "default") end
        self.options = opts

        if not keepSelection then
            if self.multiple then
                table.clear(self.selectedOptions)
                table.clear(self.selectedMap)
            else
                self:Set(self.options[1] or "default")
            end
        else
            if not self.multiple and not table.find(self.options, self.current) then
                self:Set(self.options[1] or "default")
            end
        end
    end

    function item:Refresh(newOptions, keepSelection)
        self:SetOptions(newOptions, keepSelection)
    end

    function item:ClearOptions()
        self.options = {}
        if self.multiple then
            table.clear(self.selectedOptions)
            table.clear(self.selectedMap)
        end
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.multiple and item.selectedOptions or item.current
        if tab and tab.window and tab.window.itemsByFlag then
            tab.window.itemsByFlag[item.flag] = item
        end
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateKeybind(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local defaultKey = cfg.CurrentKeybind or cfg.Default or "None"
    if typeof(defaultKey) == "EnumItem" then
        defaultKey = defaultKey.Name
    end

    local item = {
        type = "keybind",
        name = sanitizeText(tostring(cfg.Name or "Keybind")),
        key = tostring(defaultKey),
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        listening = false,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        badgeBg = safeDrawing("Square"),
        badgeBorder = safeDrawing("Square"),
        label = createBoldText(6, true),
        keyText = createBoldText(6, true),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.badgeBg then
        item.badgeBg.Filled = true
        item.badgeBg.Color = tab.window.theme.controlBg
        item.badgeBg.Thickness = 1
        item.badgeBg.Visible = false
        pcall(function() item.badgeBg.ZIndex = 5 end)
    end

    if item.badgeBorder then
        item.badgeBorder.Filled = false
        item.badgeBorder.Color = tab.window.theme.controlBorder
        item.badgeBorder.Thickness = 1
        item.badgeBorder.Visible = false
        pcall(function() item.badgeBorder.ZIndex = 5 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.keyText then
        item.keyText.Size = 13
        item.keyText.Color = tab.window.theme.text
        item.keyText.Center = true
        item.keyText.Text = string.format("[%s]", item.key)
        item.keyText.Visible = false
    end

    function item:Set(newKey)
        if typeof(newKey) == "EnumItem" then
            newKey = newKey.Name
        end
        item.key = tostring(newKey or "None")
        item.listening = false
        if item.keyText then
            item.keyText.Text = string.format("[%s]", item.key)
            item.keyText.Color = tab.window.theme.text
        end
        if item.flag then
            DrawingUI.Flags[item.flag] = item.key
        end
        pcall(item.callback, item.key)
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.key
        if tab and tab.window and tab.window.itemsByFlag then
            tab.window.itemsByFlag[item.flag] = item
        end
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateInput(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local item = {
        type = "input",
        name = sanitizeText(tostring(cfg.Name or "Input")),
        text = sanitizeText(tostring(cfg.CurrentValue or cfg.Default or "")),
        placeholder = sanitizeText(tostring(cfg.PlaceholderText or "Type here...")),
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        pillInput = createPillInput(5),
        label = createBoldText(6, true),
        valText = createBoldText(6),
        focused = false,
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.valText then
        item.valText.Size = 12
        item.valText.Color = Color3.fromRGB(255, 255, 255)
        pcall(function() item.valText.ZIndex = 8 end)
        item.valText.Text = #item.text > 0 and item.text or item.placeholder
        item.valText.Visible = false
    end

    function item:Set(val)
        local raw = tostring(val or ""):gsub("[^ -~]", "")
        item.text = raw:sub(1, 32)
        if item.valText then
            item.valText.Text = #item.text > 0 and item.text or item.placeholder
        end
        if item.flag then
            DrawingUI.Flags[item.flag] = item.text
        end
        pcall(item.callback, item.text)
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.text
        if tab and tab.window and tab.window.itemsByFlag then
            tab.window.itemsByFlag[item.flag] = item
        end
    end

    table.insert(self.items, item)
    return item
end

-- ============================================================
--   INPUT & INTERACTION SYSTEM
-- ============================================================
function DrawingUI:InitInputHandlers()
    local conn1 = UserInputService.InputBegan:Connect(function(input, processed)
        local isToggleHit = false
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if typeof(self.toggleKey) == "EnumItem" then
                isToggleHit = (input.KeyCode == self.toggleKey)
            elseif type(self.toggleKey) == "string" then
                local tStr = self.toggleKey:lower()
                isToggleHit = (input.KeyCode.Name:lower() == tStr 
                    or (Enum.KeyCode[self.toggleKey] and input.KeyCode == Enum.KeyCode[self.toggleKey]))
            end
        end

        if isToggleHit then
            self:Toggle()
            return
        end

        if not self.visible then return end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mousePos = UserInputService:GetMouseLocation()

            -- 1. Check Traffic Lights (Radius 9 hitbox)
            local trafficRedPos = Vector2.new(self.pos.X + 18, self.pos.Y + 22)
            if pointInCircle(mousePos, trafficRedPos, 9) then
                self:Destroy()
                return
            end

            local trafficYellowPos = Vector2.new(self.pos.X + 36, self.pos.Y + 22)
            if pointInCircle(mousePos, trafficYellowPos, 9) then
                self:Toggle()
                return
            end

            local trafficGreenPos = Vector2.new(self.pos.X + 54, self.pos.Y + 22)
            if pointInCircle(mousePos, trafficGreenPos, 9) then
                return
            end

            -- 2. Header Dragging
            local headerBoxPos = self.pos
            local headerBoxSize = Vector2.new(self.size.X, self.headerHeight)
            if pointInBox(mousePos, headerBoxPos, headerBoxSize) then
                self.dragging = true
                self.dragStart = mousePos
                self.posStart = self.pos
                return
            end

            -- 3. Sidebar Tab Selection
            for idx, tab in ipairs(self.tabs) do
                if tab.hitBox and pointInBox(mousePos, tab.hitBox.pos, tab.hitBox.size) then
                    self.openDropdown = nil
                    self.activeTabIndex = idx
                    return
                end
            end

            -- 3.5. Scroller Thumb & Track Dragging / Clicking
            if self.scrollThumbHitBox and pointInBox(mousePos, self.scrollThumbHitBox.pos, self.scrollThumbHitBox.size) then
                self.openDropdown = nil
                self.draggingScroller = true
                self.scrollerDragStartY = mousePos.Y
                local curTab = self.tabs[self.activeTabIndex]
                self.scrollerStartOffset = curTab and (curTab.targetScroll or curTab.scrollOffset) or 0
                return
            elseif self.scrollTrackHitBox and pointInBox(mousePos, self.scrollTrackHitBox.pos, self.scrollTrackHitBox.size) then
                self.openDropdown = nil
                local curTab = self.tabs[self.activeTabIndex]
                if curTab and curTab.maxScroll > 0 then
                    local rel = math.clamp((mousePos.Y - self.scrollTrackHitBox.pos.Y) / self.scrollTrackHitBox.size.Y, 0, 1)
                    curTab.targetScroll = rel * curTab.maxScroll
                end
                return
            end

            -- 3.8. Active Dropdown Popup Selection (Highest priority overlay)
            if self.openDropdown and self.openDropdown.popupHitBox then
                local popBox = self.openDropdown.popupHitBox
                if pointInBox(mousePos, popBox.pos, popBox.size) then
                    local dd = self.openDropdown
                    local optH = 26
                    local optIndex = math.floor((mousePos.Y - popBox.pos.Y - 5) / optH) + 1
                    if optIndex >= 1 and optIndex <= #dd.options then
                        local chosenOpt = dd.options[optIndex]
                        if dd.multiple then
                            dd:ToggleOption(chosenOpt)
                        else
                            dd:Set(chosenOpt)
                            self.openDropdown = nil
                        end
                    end
                    return
                else
                    local hitOwnBadge = self.openDropdown.badgeHitBox and pointInBox(mousePos, self.openDropdown.badgeHitBox.pos, self.openDropdown.badgeHitBox.size)
                    if not hitOwnBadge then
                        self.openDropdown = nil
                    end
                end
            end

            -- 4. Content Item Interactions
            local curTab = self.tabs[self.activeTabIndex]
            if curTab then
                local hoveredRowFound = false
                for _, sec in ipairs(curTab.sections) do
                    for _, item in ipairs(sec.items) do
                        if item.hitBox and pointInBox(mousePos, item.hitBox.pos, item.hitBox.size) then
                            if item.type == "toggle" then
                                item:Set(not item.value)
                                return
                            elseif item.type == "button" then
                                item:Click()
                                return
                            elseif item.type == "dropdown" then
                                if self.openDropdown == item then
                                    self.openDropdown = nil
                                else
                                    self.openDropdown = item
                                end
                                return
                            elseif item.type == "slider" then
                                self.activeSlider = item
                                if item.trackPos and item.trackWidth then
                                    local rel = math.clamp((mousePos.X - item.trackPos.X) / item.trackWidth, 0, 1)
                                    local rawVal = item.min + (item.max - item.min) * rel
                                    local steps = math.round((rawVal - item.min) / item.increment)
                                    local steppedVal = item.min + steps * item.increment
                                    item:Set(steppedVal)
                                end
                                return
                            elseif item.type == "input" then
                                self.activeInput = item
                                item.focused = true
                                return
                            elseif item.type == "keybind" then
                                item.listening = true
                                if item.keyText then
                                    item.keyText.Text = "[...]"
                                    item.keyText.Color = self.theme.accent
                                end
                                self.activeKeybindListener = item
                                return
                            end
                        end
                    end
                end
            end
        end

        -- Input Box Typing Handling (Complete Number & Text Support)
        if self.activeInput and input.UserInputType == Enum.UserInputType.Keyboard then
            local it = self.activeInput
            if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Escape then
                it.focused = false
                self.activeInput = nil
                pcall(it.callback, it.text)
            elseif input.KeyCode == Enum.KeyCode.Backspace then
                if #it.text > 0 then
                    it:Set(string.sub(it.text, 1, #it.text - 1))
                end
            else
                local codeVal = input.KeyCode.Value
                local keyName = input.KeyCode.Name
                local char = nil

                -- 1. Number keys via KeyCode.Value (0-9: ASCII 48-57)
                if codeVal >= 48 and codeVal <= 57 then
                    char = tostring(codeVal - 48)
                -- 2. Keypad numbers via KeyCode.Value (0-9: 256-265)
                elseif codeVal >= 256 and codeVal <= 265 then
                    char = tostring(codeVal - 256)
                -- 3. Top-row Number Names fallback
                elseif keyName == "Zero" or keyName == "KeypadZero" then char = "0"
                elseif keyName == "One" or keyName == "KeypadOne" then char = "1"
                elseif keyName == "Two" or keyName == "KeypadTwo" then char = "2"
                elseif keyName == "Three" or keyName == "KeypadThree" then char = "3"
                elseif keyName == "Four" or keyName == "KeypadFour" then char = "4"
                elseif keyName == "Five" or keyName == "KeypadFive" then char = "5"
                elseif keyName == "Six" or keyName == "KeypadSix" then char = "6"
                elseif keyName == "Seven" or keyName == "KeypadSeven" then char = "7"
                elseif keyName == "Eight" or keyName == "KeypadEight" then char = "8"
                elseif keyName == "Nine" or keyName == "KeypadNine" then char = "9"
                -- 4. Math symbols & punctuation
                elseif keyName == "Period" or keyName == "KeypadPeriod" then char = "."
                elseif keyName == "Minus" or keyName == "KeypadMinus" then char = "-"
                elseif keyName == "Plus" or keyName == "KeypadPlus" then char = "+"
                elseif keyName == "Slash" or keyName == "KeypadDivide" then char = "/"
                elseif keyName == "Asterisk" or keyName == "KeypadMultiply" then char = "*"
                elseif keyName == "Space" then char = " "
                -- 5. Standard A-Z letters
                elseif #keyName == 1 then
                    local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
                    char = shift and string.upper(keyName) or string.lower(keyName)
                end

                if char and #it.text < 24 then
                    it:Set(it.text .. char)
                end
            end
            return
        end

        -- Keybind Rebinding
        if self.activeKeybindListener and input.UserInputType == Enum.UserInputType.Keyboard then
            local listener = self.activeKeybindListener
            self.activeKeybindListener = nil
            if input.KeyCode ~= Enum.KeyCode.Escape then
                listener:Set(input.KeyCode.Name)
            else
                listener:Set(listener.key)
            end
        end
    end)

    local conn2 = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self.dragging = false
            self.activeSlider = nil
            self.draggingScroller = false
        end
    end)

    local conn3 = UserInputService.InputChanged:Connect(function(input)
        if not self.visible then return end

        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local mousePos = UserInputService:GetMouseLocation()
            if self.dragging then
                self.pos = self.posStart + (mousePos - self.dragStart)
            elseif self.draggingScroller then
                local curTab = self.tabs[self.activeTabIndex]
                if curTab and curTab.maxScroll > 0 and self.scrollerTravel and self.scrollerTravel > 0 then
                    local deltaY = mousePos.Y - self.scrollerDragStartY
                    local deltaScroll = (deltaY / self.scrollerTravel) * curTab.maxScroll
                    curTab.targetScroll = math.clamp(self.scrollerStartOffset + deltaScroll, 0, curTab.maxScroll)
                end
            elseif self.activeSlider then
                local s = self.activeSlider
                if s.trackPos and s.trackWidth then
                    local rel = math.clamp((mousePos.X - s.trackPos.X) / s.trackWidth, 0, 1)
                    local rawVal = s.min + (s.max - s.min) * rel
                    local steps = math.round((rawVal - s.min) / s.increment)
                    local steppedVal = s.min + steps * s.increment
                    s:Set(steppedVal)
                end
            end
        elseif input.UserInputType == Enum.UserInputType.MouseWheel then
            local curTab = self.tabs[self.activeTabIndex]
            if curTab and curTab.maxScroll > 0 then
                curTab.targetScroll = curTab.targetScroll or curTab.scrollOffset or 0
                curTab.targetScroll = math.clamp(curTab.targetScroll - (input.Position.Z * 48), 0, curTab.maxScroll)
            end
        end
    end)

    local conn4 = RunService.RenderStepped:Connect(function()
        if self.running then
            self:Render()
        end
    end)

    table.insert(self.connections, conn1)
    table.insert(self.connections, conn2)
    table.insert(self.connections, conn3)
    table.insert(self.connections, conn4)
end

function DrawingUI:Toggle()
    self.visible = not self.visible
    if not self.visible then
        self.openDropdown = nil
        if self.dropdownPopupCard then self.dropdownPopupCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
        if self.dropdownOptionsPool then
            for _, r in ipairs(self.dropdownOptionsPool) do
                setObjVisible(r.hover, false)
                setObjVisible(r.check, false)
                setObjVisible(r.text, false)
            end
        end
        if self.windowCard then self.windowCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
        if self.keyBadgeCard then self.keyBadgeCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end

        for _, d in pairs(self.drawings) do
            setObjVisible(d, false)
        end
        if self.activeTabPill then self.activeTabPill:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
        setObjVisible(self.activeTabBar, false)
        if self.userCardPill then self.userCardPill:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
        if self.rowHoverCard then self.rowHoverCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
        if self.scrollThumbPill then self.scrollThumbPill:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
        setObjVisible(self.drawings.scrollTrack, false)

        for _, tab in ipairs(self.tabs) do
            setObjVisible(tab.tabText, false)
            if tab.iconObject and type(tab.iconObject.Update) == "function" then
                tab.iconObject:Update(Vector2.zero, Color3.new(), false)
            end
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.accentBar, false)
                setObjVisible(sec.titleDrawing, false)
                if sec.card then sec.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
                for _, item in ipairs(sec.items) do
                    hideItem(item)
                end
            end
        end
    end
end

-- ============================================================
--   MAIN RENDER PIPELINE (1:1 MacLib Aesthetic & Proportions)
-- ============================================================
function DrawingUI:Render()
    if not self.visible then return end

    local p = self.pos
    local sz = self.size
    local sideW = self.sidebarWidth
    local headH = self.headerHeight

    -- Clean border stroke and specular highlight (zero black drop slab)

    -- 1. Main Window 16px Generous Rounded Matte Chassis (Zero Borders)
    if self.windowCard then
        self.windowCard:Update(p, sz, 16, self.theme.bg, self.theme.border, true, "raised")
    end

    -- 2. Left Sidebar Debossed Cavity Surface & Dual-Line Carved Trench
    if self.drawings.sidebarBg then
        self.drawings.sidebarBg.Position = Vector2.new(p.X, p.Y + headH)
        self.drawings.sidebarBg.Size = Vector2.new(sideW, sz.Y - headH - 10)
        self.drawings.sidebarBg.Visible = true
    end

    if self.drawings.sidebarLine then
        self.drawings.sidebarLine.From = Vector2.new(p.X + sideW, p.Y + headH)
        self.drawings.sidebarLine.To = Vector2.new(p.X + sideW, p.Y + sz.Y - 2)
        self.drawings.sidebarLine.Visible = true
    end

    if self.drawings.sidebarLineLight then
        self.drawings.sidebarLineLight.From = Vector2.new(p.X + sideW + 1, p.Y + headH)
        self.drawings.sidebarLineLight.To = Vector2.new(p.X + sideW + 1, p.Y + sz.Y - 2)
        self.drawings.sidebarLineLight.Visible = true
    end

    -- 3. Header Divider (Carved Trench)
    if self.drawings.headerLine then
        self.drawings.headerLine.From = Vector2.new(p.X, p.Y + headH)
        self.drawings.headerLine.To = Vector2.new(p.X + sz.X, p.Y + headH)
        self.drawings.headerLine.Visible = true
    end

    if self.drawings.headerLineLight then
        self.drawings.headerLineLight.From = Vector2.new(p.X, p.Y + headH + 1)
        self.drawings.headerLineLight.To = Vector2.new(p.X + sz.X, p.Y + headH + 1)
        self.drawings.headerLineLight.Visible = true
    end

    -- 4. Traffic Lights with Recessed Sockets
    if self.drawings.socketRed then
        self.drawings.socketRed.Position = Vector2.new(p.X + 18, p.Y + 22)
        self.drawings.socketRed.Visible = true
    end
    if self.drawings.trafficRed then
        self.drawings.trafficRed.Position = Vector2.new(p.X + 18, p.Y + 22)
        self.drawings.trafficRed.Visible = true
    end

    if self.drawings.socketYellow then
        self.drawings.socketYellow.Position = Vector2.new(p.X + 36, p.Y + 22)
        self.drawings.socketYellow.Visible = true
    end
    if self.drawings.trafficYellow then
        self.drawings.trafficYellow.Position = Vector2.new(p.X + 36, p.Y + 22)
        self.drawings.trafficYellow.Visible = true
    end

    if self.drawings.socketGreen then
        self.drawings.socketGreen.Position = Vector2.new(p.X + 54, p.Y + 22)
        self.drawings.socketGreen.Visible = true
    end
    if self.drawings.trafficGreen then
        self.drawings.trafficGreen.Position = Vector2.new(p.X + 54, p.Y + 22)
        self.drawings.trafficGreen.Visible = true
    end

    -- 5. Title & Subtitle (Crisp Bold Typography, Exact 13px Baseline)
    if self.drawings.title then
        self.drawings.title.Position = Vector2.new(p.X + 78, p.Y + 15)
        self.drawings.title.Visible = true
    end

    if self.drawings.subtitle then
        self.drawings.subtitle.Position = Vector2.new(p.X + 175, p.Y + 15)
        self.drawings.subtitle.Visible = true
    end

    -- 6. Top-Right Key Badge (Rounded Pill, Clean 13px Padding)
    local keyName = "RShift"
    if self.toggleKey then
        if typeof(self.toggleKey) == "EnumItem" then
            keyName = self.toggleKey.Name
        else
            keyName = tostring(self.toggleKey)
        end
    end
    local displayKey = keyName
    if displayKey == "RightShift" then displayKey = "RShift"
    elseif displayKey == "LeftShift" then displayKey = "LShift"
    elseif displayKey == "RightControl" then displayKey = "RCtrl"
    elseif displayKey == "LeftControl" then displayKey = "LCtrl"
    elseif displayKey == "RightAlt" then displayKey = "RAlt"
    elseif displayKey == "LeftAlt" then displayKey = "LAlt"
    end

    local hintStr = string.format("[%s] Toggle", displayKey)
    local badgeW = math.max(110, #hintStr * 8 + 24)
    local badgeH = 26
    local badgeX = p.X + sz.X - badgeW - 14
    local badgeY = p.Y + 9

    if self.keyBadgeCard then
        self.keyBadgeCard:Update(Vector2.new(badgeX, badgeY), Vector2.new(badgeW, badgeH), 8, self.theme.controlBg, nil, true, "raised")
    end

    if self.drawings.hint then
        self.drawings.hint.Text = hintStr
        self.drawings.hint.Position = Vector2.new(badgeX + badgeW / 2, badgeY + 6)
        self.drawings.hint.Visible = true
    end

    -- 7. Sidebar Footer (Rounded User Profile Card, Clean 13px Spacing)
    local cardH = 46
    local cardY = p.Y + sz.Y - cardH - 12
    local cardX = p.X + 8
    local cardW = sideW - 16

    if self.userCardPill then
        self.userCardPill:Update(Vector2.new(cardX, cardY), Vector2.new(cardW, cardH), 10, self.theme.neuInsetBg, nil, true, "inset")
    end

    if self.drawings.userDot then
        self.drawings.userDot.Position = Vector2.new(cardX + 14, cardY + 23)
        self.drawings.userDot.Visible = true
    end

    if self.drawings.userName then
        self.drawings.userName.Position = Vector2.new(cardX + 26, cardY + 6)
        self.drawings.userName.Visible = true
    end

    if self.drawings.userStatus then
        self.drawings.userStatus.Position = Vector2.new(cardX + 26, cardY + 23)
        self.drawings.userStatus.Visible = true
    end

    -- 8. Render Tabs in Left Sidebar
    local tabStartY = p.Y + headH + 12
    local tabBtnH = 38
    local tabBtnW = sideW - 16
    local tabX = p.X + 8

    local curTab = self.tabs[self.activeTabIndex]

    for idx, tab in ipairs(self.tabs) do
        local isActive = (idx == self.activeTabIndex)
        local btnY = tabStartY + (idx - 1) * (tabBtnH + 4)

        tab.hitBox = {
            pos = Vector2.new(tabX, btnY),
            size = Vector2.new(tabBtnW, tabBtnH)
        }

        if isActive then
            if self.activeTabPill then
                self.activeTabPill:Update(Vector2.new(tabX, btnY), Vector2.new(tabBtnW, tabBtnH), 10, self.theme.tabActiveBg, Color3.fromRGB(44, 52, 70), true, "raised")
            end
            if self.activeTabBar then
                self.activeTabBar.Position = Vector2.new(tabX + 2, btnY + 8)
                self.activeTabBar.Size = Vector2.new(3, tabBtnH - 16)
                self.activeTabBar.Visible = true
            end
        end

        if tab.iconObject then
            local iconCol = isActive and self.theme.tabActiveBar or self.theme.tabInactive
            tab.iconObject:Update(Vector2.new(tabX + 22, btnY + 19), iconCol, true)
        end

        if tab.tabText then
            local textX = tab.iconObject and (tabX + 38) or (tabX + 16)
            tab.tabText.Position = Vector2.new(textX, btnY + 11)
            tab.tabText.Color = isActive and self.theme.tabActive or self.theme.tabInactive
            tab.tabText.Size = 13
            tab.tabText.Visible = true
        end
    end

    -- 9. Render Active Tab Content on the Right
    local contentLeft = p.X + sideW + 18
    local contentWidth = sz.X - sideW - 36
    local contentTop = p.Y + headH + 14
    local contentMaxHeight = sz.Y - headH - 28

    -- Hide non-active tab elements
    for idx, tab in ipairs(self.tabs) do
        if idx ~= self.activeTabIndex then
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.accentBar, false)
                setObjVisible(sec.titleDrawing, false)
                if sec.card then
                    sec.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
                end
                for _, item in ipairs(sec.items) do
                    hideItem(item)
                end
            end
        end
    end

    local hoveredRowFound = false

    if curTab then
        curTab.targetScroll = curTab.targetScroll or curTab.scrollOffset or 0
        curTab.targetScroll = math.clamp(curTab.targetScroll, 0, curTab.maxScroll or 0)

        -- Butter-smooth exponential damping (easy on the eyes, silky macOS inertia)
        local scrollDiff = curTab.targetScroll - curTab.scrollOffset
        if math.abs(scrollDiff) > 0.2 then
            curTab.scrollOffset = curTab.scrollOffset + scrollDiff * 0.16
        else
            curTab.scrollOffset = curTab.targetScroll
        end

        local cursorY = contentTop - curTab.scrollOffset
        local mousePos = UserInputService:GetMouseLocation()

        for _, sec in ipairs(curTab.sections) do
            -- Precalculate item heights for this section
            local secItemsH = 0
            local itemHeights = {}

            for i, item in ipairs(sec.items) do
                local h = 44
                if item.type == "slider" then
                    h = 58
                elseif item.type == "paragraph" then
                    local numLines = (item.lines and #item.lines > 0) and #item.lines or 1
                    h = 28 + (numLines * 18) + 8
                elseif item.type == "divider" then
                    h = 12
                elseif item.type == "label" then
                    h = 26
                end
                itemHeights[i] = h
                secItemsH = secItemsH + h
            end

            local secCardH = #sec.items > 0 and (secItemsH + 8) or 0

            -- Section Title Header (macOS Uppercase with Vector Accent Bar)
            local titleY = cursorY
            local inTitleBounds = (titleY >= (contentTop - 10) and titleY <= (contentTop + contentMaxHeight - 16))
            if sec.accentBar then
                sec.accentBar.Position = Vector2.new(contentLeft + 4, titleY + 2)
                sec.accentBar.Size = Vector2.new(3, 11)
                sec.accentBar.Color = self.theme.sectionTitle
                sec.accentBar.Visible = inTitleBounds
            end
            if sec.titleDrawing then
                sec.titleDrawing.Position = Vector2.new(contentLeft + 14, titleY)
                sec.titleDrawing.Visible = inTitleBounds
            end
            cursorY = cursorY + 24

            -- Section Group Container Card with Boundary Clamping (Prevent header overflow)
            local cardY = cursorY
            local cardBottom = cardY + secCardH
            local isCardVisible = (secCardH > 0 and cardBottom > contentTop and cardY < (contentTop + contentMaxHeight))

            if isCardVisible then
                local drawCardY = math.max(cardY, contentTop)
                local drawCardBottom = math.min(cardBottom, contentTop + contentMaxHeight)
                local drawCardH = drawCardBottom - drawCardY

                if drawCardH > 4 and sec.card then
                    local isClipped = (cardY < contentTop or cardBottom > (contentTop + contentMaxHeight))
                    local radius = isClipped and 0 or 12
                    sec.card:Update(
                        Vector2.new(contentLeft, drawCardY),
                        Vector2.new(contentWidth, drawCardH),
                        radius,
                        self.theme.cardBg,
                        self.theme.cardBorder,
                        true,
                        "raised"
                    )
                elseif sec.card then
                    sec.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
                end
            else
                if sec.card then
                    sec.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
                end
            end

            -- Render controls inside the Section Container Card
            local rowY = cardY + 4

            for idx, item in ipairs(sec.items) do
                local itemHeight = itemHeights[idx] or 44
                local inBounds = (rowY >= contentTop and (rowY + itemHeight) <= (contentTop + contentMaxHeight))

                if inBounds and isCardVisible then
                    item.hitBox = {
                        pos = Vector2.new(contentLeft, rowY),
                        size = Vector2.new(contentWidth, itemHeight)
                    }

                    local isHovered = pointInBox(mousePos, item.hitBox.pos, item.hitBox.size)

                    -- Hide sharp legacy rectangle hover
                    if item.hoverBg then
                        item.hoverBg.Visible = false
                    end

                    -- Smooth Rounded Neumorphic Hover Pill
                    local canHover = not self.dragging and not self.draggingScroller and not self.openDropdown
                    if isHovered and item.type ~= "divider" and not hoveredRowFound and canHover then
                        hoveredRowFound = true
                        if self.rowHoverCard then
                            self.rowHoverCard:Update(
                                Vector2.new(contentLeft + 6, rowY + 2),
                                Vector2.new(contentWidth - 12, itemHeight - 4),
                                8,
                                self.theme.rowHover,
                                nil,
                                true,
                                "raised"
                            )
                        end
                    end

                    -- Subtle inner divider line between items inside card
                    if item.innerDivider then
                        if idx < #sec.items and item.type ~= "divider" then
                            item.innerDivider.From = Vector2.new(contentLeft + 16, rowY + itemHeight)
                            item.innerDivider.To = Vector2.new(contentLeft + contentWidth - 16, rowY + itemHeight)
                            item.innerDivider.Color = self.theme.rowDivider
                            item.innerDivider.Thickness = 1
                            item.innerDivider.Visible = true
                        else
                            item.innerDivider.Visible = false
                        end
                    end

                    -- Specific item controls
                    if item.type == "toggle" then
                        local pillW = 38
                        local pillH = 22
                        local pillX = contentLeft + contentWidth - pillW - 16
                        local pillY = rowY + math.floor((itemHeight - pillH) / 2)

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 14)
                            item.label.Visible = true
                        end

                        if item.pill then
                            item.pill:Update(
                                Vector2.new(pillX, pillY),
                                Vector2.new(pillW, pillH),
                                item.value,
                                self.theme.toggleOn,
                                self.theme.toggleOff,
                                self.theme.toggleBorder,
                                self.theme.knob,
                                true
                            )
                        end

                    elseif item.type == "slider" then
                        local badgeW = 74
                        local badgeH = 22
                        local badgeX = contentLeft + contentWidth - badgeW - 16
                        local badgeY = rowY + 6

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 9)
                            item.label.Visible = true
                        end

                        -- Hide legacy square badge
                        if item.valBadgeBg then item.valBadgeBg.Visible = false end
                        if item.valBadgeBorder then item.valBadgeBorder.Visible = false end

                        -- Debossed Capsule Value Badge (border-radius: 9999px • box-shadow: inset 2px 5px 10px rgb(5,5,5))
                        if item.valBadgeCapsule then
                            item.valBadgeCapsule:Update(Vector2.new(badgeX, badgeY), Vector2.new(badgeW, badgeH), false, true)
                        end

                        if item.valText then
                            item.valText.Position = Vector2.new(badgeX + badgeW / 2, badgeY + 4)
                            local valDisplay = item.value
                            if type(valDisplay) == "number" and valDisplay ~= math.floor(valDisplay) then
                                valDisplay = string.format("%.3f", valDisplay):gsub("%.?0+$", "")
                            end
                            item.valText.Text = string.format("%s%s", tostring(valDisplay), item.suffix)
                            item.valText.Color = Color3.fromRGB(255, 255, 255) -- color: #fff
                            item.valText.Center = true
                            item.valText.Visible = true
                        end

                        local trackW = contentWidth - 32
                        local trackH = 6
                        local trackX = contentLeft + 16
                        local trackY = rowY + 40
                        local fillW = math.clamp(((item.value - item.min) / math.max(0.0001, (item.max - item.min))) * trackW, 0, trackW)

                        item.trackPos = Vector2.new(trackX, trackY)
                        item.trackWidth = trackW

                        if item.track then
                            item.track.Position = Vector2.new(trackX, trackY)
                            item.track.Size = Vector2.new(trackW, trackH)
                            item.track.Color = self.theme.sliderTrack
                            item.track.Visible = true
                        end

                        if item.fill then
                            item.fill.Position = Vector2.new(trackX, trackY)
                            item.fill.Size = Vector2.new(fillW, trackH)
                            item.fill.Color = self.theme.sliderFill
                            item.fill.Visible = true
                        end

                        if item.knob then
                            item.knob.Position = Vector2.new(trackX + fillW, trackY + 3)
                            item.knob.Visible = true
                        end

                    elseif item.type == "button" then
                        local btnW = contentWidth - 32
                        local btnH = 34
                        local btnX = contentLeft + 16
                        local btnY = rowY + 5

                        if item.buttonCard then
                            local btnBg = isHovered and self.theme.neuRaisedHover or self.theme.controlBg
                            item.buttonCard:Update(Vector2.new(btnX, btnY), Vector2.new(btnW, btnH), 8, btnBg, nil, true, "raised")
                        end

                        if item.label then
                            item.label.Position = Vector2.new(btnX + btnW / 2, btnY + 9)
                            item.label.Visible = true
                        end

                    elseif item.type == "dropdown" then
                        local badgeW = 160
                        local badgeH = 28
                        local badgeX = contentLeft + contentWidth - badgeW - 16
                        local badgeY = rowY + 8

                        item.badgeX = badgeX
                        item.badgeY = badgeY
                        item.badgeW = badgeW
                        item.badgeH = badgeH
                        item.badgeHitBox = {
                            pos = Vector2.new(badgeX, badgeY),
                            size = Vector2.new(badgeW, badgeH)
                        }

                        if item.label then
                            local maxLabelLen = math.max(10, math.floor((contentWidth - badgeW - 38) / 7.5))
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 14)
                            item.label.Text = truncateText(item.name, maxLabelLen)
                            item.label.Visible = true
                        end

                        if item.badgeBg then item.badgeBg.Visible = false end
                        if item.badgeBorder then item.badgeBorder.Visible = false end

                        local isOpen = (self.openDropdown == item)
                        if item.badgeCapsule then
                            item.badgeCapsule:Update(Vector2.new(badgeX, badgeY), Vector2.new(badgeW, badgeH), isOpen, true)
                        end

                        if item.valText then
                            local maxPillChars = math.max(8, math.floor((badgeW - 38) / 7.5))
                            local dispVal = item:GetDisplayValue()
                            item.valText.Position = Vector2.new(badgeX + 16, badgeY + math.floor((badgeH - 12) / 2))
                            item.valText.Text = truncateText(dispVal, maxPillChars)
                            item.valText.Color = isOpen and self.theme.accent or Color3.fromRGB(255, 255, 255)
                            item.valText.Visible = true
                        end

                        if item.arrow then
                            item.arrow.Position = Vector2.new(badgeX + badgeW - 18, badgeY + math.floor((badgeH - 12) / 2))
                            item.arrow.Text = isOpen and "^" or "v"
                            item.arrow.Color = isOpen and self.theme.accent or self.theme.textMuted
                            item.arrow.Visible = true
                        end

                    elseif item.type == "keybind" then
                        local badgeW = 96
                        local badgeH = 26
                        local badgeX = contentLeft + contentWidth - badgeW - 16
                        local badgeY = rowY + 9

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 14)
                            item.label.Visible = true
                        end

                        if item.badgeBg then item.badgeBg.Visible = false end
                        if item.badgeBorder then item.badgeBorder.Visible = false end

                        if item.badgeCapsule then
                            item.badgeCapsule:Update(Vector2.new(badgeX, badgeY), Vector2.new(badgeW, badgeH), item.listening, true)
                        end

                        if item.keyText then
                            item.keyText.Position = Vector2.new(badgeX + badgeW / 2, badgeY + math.floor((badgeH - 12) / 2))
                            item.keyText.Color = item.listening and self.theme.accent or Color3.fromRGB(255, 255, 255)
                            item.keyText.Visible = true
                        end

                    elseif item.type == "paragraph" then
                        if item.titleText then
                            item.titleText.Position = Vector2.new(contentLeft + 16, rowY + 8)
                            item.titleText.Visible = true
                        end

                        local lineY = rowY + 28
                        local lines = item.lines or { item.content or "" }
                        for lineIdx, lineStr in ipairs(lines) do
                            local lineObj = item.descLines and item.descLines[lineIdx]
                            if lineObj then
                                lineObj.Text = lineStr
                                lineObj.Position = Vector2.new(contentLeft + 16, lineY)
                                lineObj.Visible = true
                                lineY = lineY + 18
                            end
                        end
                        if item.descLines then
                            for extraIdx = #lines + 1, #item.descLines do
                                setObjVisible(item.descLines[extraIdx], false)
                            end
                        end

                    elseif item.type == "label" then
                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 6)
                            item.label.Visible = true
                        end

                    elseif item.type == "divider" then
                        if item.line then
                            item.line.From = Vector2.new(contentLeft + 16, rowY + 6)
                            item.line.To = Vector2.new(contentLeft + contentWidth - 16, rowY + 6)
                            item.line.Visible = true
                        end

                    elseif item.type == "input" then
                        local inW = 180
                        local inH = 30
                        local inX = contentLeft + contentWidth - inW - 16
                        local inY = rowY + math.floor((itemHeight - inH) / 2)

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 14)
                            item.label.Visible = true
                        end

                        local isFocused = (self.activeInput == item)
                        item.focused = isFocused

                        if item.pillInput then
                            item.pillInput:Update(
                                Vector2.new(inX, inY),
                                Vector2.new(inW, inH),
                                isFocused,
                                true
                            )
                        end

                        if item.valText then
                            pcall(function() item.valText.ZIndex = 8 end)
                            item.valText.Size = 13
                            local cursorChar = (isFocused and (math.floor(tick() * 2) % 2 == 0)) and "|" or ""
                            if isFocused then
                                item.valText.Text = item.text .. cursorChar
                                item.valText.Color = Color3.fromRGB(255, 255, 255)
                            else
                                if #item.text > 0 then
                                    item.valText.Text = item.text
                                    item.valText.Color = Color3.fromRGB(255, 255, 255)
                                else
                                    item.valText.Text = item.placeholder
                                    item.valText.Color = Color3.fromRGB(135, 145, 165)
                                end
                            end

                            item.valText.Position = Vector2.new(inX + 16, inY + math.floor((inH - 13) / 2))
                            item.valText.Visible = true
                        end
                    end
                else
                    hideItem(item)
                end

                rowY = rowY + itemHeight
            end

            cursorY = cursorY + secCardH + 16
        end

        if not hoveredRowFound and self.rowHoverCard then
            self.rowHoverCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
        end

        local totalH = cursorY - (contentTop - curTab.scrollOffset)
        curTab.maxScroll = math.max(0, totalH - contentMaxHeight)

        -- 10. Render Vertical Scroller (Apple Soft UI Track & Smooth Capsule Thumb)
        local scrollerX = contentLeft + contentWidth + 8
        local scrollerW = 5
        local scrollerY = contentTop + 4
        local scrollerH = contentMaxHeight - 8

        if curTab.maxScroll > 0 then
            if self.drawings.scrollTrack then
                self.drawings.scrollTrack.Position = Vector2.new(scrollerX, scrollerY)
                self.drawings.scrollTrack.Size = Vector2.new(scrollerW, scrollerH)
                self.drawings.scrollTrack.Visible = true
            end

            local thumbH = math.clamp(math.floor(scrollerH * (contentMaxHeight / (totalH + 1))), 28, scrollerH - 10)
            local thumbTravel = scrollerH - thumbH
            self.scrollerTravel = thumbTravel
            local thumbProgress = math.clamp(curTab.scrollOffset / curTab.maxScroll, 0, 1)
            local thumbY = scrollerY + math.floor(thumbProgress * thumbTravel)

            self.scrollThumbHitBox = {
                pos = Vector2.new(scrollerX - 4, thumbY),
                size = Vector2.new(scrollerW + 8, thumbH)
            }
            self.scrollTrackHitBox = {
                pos = Vector2.new(scrollerX - 4, scrollerY),
                size = Vector2.new(scrollerW + 8, scrollerH)
            }

            local isThumbHovered = pointInBox(mousePos, self.scrollThumbHitBox.pos, self.scrollThumbHitBox.size)
            local thumbColor = (self.draggingScroller or isThumbHovered)
                and Color3.fromRGB(88, 166, 255)
                or Color3.fromRGB(56, 66, 88)

            if self.scrollThumbPill then
                self.scrollThumbPill:Update(
                    Vector2.new(scrollerX, thumbY),
                    Vector2.new(scrollerW, thumbH),
                    2,
                    thumbColor,
                    nil,
                    true,
                    "raised"
                )
            end
        else
            setObjVisible(self.drawings.scrollTrack, false)
            if self.scrollThumbPill then
                self.scrollThumbPill:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
            end
            self.scrollThumbHitBox = nil
            self.scrollTrackHitBox = nil
            self.scrollerTravel = 0
        end
    else
        setObjVisible(self.drawings.scrollTrack, false)
        if self.scrollThumbPill then
            self.scrollThumbPill:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
        end
        if self.rowHoverCard then
            self.rowHoverCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
        end
        self.scrollThumbHitBox = nil
        self.scrollTrackHitBox = nil
        self.scrollerTravel = 0
    end

    -- 11. Render Active Dropdown Popup Floating Menu (Layer 25 - highest z-index)
    if self.openDropdown and self.openDropdown.tab == curTab and self.openDropdown.badgeHitBox then
        local dd = self.openDropdown
        local badgeX = dd.badgeX or (contentLeft + contentWidth - 176)
        local badgeY = dd.badgeY or contentTop
        local badgeW = dd.badgeW or 160
        local badgeH = dd.badgeH or 28

        local popW = math.max(badgeW, 180)
        local optH = 26
        local maxVisibleOpts = 8
        local numOpts = math.min(#dd.options, maxVisibleOpts)
        local popH = numOpts * optH + 10
        local popX = math.clamp(badgeX + badgeW - popW, contentLeft, p.X + sz.X - popW - 10)
        local popY = badgeY + badgeH + 4

        if popY + popH > (p.Y + sz.Y - 10) then
            popY = badgeY - popH - 4
        end

        dd.popupHitBox = {
            pos = Vector2.new(popX, popY),
            size = Vector2.new(popW, popH)
        }

        if not self.dropdownPopupCard then
            self.dropdownPopupCard = createRoundedCard(25)
        end
        if not self.dropdownOptionsPool then
            self.dropdownOptionsPool = {}
        end
        self.dropdownPopupCard:Update(
            Vector2.new(popX, popY),
            Vector2.new(popW, popH),
            8,
            Color3.fromRGB(24, 28, 38),
            Color3.fromRGB(56, 68, 96),
            true,
            "raised"
        )

        local mousePos = UserInputService:GetMouseLocation()
        for i = 1, numOpts do
            local opt = dd.options[i]
            local oY = popY + 5 + (i - 1) * optH
            local isSelected = dd:IsSelected(opt)
            local isHover = pointInBox(mousePos, Vector2.new(popX + 4, oY), Vector2.new(popW - 8, optH))

            local row = self.dropdownOptionsPool[i]
            if not row then
                row = {
                    hover = safeDrawing("Square"),
                    check = createBoldText(26),
                    text = createBoldText(26),
                }
                if row.hover then
                    row.hover.Filled = true
                    row.hover.Thickness = 1
                    pcall(function() row.hover.ZIndex = 25 end)
                end
                self.dropdownOptionsPool[i] = row
            end

            if isHover or isSelected then
                row.hover.Position = Vector2.new(popX + 4, oY)
                row.hover.Size = Vector2.new(popW - 8, optH)
                row.hover.Color = isSelected and Color3.fromRGB(42, 54, 78) or Color3.fromRGB(32, 38, 52)
                row.hover.Visible = true
            else
                row.hover.Visible = false
            end

            if isSelected then
                row.check.Position = Vector2.new(popX + 8, oY + 5)
                row.check.Text = "✓"
                row.check.Color = self.theme.accent
                row.check.Size = 13
                row.check.Visible = true
            else
                row.check.Visible = false
            end

            local maxOptChars = math.max(12, math.floor((popW - 36) / 7.5))
            row.text.Position = Vector2.new(popX + 24, oY + 5)
            row.text.Text = truncateText(tostring(opt), maxOptChars)
            row.text.Color = isSelected and Color3.fromRGB(255, 255, 255) or self.theme.textMuted
            row.text.Size = 13
            row.text.Visible = true
        end

        for j = numOpts + 1, #self.dropdownOptionsPool do
            local r = self.dropdownOptionsPool[j]
            if r then
                setObjVisible(r.hover, false)
                setObjVisible(r.check, false)
                setObjVisible(r.text, false)
            end
        end
    else
        if self.dropdownPopupCard then
            self.dropdownPopupCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
        end
        if self.dropdownOptionsPool then
            for _, r in ipairs(self.dropdownOptionsPool) do
                setObjVisible(r.hover, false)
                setObjVisible(r.check, false)
                setObjVisible(r.text, false)
            end
        end
    end
end

-- ============================================================
--   CLEANUP & UNLOAD HANDLERS
-- ============================================================
function DrawingUI:Destroy()
    -- 1. Support static / module-level invocation (e.g. HubUI:Destroy())
    if self == DrawingUI or not self.tabs then
        if DrawingUI._activeWindows then
            for _, win in ipairs(DrawingUI._activeWindows) do
                if win and type(win.Destroy) == "function" and win ~= self then
                    pcall(function() win:Destroy() end)
                end
            end
            table.clear(DrawingUI._activeWindows)
        end
        local env = (type(getgenv) == "function" and getgenv()) or _G
        if env and env.__RAVEN_DRAWING_WINDOW and type(env.__RAVEN_DRAWING_WINDOW.Destroy) == "function" then
            pcall(function() env.__RAVEN_DRAWING_WINDOW:Destroy() end)
            env.__RAVEN_DRAWING_WINDOW = nil
        end
        if DrawingUI._allDrawings then
            for _, d in ipairs(DrawingUI._allDrawings) do
                removeObj(d)
            end
            table.clear(DrawingUI._allDrawings)
        end
        return
    end

    -- 2. Instance-level destruction
    self.running = false
    self.visible = false

    local env = (type(getgenv) == "function" and getgenv()) or _G
    if env and env.__RAVEN_DRAWING_WINDOW == self then
        env.__RAVEN_DRAWING_WINDOW = nil
    end

    if self._unloadCallbacks then
        for _, cb in ipairs(self._unloadCallbacks) do
            pcall(cb)
        end
        table.clear(self._unloadCallbacks)
    end

    if self.connections then
        for _, conn in ipairs(self.connections) do
            if conn and conn.Disconnect then
                pcall(function() conn:Disconnect() end)
            end
        end
        table.clear(self.connections)
    end

    if self.drawings then
        for _, d in pairs(self.drawings) do
            removeObj(d)
        end
        table.clear(self.drawings)
    end

    if self.windowCard then self.windowCard:Remove() end
    if self.keyBadgeCard then self.keyBadgeCard:Remove() end
    if self.activeTabPill then self.activeTabPill:Remove() end
    removeObj(self.activeTabBar)
    if self.userCardPill then self.userCardPill:Remove() end
    if self.rowHoverCard then self.rowHoverCard:Remove() end
    if self.scrollThumbPill then self.scrollThumbPill:Remove() end
    if self.dropdownPopupCard then self.dropdownPopupCard:Remove() end
    if self.dropdownOptionsPool then
        for _, r in ipairs(self.dropdownOptionsPool) do
            removeObj(r.hover)
            removeObj(r.check)
            removeObj(r.text)
        end
        table.clear(self.dropdownOptionsPool)
    end
    self.openDropdown = nil

    if self.tabs then
        for _, tab in ipairs(self.tabs) do
            removeObj(tab.tabText)
            if tab.iconObject then
                pcall(function()
                    if type(tab.iconObject.Remove) == "function" then
                        tab.iconObject:Remove()
                    end
                end)
            end
            if tab.sections then
                for _, sec in ipairs(tab.sections) do
                    removeObj(sec.accentBar)
                    removeObj(sec.titleDrawing)
                    if sec.card then sec.card:Remove() end
                    if sec.items then
                        for _, item in ipairs(sec.items) do
                            removeItem(item)
                        end
                        table.clear(sec.items)
                    end
                end
                table.clear(tab.sections)
            end
        end
        table.clear(self.tabs)
    end

    if self.itemsByFlag then
        table.clear(self.itemsByFlag)
        self.itemsByFlag = nil
    end

    -- 3. Comprehensive sweep: eliminate 100% of residual drawings
    if DrawingUI._allDrawings then
        for _, d in ipairs(DrawingUI._allDrawings) do
            removeObj(d)
        end
        table.clear(DrawingUI._allDrawings)
    end

    if DrawingUI._activeWindows then
        for idx, win in ipairs(DrawingUI._activeWindows) do
            if win == self then
                table.remove(DrawingUI._activeWindows, idx)
                break
            end
        end
    end
end

return DrawingUI
