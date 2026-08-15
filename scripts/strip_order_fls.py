from pathlib import Path
import re

path = Path(r"c:\Users\matth\Github Local\Propump billing controller\force-app\main\default\permissionsets\Billing_Control_Center_User.permissionset-meta.xml")
text = path.read_text(encoding="utf-8")
text = re.sub(
    r"    <fieldPermissions>\s*<editable>.*?</editable>\s*<field>Order\.[^<]+</field>\s*<readable>.*?</readable>\s*</fieldPermissions>\n",
    "",
    text,
    flags=re.S,
)
text = re.sub(
    r"    <objectPermissions>\s*<allowCreate>.*?</allowCreate>\s*<allowDelete>.*?</allowDelete>\s*<allowEdit>.*?</allowEdit>\s*<allowRead>.*?</allowRead>\s*<modifyAllRecords>.*?</modifyAllRecords>\s*<object>Order</object>\s*<viewAllRecords>.*?</viewAllRecords>\s*</objectPermissions>\n",
    "",
    text,
    flags=re.S,
)
path.write_text(text, encoding="utf-8")
print("remaining Order.", text.count("Order."))
print("remaining >Order<", ">Order<" in text)
