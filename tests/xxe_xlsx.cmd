-- Security regression (sdata-core XXE fix): xxe.xlsx is a crafted workbook
-- whose sharedStrings.xml declares an external entity
-- (<!ENTITY xxe SYSTEM "xxe_secret.txt">) and uses it as a cell value.  A
-- vulnerable reader resolves the entity and the LEAK column comes back holding
-- the contents of tests/data/xxe_secret.txt (the canary string).  With the
-- SData_Core.File_IO.Helpers.Secure_Reader entity-resolver override in place,
-- the external entity must resolve to nothing, so LEAK$ prints "." (missing;
-- per issue #55 an empty character value is stored as missing).  If the
-- canary text ever reappears here, the XXE hardening has regressed.
USE "tests/data/xxe.xlsx"
PRINT LEAK$
RUN
END
