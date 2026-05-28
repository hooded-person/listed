local listed = require "listed"
local pprint = require "cc.pretty".pretty_print

local w, h = term.getSize()

local win = window.create(term.current(), 1, 1, w, h)

local list = listed.create(win, {
    columns = {
        {
            type = "number",
            header = "Id",
            width = 2,
        },
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


list:set (
    { 1, "hi", 1 },
    { 2, "bye", 4 }
)

list:add { 3, "string", 0 }
list:add { 4, "averyveryveryverylongbigstringthatisclippedandold", 324 }

list:display()
