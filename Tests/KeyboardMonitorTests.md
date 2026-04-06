# KeyboardMonitor Manual Verification

## Bug: `isKeyPressed` stuck if shortcut key changed mid-press

When the user holds a shortcut key (setting `isKeyPressed = true`) and then changes the shortcut key in Settings before releasing, the key-up event for the original key no longer matches the new `appState.shortcutKey`. This causes `isKeyPressed` to remain `true` permanently, meaning recording never stops.

### Fix

Added a `pressedKeyCode` property that tracks which physical key initiated the press. On key-up, the handler first checks whether the released key matches `pressedKeyCode`, regardless of the current shortcut setting. This ensures the release is always detected even if the shortcut was changed mid-press.

### Manual Test Steps

1. Start recording by holding the configured shortcut key (e.g., Globe/Fn).
2. While still holding the key, open Settings and change the shortcut key to a different option (e.g., Right Option).
3. Release the original key (Globe/Fn).
4. Verify that recording stops. Previously it would get stuck in the recording state.
5. Press and hold the newly configured shortcut key (Right Option) and verify a new recording starts.
6. Release the new shortcut key and verify recording stops normally.

### Expected Results

- Step 4: Recording stops when the original key is released, even though the shortcut setting now points to a different key.
- Step 5-6: The new shortcut key works correctly for subsequent recordings.
