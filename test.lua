local listed = require "listed"
local pprint = require "cc.pretty".pretty_print

local w, h = term.getSize()

local win = window.create(term.current(), 1, 1, w, h)

local list = listed.create(win, {
    columns = {
        {
            type = "number",
            header = "Id",
            width = 3,
        },
        {
            type = "string",
            header = "Name",
        },
        {
            type = "string",
            header = "Country",
        },
        {
            type = "number",
            header = "Age",
            width = 4,
        },
        {
            type = "boolean",
            header = "Living",
            width = 6,
        }
    },
    gapSize = 1,
    pretty = true,
})


list:set(
    { 1, "hi", "bye", 1, false },
    { 2, "Luigi", "Mario Universe", 4, true }
)

list:add { 3, "string", "heap memory", 0, true }
list:add { 4, "averyveryveryverylongbigstringthatisclippedandoldokaysoitwasntlongenoughwhenfullscreeningthewindowsoimadeitlonger", "stone?", 324, false }

for i = 5, 1.5 * h do
    local str = ""
    for _ = 4, 8 do
        str = str .. string.char(math.random(65, 122))
    end
    local addr = ""
    for _ = 4, 8 do
        addr = addr .. string.char(math.random(65, 122))
    end
    list:add { i, str, addr, math.random(999), math.random() >= 0.5 }
end

-- list:display(0, list.c.Id)

list:run(0, {
    sortBy = list.c.Id,
    scrollbar = true,
    scrollmode = "revealLast",
    -- lockSorting = true,
})
