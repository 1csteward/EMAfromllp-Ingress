-- =============================================================================
-- hl7_utils.lua
-- Author: Conor Steward
-- Last Updated: 07/22/25
--
-- Purpose:
--   HL7 message validator for From LLP - Ingress component.
--   Uses segment-by-line parsing and VMD decoding for ZEF validation.
-- =============================================================================

local hl7_utils = {}

-- =============================================================================
-- Function: normalizeDelimiters
-- Purpose: Ensures consistent segment delimiter (\r)
-- =============================================================================
local function normalizeDelimiters(s)
   s = s:gsub("\r\n", "\r")
   s = s:gsub("\n", "\r")
   return s
end

-- =============================================================================
-- Function: splitSegments
-- Purpose: Splits raw HL7 into individual segment lines
-- =============================================================================
local function splitSegments(hl7)
   hl7 = normalizeDelimiters(hl7)
   local segments = {}
   for segment in hl7:gmatch("([^\r]+)") do
      segments[#segments + 1] = segment
   end
   return segments
end

-- =============================================================================
-- Function: segmentExists
-- Purpose: Checks if a segment is present in segment lines
-- =============================================================================
local function segmentExists(segments, name)
   for _, seg in ipairs(segments) do
      if seg:sub(1, #name + 1) == name.."|" then return true end
   end
   return false
end

-- =============================================================================
-- Function: segmentCount
-- Purpose: Counts how many times a segment appears in segment lines
-- =============================================================================
local function segmentCount(segments, name)
   local count = 0
   for _, seg in ipairs(segments) do
      if seg:sub(1, #name + 1) == name.."|" then count = count + 1 end
   end
   return count
end

-- =============================================================================
-- Function: isValidBase64Pdf
-- Purpose: Confirms input string is base64 and decodes to a PDF
-- =============================================================================
local function isValidBase64Pdf(str)
   local ok, decoded = pcall(filter.base64.dec, str)
   if not ok or not decoded then return false end
   return true
end

-- =============================================================================
-- Function: validateMessage
-- Purpose: Full HL7 validation + ZEF[2] base64 validation
-- Output: true if valid
--         false, errorCode, errorMessage if invalid
-- =============================================================================
function hl7_utils.validateMessage(rawHL7)
   local segments = splitSegments(rawHL7)

   -- Required segments
   for _, seg in ipairs({ "MSH", "PID", "ORC", "OBX" }) do
      if not segmentExists(segments, seg) then
         iguana.logError("Validation failed: Missing required segment ["..seg.."]")
         return false, "AR", "Missing required segment ["..seg.."]"
      end
   end

   -- Non-repeating segments
   for _, seg in ipairs({ "MSH", "PID", "PV1", "GT1", "ORC", "ZEF" }) do
      local count = segmentCount(segments, seg)
      if count > 1 then
         iguana.logError("Validation failed: Segment ["..seg.."] occurs "..count.." times but must not repeat.")
         return false, "AR", "Segment ["..seg.."] occurs "..count.." times but must not repeat."
      end
   end

   -- ZEF validation
   if segmentExists(segments, "ZEF") then
      local ok, parsed = pcall(hl7.parse, {vmd = "lab_orders.vmd", data = rawHL7})
      if not ok then
         iguana.logError("Validation failed: Could not parse message for ZEF decoding.")
         return false, "AR", "Could not parse message for ZEF decoding."
      end

      local zef = parsed.ZEF[2]
      if not zef then
         iguana.logError("Validation failed: No ZEF segment found in parsed structure.")
         return false, "AR", "No ZEF segment found in parsed structure."
      end

      if not isValidBase64Pdf(zef) then
         iguana.logError("Validation failed: ZEF[2] is not a valid base64-encoded PDF.")
         return false, "AR", "ZEF[2] is not a valid base64-encoded PDF."
      end
   end

   return true
end

return hl7_utils