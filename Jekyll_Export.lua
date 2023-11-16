--[[
  Laurent Perraut - Export for Jekyll 

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
    Laurent Perraut - Export for Jekyll 

    This script provides a new target storage "Export for Jekyll".
    Images will be exported and all necessary files for Jekyll will be  
    automatically created.

  USAGE
    * require this script from main lua file
    * from "export selected", choose "Export for Jekyll"
    * Give a name to the gallery
    * configure other export options (size, etc.)
    * export

  CAVEATS
    None

  BUGS, COMMENTS, SUGGESTIONS
    send to Laurent Perraut, laurent.perraut.lp@gmail.com

  CHANGES
    * 20230805 - initial version
]]

local dt =    require "darktable"
local du =    require "lib/dtutils"
local df =    require "lib/dtutils.file"
local dtsys = require "lib/dtutils.system"
local lu =    require "lpc/lpcutils"

-- OS compatibility
local OS = dt.configuration.running_os
local PS = OS == "windows" and  "\\"  or  "/"

-- Consts
local MODULE_NAME   = "JekyllExport"
local GALLERY_INCLUDE  = [[
  <script src="{{ "/assets/lightbox-plus-jquery.min.js" | relative_url }}"></script>
  <ul class="photo-gallery">
    {%%- for image in site.%s -%%}
      <li>
        <a href="{{ image.image_path }}" data-lightbox="roadtrip" data-title="{{ image.title }} ({{ image.model }} - ISO {{ image.iso }} - {{ image.focal_length }})">
            <div class="img-container">
                <img src="{{ image.image_path }}" alt="{{ image.title }}" /><br>
            </div>
            {{ image.title }}                
        </a>
      </li>
    {%%- endfor -%%}
  </ul>
]]
local GALLERY_MD = [[
---
title: %s
description: %s
image: %s
featured: %i
---
]]
local GALLERY_PAGE = [[
---
layout: default
---
%s
{%% include gallery-%s.html %%}
]]
local COLLECTION_PATH = "galleries"
local GALLERIES_PATH = COLLECTION_PATH..PS.."_galleries"
local IMAGES_PATH = "images"
local INCLUDE_PATH = "_includes"
local FEATURE_TAG = "perraut.net|featured"
local DESCRIPTION_TAG = "perraut.net|description"

-- check API version
du.check_min_api_version("5.0.0", MODULE_NAME)

-- translation
local gettext = dt.gettext
gettext.bindtextdomain(MODULE_NAME, dt.configuration.config_dir..PS.."lua"..PS.."locale"..PS)
local function _(msgid)
  return gettext.dgettext(MODULE_NAME, msgid)
end

-- variables

local output_folder_selector = dt.new_widget("file_chooser_button"){
  title = _("select output folder"),
  tooltip = _("select output folder - disabled with CI (collection import) workflow step"),
  value = dt.preferences.read(MODULE_NAME, "output_folder", "string"),
  is_directory = true,
  sensitive = true,
  changed_callback = function(self)
    dt.preferences.write(MODULE_NAME, "output_folder", "string", self.value)
  end
  }

local gallery_text = dt.new_widget("entry"){
  tooltip = _("Give a name to the gallery"),
  editable = true
}

--Helper functions
local function remove_existing(fname)
  if df.check_if_file_exists(fname) then os.remove(fname) end
end

-------------------------------------------------------------------------------
-- EXPORT STORAGE -------------------------------------------------------------
-------------------------------------------------------------------------------

local function initialize(storage, img_format, image_table, hq, data)
  
  -- Create export folder
  local tname = output_folder_selector.value
  local gname = gallery_text.text
  local fname = df.sanitize_filename(tname)
  if not df.check_if_file_exists(fname) then df.mkdir(fname) end

  fname = df.sanitize_filename(tname..PS..COLLECTION_PATH..PS.."_"..gname)
  if df.check_if_file_exists(fname) then df.rmdir(fname) end
  df.mkdir(fname)
  fname = df.sanitize_filename(tname..PS..IMAGES_PATH..PS..gname)
  if df.check_if_file_exists(fname) then df.rmdir(fname) end
  df.mkdir(fname)

  -- Create include html file
  fname = tname..PS..INCLUDE_PATH..PS.."gallery-"..gname..".html"
  remove_existing(fname)
  local f, err = io.open(fname, "w")
  if f then
    f:write(string.format(GALLERY_INCLUDE, gname))
    f:close()
  else
    dt.print_log("Error creating "..fname..": "..err)
  end

end

-- temp export formats: tif only is supported
local function supported(storage, img_format)
  return (img_format.extension == "jpg")
end

local function store(storage, image, output_fmt, output_file, number, total, hq, data)

  local tname = output_folder_selector.value
  local gname = gallery_text.text
  local iname = "image_"..string.format("%03d", number)
  local fname
  local f
  local err

  -- Create gallery md file - take title and description of main picture (notes and description fields)
  -- Check tags
  local featured = 0
  local title = ""
  local description = ""
  local tags = image:get_tags()
  for key, tag in pairs(tags) do
    if tag.name == FEATURE_TAG then featured = tonumber(image.notes:sub(1,string.len(image.notes)))
    elseif tag.name == DESCRIPTION_TAG then
      local t = du.split(image.description, "|")
      title = t[1]
      description = t[2]
    end
  end

  if (title ~= "") then
    fname = tname..PS..GALLERIES_PATH..PS..gname..".md"
    remove_existing(fname)
    f, err = io.open(fname, "w")
    if f then
      f:write(string.format(GALLERY_MD, title, description, "/images/"..gname.."/"..iname..".jpg", featured))
      f:close()
    else
      dt.print_log("Error creating "..fname..": "..err)
    end
    -- Create gallery page
    fname = tname..PS..COLLECTION_PATH..PS..gname..".md"
    remove_existing(fname)
    f, err = io.open(fname, "w")
    if f then
      f:write(string.format(GALLERY_PAGE, description, gname))
      f:close()
    else
      dt.print_log("Error creating "..fname..": "..err)
    end

  end

  -- Create md file
  fname = tname..PS..COLLECTION_PATH..PS.."_"..gname..PS..iname..".md"
  remove_existing(fname)
  dt.print_log("Create md-file: "..fname)
  f, err = io.open(fname, "w")
  if f then
    f:write("---\n")
    f:write("image_path: /images/"..gname.."/"..iname..".jpg\n")
    f:write("title: "..image.title.."\n")
    f:write("maker: "..image.exif_maker.."\n")
    f:write("model: "..image.exif_model.."\n")
    f:write("lens: "..image.exif_lens.."\n")
    f:write("focal_length: "..string.format("%dmm", image.exif_focal_length).."\n")
    f:write("iso: "..string.format("%d", image.exif_iso).."\n")
    f:write("datetime: "..image.exif_datetime_taken.."\n")
    f:write("---\n")
    f:close()
  else
    dt.print_log("Error creating "..fname..": "..err)
  end

  -- Move to images destination path
  fname = tname..PS..IMAGES_PATH..PS..gname..PS..iname..".jpg"
  remove_existing(fname)
  success = df.file_move(output_file, fname)
  if not success then
    dt.print_log("Move to images folder ("..tname..") failed")
  end
end

local function finalize(storage, image_table, data)

    -- run through image list
    -- for image, exp_img in pairs(image_table) do
    -- end
end

-- new widgets ----------------------------------------------------------------
local storage_widget = dt.new_widget("box") {
  orientation = "vertical",
  output_folder_selector,
  dt.new_widget("box") {
    orientation = "horizontal",
    dt.new_widget("label") {
      label = "Gallery"
    },
    gallery_text
  },
  gallery_text
}

-- register new storage -------------------------------------------------------
dt.register_storage("JKexp", "Export for Jekyll", store, nil, supported, initialize, storage_widget)

-- Main
-- Setup last choices

-- end of script --------------------------------------------------------------

-- vim: shiftwidth=2 expandtab tabstop=2 cindent syntax=lua
-- kate: hl Lua;
