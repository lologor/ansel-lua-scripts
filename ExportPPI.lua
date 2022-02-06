--[[
  Laurent Perraut - Set PPI by exporting files

  darktable is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  darktable is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with darktable.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[
  DESCRIPTION
    Laurent Perraut - Set PPI by exporting files

    This script provides a new target storage "Export with PPI".
    Images exported will be exported with a given PPI value

  REQUIRED SOFTWARE
    ImageMagick (convert)

  USAGE
    * require this script from main lua file
    * from "export selected", choose "Export with PPI"
    * configure PPI (by choosing a factor of 72 for Epson printers or choosing a paper format optimzied for 3x2 formats)
    * configure quality, jpg 8bpp (good quality)
      and tif 16bpp (best quality) are supported
    * configure other export options (size, etc.)
    * export

  EXAMPLE
    set PPI to a factor of 72 to prepare for printing with Epson(r) printers

  CAVEATS
    None

  BUGS, COMMENTS, SUGGESTIONS
    send to Laurent Perraut, laurent.perraut.lp@gmail.com

  CHANGES
    * 20200806 - initial version
]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
local dtsys = require "lib/dtutils.system"
local lu = require "lpc/lpcutils"

-- module name
local MODULE_NAME = "ExportPPI"

-- check API version
du.check_min_api_version("5.0.0", MODULE_NAME)

-- OS compatibility
local PS = dt.configuration.running_os == "windows" and  "\\"  or  "/"

-- translation
local gettext = dt.gettext
gettext.bindtextdomain(MODULE_NAME, dt.configuration.config_dir..PS.."lua"..PS.."locale"..PS)
local function _(msgid)
  return gettext.dgettext(MODULE_NAME, msgid)
end

-- initialize module preferences
if not dt.preferences.read(MODULE_NAME, "initialized", "bool") then
  dt.preferences.write(MODULE_NAME, "ppi", "string", "360")
end

-- temp export formats: jpg and tif are supported -----------------------------
local function supported(storage, img_format)
  return (img_format.extension == "jpg") or (img_format.extension == "tif")
end

-- export and print --------------------------------------------------
-- Forward declaration
local ppi, paper_combobox, postp

local function store(storage, image, output_fmt, output_file)

    local run_cmd, result

    dt.print_log("Output file: "..output_file)
    -- read parameters
    local imtool = dt.preferences.read(MODULE_NAME, "im_exe", "string")
    if imtool == "" then
        dt.print(_("ImageMagick tool executable not configured"))
        return
    end
    imtool = df.sanitize_filename(imtool)
    local imtool_args = dt.preferences.read(MODULE_NAME, "im_args", "string")

    -- Run the ImageMagick tool command
    dt.print(_("Set PPI to "..ppi.text))
    -- Difficult macos workaround
    if dt.configuration.running_os == "macos" then
        local file = io.open("/tmp/dt_exec.sh", "w+")
        file:write(string.format("%s -quiet %s -density %i %s", imtool, output_file, tonumber(ppi.text), output_file))
        file:close()
        run_cmd = "open -a " .. imtool .. " " .. imtool_args
    else
        run_cmd = imtool .. " " .. string.format(imtool_args, output_file, tonumber(ppi.text), output_file)
    end
    dt.print_log("Set PPI: "..run_cmd)

    result = dtsys.external_command(run_cmd)
    if result ~= 0 then
        dt.print(_("Error by setting PPI!"))
        return
    end
end

function finalize(storage, image_table, extra_data)
    local run_cmd, result

    local printtool = postp.text
    if printtool == "" then return end
    
    printtool = df.sanitize_filename(printtool)
    if dt.configuration.running_os == "macos" then
        printtool = "open -a " .. printtool
    end

    -- list of exported images
    local img_list
    -- file names
    local fname
    local tname
    local success
     -- reset and create image list
    img_list = ""
    local output_dir = dt.preferences.read(MODULE_NAME, "ppi_output", "string") 

    for _,exp_img in pairs(image_table) do
      fname = df.get_filename(exp_img)
      tname = output_dir .. PS .. fname
      if df.check_if_file_exists(tname) then
        os.remove(tname)
      end
      success = os.rename(exp_img, tname)
      tname = df.sanitize_filename(tname)
      img_list = img_list .. tname .. " "
    end

    -- Run print tool
    dt.print(_("Run print tool..."))
    run_cmd = printtool.." "..img_list
    dt.print_log("Run print tool: "..run_cmd)
    result = dtsys.external_command(run_cmd)
    if result ~= 0 then
        dt.print(_("Error by printing!"))
        return
    end
end

-- new widgets ----------------------------------------------------------------

local preview_file
local preview
local preview_width
local preview_height
local selected

local res_label = dt.new_widget("label")
local size_label = dt.new_widget("label")
size_label.label = _("width x height (mm): ")

local res = dt.new_widget("entry")
{
    text = "",
    editable = false,
    tooltip = _("Resolution in pixels"),
    reset_callback = function(self) self.text = "" end
}
local box_res = dt.new_widget("box") {
    orientation = "horizontal",
    res_label,
    res
}

local size = dt.new_widget("entry")
{
    text = "",
    editable = false,
    tooltip = _("Print size in millimeter"),
    reset_callback = function(self) self.text = "" end
}
local box_size = dt.new_widget("box") {
    orientation = "horizontal",
    size_label,
    size
}

local function compute_mm(i_ppi)
    -- check if one image is selected, return if not
    if #dt.gui.selection() < 1 then
      dt.print(_("please select one image"))
      return
    end

    local w, h, l
    if preview_width == nil then
        i, selected = next(dt.gui.selection())
        w = selected.width
        h = selected.height
        l = "original "
    else
        w = preview_width
        h = preview_height
        l = "preview "
    end
    size.text = string.format("%.2f x %.2f", 25.4 * w / i_ppi, 25.4 * h / i_ppi)
    res_label.label = _(l .. string.format("resolution (px): "))
    res.text = _(string.format("%i x %i", w, h))
end

local function select_paper(sel)
        -- Retrieve image resolution
        local w, iw, ih
        if preview_width == nil then
            i, selected = next(dt.gui.selection())
            iw = selected.width
            ih = selected.height
        else
            iw = preview_width
            ih = preview_height
        end
        if ih > iw then
            iw = ih
        end

        if sel == 1 then
            w = 186
        elseif sel == 2 then
            w = 261
        elseif sel == 3 then
            w = 369
        elseif sel == 4 then
            w = 462
        elseif sel == 5 then
            w = 522
        elseif sel == 6 then
            w = 648
        elseif sel == 7 then
            w = 310.8
        end
        ippi = iw / (w / 25.4)
        ppi.text = string.format("%i", ippi + 0.5 - (ippi + 0.5) % 1)
        compute_mm(ppi.text)
end

-- Main setup check_button
local setup_bt = dt.new_widget("button")
{
    label = _("load preview"),
    clicked_callback = function(self)
        -- variables
        local run_cmd, result

        -- check if one image is selected, return if not
        if #dt.gui.action_images ~= 1 then
            dt.print(_("Please select only one image"))
            return
        end
        dt.print(_("Create preview..."))
        local image
        i, image = next(dt.gui.action_images)
        -- Write temp jpeg file
        local jpg_format
        jpg_format = dt.new_format("jpeg")
        jpg_format.quality = 60.0
        jpg_format.max_width = 0.0
        jpg_format.max_height = 0.0
        preview_file = "/tmp/" .. image.filename .. "." .. jpg_format.extension
        if df.check_if_file_exists(preview_file) then
          os.remove(preview_file)
        end
        jpg_format.write_image(jpg_format, image, preview_file)
        -- Read image size
        dt.print(_("Analyze preview..."))
        run_cmd = "identify".." "..preview_file
        dt.print_log("Run identify(ImageMagick) tool: "..run_cmd)
        result = os.capture(run_cmd, true)
        wh = du.split(tokenize(result)[3],"x")
        preview_width = wh[1]
        preview_height = wh[2]
        select_paper(paper_combobox.selected)
        -- Cleanup
        os.remove(preview_file)
    end
}
local reset_bt = dt.new_widget("button")
{
    label = _("reset"),
    clicked_callback = function(self)
        preview_width = nil
        preview_height = nil
        compute_mm(ppi.text)
    end
}
local box_bts = dt.new_widget("box") {
    orientation = "horizontal",
    setup_bt,
    reset_bt
}

local ppi_label = dt.new_widget("label")
ppi_label.label = _("pixels per inch: ")
ppi = dt.new_widget("entry")
{
    text = "360",
    editable = true,
    tooltip = _("Enter here the PPI to compute the print size"),
    reset_callback = function(self) self.text = "360" end
}
local ppi_bt = dt.new_widget("button")
{
    label = _("in mm"),
    clicked_callback = function(self)
        compute_mm(ppi.text)
    end
}

local box_ppi = dt.new_widget("box") {
    orientation = "horizontal",
    ppi_label,
    ppi,
    ppi_bt
}

paper_combobox = dt.new_widget("combobox") {
    label = _("paper: "),
    selected = 2,
    "2x3 - DIN A5  - 12.0",
    "2x3 - DIN A4  - 18.0",
    "2x3 - DIN A3  - 25.5",
    "2x3 - DIN A3+ - 10.5",
    "2x3 - DIN A2  - 36.0",
    "2x3 - DIN A2+ - 00.0",
    "5x7 - 1/2 A3+ - 09.5",
    changed_callback = function(self)
      select_paper(self.selected)
    end
}

local box_paper = dt.new_widget("box") {
  orientation = "horizontal",
  paper_combobox
}

local postp_label = dt.new_widget("label")
postp_label.label = "postprocessing: "
postp = dt.new_widget("entry")
{
  text = "",
  editable = true,
  tooltip = "enter the postprecessing command",
  reset_callback = function(self) self.text = dt.preferences.read(MODULE_NAME, "printtool_exe", "string") end
}
local box_postp = dt.new_widget("box") {
  orientation = "horizontal",
  postp_label,
  postp
}


local storage_widget = dt.new_widget("box") {
  orientation = "vertical",
  box_bts,
  box_res,
  box_paper,
  box_ppi,
  box_size
  , box_postp
}

-- Event management
function handle_selchanged(event)
    if #dt.gui.selection() == 1 then
        local sel
        i, sel = next(dt.gui.selection())
        if sel ~= selected then
            selected = sel
            preview_width = nil
            compute_mm(ppi.text)
        end
    end
end

-- dt.register_event(MODULE_NAME, "mouse-over-image-changed", handle_moi)
dt.register_event(MODULE_NAME, "selection-changed", handle_selchanged)

-- register new storage -------------------------------------------------------
dt.register_storage("expPPI", "export for print", store, finalize, supported, nil, storage_widget)

-- register the new preferences -----------------------------------------------
dt.preferences.register(MODULE_NAME, "printtool_exe", "file",
 _("ExportPPI: Executable for print tool"),
 _("select executable for the print tool")  , "")
dt.preferences.register(MODULE_NAME, "im_args", "string",
 _("ExportPPI: Arguments for ImageMagick tool"),
 _("enter the arguments for the ImageMagick tool - %s will represent the file")  , "")
dt.preferences.register(MODULE_NAME, "im_exe", "file",
 _("ExportPPI: Executable for ImageMagick tool"),
 _("select executable for the ImageMagick tool")  , "")
dt.preferences.register(MODULE_NAME, "ppi_output", "directory",
 _("ExportPPI: Output directory"),
 _("select directory for file output")  , "")
 
-- Main
postp.text = dt.preferences.read(MODULE_NAME, "printtool_exe", "string")
 
-- set sliders to the last used value at startup ------------------------------
-- sigma_slider.value = dt.preferences.read(MODULE_NAME, "sigma", "float")
-- iterations_slider.value = dt.preferences.read(MODULE_NAME, "iterations", "float")
-- jpg_quality_slider.value = dt.preferences.read(MODULE_NAME, "jpg_quality", "float")

-- end of script --------------------------------------------------------------

-- vim: shiftwidth=2 expandtab tabstop=2 cindent syntax=lua
-- kate: hl Lua;
