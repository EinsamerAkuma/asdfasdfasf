local scriptName = "AE2 Colony"
local scriptVersion = "0.4.1 ATM9"

local craftMaxStack = false
local scanInterval = 8
local exportPeripheral = "sophisticatedstorage:chest_0"

local monitorLines = {}

local function logAndDisplay(msg)
  print(msg)
  table.insert(monitorLines, msg)
end

-- PERIPHERALS
local function setupPeripherals()
  term.clear()
  term.setCursorPos(1, 1)

  local bridge = peripheral.find("meBridge") or error("meBridge missing")
  local colony = peripheral.find("colonyIntegrator") or error("colonyIntegrator missing")
  local monitor = peripheral.find("monitor")

  return bridge, colony, monitor
end

local function confirmConnection(bridge)
  return bridge.isConnected()
end

-- MONITOR
local function updateMonitor(monitor)
  if not monitor then return end

  monitor.clear()
  monitor.setCursorPos(1,1)
  monitor.setTextScale(0.5)

  monitor.write(scriptName .. " v" .. scriptVersion)

  local y = 3

  for i = math.max(1, #monitorLines - 25), #monitorLines do
    monitor.setCursorPos(1, y)
    monitor.write(tostring(monitorLines[i]))
    y = y + 1
  end
end

-- EXPORT
local exportBuffer = {}

local function queueExport(name, count, target)
  table.insert(exportBuffer, {
    name = name,
    count = count,
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
        "[ERROR] Export failed x%d %s",
        item.count,
        item.name
      ))
    end
  end
end

-- ITEMS
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

-- REQUESTS
local function colonyRequestHandler(colony)

  local ok, result = pcall(function()
    return colony.getRequests()
  end)

  if ok then
    return result
  end

  return nil
end

-- SKIP LOGIC
local function shouldSkip(requestItem)

  if not requestItem then
    return true
  end

  local name = requestItem.name

  if not name then
    return true
  end

  if name:find("domum_ornamentum") then
    return true
  end

  if requestItem.components then
    return true
  end

  return false
end

-- CRAFTING
local function canCraft(bridge, requestName)

  local ok, craftables = pcall(function()
    return bridge.listCraftableItems()
  end)

  if ok and craftables then

    for _, item in pairs(craftables) do

      if item.name == requestName then
        return true
      end

    end
  end

  return false
end

local function craftHandler(request, bridge)

  local requestItem = request.items[1]

  if shouldSkip(requestItem) then
    return
  end

  local requestName = requestItem.name
  local fingerprint = requestItem.fingerprint

  local stackSize = request.count or 1

  if stackSize <= 0 then
    stackSize = 1
  end

  local craftable = canCraft(bridge, requestName)

  if craftable then

    local ok = pcall(function()

      bridge.craftItem({
        name = requestName,
        count = stackSize
      })

    end)

    if ok then

      logAndDisplay(string.format(
        "[CRAFT] x%d %s [%s]",
        stackSize,
        requestName,
        tostring(fingerprint)
      ))

    else

      logAndDisplay(string.format(
        "[ERROR] Craft failed x%d %s",
        stackSize,
        requestName
      ))

    end

  else

    logAndDisplay(string.format(
      "[MISSING] No recipe x%d %s",
      stackSize,
      requestName
    ))

  end
end

-- MAIN
local function mainHandler(bridge, colony)

  local requests = colonyRequestHandler(colony)

  if not requests or not next(requests) then
    logAndDisplay("[INFO] No colony requests detected!")
    return
  end

  local bridgeItems = bridgeDataHandler(bridge)

  for _, request in ipairs(requests) do

    local requestItem = request.items[1]

    if requestItem and not shouldSkip(requestItem) then

      local requestName = requestItem.name
      local fingerprint = requestItem.fingerprint
      local requestCount = request.count or 1
      local requestTarget = request.target or "Unknown"

      local bridgeItem = bridgeItems[fingerprint]

      if bridgeItem then

        local available = bridgeItem.amount or bridgeItem.count or 0

        if available >= requestCount then

          queueExport(
            requestName,
            requestCount,
            requestTarget
          )

        elseif available > 0 then

          queueExport(
            requestName,
            available,
            requestTarget
          )

          craftHandler(request, bridge)

        else

          craftHandler(request, bridge)

        end

      else

        craftHandler(request, bridge)

      end
    end
  end
end

-- START
local bridge, colony, monitor = setupPeripherals()

logAndDisplay(
  string.format(
    "[INFO] %s v%s initialized",
    scriptName,
    scriptVersion
  )
)

while true do

  exportBuffer = {}

  if confirmConnection(bridge) then

    mainHandler(bridge, colony)

    processExportBuffer(bridge)

  else

    logAndDisplay("[ERROR] AE2 OFFLINE")

  end

  updateMonitor(monitor)

  sleep(scanInterval)

end
