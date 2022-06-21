-- Configuration : 

local DEFAULT_TIMEOUT = 30

-----------------------------------------------------------------------

local HTTPService = game:GetService("HttpService")

local Promise = require(script.Promise)

local isServer = game:GetService("RunService"):IsServer()

local remoteFunction : RemoteFunction = isServer and Instance.new("RemoteFunction") or script:WaitForChild("RemoteFunction")
local remoteEvent : RemoteEvent = isServer and Instance.new("RemoteEvent") or script:WaitForChild("RemoteEvent")

local module = {}
module.Promise = Promise
module.Error = Promise.Error

if isServer then
	remoteFunction.Parent = script
	remoteEvent.Parent = script

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
			else
				warn(e)
			end
		end):finally(function(status)
			if _conn then _conn:Disconnect() end
			activeRequests[player][requestName][uuid] = nil
			
			if status == Promise.Status.Cancelled then
				remoteEvent:FireClient(player, uuid)
			end
		end)
		
		activeRequests[player][requestName][uuid] = thisPromise
		
		return thisPromise, uuid
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
	local requestHandlersPromise = {}
	
	function module.SetRequestHandler(requestName, handler : ((any) -> any)?)
		assert(type(requestName) == "string", "RequestName was not a string")
		
		if requestHandlers[requestName] or requestHandlersPromise[requestName]  then return error("Request handler for " .. requestName .. " already exists. Must be removed / replaced") end
		requestHandlers[requestName] = handler
	end
	
	function module.SetRequestHandlerPromise(requestName, handler : ((any) -> Promise)?)
		assert(type(requestName) == "string", "RequestName was not a string")
		
		if requestHandlersPromise[requestName] or requestHandlers[requestName] then return error("Request handler for " .. requestName .. " already exists. Must be removed / replaced") end
		requestHandlersPromise[requestName] = handler
	end
	
	function module.GetRequestHandler(requestName)
		return requestHandlers[requestName] or requestHandlersPromise[requestName]
	end
	
	local activeRequests = {}
	
	remoteEvent.OnClientEvent:Connect(function(uuid)
		if not activeRequests[uuid] then return warn("No active request for " .. tostring(uuid)) end
		warn("cancelling", uuid)

		activeRequests[uuid]:cancel()
	end)
	
	remoteFunction.OnClientInvoke = function(uuid, requestName, ...)
		local newRequestPromise;
		
		if requestHandlers[requestName] then
			newRequestPromise = Promise.try(requestHandlers[requestName])
		elseif 	requestHandlersPromise[requestName] then
			newRequestPromise = requestHandlersPromise[requestName](...)
		else
			return error("No request handler for " .. requestName) -- Hoow are errors handled by remote functions ???? idk LOL
		end

		activeRequests[uuid] = newRequestPromise
		
		assert(Promise.is(newRequestPromise), "Client '" .. requestName .. "' did not return a Promise.")
		
		local succ, res = newRequestPromise:await()

		if succ then return res end
	end
end

return module