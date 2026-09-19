-- Option A (semicolon cleanup): a stray ";" after ARRAY (bare ARRAY lists arrays; the ';' must not be silently swallowed) must stay a syntax error.
ARRAY ;
QUIT
