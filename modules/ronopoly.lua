-- ═════════════════════════════════════════════════════════════════
-- Ronopoly 🎲 | RAVEN HUB Module v1.0.0
-- PlaceId: 6875760739 | GameId: 2621511041
-- Features: Tile ESP | Owner & Rent Info | Dice Probability Predictor | Player Net Worth
-- ═════════════════════════════════════════════════════════════════

return function(Window, scriptInfo)
    local Players           = game:GetService("Players")
    local Workspace         = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService        = game:GetService("RunService")
    local Camera            = Workspace.CurrentCamera

    local LocalPlayer = Players.LocalPlayer

    local environment = getgenv and getgenv() or _G
    if type(environment.__RAVEN_RONOPOLY) == "table"
        and type(environment.__RAVEN_RONOPOLY.Destroy) == "function" then
        pcall(environment.__RAVEN_RONOPOLY.Destroy)
    end

    local running = true
    local drawings = {}
    local connections = {}

    local settings = {
        tileEspEnabled       = true,
        showOwnedOnly        = false,
        showRentPrice        = true,
        showPlotPrice        = true,
        dicePredictorEnabled = true,
        playerNetWorthEsp    = true,
        maxDistance          = 1500,
    }

    local DICE_PROBABILITIES = {
        [2] = {chance = 2.78, combos = 1},
        [3] = {chance = 5.56, combos = 2},
        [4] = {chance = 8.33, combos = 3},
        [5] = {chance = 11.11, combos = 4},
        [6] = {chance = 13.89, combos = 5},
        [7] = {chance = 16.67, combos = 6},
        [8] = {chance = 13.89, combos = 5},
        [9] = {chance = 11.11, combos = 4},
        [10] = {chance = 8.33, combos = 3},
        [11] = {chance = 5.56, combos = 2},
        [12] = {chance = 2.78, combos = 1}
    }

    local function createDrawing(class, props)
        local obj = Drawing.new(class)
        for k, v in pairs(props or {}) do
            obj[k] = v
        end
        table.insert(drawings, obj)
        return obj
    end

    local tileDrawings = {}
    local predictorDrawings = {}
    local netWorthDrawings = {}

    local function getBoardPieces()
        return Workspace:FindFirstChild("boardPieces")
    end

    local function getPieces()
        return Workspace:FindFirstChild("Pieces")
    end

    local function getLocalPiece()
        local pcs = getPieces()
        if not pcs then return nil end
        for _, p in ipairs(pcs:GetChildren()) do
            local pl = p:FindFirstChild("Player")
            if pl and pl.Value == LocalPlayer.Name then
                return p
            end
        end
        return nil
    end

    local function getTilePosition(tileModel)
        if not tileModel then return nil end
        local pavement = tileModel:FindFirstChild("pavement") or tileModel:FindFirstChildWhichIsA("BasePart")
        if pavement then
            return pavement.Position
        end
        return nil
    end

    local function cleanupDrawings()
        for _, d in ipairs(drawings) do
            pcall(function() d:Remove() end)
        end
        table.clear(drawings)
        table.clear(tileDrawings)
        table.clear(predictorDrawings)
        table.clear(netWorthDrawings)
    end

    for i = 0, 31 do
        local txt = createDrawing("Text", {
            Size = 13,
            Center = true,
            Outline = true,
            OutlineColor = Color3.new(0, 0, 0),
            Visible = false,
            ZIndex = 2
        })
        tileDrawings[i] = txt
    end

    for i = 2, 12 do
        local line = createDrawing("Line", {
            Thickness = 1.5,
            Color = Color3.fromRGB(255, 215, 0),
            Transparency = 0.8,
            Visible = false,
            ZIndex = 1
        })
        local txt = createDrawing("Text", {
            Size = 12,
            Center = true,
            Outline = true,
            OutlineColor = Color3.new(0, 0, 0),
            Visible = false,
            ZIndex = 3
        })
        predictorDrawings[i] = {line = line, text = txt}
    end

    for i = 1, 6 do
        local txt = createDrawing("Text", {
            Size = 14,
            Center = false,
            Outline = true,
            OutlineColor = Color3.new(0, 0, 0),
            Visible = false,
            ZIndex = 4
        })
        netWorthDrawings[i] = txt
    end

    local updateConn = RunService.RenderStepped:Connect(function()
        if not running then return end

        local boardPieces = getBoardPieces()
        local myPiece = getLocalPiece()
        local myCurrentTile = myPiece and myPiece:GetAttribute("currentTile") or 0

        -- 1. Tile ESP
        if settings.tileEspEnabled and boardPieces then
            for i = 0, 31 do
                local tileModel = boardPieces:FindFirstChild(tostring(i))
                local drawObj = tileDrawings[i]

                if tileModel and drawObj then
                    local pos = getTilePosition(tileModel)
                    if pos then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(pos + Vector3.new(0, 3, 0))
                        local dist = (Camera.CFrame.Position - pos).Magnitude

                        if onScreen and dist <= settings.maxDistance then
                            local tType = tileModel:FindFirstChild("Type") and tileModel.Type.Value or tileModel:GetAttribute("tileType") or "Tile"
                            local ownerVal = tileModel:FindFirstChild("owner") and tileModel.owner.Value or ""
                            local priceVal = tileModel:FindFirstChild("price") and tileModel.price.Value or 0
                            local taxVal = tileModel:FindFirstChild("taxPrice") and tileModel.taxPrice.Value or 0
                            local bloxyCount = tileModel:FindFirstChild("bloxyCount") and tileModel.bloxyCount.Value or 0
                            local isShielded = tileModel:FindFirstChild("shielded") and tileModel.shielded.Value or false

                            local isOwned = ownerVal ~= ""
                            local isMine = isOwned and (ownerVal == LocalPlayer.Name)

                            if settings.showOwnedOnly and not isOwned then
                                drawObj.Visible = false
                            else
                                local color = Color3.fromRGB(180, 180, 180)
                                if isMine then
                                    color = Color3.fromRGB(50, 255, 100) -- Green for owned by local
                                elseif isOwned then
                                    color = Color3.fromRGB(255, 75, 75) -- Red for owned by opponents
                                elseif priceVal > 0 then
                                    color = Color3.fromRGB(80, 175, 255) -- Blue for unowned buyable
                                end

                                local lines = {}
                                table.insert(lines, string.format("[%d] %s", i, tileModel.Name))

                                if isOwned then
                                    local ownerTag = isMine and "YOU" or ownerVal
                                    table.insert(lines, string.format("Owner: %s", ownerTag))
                                    if settings.showRentPrice and taxVal > 0 then
                                        table.insert(lines, string.format("Rent: $%d", taxVal))
                                    end
                                    if bloxyCount > 0 then
                                        table.insert(lines, string.format("Houses: %d", bloxyCount))
                                    end
                                    if isShielded then
                                        table.insert(lines, "[SHIELDED]")
                                    end
                                elseif priceVal > 0 and settings.showPlotPrice then
                                    table.insert(lines, string.format("Price: $%d", priceVal))
                                end

                                drawObj.Text = table.concat(lines, "\n")
                                drawObj.Position = Vector2.new(screenPos.X, screenPos.Y)
                                drawObj.Color = color
                                drawObj.Visible = true
                            end
                        else
                            drawObj.Visible = false
                        end
                    else
                        drawObj.Visible = false
                    end
                elseif drawObj then
                    drawObj.Visible = false
                end
            end
        else
            for _, d in pairs(tileDrawings) do
                d.Visible = false
            end
        end

        -- 2. Dice Predictor (Landing Probabilities)
        if settings.dicePredictorEnabled and myPiece and boardPieces then
            local startPos = myPiece.PrimaryPart and myPiece.PrimaryPart.Position or (myPiece:FindFirstChild("Part") and myPiece.Part.Position)
            local startScreen, startOnScreen = startPos and Camera:WorldToViewportPoint(startPos)

            for roll = 2, 12 do
                local targetTileIndex = (myCurrentTile + roll) % 32
                local targetTile = boardPieces:FindFirstChild(tostring(targetTileIndex))
                local pDraw = predictorDrawings[roll]

                if targetTile and pDraw and startPos and startOnScreen then
                    local targetPos = getTilePosition(targetTile)
                    if targetPos then
                        local endScreen, endOnScreen = Camera:WorldToViewportPoint(targetPos + Vector3.new(0, 1.5, 0))

                        if endOnScreen then
                            local prob = DICE_PROBABILITIES[roll]
                            local ownerVal = targetTile:FindFirstChild("owner") and targetTile.owner.Value or ""
                            local isMine = ownerVal == LocalPlayer.Name
                            local isDanger = (ownerVal ~= "") and not isMine

                            local lineColor = isDanger and Color3.fromRGB(255, 60, 60) or (isMine and Color3.fromRGB(60, 255, 120) or Color3.fromRGB(255, 215, 0))
                            if roll == 7 then
                                pDraw.line.Thickness = 3
                            else
                                pDraw.line.Thickness = 1.5
                            end

                            pDraw.line.From = Vector2.new(startScreen.X, startScreen.Y)
                            pDraw.line.To = Vector2.new(endScreen.X, endScreen.Y)
                            pDraw.line.Color = lineColor
                            pDraw.line.Visible = true

                            pDraw.text.Text = string.format("+%d (%.1f%%)", roll, prob.chance)
                            pDraw.text.Position = Vector2.new(endScreen.X, endScreen.Y - 18)
                            pDraw.text.Color = lineColor
                            pDraw.text.Visible = true
                        else
                            pDraw.line.Visible = false
                            pDraw.text.Visible = false
                        end
                    else
                        pDraw.line.Visible = false
                        pDraw.text.Visible = false
                    end
                elseif pDraw then
                    pDraw.line.Visible = false
                    pDraw.text.Visible = false
                end
            end
        else
            for _, p in pairs(predictorDrawings) do
                p.line.Visible = false
                p.text.Visible = false
            end
        end

        -- 3. Player Net Worth Billboard
        if settings.playerNetWorthEsp then
            local pcs = getPieces()
            local idx = 1
            if pcs then
                for _, piece in ipairs(pcs:GetChildren()) do
                    local plVal = piece:FindFirstChild("Player")
                    local txtObj = netWorthDrawings[idx]

                    if plVal and txtObj then
                        local pName = plVal.Value
                        local tileIdx = piece:GetAttribute("currentTile") or 0
                        local primary = piece.PrimaryPart or piece:FindFirstChild("Part")

                        if primary then
                            local sPos, onScreen = Camera:WorldToViewportPoint(primary.Position + Vector3.new(0, 4, 0))
                            if onScreen then
                                local isMe = pName == LocalPlayer.Name
                                txtObj.Text = string.format("%s%s [Tile %d]", isMe and "★ " or "", pName, tileIdx)
                                txtObj.Position = Vector2.new(sPos.X - 40, sPos.Y)
                                txtObj.Color = isMe and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 255, 255)
                                txtObj.Visible = true
                            else
                                txtObj.Visible = false
                            end
                        else
                            txtObj.Visible = false
                        end
                        idx = idx + 1
                    end
                end
            end
            for j = idx, 6 do
                if netWorthDrawings[j] then
                    netWorthDrawings[j].Visible = false
                end
            end
        else
            for _, d in pairs(netWorthDrawings) do
                d.Visible = false
            end
        end
    end)
    table.insert(connections, updateConn)

    -- ═════════════════════════════════════════════════════════════════
    --   GUI CREATION
    -- ═════════════════════════════════════════════════════════════════

    local VisualsTab = Window:CreateTab("Visuals & ESP", 10734950309)

    VisualsTab:CreateSection("🎲 Board & Tile ESP")

    VisualsTab:CreateToggle({
        Name = "Tile ESP (3D Highlight)",
        CurrentValue = settings.tileEspEnabled,
        Flag = "RNP_TileEsp",
        Callback = function(val)
            settings.tileEspEnabled = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Rent Price",
        CurrentValue = settings.showRentPrice,
        Flag = "RNP_ShowRent",
        Callback = function(val)
            settings.showRentPrice = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Buy Price",
        CurrentValue = settings.showPlotPrice,
        Flag = "RNP_ShowPrice",
        Callback = function(val)
            settings.showPlotPrice = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Owned Only",
        CurrentValue = settings.showOwnedOnly,
        Flag = "RNP_ShowOwnedOnly",
        Callback = function(val)
            settings.showOwnedOnly = val
        end,
    })

    VisualsTab:CreateSlider({
        Name = "Max ESP Distance",
        Range = {100, 3000},
        Increment = 50,
        Suffix = " studs",
        CurrentValue = settings.maxDistance,
        Flag = "RNP_MaxDist",
        Callback = function(val)
            settings.maxDistance = val
        end,
    })

    VisualsTab:CreateSection("🎯 Dice Probability Predictor")

    VisualsTab:CreateToggle({
        Name = "Landing Predictor (2-12 Probabilities)",
        CurrentValue = settings.dicePredictorEnabled,
        Flag = "RNP_DicePredictor",
        Callback = function(val)
            settings.dicePredictorEnabled = val
        end,
    })

    VisualsTab:CreateSection("👤 Player Tracking")

    VisualsTab:CreateToggle({
        Name = "Player Piece & Tile Tag",
        CurrentValue = settings.playerNetWorthEsp,
        Flag = "RNP_PlayerNetWorth",
        Callback = function(val)
            settings.playerNetWorthEsp = val
        end,
    })

    Window:SortTabs({"Visuals & ESP", "Settings"})

    local moduleObj = {}
    function moduleObj.Destroy()
        running = false
        for _, c in ipairs(connections) do
            pcall(function() c:Disconnect() end)
        end
        cleanupDrawings()
    end

    environment.__RAVEN_RONOPOLY = moduleObj
    return moduleObj
end