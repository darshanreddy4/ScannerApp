/// One function the spreadsheet can calculate, as the function list shows it.
class FunctionInfo {
  const FunctionInfo(this.name, this.category, this.syntax, this.summary);
  final String name;
  final String category;

  /// For example `SUMIF(range, condition, [sum_range])`; square brackets mark what can be left out.
  final String syntax;
  final String summary;
}

const functionCategories = ['Math', 'Statistics', 'Logic', 'Text', 'Date and time', 'Lookup', 'Money'];

const functionCatalog = <FunctionInfo>[
  // Math
  FunctionInfo('SUM', 'Math', 'SUM(number1, [number2], ...)', 'Adds numbers and ranges.'),
  FunctionInfo('SUMIF', 'Math', 'SUMIF(range, condition, [sum_range])', 'Adds the cells that meet one condition.'),
  FunctionInfo('SUMIFS', 'Math', 'SUMIFS(sum_range, range1, condition1, ...)', 'Adds the cells that meet all conditions.'),
  FunctionInfo('SUMPRODUCT', 'Math', 'SUMPRODUCT(range1, range2, ...)', 'Multiplies ranges cell by cell and adds the results.'),
  FunctionInfo('SUMSQ', 'Math', 'SUMSQ(number1, ...)', 'Adds the squares of numbers.'),
  FunctionInfo('SUBTOTAL', 'Math', 'SUBTOTAL(function_num, range1, ...)', 'Sum (9), average (1), count (2), max (4), min (5) and more of a range.'),
  FunctionInfo('PRODUCT', 'Math', 'PRODUCT(number1, ...)', 'Multiplies numbers.'),
  FunctionInfo('ROUND', 'Math', 'ROUND(number, digits)', 'Rounds to a number of decimals.'),
  FunctionInfo('ROUNDUP', 'Math', 'ROUNDUP(number, digits)', 'Rounds away from zero.'),
  FunctionInfo('ROUNDDOWN', 'Math', 'ROUNDDOWN(number, digits)', 'Rounds towards zero.'),
  FunctionInfo('MROUND', 'Math', 'MROUND(number, multiple)', 'Rounds to the nearest multiple.'),
  FunctionInfo('CEILING', 'Math', 'CEILING(number, [step])', 'Rounds up to a multiple.'),
  FunctionInfo('FLOOR', 'Math', 'FLOOR(number, [step])', 'Rounds down to a multiple.'),
  FunctionInfo('INT', 'Math', 'INT(number)', 'Rounds down to a whole number.'),
  FunctionInfo('TRUNC', 'Math', 'TRUNC(number, [digits])', 'Cuts off decimals.'),
  FunctionInfo('ABS', 'Math', 'ABS(number)', 'Removes the minus sign.'),
  FunctionInfo('SIGN', 'Math', 'SIGN(number)', '1 for positive, -1 for negative, 0 for zero.'),
  FunctionInfo('MOD', 'Math', 'MOD(number, divisor)', 'The remainder after dividing.'),
  FunctionInfo('QUOTIENT', 'Math', 'QUOTIENT(number, divisor)', 'The whole part of a division.'),
  FunctionInfo('POWER', 'Math', 'POWER(number, power)', 'A number raised to a power.'),
  FunctionInfo('SQRT', 'Math', 'SQRT(number)', 'Square root.'),
  FunctionInfo('EXP', 'Math', 'EXP(number)', 'e raised to a power.'),
  FunctionInfo('LN', 'Math', 'LN(number)', 'Natural logarithm.'),
  FunctionInfo('LOG', 'Math', 'LOG(number, [base])', 'Logarithm; base 10 when left out.'),
  FunctionInfo('LOG10', 'Math', 'LOG10(number)', 'Logarithm to base 10.'),
  FunctionInfo('PI', 'Math', 'PI()', 'The number pi.'),
  FunctionInfo('FACT', 'Math', 'FACT(number)', 'Factorial, such as 5! = 120.'),
  FunctionInfo('COMBIN', 'Math', 'COMBIN(n, k)', 'Number of ways to choose k of n, order ignored.'),
  FunctionInfo('PERMUT', 'Math', 'PERMUT(n, k)', 'Number of ways to choose k of n, order counts.'),
  FunctionInfo('GCD', 'Math', 'GCD(number1, ...)', 'Greatest common divisor.'),
  FunctionInfo('LCM', 'Math', 'LCM(number1, ...)', 'Least common multiple.'),
  FunctionInfo('ISEVEN', 'Math', 'ISEVEN(number)', 'TRUE when the number is even.'),
  FunctionInfo('ISODD', 'Math', 'ISODD(number)', 'TRUE when the number is odd.'),
  FunctionInfo('SIN', 'Math', 'SIN(radians)', 'Sine of an angle in radians.'),
  FunctionInfo('COS', 'Math', 'COS(radians)', 'Cosine of an angle in radians.'),
  FunctionInfo('TAN', 'Math', 'TAN(radians)', 'Tangent of an angle in radians.'),
  FunctionInfo('ASIN', 'Math', 'ASIN(number)', 'Angle whose sine is the number.'),
  FunctionInfo('ACOS', 'Math', 'ACOS(number)', 'Angle whose cosine is the number.'),
  FunctionInfo('ATAN', 'Math', 'ATAN(number)', 'Angle whose tangent is the number.'),
  FunctionInfo('ATAN2', 'Math', 'ATAN2(x, y)', 'Angle of the point (x, y).'),
  FunctionInfo('RADIANS', 'Math', 'RADIANS(degrees)', 'Degrees to radians.'),
  FunctionInfo('DEGREES', 'Math', 'DEGREES(radians)', 'Radians to degrees.'),
  // Statistics
  FunctionInfo('AVERAGE', 'Statistics', 'AVERAGE(number1, ...)', 'The mean of numbers and ranges.'),
  FunctionInfo('AVERAGEIF', 'Statistics', 'AVERAGEIF(range, condition, [average_range])', 'Mean of the cells that meet a condition.'),
  FunctionInfo('AVERAGEIFS', 'Statistics', 'AVERAGEIFS(average_range, range1, condition1, ...)', 'Mean of the cells that meet all conditions.'),
  FunctionInfo('COUNT', 'Statistics', 'COUNT(value1, ...)', 'Counts cells that hold numbers.'),
  FunctionInfo('COUNTA', 'Statistics', 'COUNTA(value1, ...)', 'Counts cells that are not empty.'),
  FunctionInfo('COUNTBLANK', 'Statistics', 'COUNTBLANK(range)', 'Counts empty cells.'),
  FunctionInfo('COUNTIF', 'Statistics', 'COUNTIF(range, condition)', 'Counts the cells that meet a condition.'),
  FunctionInfo('COUNTIFS', 'Statistics', 'COUNTIFS(range1, condition1, ...)', 'Counts the cells that meet all conditions.'),
  FunctionInfo('MAX', 'Statistics', 'MAX(number1, ...)', 'The largest number.'),
  FunctionInfo('MIN', 'Statistics', 'MIN(number1, ...)', 'The smallest number.'),
  FunctionInfo('MAXIFS', 'Statistics', 'MAXIFS(max_range, range1, condition1, ...)', 'The largest value that meets the conditions.'),
  FunctionInfo('MINIFS', 'Statistics', 'MINIFS(min_range, range1, condition1, ...)', 'The smallest value that meets the conditions.'),
  FunctionInfo('LARGE', 'Statistics', 'LARGE(range, k)', 'The k-th largest value.'),
  FunctionInfo('SMALL', 'Statistics', 'SMALL(range, k)', 'The k-th smallest value.'),
  FunctionInfo('MEDIAN', 'Statistics', 'MEDIAN(number1, ...)', 'The middle value.'),
  FunctionInfo('MODE', 'Statistics', 'MODE(number1, ...)', 'The value that appears most often.'),
  FunctionInfo('RANK', 'Statistics', 'RANK(number, range, [order])', 'Position of a number in a list; 0 or left out is largest first.'),
  FunctionInfo('PERCENTILE', 'Statistics', 'PERCENTILE(range, k)', 'The value at a share k (0 to 1) of the data.'),
  FunctionInfo('QUARTILE', 'Statistics', 'QUARTILE(range, quart)', 'Quartile 0 to 4 of the data.'),
  FunctionInfo('STDEV', 'Statistics', 'STDEV(number1, ...)', 'Standard deviation of a sample.'),
  FunctionInfo('STDEV.P', 'Statistics', 'STDEV.P(number1, ...)', 'Standard deviation of a whole population.'),
  FunctionInfo('VAR', 'Statistics', 'VAR(number1, ...)', 'Variance of a sample.'),
  FunctionInfo('VAR.P', 'Statistics', 'VAR.P(number1, ...)', 'Variance of a whole population.'),
  FunctionInfo('CORREL', 'Statistics', 'CORREL(range1, range2)', 'How closely two lists move together (-1 to 1).'),
  FunctionInfo('SLOPE', 'Statistics', 'SLOPE(known_y, known_x)', 'Slope of the best straight line.'),
  FunctionInfo('INTERCEPT', 'Statistics', 'INTERCEPT(known_y, known_x)', 'Where the best straight line crosses the y axis.'),
  FunctionInfo('FORECAST', 'Statistics', 'FORECAST(x, known_y, known_x)', 'Predicts a value on the best straight line.'),
  // Logic
  FunctionInfo('IF', 'Logic', 'IF(test, if_true, [if_false])', 'One result when the test is true, another when it is not.'),
  FunctionInfo('IFS', 'Logic', 'IFS(test1, result1, test2, result2, ...)', 'The result of the first test that is true.'),
  FunctionInfo('SWITCH', 'Logic', 'SWITCH(value, match1, result1, ..., [default])', 'Picks a result by matching a value.'),
  FunctionInfo('IFERROR', 'Logic', 'IFERROR(value, if_error)', 'Replaces an error with something else.'),
  FunctionInfo('IFNA', 'Logic', 'IFNA(value, if_na)', 'Replaces only #N/A.'),
  FunctionInfo('AND', 'Logic', 'AND(test1, test2, ...)', 'TRUE when all tests are true.'),
  FunctionInfo('OR', 'Logic', 'OR(test1, test2, ...)', 'TRUE when any test is true.'),
  FunctionInfo('NOT', 'Logic', 'NOT(test)', 'Turns TRUE into FALSE and back.'),
  FunctionInfo('XOR', 'Logic', 'XOR(test1, test2, ...)', 'TRUE when an odd number of tests are true.'),
  FunctionInfo('ISBLANK', 'Logic', 'ISBLANK(cell)', 'TRUE when the cell is empty.'),
  FunctionInfo('ISNUMBER', 'Logic', 'ISNUMBER(value)', 'TRUE when the value is a number.'),
  FunctionInfo('ISTEXT', 'Logic', 'ISTEXT(value)', 'TRUE when the value is text.'),
  FunctionInfo('ISERROR', 'Logic', 'ISERROR(value)', 'TRUE when the value is an error.'),
  FunctionInfo('CHOOSE', 'Logic', 'CHOOSE(index, value1, value2, ...)', 'The value at position index.'),
  // Text
  FunctionInfo('CONCAT', 'Text', 'CONCAT(text1, ...)', 'Joins text and ranges.'),
  FunctionInfo('CONCATENATE', 'Text', 'CONCATENATE(text1, ...)', 'Joins text.'),
  FunctionInfo('TEXTJOIN', 'Text', 'TEXTJOIN(separator, ignore_empty, text1, ...)', 'Joins text with a separator between the parts.'),
  FunctionInfo('LEFT', 'Text', 'LEFT(text, [count])', 'The first characters of text.'),
  FunctionInfo('RIGHT', 'Text', 'RIGHT(text, [count])', 'The last characters of text.'),
  FunctionInfo('MID', 'Text', 'MID(text, start, count)', 'Characters from the middle of text.'),
  FunctionInfo('LEN', 'Text', 'LEN(text)', 'Number of characters.'),
  FunctionInfo('UPPER', 'Text', 'UPPER(text)', 'CAPITAL LETTERS.'),
  FunctionInfo('LOWER', 'Text', 'LOWER(text)', 'small letters.'),
  FunctionInfo('PROPER', 'Text', 'PROPER(text)', 'Capital Letter Of Each Word.'),
  FunctionInfo('TRIM', 'Text', 'TRIM(text)', 'Removes extra spaces.'),
  FunctionInfo('CLEAN', 'Text', 'CLEAN(text)', 'Removes characters that cannot be printed.'),
  FunctionInfo('SUBSTITUTE', 'Text', 'SUBSTITUTE(text, old, new, [which])', 'Replaces text by matching it.'),
  FunctionInfo('REPLACE', 'Text', 'REPLACE(text, start, count, new)', 'Replaces text by position.'),
  FunctionInfo('FIND', 'Text', 'FIND(find, text, [start])', 'Position of text, case sensitive.'),
  FunctionInfo('SEARCH', 'Text', 'SEARCH(find, text, [start])', 'Position of text, ignoring case.'),
  FunctionInfo('TEXTBEFORE', 'Text', 'TEXTBEFORE(text, delimiter, [instance])', 'The text before a delimiter.'),
  FunctionInfo('TEXTAFTER', 'Text', 'TEXTAFTER(text, delimiter, [instance])', 'The text after a delimiter.'),
  FunctionInfo('REPT', 'Text', 'REPT(text, times)', 'Repeats text.'),
  FunctionInfo('EXACT', 'Text', 'EXACT(text1, text2)', 'TRUE when two texts are the same, case included.'),
  FunctionInfo('TEXT', 'Text', 'TEXT(value, format)', 'Shows a number in a format, such as "0.00" or "dd/mm/yyyy".'),
  FunctionInfo('VALUE', 'Text', 'VALUE(text)', 'Turns text that looks like a number into a number.'),
  FunctionInfo('CODE', 'Text', 'CODE(text)', 'Code of the first character.'),
  FunctionInfo('CHAR', 'Text', 'CHAR(code)', 'The character with that code.'),
  // Date and time
  FunctionInfo('TODAY', 'Date and time', 'TODAY()', 'Today\'s date.'),
  FunctionInfo('NOW', 'Date and time', 'NOW()', 'Date and time now.'),
  FunctionInfo('DATE', 'Date and time', 'DATE(year, month, day)', 'Makes a date.'),
  FunctionInfo('YEAR', 'Date and time', 'YEAR(date)', 'The year of a date.'),
  FunctionInfo('MONTH', 'Date and time', 'MONTH(date)', 'The month of a date.'),
  FunctionInfo('DAY', 'Date and time', 'DAY(date)', 'The day of a date.'),
  FunctionInfo('WEEKDAY', 'Date and time', 'WEEKDAY(date)', 'Day of the week, 1 for Sunday.'),
  FunctionInfo('WEEKNUM', 'Date and time', 'WEEKNUM(date, [type])', 'Week of the year; type 2 starts weeks on Monday.'),
  FunctionInfo('DAYS', 'Date and time', 'DAYS(end_date, start_date)', 'Days between two dates.'),
  FunctionInfo('DATEDIF', 'Date and time', 'DATEDIF(start, end, unit)', 'Years ("Y"), months ("M") or days ("D") between dates.'),
  FunctionInfo('EDATE', 'Date and time', 'EDATE(date, months)', 'The date some months before or after.'),
  FunctionInfo('EOMONTH', 'Date and time', 'EOMONTH(date, months)', 'The last day of a month.'),
  FunctionInfo('NETWORKDAYS', 'Date and time', 'NETWORKDAYS(start, end, [holidays])', 'Working days (Monday to Friday) between dates.'),
  FunctionInfo('WORKDAY', 'Date and time', 'WORKDAY(start, days, [holidays])', 'The date after some working days.'),
  FunctionInfo('HOUR', 'Date and time', 'HOUR(time)', 'The hour of a time.'),
  FunctionInfo('MINUTE', 'Date and time', 'MINUTE(time)', 'The minute of a time.'),
  FunctionInfo('SECOND', 'Date and time', 'SECOND(time)', 'The second of a time.'),
  // Lookup
  FunctionInfo('VLOOKUP', 'Lookup', 'VLOOKUP(value, table, column, [exact])', 'Finds a value in the first column and returns a cell from the same row. Use FALSE for exact.'),
  FunctionInfo('HLOOKUP', 'Lookup', 'HLOOKUP(value, table, row, [exact])', 'Like VLOOKUP, along the first row.'),
  FunctionInfo('XLOOKUP', 'Lookup', 'XLOOKUP(value, lookup_range, return_range, [if_not_found], [match_mode])', 'Finds a value and returns the cell next to it, in any direction.'),
  FunctionInfo('LOOKUP', 'Lookup', 'LOOKUP(value, lookup_range, [result_range])', 'Finds the closest smaller value in a sorted list.'),
  FunctionInfo('INDEX', 'Lookup', 'INDEX(range, row, [column])', 'The cell at a row and column of a range.'),
  FunctionInfo('MATCH', 'Lookup', 'MATCH(value, range, [type])', 'The position of a value in a range; 0 for exact.'),
  FunctionInfo('ROW', 'Lookup', 'ROW(cell)', 'Row number of a cell.'),
  FunctionInfo('COLUMN', 'Lookup', 'COLUMN(cell)', 'Column number of a cell.'),
  FunctionInfo('ROWS', 'Lookup', 'ROWS(range)', 'Number of rows in a range.'),
  FunctionInfo('COLUMNS', 'Lookup', 'COLUMNS(range)', 'Number of columns in a range.'),
  // Money
  FunctionInfo('PMT', 'Money', 'PMT(rate, periods, present_value, [future_value], [type])', 'The payment of a loan each period. Rate is per period, for example 5%/12.'),
  FunctionInfo('FV', 'Money', 'FV(rate, periods, payment, [present_value], [type])', 'What regular savings will be worth.'),
  FunctionInfo('PV', 'Money', 'PV(rate, periods, payment, [future_value], [type])', 'What regular payments are worth today.'),
  FunctionInfo('NPER', 'Money', 'NPER(rate, payment, present_value, [future_value], [type])', 'How many periods a loan or saving plan takes.'),
  FunctionInfo('NPV', 'Money', 'NPV(rate, value1, ...)', 'Today\'s value of future amounts.'),
];

/// The functions that match what was typed, best matches first: a name that starts with it, then a name that contains it, then a description that does.
List<FunctionInfo> searchFunctions(String query, {String? category}) {
  final q = query.trim().toLowerCase();
  final pool = [
    for (final f in functionCatalog)
      if (category == null || f.category == category) f,
  ];
  if (q.isEmpty) return pool;
  final starts = <FunctionInfo>[], contains = <FunctionInfo>[], described = <FunctionInfo>[];
  for (final f in pool) {
    final name = f.name.toLowerCase();
    if (name.startsWith(q)) {
      starts.add(f);
    } else if (name.contains(q)) {
      contains.add(f);
    } else if (f.summary.toLowerCase().contains(q)) {
      described.add(f);
    }
  }
  return [...starts, ...contains, ...described];
}
