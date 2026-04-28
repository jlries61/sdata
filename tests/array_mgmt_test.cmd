-- Test bare ARRAY listing and ARRAY undefine (immediate commands)

-- No virtual arrays defined yet
ARRAY

-- Define a virtual array
REPEAT 1
LET A = 10
LET B = 20
LET C = 30
ARRAY VEC A B C
PRINT VEC{2}
RUN

-- Listing should now show VEC
ARRAY

-- Undefine VEC
ARRAY VEC

-- Listing should show none again
ARRAY

QUIT
