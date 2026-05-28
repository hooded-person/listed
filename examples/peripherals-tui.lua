local pprint = require"cc.pretty".pretty_print
local listed = require "/listed"

local w, h = term.getSize()
local win = window.create(term.current(), 1, 1, w, h)
local list = listed.create(win, {
    columns = {
        {
            type = "string",
            header = "Name/Side",
            sorting = function(a, b)
                local a_name = a:match("^[^_]+")
                local a_id = a:match("_(%d+)$")
                local b_name = b:match("^[^_]+")
                local b_id = b:match("_(%d+)$")
                print(a_name, a_id, b_name, b_id)
                if (a_id and not b_id) or (not a_id and b_id) then -- either one is a side and the other is an modem thingy
                    return not a_id -- a is a side and b is not, so a goes first 
                elseif a_id and b_id then
                    if a_name == b_name then
                        return tonumber(a_id) < tonumber(b_id)
                    else
                        return a_name > b_name
                    end
                end
                return false
            end
        },
        {
            type = "table",
            header = "Type",
        },
    },
    gapSize = 1,
})

local names = peripheral.getNames()
if #names == 0 then
    print("No peripherals attached")
    error()
end

table.sort(names, list.columns[1].sorting)

for _, name in ipairs(names) do
    local types = { peripheral.getType(name) }
    list:add { name, types }
end

list:run(0, {
    scrollbar = true,
})
