--[[
  ext_editor.lua - edit images with external editors
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
    RT_Demoz.lua - Demosaicing with RawTherappe and profile application
    This script provides helpers to edit image files with programs external to darktable. It adds:
      - a new target storage "collection". Image exported will be reimported to collection for further edit with external programs
      - a new lighttable module "external editors", to select a program from a list of up to
      - 9 external editors and run it on a selected image (adjust this limit by changing MAX_EDITORS)
      - a set of lua preferences in order to configure name and path of up to 9 external editors
      - a set of lua shortcuts in order to quick launch the external editors
    
  USAGE
    * require this script from main lua file
  
    -- setup --
      * in "preferences/lua options" configure name and path/command of external programs
      * note that if a program name is left empty, that and all following entries will be ignored
      * in "preferences/shortcuts/lua" configure shortcuts for external programs (optional)
      * whenever programs preferences are changed, in lighttable/external editors, press "update list"
    -- use --
      * in the export dialog choose "collection" and select the format and bit depth for the
        exported image
      * press "export"
      * the exported image will be imported into collection and grouped with the original image
      
      * select an image for editing with en external program, and:
      * in lighttable/external editors, select program and press "edit"
      * edit the image with the external editor, overwite the file, quit the external program
      * the selected image will be updated
      or
      * in lighttable/external editors, select program and press "edit a copy"
      * edit the image with the external editor, overwite the file, quit the external program
      * a copy of the selected image will be created and updated
      or
      * in lighttable select target storage "collection"
      * enter in darkroom
      * to create an export or a copy press CRTL+E
      * use the shortcut to edit the current image with the corresponding external editor
      * overwite the file, quit the external program
      * the darkroom view will be updated
    
    * warning: mouseover on lighttable/filmstrip will prevail on current image
    * this is the default DT behavior, not a bug of this script
  CAVEATS
    * MAC compatibility not tested
  
  BUGS, COMMENTS, SUGGESTIONS
    * send to Marco Carrarini, marco.carrarini@gmail.com
]]


local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
local dtsys = require "lib/dtutils.system"


-- module name
local MODULE_NAME = "rt_demoz"

-- check API version
du.check_min_api_version("5.0.2", MODULE_NAME)  -- darktable 3.x


-- OS compatibility
local PS = dt.configuration.running_os == "windows" and  "\\"  or  "/"

-- namespace
local ee = {}
ee.module_installed = false
ee.event_registered = false
ee.widgets = {}

-- translation
local gettext = dt.gettext
gettext.bindtextdomain(MODULE_NAME, dt.configuration.config_dir..PS.."lua"..PS.."locale"..PS)
local function _(msgid)
    return gettext.dgettext(MODULE_NAME, msgid)
end

-- number of valid entries in the list of external programs
local n_entries

-- last used editor initialization
if not dt.preferences.read(MODULE_NAME, "initialized", "bool") then
    dt.preferences.write(MODULE_NAME, "lastchoice", "integer", 0)
    dt.preferences.write(MODULE_NAME, "initialized", "bool", true)
end
local lastchoice = 0

-- update lists of program names and paths, as well as combobox ---------------
local function UpdatePP3List(combobox, button_edit, update_button_pressed) 
    -- initialize lists
    profile_names = {}

    -- build lists from profile UpdatePP3List
    local pp3_path = dt.configuration.config_dir..PS.."RT-profiles/"
    local ls_cmd = "ls"
    if dt.configuration.running_os == "macos" then
        pp3_path = "~/Library/Application Support/RawTherapee/config/profiles/"
    elseif dt.configuration.running_os == "windows" then
        pp3_path = "."
        ls_cmd = "dir /AD /B "
    end

    n_entries = 0
    local i = 1
    local p = io.popen(ls_cmd..' '..pp3_path:gsub(" ", "\\ "))
    for file in p:lines() do                         --Loop through all files
        combobox[i] = file
        profile_names[i] = pp3_path..file
        n_entries = i
        i = i+1
    end
    combobox[n_entries+1] = nil

    lastchoice = dt.preferences.read(MODULE_NAME, "lastchoice", "integer")
    if lastchoice == 0 and n_entries > 0 then lastchoice = 1 end
    if lastchoice > n_entries then lastchoice = n_entries end
    dt.preferences.write(MODULE_NAME, "lastchoice", "integer", lastchoice)

    -- widgets enabled if there is at least one program configured
    combobox.selected = lastchoice 
    local active = n_entries > 0
    combobox.sensitive = active
    button_edit.sensitive = active

    if update_button_pressed then dt.print(n_entries.._(" RawTherapee profiles found")) end
end

-- callback for buttons "edit" and "edit a copy" ------------------------------
local function OpenWith(images, choice)
    -- check choice is valid, return if not
    if choice > n_entries then
        dt.print(_("not a valid choice"))
        return
    end
    
    -- check if one image is selected, return if not
    if #images ~= 1 then
        dt.print(_("please select one image"))
        return
    end

    local run_cmd

    -- image to be edited
    local image
    i, image = next(images)
    local name = image.path..PS..image.filename

    -- save image tags, rating and color
    local tags = {}
    for i, tag in ipairs(dt.tags.get_tags(image)) do
        if not (string.sub(tag.name, 1, 9) == "darktable") then table.insert(tags, tag) end
    end
    local rating = image.rating
    local red = image.red
    local blue = image.blue
    local green = image.green
    local yellow = image.yellow
    local purple = image.purple

    -- new image
    local new_name = name
    local new_image = image

    new_name = df.create_unique_filename(df.chop_filetype(name)..".tif")

    run_cmd = string.format("rawtherapee-cli -o %s -p %s -b16 -tz -Y -c %s", new_name:gsub(" ", "\\ "), profile_names[choice]:gsub(" ", "\\ "), name:gsub(" ", "\\ "))
    if dt.configuration.running_os == "macos" then
        run_cmd = "/Applications/RawTherapee.app/Contents/MacOS/bin/"..run_cmd
    elseif dt.configuration.running_os == "windows" then
        run_cmd = string.format("rawtherapee-cli -o %s -p %s -b16 -tz -Y -c %s", new_name, profile_names[choice], name)
    end

    -- launch the external editor, check result, return if error
    dt.print(_("launching RawTherapee..."))
    local p = io.popen(run_cmd)
    for line in p:lines() do                         --Loop through all files
        dt.print_log(line)
    end

    -- import in database and group
    dt.print_log(new_name)
    new_image = dt.database.import(new_name)
    new_image:group_with(image)

    -- restore image tags, rating and color, must be put after refresh darkroom view
    for i, tag in ipairs(tags) do dt.tags.attach(tag, new_image) end
    new_image.rating = rating
    new_image.red = red
    new_image.blue = blue
    new_image.green = green
    new_image.yellow = yellow
    new_image.purple = purple

    -- select the new image
    local selection = {}
    table.insert(selection, new_image)
    dt.gui.selection (selection)
end


-- callback function for shortcuts --------------------------------------------
local function program_shortcut(event, shortcut)
    OpenWith(dt.gui.action_images, tonumber(string.sub(shortcut, -2)))
end

-- install the module in the UI
local function install_module()
    if not ee.module_installed then
        -- register new module "external editors" in lighttable ------------------------
        dt.register_lib(
            MODULE_NAME,
            _("demosaicing with rawtherapee"),
            true, -- expandable
            false,  -- resetable
            {[dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_RIGHT_CENTER", 100}},
            dt.new_widget("box") {
                orientation = "vertical",
                table.unpack(ee.widgets),
            },
            nil,  -- view_enter
            nil   -- view_leave
        )
        ee.module_installed = true
    end
end

-- combobox, with variable number of entries ----------------------------------
local combobox = dt.new_widget("combobox") {
    label = _("choose profile"), 
    tooltip = _("select the profile that will be used by RawTherapee"),
    changed_callback = function(self)
    dt.preferences.write(MODULE_NAME, "lastchoice", "integer", self.selected)
    end,
    ""
}


-- button edit ----------------------------------------------------------------
local button_edit = dt.new_widget("button") {
    label = _("create"),
    tooltip = _("Demosaicing with RawTherapee"),
    --sensitive = false,
    clicked_callback = function()
    OpenWith(dt.gui.action_images, combobox.selected)
    end
}

-- button update list ---------------------------------------------------------
local button_update_list = dt.new_widget("button") {
    label = _("update list"),
    tooltip = _("update list of profiles"),
    clicked_callback = function()
    UpdatePP3List(combobox, button_edit, true)
    end
}

-- box for the buttons --------------------------------------------------------
-- it doesn't seem there is a way to make the buttons equal in size
local box1 = dt.new_widget("box") {
    orientation = "horizontal",
    button_edit,
    button_update_list
}

table.insert(ee.widgets, combobox)
table.insert(ee.widgets, box1)

-- register new module "external editors" in lighttable ------------------------
if dt.gui.current_view().id == "lighttable" then
    install_module()
else
    if not ee.event_registered then
        dt.register_event(
            "view-changed",
            function(event, old_view, new_view)
                if new_view.name == "lighttable" and old_view.name == "darkroom" then
                    install_module()
                end
            end
        )
        ee.event_registered = true
    end
end

-- initialize list of programs and widgets ------------------------------------ 
UpdatePP3List(combobox, button_edit, false)

-- end of script --------------------------------------------------------------

-- vim: shiftwidth=2 expandtab tabstop=2 cindent syntax=lua
-- kate: hl Lua;
