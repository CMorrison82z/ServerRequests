local HTTPService = game:GetService("HttpService")

local Promise = require(script.Promise)

local isServer = game:GetService("RunService"):IsServer()

local remoteFunction : RemoteFunction = isServer and Instance.new("RemoteFunction") or script:WaitForChild("RemoteFunction")
local remoteEvent : RemoteEvent = isServer and Instance.new("RemoteEvent") or script:WaitForChild("RemoteEvent")

if isServer then	
	remoteFunction.Parent = script
	remoteEvent.Parent = script
end

local module = {}

if isServer then
	local DEFAULT_TIMEOUT = 30

	local activeRequests = {}
	
	function module.InvokeClient(player, requestName, timeout, ...)
		if not activeRequests[player] then
			activeRequests[player] = {}
		end
		
		if not activeRequests[player][requestName] then
			activeRequests[player][requestName] = {}
		end
		
		timeout = timeout or DEFAULT_TIMEOUT
		 
		local uuid = HTTPService:GenerateGUID(false)

		local thisPromise = Promise.try(remoteFunction.InvokeClient, remoteFunction, player, uuid, requestName, ...):timeout(timeout)
			
		local _conn; _conn = player.AncestryChanged:Connect(function(c, p)
			if p ~= game:GetService("Players") then
				thisPromise:cancel()
			end
		end)
		
		thisPromise:catch(function(e)
			if Promise.Error.isKind(e, Promise.Error.Kind.TimedOut) then
				remoteEvent:FireClient(player, uuid)
			end
		end):finally(function(status)
			if _conn then _conn:Disconnect() end
			activeRequests[player][requestName][uuid] = nil
			
			if status == Promise.Status.Cancelled then
				remoteEvent:FireClient(player, uuid)
			end
		end)
		
		activeRequests[player][requestName][uuid] = thisPromise
		
		return thisPromise
	end
	
	-- Returns a dictionary of dictionaries per requestName that themselves consist of promises.
	function module.GetPlayerActiveRequests(player)
		return activeRequests[player]
	end
	
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		if activeRequests[player] then
			for _, promisesOfRequest in pairs(activeRequests[player]) do
				for _, aPromise in pairs(promisesOfRequest) do
					aPromise:cancel()
				end
			end
			
			table.clear(activeRequests[player])
			
			activeRequests[player] = nil
		end
	end)
else
	local requestHandlers = {}
	
	function module.SetRequestHandler(requestName, handler : () -> any)
		assert(type(requestName) == "string", "RequestName was not a string")
		
		if requestHandlers[requestName] then return error("Request handler for " .. requestName .. " already exists. Must be removed / replaced") end
		requestHandlers[requestName] = handler
	end
	
	-- This also behaves as "Remove"
	function module.ReplaceRequestHandler(requestName, handler)
		requestHandlers[requestName] = handler
	end
	
	function module.GetRequestHandler(requestName)
		return requestHandlers[requestName]
	end
	
	local activeRequests = {}
	
	remoteEvent.OnClientEvent:Connect(function(uuid)
		if not activeRequests[uuid] then return warn("No active request for " .. tostring(uuid)) end
		warn("cancelling", uuid)

		activeRequests[uuid]:cancel()
	end)
	
	remoteFunction.OnClientInvoke = function(uuid, requestName, ...)
		if not requestHandlers[requestName] then return error("No request handler for " .. requestName) end -- Hoow are errors handled by remote functions ???? idk LOL
		
		warn("trying", uuid)
		activeRequests[uuid] = Promise.try(requestHandlers[requestName], ...)
		
		local succ, res = activeRequests[uuid]:await()
		warn(succ, res)

		if succ then return res end
	end
end

return module