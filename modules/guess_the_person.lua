-- ═════════════════════════════════════════════════════════════════
-- [2 Player] Guess The Person 🕵️ | RAVEN HUB Module v2.3.0
-- PlaceId: 88989028816809 | GameId: 10637759898
-- Features: 
--   • Multi-Strategy Question Solver:
--       - "Balanced 50/50" (Optimal Information Gain / Binary Search)
--       - "Sniper / Rare Trait" (Asks ultra-specific trait targeting 1-2 characters for instant win)
--       - "Category Priority" (Gender -> Hair Length -> Hair Color -> Facial/Accessories)
--   • 100% Accurate Truth Auto Answer (Evaluates Secret Character Traits)
--   • Auto Done After Flipping (Waits for all tiles to finish flipping, then clicks Done)
--   • Free Native Auto-Flip Gamepass Unlock
--   • Auto Guess / Instant Win on 1 Tile Left
--   • Solo Infinite Bot Farm (Auto Play Alone + Auto Ready + Auto Rematch)
-- ═════════════════════════════════════════════════════════════════

return function(Window, scriptInfo)
    local Players           = game:GetService("Players")
    local Workspace         = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService        = game:GetService("RunService")

    local LocalPlayer = Players.LocalPlayer
    local Remotes     = ReplicatedStorage:WaitForChild("Remotes", 15)
    local MatchRemotes = Remotes and Remotes:WaitForChild("Match", 15)

    -- Game Data Modules
    local SharedFolder      = ReplicatedStorage:WaitForChild("Shared", 15)
    local CharacterDataMod  = SharedFolder and SharedFolder:FindFirstChild("characters") and SharedFolder.characters:FindFirstChild("CharacterData")
    local QuestionCatMod    = SharedFolder and SharedFolder:FindFirstChild("match") and SharedFolder.match:FindFirstChild("QuestionCatalogue")

    local CharacterData = CharacterDataMod and require(CharacterDataMod) or {}
    local QuestionCat   = QuestionCatMod and require(QuestionCatMod) or nil

    -- Map Character name -> trait data
    local CharByName = {}
    if type(CharacterData) == "table" then
        for _, c in pairs(CharacterData) do
            if type(c) == "table" and c.name then
                CharByName[c.name] = c
            end
        end
    end

    -- Map Question Text -> pair { question, answer }
    local TextToPair = {}
    if QuestionCat and QuestionCat.allPairs and QuestionCat.textFor then
        for _, pair in ipairs(QuestionCat.allPairs()) do
            local txt = QuestionCat.textFor(pair.question, pair.answer)
            if txt then
                TextToPair[txt] = pair
            end
        end
    end

    local environment = getgenv and getgenv() or _G
    if type(environment.__RAVEN_GUESS_THE_PERSON) == "table"
        and type(environment.__RAVEN_GUESS_THE_PERSON.Destroy) == "function" then
        pcall(environment.__RAVEN_GUESS_THE_PERSON.Destroy)
    end

    local running = true
    local threads = {}
    local connections = {}

    local function startThread(key, func)
        threads[key] = nil
        task.spawn(function()
            threads[key] = true
            func(function() return threads[key] == true and running end)
            threads[key] = nil
        end)
    end

    local function stopThread(key)
        threads[key] = nil
    end

    -- ═══════════ Safe UI Clicker ═══════════
    local function clickButton(button)
        if not button then return false end
        local clicked = false
        if firesignal and button.Activated then
            pcall(firesignal, button.Activated)
            clicked = true
        end
        if firesignal and button.MouseButton1Click then
            pcall(firesignal, button.MouseButton1Click)
            clicked = true
        end
        return clicked
    end

    -- ═══════════ Settings ═══════════
    local settings = {
        -- 1. Auto Solver & Match Engine
        freeAutoFlip     = true,
        autoAsk          = true,
        askStrategy      = "Balanced 50/50 (Fastest Win)", -- "Balanced 50/50 (Fastest Win)", "Smart Adaptive (Grandmaster)", "Category Priority", "Sniper / Specific Trait"
        autoAnswer       = true,
        answerMode       = "Smart (100% Truth)",     -- "Smart (100% Truth)", "Always Yes", "Always No", "Random"
        autoDoneFlipping = true,                     -- Auto click Done when all tiles finish flipping
        doneDelay        = 0.4,                      -- Buffer delay in seconds after flipping settles
        autoGuess        = true,
        guessThreshold   = 1,

        -- 2. Solo Infinite Farm
        autoPlayAlone    = false,
        autoReady        = true,
        autoChooseCharacter = true,
        autoRematch      = false,
        autoSit          = false,
        tableTier        = "EasyMode", -- "EasyMode", "HardMode", "Any"
    }

    local stats = {
        status         = "Idle",
        matchPhase     = "None",
        matchRole      = "None",
        roundStage     = "None",
        standingTiles  = 0,
        bestQuestion   = "None",
        crowns         = 0,
        isBotMatch     = false,
    }

    -- ═══════════ Safe Game References ═══════════
    local function getBoardController()
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        local ctrl = ps and ps:FindFirstChild("BoardController", true)
        if ctrl and ctrl:IsA("ModuleScript") then
            local ok, mod = pcall(require, ctrl)
            if ok and type(mod) == "table" then return mod end
        end
        return nil
    end

    local function getMatchReadyModule()
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        local modScript = ps and ps:FindFirstChild("MatchReady", true)
        if modScript and modScript:IsA("ModuleScript") then
            local ok, mod = pcall(require, modScript)
            if ok and type(mod) == "table" then return mod end
        end
        return nil
    end

    local function getCharacter()
        return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    end

    local function getHRP()
        local char = getCharacter()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function isSeated()
        local char = getCharacter()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil and hum:GetState() == Enum.HumanoidStateType.Seated
    end

    local function getMyBoardModel()
        local bc = getBoardController()
        if bc and bc.getLocalController then
            local ctrl = bc.getLocalController()
            if ctrl and ctrl.model then
                return ctrl.model, ctrl
            end
        end
        local myBoard = Workspace:FindFirstChild("Boards") and Workspace.Boards:FindFirstChild("Board_" .. LocalPlayer.Name)
        return myBoard, nil
    end

    local function findTilePart(myBoard, idx)
        if not myBoard or not myBoard:FindFirstChild("Tiles") then return nil end
        return myBoard.Tiles:FindFirstChild(string.format("Tile%02d", idx))
            or myBoard.Tiles:FindFirstChild("Tile" .. idx)
    end

    local function getStandingTiles()
        local bc = getBoardController()
        if bc and bc.getLocalController then
            local ctrl = bc.getLocalController()
            if ctrl and ctrl.getStanding then
                local ok, standing = pcall(function() return ctrl:getStanding() end)
                if ok and type(standing) == "table" then
                    return standing
                end
            end
        end
        local myBoard, controller = getMyBoardModel()
        if controller and type(controller.tiles) == "table" then
            local list = {}
            for _, entry in pairs(controller.tiles) do
                local idx = entry.part and entry.part:GetAttribute("TileIndex")
                if not entry.isDown then
                    if not idx then return {} end
                    table.insert(list, idx)
                end
            end
            return list
        end
        return {}
    end

    local function getPendingFlipsCount()
        local bc = getBoardController()
        if bc and bc.getLocalController then
            local ctrl = bc.getLocalController()
            if ctrl and ctrl.pendingFlips then
                if type(ctrl.pendingFlips) == "table" then
                    local count = 0
                    for _ in pairs(ctrl.pendingFlips) do count = count + 1 end
                    return count
                end
            end
        end
        return 0
    end

    local function getWrongFlipModule()
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        local mod = ps and ps:FindFirstChild("WrongFlip", true)
        if mod and mod:IsA("ModuleScript") then
            local ok, res = pcall(require, mod)
            if ok and type(res) == "table" then return res end
        end
        return nil
    end

    local function getWrongStandingCount()
        local wf = getWrongFlipModule()
        if not wf or not wf.hasAnswer or not wf.hasAnswer() then
            return 0
        end

        local myBoard, ctrl = getMyBoardModel()
        local wrongCount = 0

        if ctrl and type(ctrl.tiles) == "table" then
            for _, entry in pairs(ctrl.tiles) do
                if entry and not entry.isDown and entry.part then
                    local charName = entry.part:GetAttribute("CharacterName")
                    if charName and wf.isWrong and wf.isWrong(charName) then
                        wrongCount = wrongCount + 1
                    end
                end
            end
            return wrongCount
        end

        if myBoard and myBoard:FindFirstChild("Tiles") then
            for _, t in ipairs(myBoard.Tiles:GetChildren()) do
                local charName = t:GetAttribute("CharacterName")
                if charName and wf.isWrong and wf.isWrong(charName) then
                    wrongCount = wrongCount + 1
                end
            end
        end

        return wrongCount
    end

    local function getStandingCharacters()
        local myBoard, ctrl = getMyBoardModel()
        local chars = {}
        local seen = {}

        local wf = getWrongFlipModule()

        -- Priority 1: Use ctrl.tiles directly (live controller state)
        if ctrl and type(ctrl.tiles) == "table" then
            for _, entry in pairs(ctrl.tiles) do
                if entry and not entry.isDown and entry.part then
                    local cName = entry.part:GetAttribute("CharacterName")
                    if cName and not seen[cName] and CharByName[cName] then
                        local isWrong = wf and wf.hasAnswer and wf.hasAnswer() and wf.isWrong and wf.isWrong(cName)
                        if not isWrong then
                            seen[cName] = true
                            table.insert(chars, CharByName[cName])
                        end
                    end
                end
            end
        end

        -- Priority 2: Read directly from physical standing children in myBoard.Tiles
        if #chars == 0 and myBoard and myBoard:FindFirstChild("Tiles") then
            for _, t in ipairs(myBoard.Tiles:GetChildren()) do
                local cName = t:GetAttribute("CharacterName")
                if cName and not seen[cName] and CharByName[cName] then
                    local isWrong = wf and wf.hasAnswer and wf.hasAnswer() and wf.isWrong and wf.isWrong(cName)
                    if not isWrong then
                        seen[cName] = true
                        table.insert(chars, CharByName[cName])
                    end
                end
            end
        end

        return chars
    end

    local function getMySecretCharacterData()
        local bc = getBoardController()
        local chosenIdx = bc and bc.getChosenIndex and bc.getChosenIndex()
        local myBoard = getMyBoardModel()
        if myBoard and chosenIdx then
            local t = findTilePart(myBoard, chosenIdx)
            local charName = t and t:GetAttribute("CharacterName")
            if charName and CharByName[charName] then
                return CharByName[charName]
            end
        end
        return nil
    end

    -- ═══════════ 1. Question Solver Engine ═══════════
    local function applyFreeAutoFlip()
        pcall(function()
            LocalPlayer:SetAttribute("OwnsAutoFlip", true)
            LocalPlayer:SetAttribute("AutoFlipEnabled", true)

            local pgui = LocalPlayer:FindFirstChild("PlayerGui")
            local mbg = pgui and pgui:FindFirstChild("MatchBeginGui")
            local toggleBtn = mbg and mbg:FindFirstChild("AutoFlipToggleButton")
            if toggleBtn then
                toggleBtn.Visible = true
                local title = toggleBtn:FindFirstChild("Title", true)
                if title and title:IsA("TextLabel") and title.Text:find("OFF") then
                    clickButton(toggleBtn)
                end
            end
        end)
    end

    local function triggerDoneFlipping()
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local mbg = pgui and pgui:FindFirstChild("MatchBeginGui")
        local bbc = mbg and mbg:FindFirstChild("BoardsButtonContainer")
        local dfh = bbc and bbc:FindFirstChild("DoneFlippingHolder")
        local dfb = dfh and dfh:FindFirstChild("DoneFlippingButton")

        if dfb and dfb.Visible then
            clickButton(dfb)
            return true
        end

        if MatchRemotes and MatchRemotes:FindFirstChild("EndFlipping") then
            pcall(function()
                MatchRemotes.EndFlipping:FireServer()
            end)
            return true
        end
        return false
    end

    local function triggerLastTileGuess()
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local mbg = pgui and pgui:FindFirstChild("MatchBeginGui")
        local bbc = mbg and mbg:FindFirstChild("BoardsButtonContainer")
        local ltgb = bbc and bbc:FindFirstChild("LastTileGuessButton")
        if ltgb and ltgb.Visible then
            clickButton(ltgb)
            return true
        end

        if MatchRemotes and MatchRemotes:FindFirstChild("GuessLastTile") then
            pcall(function()
                MatchRemotes.GuessLastTile:FireServer()
            end)
            return true
        end
        return false
    end

    -- Pure bounded decision-tree search; no game actions or secret-player data.
    local function adaptiveQuestion(chars, catalogue)
        if #chars < 2 or #chars > 128 then return nil end
        local questions, rows = catalogue.allPairs(), {}
        if #questions > 256 then return nil end
        for q, pair in ipairs(questions) do
            rows[q] = {}
            for i, character in ipairs(chars) do
                local ok, value = pcall(catalogue.matches, character, pair.question, pair.answer)
                if not ok or type(value) ~= "boolean" then return nil end
                rows[q][i] = value
            end
        end
        local nodes, memo = 0, {}
        local function solve(ids, depth)
            if #ids <= 1 then return 0 end
            local key = depth .. ":" .. table.concat(ids, ",")
            if memo[key] then return memo[key][1], memo[key][2] end
            nodes = nodes + 1
            if nodes > 3000 then error("adaptive search budget") end
            if nodes % 100 == 0 then task.wait() end
            local best, chosen, bestBalance = math.huge, nil, math.huge
            local partitions = {}
            for q, row in ipairs(rows) do
                local yes, no = {}, {}
                for _, id in ipairs(ids) do
                    table.insert(row[id] and yes or no, id)
                end
                if #yes > 0 and #no > 0 then
                    local a, b = table.concat(yes, ","), table.concat(no, ",")
                    local signature = a < b and a .. "/" .. b or b .. "/" .. a
                    if not partitions[signature] then
                        partitions[signature] = true
                        local cost
                        if depth == 1 then
                            -- Finite-horizon residual uncertainty, not a win guarantee.
                            cost = 1 + (#yes * math.log(#yes, 2) + #no * math.log(#no, 2)) / #ids
                        else
                            cost = 1 + (#yes * solve(yes, depth - 1) + #no * solve(no, depth - 1)) / #ids
                        end
                        local balance = math.abs(#yes - #no)
                        if cost < best - 1e-9 or (math.abs(cost - best) < 1e-9 and balance < bestBalance) then
                            best, chosen, bestBalance = cost, q, balance
                        end
                    end
                end
            end
            memo[key] = {best, chosen}
            return best, chosen
        end
        local ids = {}
        for i = 1, #chars do ids[i] = i end
        local ok, cost, q = pcall(solve, ids, 3)
        if not ok or not q then return nil end
        local yes = 0
        for _, value in ipairs(rows[q]) do if value then yes = yes + 1 end end
        return questions[q], yes, #chars - yes, #chars, cost
    end

    -- Solves for question based on selected strategy
    local function getBestQuestion(strategy)
        if not QuestionCat or not QuestionCat.allPairs or not QuestionCat.matches then
            return nil
        end

        local standing = getStandingTiles()
        if #standing <= 1 then return nil end

        local myBoard = getMyBoardModel()
        if not myBoard then return nil end
        local standingChars = {}
        for _, idx in ipairs(standing) do
            local tile = findTilePart(myBoard, idx)
            local name = tile and tile:GetAttribute("CharacterName")
            local data = name and CharByName[name]
            -- Partial data would bias the split and can produce a false final guess.
            if not data then return nil end
            table.insert(standingChars, data)
        end

        local allPairs = QuestionCat.allPairs()
        strategy = type(strategy) == "table" and (strategy[1] or strategy.Value) or strategy
        strategy = tostring(strategy or "Balanced")
        if strategy:find("Smart Adaptive", 1, true) then
            local pair, yes, no, total = adaptiveQuestion(standingChars, QuestionCat)
            if pair then return pair, yes, no, total end
        end
        local candidateList = {}

        for _, pair in ipairs(allPairs) do
            local yesCount = 0
            local noCount = 0
            for _, c in ipairs(standingChars) do
                if QuestionCat.matches(c, pair.question, pair.answer) then
                    yesCount = yesCount + 1
                else
                    noCount = noCount + 1
                end
            end

            -- Must eliminate at least 1 tile on either outcome
            if yesCount > 0 and noCount > 0 then
                table.insert(candidateList, {
                    pair = pair,
                    yes = yesCount,
                    no = noCount,
                    diff = math.abs(yesCount - noCount),
                    specificScore = yesCount -- smaller yesCount means more specific trait
                })
            end
        end

        if #candidateList == 0 then return nil end

        if type(strategy) == "table" then
            strategy = strategy[1] or strategy.Value or tostring(strategy)
        end

        local categoryWeight = {
            Gender = 10,
            Hair = 8,
            SkinTone = 6,
            EyeColor = 5,
            HairColor = 4,
            FacialHair = 1,
            Accessories = 1
        }

        local totalStanding = #standingChars

        local function getCandidateScore(item)
            local diff = item.diff
            local catBonus = (categoryWeight[item.pair.question] or 1) * 2
            local rarePenalty = 0

            if totalStanding > 3 then
                -- Heavily penalize optional accessories, facial hair, or baldness that most characters don't have
                if item.pair.question == "Accessories" or item.pair.question == "FacialHair" or item.pair.answer == "Bald" then
                    rarePenalty = rarePenalty + 50
                end
                -- Penalize traits that fewer than 25% of standing characters possess
                if (item.yes / totalStanding) < 0.25 then
                    rarePenalty = rarePenalty + 30
                end
            end

            return diff - catBonus + rarePenalty
        end

        for _, c in ipairs(candidateList) do
            c.score = getCandidateScore(c)
        end

        if strategy:find("Sniper") then
            if totalStanding > 3 then
                table.sort(candidateList, function(a, b)
                    if a.score == b.score then
                        return a.diff < b.diff
                    end
                    return a.score < b.score
                end)
            else
                -- When <= 3 cards left, snipe the specific single card
                table.sort(candidateList, function(a, b)
                    if a.specificScore == b.specificScore then
                        return a.score < b.score
                    end
                    return a.specificScore < b.specificScore
                end)
            end
            local best = candidateList[1]
            return best.pair, best.yes, best.no, totalStanding
        elseif strategy:find("Category") then
            -- Strict category order priority
            table.sort(candidateList, function(a, b)
                local wA = categoryWeight[a.pair.question] or 1
                local wB = categoryWeight[b.pair.question] or 1
                if wA == wB then
                    return a.score < b.score
                end
                return wA > wB
            end)
            local best = candidateList[1]
            return best.pair, best.yes, best.no, totalStanding
        else
            -- Minimize expected remaining candidates: (yes^2 + no^2) / total.
            -- Category preference is only a tie-break, never a split penalty.
            table.sort(candidateList, function(a, b)
                if a.diff ~= b.diff then
                    return a.diff < b.diff
                end
                local wa = categoryWeight[a.pair.question] or 1
                local wb = categoryWeight[b.pair.question] or 1
                if wa ~= wb then return wa > wb end
                return tostring(a.pair.question) .. ':' .. tostring(a.pair.answer)
                    < tostring(b.pair.question) .. ':' .. tostring(b.pair.answer)
            end)
            local best = candidateList[1]
            return best.pair, best.yes, best.no, totalStanding
        end
    end

    local hasAskedThisTurn = false
    local hasAnsweredThisTurn = false
    local hasDoneFlippedThisTurn = false

    local function handleAutoAsk()
        local turn = LocalPlayer:GetAttribute("TurnEndsAt")
        local optimalPair, yesCount, noCount, total = getBestQuestion(settings.askStrategy)
        if not running or not settings.autoAsk or LocalPlayer:GetAttribute("MatchPhase") ~= "Playing"
            or LocalPlayer:GetAttribute("MatchRole") ~= "Asking" or LocalPlayer:GetAttribute("RoundStage") ~= "Asking"
            or LocalPlayer:GetAttribute("TurnEndsAt") ~= turn then return false end
        if optimalPair then
            stats.bestQuestion = optimalPair.question .. ": " .. optimalPair.answer .. " [Yes:" .. yesCount .. "/No:" .. noCount .. "]"
            
            -- 1. Direct Remote Fire (Clean, Guaranteed, Instant)
            if MatchRemotes and MatchRemotes:FindFirstChild("AskQuestion") then
                local sent = pcall(function()
                    MatchRemotes.AskQuestion:FireServer(optimalPair.question, optimalPair.answer)
                end)
                if sent then return true end
            end

            -- 2. Visual click UI backup
            pcall(function()
                local pgui = LocalPlayer:FindFirstChild("PlayerGui")
                local mbg = pgui and pgui:FindFirstChild("MatchBeginGui")
                local qc = mbg and mbg:FindFirstChild("QuestionsContainer")
                local ab = mbg and mbg:FindFirstChild("AnswerBoxes")
                if qc and ab then
                    local catBtn = qc:FindFirstChild(optimalPair.question)
                    if catBtn then
                        clickButton(catBtn)
                        task.wait(0.05)
                        local ansFolder = ab:FindFirstChild(optimalPair.question .. "Answers")
                        local answersHolder = ansFolder and ansFolder:FindFirstChild("Answers")
                        local optBtn = answersHolder and answersHolder:FindFirstChild(optimalPair.answer)
                        if optBtn then
                            clickButton(optBtn)
                        end
                    end
                end
            end)

            return true
        else
            stats.bestQuestion = "Waiting for complete board data or a useful split"
        end
        return false
    end

    local function handleSmartAnswer()
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local mbg = pgui and pgui:FindFirstChild("MatchBeginGui")
        local tc = mbg and mbg:FindFirstChild("ThinkingContainer")

        local qLabel = tc and tc:FindFirstChild("QuestionTextLabel", true)
        local qText = qLabel and qLabel.Text or ""
        if qText == "" or qText:lower():find("thinking") then
            return false
        end

        local answerStr = "Yes"
        local mode = settings.answerMode
        if type(mode) == "table" then
            mode = mode[1] or mode.Value or tostring(mode)
        end

        if mode == "Smart (100% Truth)" then
            local pair = TextToPair[qText]
            local myChar = getMySecretCharacterData()

            if pair and myChar and QuestionCat and QuestionCat.trueReply then
                local truth = QuestionCat.trueReply(myChar, pair.question, pair.answer)
                if truth == "Yes" then
                    answerStr = "Yes"
                else
                    answerStr = "No"
                end
            else
                answerStr = "Yes"
            end
        elseif mode == "Always Yes" then
            answerStr = "Yes"
        elseif mode == "Always No" then
            answerStr = "No"
        elseif mode == "Random" then
            answerStr = (math.random(1, 2) == 1) and "Yes" or "No"
        end

        -- Direct remote fire
        if MatchRemotes and MatchRemotes:FindFirstChild("AnswerQuestion") then
            pcall(function()
                MatchRemotes.AnswerQuestion:FireServer(answerStr)
            end)
        end

        -- Visual click UI backup
        if tc then
            local targetBtn = tc:FindFirstChild(answerStr)
            if targetBtn and targetBtn.Visible then
                clickButton(targetBtn)
            end
        end
        return true
    end

    -- ═══════════ 2. Solo Infinite Farm Mechanics ═══════════
    local function handlePlayAlone()
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local mqg = pgui and pgui:FindFirstChild("MatchQueueGui")
        local mqb = mqg and mqg:FindFirstChild("MatchQueueButtons")
        local pab = mqb and mqb:FindFirstChild("PlayAloneButton")
        if pab and pab.Visible then
            clickButton(pab)
            return true
        end

        if MatchRemotes and MatchRemotes:FindFirstChild("PlayAlone") then
            pcall(function()
                MatchRemotes.PlayAlone:FireServer()
            end)
            return true
        end
        return false
    end

    local function handleReadyUp()
        local mr = getMatchReadyModule()
        if mr and mr.canSetReady and mr.canSetReady() then
            pcall(function() mr.setReady(true) end)
            return true
        end

        if MatchRemotes and MatchRemotes:FindFirstChild("SetReady") then
            pcall(function()
                MatchRemotes.SetReady:FireServer(true)
            end)
            return true
        end
        return false
    end

    local function handleChooseCharacter()
        local bc = getBoardController()
        local chosen = bc and bc.getChosenIndex and bc.getChosenIndex()
        if not chosen or chosen == 0 then
            if MatchRemotes and MatchRemotes:FindFirstChild("ChooseCharacter") then
                pcall(function()
                    MatchRemotes.ChooseCharacter:FireServer(math.random(1, 30))
                end)
            end
        end
    end

    local function handleRematch()
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local meg = pgui and pgui:FindFirstChild("MatchEndGui")
        local pac = meg and meg:FindFirstChild("PlayAgainContainer")
        local yesBtn = pac and pac:FindFirstChild("YesButton")
        if yesBtn and yesBtn.Visible then
            clickButton(yesBtn)
            return true
        end

        if MatchRemotes and MatchRemotes:FindFirstChild("PlayAgain") then
            pcall(function()
                MatchRemotes.PlayAgain:FireServer()
            end)
            return true
        end
        return false
    end

    local function findAvailableSeat(targetTier)
        local plotsFolder = Workspace:FindFirstChild("Plots")
        if not plotsFolder then return nil end

        local sides = {"LeftSide", "RightSide"}
        local tiers = {"EasyMode", "HardMode"}
        if targetTier and targetTier ~= "Any" then
            tiers = {targetTier}
        end

        for _, sideName in ipairs(sides) do
            local side = plotsFolder:FindFirstChild(sideName)
            if side then
                for _, tierName in ipairs(tiers) do
                    local tier = side:FindFirstChild(tierName)
                    if tier then
                        for _, plot in ipairs(tier:GetChildren()) do
                            local seatsFolder = plot:FindFirstChild("MatchStartSeats")
                            if seatsFolder then
                                for _, seatHolderName in ipairs({"PlayerSeatLeft", "PlayerSeatRight"}) do
                                    local holder = seatsFolder:FindFirstChild(seatHolderName)
                                    local seat = holder and holder:FindFirstChild("Seat")
                                    if seat and seat:IsA("Seat") and seat.Occupant == nil then
                                        return seat, plot.Name .. " (" .. tierName .. ")"
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function sitAtSeat(seat)
        local hrp = getHRP()
        local char = getCharacter()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hrp and hum and seat and seat.Occupant == nil then
            hrp.CFrame = seat.CFrame + Vector3.new(0, 1.5, 0)
            task.wait(0.2)
            seat:Sit(hum)
        end
    end

    -- ═══════════ Main Solver & Farm Loop ═══════════
    local flippingSettledTime = 0
    local wasFlipping = false

    startThread("MainMasterLoop", function(isAlive)
        while isAlive() do
            pcall(function()
                if settings.freeAutoFlip then
                    applyFreeAutoFlip()
                end

                local phase = LocalPlayer:GetAttribute("MatchPhase") or "None"
                local role = LocalPlayer:GetAttribute("MatchRole") or "None"
                local stage = LocalPlayer:GetAttribute("RoundStage") or "None"
                local standing = getStandingTiles()

                stats.matchPhase = phase
                stats.matchRole = role
                stats.roundStage = stage
                stats.standingTiles = #standing
                stats.crowns = LocalPlayer:GetAttribute("Crowns") or stats.crowns
                stats.isBotMatch = LocalPlayer:GetAttribute("MatchOpponentIsBot") or false

                -- 1. Seating & Solo Queue
                if not isSeated() then
                    stats.status = "In Lobby / Not Seated"
                    if settings.autoSit then
                        local seat, name = findAvailableSeat(settings.tableTier)
                        if seat then
                            stats.status = "Sitting at " .. tostring(name)
                            sitAtSeat(seat)
                            task.wait(1)
                        end
                    end
                else
                    if phase == "None" or phase == "Lobby" then
                        stats.status = "Waiting for Match"
                        if settings.autoPlayAlone then
                            stats.status = "Triggering Play Alone (Bot)"
                            handlePlayAlone()
                            task.wait(1)
                        end
                    end
                end

                -- 2. ReadyUp Phase
                if phase == "ReadyUp" then
                    stats.status = "Readying Up"
                    if settings.autoReady then
                        handleReadyUp()
                    end
                end

                -- 3. Reveal Phase
                if phase == "Reveal" then
                    stats.status = "Character Reveal / Selection"
                    if settings.autoChooseCharacter then
                        handleChooseCharacter()
                    end
                end

                -- 4. Playing Phase (Solving & Matching)
                if phase == "Playing" then
                    stats.status = "Playing [" .. tostring(role) .. " / " .. tostring(stage) .. "]"

                    -- Check Instant Win / Last Tile Guess
                    if settings.autoGuess and (#standing <= settings.guessThreshold and #standing > 0) then
                        stats.status = "🎯 Instant Guessing Last Tile!"
                        triggerLastTileGuess()
                        task.wait(0.5)
                    end

                    -- Asking Turn -> Strategy Question Solver
                    if stage == "Asking" and role == "Asking" then
                        wasFlipping = false
                        flippingSettledTime = 0
                        if settings.autoAsk and not hasAskedThisTurn then
                            stats.status = "🎯 Asking [" .. settings.askStrategy .. "]..."
                            hasAskedThisTurn = handleAutoAsk()
                        end
                    else
                        if stage ~= "Asking" or role ~= "Asking" then
                            hasAskedThisTurn = false
                        end
                    end

                    -- Answering Turn -> 100% Accurate Truth Evaluator
                    if (stage == "Answering" or stage == "Thinking") and role == "Answering" then
                        wasFlipping = false
                        flippingSettledTime = 0
                        if settings.autoAnswer and not hasAnsweredThisTurn then
                            local answered = handleSmartAnswer()
                            if answered then
                                hasAnsweredThisTurn = true
                                stats.status = "🛡️ Answered (" .. tostring(settings.answerMode) .. ")"
                            else
                                stats.status = "🛡️ Waiting for opponent question..."
                            end
                        end
                    else
                        if stage ~= "Answering" and stage ~= "Thinking" then
                            hasAnsweredThisTurn = false
                        end
                    end

                    -- Flipping Phase -> Wait for AutoFlip to finish ALL wrong tiles, then buffer settle, then Done
                    if stage == "Flipping" then
                        local pending = getPendingFlipsCount()
                        local wrongStanding = getWrongStandingCount()

                        if not wasFlipping then
                            wasFlipping = true
                            flippingSettledTime = 0
                            stats.status = "🔄 Starting Tile Flipping..."
                        end

                        if wrongStanding > 0 or pending > 0 then
                            flippingSettledTime = 0
                            stats.status = "🔄 Flipping (" .. tostring(wrongStanding) .. " wrong / " .. tostring(pending) .. " pending)..."
                        else
                            if flippingSettledTime == 0 then
                                flippingSettledTime = os.clock()
                            end

                            local timeSinceSettle = os.clock() - flippingSettledTime
                            local targetDelay = math.max(0.3, tonumber(settings.doneDelay) or 0.4)
                            stats.status = "🔄 Flipping Settle (" .. string.format("%.1f", timeSinceSettle) .. "s / " .. string.format("%.1f", targetDelay) .. "s)..."

                            if timeSinceSettle >= targetDelay then
                                if settings.autoDoneFlipping and not hasDoneFlippedThisTurn then
                                    hasDoneFlippedThisTurn = true
                                    stats.status = "✅ Flipping Complete! Clicking Done..."
                                    triggerDoneFlipping()
                                end
                            end
                        end
                    else
                        wasFlipping = false
                        flippingSettledTime = 0
                        hasDoneFlippedThisTurn = false
                    end
                end

                -- 5. Match Result & Rematch Loop
                local pgui = LocalPlayer:FindFirstChild("PlayerGui")
                local meg = pgui and pgui:FindFirstChild("MatchEndGui")
                if phase == "MatchEnd" or phase == "Ending" or (phase == "None" and meg and meg.Enabled) then
                    wasFlipping = false
                    stats.status = "Match Ended"
                    if settings.autoRematch then
                        stats.status = "🔄 Auto Accepting Rematch"
                        handleRematch()
                        task.wait(1)
                    end
                end
            end)
            task.wait(0.2)
        end
    end)

    -- ═════════════════════════════════════════════════════════════════
    -- UI TABS SETUP (Rayfield)
    -- ═════════════════════════════════════════════════════════════════

    -- Tab 1: Match & Auto Solver
    local SolverTab = Window:CreateTab("Match & Solver", 4483362458)

    SolverTab:CreateSection("🎯 Targeted Question Solver & Instant Win")

    SolverTab:CreateToggle({
        Name = "Auto Ask Question",
        CurrentValue = true,
        Flag = "GTP_AutoAsk",
        Callback = function(val)
            settings.autoAsk = val
        end,
    })

    SolverTab:CreateDropdown({
        Name = "Question Targeting Strategy",
        Options = {"Smart Adaptive (Grandmaster)", "Balanced 50/50 (Fastest Win)", "Category Priority", "Sniper / Specific Trait"},
        CurrentOption = "Smart Adaptive (Grandmaster)",
        Flag = "GTP_AskStrategy_v3",
        Callback = function(opt)
            settings.askStrategy = type(opt) == "table" and (opt[1] or opt.Value) or opt
        end,
    })

    SolverTab:CreateToggle({
        Name = "Smart 100% Accurate Auto Answer",
        CurrentValue = true,
        Flag = "GTP_AutoAnswer",
        Callback = function(val)
            settings.autoAnswer = val
        end,
    })

    SolverTab:CreateDropdown({
        Name = "Answer Mode Choice",
        Options = {"Smart (100% Truth)", "Always Yes", "Always No", "Random"},
        CurrentOption = "Smart (100% Truth)",
        MultipleOptions = false,
        Flag = "GTP_AnswerMode",
        Callback = function(opt)
            settings.answerMode = type(opt) == "table" and (opt[1] or opt.Value) or opt
        end,
    })

    SolverTab:CreateToggle({
        Name = "Auto Guess / Instant Win (When 1 Tile Left)",
        CurrentValue = true,
        Flag = "GTP_AutoGuess",
        Callback = function(val)
            settings.autoGuess = val
        end,
    })

    SolverTab:CreateButton({
        Name = "🎯 Guess Last Tile Now",
        Callback = function()
            triggerLastTileGuess()
        end,
    })

    SolverTab:CreateSection("🔄 Tile Flipping Control")

    SolverTab:CreateToggle({
        Name = "Auto Done After Flipping (Wait Flip Done -> Click Done)",
        CurrentValue = true,
        Flag = "GTP_AutoDoneFlipping",
        Callback = function(val)
            settings.autoDoneFlipping = val
        end,
    })

    SolverTab:CreateSlider({
        Name = "Done Click Settle Delay (Seconds)",
        Range = {0.1, 2.0},
        Increment = 0.1,
        Suffix = "s",
        CurrentValue = 0.4,
        Flag = "GTP_DoneDelay",
        Callback = function(val)
            settings.doneDelay = val
        end,
    })

    SolverTab:CreateButton({
        Name = "✅ Click Done Flipping Now",
        Callback = function()
            triggerDoneFlipping()
        end,
    })

    SolverTab:CreateToggle({
        Name = "Unlock Native Free Auto-Flip (Gamepass Bypass)",
        CurrentValue = true,
        Flag = "GTP_FreeAutoFlip",
        Callback = function(val)
            settings.freeAutoFlip = val
            if val then applyFreeAutoFlip() end
        end,
    })

    -- Tab 2: Solo Bot Farm
    local FarmTab = Window:CreateTab("Solo Bot Farm", 4483362458)

    FarmTab:CreateSection("🤖 Solo Infinite Bot Match Farm")

    FarmTab:CreateToggle({
        Name = "Auto Play Alone (Instant Bot Match)",
        CurrentValue = false,
        Flag = "GTP_AutoPlayAlone",
        Callback = function(val)
            settings.autoPlayAlone = val
            if val and isSeated() then
                handlePlayAlone()
            end
        end,
    })

    FarmTab:CreateButton({
        Name = "🤖 Play Alone (Bot Match Once)",
        Callback = function()
            handlePlayAlone()
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Ready Up (Skip Waiting)",
        CurrentValue = true,
        Flag = "GTP_AutoReady",
        Callback = function(val)
            settings.autoReady = val
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Choose Secret Character",
        CurrentValue = true,
        Flag = "GTP_AutoChooseCharacter",
        Callback = function(val)
            settings.autoChooseCharacter = val
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Rematch / Play Again (Infinite Loop)",
        CurrentValue = false,
        Flag = "GTP_AutoRematch",
        Callback = function(val)
            settings.autoRematch = val
        end,
    })

    FarmTab:CreateButton({
        Name = "🔄 Accept Rematch Now",
        Callback = function()
            handleRematch()
        end,
    })

    FarmTab:CreateSection("🪑 Table Seating Engine")

    FarmTab:CreateDropdown({
        Name = "Table Difficulty Target",
        Options = {"EasyMode", "HardMode", "Any"},
        CurrentOption = "EasyMode",
        MultipleOptions = false,
        Flag = "GTP_TableTier",
        Callback = function(opt)
            settings.tableTier = type(opt) == "table" and (opt[1] or opt.Value) or opt
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Sit Available Table",
        CurrentValue = false,
        Flag = "GTP_AutoSit",
        Callback = function(val)
            settings.autoSit = val
            if val and not isSeated() then
                local seat = findAvailableSeat(settings.tableTier)
                if seat then sitAtSeat(seat) end
            end
        end,
    })

    FarmTab:CreateButton({
        Name = "🪑 Sit Available Table (Once)",
        Callback = function()
            local seat = findAvailableSeat(settings.tableTier)
            if seat then sitAtSeat(seat) end
        end,
    })

    -- Live Stats Section on SolverTab
    SolverTab:CreateSection("📊 Live Solver & Match Stats")
    local StatusLabel   = SolverTab:CreateLabel("Status: " .. stats.status)
    local PhaseLabel    = SolverTab:CreateLabel("Phase: " .. stats.matchPhase)
    local RoleLabel     = SolverTab:CreateLabel("Role / Stage: " .. stats.matchRole .. " / " .. stats.roundStage)
    local BestQLabel    = SolverTab:CreateLabel("Best Question: None")
    local StandingLabel = SolverTab:CreateLabel("Standing Tiles: " .. tostring(stats.standingTiles))
    local CrownsLabel   = SolverTab:CreateLabel("Crowns: " .. tostring(stats.crowns))

    startThread("StatsTracker", function(isAlive)
        while isAlive() do
            pcall(function()
                if StatusLabel and StatusLabel.Set then
                    StatusLabel:Set("Status: " .. stats.status)
                end
                if PhaseLabel and PhaseLabel.Set then
                    PhaseLabel:Set("Phase: " .. stats.matchPhase .. (stats.isBotMatch and " [Bot Match]" or ""))
                end
                if RoleLabel and RoleLabel.Set then
                    RoleLabel:Set("Role / Stage: " .. stats.matchRole .. " / " .. stats.roundStage)
                end
                if BestQLabel and BestQLabel.Set then
                    BestQLabel:Set("Target Question: " .. stats.bestQuestion)
                end
                if StandingLabel and StandingLabel.Set then
                    StandingLabel:Set("Standing Tiles: " .. tostring(stats.standingTiles))
                end
                if CrownsLabel and CrownsLabel.Set then
                    CrownsLabel:Set("Crowns: " .. tostring(stats.crowns))
                end
            end)
            task.wait(0.4)
        end
    end)

    -- ═══════════ Cleanup / Destroy Handler ═══════════
    environment.__RAVEN_GUESS_THE_PERSON = {
        Version = "v2.3.0",
        stats = stats,
        settings = settings,
        Destroy = function()
            running = false
            for k, _ in pairs(threads) do
                threads[k] = nil
            end
            for _, c in ipairs(connections) do
                pcall(function() c:Disconnect() end)
            end
            table.clear(connections)
        end
    }
end
