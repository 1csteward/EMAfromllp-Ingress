require "VALID.VALIDsetEncoding"
require "VALID.VALIDencodings"
require "VALID.VALIDerrorCheck"
require "CONN.CONNsetPrefixSuffix"
require "ACK.ACKcustomAck"
require "ACK.ACKfastAck"
require "LLPS.LLPSserver"
local Configs = component.fields()

-- The main function is called when a message is received by the server
-- An ACKnowledgement message must be returned when it exits
function main(Message)
   if (Message == "INIT") then
      LLPstart()
      if Configs.MessageEncoding == '' then
         VALIDsetEncoding()
      end
      VALIDerrorCheck()
      return
   end
   
   local MessageId = queue.push{data=Message}
   local Ack
   if Configs.AckGeneration == 'Fast' then
      Ack = ACKfastAck(Message)
   else
      Ack = ACKcustomAck(Message)
   end
   iguana.logInfo("Generated ACK\n"..Ack, MessageId)
   return Ack
end