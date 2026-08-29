/**
 * Parses legacy Work Order / Service Appointment invoice-number text into typed tokens.
 * Workflow notes on the deny-list return zero tokens and must never become invoices.
 */
public inherited sharing class BillingControl_InvoiceNumberParser {
    public static final String TYPE_DEPOSIT = 'Deposit';
    public static final String TYPE_BALANCE = 'Balance';

    private static final Set<String> DENY_LIST = new Set<String>{
        'inspection to quote',
        'to be quote',
        'pending as per dw',
        'to be rescheduled',
        'incomplete',
        'no bill as per dw',
        'completed',
        'deposit required',
        'waiting for deposit',
        'deposit received',
        'due in full',
        'no deposit required'
    };

    public class ParsedToken {
        public String type;
        public String invoiceNumber;
        public String raw;
    }

    public static String canonicalNumber(ParsedToken token) {
        if (token == null || String.isBlank(token.invoiceNumber)) {
            return null;
        }
        return token.type == TYPE_DEPOSIT
            ? 'DP ' + token.invoiceNumber
            : 'Inv ' + token.invoiceNumber;
    }

    public static String digitKey(String invoiceNumberText) {
        List<ParsedToken> tokens = parse(invoiceNumberText);
        if (tokens.isEmpty()) {
            return null;
        }
        return tokens[0].invoiceNumber;
    }

    public static List<ParsedToken> parse(String input) {
        List<ParsedToken> tokens = new List<ParsedToken>();
        if (String.isBlank(input)) {
            return tokens;
        }

        String trimmed = input.trim();
        if (DENY_LIST.contains(trimmed.toLowerCase())) {
            return tokens;
        }

        String lower = trimmed.toLowerCase();
        Integer length = trimmed.length();
        Integer index = 0;
        String lastType = null;

        while (index < length) {
            index = skipSeparators(trimmed, index);
            if (index >= length) {
                break;
            }

            Integer prefixLength = matchPrefixLength(lower, index);
            if (prefixLength > 0) {
                Integer numberStart = skipSeparators(trimmed, index + prefixLength);
                Integer numberEnd = consumeDigits(trimmed, numberStart);
                Integer digitCount = numberEnd - numberStart;
                if (digitCount >= 4 && digitCount <= 7) {
                    String tokenType = lower.substring(index, index + prefixLength).startsWith('dp')
                        ? TYPE_DEPOSIT
                        : TYPE_BALANCE;
                    lastType = tokenType;
                    tokens.add(buildToken(tokenType, trimmed.substring(numberStart, numberEnd), trimmed.substring(index, numberEnd)));
                    index = numberEnd;
                    continue;
                }
                index += 1;
                continue;
            }

            Integer numberEnd = consumeDigits(trimmed, index);
            Integer digitCount = numberEnd - index;
            if (digitCount >= 4 && digitCount <= 7 && lastType != null) {
                tokens.add(buildToken(lastType, trimmed.substring(index, numberEnd), trimmed.substring(index, numberEnd)));
                index = numberEnd;
                continue;
            }
            if (digitCount > 0) {
                index = numberEnd;
                continue;
            }
            index += 1;
        }

        return tokens;
    }

    private static ParsedToken buildToken(String tokenType, String numberValue, String rawValue) {
        ParsedToken token = new ParsedToken();
        token.type = tokenType;
        token.invoiceNumber = numberValue;
        token.raw = rawValue;
        return token;
    }

    private static Integer matchPrefixLength(String lower, Integer index) {
        if (startsWithAt(lower, index, 'invoice')) {
            return 7;
        }
        if (startsWithAt(lower, index, 'inv')) {
            return 3;
        }
        if (startsWithAt(lower, index, 'dp')) {
            return 2;
        }
        return 0;
    }

    private static Boolean startsWithAt(String lower, Integer index, String prefix) {
        Integer endIndex = index + prefix.length();
        if (endIndex > lower.length()) {
            return false;
        }
        return lower.substring(index, endIndex) == prefix;
    }

    private static Integer skipSeparators(String value, Integer index) {
        Integer length = value.length();
        while (index < length) {
            String character = value.substring(index, index + 1);
            if (character == ' ' || character == '\t' || character == '-' || character == ',' || character == '/' || character == ':') {
                index += 1;
                continue;
            }
            break;
        }
        return index;
    }

    private static Integer consumeDigits(String value, Integer index) {
        Integer length = value.length();
        while (index < length) {
            String character = value.substring(index, index + 1);
            if (character >= '0' && character <= '9') {
                index += 1;
                continue;
            }
            break;
        }
        return index;
    }
}
