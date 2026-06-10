-- 将 200 等级以下的敌人信息统一显示为黄色，便于快速识别低等级目标。
-- 使用 game 玩家快照读取敌人等级、距离、血量和护盾，使用 esp.add 注册独立 ESP 信息。
-- 脚本只绘制文字和状态条，不接管骨骼或方框，避免覆盖用户现有骨骼/方框样式。
-- 如果当前 HApex3.0 构建没有暴露等级字段，目标会被安全跳过，避免误标记。

local LEVEL_LIMIT = 200
local LOW_LEVEL_COLOR = draw.u8(235, 235, 0, 255)
local LOW_LEVEL_PALETTE = {
    { 235 / 255, 235 / 255, 0.0, 1.0 },
    { 235 / 255, 235 / 255, 0.0, 1.0 },
    { 235 / 255, 235 / 255, 0.0, 1.0 },
    { 235 / 255, 235 / 255, 0.0, 1.0 },
}

local function first_number(...)
    for _, value in ipairs({ ... }) do
        if type(value) == "number" then
            return value
        end
    end
    return nil
end

local function get_player_level(player)
    -- 不同构建可能使用不同字段名；按常见命名逐个兼容，缺失字段会返回 nil。
    return first_number(
        player.level,
        player.account_level,
        player.player_level,
        player.accountLevel,
        player.playerLevel
    )
end

local function get_health_ratio(player)
    local health = player.health or 0
    local shield = player.shield or 0
    local max_shield = player.max_shield or 0
    local max_total = 100 + max_shield

    if max_total <= 0 then
        return 0
    end

    local ratio = (health + shield) / max_total
    if ratio < 0 then return 0 end
    if ratio > 1 then return 1 end
    return ratio
end

esp.add("low_level_enemy_yellow_info", function(player, ctx)
    if player.is_teammate or player.is_dead then
        return nil
    end

    local level = get_player_level(player)
    if not level or level >= LEVEL_LIMIT then
        return nil
    end

    local distance = ctx.distance or player.distance or 0
    local name = player.name or "enemy"

    return {
        text = string.format("Lv.%d  %s  %.0fm", level, name, distance),
        text_color = LOW_LEVEL_COLOR,
        bar = get_health_ratio(player),
        bar_color = LOW_LEVEL_COLOR,
    }
end, {
    label = "<200 Enemy Yellow Info",
    kind = "mixed",
    colors = LOW_LEVEL_PALETTE,
    dist = { 0.0, 500.0 },
})

log.success("Low-level enemy yellow info ESP loaded")
