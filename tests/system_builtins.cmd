REM F30: the command runs under a shell, so builtins and lists work.
SYSTEM "cd /tmp && pwd"
SYSTEM "exit 7"
SYSTEM "echo after exit"
