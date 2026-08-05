-- Test DIM with variable bounds.
-- DIM is Declarative (P11 fix): it dispatches immediately, once, at the
-- point the interpreter reaches it -- not once per record. Its bound
-- expressions are therefore evaluated using whatever is already resolved
-- at that point, same as any other Declarative statement. SET/LET stay
-- Deferred (tied to a data step), so a bound variable set via SET must
-- go through a RUN before DIM can see it.
set ndim = 5
set lo = 3
set hi = 7
set n = 4.9
run

-- Test DIM with a variable bound
dim arr1(ndim)

-- Test DIM with variable bounds using TO
dim arr2(lo TO hi)

-- Test DIM with a float variable bound (should floor)
dim arr3(n)

repeat 1
for i = 1 to ndim
  let arr1(i) = i * 10
next
for i = lo to hi
  let arr2(i) = i * 100
next
for i = 1 to 4
  let arr3(i) = i
next
print arr1
print arr2
print arr3
run
