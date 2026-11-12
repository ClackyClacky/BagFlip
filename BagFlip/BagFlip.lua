-- BagFlip: for each item in your bags, should you sell it to a vendor or list it on the auction house?
-- Vendor prices come from the game itself. Auction prices come from Prices.lua, a snapshot of
-- the EU PvP auction houses, or from your own Auctionator scans when those are recent.

local ADDON = ...
local AH_CUT = 0.05          -- faction auction house cut
local DEPOSIT = 100          -- copper per listing (1s for now; set to 1 once the 1c deposit is live)
-- The deposit is subtracted below, so the margins only need to cover the time an auction takes:
local MIN_GAIN = 100         -- copper: auction must beat the vendor by at least 1s per stack...
local MIN_RATIO = 1.10       -- ...and pay at least 10% more than the vendor
local SLOW_SALES = 0.5       -- sold per day (TSM, EU-wide) below this counts as slow

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local floor, max, min = math.floor, math.max, math.min

-- Backpack + 4 bags, plus the reagent bag on clients that have one (Forever does: bag 5).
local BAG_IDS = {}
for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do BAG_IDS[#BAG_IDS + 1] = bag end
do
  local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if reagent and reagent > BAG_IDS[#BAG_IDS] then BAG_IDS[#BAG_IDS + 1] = reagent end
end

-- Bank: the main bank slots plus the bank bag slots. Newer clients name them in Enum.BagIndex;
-- older ones number the bank bags straight after your own bags (and the reagent bag).
local BANK_IDS = {}
do
  local BI = Enum and Enum.BagIndex or {}
  local seen = {}
  local function add(b) if b and not seen[b] then seen[b] = true; BANK_IDS[#BANK_IDS + 1] = b end end
  add(BI.Bank or BANK_CONTAINER or -1)
  if BI.CharacterBankTab_1 then
    local i = 1
    while BI["CharacterBankTab_" .. i] do add(BI["CharacterBankTab_" .. i]); i = i + 1 end
  elseif BI.BankBag_1 then
    local i = 1
    while BI["BankBag_" .. i] do add(BI["BankBag_" .. i]); i = i + 1 end
  else
    local first = BAG_IDS[#BAG_IDS] + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do add(b) end
  end
  add(BI.Reagentbank or REAGENTBANK_CONTAINER)
end

local db -- SavedVariables, set on ADDON_LOADED

---------------------------------------------------------------------------- helpers
local function money(c)
  c = floor((c or 0) + 0.5)
  if GetCoinTextureString then return GetCoinTextureString(c, 12) end
  local g, s, cc = floor(c / 10000), floor(c / 100) % 100, c % 100
  return (g > 0 and g .. "g " or "") .. ((g > 0 or s > 0) and s .. "s " or "") .. cc .. "c"
end

-- Sales per day, TSM's EU-wide figure (all Forever auction houses in the region).
local function perDay(id)
  local spd = BagFlipPrices and BagFlipPrices.sold and BagFlipPrices.sold[id]
  if not spd or spd <= 0 then return nil end
  if spd >= 10 then return ("%d"):format(floor(spd + 0.5)) end
  if spd >= 0.1 then return ("%.1f"):format(spd) end
  return "<0.1"
end

local function faction()
  local f = UnitFactionGroup("player")
  return (f == "Alliance" or f == "Horde") and f or "Horde"
end

local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(bag, slot)
    if i then return i.itemID, i.stackCount, i.hyperlink, i.iconFileID, i.isBound, i.isLocked end
    return
  end
  local icon, count, locked, _, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
  if link then return id or tonumber(link:match("item:(%d+)")), count, link, icon, nil, locked end
end

local function numSlots(bag)
  return (C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag)
end

-- Soulbound check that works whether or not the client gives us isBound.
local scan = CreateFrame("GameTooltip", "BagFlipScanTip", nil, "GameTooltipTemplate")
scan:SetOwner(WorldFrame, "ANCHOR_NONE")
local function isBound(bag, slot, flag)
  if flag ~= nil then return flag end
  scan:ClearLines(); scan:SetBagItem(bag, slot)
  for i = 2, min(scan:NumLines(), 6) do
    local t = _G["BagFlipScanTipTextLeft" .. i]:GetText()
    if t == ITEM_SOULBOUND or t == ITEM_BIND_QUEST then return true end
  end
  return false
end

-- Auctionator's own scan of *your* auction house wins when it is recent (<= 2 days old).
local function auctionatorPrice(id)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetAuctionPriceByItemID) then return nil end
  local ok, price = pcall(api.GetAuctionPriceByItemID, "BagFlip", id)
  if not ok or not price or price <= 0 then return nil end
  local okAge, age = pcall(api.GetAuctionAgeByItemID, "BagFlip", id)
  if okAge and age and age > 2 then return nil end
  return price, (okAge and age) or 0
end

-- Price per unit we could realistically list at on our faction's auction house.
-- Returns price, soldPerDay, listedQty (-1 = from Auctionator), source note.
-- Snapshot entries in Prices.lua are { lowest, market, average, listed } in copper.
local function ahPrice(id)
  local scanned, age = auctionatorPrice(id)
  local spd0 = BagFlipPrices and BagFlipPrices.sold and BagFlipPrices.sold[id] or 0
  if scanned then
    return max(scanned - 1, 1), spd0, -1, (age == 0 and "your scan today" or ("your scan, " .. age .. "d old"))
  end
  local d = BagFlipPrices and BagFlipPrices[faction()]
  local p = d and d[id]
  if not p then return nil end
  local low, market, avg, qty = p[1], p[2], p[3], p[4]
  local spd = BagFlipPrices.sold and BagFlipPrices.sold[id] or 0
  local price
  if qty > 0 and market > 0 then
    price = market
    if avg > 0 then price = min(price, floor(avg * 1.15)) end  -- ignore one inflated listing
    price = max(price, low)
    price = max(price - 1, 1)                                    -- undercut by 1c
  elseif avg > 0 then
    price = avg                                                 -- none listed: last known average
  end
  return price, spd, qty, nil
end

-- Returns: verdict ("AH", "Vendor" or "Keep"), vendor total, AH net total, note
local function judge(id, count, bound)
  local sell = select(11, GetItemInfo(id)) or 0
  local vendorTotal = sell * count
  if bound then return (sell > 0 and "Vendor" or "Keep"), vendorTotal, nil, "soulbound" end
  local price, spd, qty, src = ahPrice(id)
  if not price then return (sell > 0 and "Vendor" or "Keep"), vendorTotal, nil, "no auction data" end
  local ahTotal = max(floor(price * (1 - AH_CUT)) * count - DEPOSIT, 0)  -- one listing per stack
  local note
  if qty == 0 then note = "none listed now" elseif spd > 0 and spd < SLOW_SALES then note = "sells slowly" end
  if ahTotal - vendorTotal >= MIN_GAIN and ahTotal >= vendorTotal * MIN_RATIO then
    return "AH", vendorTotal, ahTotal, note
  end
  if sell == 0 then return "Keep", 0, ahTotal, "worth too little on the AH" end
  return "Vendor", vendorTotal, ahTotal, note
end

---------------------------------------------------------------------------- bag scan
local pending = false

-- Adds one stack to rows, merging stacks of the same item (and bound state and place).
local function addStack(rows, byKey, id, count, link, icon, bound, bank)
  local key = id .. (bound and "b" or "") .. (bank and "k" or "")
  local r = byKey[key]
  if r then r.count = r.count + (count or 1)
  else
    r = { id = id, link = link, icon = icon, count = count or 1, bound = bound, bank = bank }
    byKey[key] = r; rows[#rows + 1] = r
  end
  if not GetItemInfo(id) then pending = true end
end

local function readContainers(ids, rows, byKey, bank)
  for _, bag in ipairs(ids) do
    for slot = 1, numSlots(bag) or 0 do
      local id, count, link, icon, boundFlag = slotInfo(bag, slot)
      if id then addStack(rows, byKey, id, count, link, icon, isBound(bag, slot, boundFlag), bank) end
    end
  end
end

-- The game only lets addons read the bank while it is open, so each visit is saved
-- per character and shown from that copy the rest of the time.
local bankOpen = false
local function charBank()
  if not db then return nil end
  db.bank = db.bank or {}
  local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
  db.bank[key] = db.bank[key] or {}
  return db.bank[key]
end

local function saveBank()
  local store = bankOpen and charBank()
  if not store then return end
  local items = {}
  readContainers(BANK_IDS, items, {}, true)
  for _, r in ipairs(items) do r.bank = nil end
  store.items, store.time = items, time()
end

local function scanBags()
  local rows, byKey = {}, {}
  readContainers(BAG_IDS, rows, byKey, false)
  local store = db and not db.hideBank and charBank()
  if store and store.items then
    for _, r in ipairs(store.items) do addStack(rows, byKey, r.id, r.count, r.link, r.icon, r.bound, true) end
  end
  local vendorAll, smart = 0, 0
  for _, r in ipairs(rows) do
    r.verdict, r.vendor, r.ah, r.note = judge(r.id, r.count, r.bound)
    r.gain = (r.verdict == "AH") and (r.ah - r.vendor) or 0
    vendorAll = vendorAll + r.vendor
    smart = smart + (r.verdict == "AH" and r.ah or r.vendor)
  end
  local order = { AH = 0, Vendor = 1, Keep = 2 }
  table.sort(rows, function(a, b)
    if order[a.verdict] ~= order[b.verdict] then return order[a.verdict] < order[b.verdict] end
    if a.gain ~= b.gain then return a.gain > b.gain end
    return (a.vendor or 0) > (b.vendor or 0)
  end)
  return rows, vendorAll, smart
end

---------------------------------------------------------------------------- window
local ROW_H, VISIBLE = 22, 16  -- VISIBLE sets the window height
local f = CreateFrame("Frame", "BagFlipFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(680, 142 + ROW_H * VISIBLE)
f:SetPoint("CENTER")
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetClampedToScreen(true)
f:Hide()
tinsert(UISpecialFrames, "BagFlipFrame")  -- Escape closes it

f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.title:SetPoint("TOP", 0, -5)
f.title:SetText("BagFlip: vendor it or auction it?")

f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
f.summary:SetPoint("TOPLEFT", 14, -32); f.summary:SetPoint("TOPRIGHT", -14, -32)
f.summary:SetJustifyH("LEFT")

f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
f.sub:SetPoint("TOPLEFT", f.summary, "BOTTOMLEFT", 0, -4)
f.sub:SetPoint("RIGHT", -14, 0); f.sub:SetJustifyH("LEFT")

f.bankBox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
f.bankBox:SetSize(22, 22); f.bankBox:SetPoint("TOPLEFT", 10, -66)
f.bankText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
f.bankText:SetPoint("LEFT", f.bankBox, "RIGHT", 2, 0)
f.vendorBox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
f.vendorBox:SetSize(22, 22); f.vendorBox:SetPoint("TOPLEFT", 400, -66)
f.vendorText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
f.vendorText:SetPoint("LEFT", f.vendorBox, "RIGHT", 2, 0)
f.vendorText:SetText("Open at vendors")

local COLX = { name = 34, count = 290, vendor = 335, ah = 425, sales = 535, verdict = 595 }
local header = CreateFrame("Frame", nil, f); header:SetPoint("TOPLEFT", 10, -94); header:SetSize(650, 16)
for k, label in pairs({ name = "Item", count = "Qty", vendor = "Vendor", ah = "Auction (after cut)",
                        sales = "Sales/day", verdict = "Do this" }) do
  local t = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  t:SetPoint("LEFT", COLX[k] - 10, 0); t:SetText(label)
end

local scroll = CreateFrame("ScrollFrame", "BagFlipScroll", f, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 10, -112); scroll:SetPoint("BOTTOMRIGHT", -30, 12)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(640, ROW_H)
scroll:SetScrollChild(list)

local VERDICT = {
  AH = "|cff40d060Auction|r", Vendor = "|cffffd100Vendor|r", Keep = "|cff9d9d9dKeep / bin|r",
}
---------------------------------------------------------------------------- click to sell
-- Selling uses the same call as right-clicking the item in your bag. Away from a vendor that
-- would use or equip it instead, so it only ever runs while a merchant window is open.
local merchantOpen = false
local autoOpened = false  -- window was opened by a vendor visit, so close it when leaving
local useItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
local function say(msg) print("|cff40d060BagFlip|r " .. msg) end

local function sellHint(d)
  if d.bank then return "|cff9d9d9dIn your bank: take it out to sell it|r" end
  if (d.vendor or 0) <= 0 then return "|cff9d9d9dVendors won't buy this|r" end
  if not merchantOpen then return "|cff9d9d9dOpen a vendor, then click to sell|r" end
  if d.verdict == "AH" then return "|cffffd100Shift-click to sell anyway (the AH pays more)|r" end
  return "|cff40d060Click to sell to the vendor|r"
end

local function sellRow(d)
  if d.bank then say("that stack is in your bank."); return end
  if (d.vendor or 0) <= 0 then say("vendors won't buy that."); return end
  if not merchantOpen then say("open a vendor first, then click to sell."); return end
  if d.verdict == "AH" and not IsShiftKeyDown() then
    say("the auction house pays more for that. Shift-click to sell it anyway."); return
  end
  local sold = 0
  for _, bag in ipairs(BAG_IDS) do
    for slot = 1, numSlots(bag) or 0 do
      local id, count, _, _, boundFlag, locked = slotInfo(bag, slot)
      if id == d.id and not locked and (isBound(bag, slot, boundFlag) and true or false) == (d.bound and true or false) then
        if not merchantOpen then return end
        useItem(bag, slot)
        sold = sold + (count or 1)
      end
    end
  end
  if sold > 0 then say(("sold %d x %s (buyback on the vendor if that was a mistake)."):format(sold, d.link or d.id)) end
end

local rowsUI = {}
local function getRow(i)
  local r = rowsUI[i]
  if r then return r end
  r = CreateFrame("Button", nil, list)
  r:SetSize(640, ROW_H); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 2, 0)
  for _, k in ipairs({ "name", "count", "vendor", "ah", "sales", "verdict" }) do
    local t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", COLX[k] - 10, 0); t:SetJustifyH("LEFT"); r[k] = t
  end
  r.name:SetWidth(245); r.name:SetWordWrap(false)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.06)
  r:SetScript("OnEnter", function(self)
    if not self.data then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self.data.link)
    GameTooltip:AddLine(sellHint(self.data)); GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self) if self.data then sellRow(self.data) end end)
  rowsUI[i] = r
  return r
end

local data = {}
local function refresh()
  for i, d in ipairs(data) do
    local ui = getRow(i)
    ui.data = d
    ui.icon:SetTexture(d.icon)
    ui.name:SetText(d.bank and (d.link .. " |cff9d9d9d(bank)|r") or d.link)
    ui.count:SetText(d.count)
    ui.vendor:SetText(d.vendor > 0 and money(d.vendor) or "|cff9d9d9d-|r")
    ui.ah:SetText(d.ah and money(d.ah) or "|cff9d9d9d-|r")
    local ph = not d.bound and perDay(d.id)
    ui.sales:SetText(ph or "|cff9d9d9d-|r")
    ui.verdict:SetText(VERDICT[d.verdict] .. (d.note and (" |cff9d9d9d" .. d.note .. "|r") or ""))
    ui:Show()
  end
  for i = #data + 1, #rowsUI do rowsUI[i]:Hide(); rowsUI[i].data = nil end
  list:SetHeight(max(ROW_H, #data * ROW_H))
end

local function update()
  pending = false
  local rows, vendorAll, smart = scanBags()
  data = rows
  local ahCount = 0
  for _, r in ipairs(rows) do if r.verdict == "AH" then ahCount = ahCount + 1 end end
  f.summary:SetText(("Vendor everything: %s     Auction the %d green ones, vendor the rest: |cff40d060%s|r")
    :format(money(vendorAll), ahCount, money(smart)))
  local snap = BagFlipPrices and BagFlipPrices.snapshot or "missing"
  local src = (Auctionator and Auctionator.API) and "your Auctionator scans first, then " or ""
  f.sub:SetText(("Auction: %sEU PvP %s snapshot (%s).  Sales/day: TSM, all EU Forever.  Vendor: the game.")
    :format(src, faction(), snap))
  local store = db and charBank()
  local seen
  if bankOpen then seen = "bank is open, live"
  elseif store and store.time then
    local s = time() - store.time
    seen = "as of your last visit, " .. (s < 3600 and floor(s / 60) .. "m" or s < 86400 and floor(s / 3600) .. "h"
      or floor(s / 86400) .. "d") .. " ago"
  else seen = "not seen yet: open your bank once" end
  f.bankBox:SetChecked(not (db and db.hideBank))
  f.bankText:SetText("Include bank items |cff9d9d9d(" .. seen .. ")|r")
  f.vendorBox:SetChecked(db and db.openAtVendor and true or false)
  refresh()
end

f.bankBox:SetScript("OnClick", function(self)
  if not db then return end
  db.hideBank = not self:GetChecked()
  update()
end)
f.vendorBox:SetScript("OnClick", function(self)
  if not db then return end
  db.openAtVendor = self:GetChecked() and true or false
end)

-- Bag and item-info events only matter while the window is open, and they arrive in bursts
-- (looting, vendoring, a bag full of uncached items), so listen only while shown and
-- rescan at most once per burst.
local queued = false
local function queueUpdate()
  if queued then return end
  queued = true
  C_Timer.After(0.2, function() queued = false; if f:IsShown() then update() end end)
end
local live = CreateFrame("Frame")
live:SetScript("OnEvent", function(_, e)
  if e == "BAG_UPDATE_DELAYED" or pending then queueUpdate() end
end)
f:SetScript("OnShow", function()
  live:RegisterEvent("BAG_UPDATE_DELAYED")
  live:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  update()
end)
f:SetScript("OnHide", function() live:UnregisterAllEvents(); autoOpened = false end)

-- While the bank is open, keep the saved copy current (again at most once per burst).
local bankQueued = false
local function queueBankSave()
  if bankQueued then return end
  bankQueued = true
  C_Timer.After(0.2, function()
    bankQueued = false
    saveBank()
    if f:IsShown() then queueUpdate() end
  end)
end
local bankWatch = CreateFrame("Frame")
bankWatch:SetScript("OnEvent", queueBankSave)

---------------------------------------------------------------------------- events & command
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:SetScript("OnEvent", function(self, e, name)
  if e == "ADDON_LOADED" then
    if name ~= ADDON then return end
    BagFlipDB = BagFlipDB or {}
    db = BagFlipDB
    self:UnregisterEvent("ADDON_LOADED")
  elseif e == "MERCHANT_SHOW" then
    merchantOpen = true
    if db and db.openAtVendor and not f:IsShown() then
      f:Show()
      autoOpened = true  -- close it again when you leave this vendor
    end
  elseif e == "MERCHANT_CLOSED" then
    merchantOpen = false
    if autoOpened then autoOpened = false; f:Hide() end
  elseif e == "BANKFRAME_OPENED" then
    bankOpen = true
    saveBank()
    bankWatch:RegisterEvent("BAG_UPDATE_DELAYED")
    bankWatch:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    queueBankSave()  -- once more after the bank finishes loading
    if f:IsShown() then queueUpdate() end
  elseif e == "BANKFRAME_CLOSED" then
    -- No save here: by now the bank may already be unreadable, which would save it as empty.
    bankOpen = false
    bankWatch:UnregisterAllEvents()
    if f:IsShown() then queueUpdate() end
  end
end)

SLASH_BAGFLIP1, SLASH_BAGFLIP2 = "/bagflip", "/bf"
SlashCmdList.BAGFLIP = function(msg)
  msg = (msg or ""):lower()
  if msg == "vendor" then
    db = db or BagFlipDB or {}
    BagFlipDB = db
    db.openAtVendor = not db.openAtVendor
    print("|cff40d060BagFlip|r opens at vendors: " .. (db.openAtVendor and "on" or "off"))
    if f:IsShown() then update() end
  elseif msg == "bank" then
    db = db or BagFlipDB or {}
    BagFlipDB = db
    db.hideBank = not db.hideBank
    print("|cff40d060BagFlip|r bank items: " .. (db.hideBank and "hidden" or "shown"))
    if f:IsShown() then update() end
  else
    f:SetShown(not f:IsShown())
  end
end
