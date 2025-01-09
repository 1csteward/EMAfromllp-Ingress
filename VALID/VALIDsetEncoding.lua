local Configs = component.fields()

function VALIDsetEncoding()
   local Encoding = Configs.MessageEncoding
   if Encoding == '' then
      component.setField{key='MessageEncoding',value=os.posix() and 'ISO-8859-1' or 'Windows-1252'}
   end
end