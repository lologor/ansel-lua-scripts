--[[
    This file is part of darktable,
    copyright (c) 2016 Tobias Jakobs

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

USAGE
* require to have install wine and Nik tools into default folder, anyway you mus update app path
BdM5959
]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
local dtsys = require "lib/dtutils.system"


dt.print_error("Alles klar...")
-- module name
local MODULE_NAME = "nikCollection"

--local silver_widget = nil

--OS compatibility
local PS = dt.configuration.running_os == "windows" and  "\\"  or  "/"

--API compatibility
du.check_min_api_version("5.0.0", "nikCollection") 

-- instance of DT tiff exporter
local tiff_exporter = dt.new_format("tiff")
tiff_exporter.bpp = 16
tiff_exporter.max_height = 0
tiff_exporter.max_width = 0

-- Tell gettext where to find the .mo file translating messages for a particular domain
local gettext = dt.gettext
gettext.bindtextdomain(MODULE_NAME, dt.configuration.config_dir..PS.."lua"..PS.."locale"..PS)
local function _(msgid)
    return gettext.dgettext(MODULE_NAME, msgid)
end

local function group_if_not_member(img, new_img)
  local image_table = img:get_group_members()
  local is_member = false
  for _,image in ipairs(image_table) do
    dt.print_log(image.filename .. " is a member")
    if image.filename == new_img.filename then
      is_member = true
      dt.print_log("Already in group")
    end
  end
  if not is_member then
    dt.print_log("group leader is "..img.group_leader.filename)
    new_img:group_with(img.group_leader)
    dt.print_log("Added to group")
  end
end

local function show_status(storage, image, format, filename,
  number, total, high_quality, extra_data)
    dt.print(string.format(_("Export Image %i/%i"), number, total))
end


local function Nik_Edit()
	local images = dt.gui.selection() --dt.gui.action_images--
	local target_dir
	local curr_image = ""
	local tmp_name = os.tmpname()
	local tmp_exported=tmp_name..".tif"
        local NewFileName= ""
        if dt.configuration.running_os == "windows" then
          tmp_exported = dt.configuration.tmp_dir .. tmp_exported -- windows os.tmpname() defaults to root directory
        end
        local f = io.open(tmp_exported, "w")
	    if not f then
	      dt.print(string.format(_("Error writing to `%s`"), tmp_exported))
	      os.remove(tmp_exported)
	      return
	    end
   --wine
  local wine_executable = df.check_if_bin_exists("wine")

  if not wine_executable then
    dt.print_error(_("wine not found"))
    return
  end

  if dt.configuration.running_os == "macos" then
    wine_executable = "open -W -a " .. wine_executable
  end

	for i_, i in pairs(images) do 
		target_dir=i.path..PS
		curr_image = i.path..PS..i.filename
 
        	tiff_exporter:write_image(i, tmp_exported, false)
 		f:write(tmp_exported.."\n")
		f:close()
 
                local j=string.len(curr_image)-4
                NewFileName=string.sub(curr_image, 1,j)..".tif"
                dt.print(_("Launching Nik tool..."))

                local wineNikSilverStartCommand
                wineNikSilverStartCommand = wine_executable .. " " ..Nik2run.. " " .. tmp_exported

                dt.print_log(wineNikSilverStartCommand)
                dtsys.external_command(wineNikSilverStartCommand)

                local myimage_name = NewFileName

                while df.check_if_file_exists(myimage_name) do
                 	myimage_name = df.filename_increment(myimage_name)
      			-- limit to 99 more exports of the original export
      			if string.match(df.get_basename(myimage_name), "_(d-)$") == "99" then
        			break
      			end
    		end

                dt.print_log("moving " .. tmp_exported .. " to " .. myimage_name)
                local result = df.file_move(tmp_exported, myimage_name)

		    if result then
		      dt.print_log("importing file")
		      local myimage = dt.database.import(myimage_name)

		      group_if_not_member(i, myimage)

		      for _,tag in pairs(dt.tags.get_tags(i)) do
			if not (string.sub(tag.name,1,9) == "darktable") then
			  dt.print_log("attaching tag")
			  dt.tags.attach(tag,myimage)
			end
		      end
		    end
		--clean tmp file
		os.remove(tmp_name)
		os.remove(tmp_exported)
	end
end


--register
Nik2run=""

local Nikcombo = dt.new_widget("combobox"){label = "Nik tools", tooltip = _("Select Nik tools to run"),value = 1, "Dfine", "Color Fx", "Silver Fx", "Pre-sharpener", "Sharpener", "Viveza", "Analog Fx",
  changed_callback = function(selection)
    if (selection.value == "Dfine") then
      Nik2run="'c:/Program Files/Google/Nik Collection/Dfine 2/Dfine 2 (64-Bit)/Dfine2.exe'"
    elseif (selection.value == "Color Fx") then
      Nik2run="'c:/Program Files/Google/Nik Collection/Color Efex Pro 4/Color Efex Pro 4 (64-Bit)/Color Efex Pro 4.exe'"
    elseif (selection.value == "Silver Fx") then
      Nik2run="'c:/Program Files/Google/Nik Collection/Silver Efex Pro 2/Silver Efex Pro 2 (64-Bit)/Silver Efex Pro 2.exe'"
    elseif (selection.value == "Pre-sharpener") then
      Nik2run="'c:/Program Files/Google/Nik Collection/Sharpener Pro 3/Sharpener Pro 3 (64-Bit)/SHP3RPS.exe'"
    elseif (selection.value == "Sharpener") then
      Nik2run="'c:/Program Files/Google/Nik Collection/Sharpener Pro 3/Sharpener Pro 3 (64-Bit)/SHP3OS.exe'"
    elseif (selection.value == "Viveza") then
      Nik2run="'c:/Program Files/Google/Nik Collection/Viveza 2/Viveza 2 (64-Bit)/Viveza 2.exe'"
    elseif (selection.value == "Analog Fx") then
      Nik2run="'c:/Program Files/Google/Nik Collection/Analog Efex Pro 2/Analog Efex Pro 2 (64-Bit)/Analog Efex Pro 2.exe'"
    end
  end
}

dt.register_lib(
  MODULE_NAME,        -- Module name
  _("Nik Collection"),       -- name
  true,                -- expandable
  false,               -- resetable
  {[dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_RIGHT_CENTER", 100}},   -- containers
  dt.new_widget("box")
  {
    orientation = "vertical",
    
    Nikcombo,    
    
    dt.new_widget("button")
    {
      label = _("Open Image"),
      tooltip = _("Select an image to open"),
      clicked_callback = Nik_Edit
    },
  },
  nil,-- view_enter
  nil -- view_leave
)


