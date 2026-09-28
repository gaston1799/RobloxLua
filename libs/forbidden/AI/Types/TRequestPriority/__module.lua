export type RequestPriority = "Low" | "DefaultStart" | "Normal" | "DefaultStop" | "High" | "Critical" | string

local API = {}

API.ConvertNumberToPriority = function(Number: number): RequestPriority
    if Number <= 0 then
        return "Low"
    elseif Number == 1 then
        return "Normal"
    elseif Number == 2 then
        return "High"
    elseif Number >= 3 then
        return "Critical"
    else
        error("Invalid number for RequestPriority: " .. tostring(Number))
    end
end

API.ConvertPriorityToNumber = function(Priority: RequestPriority): number
    if Priority == "Low" then
        return 0
    elseif Priority == "DefaultStart" then
        return 1
    elseif Priority == "Normal" then
        return 1
    elseif Priority == "DefaultStop" then
        return 2
    elseif Priority == "High" then
        return 2
    elseif Priority == "Critical" then
        return 3
    else
        error("Invalid RequestPriority: " .. tostring(Priority))
    end
end

API.GetPriorityNumber = function(Priority: RequestPriority | number): number

    if typeof(Priority) == "number" then
        return Priority
    end

    return API.ConvertPriorityToNumber(Priority)
end

return API