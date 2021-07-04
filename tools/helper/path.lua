local path = {}

function path.isabs(str)
    if type(str) == "table" then
        str = str[1]
        if not str then
            return false
        end
    end
    
    return path.isunixabs(str) or path.iswinabs(str)
end

function path.isunixabs(str)
    return str == "" or str:sub(1, 1) == "/"
end

function path.iswinabs(str)
    return str:match("^[A-Za-z]:") and true or false
end

function path.split(str)
    local ret = {}
    
    for v in str:gmatch("[^\\/]+") do
        table.insert(ret, v)
    end
    
    return ret
end

function path.abssplit(str)
    local ret = {}
    
    if path.iswinabs(str) then
        local first = str:sub(1, 2)
        table.insert(ret, first)
        
        str = str:sub(3)
        
        for v in str:gmatch("[^\\/]+") do
            table.insert(ret, v)
        end
        
        return ret
    end
    
    local idx, idxe = str:find("[\\/]+")
    if idx then
       local first = str:sub(1, idx - 1)
       table.insert(ret, first)
       
       str = str:sub(idxe + 1)
    end
    
    for v in str:gmatch("[^\\/]+") do
        table.insert(ret, v)
    end
    
    return ret
end

function path.relpath(str)
    if str == nil then
        return ""
    end
    
    return path.combine(path.split(str))
end

function path.abspath(str)
    if str == nil then
        return "/"
    end
    
    local ret = path.combine(path.abssplit(str))
    if ret ~= "" then
        return ret
    else
        return "/"
    end
end

function path.mwpath(str)
    local ret = path.abssplit(str)
    local retlen = #ret
    
    if retlen == 0 or retlen == 1 or ret[1] ~= "" or #ret[2] ~= 1 then
        return path.abspath(str)
    end
    
    local newchar = ret[2]:byte()
    newchar = newchar - 0x20
    
    if newchar < 0x41 or newchar > 0x5A then
        return path.abspath(str)
    end
    
    local newret = {}
    
    local first = string.char(newchar) .. ":"
    
    table.insert(newret, first)
    
    for k,v in ipairs(ret) do
        if k ~= 1 and k ~= 2 then
            table.insert(newret, v)
        end
    end
    
    return path.combine(newret)
end

function path.combine(...)
    local args = {...}
    
    if #args == 1 and type(args[1]) == "table" then
        args = args[1]
    end
    
    if args[1] == "" then
        local largs = {}
        for k,v in ipairs(args) do
            if k ~= 1 then
                table.insert(largs, v)
            end
        end
        
        args = largs
    end
    
    return table.concat(args, "/")
end

function path.join(...)
    local args = {...}
    
    local buf = {}
    
    for _, v in ipairs(args) do
        for _, w in ipairs(path.split(v)) do
            table.insert(buf, w)
        end
    end
    
    return path.sanitize(buf)
end

function path.rawsan(obj, abs)
    local split = obj
    
    local deep = 0
    local stack = {}
    
    local lastval
    if abs and #split ~= 0 then
        lastval = table.remove(split, 1)
    end
    
    for _, v in ipairs(split) do
        if v == ".." then
            table.remove(stack)
            deep = deep - 1
        elseif v ~= "." then
            table.insert(stack, v)
            deep = deep + 1
        end
    end
    
    deep = #stack - deep
    if abs or deep ~= 0 then
        local ret = {}
        
        if not abs then
            repeat
                table.insert(ret, "..")
                deep = deep - 1
            until deep == 0
        elseif lastval then
            table.insert(ret, lastval)
        end
        
        for _, v in ipairs(stack) do
            table.insert(ret, v)
        end
        
        return ret
    elseif #stack ~= 0 then
        return stack
    else
        return {}
    end
end

function path.san(obj)
    local split
    
    if type(obj) ~= "table" then
        split = path.split(obj)
    else
        split = obj
    end
    
    local ret = path.rawsan(split)
    
    if #ret ~= 0 then
        return table.concat(ret, "/")
    else
        return "."
    end
end

function path.abssan(obj)
    if not path.isabs(obj) then
        return path.san(obj)
    end
    
    local split
    
    if type(obj) ~= "table" then
        split = path.abssplit(obj)
    else
        split = obj
    end
    
    local ret = path.rawsan(split, true)
    
    if #ret ~= 0 then
        if #ret == 1 and ret[1] == "" then
            return "/"
        end
        
        return table.concat(ret, "/")
    else
        return "."
    end
end

return path
