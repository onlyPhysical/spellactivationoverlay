local AddonName, SAO = ...
local Module = "effect"

--[[
    List of registered effect objects.
    Each object can have / must have these members:

{
    name = "my_effect", -- Mandatory
    project = SAO.WRATH + SAO.CATA, -- Mandatory
    spellID = 12345, -- Mandatory; usually a buff to track, for counters this is the counter ability
    talent = 49188, -- Talent or rune or nil (for counters)
    counter = false, -- Default is false
    combatOnly = false, -- Default is false

    overlays = {{
        stacks = 0, -- Default is 0
        spellID = nil, -- Default is spellID from effect
        texture = "genericarc_05", -- Mandatory
        position = "Top", -- Mandatory
        scale = 1, -- Default is 1
        color = {255, 255, 255}, -- Default is {255, 255, 255}
        pulse = true, -- Default is true
        option = { -- Default is true
            setupStacks = 0, -- Default is number of stacks from overlay
            testStacks = 0, -- Default is nil, which defaults to setupStacks
            subText = "no stacks", -- Default is nil
            variants = nil, -- Default is nil
        },
    }}, -- Although rare, multiple overlays are possible

    buttons = {{
        project = SAO.WRATH, -- Default is project from effect
        spellID = 1111, -- Default is spellID from effect
        useName = true, -- Default is false from Era to Wrath, default is true starting from Cataclysm
        option = true, -- Default is true
    }, { -- Multiple buttons if needed
        project = SAO.CATA,
        spellID = 2222,
        useName = true,
    }},
}

]]
local allEffects = {}

local function doesUseName(useNameProp)
    if useNameProp == nil then
        return SAO.IsCata() == true;
    else
        return useNameProp == true;
    end
end

local function copyOption(option)
    if type(option) == 'table' then
        local optionCopy = {}; -- Copy table to avoid issues when re-using options between effects
        for k, v in pairs(option) do
            optionCopy[k] = v; -- Copy one depth level only
            -- optionCopy[k] = copyOption(v); -- Use this code for a full deep copy
        end
        return optionCopy;
    else
        return option;
    end
end

local function addAuraOverlay(overlays, overlayConfig, project)
    if type(overlayConfig.stacks) ~= 'nil' and (type(overlayConfig.stacks) ~= 'number' or overlayConfig.stacks < 0) then
        SAO:Error(Module, "Adding Overlay with invalid number of stacks "..tostring(overlayConfig.stacks));
    end
    if type(overlayConfig.texture) ~= 'string' then
        SAO:Error(Module, "Adding Overlay with invalid texture "..tostring(overlayConfig.texture));
    end
    if type(overlayConfig.position) ~= 'string' then
        SAO:Error(Module, "Adding Overlay with invalid position "..tostring(overlayConfig.position));
    end
    if overlayConfig.option ~= nil and type(overlayConfig.option) ~= 'boolean' and type(overlayConfig.option) ~= 'table' then
        SAO:Error(Module, "Adding Overlay with invalid option "..tostring(overlayConfig.option));
    end

    local overlay = {
        project = project or overlayConfig.project,
        stacks = overlayConfig.stacks,
        texture = overlayConfig.texture,
        position = overlayConfig.position,
        scale = overlayConfig.scale,
        color = overlayConfig.color and { overlayConfig.color[1], overlayConfig.color[2], overlayConfig.color[3] } or nil,
        pulse = overlayConfig.pulse,
        option = copyOption(overlayConfig.option),
    }

    if type(overlay.project) == 'number' and not SAO.IsProject(overlay.project) then
        return;
    end

    table.insert(overlays, overlay);
end

local function addAuraButton(buttons, buttonConfig, project)
    if type(buttonConfig) == 'table' then
        if buttonConfig.spellID ~= nil and type(buttonConfig.spellID) ~= 'number' then
            SAO:Error(Module, "Adding Button with invalid spellID "..tostring(buttonConfig.spellID));
        end
        if buttonConfig.option ~= nil and type(buttonConfig.option) ~= 'table' then
            SAO:Error(Module, "Adding Overlay with invalid option "..tostring(buttonConfig.option));
        end
    end

    local button = {};

    if type(buttonConfig) == 'number' then
        button.project = project;
        button.spellID = buttonConfig;
    elseif type(buttonConfig) == 'table' then
        button.project = project or buttonConfig.project;
        button.spellID = buttonConfig.spellID;
        button.useName = buttonConfig.useName;
        button.option = copyOption(buttonConfig.option);
    else
        SAO:Error(Module, "Adding Button with invalid value "..tostring(buttonConfig));
    end

    if type(button.project) == 'number' and not SAO.IsProject(button.project) then
        return;
    end

    table.insert(buttons, button);
end

local function importOverlays(effect, props)
    effect.overlays = {}
    if props.overlay then
        addAuraOverlay(effect.overlays, props.overlay);
    end
    for key, overlayConfig in pairs(props.overlays or {}) do
        if type(key) == 'number' and key >= SAO.ERA then
            if type(overlayConfig) == 'table' and overlayConfig[1] then
                for _, subOverlayConfig in ipairs(overlayConfig) do
                    addAuraOverlay(effect.overlays, subOverlayConfig, key);
                end
            else
                addAuraOverlay(effect.overlays, overlayConfig, key);
            end
        else
            addAuraOverlay(effect.overlays, overlayConfig);
        end
    end
end

local function importButtons(effect, props)
    effect.buttons = {}
    if props.button then
        addAuraButton(effect.buttons, props.button);
    end
    for key, buttonConfig in pairs(props.buttons or {}) do
        if type(key) == 'number' and key >= SAO.ERA then
            if type(buttonConfig) == 'table' and buttonConfig[1] then
                for _, subButtonConfig in ipairs(buttonConfig) do
                    addAuraButton(effect.buttons, subButtonConfig, key);
                end
            else
                addAuraButton(effect.buttons, buttonConfig, key);
            end
        else
            addAuraButton(effect.buttons, buttonConfig);
        end
    end
end

local function createCounter(effect, props)
    effect.counter = true;

    if type(props) == 'table' then
        effect.combatOnly = props.combatOnly;
        effect.buttons = {{
            useName = doesUseName(props.useName),
        }}
    else
        effect.buttons = {{
            useName = doesUseName(),
        }}
    end

    return effect;
end

local function createAura(effect, props)
    if type(props) == 'table' then
        effect.talent = props.talent;
        effect.combatOnly = props.combatOnly;
    else
        SAO:Error(Module, "Creating an aura for "..tostring(effect.name).." requires a 'props' table");
    end

    importOverlays(effect, props);

    importButtons(effect, props);

    return effect;
end

local function createCounterWithOverlay(effect, props)
    if type(props) ~= 'table' or (not props.overlay and not props.overlays) then
        SAO:Error(Module, "Creating a counter with overlay for "..tostring(effect.name).." requires a 'props' table that contains either 'overlay' or 'overlays' or both");
    end

    effect.talent = props.talent or effect.spellID;

    createCounter(effect, props);

    importOverlays(effect, props);

    return effect;
end

local function checkEffect(effect)
    if type(effect) ~= 'table' then
        SAO:Error(Module, "Registering invalid effect "..tostring(effect));
        return false;
    end
    if type(effect.name) ~= 'string' or effect.name == '' then
        SAO:Error(Module, "Registering effect with invalid name "..tostring(effect.name));
        return false;
    end
    if type(effect.project) ~= 'number' or bit.band(effect.project, SAO.ALL_PROJECTS) == 0 then
        SAO:Error(Module, "Registering effect "..effect.name.." with invalid project flags "..tostring(effect.project));
        return false;
    end
    if type(effect.spellID) ~= 'number' or effect.spellID <= 0 then
        SAO:Error(Module, "Registering effect "..effect.name.." with invalid spellID "..tostring(effect.spellID));
        return false;
    end
    if effect.talent and type(effect.talent) ~= 'number' then
        SAO:Error(Module, "Registering effect "..effect.name.." with invalid talent "..tostring(effect.talent));
        return false;
    end
    if effect.counter ~= true and type(effect.overlays) ~= "table" then
        SAO:Error(Module, "Registering effect "..effect.name.." with no overlays and not as counter");
        return false;
    end
    if effect.counter == true and (type(effect.buttons) ~= "table" or #effect.buttons == 0) then
        SAO:Error(Module, "Registering effect "..effect.name.." with no buttons despite being a counter");
        return false;
    end
    if effect.overlays and type(effect.overlays) ~= 'table' then
        SAO:Error(Module, "Registering effect "..effect.name.." with invalid overlay list");
        return false;
    end
    if effect.buttons and type(effect.buttons) ~= 'table' then
        SAO:Error(Module, "Registering effect "..effect.name.." with invalid button list");
        return false;
    end

    for i, overlay in ipairs(effect.overlays or {}) do
        if overlay.project and type(overlay.project) ~= 'number' then
            SAO:Error(Module, "Registering effect "..effect.name.." for overlay "..i.." with invalid project flags "..tostring(overlay.project));
            return false;
        end
        if overlay.spellID and type(overlay.spellID) ~= 'number' then
            SAO:Error(Module, "Registering effect "..effect.name.." for overlay "..i.." with invalid spellID "..tostring(overlay.spellID));
            return false;
        end
        if type(overlay.stacks) ~= 'nil' and (type(overlay.stacks) ~= 'number' or overlay.stacks < 0) then
            SAO:Error(Module, "Registering effect "..effect.name.." for overlay "..i.." with invalid number of stacks "..tostring(overlay.stacks));
            return false;
        end
        if type(overlay.texture) ~= 'string' then -- @todo check the texture even exists
            SAO:Error(Module, "Registering effect "..effect.name.." for overlay "..i.." with invalid texture name "..tostring(overlay.texture));
            return false;
        end
        if type(overlay.position) ~= 'string' then -- @todo check the position is one of the allowed values
            SAO:Error(Module, "Registering effect "..effect.name.." for overlay "..i.." with invalid position "..tostring(overlay.position));
            return false;
        end
        if overlay.scale and (type(overlay.scale) ~= 'number' or overlay.scale <= 0) then
            SAO:Error(Module, "Registering effect "..effect.name.." for overlay "..i.." with invalid scale factor "..tostring(overlay.scale));
            return false;
        end
        if overlay.color and (type(overlay.color) ~= 'table' or type(overlay.color[1]) ~= 'number' or type(overlay.color[2]) ~= 'number' or type(overlay.color[3]) ~= 'number') then
            SAO:Error(Module, "Registering effect "..effect.name.." for overlay "..i.." with invalid color");
            return false;
        end
    end

    for i, button in ipairs(effect.buttons or {}) do
        if button.project and type(button.project) ~= 'number' then
            SAO:Error(Module, "Registering effect "..effect.name.." for button "..i.." with invalid project flags "..tostring(button.project));
            return false;
        end
        if button.spellID and type(button.spellID) ~= 'number' then
            SAO:Error(Module, "Registering effect "..effect.name.." for button "..i.." with invalid spellID "..tostring(button.spellID));
            return false;
        end
    end

    return true;
end

function SAO:RegisterEffect(effect)
    if not checkEffect(effect) then
        return;
    end

    if not self.IsProject(effect.project) then
        return;
    end

    local glowIDs = nil
    if type(effect.buttons) == 'table' then
        glowIDs = {}
        for i, button in ipairs(effect.buttons) do
            if not button.project or self.IsProject(button.project) then
                local spellID = button.spellID or effect.spellID;
                local useName = doesUseName(button.useName);
                if useName then
                    local spellName = GetSpellInfo(spellID);
                    if not spellName then
                        SAO:Error(Module, "Registering effect "..effect.name.." for button "..i.." with unknown spellID "..tostring(spellID));
                        return false;
                    end
                    table.insert(glowIDs, spellName);
                else
                    table.insert(glowIDs, spellID);
                end
            end
        end
    end

    for _, overlay in ipairs(effect.overlays or {}) do
        if not overlay.project or self.IsProject(overlay.project) then
            local name = effect.name;
            local stacks = overlay.stacks or 0;
            if stacks > 0 then
                name = name.." "..stacks;
            end
            local spellID = overlay.spellID or effect.spellID;
            local texture = overlay.texture;
            local position = overlay.position;
            local scale = overlay.scale or 1;
            local r, g, b = 255, 255, 255
            if overlay.color then r, g, b = overlay.color[1], overlay.color[2], overlay.color[3] end
            local autoPulse = overlay.pulse ~= false;
            local combatOnly = overlay.combatOnly == true or effect.combatOnly == true;
            self:RegisterAura(name, stacks, spellID, texture, position, scale, r, g, b, autoPulse, glowIDs, combatOnly);
            glowIDs = nil; -- Immediately clear the glow ID list to avoid re-registering the same list on next overlay
        end
    end

    if not effect.overlays and effect.counter == true then
        self:RegisterAura(effect.name, 0, effect.spellID, nil, "", 0, 0, 0, 0, false, glowIDs);
    end

    if effect.counter == true then
        self:RegisterCounter(effect.name);
    end

    table.insert(allEffects, effect);
end

function SAO:AddEffectOptions()
    for _, effect in ipairs(allEffects) do
        local overlayTalent = effect.talent;
        local buttonTalent = (not effect.counter) and effect.talent or nil;

        for _, overlay in ipairs(effect.overlays or {}) do
            if overlay.option ~= false and (not overlay.project or self.IsProject(overlay.project)) then
                local buff = overlay.spellID or effect.spellID;
                if type(overlay.option) == 'table' then
                    local setupStacks = type(overlay.option.setupStacks) == 'number' and overlay.option.setupStacks or overlay.stacks;
                    local testStacks = type(overlay.option.testStacks) == 'number' and overlay.option.testStacks or setupStacks;
                    local subText = overlay.option.subText;
                    local variants = overlay.option.variants;
                    self:AddOverlayOption(overlayTalent, buff, setupStacks, subText, variants, testStacks);
                else
                    local setupStacks = overlay.stacks;
                    self:AddOverlayOption(overlayTalent, buff, setupStacks);
                end
            end
        end

        for _, button in ipairs(effect.buttons or {}) do
            if button.option ~= false and (not button.project or self.IsProject(button.project)) then
                local buff = effect.spellID;
                local spellID = button.spellID or effect.spellID;
                self:AddGlowingOption(buttonTalent, buff, spellID);
            end
        end
    end
end

--[[
    Create an effect based on a specific class.
    @param name Effect name, must be unique
    @param project Project flags where the effect is used e.g. SAO.WRATH+SAO.CATA
    @param class Class name e.g., "counter"
    @param props (optional) Properties to initialize the effect
    @param register (optional) Register the effect immediately after creation; default is true
]]
function SAO:CreateEffect(name, project, spellID, class, props, register)
    if type(name) ~= 'string' or name == '' then
        self:Error(Module, "Creating effect with invalid name "..tostring(name));
        return nil;
    end
    if type(project) ~= 'number' or bit.band(project, SAO.ALL_PROJECTS) == 0 then
        self:Error(Module, "Creating effect "..name.." with invalid project flags "..tostring(project));
        return nil;
    end
    if type(spellID) ~= 'number' or spellID <= 0 then
        self:Error(Module, "Creating effect "..name.." with invalid spellID "..tostring(spellID));
        return nil;
    end
    if type(class) ~= 'string' then
        self:Error(Module, "Creating effect "..name.." with invalid class "..tostring(spellID));
        return nil;
    end
    if props and type(props) ~= 'table' then
        self:Error(Module, "Creating effect "..name.." with invalid props "..tostring(props));
        return nil;
    end

    local effect = {
        name = name,
        project = project,
        spellID = spellID,
    }

    if strlower(class) == "counter" then
        createCounter(effect, props);
    elseif strlower(class) == "aura" then
        createAura(effect, props);
    elseif strlower(class) == "counter_with_overlay" then
        createCounterWithOverlay(effect, props);
    else
        self:Error(Module, "Creating effect "..name.." with unknown class "..tostring(class));
        return nil;
    end

    if register == nil or register == true then
        self:RegisterEffect(effect);
    end

    return effect;
end
