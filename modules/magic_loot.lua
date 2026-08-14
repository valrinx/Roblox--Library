-- RAVEN HUB | Magic Loot automation suite
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedFirst = game:GetService("ReplicatedFirst")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local HttpService = game:GetService("HttpService")
    local TeleportService = game:GetService("TeleportService")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local VirtualUser = game:GetService("VirtualUser")

    local player = Players.LocalPlayer
    local environment = getgenv()
    if type(environment.__RAVEN_MAGIC_LOOT) == "table"
        and type(environment.__RAVEN_MAGIC_LOOT.Destroy) == "function" then
        pcall(environment.__RAVEN_MAGIC_LOOT.Destroy)
    end
    local running = true
    local connections = {}
    local highlights = {}
    local returnCFrame = nil
    local trainingCache = environment.__RAVEN_MAGIC_LOOT_GROUNDS or {}
    environment.__RAVEN_MAGIC_LOOT_GROUNDS = trainingCache
    local LOCKED_MARKER = utf8.char(0x672A, 0x89E3, 0x9501)
    local safeSpotFolder = "RAVENHUB-" .. tostring(game.GameId ~= 0 and game.GameId or game.PlaceId)
    local safeSpotFile = safeSpotFolder .. "/magic_loot_safe_spots.json"
    local safeSpots = {}

    local function decodeCFrame(values)
        if type(values) ~= "table" or #values ~= 12 then return nil end
        local numbers = {}
        for index = 1, 12 do
            numbers[index] = tonumber(values[index])
            if not numbers[index] then return nil end
        end
        return CFrame.new(table.unpack(numbers))
    end

    if type(isfile) == "function" and type(readfile) == "function" and isfile(safeSpotFile) then
        pcall(function()
            local decoded = HttpService:JSONDecode(readfile(safeSpotFile))
            for stage, values in pairs(decoded) do
                local cframe = decodeCFrame(values)
                if cframe then safeSpots[tostring(stage)] = cframe end
            end
        end)
    end

    local settings = {
        autoTrain = false,
        trainMode = "Best Available",
        trainKeepPosition = true,
        autoTrainingPotion = false,
        autoRebirth = false,
        rebirthInterval = 8,
        autoEquipWeapon = false,
        autoEquipArmor = false,
        autoEquipBroom = false,
        autoSell = false,
        sellInterval = 45,
        autoRewards = false,
        autoAlchemy = false,
        autoEventRewards = false,
        autoFarm = false,
        autoDungeon = false,
        autoMoney = false,
        moneyStage = 1,
        moneyBagSlots = 20,
        moneyKeepIds = {},
        useSafeSpots = true,
        skillInterval = 0.65,
        autoDrops = false,
        dropPriority = "Rarity then Price",
        monsterEsp = false,
        dropEsp = false,
        antiAfk = true,
        lowGraphics = false,
        autoRejoin = false,
    }

    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function()
                ui:Notify({Title = title, Content = content, Duration = 5})
            end)
        end
    end

    local function setStatus(label, text)
        if not label or type(label.Set)~="function" then return false end
        return pcall(function() label:Set(text) end)
    end

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function getCharacter()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        return character, humanoid, root
    end

    local function currentCombatStage()
        local dungeon = player:FindFirstChild("InDungeonChallenge")
        local aggro = player:FindFirstChild("DungeonAggroStage")
        local stage = math.max(dungeon and dungeon.Value or 0, aggro and aggro.Value or 0)
        if stage <= 0 then
            local career = player:FindFirstChild("CareerMaxStage")
            stage = career and career.Value or 0
        end
        return math.max(0, math.floor(tonumber(stage) or 0))
    end

    local function findStageArea(stage, attribute)
        stage = math.max(0, math.floor(tonumber(stage) or 0))
        for _, object in ipairs(workspace:GetDescendants()) do
            if object:IsA("BasePart") and object:GetAttribute(attribute) == true
                and tonumber(object:GetAttribute("Stage")) == stage then
                return object
            end
        end
        return nil
    end

    local function isPointInsidePart(part, position, margin)
        if not part or typeof(position) ~= "Vector3" then return false end
        local point = part.CFrame:PointToObjectSpace(position)
        local half = part.Size * 0.5
        margin = math.max(0, tonumber(margin) or 0)
        return math.abs(point.X) <= math.max(0, half.X-margin)
            and math.abs(point.Y) <= half.Y+8
            and math.abs(point.Z) <= math.max(0, half.Z-margin)
    end

    local function stageAtPosition(position)
        if typeof(position)~="Vector3" then return nil end
        for _,object in ipairs(workspace:GetDescendants()) do
            if object:IsA("BasePart") and object:GetAttribute("BattleArea")==true
                and isPointInsidePart(object,position,0) then
                return math.floor(tonumber(object:GetAttribute("Stage")) or 0),object
            end
        end
        return nil
    end

    local function persistSafeSpots()
        if type(writefile) ~= "function" then return false end
        if next(safeSpots) == nil and type(isfile) == "function" and type(delfile) == "function"
            and isfile(safeSpotFile) then
            return pcall(delfile, safeSpotFile)
        end
        if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(safeSpotFolder) then
            makefolder(safeSpotFolder)
        end
        local encoded = {}
        for stage, cframe in pairs(safeSpots) do
            encoded[stage] = {cframe:GetComponents()}
        end
        local ok, json = pcall(HttpService.JSONEncode, HttpService, encoded)
        if not ok then return false end
        return pcall(writefile, safeSpotFile, json)
    end

    local function saveCurrentSafeSpot()
        local _, _, root = getCharacter()
        local dungeon = player:FindFirstChild("InDungeonChallenge")
        local officialSafe = player:FindFirstChild("InStageSafeArea")
        -- DungeonAggroStage can remain on the old stage after automation is
        -- disabled. Prefer the BattleArea physically containing the player so
        -- Save writes to the stage the player is actually standing in.
        local stage = stageAtPosition(root.Position) or currentCombatStage()
        if not root or stage <= 0 then return false, stage, "Unable to detect the current stage" end
        if not dungeon or dungeon.Value <= 0 then
            return false, stage, "Enter the stage before saving its combat safe spot"
        end
        if officialSafe and officialSafe.Value > 0 then
            return false, stage, "Walk out of the official safe area before saving (skills are disabled there)"
        end
        local battleArea = findStageArea(stage, "BattleArea")
        if battleArea and not isPointInsidePart(battleArea, root.Position, 2) then
            return false, stage, "Move inside the Stage "..stage.." battle area before saving"
        end
        safeSpots[tostring(stage)] = root.CFrame
        persistSafeSpots()
        warn("[RAVEN HUB][Magic Loot] saved Stage "..stage.." safe spot at "..tostring(root.Position))
        return true, stage
    end

    local function clearCurrentSafeSpot()
        local stage = currentCombatStage()
        if stage <= 0 then return false, stage end
        safeSpots[tostring(stage)] = nil
        persistSafeSpots()
        return true, stage
    end

    local function screenGui()
        local playerGui = player:FindFirstChildOfClass("PlayerGui")
        return playerGui and playerGui:FindFirstChild("ScreenGui")
    end

    local function guiModules()
        local clientCode = ReplicatedStorage:FindFirstChild("ClientSideCode")
        local scripts = clientCode and clientCode:FindFirstChild("GuiScripts")
        return scripts and scripts:FindFirstChild("ModuleScript")
    end

    local function openModule(name)
        local root = guiModules()
        local moduleScript = root and root:FindFirstChild(name)
        if not moduleScript then
            return nil
        end
        local ok, module = pcall(require, moduleScript)
        if not ok or type(module) ~= "table" then
            return nil
        end
        if type(module.openUi) == "function" then
            pcall(module.openUi)
            task.wait(0.12)
        end
        return module
    end

    local function closeModule(module)
        if module and type(module.closeUi) == "function" then
            pcall(module.closeUi)
        end
    end

    local function activate(button)
        if not button or not button.Parent then
            return false
        end
        local fired = false
        if type(firesignal) == "function" then
            -- These UI helpers bind the same action to both signals. Firing both
            -- can submit purchases/claims twice, so use the canonical signal once.
            fired = pcall(function()
                firesignal(button.Activated)
            end)
        elseif type(getconnections) == "function" then
            for _, connection in ipairs(getconnections(button.Activated)) do
                local ok = pcall(function()
                    if connection.Function then
                        connection.Function()
                    else
                        connection:Fire()
                    end
                end)
                fired = fired or ok
            end
        end
        return fired
    end

    local function ancestorText(instance, depthLimit)
        local parts = {}
        local node = instance
        for _ = 1, depthLimit or 3 do
            if not node then break end
            for _, descendant in ipairs(node:GetDescendants()) do
                if descendant:IsA("TextLabel") and descendant.Text ~= "" then
                    table.insert(parts, descendant.Text)
                    if #parts >= 16 then break end
                end
            end
            node = node.Parent
        end
        return string.lower(table.concat(parts, " "))
    end

    local function isActuallyVisible(object)
        local node = object
        while node and node:IsA("GuiObject") do
            if not node.Visible then return false end
            node = node.Parent
        end
        return true
    end

    local function clickPanelButtons(panelName, predicate, maximum)
        local gui = screenGui()
        local panel = gui and gui:FindFirstChild(panelName)
        if not panel then
            return 0
        end
        local count = 0
        for _, object in ipairs(panel:GetDescendants()) do
            if (object:IsA("TextButton") or object:IsA("ImageButton")) and isActuallyVisible(object) then
                local text = object:IsA("TextButton") and object.Text or ""
                local context = ancestorText(object.Parent, 2)
                if predicate(object, string.lower(text), context) and activate(object) then
                    count += 1
                    task.wait(0.08)
                    if maximum and count >= maximum then break end
                end
            end
        end
        return count
    end

    local function parseMultiplier(text)
        local number = tostring(text):match("[xX]%s*([%d%.]+)")
        return tonumber(number) or 0
    end

    local function collectTrainingGrounds()
        local grounds = {}
        for _, gui in ipairs(workspace:GetDescendants()) do
            if gui:IsA("BillboardGui") and gui.Name == "TrainGui" then
                local root = gui.Parent
                local model = root and root.Parent
                local multiplier = 0
                local labels = {}
                for _, object in ipairs(gui:GetDescendants()) do
                    if object:IsA("TextLabel") then
                        table.insert(labels, object.Text)
                        multiplier = math.max(multiplier, parseMultiplier(object.Text))
                    end
                end
                if root and root:IsA("BasePart") and model then
                    local locked = string.find(model.Name, LOCKED_MARKER, 1, true) ~= nil
                    local ground = {
                        root = root,
                        cframe = root.CFrame,
                        model = model,
                        multiplier = multiplier,
                        locked = locked,
                        labels = labels,
                    }
                    table.insert(grounds, ground)
                    if multiplier > 0 then
                        trainingCache[multiplier] = {
                            cframe = root.CFrame,
                            multiplier = multiplier,
                            locked = locked,
                            labels = labels,
                        }
                    end
                end
            end
        end
        table.sort(grounds, function(a, b)
            return a.multiplier > b.multiplier
        end)
        return grounds
    end

    local function selectTrainingGround()
        local grounds = collectTrainingGrounds()
        if settings.trainMode == "Admin x500" then
            for _, ground in ipairs(grounds) do
                if ground.multiplier >= 500 then return ground end
            end
            if trainingCache[500] then return trainingCache[500] end
            -- Admin grounds are temporary/server-specific. Fall through to the
            -- best unlocked public ground when x500 is not currently spawned.
        elseif settings.trainMode ~= "Best Available" then
            local wanted = tonumber(settings.trainMode:match("[%d%.]+"))
            for _, ground in ipairs(grounds) do
                if ground.multiplier == wanted then return ground end
            end
        end
        for _, ground in ipairs(grounds) do
            if not ground.locked then return ground end
        end
        return grounds[#grounds]
    end

    local function trainingCFrame(ground)
        local source = ground and (ground.root and ground.root.CFrame or ground.cframe)
        if not source then return nil end

        -- TrainGui is attached to the crystal itself. Teleporting to that exact
        -- CFrame embeds the character in the collidable prop, which can lock
        -- movement and place the camera inside the mesh. Find nearby floor
        -- space while remaining close enough to activate the training zone.
        local character, humanoid, root = getCharacter()
        local characterFolder = workspace:FindFirstChild("Characters")
        local excluded = {}
        if character then table.insert(excluded, character) end
        if characterFolder and characterFolder ~= character then table.insert(excluded, characterFolder) end
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = excluded
        rayParams.IgnoreWater = true
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = excluded

        local rootHeight = root and root.Size.Y or 2
        local hipHeight = humanoid and humanoid.HipHeight or 2
        local standingOffset = hipHeight + rootHeight * 0.5 + 0.15
        local directions = {
            -- The public grounds face the open walkway on their -X side.
            Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1),
            Vector3.new(0, 0, -1), Vector3.new(1, 0, 0),
            Vector3.new(0.707, 0, 0.707), Vector3.new(-0.707, 0, 0.707),
            Vector3.new(0.707, 0, -0.707), Vector3.new(-0.707, 0, -0.707),
        }
        for _, radius in ipairs({5.25, 6.25}) do
            for _, direction in ipairs(directions) do
                local horizontal = source.Position + direction * radius
                local hit = workspace:Raycast(horizontal + Vector3.new(0, 14, 0), Vector3.new(0, -35, 0), rayParams)
                local surface = hit and hit.Instance
                local surfaceSize = surface and surface:IsA("BasePart") and surface.Size or nil
                local broadFlatSurface = surface == workspace.Terrain or (surfaceSize
                    and hit.Normal.Y > 0.96 and surfaceSize.Y <= 3.5
                    and math.min(surfaceSize.X, surfaceSize.Z) >= 3.5)
                if hit and broadFlatSurface then
                    local position = Vector3.new(horizontal.X, hit.Position.Y + standingOffset, horizontal.Z)
                    local blocked = false
                    for _, part in ipairs(workspace:GetPartBoundsInBox(
                        CFrame.new(position + Vector3.new(0, 0.35, 0)),
                        Vector3.new(3.5, math.max(4, rootHeight), 3.5), overlapParams
                    )) do
                        -- Ignore layered floor/decor pieces below the root;
                        -- only geometry extending into the torso can trap it.
                        local approximateTop = part.Position.Y + part.Size.Y * 0.5
                        if part.CanCollide and part ~= hit.Instance and approximateTop > position.Y + 0.25 then
                            blocked = true
                            break
                        end
                    end
                    if not blocked then
                        return CFrame.lookAt(position, Vector3.new(source.Position.X, position.Y, source.Position.Z))
                    end
                end
            end
        end

        -- Conservative fallback: offset from the prop even when streamed map
        -- geometry is unavailable for the floor/clearance probes.
        return source * CFrame.new(5.5, 0, 0)
    end

    local function teleportTo(cframe, remember)
        local _, _, root = getCharacter()
        if not root then return false end
        if remember and not returnCFrame then
            returnCFrame = root.CFrame
        end
        root.CFrame = cframe
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    local function returnFromDungeon()
        local gui = player:FindFirstChildOfClass("PlayerGui")
        local full = gui and gui:FindFirstChild("ScreenGui_Full")
        local top = full and full:FindFirstChild("Top")
        local button
        if top then
            for _, object in ipairs(top:GetDescendants()) do
                if object:IsA("GuiButton") and isActuallyVisible(object) then
                    button = object
                    break
                end
            end
        end
        return button and activate(button) or false
    end

    local function leaveTrainingGround()
        local inGround = player:FindFirstChild("InTrainGround")
        local autoTraining = player:FindFirstChild("IsAutoTraining")
        if not ((inGround and inGround.Value) or (autoTraining and autoTraining.Value)) then
            return true
        end
        local _, _, root = getCharacter()
        local destination = returnCFrame or (root and (root.CFrame + Vector3.new(60, 5, 0)))
        if not destination or not teleportTo(destination, false) then return false end
        returnCFrame = nil
        local deadline = os.clock() + 3
        repeat task.wait(0.1)
        until not running or os.clock() >= deadline
            or not ((inGround and inGround.Value) or (autoTraining and autoTraining.Value))
        return not ((inGround and inGround.Value) or (autoTraining and autoTraining.Value))
    end

    local function teleportStage(wantedStage)
        local dungeonState = player:FindFirstChild("InDungeonChallenge")
        wantedStage = math.max(0, math.floor(tonumber(wantedStage) or 0))
        if dungeonState and wantedStage > 0 and dungeonState.Value == wantedStage then
            return true, wantedStage
        end
        if dungeonState and dungeonState.Value ~= 0 then
            if not returnFromDungeon() then return false end
            local deadline = os.clock() + 5
            repeat task.wait(0.1) until not running or dungeonState.Value == 0 or os.clock() >= deadline
            if dungeonState.Value ~= 0 then return false end
        end
        if not leaveTrainingGround() then return false end
        local module = openModule("StageJump")
        local gui = screenGui()
        local panel = gui and gui:FindFirstChild("StageJump")
        local best, bestStage
        if panel then
            for _, object in ipairs(panel:GetDescendants()) do
                if object:IsA("GuiButton") and object.Name == "Button" then
                    local node, stage = object, nil
                    while node and node ~= panel do
                        stage = tonumber(node.Name) or stage
                        node = node.Parent
                    end
                    if stage and isActuallyVisible(object) then
                        if wantedStage > 0 and stage <= wantedStage and (not bestStage or stage > bestStage) then
                            -- Stage Jump exposes checkpoints only. Start at the
                            -- closest checkpoint below the requested stage and
                            -- let the farm unlock each following stage in order.
                            best, bestStage = object, stage
                        elseif wantedStage <= 0 and (not bestStage or stage > bestStage) then
                            best, bestStage = object, stage
                        end
                    end
                end
            end
        end
        local clicked = best and activate(best) or false
        closeModule(module)
        return clicked, bestStage
    end

    local function teleportHighestStage()
        return teleportStage(0)
    end

    local function fallbackStageCFrame(battleArea, entryArea, rotation)
        if not battleArea then return nil end
        local half = battleArea.Size*0.5
        local entryPoint = entryArea and battleArea.CFrame:PointToObjectSpace(entryArea.Position)
            or Vector3.new(0,0,half.Z)
        local inward = Vector3.new(-entryPoint.X,0,-entryPoint.Z)
        inward = inward.Magnitude>0.01 and inward.Unit or Vector3.new(0,0,-1)
        local localPoint = entryPoint+inward*14
        localPoint = Vector3.new(
            math.clamp(localPoint.X,-half.X+6,half.X-6),
            half.Y+20,
            math.clamp(localPoint.Z,-half.Z+6,half.Z-6)
        )
        local probe = battleArea.CFrame:PointToWorldSpace(localPoint)
        local character, humanoid, root = getCharacter()
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = character and {character,battleArea} or {battleArea}
        local hit = workspace:Raycast(probe,Vector3.new(0,-math.max(100,battleArea.Size.Y+60),0),params)
        local rootOffset = (humanoid and humanoid.HipHeight or 2)
            +(root and root.Size.Y*0.5 or 1)
        local position = hit and (hit.Position+Vector3.new(0,rootOffset+0.25,0))
            or battleArea.Position
        return CFrame.new(position)*(rotation or battleArea.CFrame.Rotation)
    end

    local function advanceMoneyStage(stage)
        stage = math.max(1, math.floor(tonumber(stage) or 1))
        local saved = safeSpots[tostring(stage)]
        local battleArea = findStageArea(stage, "BattleArea")
        -- The next stage is often not streamed until the player crosses the
        -- current stage's exit. A persisted safe spot is still valid while its
        -- BattleArea part is absent; validate it once that part has streamed.
        if saved and battleArea and not isPointInsidePart(battleArea, saved.Position, 2) then
            -- Older saved positions may sit a few studs outside the server's
            -- BattleArea (Stage 15 is a known example). Move them just inside
            -- the boundary so crossing the gate can activate the next wave.
            local point = battleArea.CFrame:PointToObjectSpace(saved.Position)
            local half = battleArea.Size*0.5
            local repairedPoint = Vector3.new(
                math.clamp(point.X,-half.X+5,half.X-5),
                math.clamp(point.Y,-half.Y+3,half.Y+6),
                math.clamp(point.Z,-half.Z+5,half.Z-5)
            )
            saved = CFrame.new(battleArea.CFrame:PointToWorldSpace(repairedPoint))*saved.Rotation
            safeSpots[tostring(stage)] = saved
            pcall(persistSafeSpots)
        end
        -- Enter through the next stage's official safe trigger first. Jumping
        -- straight from one BattleArea to another can race the server's door
        -- unlock and leaves the next monster wave unspawned.
        -- SafeArea belongs to the exit of its own stage. To enter Stage N, cross
        -- Stage N-1's exit first; using Stage N's SafeArea skips the spawn gate.
        local safeArea = findStageArea(stage-1, "SafeArea")
            or findStageArea(stage, "SafeArea")
        if safeArea then
            local _,_,root = getCharacter()
            local transitionRotation = saved and saved.Rotation
                or root and root.CFrame.Rotation or safeArea.CFrame.Rotation
            local safeDestination = CFrame.new(safeArea.Position+Vector3.new(0,4,0))
                *transitionRotation
            if not teleportTo(safeDestination, false) then return false, "safe-entry-failed" end
            local officialSafe = player:FindFirstChild("InStageSafeArea")
            local safeDeadline = os.clock()+4
            repeat task.wait(0.1)
                battleArea = battleArea or findStageArea(stage, "BattleArea")
            until not running or os.clock()>=safeDeadline
                or (officialSafe and officialSafe.Value>0) or battleArea
        end
        battleArea = battleArea or findStageArea(stage, "BattleArea")
        if not saved and battleArea then
            saved = fallbackStageCFrame(battleArea,safeArea)
            if saved then
                safeSpots[tostring(stage)] = saved
                pcall(persistSafeSpots)
            end
        end
        if not saved then return false,"stage-not-streamed" end
        if battleArea and not isPointInsidePart(battleArea, saved.Position, 2) then
            return false, "invalid-safe-spot"
        end
        if not teleportTo(saved, false) then return false, "battle-entry-failed" end
        local dungeon = player:FindFirstChild("InDungeonChallenge")
        local aggro = player:FindFirstChild("DungeonAggroStage")
        local deadline = os.clock()+6
        repeat task.wait(0.1)
        until not running or os.clock()>=deadline
            or math.max(dungeon and dungeon.Value or 0, aggro and aggro.Value or 0)>=stage
        return math.max(dungeon and dungeon.Value or 0, aggro and aggro.Value or 0)>=stage,
            "stage-not-activated"
    end

    local function useTrainingPotion()
        pcall(function()
            local core = player.PlayerScripts.ClientScript.Backpack:FindFirstChild("BackpackCore")
            local backpack = core and require(core)
            if backpack and type(backpack.refreshAll) == "function" then backpack.refreshAll() end
        end)
        task.wait(0.05)
        local gui = screenGui()
        local toolbar = gui and gui:FindFirstChild("Main")
        toolbar = toolbar and toolbar:FindFirstChild("Backpack")
        if toolbar then
            for _, object in ipairs(toolbar:GetDescendants()) do
                if object:IsA("GuiObject") and object:FindFirstChild("Slot1") then
                    toolbar = object
                    break
                end
            end
        end
        if not toolbar then return false end
        for _, slot in ipairs(toolbar:GetChildren()) do
            if isActuallyVisible(slot) and ancestorText(slot, 1):find("training potion", 1, true) then
                local button = slot:IsA("GuiButton") and slot or slot:FindFirstChildWhichIsA("GuiButton", true)
                if button then return activate(button) end
            end
        end
        return false
    end

    local function performRebirth()
        local module = openModule("Rebirth")
        local gui = screenGui()
        local panel = gui and gui:FindFirstChild("Rebirth")
        local frame = panel and panel:FindFirstChild("_Frame")
        local progressText = frame and ancestorText(frame, 1) or ""
        local current, required = progressText:match("level%s*</font><font[^>]*>(%d+)</font><font[^>]*>/(%d+)</font>")
        current, required = tonumber(current), tonumber(required)
        local clicked = 0
        if current and required and current >= required then
            local container = frame:FindFirstChild("_RebirthBtn")
            local button = container and container:FindFirstChildWhichIsA("GuiButton", true)
            if button and activate(button) then clicked = 1 end
        end
        local warning = gui and gui:FindFirstChild("WarnWindow")
        if clicked > 0 and warning and warning.Visible then
            local confirm = warning:FindFirstChild("Confirm", true)
            confirm = confirm and (confirm:IsA("GuiButton") and confirm or confirm:FindFirstChildWhichIsA("GuiButton", true))
            if confirm then activate(confirm) end
        end
        closeModule(module)
        return clicked > 0
    end

    local function equipBest(panelName)
        local module = openModule(panelName)
        local gui = screenGui()
        local panel = gui and gui:FindFirstChild(panelName)
        local candidates = {}
        if panel then
            for _, item in ipairs(panel:GetDescendants()) do
                if item:IsA("GuiObject") and item.Name:match("^Equip_%d+$") then
                    local id = tonumber(item.Name:match("(%d+)$")) or 0
                    local context = ancestorText(item, 1)
                    local improvement = tonumber(context:match("better than u best%s*([%d%.]+)%%")) or 0
                    local stage = tonumber(context:match("stage%s*(%d+)")) or 0
                    local score = improvement * 100000 + stage * 1000 + id
                    local equipContainer = item:FindFirstChild("_EquipBtn", true)
                    local isOwned = equipContainer and isActuallyVisible(equipContainer)
                    if isOwned and (panelName ~= "Broom" or stage == 0
                        or stage <= (player:FindFirstChild("CareerMaxStage") and player.CareerMaxStage.Value or 0)) then
                        local button = equipContainer and equipContainer:FindFirstChildWhichIsA("GuiButton", true)
                        table.insert(candidates, {button = button, score = score, id = id})
                    end
                end
            end
        end
        table.sort(candidates, function(a, b) return a.score > b.score end)
        local candidate = candidates[1]
        -- Equipped entries omit/hide their equip button. If the strongest entry
        -- has no actionable button, it is already equipped; never downgrade by
        -- falling through to the next candidate.
        local clicked = candidate ~= nil and candidate.button ~= nil
            and isActuallyVisible(candidate.button) and activate(candidate.button) or false
        closeModule(module)
        return clicked
    end

    local function performSell()
        local module = openModule("Sell")
        local gui = screenGui()
        local panel = gui and gui:FindFirstChild("Sell")
        local bottom = panel and panel:FindFirstChild("Bottom")
        local container = bottom and bottom:FindFirstChild("_SellAll")
        local button = container and container:FindFirstChildWhichIsA("GuiButton", true)
        local clicked = button and isActuallyVisible(button) and activate(button) and 1 or 0
        closeModule(module)
        return clicked > 0
    end

    local function materialBagCount()
        local count = 0
        pcall(function()
            local utilities = require(ReplicatedFirst.AllSideCode.UtilsSystem)
            local bag = utilities.PlayerData.GetPlrDataByKey(player, "Bag")
            local materialType = utilities.EnumMgr.ItemType.Material
            if type(bag) == "table" then
                for _, item in pairs(bag) do
                    -- Locked and recipe-protected materials still occupy bag
                    -- slots. Excluding them prevented the sell threshold from
                    -- ever being reached even when the real bag was full.
                    if type(item) == "table" and tonumber(item.tp) == materialType then
                        count += 1
                    end
                end
            end
        end)
        return count
    end

    local function gameMoneyBagUsage()
        local gui=screenGui()
        local main=gui and gui:FindFirstChild("Main")
        local bottomLeft=main and (main:FindFirstChild("ButtomLeft") or main:FindFirstChild("BottomLeft"))
        if not bottomLeft then return nil,nil end
        for _,object in ipairs(bottomLeft:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                local used,capacity=tostring(object.Text):match("^%s*(%d+)%s*/%s*(%d+)%s*$")
                used,capacity=tonumber(used),tonumber(capacity)
                if used and capacity and capacity>0 then return used,capacity end
            end
        end
        return nil,nil
    end

    local function materialKeepOptions()
        local options, seen = {}, {}
        pcall(function()
            local utilities = require(ReplicatedFirst.AllSideCode.UtilsSystem)
            local materialType = utilities.EnumMgr.ItemType.Material
            local configs = {}
            -- FindCfgByID closes over each complete item-type config table.
            -- Select the table whose rows are Material configs so the dropdown
            -- includes every material, not only items currently in the bag.
            if debug and type(debug.getupvalues)=="function" then
                for _, candidate in pairs(debug.getupvalues(utilities.CfgFind.FindCfgByID)) do
                    if type(candidate)=="table" then
                        local matches = {}
                        for id, config in pairs(candidate) do
                            if type(config)=="table" and tonumber(config.tp)==materialType
                                and tonumber(id) then
                                matches[tonumber(id)] = config
                            end
                        end
                        if (function() local n=0 for _ in pairs(matches) do n+=1 end return n end)()
                            > (function() local n=0 for _ in pairs(configs) do n+=1 end return n end)() then
                            configs = matches
                        end
                    end
                end
            end
            -- Compatibility fallback for executors without debug upvalues.
            if next(configs)==nil then
                local bag = utilities.PlayerData.GetPlrDataByKey(player, "Bag")
                for _, item in pairs(type(bag)=="table" and bag or {}) do
                    local id=type(item)=="table" and tonumber(item.id) or nil
                    if id and tonumber(item.tp)==materialType then
                        configs[id]=utilities.CfgFind.FindCfgByID(id,materialType)
                    end
                end
            end
            for id, config in pairs(configs) do
                if id and config and not seen[id] then
                    seen[id] = true
                    local name = config and (config.ZhName or config.Model or config.Name) or "Material"
                    if config and config.ZhName and utilities.TranslationHelper
                        and type(utilities.TranslationHelper.TranslateByKey)=="function" then
                        local translatedOk, translated = pcall(
                            utilities.TranslationHelper.TranslateByKey, config.ZhName
                        )
                        if translatedOk and type(translated)=="string" and translated~="" then
                            name = translated
                        end
                    end
                    table.insert(options, tostring(id).." | "..tostring(name))
                end
            end
        end)
        table.sort(options, function(a,b)
            return (tonumber(a:match("^%d+")) or 0) < (tonumber(b:match("^%d+")) or 0)
        end)
        if #options == 0 then options = {"No materials found - refresh after collecting"} end
        return options
    end

    local function performMoneySell()
        local candidates = {}
        local unlockedForSale = {}
        local unlockedForSaleSet = {}
        local ok = pcall(function()
            local utilities = require(ReplicatedFirst.AllSideCode.UtilsSystem)
            local bag = utilities.PlayerData.GetPlrDataByKey(player, "Bag")
            local materialType = utilities.EnumMgr.ItemType.Material
            -- Keep-list selection is the Money mode protection source. Unlock
            -- other sellable materials first, otherwise a full bag made only of
            -- locked drops can never be emptied.
            for _, item in pairs(type(bag)=="table" and bag or {}) do
                local id=type(item)=="table" and tonumber(item.id) or nil
                local onlyId=type(item)=="table" and tonumber(item.onlyID) or nil
                local locked=type(item)=="table" and (item.lock==true or item.lock==1)
                local recipeProtected=false
                if id and type(utilities.GetData.IsMarkedRecipeMaterial)=="function" then
                    pcall(function() recipeProtected=utilities.GetData.IsMarkedRecipeMaterial(player,id)==true end)
                end
                if id and onlyId and tonumber(item.tp)==materialType and locked
                    and not recipeProtected and not settings.moneyKeepIds[id] then
                    item.lock=0
                    table.insert(unlockedForSale,onlyId)
                    unlockedForSaleSet[onlyId]=true
                end
            end
            if #unlockedForSale>0 then
                utilities.NetWork.FireServer(utilities.NetMsg.BAG_LOCK_ITEMS,{
                    unlockOnlyIds=unlockedForSale,
                })
                task.wait(0.35)
                bag=utilities.PlayerData.GetPlrDataByKey(player,"Bag")
            end
            for _, item in pairs(type(bag)=="table" and bag or {}) do
                local id = type(item)=="table" and tonumber(item.id) or nil
                local onlyId = type(item)=="table" and tonumber(item.onlyID) or nil
                local locked = type(item)=="table" and (item.lock==true or item.lock==1)
                local recipeProtected = false
                if id and type(utilities.GetData.IsMarkedRecipeMaterial)=="function" then
                    pcall(function() recipeProtected=utilities.GetData.IsMarkedRecipeMaterial(player,id)==true end)
                end
                if id and onlyId and tonumber(item.tp)==materialType
                    and (not locked or unlockedForSaleSet[onlyId])
                    and not recipeProtected and not settings.moneyKeepIds[id] then
                    table.insert(candidates, onlyId)
                end
            end
            if #candidates > 0 then
                local result = utilities.NetWork.InvokeServer(utilities.NetMsg.SELL_MATERIAL, {
                    onlyIDList = candidates,
                })
                if result ~= true then
                    if #unlockedForSale>0 then
                        utilities.NetWork.FireServer(utilities.NetMsg.BAG_LOCK_ITEMS,{
                            lockOnlyIds=unlockedForSale,
                        })
                    end
                    error("server rejected selective sell")
                end
            end
        end)
        return ok, #candidates
    end

    local function isMoneyBagFull()
        local serverLimit = player:FindFirstChild("LimitBagUsed")
        local materialSlots = materialBagCount()
        -- LimitBagUsed is a used-slot counter, not a boolean full flag. Treating
        -- its first increment as "full" made Money mode return safe instantly.
        local gameUsed,gameCapacity=gameMoneyBagUsage()
        local usedSlots=gameUsed or math.max(materialSlots,
            math.floor(tonumber(serverLimit and serverLimit.Value) or 0))
        local threshold=gameCapacity or math.max(1,tonumber(settings.moneyBagSlots) or 20)
        if gameCapacity then settings.moneyBagSlots=gameCapacity end
        local sellableSlots = 0
        pcall(function()
            local utilities=require(ReplicatedFirst.AllSideCode.UtilsSystem)
            local bag=utilities.PlayerData.GetPlrDataByKey(player,"Bag")
            local materialType=utilities.EnumMgr.ItemType.Material
            for _,item in pairs(type(bag)=="table" and bag or {}) do
                local id=type(item)=="table" and tonumber(item.id) or nil
                local recipeProtected=false
                if id and type(utilities.GetData.IsMarkedRecipeMaterial)=="function" then
                    pcall(function() recipeProtected=utilities.GetData.IsMarkedRecipeMaterial(player,id)==true end)
                end
                if id and tonumber(item.tp)==materialType and tonumber(item.onlyID)
                    and not recipeProtected and not settings.moneyKeepIds[id] then
                    sellableSlots+=1
                end
            end
        end)
        local full=gameCapacity and usedSlots>=threshold
            or usedSlots>=threshold and sellableSlots>0
        return full,materialSlots,usedSlots,sellableSlots,threshold
    end

    local function claimOnlineRewards()
        local module = openModule("OnlineAward")
        local count = 0
        local processed = {}
        -- The countdown label can remain visible when a reward becomes ready.
        -- Bg.Visible is the controller's authoritative claimable state.
        for _ = 1, 12 do
            local gui = screenGui()
            local panel = gui and gui:FindFirstChild("OnlineAward")
            local claimed = false
            if panel then
                for _, claimContainer in ipairs(panel:GetDescendants()) do
                    if claimContainer:IsA("GuiObject") and claimContainer.Name == "ClaimBtn"
                        and not processed[claimContainer] and isActuallyVisible(claimContainer) then
                        local available = claimContainer:FindFirstChild("Bg")
                        local button = claimContainer:FindFirstChildWhichIsA("GuiButton", true)
                        if available and available.Visible and button and isActuallyVisible(button)
                            and activate(button) then
                            processed[claimContainer] = true
                            count += 1
                            claimed = true
                            task.wait(0.12)
                            break
                        end
                    end
                end
            end
            if not claimed then break end
        end
        closeModule(module)
        return count
    end

    local function collectAlchemy()
        local module = openModule("Alchemy")
        local gui = screenGui()
        local panel = gui and gui:FindFirstChild("Alchemy")
        local count = 0
        if panel then
            for _, recipe in ipairs(panel:GetDescendants()) do
                if recipe:IsA("GuiObject") and recipe.Name:match("^Recipe_%d+$") then
                    local buttons = recipe:FindFirstChild("Btns", true)
                    local okContainer = buttons and buttons:FindFirstChild("OkBtn")
                    local available = okContainer and okContainer:FindFirstChild("Bg")
                    local button = okContainer and okContainer:FindFirstChildWhichIsA("GuiButton", true)
                    if available and available.Visible and button and isActuallyVisible(button) and activate(button) then
                        count = 1
                        break -- The server permits one active brew at a time.
                    end
                end
            end
        end
        closeModule(module)
        return count
    end

    local function claimEventRewards()
        local module = openModule("Event")
        local gui = screenGui()
        local panel = gui and gui:FindFirstChild("Event")
        local taskTab = panel and panel:FindFirstChild("Tab_Task", true)
        local taskTabButton = taskTab and taskTab:FindFirstChildWhichIsA("GuiButton", true)
        if taskTabButton then
            activate(taskTabButton)
            task.wait(0.12)
        end
        local count = 0
        local taskFrame = panel and panel:FindFirstChild("_Task", true)
        if taskFrame then
            for _, row in ipairs(taskFrame:GetChildren()) do
                if row:IsA("GuiObject") and row.Name:match("^Task_") then
                    local okContainer = row:FindFirstChild("OkBtn", true)
                    local available = okContainer and okContainer:FindFirstChild("Bg")
                    local button = okContainer and okContainer:FindFirstChildWhichIsA("GuiButton", true)
                    if available and available.Visible and button and isActuallyVisible(button) and activate(button) then
                        count += 1
                        task.wait(0.1)
                    end
                end
            end
        end
        closeModule(module)
        return count
    end

    local function humanoidModel(instance)
        local model = instance:IsA("Model") and instance or instance:FindFirstAncestorOfClass("Model")
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
        if humanoid and humanoid.Health > 0 and root then
            return model, humanoid, root
        end
    end

    local function nearestMonster(preferredStage)
        local _, _, localRoot = getCharacter()
        if not localRoot then return nil end
        local best, bestDistance
        local seen = {}
        for _, folderName in ipairs({"Monster", "LocalMonster"}) do
            local folder = workspace:FindFirstChild(folderName)
            if folder then
                for _, descendant in ipairs(folder:GetDescendants()) do
                    local model, humanoid, root = humanoidModel(descendant)
                    if model and not seen[model] then
                        seen[model] = true
                        local stage = tonumber(model:GetAttribute("Stage"))
                        local allowed = tostring(model:GetAttribute("AllowedPlayerIds") or "")
                        local belongsToPlayer = allowed == "" or allowed:find(tostring(player.UserId), 1, true) ~= nil
                        local combatReady = model:GetAttribute("CombatReady") ~= false
                        local stageMatches = not preferredStage or preferredStage <= 0 or stage == preferredStage
                        if not (belongsToPlayer and combatReady and stageMatches) then continue end
                        local distance = (root.Position - localRoot.Position).Magnitude
                        if not bestDistance or distance < bestDistance then
                            best = {model = model, humanoid = humanoid, root = root}
                            bestDistance = distance
                        end
                    end
                end
            end
        end
        return best
    end

    local skillInput, skillSlotConfig
    pcall(function()
        local manager = player:WaitForChild("PlayerScripts", 5)
        manager = manager and manager:FindFirstChild("Manager")
        manager = manager and manager:FindFirstChild("PlayerSkillClientManager")
        if manager then
            skillInput = require(manager:FindFirstChild("PlayerSkillInput"))
            skillSlotConfig = require(manager:FindFirstChild("SkillSlotConfig"))
        end
    end)

    local nextSkillSlot = 1
    local function castSkills()
        if skillInput and skillSlotConfig and type(skillInput.simulateSlotPressRelease) == "function" then
            local maximum = math.clamp(player:FindFirstChild("SkillMax") and player.SkillMax.Value or 2, 1, skillSlotConfig.MAX_SKILL_COUNT)
            if nextSkillSlot > maximum then nextSkillSlot = 1 end
            local fired = skillInput.simulateSlotPressRelease(nextSkillSlot)
            nextSkillSlot = nextSkillSlot % maximum + 1
            if not fired then
                fired = skillInput.simulateSlotPressRelease(skillSlotConfig.NORMAL_ATTACK_SLOT_INDEX)
            end
            return fired
        end

        -- Fallback for a future client revision where the skill modules move.
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        for _, key in ipairs({Enum.KeyCode.E, Enum.KeyCode.R, Enum.KeyCode.T}) do
            VirtualInputManager:SendKeyEvent(true, key, false, game)
            task.wait(0.03)
            VirtualInputManager:SendKeyEvent(false, key, false, game)
        end
        return false
    end

    local function activeDropStage()
        local dungeon = player:FindFirstChild("InDungeonChallenge")
        local aggro = player:FindFirstChild("DungeonAggroStage")
        return math.max(dungeon and dungeon.Value or 0, aggro and aggro.Value or 0)
    end

    local function dropInfo(prompt)
        local model = prompt and prompt:FindFirstAncestorOfClass("Model")
        while model and model ~= workspace do
            if model:GetAttribute("ItemId") ~= nil and model:GetAttribute("Stage") ~= nil then break end
            model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") or nil
        end
        if not model or model == workspace then return nil end
        local itemId = tonumber(model:GetAttribute("ItemId")) or 0
        local stage = tonumber(model:GetAttribute("Stage")) or 0
        local rarity = tonumber(model.Parent and model.Parent.Name) or 0
        local price = tonumber(model:GetAttribute("GoldValue")) or 0
        pcall(function()
            local utils = require(ReplicatedFirst.AllSideCode.UtilsSystem)
            local config = utils.CfgFind.FindCfgByID(itemId)
            rarity = tonumber(config and config.xyd) or rarity
            price = tonumber(config and config.GoldValue) or price
        end)
        return {prompt=prompt, model=model, itemId=itemId, stage=stage, rarity=rarity, price=price}
    end

    local function rankedDrops(wantedStage)
        local drops = workspace:FindFirstChild("DropsClient")
        local _, _, root = getCharacter()
        if not drops or not root then return {} end
        local currentStage = tonumber(wantedStage) or activeDropStage()
        local candidates = {}
        for _, object in ipairs(drops:GetDescendants()) do
            if object:IsA("ProximityPrompt") and object.Name == "PickupPrompt" and object.Enabled then
                local info = dropInfo(object)
                if info and (currentStage <= 0 and info.stage <= 0 or info.stage == currentStage) then
                    info.distance = (object.Parent.Position - root.Position).Magnitude
                    table.insert(candidates, info)
                end
            end
        end
        table.sort(candidates, function(a, b)
            if settings.dropPriority == "Price then Rarity" then
                if a.price ~= b.price then return a.price > b.price end
                if a.rarity ~= b.rarity then return a.rarity > b.rarity end
            else
                if a.rarity ~= b.rarity then return a.rarity > b.rarity end
                if a.price ~= b.price then return a.price > b.price end
            end
            return a.distance < b.distance
        end)
        return candidates
    end

    local function collectDrops(wantedStage)
        local best = rankedDrops(wantedStage)[1]
        if not best then return 0 end
        local object = best.prompt
        if type(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, object, object.HoldDuration)
        else
            object:InputHoldBegin()
            task.wait(math.min(object.HoldDuration, 0.15))
            object:InputHoldEnd()
        end
        return 1
    end

    local function clearHighlights()
        for object, highlight in pairs(highlights) do
            if highlight then highlight:Destroy() end
            highlights[object] = nil
        end
    end

    local function refreshEsp()
        local wanted = {}
        if settings.monsterEsp then
            for _, folderName in ipairs({"Monster", "LocalMonster"}) do
                local folder = workspace:FindFirstChild(folderName)
                if folder then
                    for _, object in ipairs(folder:GetChildren()) do wanted[object] = Color3.fromRGB(255, 80, 80) end
                end
            end
        end
        if settings.dropEsp then
            for _, drop in ipairs(rankedDrops()) do
                wanted[drop.model] = Color3.fromRGB(255, 211, 72)
            end
        end
        for object, color in pairs(wanted) do
            if object.Parent and not highlights[object] then
                local highlight = Instance.new("Highlight")
                highlight.Name = "RavenMagicLootESP"
                highlight.FillColor = color
                highlight.FillTransparency = 0.72
                highlight.OutlineColor = color
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                highlight.Adornee = object
                highlight.Parent = object
                highlights[object] = highlight
            end
        end
        for object, highlight in pairs(highlights) do
            if not wanted[object] or not object.Parent then
                highlight:Destroy()
                highlights[object] = nil
            end
        end
    end

    local function setLowGraphics(enabled)
        settings.lowGraphics = enabled
        for _, object in ipairs(workspace:GetDescendants()) do
            if object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam") then
                if object:GetAttribute("RavenOriginalEnabled") == nil then
                    object:SetAttribute("RavenOriginalEnabled", object.Enabled)
                end
                if enabled then
                    object.Enabled = false
                else
                    object.Enabled = object:GetAttribute("RavenOriginalEnabled") == true
                end
            end
        end
        pcall(function()
            UserSettings():GetService("UserGameSettings").SavedQualityLevel = enabled
                and Enum.SavedQualitySetting.QualityLevel1
                or Enum.SavedQualitySetting.Automatic
        end)
    end

    connect(workspace.DescendantAdded, function(object)
        if settings.lowGraphics and (object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")) then
            if object:GetAttribute("RavenOriginalEnabled") == nil then
                object:SetAttribute("RavenOriginalEnabled", object.Enabled)
            end
            object.Enabled = false
        end
    end)

    local AutomationTab = Window:CreateTab("Automation", 4483362458)
    AutomationTab:CreateSection("Training")
    local trainStatus = AutomationTab:CreateLabel("Train: idle")
    AutomationTab:CreateDropdown({
        Name = "Training Ground",
        Options = {"Best Available", "Admin x500", "x25", "x15", "x10", "x8", "x6", "x4", "x2", "x1.5"},
        CurrentOption = {"Best Available"},
        Flag = "MagicLootTrainMode",
        Callback = function(value) settings.trainMode = type(value) == "table" and value[1] or value end,
    })
    AutomationTab:CreateToggle({Name="Auto Train",CurrentValue=false,Flag="MagicLootAutoTrain",Callback=function(v)
        settings.autoTrain = v
        if not v and returnCFrame then
            teleportTo(returnCFrame, false)
            returnCFrame = nil
        end
    end})
    AutomationTab:CreateToggle({Name="Keep Position In Ground",CurrentValue=true,Flag="MagicLootKeepTrainPosition",Callback=function(v) settings.trainKeepPosition=v end})
    AutomationTab:CreateToggle({Name="Auto Use Equipped Training Potion",CurrentValue=false,Flag="MagicLootTrainingPotion",Callback=function(v) settings.autoTrainingPotion=v end})
    AutomationTab:CreateButton({Name="Teleport To Best Training Ground",Callback=function()
        local ground=selectTrainingGround()
        local cframe=trainingCFrame(ground)
        if cframe then teleportTo(cframe,true) notify("Magic Loot","Moved to x"..ground.multiplier) end
    end})
    AutomationTab:CreateButton({Name="Return To Saved Position",Callback=function() if returnCFrame then teleportTo(returnCFrame,false) returnCFrame=nil end end})

    AutomationTab:CreateSection("Progression")
    AutomationTab:CreateToggle({Name="Auto Rebirth",CurrentValue=false,Flag="MagicLootAutoRebirth",Callback=function(v) settings.autoRebirth=v end})
    AutomationTab:CreateSlider({Name="Rebirth Check Interval",Range={5,60},Increment=1,CurrentValue=8,Suffix=" s",Flag="MagicLootRebirthInterval",Callback=function(v) settings.rebirthInterval=v end})
    AutomationTab:CreateToggle({Name="Auto Equip Best Wand",CurrentValue=false,Flag="MagicLootEquipWeapon",Callback=function(v) settings.autoEquipWeapon=v end})
    AutomationTab:CreateToggle({Name="Auto Equip Best Armor",CurrentValue=false,Flag="MagicLootEquipArmor",Callback=function(v) settings.autoEquipArmor=v end})
    AutomationTab:CreateToggle({Name="Auto Equip Best Broom",CurrentValue=false,Flag="MagicLootEquipBroom",Callback=function(v) settings.autoEquipBroom=v end})
    AutomationTab:CreateToggle({Name="Auto Sell",CurrentValue=false,Flag="MagicLootAutoSell",Callback=function(v) settings.autoSell=v end})
    AutomationTab:CreateSlider({Name="Sell Interval",Range={15,300},Increment=5,CurrentValue=45,Suffix=" s",Flag="MagicLootSellInterval",Callback=function(v) settings.sellInterval=v end})

    local CombatTab = Window:CreateTab("Combat", 4483362458)
    CombatTab:CreateSection("Farm")
    local combatStatus = CombatTab:CreateLabel("Combat: waiting")
    CombatTab:CreateToggle({Name="Auto Farm Monsters",CurrentValue=false,Flag="MagicLootAutoFarm",Callback=function(v) settings.autoFarm=v end})
    CombatTab:CreateToggle({Name="Dungeon Farm Mode (Auto Stage)",CurrentValue=false,Flag="MagicLootDungeonFarm",Callback=function(v) settings.autoDungeon=v end})
    CombatTab:CreateToggle({Name="Use Per-Stage Safe Spots",CurrentValue=true,Flag="MagicLootUseSafeSpots",Callback=function(v) settings.useSafeSpots=v end})
    CombatTab:CreateButton({Name="Save Current Position For This Stage",Callback=function()
        if settings.autoMoney then
            notify("Magic Loot","Turn off Auto Money before saving a new safe spot.")
            return
        end
        local ok, stage, reason = saveCurrentSafeSpot()
        notify("Magic Loot", ok and ("Saved safe spot for Stage " .. stage) or reason or "Unable to save this position")
    end})
    CombatTab:CreateButton({Name="Clear Safe Spot For This Stage",Callback=function()
        local ok, stage = clearCurrentSafeSpot()
        notify("Magic Loot", ok and ("Cleared safe spot for Stage " .. stage) or "Unable to detect the current stage")
    end})
    CombatTab:CreateSlider({Name="Skill Interval",Range={0.2,2},Increment=0.05,CurrentValue=0.65,Suffix=" s",Flag="MagicLootSkillInterval",Callback=function(v) settings.skillInterval=v end})
    CombatTab:CreateToggle({Name="Auto Collect Drops",CurrentValue=false,Flag="MagicLootAutoDrops",Callback=function(v) settings.autoDrops=v end})
    CombatTab:CreateDropdown({Name="Drop Priority",Options={"Rarity then Price","Price then Rarity"},CurrentOption={"Rarity then Price"},Flag="MagicLootDropPriority",Callback=function(v) settings.dropPriority=type(v)=="table" and v[1] or v end})

    CombatTab:CreateSection("Money Loop")
    local moneyStageOptions = {}
    local careerStage = player:FindFirstChild("CareerMaxStage")
    local highestUnlockedStage = math.max(1, math.floor(careerStage and careerStage.Value or 1))
    local highestMoneyStage = highestUnlockedStage
    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("BasePart") and object:GetAttribute("BattleArea")==true then
            highestMoneyStage=math.max(highestMoneyStage,math.floor(tonumber(object:GetAttribute("Stage")) or 0))
        end
    end
    settings.moneyStage = highestUnlockedStage
    for stage = 1, highestMoneyStage do table.insert(moneyStageOptions, "Stage " .. stage) end
    CombatTab:CreateDropdown({
        Name="Money Farm Stage",Options=moneyStageOptions,CurrentOption={"Stage "..highestUnlockedStage},
        Flag="MagicLootMoneyStage",Callback=function(v)
            local value=type(v)=="table" and v[1] or v
            settings.moneyStage=math.clamp(tonumber(tostring(value):match("%d+")) or 1,1,highestMoneyStage)
        end,
    })
    CombatTab:CreateLabel("Money Bag Capacity: Auto-detected from game (config value is fallback)")
    local moneyKeepDropdown
    moneyKeepDropdown=CombatTab:CreateDropdown({
        Name="Keep Materials (Do Not Sell)",Options=materialKeepOptions(),CurrentOption={},
        MultipleOptions=true,Flag="MagicLootMoneyKeepItems",Callback=function(values)
            local protected = {}
            for _, value in ipairs(type(values)=="table" and values or {values}) do
                local id=tonumber(tostring(value):match("^%d+"))
                if id then protected[id]=true end
            end
            settings.moneyKeepIds=protected
        end,
    })
    CombatTab:CreateButton({Name="Refresh Keep-Item List",Callback=function()
        moneyKeepDropdown:Refresh(materialKeepOptions(),true)
    end})
    CombatTab:CreateToggle({
        Name="Auto Money (Farm > Safe > Sell > Repeat)",CurrentValue=false,Flag="MagicLootAutoMoney",
        Callback=function(v) settings.autoMoney=v end,
    })

    local UtilityTab = Window:CreateTab("Rewards & Utility", 4483362458)
    UtilityTab:CreateSection("Claims")
    UtilityTab:CreateToggle({Name="Auto Online Rewards",CurrentValue=false,Flag="MagicLootRewards",Callback=function(v) settings.autoRewards=v end})
    UtilityTab:CreateToggle({Name="Auto Brew Available Recipe",CurrentValue=false,Flag="MagicLootAlchemy",Callback=function(v) settings.autoAlchemy=v end})
    UtilityTab:CreateToggle({Name="Auto Event Rewards",CurrentValue=false,Flag="MagicLootEventRewards",Callback=function(v) settings.autoEventRewards=v end})
    UtilityTab:CreateButton({Name="Claim Available Rewards Now",Callback=function() claimOnlineRewards() collectAlchemy() claimEventRewards() end})
    UtilityTab:CreateSection("ESP")
    UtilityTab:CreateToggle({Name="Monster ESP",CurrentValue=false,Flag="MagicLootMonsterESP",Callback=function(v) settings.monsterEsp=v refreshEsp() end})
    UtilityTab:CreateToggle({Name="Drop ESP",CurrentValue=false,Flag="MagicLootDropESP",Callback=function(v) settings.dropEsp=v refreshEsp() end})

    local TravelTab = Window:CreateTab("Travel", 4483362458)
    TravelTab:CreateSection("Locations")
    TravelTab:CreateButton({Name="Best Training Ground",Callback=function() local g=selectTrainingGround() local cf=trainingCFrame(g) if cf then teleportTo(cf,true) end end})
    TravelTab:CreateButton({Name="Highest Stage",Callback=function()
        teleportHighestStage()
    end})
    TravelTab:CreateButton({Name="Return From Dungeon",Callback=returnFromDungeon})
    TravelTab:CreateButton({Name="Return To Saved Position",Callback=function() if returnCFrame then teleportTo(returnCFrame,false) returnCFrame=nil end end})

    local StabilityTab = Window:CreateTab("Stability", 4483362458)
    StabilityTab:CreateSection("Long Sessions")
    StabilityTab:CreateToggle({Name="Anti AFK",CurrentValue=true,Flag="MagicLootAntiAFK",Callback=function(v) settings.antiAfk=v end})
    StabilityTab:CreateToggle({Name="Low Graphics",CurrentValue=false,Flag="MagicLootLowGraphics",Callback=setLowGraphics})
    StabilityTab:CreateToggle({Name="Auto Rejoin On Disconnect",CurrentValue=false,Flag="MagicLootAutoRejoin",Callback=function(v) settings.autoRejoin=v end})

    connect(player.Idled, function()
        if settings.antiAfk then
            VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
            task.wait(0.3)
            VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
        end
    end)

    local trainingPotionAt = 0
    local rebirthAt = 0
    local equipAt = 0
    local sellAt = 0
    local rewardAt = 0
    local alchemyAt = 0
    local eventAt = 0
    local espAt = 0
    local skillAt = 0
    local travelAt = 0
    local dungeonEmptySince = 0
    local moneySellAt = 0
    local moneySellRequested = false

    -- Cache streamed grounds immediately, including temporary/admin grounds
    -- that may disappear after the player travels to another area.
    task.defer(function()
        if running then pcall(collectTrainingGrounds) end
    end)

    task.spawn(function()
        while running do
            local iterationOk, iterationError = xpcall(function()
            local now = os.clock()
            if settings.autoTrain then
                local ground = selectTrainingGround()
                local inGround = player:FindFirstChild("InTrainGround")
                local groundId = player:FindFirstChild("TrainGroundId")
                if ground then
                    setStatus(trainStatus,string.format("Train: x%s | server id %s", ground.multiplier, groundId and groundId.Value or "?"))
                    local _, _, root = getCharacter()
                    local groundCFrame=trainingCFrame(ground)
                    if settings.trainKeepPosition and root and groundCFrame
                        and (not inGround or not inGround.Value or (groundCFrame.Position-root.Position).Magnitude>12) then
                        if (root.Position-groundCFrame.Position).Magnitude>5 then teleportTo(groundCFrame,true) end
                    end
                elseif now-travelAt>5 then
                    travelAt=now
                    setStatus(trainStatus,"Train: returning from dungeon")
                    returnFromDungeon()
                end
                if settings.autoTrainingPotion and now-trainingPotionAt>30 then trainingPotionAt=now useTrainingPotion() end
            else
                setStatus(trainStatus,"Train: idle")
            end

            if settings.autoRebirth and now-rebirthAt>=settings.rebirthInterval then rebirthAt=now performRebirth() end
            if now-equipAt>=30 then
                equipAt=now
                if settings.autoEquipWeapon then equipBest("Weapon") end
                if settings.autoEquipArmor then equipBest("Armor") end
                if settings.autoEquipBroom then equipBest("Broom") end
            end
            if settings.autoSell and now-sellAt>=settings.sellInterval then sellAt=now performSell() end
            if settings.autoRewards and now-rewardAt>=15 then rewardAt=now claimOnlineRewards() end
            if settings.autoAlchemy and now-alchemyAt>=20 then alchemyAt=now collectAlchemy() end
            if settings.autoEventRewards and now-eventAt>=20 then eventAt=now claimEventRewards() end
            local dropDungeonState = player:FindFirstChild("InDungeonChallenge")
            local dropAggroState = player:FindFirstChild("DungeonAggroStage")
            local moneyDropStage = math.max(dropDungeonState and dropDungeonState.Value or 0,
                dropAggroState and dropAggroState.Value or 0)
            local moneyAtTargetStage = not settings.autoMoney
                or moneyDropStage == settings.moneyStage
            -- Intermediate stages are traversal only for Money mode. Suppress
            -- collection there even if the standalone Auto Drops toggle was
            -- left enabled, so bag capacity is reserved for the chosen stage.
            local collectedDropCount = 0
            if (settings.autoDrops or settings.autoMoney) and moneyAtTargetStage then
                collectedDropCount=collectDrops(settings.autoMoney and settings.moneyStage or nil)
            end

            if (settings.autoFarm or settings.autoDungeon or settings.autoMoney) and not settings.autoTrain then
                local dungeonState=player:FindFirstChild("InDungeonChallenge")
                local aggroStage=player:FindFirstChild("DungeonAggroStage")
                local dungeonValue=dungeonState and dungeonState.Value or 0
                local aggroValue=aggroStage and aggroStage.Value or 0
                local moneyProgress=math.max(dungeonValue,aggroValue)
                local bagFull, materialSlots, usedSlots, sellableSlots = isMoneyBagFull()
                local preferredStage=settings.autoMoney and (moneyProgress > 0 and moneyProgress or settings.moneyStage)
                    or settings.autoDungeon and math.max(
                    dungeonValue,
                    aggroStage and aggroStage.Value or 0
                ) or nil
                if settings.autoDungeon and (not preferredStage or preferredStage <= 0) then
                    local career = player:FindFirstChild("CareerMaxStage")
                    preferredStage = career and career.Value or nil
                end
                -- Money mode returns to the town/safe area before selling, then
                -- re-enters the same user-selected stage for the next cycle.
                if settings.autoMoney and (bagFull or moneySellRequested) then
                    dungeonEmptySince = 0
                    if moneyProgress > 0 then
                        moneySellRequested=true
                        setStatus(combatStatus,(bagFull and ("Money: bag full ("..usedSlots.." slots)")
                            or "Money: target stage cleared").." | returning safe")
                        if now-travelAt > 3 then travelAt=now returnFromDungeon() end
                    else
                        setStatus(combatStatus,materialSlots > 0
                            and ("Money: selling "..materialSlots.." material slots")
                            or "Money: bag full, but no unlocked materials can be sold")
                        if sellableSlots > 0 and now-moneySellAt > 2 then
                            moneySellAt = now
                            local soldOk, soldCount = performMoneySell()
                            if not soldOk then
                                setStatus(combatStatus,"Money: selective sell failed; retrying")
                            elseif soldCount == 0 then
                                moneySellRequested=false
                                setStatus(combatStatus,"Money: all remaining materials are protected")
                            else
                                moneySellRequested=false
                                setStatus(combatStatus,"Money: sold "..soldCount.." material slots")
                            end
                        elseif sellableSlots==0 then
                            moneySellRequested=false
                        end
                    end
                -- Dungeon modes own stage travel. Do this before scanning for
                -- monsters because streamed stage models can remain visible in
                -- the overworld and previously prevented Stage Jump entirely.
                elseif (settings.autoDungeon or settings.autoMoney) and dungeonValue <= 0 then
                    dungeonEmptySince = 0
                    setStatus(combatStatus,settings.autoMoney
                        and ("Money: entering Stage "..tostring(settings.moneyStage))
                        or "Dungeon: entering highest available stage")
                    if now-travelAt > 5 then
                        travelAt = now
                        if settings.autoMoney then
                            local entered = teleportStage(settings.moneyStage)
                            if not entered then
                                setStatus(combatStatus,"Money: Stage "..settings.moneyStage
                                    .." needs a safe spot saved inside its battle area")
                            end
                        else
                            teleportHighestStage()
                        end
                    end
                else
                    local target=nearestMonster(preferredStage)
                    local _,_,root=getCharacter()
                    if target and root then
                        dungeonEmptySince = 0
                        local stage = preferredStage or currentCombatStage()
                        local safeCFrame = safeSpots[tostring(stage)]
                        if settings.useSafeSpots and not safeCFrame then
                            setStatus(combatStatus,"Stage "..tostring(stage)..": save a safe spot first")
                        elseif settings.useSafeSpots and player:FindFirstChild("InStageSafeArea")
                            and player.InStageSafeArea.Value > 0
                            and safeCFrame and (root.Position-safeCFrame.Position).Magnitude < 8 then
                            setStatus(combatStatus,"Stage "..tostring(stage)..": saved spot is inside the official safe area")
                        else
                            if safeCFrame then
                                root.AssemblyLinearVelocity = Vector3.zero
                                root.AssemblyAngularVelocity = Vector3.zero
                                root.CFrame = CFrame.lookAt(safeCFrame.Position, target.root.Position)
                            else
                                -- Safe spots can be disabled for stationary farming,
                                -- but this mode still never teleports to a monster.
                                root.CFrame = CFrame.lookAt(root.Position, target.root.Position)
                            end
                            setStatus(combatStatus,"Stage "..tostring(stage).." | Target: "..target.model.Name
                                .." | "..math.floor(target.humanoid.Health).." HP")
                            if now-skillAt>=settings.skillInterval then skillAt=now castSkills() end
                        end
                    else
                        setStatus(combatStatus,"Combat: waiting for monsters")
                        if settings.autoMoney then
                            if dungeonEmptySince == 0 then dungeonEmptySince = now end
                            if moneyProgress>=settings.moneyStage and collectedDropCount>0 then
                                dungeonEmptySince=now
                                setStatus(combatStatus,"Money: collecting target-stage drops")
                            elseif now-dungeonEmptySince >= 6 and now-travelAt > 3 then
                                travelAt = now
                                dungeonEmptySince = now
                                if moneyProgress < settings.moneyStage then
                                    local nextStage = moneyProgress + 1
                                    local advanced, advanceReason = advanceMoneyStage(nextStage)
                                    if advanced then
                                        setStatus(combatStatus,"Money: advancing "..moneyProgress.." > "..nextStage)
                                    elseif advanceReason == "missing-safe-spot" then
                                        setStatus(combatStatus,"Money: save a battle-area spot for Stage "..nextStage)
                                    else
                                        setStatus(combatStatus,"Money: Stage "..nextStage.." did not activate; retrying")
                                    end
                                else
                                    -- Never leave the target stage with a partial
                                    -- bag. Stay here for the next wave/drop cycle;
                                    -- only the bag-full branch may return safe.
                                    dungeonEmptySince=now
                                    setStatus(combatStatus,"Money: bag not full | waiting at target stage")
                                end
                            end
                        elseif settings.autoDungeon then
                            if dungeonEmptySince == 0 then dungeonEmptySince = now end
                            -- Once a cleared stage has no targets for a short
                            -- grace period, leave it and jump to the newly
                            -- unlocked highest stage automatically.
                            if now-dungeonEmptySince >= 4 and now-travelAt > 5 then
                                travelAt = now
                                dungeonEmptySince = now
                                setStatus(combatStatus,"Dungeon: advancing stage")
                                teleportHighestStage()
                            end
                        end
                    end
                end
            else setStatus(combatStatus,"Combat: idle") end

            if (settings.monsterEsp or settings.dropEsp) and now-espAt>=0.75 then espAt=now refreshEsp() end
            end, function(message)
                return debug.traceback(tostring(message), 2)
            end)
            if not iterationOk then
                warn("[RAVEN HUB][Magic Loot] loop error: " .. tostring(iterationError))
            end
            task.wait(0.2)
        end
    end)

    local rejoinPending = false
    connect(game:GetService("GuiService").ErrorMessageChanged, function(message)
        if settings.autoRejoin and not rejoinPending and message and message ~= "" then
            rejoinPending = true
            task.delay(2, function()
                local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, game.JobId, player)
                if not ok then
                    pcall(TeleportService.Teleport, TeleportService, game.PlaceId, player)
                end
                rejoinPending = false
            end)
        end
    end)

    local function destroy()
        if not running then return end
        running = false
        clearHighlights()
        if settings.lowGraphics then pcall(setLowGraphics, false) end
        for _,connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        table.clear(connections)
        if environment.__RAVEN_MAGIC_LOOT and environment.__RAVEN_MAGIC_LOOT.Settings == settings then
            environment.__RAVEN_MAGIC_LOOT = nil
        end
    end

    environment.__RAVEN_MAGIC_LOOT = {
        Settings = settings,
        SafeSpots = safeSpots,
        Destroy = destroy,
        CurrentStage = currentCombatStage,
        SaveSafeSpot = saveCurrentSafeSpot,
        ClearSafeSpot = clearCurrentSafeSpot,
        SelectTrainingGround = selectTrainingGround,
        Rebirth = performRebirth,
        EquipBest = equipBest,
        Sell = performSell,
        MaterialBagCount = materialBagCount,
        IsMoneyBagFull = isMoneyBagFull,
        MoneyKeepOptions = materialKeepOptions,
        MoneySell = performMoneySell,
        ClaimRewards = claimOnlineRewards,
        CollectAlchemy = collectAlchemy,
        ClaimEventRewards = claimEventRewards,
        CollectDrops = collectDrops,
        RankedDrops = rankedDrops,
        CastSkills = castSkills,
        UseTrainingPotion = useTrainingPotion,
        SetLowGraphics = setLowGraphics,
        RefreshESP = refreshEsp,
        LeaveTrainingGround = leaveTrainingGround,
        ReturnFromDungeon = returnFromDungeon,
        TeleportStage = teleportStage,
        TeleportHighestStage = teleportHighestStage,
        AdvanceMoneyStage = advanceMoneyStage,
    }

    if scriptInfo and type(scriptInfo.registerCleanup)=="function" then
        scriptInfo.registerCleanup(destroy)
    end
end
