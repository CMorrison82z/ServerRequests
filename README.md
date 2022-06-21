# Server Requests

Server requests are essentially RemoteFunctions wrapped in a [Promise](https://eryn.io/roblox-lua-promise/) with some basic management options. 

## API 

Promises Cancelled on the server are automatically communicated to the client. This means that if a handler was set to handle OnCancel as specified by Promise.new, the client will be able to reconcile cancelled requests with ease.

### Server :

```lua
InvokeClient(player : Player, requestName : string, timeout : number?, ...) -> Promise, UUID
```

Invokes the client, returning a Promise.

```lua
GetPlayerActiveRequests(player : Player) -> {{[string] : {[number] : Promise}}}
```

Retrieve a dictionary of active requests for the player. The dictionary has keys of RequestName. The entries for an active request of a specified request name is a dictionary of UUID's with the associated Promise.

### Client :

```lua
SetRequestHandler(requestName, handler : (any) -> Promise)
```

Set the handler for requests of  "requestName".

```lua
SetRequestHandlerPromise(requestName, handler : ((any) -> Promise)?)
```

Set the handler for requests of  "requestName". This must return a Promise. Used for handlers that need control over what should happen if the Server cancels a request.

```lua
GetRequestHandler(requestName)
```

Gets the function set as the request handler for "requestName"