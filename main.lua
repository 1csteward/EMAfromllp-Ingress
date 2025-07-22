require "ACK.NACK"
local hl7_utils = require "hl7_utils"
require "CARDupdate"
require "STAT.STATstatus"
require "VALID.VALIDsetEncoding"
require "VALID.VALIDerrorCheck"
require "CONN.CONNsetPrefixSuffix"
require "ACK.ACKcustomAck"
require "ACK.ACKfastAck"
require "LLPS.LLPSserver"

local Configs = component.fields()

-- =============================================================================
-- Function: main
-- Purpose : Entry point for LLP - Ingress. Handles INIT, validates HL7,
--           queues messages, returns appropriate ACKs.
-- =============================================================================
function main(Message)
   -- Initiate on INIT
   if Message == "INIT" then
      if Configs.MessageEncoding == '' then
         VALIDsetEncoding()
      end
      VALIDerrorCheck()
      LLPstart()
      return
   end

   -- Validate HL7 structure and content
   local isValid, errCode, errMsg = hl7_utils.validateMessage(Message)
   if not isValid then
      iguana.logWarning("Message skipped due to validation failure: "..(errMsg or "unknown error"))
      return NACK(Message, errCode or "AR", errMsg or "Validation failed")
   end

   -- Normalize encoding
   Message = iconv.convert(Message, Configs.MessageEncoding, 'UTF-8')

   -- Push message to next stage
   local MessageId = queue.push{data=Message}

   -- Determine and return appropriate ACK
   local Ack
   if Configs.AckGeneration == 'Fast' then
      Ack = ACKfastAck(Message)
   else
      Ack = ACKcustomAck(Message)
   end

   iguana.logInfo("#ack Generated ACK\n"..Ack, MessageId)
   ui.setStatusMessage{data=CARDupdate("Data last received at", os.date("%Y/%m/%d %H:%M:%S"))}
   return Ack
end