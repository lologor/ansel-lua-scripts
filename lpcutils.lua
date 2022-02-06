--[[
  Laurent Perraut - Some utility functions

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
    Laurent Perraut - Utility functions

  REQUIRED SOFTWARE
    n/a

  USAGE
    n/a

  EXAMPLE
    n/a

  CAVEATS
    None

  BUGS, COMMENTS, SUGGESTIONS
    send to Laurent Perraut, laurent.perraut.lp@gmail.com

  CHANGES
    * 20210807 - initial version
]]


function tokenize(s)
  tokens = {}
  for substring in s:gmatch("%S+") do
    table.insert(tokens, substring)
  end
  return tokens
end

function os.capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
  return s
end
