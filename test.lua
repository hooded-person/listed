local listed = require "listed"
local pprint = require "cc.pretty".pretty_print

local w, h = term.getSize()

local win = window.create(term.current(), 1, 1, w, h)

local list = listed.create(win, {
    columns = {
        {
            type = "string",
            header = "Name",
        },
        {
            type = "number",
            header = "Age",
            width = 4,
        }
    },
    gapSize = 1,
    pretty = true,
})


list:set(
    { "hi", 1 },
    { "bye", 4 }
)

list:add { "string", 0 }
list:add { "averyveryveryverylongbigstringthatisclippedandold", 324 }

list:display()
