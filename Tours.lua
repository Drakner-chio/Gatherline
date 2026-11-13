-- Gatherline: tours, several routes ridden one after the other, in different
-- zones too: the Barrens, then Stonetalon, then Ashenvale. Start on a tour
-- rides its first route (or the one in your zone) for its laps; when they're
-- done Shortest Path Forever leads you on to the next route, by flight path,
-- boat or portal if it's far, and so on to the last (and round again, if the
-- tour starts over at the end).
--
-- db.tours = { { id, name, stages = { routeID, ... }, laps (each route), loop } }
-- GP.tourRide = { tour, stage } while one is ridden.

local ADDON, ns = ...
local L = ns.L
local GP = ns.GP
local Print = GP.Print

GP.TOUR_MAX_STAGES = 12
GP.TOUR_LAPS = { 1, 10 }

-- The tours, checked: unknown routes dropped
function GP:Tours()
    local db = self.db
    if type(db.tours) ~= "table" then db.tours = {} end
    db.nextTourID = type(db.nextTourID) == "number" and db.nextTourID or 1
    local have = {}
    for _, r in ipairs(db.routes) do if r.id then have[r.id] = true end end
    for i = #db.tours, 1, -1 do
        local t = db.tours[i]
        if type(t) ~= "table" then
            table.remove(db.tours, i)
        else
            t.id = t.id or db.nextTourID
            if t.id >= db.nextTourID then db.nextTourID = t.id + 1 end
            t.name = type(t.name) == "string" and t.name or "Tour"
            t.laps = math.max(self.TOUR_LAPS[1], math.min(self.TOUR_LAPS[2], math.floor(tonumber(t.laps) or 1)))
            t.loop = t.loop == true
            local stages = {}
            for _, id in ipairs(type(t.stages) == "table" and t.stages or {}) do
                if have[id] and #stages < self.TOUR_MAX_STAGES then stages[#stages + 1] = id end
            end
            t.stages = stages
        end
    end
    return db.tours
end

function GP:RouteByID(id)
    for _, r in ipairs(self.db.routes) do if r.id == id then return r end end
end

-- Makes a tour (or changes one): opts = { name, stages = { routeID... }, laps, loop }
function GP:SaveTour(opts, tour)
    local stages = {}
    for _, id in ipairs(opts.stages or {}) do
        if self:RouteByID(id) and #stages < self.TOUR_MAX_STAGES then stages[#stages + 1] = id end
    end
    if #stages < 2 then
        Print(L["a tour needs at least two routes."])
        return nil
    end
    local tours = self:Tours()
    local name = (type(opts.name) == "string" and opts.name:match("^%s*(.-)%s*$")) or ""
    if name == "" then
        local parts = {}
        for i = 1, math.min(#stages, 3) do parts[i] = self:MapName(self:RouteByID(stages[i]).mapID) end
        name = table.concat(parts, " – ") .. (#stages > 3 and " …" or "")
    end
    for _, t in ipairs(tours) do
        if t ~= tour and t.name == name then
            Print(L["there's already a tour called |cffffd100%s|r."]:format(name))
            return nil
        end
    end
    if self.tourRide and self.tourRide.tour == tour then self:StopNav(true) end
    if not tour then
        tour = { id = self.db.nextTourID }
        self.db.nextTourID = self.db.nextTourID + 1
        tours[#tours + 1] = tour
    end
    tour.name, tour.stages = name, stages
    tour.laps = math.max(self.TOUR_LAPS[1], math.min(self.TOUR_LAPS[2], math.floor(tonumber(opts.laps) or 1)))
    tour.loop = opts.loop == true
    self:Changed()
    return tour
end

function GP:DeleteTour(tour)
    if self.tourRide and self.tourRide.tour == tour then self:StopNav(true) end
    for i, t in ipairs(self:Tours()) do
        if t == tour then table.remove(self.db.tours, i) break end
    end
    self:Changed()
end

-- One short line: "Brachland → Steinkrallen → Eschental"
function GP:TourLine(tour)
    local parts = {}
    for i, id in ipairs(tour.stages) do
        local r = self:RouteByID(id)
        parts[i] = r and self:MapName(r.mapID) or "?"
    end
    return table.concat(parts, " → ")
end

-- The tour's route lengths and laps added up, in seconds riding (not the way between)
function GP:TourTime(tour)
    local total = 0
    for _, id in ipairs(tour.stages) do
        local r = self:RouteByID(id)
        if r then total = total + (r.length or self:RouteLength(r)) / self:Speed() * tour.laps end
    end
    return total
end

function GP:IsTouring(tour)
    return self.tourRide ~= nil and (tour == nil or self.tourRide.tour == tour)
end

function GP:EndTour()
    self.tourRide = nil
end

-- Ride stage k of the ride's tour: false if it can't
local function RideStage(k)
    local ride = GP.tourRide
    local tour = ride.tour
    local route = GP:RouteByID(tour.stages[k])
    if not route then return false end
    ride.stage = k
    local keep = GP.tourRide
    if not GP:StartNav(route, tour.laps) then
        GP.tourRide = nil
        return false
    end
    GP.tourRide = keep   -- (StartNav stopped any ride before it, which ends a tour)
    GP:Changed()
    return true
end

-- Start a tour: at the first of its routes in your zone, else at its first
function GP:StartTour(tour)
    self:Tours()
    if not tour or #tour.stages < 2 then
        Print(L["that tour has fewer than two routes to ride."])
        return false
    end
    if not self:CanNavigate() then
        Print(L["needs |cffffd100Shortest Path Forever|r for the guidance. Install it, then /reload."])
        return false
    end
    local here, first = self:PlayerMap(), 1
    for k, id in ipairs(tour.stages) do
        local r = self:RouteByID(id)
        if r and r.mapID == here then first = k break end
    end
    if self:IsNavigating() then self:StopNav(true) end
    self.tourRide = { tour = tour, stage = first }
    if not RideStage(first) then return false end
    Print(L["tour |cffffd100%s|r: %d routes, %s each. Shortest Path takes you from one to the next."]:format(tour.name,
        #tour.stages, tour.laps == 1 and L["1 lap"] or L["%d laps"]:format(tour.laps)))
    return true
end

-- The ride's route is done: on to the next one (Navigation's Finish)
function GP:TourNext()
    local ride = self.tourRide
    if not ride then return end
    if InCombatLockdown and InCombatLockdown() then
        -- the next route can't be handed over in combat: once it's over
        if not ride.waiting then Print(L["the tour goes on once you're out of combat."]) end
        ride.waiting = true
        if C_Timer and C_Timer.After then C_Timer.After(1, function() if GP.tourRide == ride then GP:TourNext() end end) end
        return
    end
    ride.waiting = nil
    local tour = ride.tour
    local k = ride.stage + 1
    if k > #tour.stages then
        if not tour.loop then
            self.tourRide = nil
            Print(L["tour |cffffd100%s|r done."]:format(tour.name))
            self:Changed()
            return
        end
        k = 1
    end
    local route = self:RouteByID(tour.stages[k])
    if not route then
        self.tourRide = nil
        Print(L["tour |cffffd100%s|r stopped: one of its routes is gone."]:format(tour.name))
        self:Changed()
        return
    end
    Print(L["on to |cffffd100%s|r (%d of %d)."]:format(route.name, k, #tour.stages))
    RideStage(k)
end
