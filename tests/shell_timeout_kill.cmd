-- SYSTEM command that exceeds its timeout must raise Script_Error
OPTIONS SHELLTIMEOUT 1
SYSTEM "sleep 3"
QUIT
