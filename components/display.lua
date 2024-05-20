local AddonName, SAO = ...
local Module = "display"

-- Optimize frequent calls
local InCombatLockdown = InCombatLockdown

--[[
    Display object
    Has a list of overlays and buttons
    Has functions to show/hide them
]]
SAO.Display = {
    new = function(self, parent, hash) -- parent is the bucket attached to the new trigger
        local display = {
            parent = parent,

            -- Constants
            spellID = parent.spellID,
            hash = hash,
            overlays = {},
            buttons = {},
            combatOnly = false,

            -- Variables
            status = 'off', -- 'off' | 'soft' | 'hard'
            softTimer = nil,
        }

        local tempHash = SAO.Hash:new(hash);
        local hashData = {
            hashName = tempHash:toString(),
        }
        if tempHash:hasAuraStacks() then
            local stacks = tempHash:getAuraStacks();
            if stacks >= 0 then
                hashData.fallbackIndex = stacks;
            end
            if stacks ~= 0 then
                tempHash.hash = tempHash:toAnyAuraStacks();
                hashData.hashAny = tempHash:toString();
            end
        end
        display.hashData = hashData;

        self.__index = nil;
        setmetatable(display, self);
        self.__index = self;

        return display;
    end,

    addOverlay = function(self, overlay)
        if not overlay.spellID then
            SAO:Warn(Module, "Missing spellID for overlay");
        end
        if not overlay.texture then
            SAO:Warn(Module, "Missing texture for overlay");
        end
        if not overlay.position then
            SAO:Warn(Module, "Missing position for overlay");
        end

        local hashData;
        if overlay.stacks then
            -- Legacy code
            hashData = overlay.stacks;
        else
            -- Modern code
            hashData = self.hashData;
        end

        local _overlay = {
            hashData = hashData,
            spellID = overlay.spellID,
            texture = overlay.texture,
            position = overlay.position,
            scale = overlay.scale or 1,
            r = overlay.color and overlay.color[1] or 255,
            g = overlay.color and overlay.color[2] or 255,
            b = overlay.color and overlay.color[3] or 255,
            autoPulse = overlay.autoPulse ~= false, -- true by default
            combatOnly = overlay.combatOnly == true, -- false by default
        }

        if _overlay.spellID ~= self.spellID then
            SAO:Warn(Module, "Inconsistent spellID between display and overlay: "..tostring(self.spellID).." vs. "..tostring(_overlay.spellID));
        end

        tinsert(self.overlays, _overlay);
    end,

    addButton = function(self, button)
        if type(button) ~= 'number' and type(button) ~= 'string' then
            SAO:Warn(Module, "Wrong spell for button");
        end

        tinsert(self.buttons, button);
    end,

    setCombatOnly = function(self, combatOnly)
        self.combatOnly = combatOnly;
    end,

    checkCombat = function(self, inCombat)
        if not self.combatOnly then
            return;
        end

        if self.status == 'off' then
            return;
        elseif self.status == 'soft' and inCombat then
            self:setStatus('hard');
        elseif self.status == 'hard' and not inCombat then
            self:setStatus('soft');
        end
    end,

    showOverlays = function(self, options)
        for _, overlay in ipairs(self.overlays) do
            local forcePulsePlay = nil;
            if options and options.mimicPulse then
                forcePulsePlay = overlay.autoPulse;
            end
            SAO:ActivateOverlay(overlay.hashData, overlay.spellID, overlay.texture, overlay.position, overlay.scale, overlay.r, overlay.g, overlay.b, overlay.autoPulse, forcePulsePlay, nil, overlay.combatOnly);
        end
    end,

    hideOverlays = function(self)
        if #self.overlays > 0 then
            SAO:DeactivateOverlay(self.spellID);
        end
    end,

    showButtons = function(self, options)
        if #self.buttons > 0 then
            SAO:AddGlow(self.spellID, self.buttons, self.hashData.hashName);
        end
    end,

    hideButtons = function(self)
        if #self.buttons > 0 then
            SAO:RemoveGlow(self.spellID);
        end
    end,

    -- Display overlays and buttons
    -- @note unlike individual showOverlays() and showButtons(), this main show() will set the bucket's displayedHash
    -- It also sets the display status to 'soft' or 'hard'
    -- Because of that, setStatus() must *not* show overlays and buttons by calling show()
    show = function(self, options)
        SAO:Debug(Module, "Showing hash "..self.hash.." of "..self.parent.description);
        self.parent.displayedHash = self.hash;
        if not self.combatOnly or InCombatLockdown() then
            self:setStatus('hard');
        else
            self:setStatus('soft');
        end
    end,

    -- Hide overlays and buttons
    -- @note unlike individual hideOverlays() and hideButtons(), this main hide() will unset the bucket's displayedHash
    -- It also sets the display status to 'off'
    -- Because of that, setStatus() must *not* hide overlays and buttons by calling hide()
    hide = function(self)
        SAO:Debug(Module, "Hiding hash "..self.hash.." of "..self.parent.description);
        self.parent.displayedHash = nil;
        self:setStatus('off');
    end,

    refresh = function(self)
        SAO:Debug(Module, "Refreshing aura of "..self.spellID.." "..(GetSpellInfo(self.spellID) or ""));
        SAO:RefreshOverlayTimer(self.spellID);
    end,

    --[[
        The status can be one of the following:
        - Off
        - Hard = active, no questions asked
        - Soft = active internally, but visually softened (e.g. can be hidden temporarily to remove visual clutter)
    ]]
    setStatus = function(self, status, options)
        local oldStatus, newStatus = self.status, status;
        if oldStatus == newStatus then
            return;
        end

        local statusChanged = false;
        if oldStatus == 'off' and newStatus == 'hard' then
            self:showOverlays(options);
            self:showButtons(options);
            self.status = newStatus;
            statusChanged = true;
        elseif oldStatus == 'hard' and newStatus == 'off' then
            self:hideOverlays(options);
            self:hideButtons(options);
            self.status = newStatus;
            statusChanged = true;
        elseif oldStatus == 'off' and newStatus == 'soft' then
            self:showOverlays(options);
            self:showButtons(options);
            local TimetoLingerForSoft = 7.5; -- Buttons glows temporarily for 7.5 secs
            -- The time is longer from Off to Soft than from Hard to Soft, because starting
            -- a spell alert out-of-combat combat incurs a 5-second highlight before fading out
            self.softTimer = C_Timer.NewTimer(
                TimetoLingerForSoft,
                function() self:hideButtons() end
            );
            self.status = newStatus;
            statusChanged = true;
        elseif oldStatus == 'soft' and newStatus == 'off' then
            self.softTimer:Cancel();
            self:hideOverlays(options);
            self:hideButtons(options);
            self.status = newStatus;
            statusChanged = true;
        elseif oldStatus == 'soft' and newStatus == 'hard' then
            self.softTimer:Cancel();
            -- self:showOverlays(options); -- No need to activate, it is already active, even if hidden
            self:showButtons(options); -- Re-glow in case the glow was removed after soft timer ended
            self.status = newStatus;
            statusChanged = true;
        elseif oldStatus == 'hard' and newStatus == 'soft' then
            -- self:showOverlays(options); -- No need to activate, it is already active
            -- self:showButtons(options); -- No need to glow, it is already glowing
            local TimetoLingerForSoft = 2.5; -- Buttons glows temporarily for 2.5 secs
            self.softTimer = C_Timer.NewTimer(
                TimetoLingerForSoft,
                function() self:hideButtons() end
            );
            self.status = newStatus;
            statusChanged = true;
        end
        if statusChanged then -- Do not compare (oldStatus ~= newStatus) because it does not tell if something was done
            SAO:Debug(Module, "Display status of "..self.parent.description.." for hash "..self.hash.." changed from '"..oldStatus.."' to '"..newStatus.."'");
        end
    end,
}
