-- ============================================================================
-- LLP Async Listener (refactored to use net.tcpAsync)
-- Author: Conor Steward
-- ============================================================================
local Configs = component.fields()
local LLP_MESSAGE_PREFIX
local LLP_MESSAGE_SUFFIX

local LLPconnections = {}
local LLP_DEBUG = Configs.UseDebugLogs
local LLP_TIMEOUT = Configs.ConnectionTimeout
local ENABLE_TIMEOUT = Configs.EnableConnectionTimeout

local CONN_DETAILS = {
   port = Configs.Port,
   ssl = {
      cert = Configs.SSLCertificate,
      key = Configs.SSLKey
   }
}

if Configs.VerifyPeer then
   CONN_DETAILS.ssl.verify_peer = true
   CONN_DETAILS.ssl.ca_file = Configs.CaFile
end

-- ============================================================================
-- Utility: Clean idle LLP connections
-- ============================================================================
local function LLPpurgeIdleConnections()
   if ENABLE_TIMEOUT then
      local now = os.time()
      for id, conn in pairs(LLPconnections) do
         if now - conn.ts > LLP_TIMEOUT then
            if LLP_DEBUG then
               iguana.logDebug("Closing idle connection: " .. tostring(id))
            end
            conn.Socket:close()
         end
      end
   end
end

-- ============================================================================
-- Utility: Check if incoming bytes resemble TLS handshake
-- ============================================================================
local function LLPisTLShandshake(Data)
   if #Data < 3 then return false end
   local b1, b2, b3 = Data:byte(1, 3)
   return b1 == 0x16 and b2 == 0x03 and (
      b3 == 0x00 or b3 == 0x01 or b3 == 0x02 or b3 == 0x03 or b3 == 0x04
   )
end

-- ============================================================================
-- LLP Buffer Parser
-- ============================================================================
local function LLPparse(Buffer)
   if #Buffer > 0 and Buffer:find(LLP_MESSAGE_PREFIX) ~= 1 then
      error("Unexpected data in buffer")
   end
   local messages, consumed = {}, 0
   for message in Buffer:gmatch(LLP_MESSAGE_PREFIX .. "(.-)" .. LLP_MESSAGE_SUFFIX) do
      consumed = consumed + #LLP_MESSAGE_PREFIX + #message + #LLP_MESSAGE_SUFFIX
      table.insert(messages, message)
   end
   return messages, consumed
end

-- ============================================================================
-- Data Received Callback
-- ============================================================================
local function onData(Socket, Buffer)
   local conn = LLPconnections[Socket]
   if not conn then return end

   if not LLP_MESSAGE_PREFIX or not LLP_MESSAGE_SUFFIX then
      LLP_MESSAGE_PREFIX = CONNsetPreffixSuffix(Configs.LLPPrefix)
      LLP_MESSAGE_SUFFIX = CONNsetPreffixSuffix(Configs.LLPSuffix)
   end

   conn.buffer = (conn.buffer or "") .. Buffer

   local ok, messages, consumed = pcall(LLPparse, conn.buffer)
   if not ok then
      if LLPisTLShandshake(Buffer) and CONN_DETAILS.ssl.cert == "" then
         iguana.logError("Client attempted SSL handshake but server has no cert configured.")
      end
      iguana.logError("Closing connection: " .. tostring(Socket) .. " — " .. tostring(messages))
      Socket:close()
      return
   end

   if consumed > 0 then
      conn.buffer = conn.buffer:sub(consumed + 1)
   end

   for _, msg in ipairs(messages) do
      local ack = main(msg)
      Socket:send(LLP_MESSAGE_PREFIX .. ack .. LLP_MESSAGE_SUFFIX)
   end

   conn.ts = os.time()
   LLPpurgeIdleConnections()
end

-- ============================================================================
-- Socket Write Complete Callback
-- ============================================================================
local function onSend(Socket)
   if LLP_DEBUG then
      iguana.logDebug("Ready for next data on: " .. tostring(Socket))
   end
   local conn = LLPconnections[Socket]
   if conn then conn.ts = os.time() end
   LLPpurgeIdleConnections()
end

-- ============================================================================
-- Socket Closed Callback
-- ============================================================================
local function onClosed(Socket, Buffer, Err)
   local msg = "Connection closed: " .. tostring(Socket)
   if #Buffer > 0 then
      msg = msg .. " | Buffer: " .. Buffer:sub(1, 1024)
   end
   if Err then
      msg = msg .. " | Error: " .. tostring(Err)
      if Err:match("wrong version number") then
         msg = msg .. " — verify SSL settings on sender/receiver"
      end
   end
   iguana.logInfo(msg)
   LLPconnections[Socket] = nil
   LLPpurgeIdleConnections()
end

-- ============================================================================
-- Accept Callback: Registers events per connection
-- ============================================================================
local function onAccept(Socket, ClientIp)
   iguana.logInfo("Accepted connection from: " .. ClientIp)
   LLPconnections[Socket] = {
      id = tostring(Socket),
      ip = ClientIp,
      ts = os.time(),
      buffer = "",
      Socket = Socket
   }

   Socket:setOnDataReceived(onData)
   Socket:setOnSendComplete(onSend)
   Socket:setOnSocketClosed(onClosed)

   LLPpurgeIdleConnections()
end

-- ============================================================================
-- Start the LLP Listener
-- ============================================================================
function LLPstart()
   iguana.logInfo("Starting LLP listener on port: " .. CONN_DETAILS.port)
   net.tcpAsync.listen{
      port     = CONN_DETAILS.port,
      ssl      = CONN_DETAILS.ssl,
      onAccept = onAccept
   }
end