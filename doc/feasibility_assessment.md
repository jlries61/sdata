# Implementation Feasibility Assessment
## Data Command Interpreter Specification

---

## EXECUTIVE SUMMARY

**Overall Feasibility: HIGH** ✓

The specification is implementable in Ada with available libraries and tools. The design is well-structured, clearly specified, and avoids unnecessary complexity. However, this is a **substantial project** requiring:

- **Estimated effort:** 7-10 months full-time (single experienced developer)
- **Lines of code:** 17,000-27,000 LOC (estimated)
- **Risk level:** Medium (manageable with proper architecture)

**Recommendation:** Proceed with implementation. The specification is sufficiently complete and unambiguous.

---

## SCOPE ANALYSIS

### Commands: ~40 commands across categories

**Data Management (9):**
- USE (including USE MOCK for test data generation), SAVE, KEEP, DROP, HOLD, UNHOLD, NEW, REPEAT, WRITE

**Control Flow (9):**
- IF/THEN/ELSE, FOR/NEXT, WHILE/WEND, REPEAT/UNTIL, SELECT/CASE
- SELECT (record filter — distinct declarative form)
- SUBMIT (recursive script execution)

**Variable/Array Operations (4):**
- LET, SET, DIM, ARRAY

**Output/Display (3):**
- PRINT, OUTPUT, ECHO

**Data Processing (4):**
- BY (grouping), SORT, RENAME, DELETE

**Configuration (5):**
- OPTIONS, DIGITS, FPATH, HEADER, RSEED

**Utility (6):**
- REM, HELP, QUIT/END, NAMES, LIST, SYSTEM

**Note on execution model:** The design distinguishes three command types rather than two. **Declarative** commands (e.g. USE, SAVE, BY, DIM) execute immediately and configure interpreter state. **Immediate Execution** commands (e.g. RUN, SORT, NAMES, LIST, SYSTEM, HELP, NEW) also execute immediately but are not declarative. **Deferred Execution** commands (e.g. LET, SET, PRINT, IF, FOR, WHILE, SUBMIT, WRITE) become part of the program run by the next RUN statement. The execution engine must maintain clean separation between all three paths.

### Functions: ~80 functions across categories

**Mathematical (20+):**
- Basic: ABS, SIN, COS, TAN, LOG, EXP, SQRT, etc.
- Advanced: Trig (SIND, COSD, ATAN2), hyperbolic, conversions

**Statistical/Probability (33+):**
- Distributions: Beta, Binomial, Chi-square, Exponential, F, Gamma, Logistic, Normal, Poisson, T, Uniform, Weibull
- Each with: CDF, PDF, IDF (inverse), RN (random number)
- Note: The Normal distribution family (ZCF, ZDF, ZIF, ZRN) accepts optional mu and sigma parameters, generalising beyond the standard normal. All four functions default to standard normal when parameters are omitted.
- Aggregate: MEAN, MAX, MIN, SUM, STD, VAR, MEDIAN, etc.

**String Functions (15+):**
- CHR$, STR$, LEFT$, RIGHT$, MID$, TRIM$, UCASE$, LCASE$
- POS, LEN, VAL, NUM$, etc.

**Type Conversion (5):**
- NUM, INT, HEX$, OCT$, BIN$

**Special (15+):**
- Record/group markers: BOF, EOF, BOG, EOG, RECNO
- Data access: OBS, OBSC$, LAG, LAGC$, NEXT
- Missing value: MISSING, NMISS
- Date/time: DATE$, TIME$
- System: RAN/RANDOM, ERR, ERL

---

## TECHNICAL ARCHITECTURE

### 1. Core Components

#### A. Lexer/Parser ⭐ CRITICAL
**Purpose:** Parse command language into AST
**Complexity:** HIGH
**Options:**
- Hand-written recursive descent parser (recommended for this grammar)
- Parser generator (GNAT-specific tools)

**Challenges:**
- Case insensitivity
- Line continuation (trailing comma)
- Expression parsing with operator precedence
- String literal handling (embedded quotes)
- Variable ranges (NAME1-NAME5, VAR1:VAR10)
- DIM array bounds use `TO` keyword syntax (e.g. `DIM MONTH(0 TO 11)`)

**Estimated effort:** 3-4 weeks

#### B. Expression Evaluator ⭐ CRITICAL
**Purpose:** Evaluate arithmetic/logical/string expressions
**Complexity:** MEDIUM-HIGH
**Requirements:**
- Type checking and coercion
- Function dispatch
- Missing value propagation
- Array element access
- Operator precedence

**Estimated effort:** 2-3 weeks

#### C. Data Table Manager ⭐ CRITICAL
**Purpose:** Manage 2D table (in-memory + external file cache)
**Complexity:** HIGH
**Requirements:**
- Dynamic column/row management
- Memory-to-disk spillover
- Row iterator with BY group support
- Missing value representation
- Type-per-column storage
- Program Data Vector (PDV): track per-record write state for WRITE command

**Challenges:**
- Efficient cache management
- Thread safety (if needed for future)
- Performance with large datasets
- Lookahead buffering required for NEXT() function (forward-looking counterpart to LAG)
- PDV "written" flag: WRITE command suppresses the automatic end-of-step record output; the table manager must track whether the current record has already been written

**Estimated effort:** 4-5 weeks

#### D. File I/O Layer ⭐ CRITICAL
**Purpose:** Read/write CSV, ODF, OOXML
**Complexity:** MEDIUM-HIGH
**Available libraries:**

**CSV:**
- Ada.Text_IO (built-in) - basic
- Custom CSV parser (200-300 LOC) - recommended
- Handles: delimiters, quotes, character sets, line endings

**ODF/OOXML:**
- **CHALLENGE:** No mature Ada libraries
- Options:
  1. Use LibreOffice UNO API via Ada bindings (complex)
  2. Direct XML parsing (ZanyBlue.Text.Locales, XML/Ada)
  3. Call Python/external tool (non-ideal)
  4. **Recommended:** XML/Ada for direct ODF/OOXML parsing

**Formula evaluation in spreadsheets:**
- Must evaluate formulas during read
- Options:
  1. Use LibreOffice headless (external process)
  2. Implement basic formula evaluator (subset)
  3. Use cached values when formulas fail

**Character set handling:**
- Ada.Strings.UTF_Encoding (Ada 2012+)
- GNAT.Decode/Encode for additional charsets

**Estimated effort:** 5-6 weeks (CSV: 1 week, Spreadsheets: 4-5 weeks)

#### E. Statistical Functions
**Purpose:** Implement ~33 distribution functions across 12 distributions
**Complexity:** MEDIUM
**Available libraries:**
- **PROBLEM:** Limited Ada statistical libraries
- Options:
  1. Port from C (GSL - GNU Scientific Library)
  2. Implement from mathematical formulas
  3. Wrapper around external library

**Distributions needed:**
- Beta, Binomial, Chi-square, Exponential, F, Gamma, Logistic, Normal, Poisson, T, Uniform, Weibull
- Each needs: CDF, PDF, Inverse CDF, Random generator
- Normal distribution (ZCF/ZDF/ZIF/ZRN): must support optional mu and sigma parameters in addition to standard normal defaults

**Recommendations:**
- Use Ada numerics packages for basic math
- Port algorithms from reliable sources (Numerical Recipes, NIST)
- Random number generation: Ada.Numerics.Float_Random

**Estimated effort:** 5-7 weeks

#### F. Command Execution Engine
**Purpose:** Execute parsed commands in sequence
**Complexity:** MEDIUM-HIGH
**Requirements:**
- Three-tier dispatch: Declarative (immediate, configures state), Immediate Execution (immediate, non-declarative), Deferred Execution (queued for RUN)
- Data step iteration (implicit loop over records)
- BY group processing
- Control flow (IF, FOR, WHILE, REPEAT, SELECT/CASE)
- SELECT as record filter (separate declarative form — not the same as SELECT CASE)
- Nested loop management
- SUBMIT (file inclusion with cycle detection)
- WRITE command: explicit PDV flush with suppression of automatic end-of-step write
- SYSTEM command: spawn external process or shell (disabled by `--noshell`)
- USE MOCK: generate synthetic test data on demand
- NAMES command (enumerate permanent and temporary variables separately)
- RSEED command (set random seed from literal integer)
- RUN: display record and variable counts after execution

**Challenges:**
- Clean separation of all three execution tiers
- BY group state management
- PDV write-state tracking per record
- Proper error handling and recovery

**Estimated effort:** 4-5 weeks

#### G. Variable Management
**Purpose:** Symbol table for variables/arrays
**Complexity:** MEDIUM
**Requirements:**
- Permanent vs temporary variables
- Scalar vs array storage
- Virtual arrays (aliases)
- Type tracking (float, integer, character)
- KEEP/DROP list management

**Implementation:**
- Hash table for symbol lookup
- Separate storage for permanent (in table) vs temporary (in memory)

**Estimated effort:** 2-3 weeks

#### H. Interactive Console
**Purpose:** REPL with line editing, paging, and dual-destination output routing
**Complexity:** LOW-MEDIUM
**Options:**
- Ada.Text_IO for basic I/O
- GNU Readline bindings for line editing
- GNAT.IO for console control

**Note:** When an OUTPUT file is in effect, console output must be written to **both** the file and standard output simultaneously, unless `-q` or `ECHO OFF` is in effect. The output routing layer must handle this fan-out correctly.

**Estimated effort:** 1-2 weeks

---

## LIBRARY AVAILABILITY ASSESSMENT

### Ada Standard Library: ✓ GOOD
- Ada.Text_IO, Ada.Strings, Ada.Containers
- Ada.Numerics (basic math, random)
- Ada.Streams (file I/O)

### GNAT Runtime: ✓ GOOD
- GNAT.OS_Lib (system calls)
- GNAT.Strings (string utilities)
- GNAT.IO (console I/O)

### Third-Party Libraries:

#### XML/Ada: ✓ AVAILABLE
- GPL licensed (compatible per spec requirement)
- Mature, maintained by AdaCore
- Suitable for ODF/OOXML parsing

#### AWS (Ada Web Server): ✓ AVAILABLE
- Not needed for this project, but shows Ada ecosystem

#### Statistical Libraries: ⚠️ LIMITED
- Very few mature Ada statistical libraries
- **Solution:** Implement or port from C

#### Spreadsheet Libraries: ⚠️ LIMITED
- No direct ODF/OOXML libraries for Ada
- **Solution:** XML parsing + formula evaluation

---

## RISK ASSESSMENT

### HIGH RISK (Mitigation Required)

**1. Spreadsheet Formula Evaluation**
- **Risk:** No Ada library for evaluating Excel/ODF formulas
- **Impact:** Core requirement
- **Mitigation:**
  - Phase 1: Use cached formula values
  - Phase 2: Call LibreOffice headless via subprocess
  - Phase 3: Implement basic formula evaluator (later)
- **Effort:** +2-3 weeks for subprocess approach

**2. Statistical Distribution Functions**
- **Risk:** Must implement ~33 distribution functions (12 distributions × CDF/PDF/IDF/RN) from scratch
- **Impact:** Significant effort, risk of numerical accuracy issues
- **Mitigation:**
  - Use proven algorithms (Numerical Recipes, NIST)
  - Extensive unit testing against R/Python
  - Consider linking to GSL via C interface (but check license)
- **Effort:** 5-7 weeks (revised up from 4-5 to account for Binomial, Logistic, Poisson, and Weibull distributions absent from original scope)

### MEDIUM RISK (Manageable)

**3. Memory/Disk Cache Management**
- **Risk:** Complex logic for spillover to disk
- **Impact:** Performance and correctness
- **Mitigation:**
  - Start with in-memory only (simpler)
  - Add disk spillover as enhancement
  - Use SQLite as external storage (MIT license compatible)

**4. Parser Complexity**
- **Risk:** BASIC syntax has quirks (line continuation, case insensitivity)
- **Impact:** Core component
- **Mitigation:**
  - Thorough testing with BW BASIC examples
  - Reference implementation analysis

**5. Character Set Handling**
- **Risk:** Auto-detection can fail, encoding conversion edge cases
- **Impact:** Medium (spec says fail on errors)
- **Mitigation:**
  - Use Ada.Strings.UTF_Encoding
  - For non-UTF, use GNAT.Decode/Encode
  - Comprehensive test suite

**6. WRITE Command / PDV State Management**
- **Risk:** Explicit record writing with automatic-write suppression adds non-trivial state to the data step execution model
- **Impact:** Medium — incorrect PDV tracking produces duplicate or missing output records
- **Mitigation:**
  - Implement a per-record "written" flag in the Data Table Manager from the outset
  - Comprehensive data step tests covering WRITE, multiple WRITEs, and mixed WRITE/no-WRITE patterns

### LOW RISK (Standard Practice)

**7. Control Flow Implementation**
- Standard compiler/interpreter techniques
- Well-documented in literature

**8. Interactive Console**
- Ada.Text_IO is sufficient
- GNU Readline available if needed
- Dual output routing (file + stdout) is straightforward fan-out logic

---

## IMPLEMENTATION STRATEGY

### Phase 1: Core Infrastructure (6-8 weeks)
1. ✓ Lexer and parser for basic commands
2. ✓ Expression evaluator (arithmetic, no functions yet)
3. ✓ In-memory data table (no disk spillover)
4. ✓ CSV reader/writer (basic)
5. ✓ Variable management (permanent/temporary)
6. ✓ Basic commands: LET, SET, PRINT, NEW, RUN
7. ✓ Test framework
8. ✓ Command-line argument parser scaffolding (stub parser wired up for all options, even those not yet active)
9. ✓ `-m` (max in-memory table size) — must be in place before Data Table Manager is fully built
10. ✓ `--clen` (max character variable length) — must be in place before variable handling is fully built
11. ✓ `--noshell` flag (disables both SYSTEM command and SHELL function)
12. ✓ Script filename argument (non-interactive execution path)
13. ✓ SYSTEM command (immediate execution; trivial to stub behind `--noshell` guard)
14. ✓ USE MOCK (synthetic test data generation — useful for early test framework work)
15. ✓ PDV "written" flag in Data Table Manager (foundation for WRITE command)

**Deliverable:** Can execute simple scripts with CSV I/O

### Phase 2: Control Flow & Functions (4-6 weeks)
1. ✓ IF/THEN/ELSE, FOR/NEXT, WHILE/WEND
2. ✓ Mathematical functions (basic: ABS, SIN, LOG, etc.)
3. ✓ String functions
4. ✓ Type conversion functions
5. ✓ Expression evaluator enhancements
6. ✓ WRITE command (deferred execution; PDV flag already in place from Phase 1)
7. ✓ Dual console output routing (file + stdout fan-out)
8. ✓ `-u` / `--infmt` (input dataset and format — wire in as USE and File I/O layer are completed)
9. ✓ `-s` / `--outfmt` (output dataset and format — wire in as SAVE is completed)
10. ✓ `-o` and `-q` (console output file and suppression — wire in as OUTPUT/ECHO are completed)
11. ✓ `-t` (max temporary variable memory — wire in as temporary variable memory management is completed)

**Deliverable:** Can execute scripts with loops and functions; all command-line options except pager active

### Phase 3: Advanced Features (7-9 weeks)
1. ✓ BY group processing
2. ✓ Statistical distributions (CDF, PDF, IDF, RN) — all 12: Beta, Binomial, Chi-square, Exponential, F, Gamma, Logistic, Normal, Poisson, T, Uniform, Weibull
3. ✓ Normal distribution with optional mu/sigma parameters (ZCF, ZDF, ZIF, ZRN)
4. ✓ Aggregate functions
5. ✓ LAG and NEXT functions (with lookahead buffering)
6. ✓ SORT, RENAME commands
7. ✓ SUBMIT with recursion detection
8. ✓ SELECT record-filter form
9. ✓ NAMES, RSEED commands

**Deliverable:** Full statistical capabilities

### Phase 4: Spreadsheet Support (4-5 weeks)
1. ✓ ODF parser (XML/Ada)
2. ✓ OOXML parser (XML/Ada)
3. ✓ Formula evaluation (subprocess approach)
4. ✓ Multi-sheet handling
5. ✓ Spreadsheet writer

**Deliverable:** Full spreadsheet I/O

### Phase 5: Polish & Optimization (3-4 weeks)
1. ✓ Memory-to-disk spillover
2. ✓ Interactive console improvements
3. ✓ `-p` (pager specification — depends on interactive console improvements above)
4. ✓ HELP system (including HELP /ALL)
5. ✓ Error messages and diagnostics
6. ✓ Performance optimization
7. ✓ Documentation
8. LIST command (display the currently queued program buffer — interactive convenience feature)
9. ERR and ERL functions (return last error code and line number — runtime error introspection for scripts)
10. Re-evaluate NEXT() lookahead if disk spillover is implemented as a streaming model rather than full in-memory; current implementation reads from the committed table and is correct for in-memory use but would need buffering for true streaming.

**Deliverable:** Production-ready system; all command-line options fully active

### Phase 6: Testing & Validation (4-6 weeks)
1. ✓ Comprehensive test suite
2. ✓ Validation against BW BASIC
3. ✓ Performance benchmarking
4. ✓ Edge case testing
5. ✓ Security review

**Total: 29-40 weeks (7-10 months)**

---

## TECHNICAL CHALLENGES & SOLUTIONS

### Challenge 1: No Ada Spreadsheet Library
**Solution:**
- Use XML/Ada to parse ODF/OOXML directly
- For formula evaluation: call LibreOffice headless via subprocess
- Future: implement basic formula evaluator

**Code estimate:** 2000-3000 LOC

### Challenge 2: Statistical Functions
**Solution:**
- Implement from mathematical formulas
- Use Numerical Recipes algorithms (check licensing)
- Extensive validation testing
- All 12 distributions required: Beta, Binomial, Chi-square, Exponential, F, Gamma, Logistic, Normal, Poisson, T, Uniform, Weibull
- Normal family (ZCF/ZDF/ZIF/ZRN) requires optional-parameter handling for generalised normal support

**Code estimate:** 2,000-2,800 LOC (revised up from 1,500-2,000 to account for four additional distributions)

### Challenge 3: Data Table with Spillover
**Solution:**
- Use SQLite as backing store (MIT license)
- Ada bindings available (matreshka-sqlite3)
- Clean abstraction layer

**Code estimate:** 1000-1500 LOC

### Challenge 4: BY Group Processing
**Solution:**
- Iterator pattern over table rows
- State machine to track group boundaries
- Buffer previous row for comparison

**Code estimate:** 500-800 LOC

### Challenge 5: Expression Parser
**Solution:**
- Recursive descent parser
- Operator precedence climbing
- Type checking during evaluation

**Code estimate:** 1500-2000 LOC

### Challenge 6: WRITE Command / PDV Model
**Solution:**
- Per-record boolean flag in Data Table Manager: `record_explicitly_written`
- WRITE sets the flag and flushes current PDV to output
- End-of-step logic: write automatically only if flag is not set
- Flag reset at start of each new record
- Multiple WRITEs per record are permitted (same record written multiple times)

**Code estimate:** 200-300 LOC (incremental, atop existing data step machinery)

---

## CODE SIZE ESTIMATE

| Component | Est. LOC |
|-----------|----------|
| Lexer/Parser | 2,500 |
| Expression Evaluator | 2,000 |
| Data Table Manager | 2,700 |
| File I/O (CSV) | 800 |
| File I/O (ODF/OOXML) | 2,500 |
| Statistical Functions | 2,400 |
| Mathematical Functions | 600 |
| String Functions | 800 |
| Command Execution | 2,400 |
| Variable Management | 1,200 |
| Control Flow | 1,500 |
| Interactive Console | 600 |
| Utilities & Error Handling | 1,500 |
| **TOTAL** | **~21,500** |

Plus test code: ~5,000-10,000 LOC

---

## DEPENDENCIES

### Required Libraries (all compatible with spec requirements):

1. **XML/Ada** (GPL) - XML parsing for spreadsheets
2. **matreshka-sqlite3** (BSD) - Optional, for disk spillover
3. **Standard Ada Libraries** (built-in)

### External Tools (optional):

1. **LibreOffice** (headless mode) - For spreadsheet formula evaluation
   - Alternative: implement basic formula evaluator

---

## TESTING STRATEGY

### Unit Tests
- Each function with multiple test cases
- Edge cases (missing values, overflow, invalid input)
- All commands individually
- WRITE command: single write, multiple writes per record, mixed WRITE/automatic-write scripts

### Integration Tests
- Complete scripts end-to-end
- CSV I/O round-trip
- Spreadsheet I/O round-trip
- BY group processing
- Nested loops
- USE MOCK for data-independent integration tests

### Validation Tests
- Compare output to BW BASIC (where applicable)
- Statistical function validation against R/Python
- Normal distribution with non-standard mu/sigma validated against reference implementations
- Performance benchmarks

### Test Coverage Goal: >90%

---

## PERFORMANCE CONSIDERATIONS

### Expected Performance:
- **CSV I/O:** 100K-500K rows/second (depending on column count)
- **In-memory operations:** Millions of operations/second
- **Disk spillover:** 10K-50K rows/second (SQLite backed)

### Bottlenecks:
1. Spreadsheet formula evaluation (external process overhead)
2. BY group processing (requires row comparisons)
3. String operations (memory allocation)

### Optimization Opportunities:
- Lazy evaluation where possible
- Column-major storage for better cache locality
- Batch operations in disk spillover

---

## MAINTENANCE & EXTENSIBILITY

### Code Organization:
- Modular architecture (separate packages per component)
- Clear interfaces between layers
- Comprehensive documentation

### Future Enhancements (Easy):
- Additional file formats
- More statistical functions
- Performance optimizations
- Additional commands

### Future Enhancements (Medium):
- GUI wrapper
- Network data sources
- Plugin system for user functions

### Future Enhancements (Hard):
- Multi-threading for parallel operations
- Distributed processing
- JIT compilation for expressions

---

## RECOMMENDATION

### ✓ PROCEED WITH IMPLEMENTATION

**Rationale:**
1. Specification is complete and unambiguous
2. Technical approach is sound
3. All components are implementable in Ada
4. Libraries available for most needs
5. Challenges are manageable with proper architecture

**Critical Success Factors:**
1. Start with core infrastructure
2. Incremental development with continuous testing
3. Address high-risk items (spreadsheets, statistics) early
4. Maintain clean architecture for maintainability

**Timeline:**
- Minimum viable product: 3-4 months
- Full featured: 7-10 months
- Production ready: 10-13 months (with testing/polish)

**Resource Requirements:**
- 1 senior Ada developer (full-time)
- OR 2 mid-level Ada developers
- Access to LibreOffice for spreadsheet testing
- Linux/Windows/macOS test environments

---

## APPENDIX: ALTERNATE APPROACHES

### Alternative 1: Use Existing Interpreter
**Pros:** Faster time-to-market
**Cons:**
- BW BASIC doesn't have data table features
- No Ada implementation
- Licensing issues
**Verdict:** Not feasible

### Alternative 2: Python/C++ then Port
**Pros:** Faster prototyping, more libraries
**Cons:**
- Defeats purpose of Ada requirement
- Translation introduces errors
**Verdict:** Not recommended

### Alternative 3: Hybrid Approach
**Pros:** Use C libraries for hard parts (stats, spreadsheets)
**Cons:**
- Foreign function interface overhead
- Licensing complexity
- Defeats Ada safety benefits
**Verdict:** Consider only for spreadsheet formulas

---

## CONCLUSION

This is an ambitious but achievable project. The specification is excellent—clear, complete, and well-thought-out. With proper planning and a phased approach, implementation in Ada is entirely feasible within 7-10 months.

**Key Success Factors:**
1. ✓ Well-specified design (complete)
2. ✓ Available Ada tools and libraries (adequate)
3. ✓ Clear technical approach (defined above)
4. ⚠️ Dedicated resources (required)
5. ⚠️ Statistical/spreadsheet expertise (needed)

**Proceed with confidence.**
