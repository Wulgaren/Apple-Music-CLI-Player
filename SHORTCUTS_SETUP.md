# Apple Shortcuts Integration Guide

This guide will help you set up Apple Shortcuts to add tracks to your Music queue from the terminal app.

## Prerequisites

- macOS with Apple Music app
- Apple Shortcuts app installed
- The `am.sh` script accessible

## Setting Up the Shortcut

### Step 1: Create the Shortcut

1. Open the **Shortcuts** app
2. Click the **+** button to create a new shortcut
3. Name it: **"Add to Queue"** (or any name you prefer, but remember it for later)

### Step 2: Configure the Shortcut Actions

Add these actions in order:

**a. Receive Input from Shortcuts**
- This action receives the input passed from the terminal
- Input Type: Text
- The input will be in format: `next|Track Name|Artist Name|Album Name` or `last|Track Name|Artist Name|Album Name`
- `next` = add to beginning (play next), `last` = add to end (default)

**b. Split Text**
- Split by: Custom
- Separator: `|`
- This splits the input into four parts: position, track name, artist, album

**c. Get Item from List**
- Get: First Item
- This is the position (`next` or `last`)
- Store in variable: `Position`

**d. Get Item from List**
- Get: Item at Index 2
- This is the track name
- Store in variable: `Track Name`

**e. Play Music** (This is the key action!)
- Search: `Track Name` variable
- **Important**: Turn ON "Add to Up Next" (this adds to queue instead of playing)
- **Important**: Set "Add to Up Next" position based on `Position` variable:
  - If `Position` = "next": Add to beginning (play next)
  - If `Position` = "last": Add to end (default)
- Turn OFF "Shuffle" and "Repeat" if they're on
- This will search for the track and add it to the queue at the specified position

**Alternative Method (More Precise):**

If you want to use artist and album for more precise matching:

**c. Get Item from List**
- Get: First Item (position: `next` or `last`)
- Store in: `Position`

**d. Get Item from List**
- Get: Item at Index 2 (track name)
- Store in: `Track Name`

**e. Get Item from List**  
- Get: Item at Index 3 (artist name)
- Store in: `Artist Name`

**f. Text**
- Combine: `Track Name` + " " + `Artist Name`
- Store in: `Search Query`

**g. Play Music**
- Search: `Search Query`
- Turn ON "Add to Up Next"
- Set position based on `Position` variable (next = beginning, last = end)
- This searches for "Track Name Artist Name" which is more precise

**h. Show Notification** (optional)
- Title: "Added to Queue"
- Body: `Track Name` by `Artist Name`

### Step 3: Configure Shortcut Settings

1. Click the shortcut name at the top
2. Enable **"Use as Quick Action"** (optional, for easier access)
3. Make sure **"Show in Share Sheet"** is enabled if you want to use it from other apps

## Using from Terminal

Once the shortcut is set up, you can use it from the terminal:

```bash
# Add a track to the end of queue (default)
./am.sh queue -s "Sweet Dreams"

# Add a track to the beginning of queue (play next)
./am.sh queue --next -s "Sweet Dreams"

# Explicitly add to end (same as default)
./am.sh queue --last -s "Sweet Dreams"

# Add a track with full search (defaults to end of queue)
./am.sh queue -s sweet

# The script will automatically invoke your Shortcut with:
# "last|Track Name|Artist Name|Album Name" (or "next|..." for --next)
```

## Custom Shortcut Name

If you named your shortcut something other than "Add to Queue", set the environment variable:

```bash
export SHORTCUT_QUEUE_NAME="Your Shortcut Name"
```

Or add it to your `~/.zshrc` or `~/.bashrc`:

```bash
export SHORTCUT_QUEUE_NAME="Add to Queue"
```

## Testing

1. Run: `./am.sh queue -s "Sweet Dreams"`
2. The script should invoke your Shortcut
3. Check the Music app to verify the track is in the queue

## Troubleshooting

### Shortcut Not Found
- Make sure the shortcut name matches exactly (case-sensitive)
- Check the shortcut name: `shortcuts list` in terminal
- Set `SHORTCUT_QUEUE_NAME` environment variable if needed

### Track Not Added
- Make sure the "Find Music" action is configured correctly
- Check that the track exists in your Music library
- Verify the "Add to Up Next" action is present in your shortcut

### Permission Issues
- Make sure Shortcuts has permission to access Music
- Go to System Settings > Privacy & Security > Automation
- Ensure Shortcuts can control Music app

## Alternative: Simple Track Name Only

If you want a simpler shortcut that only uses the track name:

1. Skip the "Split Text" and "Get Item" actions
2. Use the input directly in "Find Music"
3. Update the script to only pass the track name (modify `shortcuts_queue` function)

## Direct Terminal Usage

You can also use the queue command directly:

```bash
# Add a specific track to end of queue (default)
./am.sh queue -s "Sweet Dreams"

# Add a track to beginning of queue (play next)
./am.sh queue --next -s "Sweet Dreams"

# Add to end explicitly
./am.sh queue --last -s "Sweet Dreams"

# Fzf to search and add (defaults to end)
./am.sh queue -s

# Fzf to search and add to beginning
./am.sh queue --next -s

# Add all tracks from an album
./am.sh queue -r "Album Name"

# Add all tracks from an artist
./am.sh queue -a "Artist Name"
```

**Queue Position Options:**
- `--next` or no flag: Add to beginning of queue (will play next)
- `--last`: Add to end of queue (default behavior)

Note: Currently only `-s` (songs) uses the Shortcut integration. Other options may need additional setup.
