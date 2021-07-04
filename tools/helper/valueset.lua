local vs = {}

function vs.new()
    local obj = {}
    local mt = {}
    
    local backer = {}
    local order = {}
    local indexes = {}
    
    function mt.__index(this, index)
        return backer[index]
    end
    
    function mt.__newindex(this, index, val)
        backer[index] = val
        
        if indexes[index] then
            return
        end
        
        local newindex = #order + 1
        order[newindex] = index
        indexes[index] = newindex
    end
    
    function mt.__unm(this)
        local i = 1
        
        return function()
            if i > #order then
                return
            end
            
            local key = order[i]
            local value = backer[key]
            
            i = i + 1
            
            return key, value
        end
    end
    
    setmetatable(obj, mt)
    return obj
end

return vs
