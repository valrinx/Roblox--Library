-- RAVEN HUB | Blade Ball - Auto Parry, Ball ESP, Player ESP
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local localPlayer = Players.LocalPlayer
    local running = true
    local connections = {}
    local espObjects = {}
    local ballEspObjects = {}
    local parryCount = 0
    local lastParryTick = 0
    local settings = {
        autoParry = false, parryDistance = 15, parryMode = "Distance",
        pingCompensation = true, ballEsp = false, playerEsp = false, espShowDistance = true,
    }
    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end
    local function getCharacter(plr)
        local character = plr and plr.Character
        return character and character.Parent and character or nil
    end
    local function getRoot(character)
        return character and character:FindFirstChild("HumanoidRootPart")
    end
    local function isAlive(plr)
        local alive = workspace:FindFirstChild("Alive")
        local character = getCharacter(plr)
        return character and alive and character.Parent == alive
    end
    local function getPingMs()
        if not settings.pingCompensation then return 0 end
        local ok, value = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        return ok and (tonumber(value) or 0) or 0
    end
    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function() ui:Notify({Title = title, Content = content, Duration = 5}) end)
        end
    end
    local ballsFolder = workspace:WaitForChild("Balls", 5)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local parryRemote = remotes and remotes:FindFirstChild("ParryAttempt")
    local function getRealBalls()
        if not ballsFolder then return {} end
        local results = {}
        for _, ball in ipairs(ballsFolder:GetChildren()) do
            if ball:IsA("BasePart") then
                local realBall = ball:GetAttribute("realBall")
                if realBall == "true" or realBall == true then table.insert(results, ball) end
            end
        end
        return results
    end
    local function getBallTargetingMe()
        for _, ball in ipairs(getRealBalls()) do
            if ball:GetAttribute("target") == localPlayer.Name then return ball end
        end
        return nil
    end
    local function getBallSpeed(ball)
        local velocity = ball:FindFirstChild("zoomies")
        if velocity and velocity:IsA("LinearVelocity") then return velocity.VectorVelocity.Magnitude end
        return ball.AssemblyLinearVelocity.Magnitude
    end
    local function getBallDistance(ball)
        local root = getRoot(getCharacter(localPlayer))
        if not root or not ball then return math.huge end
        return (ball.Position - root.Position).Magnitude
    end
    local function shouldParry(ball)
        if not ball then return false end
        local distance = getBallDistance(ball)
        local speed = getBallSpeed(ball)
        if settings.parryMode == "Distance" then
            return distance <= (settings.parryDistance + getPingMs() / 1000 * speed + math.random() * 2)
        else
            local timeToReach = speed > 0 and (distance / speed) or math.huge
            return timeToReach <= (0.3 + getPingMs() / 2000)
        end
    end
    local function doParry()
        local now = tick()
        if now - lastParryTick < 0.4 then return end
        lastParryTick = now
        parryCount += 1
        if parryRemote then
            pcall(function() parryRemote:FireServer() end)
        end
    end

    local function createBallEsp(ball)
        if ballEspObjects[ball] then return end
        local hl = Instance.new("Highlight"); hl.Name="RavenBallESP"; hl.FillColor=Color3.fromRGB(255,50,50)
        hl.FillTransparency=0.3; hl.OutlineTransparency=0; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop
        hl.Adornee=ball; hl.Parent=ball
        local bb = Instance.new("BillboardGui"); bb.Name="RavenBallInfo"; bb.Size=UDim2.fromOffset(120,40)
        bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true; bb.Adornee=ball; bb.Parent=ball
        local lbl = Instance.new("TextLabel"); lbl.Name="Info"; lbl.Size=UDim2.fromScale(1,1)
        lbl.BackgroundTransparency=1; lbl.TextColor3=Color3.fromRGB(255,80,80)
        lbl.TextStrokeTransparency=0.5; lbl.TextStrokeColor3=Color3.new(0,0,0)
        lbl.Font=Enum.Font.GothamBold; lbl.TextSize=14; lbl.Text=""; lbl.Parent=bb
        ballEspObjects[ball] = {highlight=hl, billboard=bb, label=lbl}
    end
    local function removeBallEsp(ball)
        local o = ballEspObjects[ball]
        if o then pcall(function() o.highlight:Destroy() end); pcall(function() o.billboard:Destroy() end); ballEspObjects[ball]=nil end
    end
    local function clearAllBallEsp() for ball in pairs(ballEspObjects) do removeBallEsp(ball) end end
    local function updateBallEsp()
        if not settings.ballEsp then clearAllBallEsp(); return end
        local active = {}
        for _, ball in ipairs(getRealBalls()) do
            active[ball] = true; createBallEsp(ball)
            local o = ballEspObjects[ball]
            if o then
                local t = ball:GetAttribute("target") or "?"
                local d = math.floor(getBallDistance(ball))
                local s = math.floor(getBallSpeed(ball))
                local isMe = t == localPlayer.Name
                o.label.Text = string.format("%s [%dm] %d spd", t, d, s)
                o.label.TextColor3 = isMe and Color3.fromRGB(255,50,50) or Color3.fromRGB(255,200,50)
                o.highlight.FillColor = isMe and Color3.fromRGB(255,50,50) or Color3.fromRGB(255,200,50)
            end
        end
        for ball in pairs(ballEspObjects) do if not active[ball] or not ball.Parent then removeBallEsp(ball) end end
    end
    local function createPlayerEsp(plr)
        if plr == localPlayer or espObjects[plr] then return end
        local hl = Instance.new("Highlight"); hl.Name="RavenPlayerESP"; hl.FillTransparency=0.7
        hl.OutlineTransparency=0; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Enabled=false
        local bb = Instance.new("BillboardGui"); bb.Name="RavenPlayerInfo"; bb.Size=UDim2.fromOffset(150,30)
        bb.StudsOffset=Vector3.new(0,3.5,0); bb.AlwaysOnTop=true; bb.Enabled=false
        local lbl = Instance.new("TextLabel"); lbl.Name="Info"; lbl.Size=UDim2.fromScale(1,1)
        lbl.BackgroundTransparency=1; lbl.TextColor3=Color3.fromRGB(130,220,255)
        lbl.TextStrokeTransparency=0.5; lbl.TextStrokeColor3=Color3.new(0,0,0)
        lbl.Font=Enum.Font.GothamBold; lbl.TextSize=13; lbl.Text=plr.Name; lbl.Parent=bb
        espObjects[plr] = {highlight=hl, billboard=bb, label=lbl}
    end
    local function removePlayerEsp(plr)
        local o = espObjects[plr]
        if o then pcall(function() o.highlight:Destroy() end); pcall(function() o.billboard:Destroy() end); espObjects[plr]=nil end
    end
    local function clearAllPlayerEsp() for plr in pairs(espObjects) do removePlayerEsp(plr) end end
    local function updatePlayerEsp()
        if not settings.playerEsp then clearAllPlayerEsp(); return end
        local myRoot = getRoot(getCharacter(localPlayer))
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= localPlayer then
                createPlayerEsp(plr); local o = espObjects[plr]
                local c = getCharacter(plr); local root = getRoot(c)
                if o and c and root then
                    local a = isAlive(plr)
                    o.highlight.Adornee=c; o.highlight.Parent=c; o.highlight.Enabled=true
                    o.highlight.FillColor = a and Color3.fromRGB(50,200,100) or Color3.fromRGB(150,150,150)
                    o.highlight.OutlineColor = a and Color3.fromRGB(130,255,180) or Color3.fromRGB(100,100,100)
                    o.highlight.FillTransparency = a and 0.7 or 0.9
                    o.billboard.Adornee=root; o.billboard.Parent=c; o.billboard.Enabled=true
                    local text = plr.DisplayName
                    if settings.espShowDistance and myRoot then
                        text = text.." ["..math.floor((root.Position-myRoot.Position).Magnitude).."m]"
                    end
                    o.label.Text = text
                    o.label.TextColor3 = a and Color3.fromRGB(130,220,255) or Color3.fromRGB(150,150,150)
                elseif o then o.highlight.Enabled=false; o.billboard.Enabled=false end
            end
        end
        for plr in pairs(espObjects) do if not plr.Parent then removePlayerEsp(plr) end end
    end
    local statusLabel
    connect(RunService.Heartbeat, function()
        if not running then return end
        if settings.autoParry and isAlive(localPlayer) then
            local ball = getBallTargetingMe()
            if ball and shouldParry(ball) then doParry() end
        end
        updateBallEsp(); updatePlayerEsp()
    end)
    connect(Players.PlayerRemoving, function(plr) removePlayerEsp(plr) end)
    local CombatTab = Window:CreateTab("Combat", "combat")
    CombatTab:CreateSection("Auto Parry")
    statusLabel = CombatTab:CreateLabel("Parries: 0 | Status: Idle")
    CombatTab:CreateToggle({Name="Auto Parry",CurrentValue=false,Flag="BBAutoParry",Callback=function(v) settings.autoParry=v; if v then notify("Blade Ball","Auto Parry enabled") end end})
    CombatTab:CreateDropdown({Name="Parry Mode",Options={"Distance","Time-Based"},CurrentOption={"Distance"},MultipleOptions=false,Flag="BBParryMode",Callback=function(v) settings.parryMode=type(v)=="table" and v[1] or tostring(v) end})
    CombatTab:CreateSlider({Name="Parry Distance",Range={5,35},Increment=1,Suffix=" studs",CurrentValue=15,Flag="BBParryDistance",Callback=function(v) settings.parryDistance=v end})
    CombatTab:CreateToggle({Name="Ping Compensation",CurrentValue=true,Flag="BBPingComp",Callback=function(v) settings.pingCompensation=v end})
    local VisualTab = Window:CreateTab("Visual", "esp")
    VisualTab:CreateSection("Ball ESP")
    VisualTab:CreateToggle({Name="Ball ESP",CurrentValue=false,Flag="BBBallEsp",Callback=function(v) settings.ballEsp=v; if not v then clearAllBallEsp() end end})
    VisualTab:CreateSection("Player ESP")
    VisualTab:CreateToggle({Name="Player ESP",CurrentValue=false,Flag="BBPlayerEsp",Callback=function(v) settings.playerEsp=v; if not v then clearAllPlayerEsp() end end})
    VisualTab:CreateToggle({Name="Show Distance",CurrentValue=true,Flag="BBEspDistance",Callback=function(v) settings.espShowDistance=v end})
    local MiscTab = Window:CreateTab("Misc", "misc")
    MiscTab:CreateSection("Utilities")
    MiscTab:CreateButton({Name="Rejoin Server",Callback=function() pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId,game.JobId) end) end})
    MiscTab:CreateButton({Name="Server Hop",Callback=function() pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId) end) end})
    task.spawn(function()
        while running do task.wait(0.5)
            if statusLabel then
                local ball = getBallTargetingMe()
                local st = settings.autoParry and (ball and string.format("Tracking [%dm %dspd]",math.floor(getBallDistance(ball)),math.floor(getBallSpeed(ball))) or (isAlive(localPlayer) and "Waiting..." or "Dead")) or "Idle"
                pcall(function() statusLabel:Set(string.format("Parries: %d | %s", parryCount, st)) end)
            end
        end
    end)
    local function destroyScript()
        if not running then return end; running = false
        for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
        table.clear(connections); clearAllBallEsp(); clearAllPlayerEsp()
    end
    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then scriptInfo.registerCleanup(destroyScript) end
end
