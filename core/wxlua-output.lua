-- add pages (using pageup/down)
-- add zooming (using +/-)
--  how to zoom without redrawing everything? need to keep a log of calls for a page

if (not SILE.outputters) then SILE.outputters = {} end
local f
local cx
local cy

local frame, font, fontadj, bitmap

require 'wx'
local osname = wx.wxPlatformInfo.Get():GetOperatingSystemFamilyName()
local linux = osname == 'Unix'
local colors = {wx.wxBLACK}
local mdc = wx.wxMemoryDC()
local pen = wx.wxBLACK_PEN

local function OnPaint()
  -- must always create a wxPaintDC in a wxEVT_PAINT handler
  local dc = wx.wxPaintDC(frame)
  dc:DrawBitmap(bitmap, 0, 0, true)
  dc:delete() -- always delete any wxDCs created when done
end

local function l2d(v) return v*16/12 end

SILE.outputters.debug = {
  init = function()
    print("Open file", SILE.outputFilename)
    print("Set paper size ", SILE.documentState.paperSize[1],SILE.documentState.paperSize[2])
    print("Begin page")

    local w = math.floor(0.5+l2d(SILE.documentState.paperSize[1]))
    local h = math.floor(0.5+l2d(SILE.documentState.paperSize[2]))
    bitmap = wx.wxBitmap(w,h)
    frame = wx.wxFrame(
      wx.NULL, -- no parent for toplevel windows
      wx.wxID_ANY, -- don't need a wxWindow ID
      SILE.outputFilename,
      wx.wxDefaultPosition,
      wx.wxDefaultSize,
      wx.wxDEFAULT_FRAME_STYLE + wx.wxSTAY_ON_TOP - wx.wxRESIZE_BORDER - wx.wxMAXIMIZE_BOX)
    frame:SetClientSize(w, h)
    frame:Connect(wx.wxEVT_PAINT, OnPaint)
    frame:Connect(wx.wxEVT_ERASE_BACKGROUND, function () end) -- do nothing

    mdc:SelectObject(bitmap)
    mdc:Clear()
    mdc:SelectObject(wx.wxNullBitmap)
  end,
  newPage = function()
    print("New page")
  end,
  finish = function()
    print("End page")
    print("Finish")

    frame:Show()
    frame:Refresh()
    frame:Update()
    wx.wxGetApp():MainLoop()
  end,
  setColor = function(self, color)
    print("Set color", color.r, color.g, color.b)
    colors[#colors] = wx.wxColour(color.r*255, color.g*255, color.b*255)
    pen:SetColour(colors[#colors])
    mdc:SetTextForeground(colors[#colors])
  end,
  pushColor = function (self, color)
    print("Push color", color.r, color.g, color.b)
    table.insert(colors, wx.wxColour(color.r*255, color.g*255, color.b*255))
    pen:SetColour(colors[#colors])
    mdc:SetTextForeground(colors[#colors])
  end,
  popColor = function (self)
    print("Pop color")
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
    print("T", buf, "("..value.text..")")

    mdc:SelectObject(bitmap)
    mdc:SetFont(font)
    mdc:DrawText(value.text, l2d(cx), l2d(cy)-fontadj)
    mdc:SetFont(wx.wxNullFont)
    mdc:SelectObject(wx.wxNullBitmap)
  end,
  setFont = function (options)
    if f ~= SILE.font._key(options) then
      print("Set font ", SILE.font._key(options))
      f = SILE.font._key(options)
      font = wx.wxFont(options.size-2, wx.wxFONTFAMILY_MODERN, wx.wxFONTSTYLE_NORMAL,
        wx.wxFONTWEIGHT_NORMAL, false, options.font, wx.wxFONTENCODING_DEFAULT)
      local w, h, descent, leading = mdc:GetTextExtent("Text", font)
      fontadj = h-descent-leading-2
      print("Set font ", SILE.font._key(options), mdc:GetTextExtent("Text", font))
    end
  end,
  drawImage = function (src, x,y,w,h)
    print("Draw image", src, x, y, w, h)

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
    if x ~= cx then print("Mx ",string.format("%.5f",x)); cx = x end
    if y ~= cy then print("My ",string.format("%.5f",y)); cy = y end
  end,
  rule = function (x,y,w,d)
    print("Draw line", x, y, w, d)
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

SILE.outputter = SILE.outputters.debug
