-- Loaded mission methods on the existing survivor controller. The durable team
-- still belongs to Persistence; movement, needs and transfers keep their owners.
local Missions = {}
local MISSION_DECISIONS = {
    away_mission=true, away_mission_travel=true, away_return=true,
    away_return_pending=true, away_waiting_for_team=true, away_collection_retry=true,
    away_continue_search=true, away_search_wait=true, away_waiting_for_world=true,
}

function Missions.install(Controller, context)
    local AWAY_TRAVEL_SEARCH_RADIUS_SQUARED = context.AWAY_TRAVEL_SEARCH_RADIUS_SQUARED
    local AWAY_TRAVEL_FAILURE_LIMIT = context.AWAY_TRAVEL_FAILURE_LIMIT
    local EXPLORATION_RETRY_TICKS = context.EXPLORATION_RETRY_TICKS
    local THINK_MIN_TICKS = context.THINK_MIN_TICKS
    local navigationDistanceSquared = context.navigationDistanceSquared
    local moveWithTravelPace = context.moveWithTravelPace
    local currentWorldAgeHours = context.currentWorldAgeHours

    function Controller:setAwayTeam(teamId)
        self.awayTeamId = type(teamId) == "string" and teamId ~= "" and teamId or nil
        local team = self.awayTeamId ~= nil and KnoxPersistence.getAwayTeam(self.awayTeamId) or nil
        local search=team and team.searchProgress and team.searchProgress[self.id]
        self.awaySearchStep=search and search.step or 0
        local member = team ~= nil and team.collection ~= nil and team.collection.byMember ~= nil
            and team.collection.byMember[self.id] or nil
        self.awayCollected = type(member) == "table" and member.collected == true
        self.awaySearches = math.max(0, math.floor(tonumber(
            type(member) == "table" and member.searches or 0) or 0))
        self.awaySearchMisses = 0
        self.awayTravelMisses = 0
        if self.awayTeamId ~= nil then
            self.activeDecision = "away_mission"
            self.state = "IDLE"
            self.nextThink = 0
        end
    end

    function Controller:beginAwayReturn(ticks)
        if self.awayTeamId == nil then return false end
        local target = KnoxAwayTeamExecutor.returnDestination(self.awayTeamId)
        if target == nil or getCell == nil or getCell() == nil then
            self:recordFailure("away_return_target_unavailable", ticks, EXPLORATION_RETRY_TICKS)
            return false
        end
        local square = getCell():getGridSquare(
            math.floor(tonumber(target.x) or 0),
            math.floor(tonumber(target.y) or 0),
            math.floor(tonumber(target.z) or 0)
        )
        local canStand = square ~= nil
        if canStand and square.canStand ~= nil then
            local ok, value = pcall(square.canStand, square)
            canStand = ok and value == true
        end
        if not canStand then
            self:recordFailure("away_return_square_unloaded", ticks, EXPLORATION_RETRY_TICKS)
            return false
        end
        local current = self.character:getCurrentSquare()
        if current ~= nil and navigationDistanceSquared(current, square) <= 2.25 then
            local result = KnoxPersistence.completeAwayTeamMember(
                self.awayTeamId, self.id, true, "returned_to_owner", currentWorldAgeHours()
            )
            if result ~= nil then
                self.awayTeamId = nil
                self.awayCollected = false
                self.activeDecision = nil
                self.state = "IDLE"
                self.nextThink = ticks + THINK_MIN_TICKS
                return true
            end
        end
        local movement = tostring(moveWithTravelPace(
            self.bridge, self.id, self.character, square, "return_home"
        ))
        if string.find(movement, "MOVE_STARTED", 1, true) ~= 1 then
            self:recordMovementFailure("away_return", movement, ticks, EXPLORATION_RETRY_TICKS)
            return false
        end
        self.activeDecision = "away_return"
        self.state = "AWAY_RETURN"
        return true
    end

    -- A finished team keeps no claim over a loaded member. Clearing this local
    -- mission state lets the same member resume ordinary base/companion work in
    -- this decision pass instead of waiting for an external reassignment.
    function Controller:clearFinishedAwayTeam(ticks, team)
        if self.awayTeamId == nil then return false end
        if team ~= nil and team.state ~= "complete" and team.state ~= "blocked" then
            return false
        end
        local decision = tostring(self.activeDecision or "")
        self.awayTeamId = nil
        self.awayCollected = false
        self.awaySearchMisses = 0
        self.awayTravelMisses = 0
        if MISSION_DECISIONS[decision] then
            self.activeDecision = nil
            if self.state == "IDLE" or self.state == "GROUP_WAIT"
                or self.state == "MOVING_TO_EXPLORE" then
                self.state = "IDLE"
                self.nextThink = math.min(self.nextThink or ticks, ticks)
            end
        end
        return true
    end

    -- A nearby member must visibly cover the distance to its mission area before
    -- searching it.  Hibernation already owns the far case: when the population
    -- lifecycle captures this body, the unloaded ledger keeps the durable
    -- destination and the mission resolves there without any body on screen.
    function Controller:beginAwayTravel(ticks, team)
        local destination = type(team.destination) == "table" and team.destination or nil
        local x = destination ~= nil and tonumber(destination.x) or nil
        local y = destination ~= nil and tonumber(destination.y) or nil
        local cell = getCell ~= nil and getCell() or nil
        local current = self.character ~= nil and self.character:getCurrentSquare() or nil
        local square = cell ~= nil and x ~= nil and y ~= nil
            and cell:getGridSquare(math.floor(x), math.floor(y), math.floor(tonumber(destination.z) or 0))
            or nil
        if square == nil or current == nil then
            self.activeDecision="away_waiting_for_world"
            KnoxPersistence.recordAwaySearch(self.awayTeamId,self.id,self.awaySearchStep,
                "waiting_for_world",currentWorldAgeHours())
            self.state="IDLE"
            self.nextThink=ticks+EXPLORATION_RETRY_TICKS
            return true
        end
        if navigationDistanceSquared(current, square) <= AWAY_TRAVEL_SEARCH_RADIUS_SQUARED then
            self.awayTravelMisses = 0
            return false
        end
        local movement = tostring(moveWithTravelPace(
            self.bridge, self.id, self.character, square, "directed"
        ))
        if string.find(movement, "MOVE_STARTED", 1, true) == 1 then
            self.activeDecision = "away_mission_travel"
            self.state = "MOVING_TO_EXPLORE"
            self.awayTravelMisses = 0
            return true
        end
        self.awayTravelMisses = (self.awayTravelMisses or 0) + 1
        if self.awayTravelMisses >= AWAY_TRAVEL_FAILURE_LIMIT then
            self.awayTravelMisses = 0
            self:recordMovementFailure("away_route_blocked", movement, ticks, EXPLORATION_RETRY_TICKS)
            return true
        end
        self:recordMovementFailure("away_travel", movement, ticks, EXPLORATION_RETRY_TICKS)
        return true
    end

    function Controller:beginAwayMission(ticks)
        if self.awayTeamId == nil then return false end
        local team = KnoxPersistence.getAwayTeam(self.awayTeamId)
        if team == nil then
            self.awayTeamId = nil
            return false
        end
        if team.state == "returning" then
            return self:beginAwayReturn(ticks)
        end
        if team.state ~= "awaiting_collection" and team.state ~= "collecting" then
            return false
        end
        if self.awayCollected then
            -- The final acknowledgement may be an empty search or another member.
            if KnoxAwayTeamExecutor.collectionReady(self.awayTeamId) then
                local returning = KnoxAwayTeamExecutor.beginReturn(self.awayTeamId, currentWorldAgeHours())
                if returning ~= nil then
                    self.awayCollected = false
                    self.state, self.activeDecision, self.nextThink = "IDLE", "away_return_pending", ticks
                    return true
                end
            end
            self.activeDecision = "away_waiting_for_team"
            self.state = "GROUP_WAIT"
            self.nextThink = ticks + 120
            return true
        end
        local _, beginResult = KnoxAwayTeamExecutor.beginCollection(
            self.awayTeamId, currentWorldAgeHours()
        )
        if beginResult == "not_collectible" then return false end
        if team.missionType~="scout" and KnoxAwayTeamExecutor.packFull(self.character) then
            return self:finishAwayCollection(ticks)
        end
        if self:beginAwayTravel(ticks, team) then return true end
        local directive = KnoxAwayTeamExecutor.destinationDirective(team,self.awaySearchStep)
        if directive == nil then
            self:recordFailure("away_destination_unavailable", ticks, EXPLORATION_RETRY_TICKS)
            return true
        end
        if ticks < (self.nextExplorationSearch or 0) then
            self.nextThink = self.nextExplorationSearch
            return true
        end
        if getCell():getGridSquare(directive.scanX,directive.scanY,directive.z)==nil then
            -- Missing chunks are not inspected rooms and cannot complete scouting.
            self.awaySearchStep=(self.awaySearchStep or 0)+1
            KnoxPersistence.recordAwaySearch(self.awayTeamId,self.id,self.awaySearchStep,
                "waiting_for_world",currentWorldAgeHours())
            self.state,self.activeDecision="IDLE","away_waiting_for_world"
            self.nextThink=ticks+EXPLORATION_RETRY_TICKS
            return true
        end
        if self:beginExploration(ticks, directive) then
            KnoxPersistence.recordAwaySearch(self.awayTeamId,self.id,self.awaySearchStep,
                directive.allowFallback and "fallback" or "searching",currentWorldAgeHours())
            self.awaySearchMisses = 0
            return true
        end
        self.awaySearchMisses = (self.awaySearchMisses or 0) + 1
        self.awaySearchStep=(self.awaySearchStep or 0)+1
        KnoxPersistence.recordAwaySearch(self.awayTeamId,self.id,self.awaySearchStep,
            directive.allowFallback and "fallback" or "searching",currentWorldAgeHours())
        self.activeDecision="away_search_wait"
        self.state="IDLE"
        self.nextThink=math.max(self.nextExplorationSearch or ticks,ticks+EXPLORATION_RETRY_TICKS)
        if team.missionType=="scout" and self.awaySearchMisses>=3 then
            return self:finishAwayCollection(ticks)
        end
        return true
    end

    -- A loaded away member acknowledges a destination only after the ordinary
    -- search/transfer action has finished.  This keeps mission results tied to
    -- real inventory state and lets the persistence layer hold the group until
    -- every member has completed the same boundary.
    function Controller:finishAwayCollection(ticks)
        if self.awayTeamId == nil then return false end
        local supply = self.pendingSupply
        -- Only observed native transfers count. Scarcity keeps resource duty;
        -- needs and combat remain in the normal controller priority order.
        local team=KnoxPersistence.getAwayTeam(self.awayTeamId)
        self.awaySearches = (self.awaySearches or 0) + 1
        local continues = KnoxAwayTeamExecutor.runContinues({
            searches = self.awaySearches,
            missionType = team ~= nil and team.missionType,
            packFull = KnoxAwayTeamExecutor.packFull(self.character),
        })
        local recorded, detail = KnoxAwayTeamExecutor.recordCollection(
            self.awayTeamId,
            self.id,
            supply,
            self.character,
            currentWorldAgeHours(),
            not continues
        )
        if recorded ~= nil then self:markAwayCargoDelivery(supply) end
        -- Remember the container that was just worked, so the next search moves on
        -- to the next real container instead of reopening the same crate.
        if supply ~= nil and supply.container ~= nil then
            self.inspectedContainers[supply.container] = ticks + EXPLORATION_RETRY_TICKS
        end
        self:releaseSupply()
        if recorded == nil then
            self:recordFailure(
                "away_collection_record:" .. tostring(detail),
                ticks,
                EXPLORATION_RETRY_TICKS
            )
            self.state = "IDLE"
            self.activeDecision = "away_collection_retry"
            self.nextThink = ticks + EXPLORATION_RETRY_TICKS
            return true
        end
        if continues then
            self.awayCollected = false
            self.awaySearchMisses = 0
            self.activeDecision = "away_continue_search"
            self.state = "IDLE"
            self.nextThink = ticks + THINK_MIN_TICKS
            return true
        end
        self.awaySearches = nil
        self.awayCollected = true
        self.awaySearchMisses = 0
        if KnoxAwayTeamExecutor.collectionReady(self.awayTeamId) then
            local _, returnResult = KnoxAwayTeamExecutor.beginReturn(
                self.awayTeamId,
                currentWorldAgeHours()
            )
            if returnResult == "returning" then
                self.awayCollected = false
                self.activeDecision = "away_return_pending"
                self.state = "IDLE"
                self.nextThink = ticks
                return true
            end
            self:recordFailure(
                "away_return_begin:" .. tostring(returnResult),
                ticks,
                EXPLORATION_RETRY_TICKS
            )
        end
        self.activeDecision = "away_waiting_for_team"
        self.state = "GROUP_WAIT"
        self.nextThink = ticks + 120
        return true
    end
end

return Missions
