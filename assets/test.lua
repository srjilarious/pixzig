print("Hello from test.lua file!")

-- Function to print a table (including metatables)
local function print_table(tbl, indent)
    indent = indent or ""
    if type(tbl) ~= "table" then
        print(indent .. tostring(tbl))
        return
    end

    for k, v in pairs(tbl) do
        if type(v) == "table" then
            print(indent .. tostring(k) .. " = {")
            print_table(v, indent .. "  ")
            print(indent .. "}")
        else
            print(indent .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

-- Assuming my_console is already defined as a global variable by your Zig code
if my_console then
    print("my_console exists.")
    print_table(my_console)
else
    print("my_console does not exist.")
end

print("Calling console log from script...")
my_console:log('testing from script file.')
