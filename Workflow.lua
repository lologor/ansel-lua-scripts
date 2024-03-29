--[[
  Laurent Perraut - Export workflow 

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
    Laurent Perraut - Export workflow 

    This script provides a new target storage "Export workflow".
    Images exported will be exported with a given PPI value.
    The inmage can be processed with one or more workflow steps.
    THere are a number of pre-defined steps as well.

  USAGE
    * require this script from main lua file
    * from "export selected", choose "Export workflow"
    * choose a paper format optimzied for 3x2 formats
    * select your (NikCollection) workflow:
      SIZE = Determine export size (hard coded)
      PPI = Set ppi for the desired print size (hard coded)
      EXIF = TRansfer EXIF data (hard coded)
      DF = Dfine
      CE = Color Efex
      SE = Silver Efex
      PS = Sharpener Pro - Pre-sharpener
      OS = Sharpener Pro - Output sharpener
      VI = Viveza
      AE = Analog Efex
      CI = Import into collection - Built-in workflow step
      
      Workflow syntax is for example "Name:SE,GR,OS". You can choose between 3 workflows
    * configure quality, jpg 8bpp (good quality)
      and tif 16bpp (best quality) are supported
    * configure other export options (size, etc.)
    * export

  CAVEATS
    None

  BUGS, COMMENTS, SUGGESTIONS
    send to Laurent Perraut, laurent.perraut.lp@gmail.com

  CHANGES
    * 20200806 - initial version
]]

local dt =    require "darktable"
local du =    require "lib/dtutils"
local df =    require "lib/dtutils.file"
local dtsys = require "lib/dtutils.system"
local lu =    require "lpc/lpcutils"

-- Consts
local MODULE_NAME   = "ExportWorkflow"
local MAX_WORKFLOWS = 3

-- check API version
du.check_min_api_version("5.0.0", MODULE_NAME)

-- OS compatibility
local OS = dt.configuration.running_os
local PS = OS == "windows" and  "\\"  or  "/"

-- translation
local gettext = dt.gettext
gettext.bindtextdomain(MODULE_NAME, dt.configuration.config_dir..PS.."lua"..PS.."locale"..PS)
local function _(msgid)
  return gettext.dgettext(MODULE_NAME, msgid)
end

-- variables
local target_width = 0
local workflows = {}
local workflow_steps = {}
local papers = {}
local ppi

local function has_collection_import(workflow)
    local steps = du.split(workflows[workflow],",")
    for i, step in ipairs(steps) do
      step = step:gsub("^%s*(.-)%s*$", "%1")
      if step == "CI" then return true end
    end
    return false
end

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

local paper_combobox = dt.new_widget("combobox") {
    label = _("paper: "),
    changed_callback = function(self)
      dt.preferences.write(MODULE_NAME, "pp_lastchoice", "integer", self.selected)
    end
}

local workflow_combobox = dt.new_widget("combobox") {
    label = _("workflow: "),
    tooltip = _("select workflow"),
    changed_callback = function(self)
      dt.preferences.write(MODULE_NAME, "wf_lastchoice", "integer", self.selected)
      self.tooltip = "workflow steps: "..workflows[self.value]
    end
}

local function load_workflows(file)
  local lastchoice, step_name, workflow_name, paper_name
  if df.check_if_file_exists(file) then
    local lines = {}
    local w = 0
    local p = 0
    workflow_steps = {}
    workflows = {}
    papers = {}
    -- reset comboboxes
    if #workflow_combobox > 0 then 
      for j = #workflow_combobox,1,-1 do workflow_combobox[j] = nil end 
    end
    if #paper_combobox > 0 then 
      for j = #paper_combobox,1,-1 do paper_combobox[j] = nil end
    end

    -- read file linewise
    local mode = ""
    for line in io.lines(file) do
      -- check category [steps], [workflows], ...
      if line:sub(1,1) == "[" then mode = line:sub(2,line:find("]")-1):lower()
      elseif line:len() > 2 then
        if mode == "steps" then
          step_name = du.split(du.split(line,"=")[1], ":")
          workflow_steps[step_name[1]] = du.split(line,"=")[2]
        elseif mode == "workflows" then
          workflow_name = du.split(line,":")[1]
          workflows[workflow_name] = du.split(line,":")[2]:gsub("^%s*(.-)%s*$", "%1")
          w = w + 1
          workflow_combobox[w] = workflow_name
        elseif mode == "papers" then
          paper_name = du.split(line,":")[1]
          papers[paper_name] = du.split(line,":")[2]
          p = p + 1
          paper_combobox[p] = paper_name
        end
      end
    end

    -- Check last choice (workflows)
    lastchoice = dt.preferences.read(MODULE_NAME, "wf_lastchoice", "integer")
    if lastchoice == 0 and w > 0 then lastchoice = 1 end
    if lastchoice > w then lastchoice = w end
    dt.preferences.write(MODULE_NAME, "wf_lastchoice", "integer", lastchoice)
    workflow_combobox.selected = lastchoice
    workflow_combobox.tooltip = "workflow steps: "..workflows[workflow_combobox.value]
    -- Check last choice (papers)
    lastchoice = dt.preferences.read(MODULE_NAME, "pp_lastchoice", "integer")
    if lastchoice == 0 and p > 0 then lastchoice = 1 end
    if lastchoice > p then lastchoice = p end
    dt.preferences.write(MODULE_NAME, "pp_lastchoice", "integer", lastchoice)
    paper_combobox.selected = lastchoice 
    
  else
    dt.print_error("Workflows file could not be opened!")
  end
end

local workflows_file_chooser = dt.new_widget("file_chooser_button")
{
  title = _("Select the file containing workflow steps"),  -- The title of the window when choosing a file
  tooltip = _("select the file containing workflow steps"),
  value = dt.preferences.read(MODULE_NAME, "workflows_file", "string"),
  is_directory = false,              -- True if the file chooser button only allows directories to be selecte
  changed_callback = function(self)
    dt.preferences.write(MODULE_NAME, "workflows_file", "string", self.value)
    load_workflows(self.value)
  end
}

-- Load workflow step file
if workflows_file_chooser.value ~= nil then load_workflows(workflows_file_chooser.value) end

-------------------------------------------------------------------------------
-- EXPORT STORAGE -------------------------------------------------------------
-------------------------------------------------------------------------------

-- temp export formats: tif only is supported
local function supported(storage, img_format)
  return (img_format.extension == "tif")
end

local function store(storage, image, output_fmt, output_file)

  local run_cmd, result, ppi, path, step_cmd
  
  dt.print_log("Output file: "..output_file)
  local steps = du.split(workflows[workflow_combobox.value],",")
  
  -- main workflow loop
  for i, step in ipairs(steps) do
    step = step:gsub("^%s*(.-)%s*$", "%1")
    step_cmd = workflow_steps[step]
    dt.print("Proceed with "..step.." on "..image.filename)
    dt.print_log("Proceed with "..step.." on "..image.filename)
    path = df.split_filepath(output_file)
    -- hard coded steps
    if step:sub(1,2) == "CI" then   -- built-in workflow step for collection import
      run_cmd = ""
    elseif step:sub(1,3) == "PPI" then -- built-in workflow step for setting PPI
      run_cmd = string.format(step_cmd, output_file, ppi, ppi, output_file)
    elseif step:sub(1,4) == "EXIF" then -- built-in workflow step for exif transfer
      run_cmd = string.format(step_cmd, image.path .. PS .. image.filename, output_file)
    -- configurable steps
    else
      run_cmd = string.format(step_cmd, output_file)
    end

    -- Execute workflow step
    if run_cmd ~= "" then
      dt.print_log(_(step..": "..run_cmd))
      result = dtsys.external_command(run_cmd)
      if result ~= 0 then
          dt.print(_("Error executing "..step.."!"))
          if df.check_if_file_exists(output_file) then os.remove(output_file) end
          return
      end
      -- Rest of work for (some) built-in workflow steps
      if step:sub(1,4) == "SIZE" then -- built-in workflow step for getting the output file size in pixels (widthxheight)
        local file = step_cmd:sub(step_cmd:find(">") + 2, #step_cmd - 1) -- remove last character
        target_width = papers[paper_combobox.value]
        for line in io.lines(file) do
          local wh = du.split(line,"x")
          if wh[1] >= wh[2] then
            ppi = wh[1] / (target_width / 25.4)
          else
            ppi = wh[2] / (target_width / 25.4)
          end
          ppi = ppi + 0.5 - (ppi + 0.5) % 1
        end
      end
    end
  end
end

local function finalize(storage, image_table, data)
  -- output path variables
  local tname, success
  -- collection import variables
  local new_name, new_image, tags
  -- check workflow
  local coll_import = has_collection_import(workflow_combobox.value)

  -- run through image list
  for image, exp_img in pairs(image_table) do
  
    if coll_import then
      -- create unique filename
      new_name = image.path..PS..df.get_filename(exp_img)
      new_name = df.create_unique_filename(new_name)

      -- copy image to collection folder, check result, return if error
      success = df.file_copy(exp_img, new_name)
      if not success then
        dt.print(_("error copying file ")..exp_img)
        return
      end

      -- import in database and group
      new_image = dt.database.import(new_name)
      new_image:group_with(image.group_leader)

      -- clean tags
      tags = dt.tags.get_tags(new_image)
      for i, tag in ipairs(tags) do
        dt.tags.detach(tag, new_image)
      end
      tags = dt.tags.get_tags(image)
      for i, tag in ipairs(tags) do
        dt.tags.attach(tag, new_image)
      end

      -- transfer metadata
      new_image.publisher = image.publisher
      new_image.title = image.title
      new_image.creator = image.creator
      new_image.rights = image.rights
      new_image.description = image.description
      new_image.notes = image.notes
      new_image.rating = image.rating
      new_image.red = image.red
      new_image.blue = image.blue
      new_image.green = image.green
      new_image.yellow = image.yellow
      new_image.purple = image.purple

    -- just copy file to destination
    else
      tname = df.sanitize_filename(output_folder_selector.value..PS..df.get_filename(exp_img))
      if df.check_if_file_exists(tname) then
        os.remove(tname)
      end
      success = df.file_copy(exp_img, tname)
      if not success then
        dt.print(_("error copying file ")..tname)
        return
      end
    end
  end
end

-- new widgets ----------------------------------------------------------------

local storage_widget = dt.new_widget("box") {
  orientation = "vertical",
  workflows_file_chooser,
  output_folder_selector,
  paper_combobox,
  workflow_combobox
}

-- register new storage -------------------------------------------------------
dt.register_storage("expWF", "Export workflow", store, finalize, supported, nil, storage_widget)

-- Main
-- Setup last choices
local pp_lastchoice = dt.preferences.read(MODULE_NAME, "pp_lastchoice", "integer")
if pp_lastchoice == 0 then pp_lastchoice = 2 end
paper_combobox.selected = pp_lastchoice

-- end of script --------------------------------------------------------------

-- vim: shiftwidth=2 expandtab tabstop=2 cindent syntax=lua
-- kate: hl Lua;
