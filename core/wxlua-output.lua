-- SILE output for wxlua
-- Copyright 2015 Paul Kulchenko

-- Supports PgUp/PgDn navigation
-- Known issues:
--   font substitution is incomplete as it's only done based on font name
--   font size is adjusted by 2 to produce the size that closely matches the PDF output
--   text positions are adjusted as wxwidgets draws using top-left coordinates instead of baseline
-- TODO: add zooming (using +/-)

if (not SILE.outputters) then SILE.outputters = {} end
local f
local cx
local cy
local frame, font, fontadj, bitmap, title
local pages = {}
local page = 1

require 'wx'
local osname = wx.wxPlatformInfo.Get():GetOperatingSystemFamilyName()
local linux = osname == 'Unix'
local colors = {wx.wxBLACK}
local pen = wx.wxBLACK_PEN
local mdc = wx.wxMemoryDC()
local w, h

local function log(...) SU.debug("wxlua-output", table.concat({...}, "\t")) end

local function OnPaint()
  -- must always create a wxPaintDC in a wxEVT_PAINT handler
  local dc = wx.wxPaintDC(frame)
  dc:DrawBitmap(bitmap, 0, 0, true)
  dc:delete() -- always delete any wxDCs created when done
end

local function l2d(v) return v*16/12 end

local function newpage()
  bitmap = wx.wxBitmap(w,h)
  mdc:SelectObject(bitmap)
  mdc:Clear()
  mdc:SelectObject(wx.wxNullBitmap)

  table.insert(pages, {bitmap = bitmap})
end

local function setpage(p)
  page = p
  bitmap = pages[page].bitmap
  frame:SetTitle(title:format(page, #pages))
  frame:Refresh()
end

SILE.outputters.wxlua = {
  init = function()
    w = math.floor(0.5+l2d(SILE.documentState.paperSize[1]))
    h = math.floor(0.5+l2d(SILE.documentState.paperSize[2]))
    title = SILE.outputFilename.." (%d/%d)"

    log("Open file", SILE.outputFilename)
    log("Set paper size ", w, h)
    log("Init page")
    newpage()
  end,
  newPage = function()
    log("New page")
    newpage()
  end,
  finish = function()
    log("End page")
    log("Finish")

    frame = wx.wxFrame(
      wx.NULL, -- no parent for toplevel windows
      wx.wxID_ANY, -- don't need a wxWindow ID
      "",
      wx.wxDefaultPosition,
      wx.wxDefaultSize,
      wx.wxDEFAULT_FRAME_STYLE + wx.wxSTAY_ON_TOP - wx.wxRESIZE_BORDER - wx.wxMAXIMIZE_BOX)
    frame:SetClientSize(w, h)
    frame:Connect(wx.wxEVT_PAINT, OnPaint)
    frame:Connect(wx.wxEVT_ERASE_BACKGROUND, function () end) -- do nothing
    frame:Show()
    frame:Connect(wx.wxEVT_KEY_DOWN,
      function (event)
        local keycode = event:GetKeyCode()
        local mod = event:GetModifiers()
        if keycode == wx.WXK_PAGEDOWN and page < #pages then
          setpage(page + 1)
        elseif keycode == wx.WXK_PAGEUP and page > 1 then
          setpage(page - 1)
        end
      end)

    setpage(1)
    wx.wxGetApp():MainLoop()
  end,
  setColor = function(self, color)
    log("Set color", color.r, color.g, color.b)
    colors[#colors] = wx.wxColour(color.r*255, color.g*255, color.b*255)
    pen:SetColour(colors[#colors])
    mdc:SetTextForeground(colors[#colors])
  end,
  pushColor = function (self, color)
    log("Push color", color.r, color.g, color.b)
    table.insert(colors, wx.wxColour(color.r*255, color.g*255, color.b*255))
    pen:SetColour(colors[#colors])
    mdc:SetTextForeground(colors[#colors])
  end,
  popColor = function (self)
    log("Pop color")
    table.remove(colors)
    pen:SetColour(colors[#colors])
    mdc:SetTextForeground(colors[#colors])
  end,
  outputHbox = function (value,w)
    local buf = {}
    for i=1,#(value.glyphString) do
      buf[#buf+1] = value.glyphString[i]
    end
    buf = table.concat(buf, " ")
    log("T", buf, "("..value.text..")")

    mdc:SelectObject(bitmap)
    mdc:SetFont(font)
    mdc:DrawText(value.text, l2d(cx), l2d(cy)-fontadj)
    mdc:SetFont(wx.wxNullFont)
    mdc:SelectObject(wx.wxNullBitmap)
  end,
  setFont = function (options)
    local weightnormal = 200
    if f ~= SILE.font._key(options) then
      f = SILE.font._key(options)
      local face = SILE.font.cache(options, SILE.shaper.getFace)
      font = wx.wxFont(options.size-2, wx.wxFONTFAMILY_DEFAULT,
        options.style == "italic" and wx.wxFONTSTYLE_ITALIC or
        (options.style == "slant" and wx.wxFONTSTYLE_SLANT or wx.wxFONTSTYLE_NORMAL),
        options.weight == weightnormal and wx.wxFONTWEIGHT_NORMAL or
        (options.weight > weightnormal and wx.wxFONTWEIGHT_BOLD or wx.wxFONTWEIGHT_LIGHT),
        false, face.family, wx.wxFONTENCODING_DEFAULT)
      local w, h, descent, leading = mdc:GetTextExtent("Text", font)
      fontadj = h-descent-leading-2
      log("Set font ", mdc:GetTextExtent("Text", font), SILE.font._key(options), (options.font ~= face.family and " => "..face.family or ""))
    end
  end,
  drawImage = function (src, x,y,w,h)
    log("Draw image", src, x, y, w, h)

    local image = wx.wxImage()
    if not image:LoadFile(src) then return end
    image:Rescale(l2d(w),l2d(h))
    mdc:SelectObject(bitmap)
    mdc:DrawBitmap(wx.wxBitmap(image), l2d(x), l2d(y), true)
    mdc:SelectObject(wx.wxNullBitmap)
  end,
  imageSize = function (src)
    local image = wx.wxImage()
    if not image:LoadFile(src) then return end
    return image:GetWidth(), image:GetHeight()
  end,
  moveTo = function (x,y)
    if x ~= cx then log("Mx ",string.format("%.5f",x)); cx = x end
    if y ~= cy then log("My ",string.format("%.5f",y)); cy = y end
  end,
  rule = function (x,y,w,d)
    log("Draw line", x, y, w, d)
    mdc:SelectObject(bitmap)
    pen:SetWidth(l2d(d))
    mdc:SetPen(pen)
    mdc:DrawLine(l2d(x), l2d(y), l2d(x+w), l2d(y))
    if not linux then mdc:SetPen(wx.wxNullPen) end
    mdc:SelectObject(wx.wxNullBitmap)
  end,
  debugFrame = function (self,f)
  end,
  debugHbox = function(typesetter, hbox, scaledWidth)
  end
}

SILE.outputter = SILE.outputters.wxlua
