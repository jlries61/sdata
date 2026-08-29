-- A bad ECHO line must abort the whole script cleanly, not leave the
-- lexer's peeked-token cache in a state that mis-parses the following
-- statement as part of ECHO's argument. SYSTEM is Immediate, so its
-- "SHOULD_NOT_APPEAR" marker would print immediately if execution ever
-- reached it.
ECHO BOGUS
SYSTEM "echo SHOULD_NOT_APPEAR"
QUIT
