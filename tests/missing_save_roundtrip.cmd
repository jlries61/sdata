-- SAVE /MISSING= writes a literal token for a missing cell instead of
-- leaving it blank; declaring the same token on a later USE recovers the
-- missing value instead of a literal string (sdata ADR-083).
USE "tests/data/missing_first.csv"
SAVE "tests/data/missing_roundtrip_out.csv" / MISSING="NA"
RUN
USE "tests/data/missing_roundtrip_out.csv" / MISSING="NA"
PRINT X Y
RUN
SYSTEM "rm -f tests/data/missing_roundtrip_out.csv"
END
