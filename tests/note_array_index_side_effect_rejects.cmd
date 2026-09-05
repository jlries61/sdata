-- NOTE (ADR-063): the sibling case to note_array_index_side_effect_success.cmd
-- -- this seed deterministically resolves the RANDOM()-based index to the
-- permanent element (V(1), aliasing A) and must reject it consistently
-- across every run at this seed. Locks in that Print_Value_List's
-- Check_Permanent callback fires on the SAME resolved index it is about to
-- print, not a separately re-evaluated one.
RSEED 3
LET A = 1
SET B = 2
ARRAY V A B
RUN
NOTE V(1 + INT(RANDOM()*2))
QUIT
