local M = {}
local cached_is_gpon_board

function M.isGPONBoard()
    if cached_is_gpon_board == nil then
        local f = io.open("/proc/rip/011b", "rb")
        if f then
            local byte_str = f:read(1)
            f:close()
            if byte_str then
                local val = string.byte(byte_str)
                cached_is_gpon_board = (val == 1 or val == 2)
            end
        end
    end
    return cached_is_gpon_board or false
end

return M
