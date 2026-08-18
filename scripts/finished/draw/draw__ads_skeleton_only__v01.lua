-- 开镜时临时关闭非必要视觉元素，保留 HApex3.0 原生骨骼绘制样式。
-- 骨骼、小地图和屏外指示器及其必要总开关不会被修改。
-- 物品、模型和其余玩家视觉项会暂时关闭，退出开镜或卸载时恢复原值。
-- 使用 game.localplayer.is_zooming、gui.children 与 esp.elements 完成状态切换。

local VISUAL_ROOTS = {
    "visuals", "visual", "esp",
    "loot", "loots", "item", "items", "ground_loot", "groundloot",
    "model", "models", "entity_model", "entity_models", "object", "objects", "entities",
}

local PROTECTED_TOKENS = {
    "skeleton", "bones", "bone_esp", "bone esp",
    "minimap", "mini_map", "mini-map", "mini map", "radar",
    "offscreen", "off_screen", "off-screen", "off screen",
    "screen_indicator", "screen indicator",
    "骨骼", "小地图", "雷达", "屏外", "离屏",
}

local STRUCTURAL_IDS = {
    master = true,
    enable = true,
    enabled = true,
}

local SCENARIOS = { esp.INV, esp.VIS, esp.DWN, esp.ALLY }

local saved_controls = {}
local saved_esp_elements = {}
local suppression_active = false
local missing_root_reported = false

local function contains_protected_token(text)
    local normalized = string.lower(tostring(text or ""))
    for _, token in ipairs(PROTECTED_TOKENS) do
        if string.find(normalized, token, 1, true) then
            return true
        end
    end
    return false
end

local function collect_control_tree(parent_path, parent_context, visited_paths, nodes)
    for _, element in ipairs(gui.children(parent_path)) do
        local id = tostring(element:get_id())
        local path = parent_path .. "." .. id
        if not visited_paths[path] then
            visited_paths[path] = true

            local label = tostring(element:get_label() or "")
            local context = parent_context .. " " .. id .. " " .. label
            nodes[#nodes + 1] = {
                element = element,
                id = string.lower(id),
                path = path,
                parent_path = parent_path,
                protected = contains_protected_token(context),
            }

            collect_control_tree(path, context, visited_paths, nodes)
        end
    end
end

local function mark_protected_ancestors(nodes, protected_containers)
    for _, node in ipairs(nodes) do
        if node.protected then
            local path = node.parent_path
            while path ~= nil do
                protected_containers[path] = true
                path = string.match(path, "^(.*)%.[^.]+$")
            end
        end
    end
end

local function suppress_visual_controls()
    local visited_paths = {}
    local nodes = {}
    local found_root = false

    for _, root in ipairs(VISUAL_ROOTS) do
        local children = gui.children(root)
        if #children > 0 then
            found_root = true
            collect_control_tree(root, root, visited_paths, nodes)
        end
    end

    local protected_containers = {}
    mark_protected_ancestors(nodes, protected_containers)

    for _, node in ipairs(nodes) do
        if node.element:has_value() then
            local value = node.element:get()
            local required_master = STRUCTURAL_IDS[node.id] and protected_containers[node.parent_path]
            if type(value) == "boolean" and not node.protected and not required_master then
                if saved_controls[node.path] == nil then
                    saved_controls[node.path] = { element = node.element, value = value }
                end
                if value then
                    node.element:set(false)
                end
            end
        end
    end

    if not found_root and not missing_root_reported then
        missing_root_reported = true
        log.warn("未找到视觉、物品或模型菜单树；本次仅暂停非保护 ESP 元素")
    end
end

local function esp_element_is_protected(id, element)
    return contains_protected_token(tostring(id) .. " " .. tostring(element.label or ""))
end

local function suppress_esp_elements()
    for id, element in pairs(esp.elements) do
        if not esp_element_is_protected(id, element) then
            local saved = saved_esp_elements[id]
            if saved == nil then
                saved = { element = element, enabled = {} }
                saved_esp_elements[id] = saved
                for _, scenario in ipairs(SCENARIOS) do
                    saved.enabled[scenario] = element:get_enabled(scenario)
                end
            end

            for _, scenario in ipairs(SCENARIOS) do
                if element:get_enabled(scenario) then
                    element:set_enabled(false, scenario)
                end
            end
        end
    end
end

local function begin_suppression()
    saved_controls = {}
    saved_esp_elements = {}
    suppress_visual_controls()
    suppress_esp_elements()
    suppression_active = true
end

local function enforce_suppression()
    -- 热键或其他脚本可能重新打开绘制项，因此开镜期间持续压制已暂存项目。
    for _, saved in pairs(saved_controls) do
        if saved.element:get() then
            saved.element:set(false)
        end
    end

    suppress_esp_elements()
end

local function restore_suppressed_state()
    if not suppression_active then return end

    for path, saved in pairs(saved_controls) do
        local element = gui.find(path)
        if element ~= nil and element:has_value() then
            element:set(saved.value)
        end
    end

    for id, saved in pairs(saved_esp_elements) do
        local element = esp.find(id) or saved.element
        if element ~= nil then
            for _, scenario in ipairs(SCENARIOS) do
                element:set_enabled(saved.enabled[scenario], scenario)
            end
        end
    end

    saved_controls = {}
    saved_esp_elements = {}
    suppression_active = false
end

event.on("frame_update", function()
    if game.localplayer.is_zooming then
        if not suppression_active then
            begin_suppression()
        end
        enforce_suppression()
    else
        restore_suppressed_state()
    end
end)

event.on("script_unloaded", function(unload_event)
    if unload_event.script_path ~= _SCRIPT_PATH then return end
    restore_suppressed_state()
end)

log.success("ADS native-skeleton visual filter registered")
