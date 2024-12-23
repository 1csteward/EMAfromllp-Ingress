local Configs = component.fields()
local LLP_MESSAGE_PREFIX
local LLP_MESSAGE_SUFFIX

local LLPconnections = {}
local LLP_DEBUG = false
local LLP_TIMEOUT = Configs.ConnectionTimeout

local function LLPpurgeIdleConnections()
   local now = os.time()
   for id, connection in pairs(LLPconnections) do
      if now - connection.ts > LLP_TIMEOUT then
         if LLP_DEBUG then
            iguana.logDebug("Closing idle connection " .. tostring(Id))
         end
         socket.close_a{connection=id}
      end
   end
end

socket.onAccept = function(Address, Id)
   iguana.logInfo("New connection " .. tostring(Id) .. " received from " .. Address)
   LLPconnections[Id] = {id = Id, ip = Address, ts = os.time() }
   LLPpurgeIdleConnections()
end

local function LLPparse(Buffer) -- parse LLP messages in buffer into Messages
   local consumed = 0
   local messages = {}
   for message in Buffer:gmatch(LLP_MESSAGE_PREFIX .. "(.-)" .. LLP_MESSAGE_SUFFIX) do
      consumed = consumed + #LLP_MESSAGE_PREFIX + #message + #LLP_MESSAGE_SUFFIX
      table.insert(messages, message)
   end
   Buffer:sub(consumed)
   return messages, consumed
end

local function LLPonData(Connection, Data)
   if not LLP_MESSAGE_PREFIX or LLP_MESSAGE_SUFFIX then
      LLP_MESSAGE_PREFIX = CONNsetPreffixSuffix(Configs.LLPPrefix)
      LLP_MESSAGE_SUFFIX = CONNsetPreffixSuffix(Configs.LLPSuffix)
   end
   -- append data to buffer
   if not Connection.buffer then
      Connection.buffer = Data
   else
      Connection.buffer = Connection.buffer .. Data
   end
   -- extract LLP messages
   local messages, amount = LLPparse(Connection.buffer)
   if amount > 0 then  -- truncate buffer
      Connection.buffer = Connection.buffer:sub(amount + 1)
   end
   -- process messages in main and send response
   for _,message in ipairs(messages) do
      local ack = main(message)
      socket.send_a{data=LLP_MESSAGE_PREFIX..ack..LLP_MESSAGE_SUFFIX, connection=Connection.id}
   end
end

socket.onData = function(Data, Id)
   if LLP_DEBUG then
      iguana.logDebug("Received data from connection " .. tostring(Id) .. "\n")
   end
   LLPonData(LLPconnections[Id], Data)
   LLPconnections[Id].ts = os.time()
   LLPpurgeIdleConnections()
end

socket.onWrite = function(Id)
   if LLP_DEBUG then
      iguana.logDebug("Connection " .. tostring(Id) .. " is ready to receive more data")
   end
   LLPconnections[Id].ts = os.time()
   LLPpurgeIdleConnections()
end

-- TODO - we don't have an error callback
socket.onClose = function(Data, Id)
   local log_message = "Connection " .. tostring(Id) .. " closed"
   if #Data > 0 then
      log_message = log_message .. " with non-empty buffer: " .. Data:sub(1, 1024)
   end
   if LLP_DEBUG then
      iguana.logInfo(log_message)
   end
   LLPconnections[Id] = nil
   LLPpurgeIdleConnections()
end

function LLPstart()
   local Config = component.fields()
   socket.listen_a{port=Config.Port}
end