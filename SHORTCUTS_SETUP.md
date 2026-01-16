# Apple Shortcuts Integration Guide

This guide will help you set up Apple Shortcuts to add tracks and albums to your Music queue from the terminal app.

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

The script passes JSON that can be parsed into a dictionary. Add these actions in order:

**a. Receive Input from Shortcuts**
- This action receives the input passed from the terminal
- Input Type: Text
- The input will be JSON in one of these formats:
  - For tracks: `{"position":"next","track":"Song Name","artist":"Artist","album":"Album"}`
  - For albums: `{"position":"next","album":"Album Name","artist":"Artist Name"}`

**b. Get Dictionary from Input**
- This parses the JSON into a dictionary
- Store the result in variable: `Input Dict`

**c. Get Value for Key**
- Dictionary: `Input Dict`
- Key: `position`
- Store in variable: `Position`
- This is either "next" (add to beginning) or "last" (add to end)

**d. Get Value for Key**
- Dictionary: `Input Dict`
- Key: `track`
- Store in variable: `Track Name`
- This will be empty if it's an album request

**e. If Statement**
- Condition: `Track Name` is not empty
- This checks if we're adding a track or an album

**If True (Adding a Track):**

**f1. Get Value for Key**
- Dictionary: `Input Dict`
- Key: `artist`
- Store in variable: `Artist Name`

**g1. Get Value for Key**
- Dictionary: `Input Dict`
- Key: `album`
- Store in variable: `Album Name`

**h1. Text**
- Combine: `Track Name` + " " + `Artist Name`
- Store in: `Search Query`
- This creates a more precise search query

**i1. Play Music**
- Search: `Search Query`
- **Important**: Turn ON "Add to Up Next" (this adds to queue instead of playing)
- **Important**: Set "Add to Up Next" position based on `Position` variable:
  - If `Position` = "next": Add to beginning (play next)
  - If `Position` = "last": Add to end (default)
- Turn OFF "Shuffle" and "Repeat" if they're on

**If False (Adding an Album):**

**f2. Get Value for Key**
- Dictionary: `Input Dict`
- Key: `album`
- Store in variable: `Album Name`

**g2. Get Value for Key**
- Dictionary: `Input Dict`
- Key: `artist`
- Store in variable: `Artist Name` (may be empty)

**h2. Text**
- If `Artist Name` is not empty: Combine: `Album Name` + " " + `Artist Name`
- Otherwise: Use `Album Name` directly
- Store in: `Search Query`

**i2. Play Music**
- Search: `Search Query`
- **Important**: Turn ON "Add to Up Next"
- **Important**: Set "Add to Up Next" position based on `Position` variable:
  - If `Position` = "next": Add to beginning (play next)
  - If `Position` = "last": Add to end (default)
- Turn OFF "Shuffle" and "Repeat" if they're on
- This will search for the album and add all tracks to the queue

**j. Show Notification** (optional)
- Title: "Added to Queue"
- Body: Use `Track Name` if available, otherwise use `Album Name`

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

# Add an album to the queue
./am.sh queue -r "Album Name"

# Add an album to the beginning of queue (play next)
./am.sh queue --next -r "Album Name"

# The script will automatically invoke your Shortcut with JSON:
# For tracks: {"position":"last","track":"Track Name","artist":"Artist","album":"Album"}
# For albums: {"position":"last","album":"Album Name","artist":"Artist Name"}
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

### JSON Parsing Issues
- Make sure you're using "Get Dictionary from Input" action to parse the JSON
- Verify the JSON format matches the expected structure
- Check that all required keys are present in the dictionary

### Track/Album Not Added
- Make sure the "Play Music" action is configured correctly
- Check that the track/album exists in your Music library
- Verify the "Add to Up Next" option is turned ON in the "Play Music" action
- Ensure the position is set correctly (next = beginning, last = end)

### Permission Issues
- Make sure Shortcuts has permission to access Music
- Go to System Settings > Privacy & Security > Automation
- Ensure Shortcuts can control Music app

## JSON Format Reference

The script passes JSON that can be parsed into a dictionary. Here's the structure:

**For Tracks:**
```json
{
  "position": "next" | "last",
  "track": "Track Name",
  "artist": "Artist Name",
  "album": "Album Name"
}
```

**For Albums:**
```json
{
  "position": "next" | "last",
  "album": "Album Name",
  "artist": "Artist Name"  // May be empty
}
```

**Key Differences:**
- Tracks have a `track` key, albums don't
- Albums have an `album` key (tracks also have this for the album the track belongs to)
- Both have a `position` key indicating where to add in the queue
- Both may have an `artist` key

**How to Determine Type:**
- Check if the `track` key exists in the dictionary
- If `track` exists → it's a track request
- If `track` doesn't exist → it's an album request

## Direct Terminal Usage

You can use the queue command directly:

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

# Add all tracks from an album to beginning of queue
./am.sh queue --next -r "Album Name"

# Fzf to search for an album and add
./am.sh queue -r
```

**Queue Position Options:**
- `--next`: Add to beginning of queue (will play next)
- `--last` or no flag: Add to end of queue (default behavior)

**Available Options:**
- `-s`: Queue individual tracks (songs)
- `-r`: Queue entire albums

Both options use the Shortcut integration and pass JSON that can be parsed into a dictionary.
