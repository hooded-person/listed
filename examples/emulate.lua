local types = {
    ["tank"] = 100
}
local function attach(side, type)
    local ok, err = periphemu.create(side, type)
    write(("Attaching peripheral %s (%s): "):format(side, type, ok and "Success" or err))
end
attach("bottom", "modem")

for name, count in pairs(types) do
    for i=0,count do
        attach(name.."_"..i, name)
    end
end