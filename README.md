# mac-type-string

A macOS CLI tool that types a Unicode character or arbitrary string into the
frontmost application, wherever the cursor is. Works with native apps, Electron
apps, browsers — anything that accepts keyboard input.

Uses `CGEvent` keyboard simulation (`CGEventKeyboardSetUnicodeString`) which is
far more reliable across apps than the Accessibility `AXUIElement` value-replace
approach.

## Build

```bash
swift build -c release
```

The binary is at `.build/release/mac-type-string`. Copy it wherever you like:

```bash
cp .build/release/mac-type-string /usr/local/bin/
```

## Usage

```
mac-type-string --unicode-char <hex>    Type the Unicode character U+<hex>
mac-type-string --string <text>         Type the given string
```

### Examples

```bash
mac-type-string --unicode-char 2192      # Types →
mac-type-string --unicode-char 1F600     # Types 😀
mac-type-string --string '→'             # Types →
mac-type-string --string 'Hello world'   # Types Hello world
```

## Permissions

The tool posts `CGEvent` keyboard events. macOS requires the calling process
(or its parent, e.g. Karabiner) to have **Accessibility** permission.

Go to **System Settings → Privacy & Security → Accessibility** and grant
permission to the app that launches the binary (Karabiner-Elements, Terminal,
etc.).

## Karabiner integration

In your Karabiner `complex_modifications`, call the binary from a
`shell_command`:

```json
{
  "type": "basic",
  "from": { "key_code": "period", "modifiers": { "mandatory": ["option"] } },
  "to": [{ "shell_command": "/usr/local/bin/mac-type-string --unicode-char 2192" }]
}
```

## Original AXUIElement snippet (for reference)

The snippet below was the original approach found on StackOverflow. It uses the
Accessibility API to directly replace the text value of the focused UI element.
This works for native Cocoa text fields but fails for Electron apps, browsers,
and any control that doesn't expose `kAXValueAttribute`:

```objc
AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute, &focusedUI);

if (focusedUI) {
    CFTypeRef textValue, textRange;
    // get text content and range
    AXUIElementCopyAttributeValue(focusedUI, kAXValueAttribute, &textValue);
    AXUIElementCopyAttributeValue(focusedUI, kAXSelectedTextRangeAttribute, &textRange);

    NSRange range;
    AXValueGetValue(textRange, kAXValueCFRangeType, &range);
    // replace current range with new text
    NSString *newTextValue = [(__bridge NSString *)textValue stringByReplacingCharactersInRange:range withString:newText];
    AXUIElementSetAttributeValue(focusedUI, kAXValueAttribute, (__bridge CFStringRef)newTextValue);
    // set cursor to correct position
    range.length = 0;
    range.location += text.length;
    AXValueRef valueRef = AXValueCreate(kAXValueCFRangeType, (const void *)&range);
    AXUIElementSetAttributeValue(focusedUI, kAXSelectedTextRangeAttribute, valueRef);

    CFRelease(textValue);
    CFRelease(textRange);
    CFRelease(focusedUI);
}
```


