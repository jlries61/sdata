USE "F37_blank_cells.csv"
SAVE "F37_o.xlsx"
RUN
USE "F37_o.xlsx"
DISPLAY
USE "F37_openpyxl_blanks.xlsx"
DISPLAY
REM expect (.,3) in row 2; actual (3,.)
