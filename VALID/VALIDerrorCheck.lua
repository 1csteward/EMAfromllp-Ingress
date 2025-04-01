--Error checking to perform on component Config values
local Encodings = require "VALID.VALIDencodings"

local function ValidHexFormat(input)
   -- Pattern to match a single \xNN sequence
   local pattern = "\\x[%dA-Fa-f][%dA-Fa-f]"
   -- Continuously match \xNN sequences until the end of the string
   local remaining = input
   while #remaining > 0 do
      local matched = string.match(remaining, "^" .. pattern)
      if not matched then
         return false -- If a sequence doesn't match, the input is invalid
      end
      -- Remove the matched sequence from the start of the string
      remaining = string.sub(remaining, #matched + 1)
   end
   return true
end

function VALIDerrorCheck()
   -- Remove white sapce from Prefix/suffix
   component.setField{key='LLPPrefix',value=component.fields().LLPPrefix:gsub('%s','')}
   component.setField{key='LLPSuffix',value=component.fields().LLPSuffix:gsub('%s','')}
   local Configs = component.fields()
   local Separator = os.posix() and [[/]] or [[\]]
   local SslValid = false
   -- Check file encoding
   if not Encodings[Configs.MessageEncoding] then
      error('File encoding '..Configs.MessageEncoding..' is not supported.')
   end
   -- Check port
   if Configs.Port == 0 then
      error('Port field is empty.')
   end
   -- Check format of prefix and suffix
   if not (ValidHexFormat(Configs.LLPPrefix) and ValidHexFormat(Configs.LLPSuffix)) then
      error('LLP prefix/suffix is invalid.\nInput must begin with \\x and hex values must be between 0-9 and A-F.\nExample: \\x0B')
   end
   -- Check certificate and key files  
   if not (Configs.SSLCertificate == '') or not (Configs.SSLKey == '') then
      if (Configs.SSLCertificate == '') or (Configs.SSLKey == '') then error('Both SSLCertificate and SSLKey must be specified to use SSL.')
      elseif not (os.fs.access(Configs.SSLCertificate)) then
         error('Unable to access SSL certificate file:\n'..Configs.SSLCertificate)      
      elseif not (os.fs.access(Configs.SSLKey)) then
         error('Unable to access SSL key file:\n'..Configs.SSLKey)
      else
         SslValid = true
      end
   end
   -- Check verify peer
   if SslValid and Configs.VerifyPeer then
      if (Configs.CaFile == '') then error('CaFile must be specified to use VerifyPeer.')
      elseif not (os.fs.access(Configs.CaFile)) then
         error('Unable to access Certificate Authority file:\n'..Configs.CaFile)
      end
   end

end