--require "VALID.VALIDerrorCheck"
--Convert hex values to octal values
function CONNsetPreffixSuffix(HexValues)
   --VALIDerrorCheck()
   local values = string.split(HexValues,[[\]])
   table.remove(values,1)
   trace(values)
   local result = ''
   for i=1,#values do
      result = result..string.char('0'..values[i])
   end
   return result
end