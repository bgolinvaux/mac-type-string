# mac-type-string

A macOS CLI tool that types a Unicode character or arbitrary string into the
frontmost application, wherever the cursor is. Works with native apps, Electron
apps, browsers — anything that accepts keyboard input.

Uses `CGEvent` keyboard simulation (`CGEventKeyboardSetUnicodeString`) which is
far more reliable across apps than the Accessibility `AXUIElement` value-replace
approach.

Author: Claude, assisted by [Benjamin Golinvaux](https://github.com/bgolinvaux)
for preliminary research and testing 😀


## Usage

```sh
mac-type-string --unicode-char <hex>    Type the Unicode character U+<hex>
mac-type-string --string <text>         Type the given string
```

### Permissions

This tool posts `CGEvent` keyboard events. macOS requires the **calling
process** (or its parent) to have **Accessibility** permission. This means:


- If you invoke `mac-type-string` from **Terminal.app**, then Terminal needs Accessibility access.
- If you invoke it from **Alfred**, then Alfred itself (or
  whatever launches the shell command if you use a less direct approach) needs it.
- The same applies for any launcher, automation tool, or shell that calls it.

Grant permission in **System Settings → Privacy & Security → Accessibility**.

If the calling process is not trusted, `CGEvent` posting **silently fails** —
you will see no error, but nothing will be typed. Use `--verbose` to diagnose:
it will print whether `AXIsProcessTrusted()` returns true or false.

### Notes

All strings are supported, including newlines, emojis, etc.

A separate key event is generated for each Unicode character. Each character
takes slightly more than 3 milliseconds, so a string of 100 characters would
take around 300 milliseconds. This is usually fast enough, but keep it in mind
for very long strings.

### How to try it out

```sh
# Launch this and place the cursor in a text field within 5 seconds,
# e.g. a browser address bar or another tab of your terminal, then
# watch it type a right arrow (→)
sleep 5 && mac-type-string --unicode-char 2192

# multiple lines work too...
sleep 5 && mac-type-string --string "
# hello
# world
"
```

### Examples

```sh
mac-type-string --unicode-char 2192      # Types →
mac-type-string --unicode-char 1F600     # Types 😀
mac-type-string --string '→'             # Types →
mac-type-string --string 'Hello world'   # Types Hello world
```

## Build and install

```sh
# build it
just build
```
(which is just `swift build -c release` under the hood)

```sh
# install it
just install
```
The script will modify `.zshrc` to add `~/.local/bin` to the `PATH` if not
already there.

Normally, such instructions mention that you should restart your terminal 
or run `source ~/.zshrc` to apply the changes, but in this case, it does not
make much sense to use this command from the terminal, since it would type
into itself 😊.

The binary is at `.build/release/mac-type-string`. You may skip installation
and copy it wherever you like.

```sh
cp .build/release/mac-type-string /opt/alien-apps/
```

## Tests

Run the integration tests with:

```sh
just test
```

This builds the release binary, then runs `swift test`, which executes four
test cases (plain ASCII, Unicode arrow →, mixed Unicode string, and emoji 😀).

Each test:

1. Creates a temporary `.txt` file
2. Opens it in **TextEdit** via AppleScript
3. Runs `mac-type-string` to type text into TextEdit
4. Saves the file via AppleScript and reads it back
5. Asserts the file contents match the expected string
6. Closes the TextEdit document and deletes the temp file

### Don't touch anything during the test

The tests take about 10-20 seconds total. During that time, **TextEdit will
repeatedly pop up and become the frontmost app**. Do not click, type, or switch
windows — the tests send real keyboard events to whatever app is in front, so
any interference will cause failures.

### First-time permission prompts

The first time you run the tests, macOS will ask for two separate permissions:

1. **Automation permission**: _"Terminal.app wants to control TextEdit."_ This
   is needed for the AppleScript commands that open and save files. Click
   **OK**.
2. **Accessibility permission**: The test runner process (Terminal, VS Code
   integrated terminal, etc.) needs Accessibility access to post `CGEvent`
   keyboard events — the same requirement described in the [Permissions](#permissions) section.

Both prompts only appear once. After granting them, subsequent test runs work
silently.

### When tests cannot run

The tests require a **macOS GUI login session** (what Apple calls an _Aqua
session_). They will not work in any of these environments:

- **SSH sessions**: Even if you SSH into a Mac, the shell has no connection to
  the window server. `CGEvent` posting and AppleScript GUI automation both
  require an Aqua session.
- **CI services** (GitHub Actions, Jenkins, etc.): Most CI runners execute as
  headless LaunchDaemons with no GUI session, no window server, and no way to
  grant Accessibility permissions interactively. macOS CI _with_ a GUI session
  (e.g. a Mac mini with auto-login and a physical or virtual display) would
  work, but this is unusual.
- **LaunchDaemons**: System-level daemons run outside any user session and
  cannot access the window server.
- **`screen` or `tmux` over SSH**: Same as plain SSH — the shell is detached
  from any GUI session.

In these environments, the tests will fail with errors like _"no window server
connection"_ or TextEdit will simply fail to launch. There is no workaround:
`CGEvent` posting is fundamentally a GUI-session operation.

> **Note:** **LaunchAgents** (as opposed to LaunchDaemons) _do_ run within the
> user's login session and _can_ post `CGEvent`s, provided they have
> Accessibility permission. This is how tools like Karabiner work.

## Alfred integration
Use a script action 

![Alfred Script Action that calls 'mac-type-string --string 😊'](<docs/alfred-script-action.png>)

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

## Notes

### Why CGEvent requires a GUI session

`CGEvent` posting goes through the macOS **window server** (`WindowServer`
process). When you call `CGEvent.post(tap: .cghidEventTap)`, the event is
handed to the window server, which routes it to the frontmost application's
event queue — just like a real hardware keystroke.

If there is no window server (SSH, headless CI, LaunchDaemons), there is:

- No event routing infrastructure
- No concept of "frontmost application"
- No `CGEventTap` to intercept or inject events

Even a custom app that creates a `CGEventTap` to _listen_ for events would fail
— tap registration itself requires a window server connection. This is a
fundamental architectural constraint of macOS, not a permission issue. The
entire `CGEvent` system lives inside what Apple calls the _Aqua session_ — the
GUI login session tied to a physical or virtual display.

This means there is no way to write a "headless target" that receives `CGEvent`s
for testing purposes without a GUI session. If you need to test in CI, you would
need a macOS runner with auto-login and a display (physical or virtual).

### Why not use the AXUIElement Accessibility API?

The snippet below was the original approach found on StackOverflow. It uses the
Accessibility API to directly read the text content of the focused UI element,
splice in new text at the cursor position, and write it back:

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

This works for **native Cocoa text fields** (NSTextField, NSTextView) but fails
for Electron apps (VS Code, Slack, Discord), browsers, Terminal, and any control
that doesn't expose `kAXValueAttribute` as a writable attribute. Since the goal
of `mac-type-string` is to work in _any_ application, the `CGEvent` keyboard
simulation approach is far more reliable.


