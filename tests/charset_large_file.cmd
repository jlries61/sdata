-- F46 regression: a file larger than the stack (here 10 MB) converts from a
-- non-UTF-8 character set; the whole-file buffers live on the heap.
SYSTEM "sh tests/data/make_large_csv.sh"
USE "tests/data/cs_large.csv" /CHARSET=LATIN1
RUN
SYSTEM "rm -f tests/data/cs_large.csv"
QUIT
