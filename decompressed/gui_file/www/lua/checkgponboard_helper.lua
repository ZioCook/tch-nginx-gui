local M = {}
local cached_is_gpon_board

function M.isGPONBoard()
    if cached_is_gpon_board == nil then
        local result = false
        local f = io.open("/proc/rip/011b", "rb")
        if f then
            local byte_str = f:read(1)
            f:close()
            if byte_str then
                local val = string.byte(byte_str)
                if val == 1 or val == 2 then
                    result = true
                end
            end
        end
        cached_is_gpon_board = result
    end
    return cached_is_gpon_board
end

return M
