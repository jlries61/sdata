-- PCTL(var, p) used as an ordinary expression function against a live
-- array, outside AGGREGATE/STATS entirely (ADR-075/sdata#93 -- a confirmed
-- side effect of PCTL sharing the same Dispatch_Table/Evaluate_Function
-- mechanism every other aggregate function already does). PCTL(V,50) must
-- agree with MEDIAN(V) exactly; PCTL(V,25) is a genuinely interpolated
-- value, hand-verified: V=[10,20,30,40], rank=0.25*3+1=1.75 ->
-- 10+0.75*(20-10)=17.5.
NEW
REPEAT 1
DIM V(4)
LET V(1) = 10
LET V(2) = 20
LET V(3) = 30
LET V(4) = 40
PRINT "PCTL(V,50):" PCTL(V, 50)
PRINT "MEDIAN(V):" MEDIAN(V)
PRINT "PCTL(V,25):" PCTL(V, 25)
RUN
QUIT
