-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 功能：开镜时隐藏 ADS 视野锥内敌人的名称、段位和等级，并独立绘制骨骼线。
-- 分类：esp
-- 使用 API：gui、esp、game、math、event、draw、log。
-- 时序：文字 ESP 按玩家回调；draw.* 在 frame_update 中逐帧调用。
-- 验证：已按官方 API 对照并配套 mock 回归测试；仍需 HApex3.0 实机确认视觉效果。

-- ----------------------------------------------------------------------------
-- 1. GUI / 配置
--    保留控件引用，回调中直接读取最新菜单值，避免额外的状态同步。
-- ----------------------------------------------------------------------------
local tab = gui.tab("ESPDeclutter")

-- 主要的文字减负控件
local g_cfg = tab:group("g_cfg", "ADS FOV Declutter Settings", 0, 0, 360, 0)

local opt_enable_declutter = g_cfg:checkbox(
    "enable_declutter",
    "Hide Info Inside ADS FOV",
    true
):set_hint(
    "# ADS FOV Declutter\n"
 .. "> Suppresses Name / Rank / Level for enemies inside\n"
 .. "  your current ADS FOV cone (where you are focused).\n"
 .. "* Skeleton, chams, and outlines are NOT affected.\n"
 .. "* Has no effect when you are NOT in ADS."
)

-- 1.0 表示使用武器 ADS FOV 的原始半角；1.5 表示将隐藏锥扩大 50%。
local opt_fov_scale = g_cfg:slider_float(
    "fov_scale",
    "ADS FOV Tolerance Scale",
    0.5, 2.0, 1.0
):set_format("%.2fx"):set_hint(
    "Multiplier for the weapon's ADS FOV half-angle.\n"
 .. "1.0 = exact cone. 1.5 = 50% wider. 0.5 = tighter."
)

-- 三种文字信息分别控制，避免用户只能整体开关。
local opt_hide_name  = g_cfg:checkbox("hide_name",  "Suppress Name",  true)
local opt_hide_rank  = g_cfg:checkbox("hide_rank",  "Suppress Rank",  true)
local opt_hide_level = g_cfg:checkbox("hide_level", "Suppress Level", true)

-- 骨骼是空间定位信息，因此单独配置且不受 ADS 锥判断影响。
local g_skel = tab:group("g_skel", "Custom Skeleton Renderer", 0, 0, 360, 0)

local opt_draw_skeleton = g_skel:checkbox(
    "draw_skeleton",
    "Render Skeleton Lines",
    true
):set_hint(
    "Draws skeleton for all on-screen enemies regardless of\n"
 .. "ADS FOV state. Skeleton is a spatial indicator, not text."
)

local opt_skel_color = g_skel:color_edit("skel_color", "Skeleton Color", 1.0, 1.0, 1.0, 0.8)

-- ----------------------------------------------------------------------------
-- 2. ADS FOV 计算
--    HApex 没有直接返回“目标是否在 ADS 锥内”的接口，因此使用当前帧的
--    本地玩家状态、武器 ADS FOV、摄像机位置和目标位置计算角度误差。
-- ----------------------------------------------------------------------------

--- 判断目标实体是否位于本地玩家的 ADS 视野锥内。
--- 返回 true 表示位于锥内，调用方应隐藏当前文字元素；返回 false 表示不隐藏。
--- 数据缺失、非 ADS、目标无效或投影失败时均返回 false，以保留文字信息。
---
--- @param lp         table        game.localplayer 当前帧只读快照
--- @param p          PlayerEntity game.entities.players 中的敌方实体
--- @param fov_scale  number       用户设置的视野锥倍率
--- @return boolean
local function is_entity_in_ads_fov(lp, p, fov_scale)
    -- 本地玩家无效或死亡时不进行隐藏，避免状态不完整造成误隐藏。
    if not lp or lp.is_dead then return false end

    -- 双机环境不能读取玩家侧 OS 按键，使用 game.localplayer.is_zooming。
    if not lp.is_zooming then return false end

    -- 目标无效或死亡时不进行隐藏。
    if not p or p.is_dead then return false end

    -- head_pos 仅在屏幕上时由后端解析；不可用时用原点加近似头高。
    local target_pos = p.head_pos
    if not target_pos
       or (target_pos.x == 0 and target_pos.y == 0 and target_pos.z == 0)
    then
        if not p.origin then return false end
        target_pos = math.Vec3(p.origin.x, p.origin.y, p.origin.z + 45.0)
    end

    -- 投影失败表示当前无法可靠判断目标的屏幕方向，不主动隐藏文字。
    local _, _, ok = math.WorldToScreen(target_pos)
    if not ok then return false end

    -- 武器切换或未装备时可能暂时没有有效的 ADS FOV。
    local ads_fov = lp.target_zoom_fov
    if not ads_fov or ads_fov <= 0.0 then return false end

    local half_fov = (ads_fov * 0.5) * (fov_scale or 1.0)

    -- camera_origin 是摄像机位置；正常存活时 origin 作为后备值。
    local cam_pos = lp.camera_origin or lp.origin
    if not cam_pos then return false end

    if not lp.view_angle then return false end

    local aim_pitch, aim_yaw = math.CalcAngle(cam_pos, target_pos)

    -- 归一化可正确处理水平角跨越 -180/180 的情况。
    local delta_pitch = math.AngleNormalize(aim_pitch - lp.view_angle.x)
    local delta_yaw   = math.AngleNormalize(aim_yaw   - lp.view_angle.y)

    -- 在 pitch/yaw 角度平面中计算目标与视线的近似欧氏距离。
    local angular_dist = math.sqrt(
        (delta_pitch * delta_pitch) + (delta_yaw * delta_yaw)
    )

    -- 使用 <=，让正好位于边界上的目标也属于隐藏范围。
    return angular_dist <= half_fov
end

-- ----------------------------------------------------------------------------
-- 3. ESP 文字元素：名称、段位、等级
--    esp.add 的 text 回调返回字符串时绘制，返回 nil 时隐藏该玩家的该元素。
-- ----------------------------------------------------------------------------

-- 名称
esp.add("declutter_name", function(p, ctx)
    if not p or p.is_dead or p.is_teammate then return nil end

    if opt_enable_declutter:get() and opt_hide_name:get() then
        local lp = game.localplayer
        if is_entity_in_ads_fov(lp, p, opt_fov_scale:get()) then
            return nil
        end
    end

    local name = p.name
    if not name or name == "" then return nil end

    return name
end, {
    label  = "Player Name",
    kind   = "text",
    colors = {
        { 0.90, 0.90, 0.90, 1.0 },
        { 1.00, 0.30, 0.30, 1.0 },
        { 1.00, 0.75, 0.20, 1.0 },
        { 0.30, 0.85, 1.00, 1.0 },
    },
    dist   = { 5.0, 300.0 },
})

-- 段位
esp.add("declutter_rank", function(p, ctx)
    if not p or p.is_dead or p.is_teammate then return nil end

    if opt_enable_declutter:get() and opt_hide_rank:get() then
        local lp = game.localplayer
        if is_entity_in_ads_fov(lp, p, opt_fov_scale:get()) then
            return nil
        end
    end

    -- rank 在不同数据阶段可能是整数或字符串，统一转为字符串。
    local rank_val = p.rank
    if not rank_val then return nil end
    local rank_str = tostring(rank_val)
    if rank_str == "" or rank_str == "0" then return nil end

    return rank_str
end, {
    label  = "Player Rank",
    kind   = "text",
    colors = {
        { 0.80, 0.80, 0.80, 1.0 },
        { 1.00, 0.85, 0.30, 1.0 },
        { 1.00, 0.60, 0.20, 1.0 },
        { 0.40, 0.80, 1.00, 1.0 },
    },
    dist   = { 5.0, 250.0 },
})

-- 等级
esp.add("declutter_level", function(p, ctx)
    if not p or p.is_dead or p.is_teammate then return nil end

    if opt_enable_declutter:get() and opt_hide_level:get() then
        local lp = game.localplayer
        if is_entity_in_ads_fov(lp, p, opt_fov_scale:get()) then
            return nil
        end
    end

    local xp = p.xp
    if not xp or xp <= 0 then return nil end

    return string.format("Lv.%d", xp)
end, {
    label  = "Player Level (XP)",
    kind   = "text",
    colors = {
        { 0.70, 0.70, 0.70, 1.0 },
        { 0.40, 1.00, 0.40, 1.0 },
        { 1.00, 0.50, 0.20, 1.0 },
        { 0.30, 0.80, 1.00, 1.0 },
    },
    dist   = { 5.0, 200.0 },
})

-- ----------------------------------------------------------------------------
-- 4. 自定义骨骼绘制
--    骨骼只作为空间定位提示，不按 ADS 视野锥隐藏。
-- ----------------------------------------------------------------------------
local BONE_LINKS = game.BONE_LINKS

event.on("frame_update", function(e)
    if not opt_draw_skeleton:get() then return end

    local players = game.entities.players
    if not players then return end

    local ct = opt_skel_color:get()
    local skel_packed_col = draw.rgba(
        ct and ct[1] or 1.0,
        ct and ct[2] or 1.0,
        ct and ct[3] or 1.0,
        ct and ct[4] or 0.8
    )

    -- game.entities.players 是 userdata-backed table，必须使用 pairs 遍历。
    for _, p in pairs(players) do
        if not p.is_teammate
           and not p.is_dead
           and p.is_visible
           and p:has_fresh_bones()
        then
            for _, link in ipairs(BONE_LINKS) do
                local bone_a = p:bone(link[1])
                local bone_b = p:bone(link[2])

                local ax, ay, ok1 = math.WorldToScreen(bone_a)
                local bx, by, ok2 = math.WorldToScreen(bone_b)

                if ok1 and ok2 then
                    draw.line(ax, ay, bx, by, skel_packed_col, { thickness = 1.5 })
                end
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- 5. 加载确认
-- ----------------------------------------------------------------------------
log.success(
    "esp_ads_declutter.lua loaded — "
 .. "Tab: ESPDeclutter | Elements: declutter_name, declutter_rank, declutter_level"
)
