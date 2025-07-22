-- =============================================================================
-- Function: NACK
-- Author: Conor Steward
-- Date: 07/22/25
--
-- Purpose:
--   Generate a negative HL7 ACK (NACK) using the structure of the incoming message.
--   Used for messages that fail validation or cannot be processed.
--
-- Inputs:
--   - Message: Raw HL7 message string
--   - Code: HL7 MSA-1 acknowledgment code ("AE" or "AR")
--   - Text: MSA[3] error text (e.g., "PID segment missing")
--
-- Output:
--   - String: HL7-formatted NACK message
-- =============================================================================
function NACK(Message, Code, Text)
   local ErrorCode = Code or "AE"
   local DefaultNack = "MSH|^~\\&|UNKNOWN|UNKNOWN|UNKNOWN|UNKNOWN|||ACK|UNKNOWN|P|2.3\rMSA|"..ErrorCode.."|UNKNOWN\r"

   if Message:find("MSH") ~= 1 then return DefaultNack end
   local SepPos = Message:find("\r")
   if not SepPos then return DefaultNack end

   local MSH = Message:sub(1, SepPos - 1)
   local FS = MSH:sub(4, 4)
   local Fields = MSH:split(FS)
   local MsgId = Fields[10] or "UNKNOWN"

   -- Swap sending and receiving application
   Fields[9] = Fields[3]
   Fields[3] = Fields[5]
   Fields[5] = Fields[9]

   -- Swap sending and receiving facility
   Fields[9] = Fields[4]
   Fields[4] = Fields[6]
   Fields[6] = Fields[9]

   Fields[9] = "ACK"
   Fields[10] = "A" .. MsgId

   local MSA = "\rMSA|"..ErrorCode.."|"..MsgId
   if Text then
      MSA = MSA .. "|" .. Text
   end

   return table.concat(Fields, FS) .. MSA
end
