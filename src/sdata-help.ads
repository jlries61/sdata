--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  Package SData.Help — HELP command dispatcher.
--
--  All command and function reference text lives here.  The interpreter
--  delegates every Stmt_HELP statement to Print_Help; this package owns
--  the content and the lookup logic so that adding a new command or
--  function requires only adding one procedure and one table entry here,
--  with no changes to the interpreter.

package SData.Help is

   --  Display help for Topic (case-insensitive).
   --    Topic = ""     prints the command/function index.
   --    Topic = "/ALL" prints the full reference in two sections
   --                   (commands then functions).
   --    Any other key  prints the detail entry for that command/function,
   --                   or an error message if the topic is unknown.
   procedure Print_Help (Topic : String);

end SData.Help;