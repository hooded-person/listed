local cc_expect = require "cc.expect"
local expect = cc_expect.expect
local field = cc_expect.field

---@class listedColumnPattern
---@field type type|type[] Type(s) of the column
---@field header string? Header of the column
---@field width integer? Width of the column when rendered, if nil it is auto-generated
---@field sorting? fun(a:any,b:any):boolean Sorting function used when sorting by this column

---@class listedColumnPatternUnified
---@field type type[]
---@field header string?
---@field width integer?

---Validates column patterns
---@param ... type|listedColumnPattern One or more column patterns
---@return listedColumnPatternUnified[]? columns The validated and unified column patterns
---@return string? err Error if a column pattern failed validation
local function validateColumnPattern(...)
    local patterns = {}
    for i = 1, select("#", ...) do
        local pattern = select(i, ...)

        -- "string" -> { type = "string"}
        if type(pattern) == "string" then
            ---@type listedColumnPatternUnified
            pattern = { type = { pattern } }
        end

        -- pattern.type
        local columnType = pattern
            .type -- for some reason if i use `pattern.type` directly lsp doesnt understand that its type is string
        if type(columnType) == "string" then
            pattern.type = { columnType }
        elseif type(columnType) ~= "table" then
            return nil, ("bad pattern #%d type (string or table expected, got %s)"):format(i, type(columnType))
        end

        -- pattern.header
        if pattern.header and type(pattern.header) ~= "string" then
            return nil, ("bad pattern #%d header (string expected, got %s)"):format(i, type(pattern.header))
        end

        -- pattern.width
        if pattern.width and type(pattern.width) ~= "number" then
            return nil, ("bad pattern #%d width (integer number expected, got %s)"):format(i, type(pattern.width))
        end
        if pattern.width and pattern.width % 1 ~= 0 then
            return nil, ("bad pattern #%d width (number is not an integer)"):format(i, type(pattern.width))
        end

        table.insert(patterns, pattern)
    end

    return patterns
end

---Validate a row according to a column pattern
---@param row table The row to validate
---@param columnPatterns listedColumnPattern[] The column patterns to validate with
---@return boolean ok Wether the validation was successfull
---@return string? err Error message if validation failed
local function validateRow(row, columnPatterns)
    if type(row) ~= "table" then
        return false, ("Row must be a table, not a %s"):format(type(row))
    end
    expect(2, columnPatterns, "table")
    local columns, valErr = validateColumnPattern(table.unpack(columnPatterns))
    if not columns then
        error("Invalid column pattern: " .. valErr, 2)
    end

    if #row ~= #columns then
        return false, ("Expected %d columns, got %d columns"):format(#columns, #row)
    end
    for i = 1, #row do
        local column = row[i]
        local pattern = columns[i]

        local ok, err = pcall(function() expect(i, column, table.unpack(pattern.type)) end)
        if not ok and err then
            return false, err:gsub("argument", "column")
        end
    end
    return true
end

---Calculates dynamic widths, very basic and stuff.
---@param totalWidth integer Total width available
---@param rows any[][]
---@param columns listedColumnPatternUnified[]
---@param gapSize integer Width of gaps between columns
---@return integer[]? widths Table of column width, or nil in case of failure
---@return string? err Reason of failure
local function calculateWidths(totalWidth, rows, columns, gapSize)
    gapSize = gapSize or 1
    local totalGapSize = (#columns - 1) * gapSize

    ---@type integer[]
    local fixed = {}
    local fixedSum = 0
    for i, column in ipairs(columns) do
        if column.width then
            fixed[i] = column.width
            fixedSum = fixedSum + column.width
        end
    end
    if fixedSum + totalGapSize > totalWidth then
        return nil, "sum of fixed width columns + gapsize for all columns exeeds available width"
    end

    ---@type integer[]
    local maxWidths = {}
    for _, row in ipairs(rows) do
        for columnI, v in ipairs(row) do
            local width = #tostring(v)
            if not maxWidths[columnI] or width > maxWidths[columnI] then
                maxWidths[columnI] = width
            end
        end
    end

    local totalMaxWidth = 0
    for i, maxWidth in ipairs(maxWidths) do
        if fixed[i] == nil then
            totalMaxWidth = totalMaxWidth + maxWidth
        end
    end

    ---@type integer[]
    local computedWidths = {}
    local remainingWidth = totalWidth - totalGapSize - fixedSum -- Remaining for dynamic columns

    local assignedWidth = 0
    local remainders = {}
    for i, maxWidth in ipairs(maxWidths) do
        if fixed[i] ~= nil then
            computedWidths[i] = fixed[i]
        else
            local weight = maxWidth / totalMaxWidth
            local width = math.floor(weight * remainingWidth)
            local exactWidth = (maxWidth / totalMaxWidth) * remainingWidth
            local width = math.floor(exactWidth)

            computedWidths[i] = width
            assignedWidth = assignedWidth + width

            table.insert(remainders, {
                index = i,
                remainder = exactWidth - width,
            })
        end
    end

    local leftover = remainingWidth - assignedWidth

    table.sort(remainders, function(a, b)
        return a.remainder > b.remainder
    end)

    for i = 1, leftover do
        computedWidths[remainders[i].index] =
            computedWidths[remainders[i].index] + 1
    end

    return computedWidths
end

---Stringify and cutoff `value` if its longer than `width`. Trunctuates with `cutoff_str`.
---@param value any Value to stringify and trunctuate
---@param width integer Max width of the returned string
---@param cutoff_str string String to append after cutoff entries
---@return string result Trunctuated string
local function cutoff(value, width, cutoff_str)
    value = tostring(value)
    cutoff_str = cutoff_str or "..."
    if #value <= width then
        return value
    else
        return value:sub(1, width - #cutoff_str) .. cutoff_str
    end
end

---@class listedList
---@field win table The window this list is displayed to
---@field columns listedColumnPatternUnified Number of columns in the list
---@field config listedConfig Configuration for the list display
---@field rows table[] Rows in this list. Do not modify, use :set, :add, :addMany
---@field c table<string, integer> Maps column header name to column index
local listed = {}

---@type metatable
local listed_meta = {
    ---@param table listedList
    ---@param key any
    ---@return unknown
    __index = function(table, key)
        if type(key) == "number" then
            return table.rows[key]
        else
            return listed[key]
        end
    end,
    ---@param table listedList
    ---@param key any
    ---@param value any
    __newindex = function(table, key, value)
        if type(key) ~= "number" then
            rawset(table, key, value)
        else
            if key > #table.rows + 1 or key < 1 then
                error(
                    ("List rows must be sequential, can not insert at #%d in list of length %d"):format(key, #table.rows),
                    2)
            end

            local ok, err = validateRow(value, table.columns)
            if not ok then
                error(err, 2)
            end

            table.rows[key] = value
        end
    end,
    ---@param table listedList
    ---@return integer
    __len = function(table)
        return #table.rows
    end
}

---@class listedConfig
---@field columns listedColumnPattern[] The columns of the list
---@field gapSize number? Size of the gap between columns. default:0
---@field pretty boolean? Use different text color based on value type
---@field backgroundColors integer[]? List of background colors that are alternated between per row. default:{colors.lightGray,colors.gray}
---@field style listedConfigStyle? List style

---@class listedConfigStyle
---@field headerFg integer? Header text color. default:colors.white
---@field headerBg integer? Header background color. default:colors.gray
---@field rowFg integer|integer[]? Row text colors. List of colors to alternate between. default:{colors.white}
---@field rowBg integer|integer[]? Row background colors. List of colors to alternate between. default:{colors.black, colors.gray}

---Create a new list
---@param win table A `window.create` instance
---@param config listedConfig A table with the config for the list
---@return listedList
local function create(win, config)
    expect(1, win, "table")
    expect(2, config.columns, "table")
    local columns, err = validateColumnPattern(table.unpack(config.columns))
    if not columns or err then
        error(err, 2)
    end
    expect(3, config, "table", "nil")
    config = config or {}
    field(config, "gapSize", "number", "nil")
    config.gapSize = config.gapSize or 0
    field(config, "pretty", "boolean", "nil")
    config.pretty = config.pretty or false

    field(config, "style", "table", "nil")
    config.style = config.style or {}

    field(config.style, "headerFg", "number", "nil")
    config.style.headerFg = config.style.headerFg or colors.white
    field(config.style, "headerBg", "number", "nil")
    config.style.headerBg = config.style.headerBg or colors.lightGray

    field(config.style, "rowFg", "number", "table", "nil")
    if type(config.style.rowFg) == "number" then config.style.rowFg = { config.style.rowFg } end ---@diagnostic disable-line: assign-type-mismatch
    config.style.rowFg = config.style.rowFg or { colors.white }
    field(config.style, "rowBg", "number", "table", "nil")
    if type(config.style.rowBg) == "number" then config.style.rowBg = { config.style.rowBg } end ---@diagnostic disable-line: assign-type-mismatch
    config.style.rowBg = config.style.rowBg or { colors.black, colors.gray }

    local t            = setmetatable({}, listed_meta)
    t.win              = win
    t.columns          = config.columns
    t.config           = config
    t.rows             = {}
    t.c                = {}

    for i, column in ipairs(t.columns) do
        t.c[column.header:gsub(" ", "")] = i
    end

    win.setVisible(false)

    return t
end

--#region(collapsed) List modification
function listed:set(...)
    local rows = {}
    for i = 1, select("#", ...) do
        local row = select(i, ...)

        local ok, err = validateRow(row, self.columns)
        if not ok then
            error(err, 2)
        end

        table.insert(rows, row)
    end
    self.rows = rows
end

---Add a row of data to the list
---@param ... any Either a table containing a row or a each collumn seperate
function listed:add(...)
    local columns = { ... }
    if #columns == 0 then
        error("Expected column data", 2)
    end
    if #columns == 1 and type(columns[1]) == "table" then
        columns = columns[1]
    end

    -- type validation for seperate columns
    local ok, err = validateRow(columns, self.columns)
    if not ok then
        error(err, 2)
    end

    table.insert(self.rows, columns)
end

---Add multiple rows of data to the list
---@param ... table Tables containing seperate rows
function listed:addMany(...)
    local args = { ... }
    for i = 1, #args do
        local ok, err = pcall(function() self:add(args[i]) end)
        if not ok and err then
            error(err:gsub("#", ("#%d."):format(i)), 2)
        end
    end
end

--#endregion

function listed:sort(by, desc)
    expect(1, by, "number")
    assert(by > 0, "bad argument #1, must be above 0")
    assert(by <= #self.columns, ("bad argument #1, must be below %d (column count)"):format(#self.columns))
    expect(2, desc, "boolean", "nil")

    local sortFunc = self.columns[by].sorting or function(a, b)
        if type(a) == "boolean" then
            return a and not b
        end
        return a < b
    end

    table.sort(self.rows, function(a, b)
        if desc then
            return sortFunc(b[by], a[by])
        else
            return sortFunc(a[by], b[by])
        end
    end)
end

---Display the list and gather input for it
function listed:display(offset, sortBy, sortDesc, scrollbar, scrollmode)
    expect(1, offset, "number", "nil")
    offset = offset or 0
    if type(offset) ~= "number" or offset < 0 then
        term.setCursorPos(1, 1)
        error(("The offset must be a postitive integer, not %d"):format(offset), 2)
    end
    expect(2, sortBy, "number", "nil")
    expect(3, sortDesc, "boolean", "nil")
    if sortDesc ~= nil and sortBy == nil then
        error("Bad arguments, #2 required when #3 supplied", 2)
    end
    if sortBy ~= nil and sortBy > 0 then
        self:sort(sortBy, sortDesc)
    end
    if not scrollmode then
        scrollmode = "onlyLast"
    end
    assert(scrollmode == "revealLast" or scrollmode == "onlyLast",
        "scrollmode must be either 'onlyLast' or 'revealLast'")


    self.win.setVisible(false)
    local w, h = self.win.getSize()
    if scrollbar == true then w = w - 1 end
    local widths, err = calculateWidths(w, self.rows, self.columns, self.config.gapSize)
    if not widths then
        error("Failed to calculate widths, sorry: " .. err)
    end

    local oldTerm = term.current()
    term.redirect(self.win)
    local oldTextColor = term.getTextColor()
    local oldBackgroundColor = term.getBackgroundColor()

    term.setBackgroundColor(self.config.style.rowBg[1])
    term.clear()

    term.setCursorPos(1, 1)
    term.setTextColor(self.config.style.headerFg)
    term.setBackgroundColor(self.config.style.headerBg)
    term.clearLine()

    local accX = 1
    local accXAt = {}
    for i, column in ipairs(self.columns) do
        accXAt[i] = accX
        term.setCursorPos(accX, 1)
        local headerStr = column.header
        if i == sortBy then
            headerStr = (sortDesc and "\x1F" or "\x1E") .. headerStr
        end
        if #headerStr < widths[i] then
            headerStr = headerStr .. (" "):rep(widths[i] - #headerStr)
        end
        term.write(cutoff(headerStr, widths[i], self.config.cutoff))
        accX = accX + widths[i] + self.config.gapSize
    end
    -- error(#self.rows, h - 1 + offset)
    for rowI = 1 + offset, math.min(#self.rows, h - 1 + offset) do
        local row = self.rows[rowI]
        local rowY = rowI + 1 - offset
        term.setCursorPos(1, rowY)

        local fgColor = self.config.style.rowFg[((rowI - 1) % #self.config.style.rowFg) + 1]
        term.setBackgroundColor(fgColor)
        local bgColor = self.config.style.rowBg[((rowI - 1) % #self.config.style.rowBg) + 1]
        term.setBackgroundColor(bgColor)
        term.clearLine()
        for columnI, value in ipairs(row) do
            term.setCursorPos(accXAt[columnI], rowY)
            local value_str = cutoff(value, widths[columnI], self.config.cutoff)
            if self.config.pretty then
                value_str = cutoff(value, widths[columnI], self.config.cutoff)
                if type(value) == "string" then
                    term.setTextColor(colors.red)
                elseif type(value) == "number" then
                    term.setTextColor(colors.magenta)
                elseif type(value) == "boolean" and value then
                    term.setTextColor(colors.lime)
                elseif type(value) == "boolean" and not value then
                    term.setTextColor(colors.red)
                elseif type(value) == "table" then
                    term.setTextColor(colors.gray)
                end
            end
            term.write(value_str)
        end
    end

    -- scrollbar
    local scrollHeight
    if scrollbar then
        local maxOffset = #self.rows - 1
        if scrollmode == "revealLast" then
            maxOffset = maxOffset - h + 2
            if maxOffset < 0 then maxOffset = 0 end
        end

        local barHeight = math.floor(h * h / #self.rows)
        scrollHeight = h - barHeight - 3
        local barPos = scrollHeight * (offset / (maxOffset - 1))
        for y = 2, h do
            term.setCursorPos(w + 1, y)
            term.setTextColor(colors.gray)
            term.setBackgroundColor(colors.lightGray)
            if y > 2 + barPos and y - 2 < barPos + barHeight and y < h then
                term.setBackgroundColor(colors.gray)
            end
            if y == 2 then
                term.write("\x1E")
            elseif y == h then
                term.write("\x1F")
            else
                term.write(" ")
            end
        end
    end

    term.setTextColor(oldTextColor)
    term.setBackgroundColor(oldBackgroundColor)

    term.redirect(oldTerm)

    self.win.setVisible(true)

    return widths, scrollHeight
end

---@class listedRunOptions
---@field sortBy? integer Column to sort by, can be gotten from list.c.ColumnHeader
---@field sortDesc? boolean Sort descending instead of ascending
---@field lockSorting? boolean Prevent changing sort column and sort direction
---@field scrollbar? boolean Show a scrollbar
---@field scrollmode? "onlyLast"|"revealLast" Scrollmode for scrolling. "onlyLast" will allow scrolling until only the last item is visible. "revealLast" will allow scrolling until the last item is on the bottom line. default:"onlyLast"

---Run the interactive list display
---@param offset integer
---@param options listedRunOptions
function listed:run(offset, options)
    local sortBy, sortDesc, scrollbar = options.sortBy, options.sortDesc, options.scrollbar
    field(options, "scrollmode", "string", "nil")
    if not options.scrollmode then
        options.scrollmode = "onlyLast"
    end
    assert(options.scrollmode == "revealLast" or options.scrollmode == "onlyLast",
        "scrollmode must be either 'onlyLast' or 'revealLast'")
    field(options, "lockSorting", "boolean", "nil")
    if options.lockSorting == nil then
        options.lockSorting = false
    end

    local mouse_dragging_scrolbar = nil
    while true do
        local columnWidths, scrollHeight = self:display(offset, sortBy, sortDesc, scrollbar, options.scrollmode)
        local data = { os.pullEvent() }
        local event = table.remove(data, 1)
        local wW, wH = self.win.getSize()
        local wX, wY = self.win.getPosition()
        if event == "mouse_click" and not options.lockSorting then
            local btn, x, y = table.unpack(data)
            x = x - wX + 1
            y = y - wY + 1
            if btn == 1 and y == 1 then --left click on top bar
                local column = 0
                local acc = 0
                for i, width in ipairs(columnWidths) do
                    column = i
                    acc = acc + width
                    if x <= acc then
                        break
                    end
                    acc = acc + 1
                    if x == acc then -- inbetween
                        column = -1
                        break
                    end
                end
                if sortBy ~= column then
                    sortBy = column
                    sortDesc = false
                else
                    sortDesc = not sortDesc
                end
            elseif scrollbar and btn == 1 and x == wW then
                if y == 2 then
                    offset = offset - 1
                elseif y == wH then
                    offset = offset + 1
                else
                    mouse_dragging_scrolbar = y
                end
                term.clear()
                term.setCursorPos(1, 1)
            end
        elseif event == "mouse_scroll" then
            local dir, x, y = table.unpack(data)
            offset = offset + dir
        elseif event == "mouse_drag" and scrollbar and mouse_dragging_scrolbar then
            local btn, x, y = table.unpack(data)
            local diff = y - mouse_dragging_scrolbar
            local distance = math.floor(diff * #self.rows / scrollHeight)
            offset = offset + distance
            mouse_dragging_scrolbar = y
        end

        local maxOffset = #self.rows - 1
        if options.scrollmode == "revealLast" then
            maxOffset = maxOffset - wH + 2
            if maxOffset < 0 then maxOffset = 0 end
        end
        if offset < 0 then
            offset = 0
        elseif offset > maxOffset then
            offset = maxOffset
        end
    end
end

return {
    create = create
}
