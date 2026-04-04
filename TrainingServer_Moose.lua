-- ============================================================================ 
-- DCS MISSION ARCHITECT AUDITED SCRIPT: Caucasus Training Range
-- Frameworks: MOOSE 2.9.16 / MIST 4.5.126
-- ============================================================================ 

local debugger = 1 
-- Set to 1 for debug messages 
local bomber_mission = 0 
local AmbushTriggered = false 
local TankerCommands = {} 

-- =============================================
-- Carrier Landing Logger & Tanker Setup
-- Best practices: multiplayer-safe, error-handled
-- =============================================

-- Carrier-Based Tanker Setup
local status, tankerStennis = pcall(function()
    local t = RECOVERYTANKER:New("USS Roosevelt", "Arco21")
    t:SetTACAN(13, "TKR")
    t:SetRadio(313)
    t:__Start(1)
    return t
end)
if not status then
    env.info("[ERROR] Failed to start Carrier Tanker")
end

-- ===============================
-- Carrier Landing Logging
-- ===============================
CarrierTrapLog = CarrierTrapLog or {}

-- Event handler
CarrierTrapLog = {
    landings = {}
}

function CarrierTrapLog:onEvent(event)
    if not event or not event.initiator then return end
    if event.id ~= world.event.S_EVENT_LAND then return end

    local unit = event.initiator
    if not Unit.isExist(unit) then return end

    local playerName = unit:getPlayerName() or "AI"
    local carrier = event.place and event.place:getName() or "Unknown Carrier"

    -- Basic grading placeholder
    local grade = "OK"  -- Replace with your LSO grading logic

    -- Store landing safely
    CarrierTrapLog.landings[playerName] = CarrierTrapLog.landings[playerName] or {}
    table.insert(CarrierTrapLog.landings[playerName], {
        time = timer.getTime(),
        carrier = carrier,
        grade = grade,
        position = unit:getPoint()
    })

    env.info(string.format("[TRAP] %s landed on %s: %s", playerName, carrier, grade))
end

world.addEventHandler(CarrierTrapLog)

-- ===============================
-- Data Export Function (JSON)
-- ===============================
function CarrierTrapLog:exportToFile()
    local path = lfs.writedir() .. "Logs\\carrier_trap_log.json"
    local success, err = pcall(function()
        local file = io.open(path, "w")
        if not file then return end

        -- Simple JSON encoding using dkjson (add dkjson.lua in mission scripts)
        local json = require("dkjson")
        file:write(json.encode(CarrierTrapLog.landings))
        file:close()
    end)
    if not success then
        env.info("[ERROR] Failed to export carrier trap log: " .. tostring(err))
    end
end

-- Schedule periodic export every 5 minutes
timer.scheduleFunction(function()
    CarrierTrapLog:exportToFile()
    return timer.getTime() + 300  -- 300 seconds = 5 minutes
end, {}, timer.getTime() + 5)

-- 1. Enemy AIRCRAFT SPAWNING SYSTEM
local function SpawnAircraft(PlaneTemplateName)     
    local SpawnObj = SPAWN:New(PlaneTemplateName)
        :InitLimit(4, 1)
        :OnSpawnGroup(function(MooseGroup)
            -- Handle Events locally for this specific spawned group
            MooseGroup:HandleEvent(EVENTS.Land)
            MooseGroup:HandleEvent(EVENTS.Crash)
            
            function MooseGroup:OnEventCrash(EventData)
                if debugger == 1 then
                    MESSAGE:New("To all Players: " .. PlaneTemplateName .. " destroyed!", 10):ToAll()
                end
                -- Delay refresh to ensure UI doesn't stutter 
                timer.scheduleFunction(function() Refresh_Aircraft_Menu("Dead") end, nil, timer.getTime() + 5)
            end

            function MooseGroup:OnEventLand(EventData)
                if MooseGroup:AllOnGround() then
                    if debugger == 1 then
                        MESSAGE:New("To all Players: " .. PlaneTemplateName .. " has landed and returned to base.", 10):ToAll()
                    end
                    MooseGroup:Destroy()
                    Refresh_Aircraft_Menu("Landed")
                end
            end
        end)
    
    SpawnObj:Spawn()
    -- Immediate menu update for remaining slots
    SCHEDULER:New(nil, function() FightAircraft_Menu() end, {}, 0.5)
    MESSAGE:New("To all Players: " .. PlaneTemplateName .. " is airborne!", 15):ToAll()
end

-- 2. TANKER SPAWNING 
function SpawnTanker(Direction)     
    local TankerTemplates = {         
        ["West"]  = {"Tanker West 1", "Tanker West 2"},         
        ["North"] = {"Tanker North 1", "Tanker North 2", "Tanker North 3"},         
        ["South"] = {"Tanker South"},         
        ["East"]  = {"Tanker East"}     
    }          
    
    local templates = TankerTemplates[Direction]     
    if templates then         
        for i, tName in ipairs(templates) do             
            local TkrSpawn = SPAWN:New(tName):InitLimit(1, 0):Spawn()         
        end     
    end
    
    -- Clean up the menu command after spawning
    if TankerCommands[Direction] then
        TankerCommands[Direction]:Remove()
        TankerCommands[Direction] = nil
    end
end

-- 4. RANGE SYSTEM
local ActiveRangeGroup = nil

function Range_Menu()
    if Range then Range:RemoveSubMenus() end
    if ActiveRangeGroup and ActiveRangeGroup:IsAlive() then
        MENU_COALITION_COMMAND:New(coalition.side.BLUE, "--- DESPAWN CURRENT RANGE ---", Range, Despawn_Range)
    else
        MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Spawn Easy Range (Unarmed)", Range, Spawn_Range_Target, "Easy")
        MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Spawn Medium Range (Armed)", Range, Spawn_Range_Target, "Medium")
        MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Spawn Hard Range (High Skill)", Range, Spawn_Range_Target, "Hard")
    end
end

function Spawn_Range_Target(Difficulty)
    local TemplateMap = { ["Easy"] = "Range-1", ["Medium"] = "Range", ["Hard"] = "Range" }
    local templateName = TemplateMap[Difficulty]
    local targetZone = ZONE:New("Range")
    
    local SpawnObj = SPAWN:New(templateName)
        :InitLimit(30, 0)
        :InitRandomizeZones({targetZone})
    
    if Difficulty == "Hard" then
        SpawnObj:InitSkill("Hard")
    end
    
    ActiveRangeGroup = SpawnObj:Spawn()
    MESSAGE:New("Range [" .. Difficulty .. "] Active.", 15):ToAll()
    SCHEDULER:New(nil, function() Range_Menu() end, {}, 0.5)
end

function Despawn_Range()
    if ActiveRangeGroup and ActiveRangeGroup:IsAlive() then
        ActiveRangeGroup:Destroy()
        ActiveRangeGroup = nil
        MESSAGE:New("Range Cleared.", 10):ToAll()
    end
    SCHEDULER:New(nil, function() Range_Menu() end, {}, 0.5)
end

-- MISSION : Carrier Protect Mission
-- Gobal State
function Bomber_Attack()
    if bomber_mission == 0 then
        bomber_mission = 2
        local EscortSpawn = SPAWN:New("Ship attack escort")
            :InitLimit(4, 2)
            
        -- --- FUNCTION TO HANDLE SPAWNING AND TASKING ---
        local function LaunchWave(TemplateName, DelayText)
            local WaveSpawn = SPAWN:New(TemplateName):InitLimit(2, 1)
            WaveSpawn:OnSpawnGroup(function(MooseGroup)
                local MyEscort = EscortSpawn:Spawn()
                if MyEscort then
                    SCHEDULER:New(nil, function()
                        if MyEscort:IsAlive() and MooseGroup:IsAlive() then
                            -- OFFSET PARAMETERS:
                            -- -200: 200m behind the bomber's nose
                            -- 100:  100m above the bomber
                            -- 500:  500m to the right (out of the exhaust!)
                            local Offset = { x = -200, y = 100, z = 500 }
                            -- We pass the Offset table into the TaskEscort call
                            local Task = MyEscort:TaskEscort(MooseGroup, Offset)
                            MyEscort:PushTask(Task)
                        end
                    end, {}, 2)
                end
            end):Spawn()
            MESSAGE:New("RADAR ALERT: " .. DelayText .. " detected inbound on Carrier!", 15):ToAll()
        end
        
        -- --- EXECUTE WAVES ---
        -- Wave 1: Immediate
        LaunchWave("Ship attack", "Initial Bomber Wave")
        -- Wave 2: Forced 240 second delay using a Scheduler
        SCHEDULER:New(nil, function()
            LaunchWave("Ship attack-1", "Secondary Bomber Wave")
        end, {}, 240)
    end
end 

-- MISSION: TRAIN AMBUSH (Automation via Monitoring) 
-- Ensure "RED_ARMOR_1", "RED_ARMOR_2", "RED_AD", "RED_CAP_TEMPLATE" exist as templates in ME 
-- Ensure unit "LOGI_TRAIN" exists on the track and "Train_Unload_Zone" is a trigger zone 
local TrainZone = { ZONE:New( "Train_Unload_Zone" ) }
local Spawn_Armor_1 = SPAWN:New("RED_ARMOR_1"):InitLimit(10, 10):InitRandomizeZones( TrainZone )
local Spawn_Armor_2 = SPAWN:New("RED_ARMOR_2"):InitLimit(10, 10):InitRandomizeZones( TrainZone )
local Spawn_AD = SPAWN:New("RED_AD"):InitLimit(10, 10):InitRandomizeZones( TrainZone )
local Spawn_CAP_Ambush = SPAWN:New("RED_CAP_TEMPLATE"):InitLimit(2, 10)

function Spawn_Train()
    local TrainName = "LOGI_TRAIN"
    local StationZone = "Train_Unload_Zone"
    AmbushTriggered = false
    trigger.action.setUserFlag(100, true) -- ME flag for train movement
    MESSAGE:New("To all Players: Reinforcements Train Departed Soganlug!", 25):ToAll()

    local AmbushMonitor = nil
    AmbushMonitor = SCHEDULER:New(nil, function()
        if AmbushTriggered == false then
            local TrainUnit = Unit.getByName(TrainName)
            if TrainUnit and TrainUnit:isExist() then
                local Pos = TrainUnit:getPoint()
                local Velocity = TrainUnit:getVelocity()
                local AbsSpeed = (Velocity.x^2 + Velocity.y^2 + Velocity.z^2)^0.5
                -- If train is in zone and speed is near zero
                if mist.pointInZone(Pos, StationZone) and AbsSpeed < 0.5 then
                    TriggerAmbush()
                    AmbushMonitor:Stop()
                end
            else
                AmbushMonitor:Stop()
            end
        else
            AmbushMonitor:Stop()
        end
    end, {}, 1, 5) 
end

function TriggerAmbush()
    AmbushTriggered = true
    trigger.action.outText("RECON: The train has stopped! Red forces are offloading!", 15)
    Spawn_Armor_1:Spawn()
    Spawn_Armor_2:Spawn()
    Spawn_AD:Spawn()
    SCHEDULER:New(nil, function() Spawn_CAP_Ambush:Spawn() end, {}, 120)
end

--  MISSION: SUKHUMI GROUND ATTACK (Capture Logic) 
local MovingForceSpawn = SPAWN:New("Moving Targets")
local MovingForceGroup = nil
local GudautaCaptureMonitor = nil

function Spawn_Moving_Ground()
    if MovingForceGroup and MovingForceGroup:IsAlive() then
        MESSAGE:New("INTEL: Strike force already active!", 10):ToAll()
    else
        MovingForceGroup = MovingForceSpawn:Spawn()
        if MovingForceGroup then
            MESSAGE:New("To all Players: Sukhumi Force moving on Gudauta!", 25):ToAll()
            Start_Gudauta_Monitor()
        end
    end
end

function Start_Gudauta_Monitor()
    local CaptureZone = ZONE:New("Gudauta_Capture_Zone") 
    local GudautaBase = AIRBASE:FindByName("Gudauta")
    if GudautaCaptureMonitor then GudautaCaptureMonitor:Stop() end

    GudautaCaptureMonitor = SCHEDULER:New(nil, function()
        if MovingForceGroup and MovingForceGroup:IsAlive() then
            if MovingForceGroup:IsAnyInZone(CaptureZone) then
                trigger.action.setAirdromeCoalition(GudautaBase:GetID(), coalition.side.RED)
                MESSAGE:New("CRITICAL ALERT: Gudauta Airbase Captured by Red!", 30):ToAll()
                GudautaCaptureMonitor:Stop()
            end
        else
            GudautaCaptureMonitor:Stop()
        end
    end, {}, 5, 5)
end

-- 7. MENU BUILDING 
function FightAircraft_Menu()
    if Spawn_Fighters then Spawn_Fighters:Remove() end
    Spawn_Fighters = MENU_COALITION:New(coalition.side.BLUE, "Spawn Enemy Aircraft", Spawn_Aircraft_Root)
    
    local PlaneList = {"MiG-15", "MiG-19", "MiG-21", "MiG-23", "MiG-28", "MiG-29", "MiG-31", "Su-27", "Su-30"}
    for _, name in ipairs(PlaneList) do
        local ActiveGroup = GROUP:FindByName(name .. "#001")
        if not (ActiveGroup and ActiveGroup:IsAlive()) then
            MENU_COALITION_COMMAND:New(coalition.side.BLUE, name, Spawn_Fighters, SpawnAircraft, name)
        end
    end
end

function Refresh_Aircraft_Menu(reason)
    FightAircraft_Menu()
end

-- MISSION: THE TRIPLETS
-- Targets: Tbilisi-Lochini, Vaziani, Soganlug 
-- 1. CONFIGURATION & STATE 
local TripletNames = { "Tbilisi-Lochini", "Vaziani", "Soganlug" } 
local CapturedCount = 0 
local TotalGoals = 3 
local MissionActive = false 

-- Table to track persistence 
local TripletStatus = {     
    ["Tbilisi-Lochini"] = { captured = false, msg = "NORTHERN SECTOR: Tbilisi-Lochini", red_group = "RED_LOCHINI_DEFENSE" },     
    ["Vaziani"]         = { captured = false, msg = "CENTRAL HUB: Vaziani", red_group = "RED_VAZIANI_DEFENSE" },     
    ["Soganlug"]        = { captured = false, msg = "SOUTHERN SECTOR: Soganlug", red_group = "RED_SOGANLUG_DEFENSE" } 
} 

-- CAP Configuration 
local CAP_GroupName = "RED_TRIPLETS_CAP"  
local SpawnCAP = nil  

-- 2. CAP LOGIC (Combat Air Patrol with 10-minute silent respawn) 
local function SetupCAP()
    if not MissionActive then return end
    if not SpawnCAP then
        SpawnCAP = SPAWN:New(CAP_GroupName):InitLimit(2, 20)
    end
    
    local TripletsCAPGroup = SpawnCAP:Spawn()
    if TripletsCAPGroup then
        local VazianiAirbase = AIRBASE:FindByName("Vaziani")
        local PatrolCoord = VazianiAirbase and VazianiAirbase:GetCoordinate() or TripletsCAPGroup:GetCoordinate()
        local OrbitTask = TripletsCAPGroup:TaskOrbit(PatrolCoord, 4500, 600)
        TripletsCAPGroup:PushTask(OrbitTask)
        TripletsCAPGroup:OptionROEWeaponFree()
        TripletsCAPGroup:OptionROTEvadeFire()
        env.info("TRIPLETS: CAP Spawned. Monitoring for destruction...")
        
        local DeathCheck = SCHEDULER:New(nil, function()
            if not TripletsCAPGroup:IsAlive() and MissionActive then
                MESSAGE:New("INTEL: Enemy CAP destroyed. Airspace clear for now.", 10):ToAll()
                SCHEDULER:New(nil, function()
                    if MissionActive and CapturedCount < 2 then
                        SetupCAP()
                    end
                end, {}, 600)
                return false 
            end
        end, {}, 30, 30)
    end 
end

-- 3. SAM NETWORK & MISSION LOGIC 
local CentralSAMs = {
    "Central_SA10_Group", "Central_SA2_Group", "Southern_EWR_Group",
    "SA2_Outpost_North", "SA2_Outpost_West", "SA2_Outpost_South" 
}

local function CheckSAMStatus()
    for _, samName in ipairs(CentralSAMs) do
        local SamGroup = GROUP:FindByName(samName)
        if SamGroup and SamGroup:IsAlive() then
            if CapturedCount == 1 then
                SamGroup:OptionROEWeaponFree()
            elseif CapturedCount == 2 then
                SamGroup:OptionAlarmStateGreen()
                MESSAGE:New("INTEL: Red ground defenses collapsing. Air cover is withdrawing!", 10):ToAll()
            end
        end
    end 
end 

-- 4. START MISSION 
function Start_Triplets_Mission()
    if MissionActive then return end
    MissionActive = true
    MESSAGE:New("TRAINING: Triplets Mission Activated. Secure Lochini, Vaziani, and Soganlug.", 15):ToAll()
    -- Spawn Ground Defenses
    for _, samName in ipairs(CentralSAMs) do
        local S = SPAWN:New(samName)
        if S then S:Spawn() end
    end          
    for _, data in pairs(TripletStatus) do
        local S = SPAWN:New(data.red_group)
        if S then S:Spawn() end
    end
    SetupCAP()

    SCHEDULER:New(nil, function()
        if not MissionActive then return end
        for _, Name in ipairs(TripletNames) do
            local AirbaseObj = AIRBASE:FindByName(Name)
            if AirbaseObj and AirbaseObj:GetCoalition() == 2 and not TripletStatus[Name].captured then
                TripletStatus[Name].captured = true
                CapturedCount = CapturedCount + 1
                CheckSAMStatus()
                MESSAGE:New("TRIPLETS: " .. TripletStatus[Name].msg .. " is now under BLUE CONTROL!", 15):ToAll()
                if CapturedCount == TotalGoals then
                    MESSAGE:New("MISSION SUCCESS: The Triplets have been liberated!", 30):ToAll()
                    MissionActive = false
                else
                    MESSAGE:New("PROGRESS: " .. (TotalGoals - CapturedCount) .. " sectors remaining.", 10):ToAll()
                end
            end
        end
    end, {}, 5, 10) 
end

-- =====================================================
-- PRECISION WEATHER CONTROL SYSTEM (TRAINING SERVER)
-- =====================================================


-- CONFIG (Visibility in meters)

local WeatherPresets = {
    ["1_2_NM"] = 926,    -- 0.5 nautical mile
    ["3_4_NM"] = 1389,   -- 0.75 nautical mile
    ["1_NM"]   = 1852,   -- 1 nautical mile
    ["CLEAR"]  = 20000
}

local FogThickness = 3000

-- CORE FUNCTION

local function SetWeather(visibility, label)

    local success, err = pcall(function()

        if UTILS and UTILS.Weather then
            UTILS.Weather.SetFogThickness(visibility >= 20000 and 0 or FogThickness)
            UTILS.Weather.SetFogVisibilityDistance(visibility)
        else
            env.error("UTILS.Weather not available!")
        end

        MESSAGE:New(
            string.format("METAR UPDATE:\nVisibility set to %s", label),
            15
        ):ToAll()

        env.info("Weather set to: " .. label)

    end)

    if not success then
        env.error("SetWeather ERROR: " .. tostring(err))
    end
end

-- PRESET FUNCTIONS
-- =====================================================

local function Set_1_2_NM()
    SetWeather(WeatherPresets["1_2_NM"], "1/2 NM (926m)")
end

local function Set_3_4_NM()
    SetWeather(WeatherPresets["3_4_NM"], "3/4 NM (1389m)")
end

local function Set_1_NM()
    SetWeather(WeatherPresets["1_NM"], "1 NM (1852m)")
end

local function Set_Clear()
    SetWeather(WeatherPresets["CLEAR"], "CAVOK (Clear)")
end

-- End Mission
function FinalizeMission()
    trigger.action.outText("Restarting Mission on server in 10 seconds...", 10)
    
    -- Delay the actual end so players can read the message
    timer.scheduleFunction(function()
        -- This command triggers the standard DCS Mission End/Victory screen
        trigger.action.setUserFlag(666, true) -- Optional: trigger an ME flag if needed
        trigger.action.endMission() 
    end, nil, timer.getTime() + 10)
end

-- ============================================================================
-- INITIALIZE ALL MENUS
-- ============================================================================
-- Spawn_Aircraft_Root = MENU_COALITION:New(coalition.side.BLUE, "Spawn Enemy Aircraft")
FightAircraft_Menu()

local TankerRoot = MENU_COALITION:New(coalition.side.BLUE, "Spawn Tankers")
TankerCommands["North"] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "North Tanker", TankerRoot, SpawnTanker, "North")
TankerCommands["South"] = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "South Tanker", TankerRoot, SpawnTanker, "South")
TankerCommands["East"]  = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "East Tanker",  TankerRoot, SpawnTanker, "East")
TankerCommands["West"]  = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "West Tanker",  TankerRoot, SpawnTanker, "West")

Range = MENU_COALITION:New(coalition.side.BLUE, "Range")
Range_Menu()

Missions = MENU_COALITION:New(coalition.side.BLUE, "Missions") 
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Enemy Reinforcements", Missions, Spawn_Train) 
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Protect Carrier Group", Missions, Bomber_Attack )
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Protect Gudauta", Missions, Spawn_Moving_Ground ) 

-- 4. RADIO MENU INTERFACE -- Integrating into your existing 'Missions' menu 
local TripletMenu = MENU_COALITION:New(coalition.side.BLUE, "Triplets Mission", Missions) 
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Start Triplets Practice", TripletMenu, Start_Triplets_Mission) 

-- 5. INTEL UPDATE (Radio Menu) 
local MenuStatus = MENU_COALITION:New(coalition.side.BLUE, "Triplet Status", TripletMenu)
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Check Captured Sectors", MenuStatus, function()
    if not MissionActive then
        MESSAGE:New("INFO: Triplets mission is not currently active.", 5):ToAll()
        return
    end
    local report = "CURRENT SECTOR STATUS:\n"
    for _, Name in ipairs(TripletNames) do
        local status = TripletStatus[Name].captured and "SECURE" or "HOSTILE"
        report = report .. "- " .. Name .. ": " .. status .. "\n"
    end
    report = report .. "\nSAM Network Strength: " .. (100 - (CapturedCount * 33)) .. "%"
    MESSAGE:New(report, 15):ToAll() 
end)

-- Weather Menu
local WeatherMenu = MENU_MISSION:New("Weather Presets")

MENU_MISSION_COMMAND:New("Set 1/2 NM Visibility", WeatherMenu, Set_1_2_NM)
MENU_MISSION_COMMAND:New("Set 3/4 NM Visibility", WeatherMenu, Set_3_4_NM)
MENU_MISSION_COMMAND:New("Set 1 NM Visibility", WeatherMenu, Set_1_NM)
MENU_MISSION_COMMAND:New("Set Clear Weather", WeatherMenu, Set_Clear)

-- End Mission
local EndButton = MENU_COALITION_COMMAND:New(coalition.side.BLUE, "--- Restarting Mission ---", nil, FinalizeMission)

env.info("AUDITED MISSION SCRIPT LOADED SUCCESSFULLY")