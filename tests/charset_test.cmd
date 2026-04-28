-- Test 1: UTF-8 BOM stripped automatically (AUTO detection)
USE "tests/data/charset_utf8bom.csv"
PRINT NAME$ SCORE
RUN

-- Test 2: UTF-16 LE via explicit CHARSET flag on USE
USE "tests/data/charset_utf16le.csv" / CHARSET=UTF-16LE
PRINT NAME$ SCORE
RUN

-- Test 3: UTF-16 LE via AUTO BOM detection
USE "tests/data/charset_utf16le.csv"
PRINT NAME$ SCORE
RUN

END
