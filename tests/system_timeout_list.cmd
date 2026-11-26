REM F30: on timeout the whole command list is stopped; "done" never prints.
OPTIONS SHELLTIMEOUT 1
SYSTEM "sleep 5; echo done"
