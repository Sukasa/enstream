local os = require("os")
local net = require("minitel")
local component = require("component")
local event = require("event")
local bit32 = require("bit32")

if not component.isAvailable("data") then
  error("enstream library requires a tier 2 data card")
end

local data = component.data

if data.encrypt == nil then
  error("enstream library requires a tier 2 data card")
end

local enstream = {
  packetBuf = {},
  ready = false
}

local function applyKey(key, keymod)
  local scrambled = ""
  local k0 = {string.byte(key, 1, key:len())}
  local k1 = {string.byte(keymod, 1, keymod:len())}
  for i=1,#k0 do
    scrambled = scrambled .. string.char(bit32.bxor(k0[i], k1[i]))
  end
  return scrambled
end

local function generateKey()
  return data.random(16)
end

-- COMMANDS
-- 0 -> init 1 (i0)
-- 1 -> init 2 (i1)
-- 2 -> init 3 (i2)

-- 4 -> close stream

-- 8 -> data packet

--12 -> FUTURE
local function onRx(stream)  
  local packet = stream.inner:read()
  local command,iv,packetData = packet:sub(1,1),data.decode64(packet:sub(2,23).."=="),data.decode64(packet:sub(24))

  command = string.byte(command)  
  local code = bit32.rshift(bit32.band(command, 12), 2)
  local comdata = bit32.band(command, 3)
  
  if code == 0 then
    if comdata == 0 then
      -- We were connected to and received the key init.  Wrap with our keymod and send back
      local keyData = applyKey(packetData, stream.keymod)
      stream:rawPacket(1, nil, keyData)
    elseif comdata == 1 then
      -- We got the double-wrapped key; strip our mod and send back
      local keyData = applyKey(packetData, stream.keymod)
      stream:rawPacket(2, nil, keyData)
      strea.ready = true
    elseif comdata == 2 then -- key transferred.
      stream.key = applyKey(packetData, stream.keymod)
      stream.ready = true
    end
  elseif code == 1 then
    stream:close()
    ready = false
  elseif code == 2 then
    -- decrypt data and enqueue
    packetData = data.decrypt(packetData, stream.key, iv)
    stream.packetBuf[#stream.packetBuf+1] = packetData
    
    event.push("enc_msg", stream.inner.addr, stream.inner.port, packetData, stream)
    if stream.callback then
      stream.callback()
    end
  end
  
end

local function pollStream(stream)
  while stream.inner.rbuffer:len() > 0 do
    local a,b = xpcall(onRx, debug.traceback, stream)
    file:write("Poll Was: " .. tostring(a) .. ", " .. tostring(b) .. "\n")
  end
end

function enstream:rawPacket(command, iv, packetData)
  if self.inner.state ~= "open" then
    return false, "socket closed"
  end
  
  command = bit32.band(command, 15)  
  iv = iv or data.random(16)
  self.inner:write(string.char(bit32.band(math.random(255), 240) + command) .. data.encode64(tostring(iv)):sub(1,22) .. data.encode64(packetData) .. "\n")
end

function enstream:write(packetData)
  if self.inner.state == "open" then
    if not self.ready then
      return false, "connection not ready"
    end
    local iv = generateKey()
    self:rawPacket(8, iv, data.encrypt(packetData, self.key, iv))
  else
    return false, "socket closed"
  end
end

function enstream:available()
  return #self.packetBuf
end

function enstream:close()
  self.inner:write(makePacket(4, nil, ""))
  self.inner:close()
  event.cancel(self.pollEvent)
end

function enstream:read()
  if self.inner.state ~= "open" and #self.packetBuf == 0 then return nil,"Socket Closed" end
  if #self.packetBuf == 0 then return nil,"Empty Buffer" end
  return table.remove(self.packetBuf, 1)
end

function enstream:new(mStream) -- Wraps the minitel stream in an encryption layer
  local es = {inner=mStream}
  setmetatable(es, self)
  self.__index = self
  es.keymod = generateKey()
  es.pollEvent = event.timer(0.1, function() pollStream(es) end, math.huge)
  return es
end

function enstream:connect()
  self.key = generateKey()
  local scrambled = applyKey(self.key, self.keymod)  
  self:rawPacket(0, nil, scrambled)
end

return enstream