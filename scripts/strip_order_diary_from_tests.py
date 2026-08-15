"""Strip Order-diary field usage from BCC Apex tests. Brace-aware for Order constructors."""
from pathlib import Path
import re

ROOT = Path(r"c:\Users\matth\Github Local\Propump billing controller")
SERVICE = ROOT / "force-app/main/default/classes/BillingControl_InvoicingTest.cls"
PROVIDER = ROOT / "force-app/main/default/classes/BillingControl_DataProviderTest.cls"

DROP_ORDER_ARGS = {
    "Work_Order__c",
    "Service_Appointment__c",
    "Technician__c",
    "Billing_Diary_Status__c",
    "Ready_For_Billing__c",
    "Billable_Amount__c",
    "Invoiced_Amount__c",
    "Received_Amount__c",
}


def matching_paren(text: str, open_index: int) -> int:
    depth = 0
    i = open_index
    in_string = False
    quote = ""
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                in_string = False
            i += 1
            continue
        if ch in ("'", '"'):
            in_string = True
            quote = ch
            i += 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced paren")


def split_args(body: str) -> list[str]:
    args = []
    start = 0
    depth = 0
    in_string = False
    quote = ""
    i = 0
    while i < len(body):
        ch = body[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                in_string = False
            i += 1
            continue
        if ch in ("'", '"'):
            in_string = True
            quote = ch
            i += 1
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            args.append(body[start:i])
            start = i + 1
        i += 1
    args.append(body[start:])
    return args


def strip_order_ctors(text: str) -> str:
    needle = "new Order("
    out = []
    i = 0
    while True:
        found = text.find(needle, i)
        if found < 0:
            out.append(text[i:])
            break
        out.append(text[i:found])
        open_index = found + len(needle) - 1
        close_index = matching_paren(text, open_index)
        body = text[open_index + 1 : close_index]
        kept = []
        for arg in split_args(body):
            stripped = arg.strip()
            name = stripped.split("=", 1)[0].strip()
            if name in DROP_ORDER_ARGS:
                continue
            if stripped:
                kept.append(arg.rstrip())
        rebuilt = ", ".join(part.strip() if "\n" not in part else part.rstrip() for part in kept)
        # Preserve multiline style when any original arg was multiline.
        if "\n" in body:
            indent = "\n            "
            rebuilt = indent + ("," + indent).join(part.strip() for part in kept) + "\n        "
        out.append("new Order(" + rebuilt + ")")
        i = close_index + 1
    return "".join(out)


def strip_billing_order_lines(text: str) -> str:
    return re.sub(r"^[ \t]*Billing_Order__c\s*=.*?,\s*\n", "", text, flags=re.M)


def strip_invoiced_helper(text: str) -> str:
    return re.sub(
        r"\n    private static String getExpectedInvoicedOrderDiaryStatusValue\(\) \{.*?\n    \}\n",
        "\n",
        text,
        flags=re.S,
    )


def main() -> None:
    for path in (SERVICE, PROVIDER):
        original = path.read_text(encoding="utf-8")
        text = strip_order_ctors(original)
        text = strip_billing_order_lines(text)
        text = strip_invoiced_helper(text)
        path.write_text(text, encoding="utf-8")
        print(f"updated {path.name} ({len(original)} -> {len(text)})")


if __name__ == "__main__":
    main()
