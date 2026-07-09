--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  SData.Version — version and copyright constants for the sdata
--  application.  Kept separate from sdata-core because sdata-core has
--  its own version lifecycle (see sdata-core/alire.toml) and is
--  consumed by other applications (e.g., data-vandal) at their own
--  versions.

package SData.Version is

   Version_Major : constant Natural := 0;
   Version_Minor : constant Natural := 13;
   Version_Patch : constant Natural := 3;
   Version_Str   : constant String :=
      Natural'Image (Version_Major)
         (2 .. Natural'Image (Version_Major)'Last) & "." &
      Natural'Image (Version_Minor)
         (2 .. Natural'Image (Version_Minor)'Last) & "." &
      Natural'Image (Version_Patch)
         (2 .. Natural'Image (Version_Patch)'Last);

   Copyright_Str : constant String :=
      "Copyright (C) 2026 John L. Ries <john@theyarnbard.com>";

   Copyright_Notice : constant String :=
      "SData version " & Version_Str & ASCII.LF &
      Copyright_Str & ASCII.LF & ASCII.LF &
      "This program is free software: you can redistribute it and/or "
      & "modify" & ASCII.LF &
      "it under the terms of the GNU General Public License as "
      & "published by" & ASCII.LF &
      "the Free Software Foundation, either version 3 of the License, or"
      & ASCII.LF &
      "(at your option) any later version." & ASCII.LF & ASCII.LF &
      "This program is distributed in the hope that it will be useful,"
      & ASCII.LF &
      "but WITHOUT ANY WARRANTY; without even the implied warranty of"
      & ASCII.LF &
      "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the"
      & ASCII.LF &
      "GNU General Public License for more details." & ASCII.LF & ASCII.LF
      &
      "You should have received a copy of the GNU General Public License"
      & ASCII.LF &
      "along with this program. If not, see "
      & "<https://www.gnu.org/licenses/>.";

end SData.Version;
