-- Test DIM with variable bounds
-- (SET ndim placed after REPEAT: a REPEAT cancels deferred statements queued
--  before it, so the DIM bound variable must be set within the data step.)
repeat 1
set ndim = 5
dim arr1(ndim)
for i = 1 to ndim
  let arr1(i) = i * 10
next
print arr1

-- Test DIM with variable bounds using TO
set lo = 3
set hi = 7
dim arr2(lo TO hi)
for i = lo to hi
  let arr2(i) = i * 100
next
print arr2

-- Test DIM with float variable (should floor)
set n = 4.9
dim arr3(n)
for i = 1 to 4
  let arr3(i) = i
next
print arr3
run
