-- NOTE (ADR-063): an array index expression is evaluated EXACTLY ONCE, not
-- once to check permanence and again to print -- an index need not be
-- idempotent (RANDOM() draws a fresh value every call), so evaluating it
-- twice could check one element and print a different one. This seed
-- deterministically resolves to the temporary element (V(2), aliasing B)
-- and must succeed consistently across every run at this seed; see
-- note_array_index_side_effect_rejects.cmd for the sibling case that
-- deterministically resolves to the permanent element instead.
RSEED 7
LET A = 1
SET B = 2
ARRAY V A B
RUN
NOTE V(1 + INT(RANDOM()*2))
QUIT
