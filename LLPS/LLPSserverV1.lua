local Configs = component.fields()
local LLP_MESSAGE_PREFIX
local LLP_MESSAGE_SUFFIX

local LLPconnections = {}
local LLP_DEBUG = Configs.UseDebugLogs
local LLP_TIMEOUT = Configs.ConnectionTimeout

local CONN_DETAILS = {
   port = Configs.Port,
   ssl = {
      cert = Configs.SSLCertificate,
      key = Configs.SSLKey
   }
}

if Configs.VerifyPeer then
   CONN_DETAILS.ssl.verify_peer = Configs.VerifyPeer
   CONN_DETAILS.ssl.ca_file = Configs.CaFile
end

local function LLPpurgeIdleConnections()
   if EnableConnectionTimeout then
      local now = os.time()
      for id, connection in pairs(LLPconnections) do
         if now - connection.ts > LLP_TIMEOUT then
            if LLP_DEBUG then
               iguana.logDebug("Closing idle connection " .. tostring(id))
            end
            socket.close_a{connection=id}
         end
      end
   end
end

socket.onAccept = function(Address, Id)
   iguana.logInfo("New connection " .. tostring(Id) .. " received from " .. Address)
   LLPconnections[Id] = {id = Id, ip = Address, ts = os.time() }
   LLPpurgeIdleConnections()
end

local function LLPparse(Buffer) -- parse LLP messages in buffer into Messages
   if #Buffer > 0 and Buffer:find(LLP_MESSAGE_PREFIX) ~= 1 then
      error("Unexpected data in buffer")
   end
   local consumed = 0
   local messages = {}
   for message in Buffer:gmatch(LLP_MESSAGE_PREFIX .. "(.-)" .. LLP_MESSAGE_SUFFIX) do
      consumed = consumed + #LLP_MESSAGE_PREFIX + #message + #LLP_MESSAGE_SUFFIX
      table.insert(messages, message)
   end
   Buffer:sub(consumed)
   return messages, consumed
end

-- Check if it's any known TLS version
local function LLPisTLShandshake(Data)
    if #Data < 3 then return false end
    local byte1, byte2, byte3 = Data:byte(1, 3)
    return byte1 == 0x16 and byte2 == 0x03 and (
        byte3 == 0x00 or  -- SSL 3.0 (rare)
        byte3 == 0x01 or  -- TLS 1.0
        byte3 == 0x02 or  -- TLS 1.1
        byte3 == 0x03 or  -- TLS 1.2
        byte3 == 0x04     -- TLS 1.3
    )
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
   local success, messages, amount = pcall(LLPparse, Connection.buffer)
   if not success then
      if LLPisTLShandshake(Data) and CONN_DETAILS.ssl.cert == "" then
         messages = "SSL is off but client is trying to initiate SSL handshake"
      end
      if LLP_DEBUG then
         iguana.logDebug("Closing connection " .. tostring(Connection.id) .. ": " .. messages .. "\n")
      end
      socket.close_a{connection=Connection.id}
      return
   end
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

socket.onClose = function(Data, Id, Err)
   local function CloseConn()
      local log_message = "Connection " .. tostring(Id) .. " closed"
      if #Data > 0 then
         log_message = log_message .. " with non-empty buffer: " .. Data:sub(1, 1024)
      end
      if Err then
         if Err:match('wrong version number') then
            log_message = log_message .. " due to error: " .. Err .. '\nTry verifying the SSL settings on the sender and receiver'
         else
            log_message = log_message .. " due to error: " .. Err
         end
         iguana.logError(log_message)
      end
      if LLP_DEBUG then
         iguana.logInfo(log_message)
      end
      LLPconnections[Id] = nil
      LLPpurgeIdleConnections()
   end

   -- Error callback mechanism
   local success, err = pcall(CloseConn)
   if not success then
      local error_message = "Error in socket.onClose for Connection ID " .. tostring(Id) .. ": " .. tostring(err)
      if LLP_DEBUG then
         iguana.logError(error_message)
      end
   end
end

function LLPstart()
   socket.listen_a(CONN_DETAILS)
end