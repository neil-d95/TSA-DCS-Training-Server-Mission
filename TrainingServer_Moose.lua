-- ============================================================================
-- DCS MISSION ARCHITECT AUDITED SCRIPT: Caucasus Training Range
-- Frameworks: MOOSE 2.9.16 / MIST 4.5.126
-- ============================================================================

local debugger = 1 -- Set to 1 for debug messages
local bomber_mission = 0
local AmbushTriggered = false
local TankerCommands = {}

-- 1. TANKER SYSTEM (Carrier Based)
local tankerStennis = RECOVERYTANKER:New("USS Roosevelt", "Arco21")
tankerStennis:SetTACAN(13, "TKR")
tankerStennis:SetRadio(313)
tankerStennis:__Start(1)

-- 2. AIRCRAFT SPAWNING SYSTEM
local function SpawnAircraft(PlaneTemplateName)
    local SpawnObj = SPAWN:New(PlaneTemplateName)
        :InitLimit(4, 1)
        :OnSpawnGroup(function(MooseGroup)
            MooseGroup:HandleEvent(EVENTS.Land)
            MooseGroup:HandleEvent(EVENTS.Crash)
            
            function MooseGroup:OnEventCrash(EventData)
                if debugger == 1 then
                    MESSAGE:New("To all Players: " .. PlaneTemplateName .. " destroyed!", 10):ToAll()
                end
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
    SCHEDULER:New(nil, function() FightAircraft_Menu() end, {}, 0.5)
    MESSAGE:New("To all Players: " .. PlaneTemplateName .. " is airborne!", 15):ToAll()
end

-- 3. TANKER SPAWNING
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
    
    if Difficulty == "Hard" then SpawnObj:InitSkill("Hard") end
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

-- 5. TRAIN AMBUSH
local TrainZone = { ZONE:New( "Train_Unload_Zone" ) }
local Spawn_Armor_1 = SPAWN:New("RED_ARMOR_1"):InitLimit(10, 10):InitRandomizeZones( TrainZone )
local Spawn_Armor_2 = SPAWN:New("RED_ARMOR_2"):InitLimit(10, 10):InitRandomizeZones( TrainZone )
local Spawn_AD = SPAWN:New("RED_AD"):InitLimit(10, 10):InitRandomizeZones( TrainZone )
local Spawn_CAP = SPAWN:New("RED_CAP_TEMPLATE"):InitLimit(2, 10)

function Spawn_Train()
   local TrainName = "LOGI_TRAIN"
   local StationZone = "Train_Unload_Zone"
   AmbushTriggered = false
   trigger.action.setUserFlag(100, true) 
   MESSAGE:New("To all Players: Reinforcements Train Departed Soganlug!", 25):ToAll()

   local AmbushMonitor = nil
   AmbushMonitor = SCHEDULER:New(nil, function()
        if AmbushTriggered == false then
            local TrainUnit = Unit.getByName(TrainName)
            if TrainUnit and TrainUnit:isExist() then
                local Pos = TrainUnit:getPoint()
                local Velocity = TrainUnit:getVelocity()
                local AbsSpeed = (Velocity.x^2 + Velocity.y^2 + Velocity.z^2)^0.5
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
    SCHEDULER:New(nil, function() Spawn_CAP:Spawn() end, {}, 120)
end

-- 6. SUKHUMI GROUND ATTACK
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

function Refresh_Aircraft_Menu(reason) FightAircraft_Menu() end

-- --- MISSION: THE TRIPLETS ---
local TripletNames = { "Tbilisi-Lochini", "Vaziani", "Soganlug" }
local CapturedCount = 0
local MissionActive = false

-- Ensure these RED_... names match the "Unit Name" or "Group Name" of your ME Templates exactly
local TripletStatus = {
    ["Tbilisi-Lochini"] = { captured = false, red_group = "RED_LOCHINI_DEFENSE" },
    ["Vaziani"]         = { captured = false, red_group = "RED_VAZIANI_DEFENSE" },
    ["Soganlug"]        = { captured = false, red_group = "RED_SOGANLUG_DEFENSE" }
}

function Start_Triplets_Mission()
    if MissionActive then return end
    MissionActive = true
    
    MESSAGE:New("TRAINING: Triplets Mission Activated. Defend the sectors!", 15):ToAll()
    
    -- Loop through and spawn the defense groups
    for name, data in pairs(TripletStatus) do 
        -- We use :InitLimit(1,0) to ensure only one set of SAMs/Defense spawns per airfield
        local DefenseSpawn = SPAWN:New(data.red_group)
        if DefenseSpawn then
            DefenseSpawn:Spawn()
            if debugger == 1 then env.info("TRIPLETS: Spawning defense for " .. name) end
        else
            env.info("TRIPLETS ERROR: Could not find template " .. data.red_group)
        end
    end

    -- Monitor Capture Status
    SCHEDULER:New(nil, function()
        if not MissionActive then return end
        for _, Name in ipairs(TripletNames) do
            local AirbaseObj = AIRBASE:FindByName(Name)
            -- Coalition 2 is BLUE. If Airbase is Blue and we haven't marked it captured yet...
            if AirbaseObj and AirbaseObj:GetCoalition() == 2 and not TripletStatus[Name].captured then
                TripletStatus[Name].captured = true
                CapturedCount = CapturedCount + 1
                MESSAGE:New("TRIPLETS: " .. Name .. " Sector Secured!", 15):ToAll()
            end
        end
        
        -- Optional: End mission if all 3 are captured
        if CapturedCount >= 3 then
            MESSAGE:New("TRIPLETS: All sectors secured. Mission Complete!", 30):ToAll()
            MissionActive = false
        end
    end, {}, 5, 10)
end

-- ============================================================================
-- INITIALIZE ALL MENUS
-- ============================================================================
Spawn_Aircraft_Root = MENU_COALITION:New(coalition.side.BLUE, "Spawn Enemy Aircraft")
FightAircraft_Menu()

local TankerRoot = MENU_COALITION:New(coalition.side.BLUE, "Spawn Tankers")
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "North Tanker", TankerRoot, SpawnTanker, "North")
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "South Tanker", TankerRoot, SpawnTanker, "South")
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "East Tanker",  TankerRoot, SpawnTanker, "East")
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "West Tanker",  TankerRoot, SpawnTanker, "West")

Range = MENU_COALITION:New(coalition.side.BLUE, "Range")
Range_Menu()

Missions = MENU_COALITION:New(coalition.side.BLUE, "Missions")
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Show Scoreboard", Missions, DisplayScoreboard)
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Enemy Reinforcements (Train)", Missions, Spawn_Train)
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Sukhumi Ground Attack", Missions, Spawn_Moving_Ground)

local TripletMenu = MENU_COALITION:New(coalition.side.BLUE, "Triplets Mission", Missions)
MENU_COALITION_COMMAND:New(coalition.side.BLUE, "Start Triplets Practice", TripletMenu, Start_Triplets_Mission)

env.info("AUDITED MISSION SCRIPT LOADED SUCCESSFULLY")