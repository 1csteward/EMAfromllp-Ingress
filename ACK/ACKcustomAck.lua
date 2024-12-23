function ACKcustomAck(Message)
   error('Custom ack generation must be implemented in ACKcustomAck')
   
   -- CUSTOMIZE this ACK generation if it doesn't meet your requirements 
   local DefaultAck = "MSH|^~\\&|UNKNOWN|UNKNOWN|UNKNOWN|UNKNOWN|||ACK|UNKNOWN|P|2.3|\rMSA|AA|UNKNOWN|\r"
   if Message:find("MSH") ~= 1 then return DefaultAck end
   local SeparatorPosition = Message:find("\r")
   if not SeparatorPosition then return DefaultAck end
   Message = Message:sub(1, SeparatorPosition - 1)
   local FieldSeparator = Message:sub(4, 4)
   -- MSH segment
   local MshFields = Message:split(FieldSeparator)
   local MessageControlId = MshFields[10]
   -- swap Sending and Receiving Application
   MshFields[9] = MshFields[3]
   MshFields[3] = MshFields[5]
   MshFields[5] = MshFields[9]
   -- swap Sending and Receiving Facility
   MshFields[9] = MshFields[4]
   MshFields[4] = MshFields[6]
   MshFields[6] = MshFields[9]
   -- Message Type
   MshFields[9] = 'ACK'
   -- Message Control ID
   MshFields[10] = 'A'..MessageControlId
   -- MSA segment
   local MsaSegment = "\rMSA|AA|"..MessageControlId
   return table.concat(MshFields, FieldSeparator)..MsaSegment
end