local utils = require("sidebar-nvim.utils")
local view = require("sidebar-nvim.view")
local Loclist = require("sidebar-nvim.components.loclist")
local config = require("sidebar-nvim.config")
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local loclist = Loclist:new({ omit_single_group = true })
local loclist_items = {}

local buffers_mru = {}
local current_buffer = -1

local function get_fileicon(filename)
    if has_devicons and devicons.has_loaded() then
        local extension = filename:match("^.+%.(.+)$")

        local fileicon = ""
        local icon, _ = devicons.get_icon_color(filename, extension)
        if icon then
            fileicon = icon
        end

        local highlight = "SidebarNvimNormal"

        if extension then
            --highlight = "DevIcon" .. extension
        end
        return { text = "  " .. fileicon, hl = highlight }
    else
        return { text = "  " }
    end
end

--
-- Validity
--

local function is_ignored(buffer)
    local bufname = vim.api.nvim_buf_get_name(buffer)
    local filetype = vim.api.nvim_buf_get_option(buffer, "filetype")
    local buftype = vim.api.nvim_buf_get_option(buffer, "buftype")
    local ignored = false
    for _, ignored_buffer in ipairs(config.buffers.ignored_buffer_names or {}) do
        if string.match(bufname, ignored_buffer) then
            ignored = true
            break
        end
    end
    if ignored == false then
        for _, ignored_buffer in ipairs(config.buffers.ignored_filetypes or {}) do
            if string.match(filetype, ignored_buffer) then
                ignored = true
                break
            end
        end
    end
    if ignored == false then
        for _, ignored_buffer in ipairs(config.buffers.ignored_buftype or {}) do
            if string.match(buftype, ignored_buffer) then
                ignored = true
                break
            end
        end
    end
    return ignored
end

local function is_valid_buffer(buffer)
    local is_valid = vim.api.nvim_buf_is_valid(buffer)
    if is_valid then
        local is_ignored = is_ignored(buffer)
        local is_listed = vim.fn.getbufinfo(buffer)[1].listed == 1
        local is_loaded = vim.fn.getbufinfo(buffer)[1].loaded == 1

        -- Determine if this is a scratch buffer that should be skipped
        local is_nofile = vim.fn.getbufvar(buffer, '&buftype') == 'nofile'
        local is_help = vim.fn.getbufvar(buffer, '&buftype') == 'help'
        local is_hidden = vim.fn.getbufvar(buffer, '&bufhidden') == 'hide'
        local is_noswap = vim.fn.getbufvar(buffer, '&swapfile') == 0
        local is_scratch = (is_nofile and is_hidden and is_noswap) or is_help

        local is_included = (is_listed or is_loaded) and not is_scratch
        local winnr = vim.fn.bufwinnr(buffer)
        local wininfo = vim.fn.getwininfo()
        local wintype = vim.fn.win_gettype()
        local is_normal_window = (wintype == '' or wintype == nil) and wintype ~= 'popup' and wintype ~= 'quickfix'
        local is_quickfix = false
        local is_loclist = false
        if wininfo[winnr] then
            is_quickfix = wininfo[winnr].quickfix == 1
            is_loclist = wininfo[winnr].loclist == 1
        end
        return is_ignored == false and is_included == true and is_quickfix == false and is_loclist == false and is_normal_window == true
    end
    return false
end

--
-- Drawing
--

local function first_mru_entry()
    if buffers_mru[0] ~= nil then
        return buffers_mru[0]
    else
        return buffers_mru[1]
    end
end

local function loclist_item_for_buffer(buffer)
    -- Current buffer could be invalid, e.g. QuickFix window
    if not is_valid_buffer(buffer) then
        return nil
    end

    local name_hl = "SidebarNvimBuffersNormal"
    local modified = ""

    if buffer == current_buffer then
        name_hl = "SidebarNvimBuffersActive"
    end

    if vim.api.nvim_buf_get_option(buffer, "modified") then
        name_hl =  buffer == current_buffer and "SidebarNvimBuffersActiveModified" or "SidebarNvimBuffersNormalModified"
        modified = " *"
    end

    local bufname = vim.api.nvim_buf_get_name(buffer)
    local filename = utils.filename(bufname)
    if bufname ~= "" and filename ~= nil then
        local fileicon
        if buffer == current_buffer then
            fileicon = { text = " " }
        else
            fileicon = get_fileicon(bufname)
        end

        local item = {
            group = "buffers-mru",
            left = {
                fileicon,
                { text = " " .. filename .. modified, hl = name_hl },
            },
            data = { buffer = buffer, filepath = bufname },
        }
        return item
    end

    return nil
end

local function get_buffers()
    loclist_items = {}

    local first = first_mru_entry()
    if first == nil then
        return loclist_items
    end

    -- Remaining items in reverse order
    local remaining_count = (#buffers_mru - 1)
    local midpoint = math.floor(remaining_count / 2) + 1
    local remaining_items = {}
    for index, buffer in ipairs(buffers_mru) do
        if buffer ~= first and buffer ~= view.View.bufnr then
            local item = loclist_item_for_buffer(buffer)
            if item then
                table.insert(remaining_items, item)
            end
        end
    end

    if not is_valid_buffer(first) then
        return remaining_items
    end

    -- Keep the first/selected item separate
    local first_item = loclist_item_for_buffer(first)
    if first_item == nil then
        return remaining_items
    end

    if #remaining_items <= 1 then
        table.insert(loclist_items, first_item)
        table.insert(loclist_items, remaining_items[#remaining_items])
    else
        -- Divide remaining items in half to distribute them around the current item
        for index, item in ipairs(remaining_items) do
            if index == midpoint then
                table.insert(loclist_items, first_item)
            end

            if index < midpoint then
                -- Above the current selection
                -- Reverse items so when cycling back it is in expected order
                table.insert(loclist_items, 1, item)
            else
                -- Below the current selection
                -- Insert below the current midpoint in reverse order so cycling forwards is in expected order
                -- Selecting the item after the current selection
                table.insert(loclist_items, midpoint + 1, item)
            end
        end

    end

    return loclist_items
end

local function draw_buffers(ctx)
    local loclist_items = get_buffers()
    local lines = {}
    local hl = {}
    loclist:set_items(loclist_items, { remove_groups = false })
    loclist:draw(ctx, lines, hl)

    if lines == nil or #lines == 0 then
        return "<no buffers>"
    else
        return { lines = lines, hl = hl }
    end
end

--
-- Mutation
--

local function filter (list, test)
    local result = {}

    for index, value in ipairs(list) do
        if test(value, index) then
            result[#result + 1] = value
        end
    end

    return result
end

local function remove_mru_entry(target_buffer)
    -- Remove existing entry for this buffer
    for index, buffer in ipairs(buffers_mru) do
        if buffer == target_buffer then
            table.remove(buffers_mru, index)
            break
        end
    end
end

local function remove_first_mru_entry()
    local first = first_mru_entry()
    if first then
        remove_mru_entry(first)
    end
end

local function integrity_check()
    buffers_mru = filter(buffers_mru, function (buffer)
        return is_valid_buffer(buffer)
    end)
end

--
-- Navigation
--

local function switch_to_first_mru()
    local first = first_mru_entry()
    vim.cmd("b"..first)
end

local function update_mru()
    -- Record current buffer
    local buffer = vim.api.nvim_get_current_buf()
    if not is_valid_buffer(buffer) then
        return
    end
    current_buffer = buffer

    remove_mru_entry(current_buffer)

    -- Insert at top
    table.insert(buffers_mru, 1, current_buffer)

    -- Generate and draw
    local loclist_items = get_buffers()
    loclist:set_items(loclist_items, { remove_groups = true })
end

local function initialise_buffers()
    current_buffer = vim.api.nvim_get_current_buf()
    local buffers = vim.api.nvim_list_bufs()
    buffers_mru = filter(buffers, function (buffer)
        return is_valid_buffer(buffer)
    end)

    update_mru()
end

local function hidden_mru()
 --   integrity_check()
end

local function delete_mru()
    integrity_check()

    -- Generate and draw
    local loclist_items = get_buffers()
    loclist:set_items(loclist_items, { remove_groups = true })
end

local function cycle_previous()
    remove_mru_entry(current_buffer)

    integrity_check()

    -- Insert at bottom
    local current_buffer = vim.api.nvim_get_current_buf()
    table.insert(buffers_mru, current_buffer)

    switch_to_first_mru()
end

local function cycle_next()
    -- Remove last entry
    local last = buffers_mru[#buffers_mru]
    table.remove(buffers_mru, #buffers_mru)

    integrity_check()

    -- Insert at top
    table.insert(buffers_mru, 1, last)

    switch_to_first_mru()
end

--
-- Public Interface
--

return {
    title = "Buffers",
    --icon = config["buffers"].icon,
    icon = "",
    draw = function(ctx)
        return draw_buffers(ctx)
    end,
    setup = function(_)
        vim.api.nvim_exec(
          [[
          augroup sidebar_nvim_buffer_update
              autocmd!
              autocmd BufWinEnter * lua require'sidebar-mru.buffers-mru'.update_mru()
              autocmd BufHidden * lua require'sidebar-mru.buffers-mru'.hidden_mru()
              autocmd User NvimBufferDeleted lua require'sidebar-mru.buffers-mru'.delete_mru()
          augroup END
          ]],
            false
        )

        initialise_buffers()
    end,
    delete_mru = function(_)
        delete_mru()
    end,
    hidden_mru = function(_)
        hidden_mru()
    end,
    update_mru = function(_)
        update_mru()
    end,
    cycle_next = function(_)
        cycle_next()
    end,
    cycle_previous = function(_)
        cycle_previous()
    end,
    highlights = {
        groups = {},
        links = {
            SidebarNvimBuffersActive = "SidebarNvimSectionTitle",
        },
    },
    bindings = {
        ["d"] = function(line)
            local location = loclist:get_location_at(line)

            if location == nil then
                return
            end

            local buffer = location.data.buffer
            local is_modified = vim.api.nvim_buf_get_option(buffer, "modified")

            if is_modified then
                local action = vim.fn.input(
                    'file "' .. location.data.filepath .. '" has been modified. [w]rite/[d]iscard/[c]ancel: '
                )

                if action == "w" then
                    vim.api.nvim_buf_call(buffer, function()
                        vim.cmd("silent! w")
                    end)
                    vim.api.nvim_buf_delete(buffer, { force = true })
                elseif action == "d" then
                    vim.api.nvim_buf_delete(buffer, { force = true })
                end
            else
                vim.api.nvim_buf_delete(buffer, { force = true })
            end
        end,
        ["e"] = function(line)
            local location = loclist:get_location_at(line)
            if location == nil then
                return
            end

            vim.cmd("wincmd p")
            vim.cmd("e " .. location.data.filepath)
        end,
        ["w"] = function(line)
            local location = loclist:get_location_at(line)

            if location == nil then
                return
            end

            vim.api.nvim_buf_call(location.data.buffer, function()
                vim.cmd("silent! w")
            end)
        end,
    },
}
