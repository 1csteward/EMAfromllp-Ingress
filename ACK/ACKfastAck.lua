function ACKfastAck(Message)
   local DefaultAck = "MSH|^~\\&|UNKNOWN|UNKNOWN|UNKNOWN|UNKNOWN|||ACK|UNKNOWN|P|2.3|\rMSA|AA|UNKNOWN|\r"
   if Message:find("MSH") ~= 1 then return DefaultAck end
   local SeparatorPosition = Message:find("\r")
   if not SeparatorPosition then return DefaultAck end
   Message = Message:sub(1, SeparatorPosition - 1)
   local FieldSeparator = Message:sub(4, 4)
   -- MSH segment
   local MshFields = Message:split(FieldSeparator)
   local MessageControlId = MshFields[10]

   -- Replace ORM with ACK
   local MsgType = MshField[9] or ""
   -- Message Type
   MshFields[9] = MsgType:gsub("ORM", "ACK")
   -- Message Control ID
   MshFields[10] = 'A'..MessageControlId
   -- MSA segment
   local MsaSegment = "\rMSA|AA|"..MessageControlId
   return table.concat(MshFields, FieldSeparator).. MsaSegment .. '\x1c\r'
end