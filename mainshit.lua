local CONFIG = {
    BOT_ID = 1,
    MODE = "deposit",
    API_BASE = "https://mysterymp.shop/api",
    BOT_TOKEN = "BCFGHk,lnjgNHBUJIIBNJHIBBbjikbuiyugtfvuyVHJKbdghjAVdhujNHJKOVTGY&VbdjiopaSbdfty7a8vIJBK",
    ANTI_KICK = true,
    ANTI_AFK = true,
    POLL_INTERVAL = 8,
    DEBUG = true
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")
local Backpack = LP:WaitForChild("Backpack")

local isProcessing = false
local botStartTime = tick()

local function Log(msg)
    if CONFIG.DEBUG then
        print(string.format("[Bot-%d] %s", CONFIG.BOT_ID, tostring(msg)))
    end
end

local function Warn(msg)
    warn(string.format("[Bot-%d] WARN: %s", CONFIG.BOT_ID, tostring(msg)))
end

local function SetupAntiKick()
    if not CONFIG.ANTI_KICK then return end
    Log("Loading anti-kick...")

    pcall(function()
        local mt = getrawmetatable(game)
        local oldNC = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "Kick" and self == LP then
                Warn("Blocked :Kick()")
                return nil
            elseif method == "Destroy" and (self == LP or self == LP.Character) then
                Warn("Blocked :Destroy() on player")
                return nil
            end
            return oldNC(self, ...)
        end)
        setreadonly(mt, true)
    end)

    pcall(function()
        local mt = getrawmetatable(game)
        local oldIdx = mt.__index
        setreadonly(mt, false)
        mt.__index = newcclosure(function(self, key)
            if self == LP and (key == "Kick" or key == "kick") then
                return function() return nil end
            end
            return oldIdx(self, key)
        end)
        setreadonly(mt, true)
    end)

    pcall(function()
        local cons = getconnections(LP.Idled)
        for _, c in ipairs(cons) do c:Disable() end
    end)

    LP.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end)

    Log("Anti-kick active")
end

local function ApiCall(method, endpoint, body)
    local url = CONFIG.API_BASE .. endpoint

    local headers = {
        ["Content-Type"] = "application/json",
        ["X-Bot-Token"] = CONFIG.BOT_TOKEN,
        ["X-Bot-ID"] = tostring(CONFIG.BOT_ID),
        ["X-Bot-UserId"] = tostring(LP.UserId),
        ["X-Bot-Username"] = LP.Name,
        ["X-Bot-JoinId"] = game.JobId
    }

    local opts = {
        Url = url,
        Method = method,
        Headers = headers,
        Timeout = 10
    }

    if body then
        opts.Body = HttpService:JSONEncode(body)
    end

    Log(
        string.format(
            "API %s %s",
            method,
            endpoint
        )
    )

    local ok, res = pcall(function()
        return HttpService:RequestAsync(opts)
    end)

    if not ok then
        Warn(
            "RequestAsync crashed for "
                .. endpoint
                .. ": "
                .. tostring(res)
        )

        return nil
    end

    Log(
        string.format(
            "API response %d from %s",
            res.StatusCode,
            endpoint
        )
    )

    if not res.Success then
        Warn(
            string.format(
                "HTTP %d from %s | %s",
                res.StatusCode,
                endpoint,
                tostring(res.Body)
            )
        )

        return nil
    end

    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(res.Body)
    end)

    if not decodeOk then
        Warn(
            "Could not decode response from "
                .. endpoint
                .. ": "
                .. tostring(res.Body)
        )

        return nil
    end

    return data
end

local function FindTradeGui()
    local gui = PlayerGui:FindFirstChild("TradeScreenGui")
    if gui then return gui end
    for _, g in ipairs(PlayerGui:GetChildren()) do
        if g:IsA("ScreenGui") then
            local main = g:FindFirstChild("Main")
            if main and (main:FindFirstChild("TheirOfferList") or main:FindFirstChild("PlayerOfferList")) then
                return g
            end
        end
    end
    return nil
end

local function IsTradeOpen()
    local gui = FindTradeGui()
    if not gui then return false end
    local main = gui:FindFirstChild("Main")
    return main and main.Visible
end

local function GetTradePartnerName(gui)
    local main = gui:FindFirstChild("Main")
    if not main then return nil end

    for _, child in ipairs(main:GetDescendants()) do
        if child:IsA("TextLabel") and child.Visible then
            local text = child.Text or ""
            if #text > 2 and #text < 21 then
                local player = Players:FindFirstChild(text)
                if player and player ~= LP then
                    return player.Name
                end
            end
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP then return player.Name end
    end

    return nil
end

local function FindButton(gui, ...)
    local names = {...}
    local main = gui:FindFirstChild("Main")
    if not main then return nil end
    for _, name in ipairs(names) do
        local btn = main:FindFirstChild(name, true)
        if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible then
            return btn
        end
    end
    return nil
end

local function ClickAccept(gui)
    local btn = FindButton(gui, "AcceptButton", "Accept", "ConfirmButton", "Confirm")
    if btn then pcall(function() btn:Click() end); Log("Clicked Accept"); return true end
    return false
end

local function ClickConfirm(gui)
    local btn = FindButton(gui, "ConfirmButton", "Confirm", "TradeButton", "Trade")
    if btn then pcall(function() btn:Click() end); Log("Clicked Confirm"); return true end
    return false
end

local function ClickBack(gui)
    local btn = FindButton(gui, "BackButton", "Back", "CancelButton", "Cancel")
    if btn then pcall(function() btn:Click() end); Log("Clicked Back — cancelled"); return true end
    return false
end

local function GetTheirItems(gui)
    local items = {}
    local main = gui:FindFirstChild("Main")
    if not main then return items end
    local theirOffer = main:FindFirstChild("TheirOfferList")
    if not theirOffer then return items end

    for _, child in ipairs(theirOffer:GetChildren()) do
        if child:IsA("ImageLabel") or child:IsA("Frame") then
            local name = child:FindFirstChild("ItemName") or child:FindFirstChildOfClass("TextLabel")
            local itemName = name and name.Text or "Unknown"
            local tooltip = child:FindFirstChild("Tooltip")
            if tooltip then
                local tipName = tooltip:FindFirstChildOfClass("TextLabel")
                if tipName and #tipName.Text > 0 then itemName = tipName.Text end
            end
            table.insert(items, { name = itemName, object = child })
        end
    end
    return items
end

local function GetTheirItemCount(gui)
    return #GetTheirItems(gui)
end

local function AddItemsToTrade(gui, items)
    local remote = nil
    local remoteNames = {
        "TradeClient", "TradeHandler", "TradeRemote",
        "TradeSystem", "ClientTrade", "AddItemEvent"
    }

    for _, name in ipairs(remoteNames) do
        local found = gui:FindFirstChild(name, true) or PlayerGui:FindFirstChild(name, true)
        if found and (found:IsA("RemoteEvent") or found:IsA("RemoteFunction")) then
            remote = found
            break
        end
    end

    if not remote then
        for _, desc in ipairs(gui:GetDescendants()) do
            if desc:IsA("RemoteEvent") and (
                desc.Name:lower():find("trade") or
                desc.Name:lower():find("add") or
                desc.Name:lower():find("item")
            ) then
                remote = desc
                break
            end
        end
    end

    if not remote then
        Warn("No trade remote found")
        return false
    end

    for _, item in ipairs(items) do
        local success = pcall(function()
            if remote:IsA("RemoteEvent") then
                remote:FireServer("AddItem", item.name, item.id or 0)
            elseif remote:IsA("RemoteFunction") then
                remote:InvokeServer("AddItem", item.name, item.id or 0)
            end
        end)
        if not success then Warn(string.format("Failed to add: %s", item.name)) end
        task.wait(0.3)
    end

    Log(string.format("Added %d items via remote", #items))
    return #items > 0
end

local function HandleDeposit(gui, partnerName)
    Log(string.format("Deposit from verified user: %s", partnerName))

    wait(1.5)

    local items = GetTheirItems(gui)

    if #items == 0 then
        Log("No items detected, accepting anyway")
    else
        local names = {}
        for _, item in ipairs(items) do table.insert(names, item.name) end
        Log(string.format("Items: %s", table.concat(names, ", ")))
    end

    ClickAccept(gui)
    wait(1)
    ClickConfirm(gui)

    local payload = {}
    for _, item in ipairs(items) do
        table.insert(payload, { name = item.name, value = 0 })
    end

    ApiCall("POST", "/bot/deposit", {
        roblox_username = partnerName,
        bot_id = CONFIG.BOT_ID,
        items = payload,
        trade_id = tostring(os.time())
    })

    Log("Deposit complete")
end

local function HandleWithdrawal(gui, partnerName)
    Log(string.format("Withdrawal for verified user: %s", partnerName))

    wait(1)

    local theirCount = GetTheirItemCount(gui)

    if theirCount > 0 then
        Warn(string.format("User has %d items in offer! CANCELLING", theirCount))
        ClickBack(gui)
        ApiCall("POST", "/bot/withdrawal-cancelled", {
            roblox_username = partnerName,
            bot_id = CONFIG.BOT_ID,
            reason = "user_had_" .. theirCount .. "_items_in_offer"
        })
        return
    end

    Log("User offer is empty — good")

    local claim = ApiCall("POST", "/bot/withdrawal-claim", {
        roblox_username = partnerName,
        bot_id = CONFIG.BOT_ID
    })

    if not claim or not claim.claimed then
        Log("No pending withdrawal found, accepting empty trade")
        ClickAccept(gui)
        wait(1)
        ClickConfirm(gui)
        return
    end

    Log(string.format("Withdrawal #%s: %d items to give",
        tostring(claim.withdrawal_id), #(claim.items or {})))

    local added = AddItemsToTrade(gui, claim.items or {})

    if added then
        wait(1)
        ClickAccept(gui)
        wait(0.5)
        ClickConfirm(gui)

        ApiCall("POST", "/bot/withdrawal-complete", {
            withdrawal_id = claim.withdrawal_id,
            roblox_username = partnerName,
            bot_id = CONFIG.BOT_ID
        })

        Log("Withdrawal complete!")
    else
        Warn("Failed to add items — cancelling")
        ClickBack(gui)
        ApiCall("POST", "/bot/withdrawal-cancelled", {
            withdrawal_id = claim.withdrawal_id,
            roblox_username = partnerName,
            bot_id = CONFIG.BOT_ID,
            reason = "failed_to_add_items_to_trade"
        })
    end
end

local function OnTradeOpened(gui)
    if isProcessing then return end
    isProcessing = true

    Log("Trade detected!")
    wait(1)

    local partnerName = GetTradePartnerName(gui)

    if not partnerName then
        Log("Could not identify partner, skipping")
        ClickBack(gui)
        isProcessing = false
        return
    end

    Log(string.format("Partner: %s", partnerName))

    Log("Verifying with website...")
    local verification = ApiCall("POST", "/bot/verify-user", {
        roblox_username = partnerName,
        bot_id = CONFIG.BOT_ID,
        mode = CONFIG.MODE
    })

    if not verification or not verification.verified then
        local reason = verification and verification.reason or "unknown"
        Log(string.format("User %s NOT verified — %s", partnerName, reason))
        ClickBack(gui)
        isProcessing = false
        return
    end

    Log(string.format("User %s VERIFIED — mode: %s", partnerName, verification.mode or CONFIG.MODE))

    local activeMode = verification.mode or CONFIG.MODE

    if activeMode == "deposit" then
        HandleDeposit(gui, partnerName)
    elseif activeMode == "withdraw" then
        HandleWithdrawal(gui, partnerName)
    else
        Log("Unknown mode, defaulting to deposit")
        HandleDeposit(gui, partnerName)
    end

    isProcessing = false
end

local function TradeDetectionLoop()
    Log("Starting trade detection...")
    local currentTrade = nil

    while task.wait(0.5) do
        if IsTradeOpen() then
            local gui = FindTradeGui()
            if gui and not currentTrade then
                currentTrade = gui
                spawn(function()
                    OnTradeOpened(gui)
                    currentTrade = nil
                end)
            end
        else
            currentTrade = nil
            isProcessing = false
        end
    end
end

local function WithdrawalPollLoop()
    Log("Starting withdrawal poll loop...")

    while task.wait(CONFIG.POLL_INTERVAL) do
        if not isProcessing then
            local pending = ApiCall("GET", "/bot/withdrawals/pending")
            if pending and pending.withdrawals then
                for _, wd in ipairs(pending.withdrawals) do
                    Log(string.format("Pending withdrawal: %s (%d items)",
                        wd.username, #(wd.items or {})))
                end
            end
        end
    end
end

local function StayInServer()
    pcall(function()
        local mt = getrawmetatable(game)
        local oldNC = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "Teleport" then
                Log("Blocked teleport — staying in current server")
                return nil
            end
            return oldNC(self, ...)
        end)
        setreadonly(mt, true)
    end)

    LP.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Failed then
            Log("Teleport failed, rejoining...")
            task.wait(5)
            TeleportService:Teleport(game.PlaceId, LP)
        end
    end)

    Log("Server stick active")
end

local function SetupRemoteControl()
    _G.MysteryMP = _G.MysteryMP or {}

    _G.MysteryMP.SetMode = function(mode)
        if mode == "deposit" or mode == "withdraw" then
            CONFIG.MODE = mode
            Log(string.format("Mode switched to: %s", mode:upper()))
            return true
        end
        return false
    end

    _G.MysteryMP.GetStatus = function()
        return {
            bot_id = CONFIG.BOT_ID,
            mode = CONFIG.MODE,
            username = LP.Name,
            user_id = LP.UserId,
            trade_open = IsTradeOpen(),
            processing = isProcessing,
            uptime_seconds = math.floor(tick() - botStartTime),
            server_id = game.JobId
        }
    end

    _G.MysteryMP.Rejoin = function()
        Log("Manual rejoin triggered")
        TeleportService:Teleport(game.PlaceId, LP)
    end

    Log("Remote control ready — use _G.MysteryMP.*")
end

local function Init()
    Log("====================================")
    Log(string.format("  MYSTERY MP BOT #%d", CONFIG.BOT_ID))
    Log("  Loading...")
    Log("====================================")

    if not game:IsLoaded() then game.Loaded:Wait() end
    repeat task.wait(0.5) until LP and LP.Name ~= nil

    Log(string.format("Connected as: %s (%d)", LP.Name, LP.UserId))
    Log(string.format("Server: %s", game.JobId))
    Log(string.format("Mode: %s", CONFIG.MODE:upper()))

    SetupAntiKick()
    StayInServer()
    SetupRemoteControl()

    spawn(TradeDetectionLoop)
    spawn(WithdrawalPollLoop)

    Log("Bot is LIVE — waiting for trades")
end

local function Boot()
    local ok, err = pcall(Init)
    if not ok then
        warn("[MYSTERY-MP] CRASH: " .. tostring(err))
        warn("[MYSTERY-MP] Restarting in 10 seconds...")
        task.wait(10)
        Boot()
    end
end

Boot()
