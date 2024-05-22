local AddonName, SAO = ...
local Module = "bucket"

--[[
    Bucket of Displays and Triggers

    A 'bucket' is a container that stores maps of display objects
    Buckets are maps which key is a number of stacks, and value is a display
]]

--[[
    Lists of auras and effects that must be tracked
    These lists should be setup at start, based on the player class
]]
SAO.RegisteredBucketsByName = {}
SAO.RegisteredBucketsBySpellID = {}

-- List of aura arrays, indexed by stack count
-- A stack count of zero means "for everyone"
-- A stack count of non-zero means "for a specific number of stacks"
SAO.Bucket = {
    create = function(self, name, spellID)
        local bucket = {
            name = name, -- Name should be unique amongst buckets

            -- Spell ID is the main identifier to activate/deactivate visuals
            spellID = spellID,

            -- Talent Tab-Index is an option object { tab, index } telling the talent location in the player's tree
            talentTabIndex = nil,

            -- Stack-agnostic means the bucket does not care about its number of stacks
            stackAgnostic = true,

            -- Initialize current state with unattainable values
            currentStacks = -1,
            currentActionUsable = nil,
            currentTalented = nil,
            currentHolyPower = nil,

            -- Initially, nothing is displayed
            displayedHash = nil,
            currentHash = nil,
            hashCalculator = SAO.Hash:new(),

            -- Constant for more efficient debugging
            description = name.." ("..spellID..(GetSpellInfo(spellID) and " = "..GetSpellInfo(spellID) or "")..")",
        };
        bucket.trigger = SAO.Trigger:new(bucket);
        bucket.currentState = SAO.VariableState:new();

        self.__index = nil;
        setmetatable(bucket, self);
        self.__index = self;

        return bucket;
    end,

    reset = function(self)
        self.currentStacks = -1;
        self.currentActionUsable = nil;
        self.currentTalented = nil;
        self.currentHolyPower = nil;

        self.currentState:reset();

        self.trigger.informed = 0;

        self.hashCalculator:reset();

        self:applyHash();
    end,

    getOrCreateDisplay = function(self, hash)
        local created = false;

        if not self[hash.hash] then
            self[hash.hash] = SAO.Display:new(self, hash.hash);

            if hash:hasAuraStacks() then
                local stacks = hash:getAuraStacks();
                if stacks and stacks > 0 then
                    -- Having at least one positive display is enough to know the bucket cares about number of stacks
                    self.stackAgnostic = false;
                end
            end

            created = true;
        end

        return self[hash.hash], created;
    end,

    setTalentInfo = function(self, tab, index)
        self.talentTabIndex = { tab, index };
    end,

    -- Check if a specific hash is currently displayed
    -- For soft displays, it returns true even is the display is not currently on screen
    -- If hash is not set, returns tru if any display is currently shown
    isDisplayed = function(self, hash)
        if hash then
            return self.displayedHash == hash;
        else
            return self.displayedHash ~= nil;
        end
    end,

    refresh = function(self)
        if self.displayedHash == nil then
            -- Nothing to refresh if nothing is displayed
            return;
        end

        if not self.stackAgnostic and (self.currentStacks and self.currentStacks > 0) then
            local hashForAnyStacks = self.hashCalculator:toAnyAuraStacks();
            if self[hashForAnyStacks] then
                self[hashForAnyStacks]:refresh();
            end
        end
        self[self.displayedHash]:refresh();
    end,

    checkCombat = function(self, inCombat)
        if self.displayedHash then
            self[self.displayedHash]:checkCombat(inCombat);
        end
    end,

    setStacks = function(self, stacks)
        if self.currentStacks == stacks then
            return;
        end
        self.currentStacks = stacks;
        self.trigger:inform(SAO.TRIGGER_AURA);
        self.hashCalculator:setAuraStacks(stacks, self);
        self:applyHash();
    end,

    setActionUsable = function(self, usable)
        if self.currentActionUsable == usable then
            return;
        end
        self.currentActionUsable = usable;
        self.trigger:inform(SAO.TRIGGER_ACTION_USABLE);
        self.hashCalculator:setActionUsable(usable);
        self:applyHash();
    end,

    setTalented = function(self, talented)
        if self.currentTalented == talented then
            return;
        end
        self.currentTalented = talented;
        self.trigger:inform(SAO.TRIGGER_TALENT);
        self.hashCalculator:setTalented(talented);
        self:applyHash();
    end,

    setHolyPower = function(self, holyPower)
        if self.currentHolyPower == holyPower then
            return;
        end
        self.currentHolyPower = holyPower;
        self.trigger:inform(SAO.TRIGGER_HOLY_POWER);
        self.hashCalculator:setHolyPower(holyPower);
        self:applyHash();
    end,

    applyHash = function(self)
        if self.currentHash == self.hashCalculator.hash then
            return;
        end

        if SAO:HasDebug() or SAO:HasTrace(Module) then
            local describeHash = function(hash)
                local str, num = "unknown", tostring(hash);
                if type(hash) == 'number' then
                    str = SAO.Hash:new(hash):toString();
                    num = string.format("0x%X == %d", hash, hash);
                end
                return str, string.format("%s (%s)", str, num);
            end

            if self.currentHash == nil or self.currentHash == 0 then
                local shortStrHashAfter, longStrHashAfter = describeHash(self.hashCalculator.hash);
                SAO:Debug(Module, "Setting hash to "..shortStrHashAfter.." for "..self.description);
                SAO:Trace(Module, "Setting hash to "..longStrHashAfter.." for "..self.description);
            elseif self.hashCalculator.hash == 0 then
                local _, longStrHashBefore = describeHash(self.currentHash);
                SAO:Debug(Module, "Resetting hash for "..self.description);
                SAO:Trace(Module, "Resetting hash from "..longStrHashBefore.." for "..self.description);
            else
                local shortStrHashBefore, longStrHashBefore = describeHash(self.currentHash);
                local shortStrHashAfter, longStrHashAfter = describeHash(self.hashCalculator.hash);
                SAO:Debug(Module, "Changing hash from "..shortStrHashBefore.." to "..shortStrHashAfter.." for "..self.description);
                SAO:Trace(Module, "Changing hash from "..longStrHashBefore.." to "..longStrHashAfter.." for "..self.description);
            end
        end

        self.currentHash = self.hashCalculator.hash;

        if not self.trigger:isFullyInformed() then
            return;
        end

        local transitionOptions = { mimicPulse = true };
        if self.stackAgnostic then
            if self.displayedHash == nil then
                if self[self.currentHash] then
                    self[self.currentHash]:show();
                end
            else
                self[self.displayedHash]:hide();
                if self[self.currentHash] then
                    self[self.currentHash]:show(transitionOptions);
                end
            end
        else
            local hashForAnyStacks = self.hashCalculator:toAnyAuraStacks();
            if self.displayedHash == nil then -- Displayed aura was 'nil'
                if self.currentStacks == nil or self.currentStacks == 0 then
                    if self[self.currentHash] then
                        self[self.currentHash]:show();
                    end
                else
                    if self[hashForAnyStacks] then
                        self[hashForAnyStacks]:show();
                    end
                    if self[self.currentHash] then
                        self[self.currentHash]:show();
                    end
                end
            else
                local displayedStacks = SAO.Hash:new(self.displayedHash):getAuraStacks();
                if displayedStacks == nil then -- Displayed aura was 'Absent'
                    self[self.displayedHash]:hide();
                    if self[hashForAnyStacks] then
                        self[hashForAnyStacks]:show(transitionOptions);
                    end
                    if self.currentStacks > 0 and self[self.currentHash] then
                        self[self.currentHash]:show(transitionOptions);
                    end
                elseif displayedStacks == 0 then -- Displayed aura was 'Any'
                    if self.currentStacks == nil then
                        self[self.displayedHash]:hide();
                        if self[self.currentHash] then
                            self[self.currentHash]:show(transitionOptions);
                        end
                    else
                        if self[self.currentHash] then
                            self[self.currentHash]:show();
                        end
                    end
                else -- Displayed aura was N, where N > 0
                    if self.currentStacks == nil then -- Now displaying 'Absent'
                        local displayedHash = self.displayedHash; -- Must backup because it may be overwritten during hide() call
                        if self[hashForAnyStacks] then
                            self[hashForAnyStacks]:hide();
                        end
                        self[displayedHash]:hide();
                        if self[self.currentHash] then
                            self[self.currentHash]:show(transitionOptions);
                        end
                    elseif self.currentStacks == 0 then -- Now displaying 'Any'
                        self[self.displayedHash]:hide();
                        if self[self.currentHash] then
                            -- Normally, we would not need to show() 'Any' because it should be currently shown
                            -- We are in a situation where N was shown (with N > 0) and showing N included showing Any, that's why Any should be shown by now
                            -- However, due to hiding mechanics, if Any shares the same spellID as N, then Any has been hidden during the above self[N]:hide()
                            -- And unfortunately, Any should always share the same spellID as N
                            self[self.currentHash]:show(transitionOptions);
                        end
                    else -- Now displaying M, where M > 0 and M != N
                        self[self.displayedHash]:hide();
                        if self[hashForAnyStacks] then
                            -- Same comment as above: we should not need to show() 'Any' explicitly because it should be shown, but we need to show nonetheless
                            self[hashForAnyStacks]:show(transitionOptions);
                        end
                        if self[self.currentHash] then
                            self[self.currentHash]:show(transitionOptions);
                        end
                    end
                end
            end
        end
    end,
}

SAO.BucketManager = {
    addAura = function(self, aura)
        local bucket, created = self:getOrCreateBucket(aura.name, aura.spellID);

        if created and not SAO:IsFakeSpell(aura.spellID) then
            bucket.trigger:require(SAO.TRIGGER_AURA);
        end

        local displayHash = SAO.Hash:new();
        displayHash:setAuraStacks(aura.stacks);
        local display = bucket:getOrCreateDisplay(displayHash);
        if aura.overlay then
            display:addOverlay(aura.overlay);
        end
        for _, button in ipairs(aura.buttons or {}) do
            display:addButton(button);
        end
        if type(aura.combatOnly) == 'boolean' then
            display:setCombatOnly(aura.combatOnly);
        end
    end,

    addEffectOverlay = function(self, bucket, hash, overlay, combatOnly)
        local display = bucket:getOrCreateDisplay(hash);
        display:addOverlay(overlay);
        display:setCombatOnly(combatOnly);
    end,

    addEffectButton = function(self, bucket, hash, button, combatOnly)
        local display = bucket:getOrCreateDisplay(hash);
        display:addButton(button);
        display:setCombatOnly(combatOnly);
    end,

    getOrCreateBucket = function(self, name, spellID)
        local bucket = SAO.RegisteredBucketsBySpellID[spellID];
        local created = false;

        if not bucket then
            bucket = SAO.Bucket:create(name, spellID);
            SAO.RegisteredBucketsBySpellID[spellID] = bucket;
            SAO.RegisteredBucketsByName[name] = bucket;

            -- Cannot guarantee we can track spell ID on Classic Era, but can always track spell name
            if SAO.IsEra() and not SAO:IsFakeSpell(spellID) then
                local spellName = GetSpellInfo(spellID);
                if spellName then
                    SAO.RegisteredBucketsBySpellID[spellName] = bucket; -- Share pointer
                else
                    SAO:Debug(Module, "Registering aura with unknown spell "..tostring(spellID));
                end
            end

            created = true;
        end

        return bucket, created;
    end,

    checkIntegrity = function(self, bucket)
        if bucket.trigger.required == 0 then
            SAO:Warn(Module, "Effect "..bucket.description.." does not depend on any trigger");
        end

        local optionIndexes = {}
        for hash, display in pairs(bucket) do
            if type(hash) == 'number' then -- Assume number-based keys are used only by displays
                local hashCalculator = SAO.Hash:new(hash);
                local optionIndex = hashCalculator:toOptionIndex();
                local optionIndexName = hashCalculator:toString();
                if optionIndexes[optionIndex] then
                    SAO:Warn(Module, "Option conflict for "..bucket.description.." between display "..tostring(optionIndexes[optionIndex]).." and "..tostring(optionIndexName));
                else
                    optionIndexes[optionIndex] = optionIndexName;
                end
            end
        end
    end,
}

function SAO:GetBucketByName(name)
    return self.RegisteredBucketsByName[name];
end

function SAO:GetBucketBySpellID(spellID)
    return self.RegisteredBucketsBySpellID[spellID];
end

function SAO:GetBucketBySpellIDOrSpellName(spellID, fallbackSpellName)
    if not self.IsEra() or (type(spellID) == 'number' and spellID ~= 0) then
        return self.RegisteredBucketsBySpellID[spellID], spellID;
    else
        -- Due to Classic Era limitation, aura is registered by its spell name
        local bucket = self.RegisteredBucketsBySpellID[fallbackSpellName];
        if bucket then
            spellID = bucket.spellID;
        end
        return bucket, spellID;
    end
end

-- Perform a manual check on all buckets
-- If 'trigger' is set, only to buckets requiring this trigger are visited, and they check only this trigger
function SAO:CheckManuallyAllBuckets(trigger)
    if trigger then
        local buckets = self:GetBucketsByTrigger(trigger);
        for _, bucket in ipairs(buckets or {}) do
            bucket.trigger:manualCheck(trigger);
        end
    else
        for _, bucket in pairs(self.RegisteredBucketsBySpellID) do
            if bucket.trigger.required ~= 0 then
                bucket.trigger:manualCheckAll();
            end
        end
    end
end

local function dumpOneBucket(bucket, devDump)
    if devDump then
        DevTools_Dump({ [bucket.spellID] = bucket });
    else
        local describeHash = function(hash)
            local str = tostring(hash);
            if hash then
                str = string.format("%s == 0x%X == %d", SAO.Hash:new(hash):toString(), hash, hash);
            end
            return str;
        end

        local str = bucket.name..", "..
            "spellID == "..tostring(bucket.spellID)..", "..
            "currentHash == "..describeHash(bucket.currentHash)..", "..
            "displayedHash == "..describeHash(bucket.displayedHash)..", "..
            "triggerRequired == "..tostring(bucket.trigger.required)..", "..
            "triggerInformed == "..tostring(bucket.trigger.informed);
        SAO:Info(Module, str);
    end
end

function SpellActivationOverlay_DumpBuckets(spellID, devDump)
    if spellID then
        local bucket = SAO.RegisteredBucketsBySpellID[spellID];
        if bucket then
            dumpOneBucket(bucket, devDump);
            return;
        end
        SAO:Info(Module, "Bucket not found with spellID "..tostring(spellID));
        return;
    end

    local nbBuckets = 0;
    for _, _ in pairs(SAO.RegisteredBucketsBySpellID) do
        nbBuckets = nbBuckets + 1;
    end
    SAO:Info(Module, "Listing buckets ("..nbBuckets.." item"..(nbBuckets == 1 and "" or "s")..")");

    for _, bucket in pairs(SAO.RegisteredBucketsBySpellID) do
        dumpOneBucket(bucket, devDump)
    end
end
