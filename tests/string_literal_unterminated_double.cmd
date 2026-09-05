-- ADR-066/issue #88: a double-quoted string literal with no closing quote
-- before end of line/source is a lex error, not a silently-accepted
-- string that runs off across lines or truncates at EOF.
LET X$ = "unterminated
RUN
