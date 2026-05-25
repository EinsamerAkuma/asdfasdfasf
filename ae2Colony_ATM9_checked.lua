local scriptName = "AE2 Colony"
local scriptVersion = "0.4.1 ATM9"

local apVersions = {
  ["0.7.46r"] = true,
  ["0.7.51b"] = true,
  ["0.7.55b"] = true
}

local requiredAP = "0.7.46r"

local craftMaxStack = false
local scanInterval = 30
local doLog = false
local doLogExtra = false
local exportPeripheral = "sophisticatedstorage:chest_0"

local monitorLines = {}

local function logAndDisplay(msg)
  print(msg)
  table.insert(monitorLines, msg)
end

local function setupPeripherals()

  term.clear()
  term.setCursorPos(1,1)

  local bridge = peripheral.find("meBridge") or error("meBridge missing")
  local colony = peripheral.find("colonyIntegrator") or error("colonyIntegrator missing")

  return bridge, colony
end

local function confirmConnection(bridge)
  return bridge.isConnected()
end

local exportBuffer = {}

local function queueExport(fingerprint, count, name, target)

  table.insert(exportBuffer, {
    fingerprint = fingerprint,
    count = count,
    name = name,
    target = target
  })
end

local function processExportBuffer(bridge)

  for _, item in ipairs(exportBuffer) do

    local ok, result = pcall(function()

      return bridge.exportItemToPeripheral({
        name = item.name,
        count = item.count
      }, exportPeripheral)

    end)

    if ok and result and result > 0 then

      logAndDisplay(string.format(
        "[SENT] x%d %s > %s",
        item.count,
        item.name,
        item.target
      ))

    else

      logAndDisplay(string.format(
        "[ERROR] x%d %s > %s",
        item.count,
        item.name,
        item.target
      ))

    end
  end
end

local function bridgeDataHandler(bridge)

  local indexFingerprint = {}

  local ok, result = pcall(function()
    return bridge.listItems()
  end)

  if ok and result then

    for i = 1, #result do

      local item = result[i]

      if item.fingerprint then
        indexFingerprint[item.fingerprint] = item
      end
    end

  else

    logAndDisplay("[ERROR] ME Bridge Issues")

  end

  return indexFingerprint
end

local function colonyRequestHandler(colony)

  local ok, result = pcall(function()
    return colony.getRequests()
  end)

  if ok then

    if not next(result) then
      return nil
    end

    return result
  end

  return nil
end

local function craftHandler(request, bridgeItem, bridge)

  local requestItem = request.items[1]

  if not requestItem then
    return
  end

  local requestName = requestItem.name

  if not requestName then
    return
  end

  if requestName:find("domum_ornamentum") then
    logAndDisplay("[SKIP] Domum Ornamentum")
    return
  end

  if requestItem.components then
    logAndDisplay("[SKIP] NBT Item")
    return
  end

  local fingerprintRequest = requestItem.fingerprint
  local maxStackSize = requestItem.maxStackSize
  local stackSize = (craftMaxStack and maxStackSize) or request.count

  if stackSize == 0 then
    stackSize = 1
  end

  local payload = {
    name = requestName,
    count = stackSize
  }

  local craftable = false

  local okCraftables, craftables = pcall(function()
      return bridge.listCraftableItems()
  end)

  if okCraftables and craftables then

      for _, item in pairs(craftables) do

          if item.name == requestName then
              craftable = true
              break
          end

      end
  end

  if craftable then

    local ok = pcall(function()
      bridge.craftItem(payload)
    end)

    if ok then

      logAndDisplay(string.format(
        "[CRAFT] x%d - %s [%s]",
        stackSize,
        requestName,
        fingerprintRequest
      ))

    else

      logAndDisplay(string.format(
        "[ERROR] Failed crafting: x%d - %s [%s]",
        stackSize,
        requestName,
        fingerprintRequest or "N/A"
      ))

    end

  else

    logAndDisplay(string.format(
      "[MISSING] No recipe x%d - %s [%s]",
      stackSize,
      requestName,
      fingerprintRequest or "N/A"
    ))

  end
end

local function mainHandler(bridge, colony)

  local colonyRequests = colonyRequestHandler(colony)
  local indexFingerprint = bridgeDataHandler(bridge)

  if not colonyRequests then
    logAndDisplay("[INFO] No colony requests detected!")
    return
  end

  for _, request in ipairs(colonyRequests) do

    local requestCount = request.count or 0
    local requestItem = request.items[1]
    local requestTarget = request.target or request.name or "Unknown Target"

    if requestItem then

      local requestFingerprint = requestItem.fingerprint
      local requestName = requestItem.name

      if requestName and requestName:find("domum_ornamentum") then
        logAndDisplay("[SKIP] Domum Ornamentum")
        goto continue
      end

      if requestItem.components then
        logAndDisplay("[SKIP] NBT Item")
        goto continue
      end

      local bridgeItem = indexFingerprint[requestFingerprint]

      if bridgeItem then

        local bridgeCount = bridgeItem.amount or bridgeItem.count or 0
        local countDelta = bridgeCount - requestCount

        if countDelta > 0 then

          queueExport(
            requestFingerprint,
            requestCount,
            requestName,
            requestTarget
          )

        elseif bridgeCount > 0 then

          queueExport(
            requestFingerprint,
            bridgeCount,
            requestName,
            requestTarget
          )

          craftHandler(request, bridgeItem, bridge)

        else

          craftHandler(request, bridgeItem, bridge)

        end

      else

        craftHandler(request, bridgeItem, bridge)

      end
    end

    ::continue::
  end
end

local bridge, colony = setupPeripherals()

print(string.format(
  "[INFO] %s v%s initialized",
  scriptName,
  scriptVersion
))

while true do

  exportBuffer = {}
  monitorLines = {}

  local online = confirmConnection(bridge)

  if online then

    mainHandler(bridge, colony)
    processExportBuffer(bridge)

  else

    logAndDisplay("[ERROR] AE2 OFFLINE")

  end

  sleep(scanInterval)

end
