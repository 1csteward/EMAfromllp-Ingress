local Configs = component.fields()
local LLP_MESSAGE_PREFIX
local LLP_MESSAGE_SUFFIX

local LLPconnections = {}
local LLP_DEBUG = Configs.UseDebugLogs
local LLP_TIMEOUT = Configs.ConnectionTimeout

local function LLPpurgeIdleConnections()
   if not Configs.EnableConnectionTimeout then return end
   local now = os.time()
   for socket, connection in pairs(LLPconnections) do
      if now - connection.ts > LLP_TIMEOUT then
         if LLP_DEBUG then
            iguana.logDebug("Closing idle " .. socket)
         end
         socket:close()
      end
   end
end

local function LLPparse(Buffer) -- parse LLP messages in buffer into Messages
   if #Buffer > 0 and Buffer:find(LLP_MESSAGE_PREFIX) ~= 1 then
      error("Unexpected data in buffer\n"..Buffer)
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
      if LLPisTLShandshake(Data) and Configs.SSLCertificate == "" then
         messages = "SSL is off but client is trying to initiate SSL handshake"
      end
      if LLP_DEBUG then
         iguana.logDebug("Closing " .. Connection.socket .. ": " .. messages .. "\n")
      end
      Connection.socket:close()
      return
   end
   local messages, amount = LLPparse(Connection.buffer)
   if amount > 0 then  -- truncate buffer
      Connection.buffer = Connection.buffer:sub(amount + 1)
   end
   -- process messages in main and send response
   for _,message in ipairs(messages) do
      local ack = main(message)
      Connection.socket:send(LLP_MESSAGE_PREFIX..ack..LLP_MESSAGE_SUFFIX)
   end
end

local function onData(Socket, Data)
   if LLP_DEBUG then
      iguana.logDebug("Received data on " .. Socket)
   end
   if #Data > 0 then
      LLPonData(LLPconnections[Socket], Data)
   end
   LLPconnections[Socket].ts = os.time()
   LLPpurgeIdleConnections()
end

local function onWrite(Socket)   -- optional callback function
   if LLP_DEBUG then
      iguana.logDebug(Socket .. " is ready to receive more data")
   end
   LLPconnections[Socket].ts = os.time()
   LLPpurgeIdleConnections()
end

local function onClose(Socket, Data, Err)
   if #Data > 0 then
      iguana.logWarning(Socket .. " closed with non-empty buffer: " .. Data:sub(1, 1024))
   end
   if Err then
      local error_message = Socket .. " closed due to error: " .. Err
      if Err:match('wrong version number') then
         error_message = error_message .. "\nTry verifying the SSL settings on the sender and receiver"
      end
      iguana.logError(error_message)
   end
   if LLP_DEBUG then
      iguana.logDebug(Socket .. " closed")
   end
   LLPconnections[Socket] = nil
   LLPpurgeIdleConnections()
end

local function onAccept(Socket, ClientIp)
   if LLP_DEBUG then
      iguana.logDebug("New " .. Socket)
   end
   Socket:setOnDataReceived(onData)
   Socket:setOnSendComplete(onWrite)
   Socket:setOnSocketClosed(onClose)
   LLPconnections[Socket] = {socket = Socket, ip = ClientIp, ts = os.time() }
   LLPpurgeIdleConnections()
end

function LLPstart()
   local Config = {
      port = Configs.Port,
      ssl = {
         cert = Configs.SSLCertificate,
         key = Configs.SSLKey,
         verify_peer = Configs.VerifyPeer,
         ca_file = Configs.CaFile
      },
      onAccept=onAccept
   }
   net.tcpAsync.listen(Config)
end