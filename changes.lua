local files = {
    "changes.lua",
    "test.lua",
    "listed.lua"
}
local entry = "test.lua"

for i, file in ipairs(files) do
    local resolved = shell.resolve(file)
    if not fs.exists(resolved) then
        error(("File '%s' ('%s') does not exist"):format(file, resolved))
    end
    if fs.isDir(resolved) then
        error(("'%s' ('%s') is not a file but a directory"):format(file, resolved))
    end
end

local restart = true
while restart do
    local changed = nil
    parallel.waitForAny(
        function()
            shell.run(entry)
            print("Program ended")
            print("Press x to exit, press any other key to restart")
            local _, key = os.pullEvent("key")
            restart = key ~= keys.x
            os.pullEvent("char")
        end,
        function()
            local contents = {}
            while true do
                for i, file in ipairs(files) do
                    local h = fs.open(file, "r")
                    local content = h.readAll()
                    h.close()
                    if contents[file] == nil then
                        contents[file] = content
                    elseif contents[file] ~= content then
                        changed = file
                        return
                    end
                end
                sleep()
            end
        end
    )
    if changed then
        if changed ~= shell.getRunningProgram() then
            print(("File '%s' contents changed, reloading"):format(changed))
            sleep(1)
        else
            print("This file got changed, 'tailcalling' new version")
            restart = false
            sleep(1)
            shell.run(shell.getRunningProgram())
        end
    else
        print("Restarting")
    end
end
