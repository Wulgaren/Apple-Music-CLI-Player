#!/bin/zsh

# XML Library Functions
# Get the path to the most recent XML library file
get_xml_library_path() {
	local alias_path="$HOME/Documents/Coding/Apple-Music-CLI-Player/xml alias"
	local xml_dir
	
	# Try to resolve the alias - if it's a symlink, use readlink
	if [ -L "$alias_path" ]; then
		xml_dir=$(readlink -f "$alias_path")
		xml_dir=$(dirname "$xml_dir")
	else
		# If it's a macOS alias, try to find the xml directory
		# Based on what we found, it points to Music Library Script/xml
		xml_dir="$HOME/Documents/Coding/Music Library Script/xml"
	fi
	
	# Find the most recent XML file
	if [ -d "$xml_dir" ]; then
		ls -t "$xml_dir"/Library*.xml 2>/dev/null | head -1
	else
		echo "Error: Could not find XML library directory" >&2
		return 1
	fi
}

# Parse XML and extract tracks in format: name|artist|album|genre
# This function caches the parsed data for performance
_xml_cache_file=""
_xml_cache_data=""
get_tracks_from_xml() {
	local xml_file="${1:-$(get_xml_library_path)}"
	
	# Use cache if same file and cache exists
	if [ -n "$_xml_cache_file" ] && [ "$_xml_cache_file" = "$xml_file" ] && [ -n "$_xml_cache_data" ]; then
		echo "$_xml_cache_data"
		return 0
	fi
	
	if [ ! -f "$xml_file" ]; then
		echo "Error: XML file not found: $xml_file" >&2
		return 1
	fi
	
	# Use Python to parse the plist XML efficiently
	_xml_cache_data=$(XML_FILE="$xml_file" python3 << 'PYTHON_EOF'
import plistlib
import sys
import os

xml_file = os.environ.get('XML_FILE', '')
if not xml_file or not os.path.exists(xml_file):
    sys.exit(1)

try:
    with open(xml_file, 'rb') as f:
        plist = plistlib.load(f)
    
    tracks = plist.get('Tracks', {})
    track_list = []
    
    for track_id, track_data in tracks.items():
        name = track_data.get('Name', '')
        artist = track_data.get('Artist', '')
        album = track_data.get('Album', '')
        genre = track_data.get('Genre', '')
        album_artist = track_data.get('Album Artist', '')
        
        # Skip tracks without a name
        if not name:
            continue
        
        # Use Album Artist as the artist field, fallback to Artist if Album Artist is empty
        # Format: name|album_artist|album|genre|artist (original artist kept for reference)
        display_artist = album_artist if album_artist else artist
        track_list.append(f"{name}|{display_artist}|{album}|{genre}|{artist}")
    
    print('\n'.join(track_list))
except Exception as e:
    sys.exit(1)
PYTHON_EOF
	)
	
	if [ $? -eq 0 ] && [ -n "$_xml_cache_data" ]; then
		_xml_cache_file="$xml_file"
		echo "$_xml_cache_data"
		return 0
	else
		echo "Error: Failed to parse XML file" >&2
		return 1
	fi
}

# Get unique values for a field (artist, album, genre)
get_unique_from_xml() {
	local field="$1"  # "artist", "album", or "genre"
	local xml_file="${2:-$(get_xml_library_path)}"
	
	local tracks=$(get_tracks_from_xml "$xml_file")
	if [ $? -ne 0 ]; then
		return 1
	fi
	
	case "$field" in
		artist)
			# Field 2 is now album_artist (after Python update)
			echo "$tracks" | awk -F'|' '{if ($2 != "") print $2}' | sort -u
			;;
		album)
			echo "$tracks" | awk -F'|' '{if ($3 != "") print $3}' | sort -u
			;;
		genre)
			echo "$tracks" | awk -F'|' '{if ($4 != "") print $4}' | sort -u
			;;
		*)
			return 1
			;;
	esac
}

# Get unique albums with their album artists in format: "Album - Album Artist"
get_albums_with_artists() {
	local xml_file="${1:-$(get_xml_library_path)}"
	
	local tracks=$(get_tracks_from_xml "$xml_file")
	if [ $? -ne 0 ]; then
		return 1
	fi
	
	# Get unique album-album_artist pairs, format as "Album - Album Artist"
	# Field 2 is now album_artist, field 3 is album
	echo "$tracks" | awk -F'|' '{
		if ($3 != "" && $2 != "") {
			# Use album and album artist
			print $3 " - " $2
		} else if ($3 != "") {
			# Album without artist
			print $3
		}
	}' | sort -u
}

# Get tracks filtered by field and value
get_tracks_by_field() {
	local field="$1"  # "artist", "album", or "genre"
	local value="$2"
	local xml_file="${3:-$(get_xml_library_path)}"
	
	local tracks=$(get_tracks_from_xml "$xml_file")
	if [ $? -ne 0 ]; then
		return 1
	fi
	
	case "$field" in
		artist)
			# Field 2 is now album_artist (after Python update), match against it
			echo "$tracks" | awk -F'|' -v val="$value" 'tolower($2) == tolower(val) {print $1 "|" $2 "|" $3 "|" $4}'
			;;
		album)
			echo "$tracks" | awk -F'|' -v val="$value" 'tolower($3) == tolower(val) {print $1 "|" $2 "|" $3 "|" $4}'
			;;
		genre)
			echo "$tracks" | awk -F'|' -v val="$value" 'tolower($4) == tolower(val) {print $1 "|" $2 "|" $3 "|" $4}'
			;;
		*)
			return 1
			;;
	esac
}

np(){
	# Helper function to format seconds into MM:SS
	format_time() {
		local seconds=$1
		local min=$(( seconds / 60 ))
		local sec=$(( seconds % 60 ))
		printf "%02d:%02d" $min $sec
	}
	
	init=1
	help='false'
	prev_name=""
	while :
	do
		vol=$(osascript -e 'tell application "Music" to get sound volume' 2>/dev/null || echo "0")
		shuffle=$(osascript -e 'tell application "Music" to get shuffle enabled' 2>/dev/null || echo "false")
		repeat=$(osascript -e 'tell application "Music" to get song repeat' 2>/dev/null || echo "off")
	    keybindings="
Keybindings:

p                       Play / Pause
f                       Forward one track
b                       Backward one track
>                       Begin fast forwarding current track
<                       Begin rewinding current track
R                       Resume normal playback
+                       Increase Music.app volume 5%
-                       Decrease Music.app volume 5%
s                       Toggle shuffle
r                       Toggle song repeat
q                       Quit np
Q                       Quit np and Music.app
?                       Show / hide keybindings"
		# Check if there's a current track playing
		current_name=$(osascript -e 'tell application "Music" to get name of current track' 2>/dev/null)
		if [ -z "$current_name" ]; then
			clear
			echo "No track currently playing"
			echo ""
			echo "Press 'p' to play, 'q' to quit, or '?' for help"
			input=$(/bin/bash -c "read -n 1 -t 1 input; echo \$input | xargs")
			if [[ "${input}" == *"p"* ]]; then
				osascript -e 'tell app "Music" to playpause' 2>/dev/null
			elif [[ "${input}" == *"q"* ]]; then
				clear
				exit
			elif [[ "${input}" == *"Q"* ]]; then
				killall Music
				clear
				exit
			elif [[ "${input}" == *"?"* ]]; then
				printf '%s\n' "$keybindings"
			fi
			read -sk 1 -t 0.001
			continue
		fi
		
		duration=$(osascript -e 'tell application "Music" to get {player position} & {duration} of current track' 2>/dev/null)
		if [ -z "$duration" ]; then
			clear
			echo "No track currently playing"
			echo ""
			echo "Press 'p' to play, 'q' to quit, or '?' for help"
			input=$(/bin/bash -c "read -n 1 -t 1 input; echo \$input | xargs")
			if [[ "${input}" == *"p"* ]]; then
				osascript -e 'tell app "Music" to playpause' 2>/dev/null
			elif [[ "${input}" == *"q"* ]]; then
				clear
				exit
			elif [[ "${input}" == *"Q"* ]]; then
				killall Music
				clear
				exit
			elif [[ "${input}" == *"?"* ]]; then
				printf '%s\n' "$keybindings"
			fi
			read -sk 1 -t 0.001
			continue
		fi
		
		arr=(`echo ${duration}`)
		curr=$(cut -d . -f 1 <<< ${arr[-2]} 2>/dev/null || echo "0")
		end=$(cut -d . -f 1 <<< ${arr[-1]} 2>/dev/null || echo "0")
		
		# Prevent division by zero
		if [ "$end" -eq 0 ]; then
			end=1
		fi
		
		currTime=$(format_time $curr)
		endTime=$(format_time $end)
		# Update track info if track changed or on first run or at start of track
		if (( curr < 2 || init == 1 )) || [ "$current_name" != "$prev_name" ]; then
			init=0
			prev_name="$current_name"
			name=${current_name:0:50}
			artist=$(osascript -e 'tell application "Music" to get artist of current track' 2>/dev/null || echo "Unknown Artist")
			artist=${artist:0:50}
			record=$(osascript -e 'tell application "Music" to get album of current track' 2>/dev/null || echo "Unknown Album")
			record=${record:0:50}
			# Re-fetch duration when track changes to ensure we get the correct duration for the new track
			duration=$(osascript -e 'tell application "Music" to get {player position} & {duration} of current track' 2>/dev/null)
			if [ -n "$duration" ]; then
				arr=(`echo ${duration}`)
				curr=$(cut -d . -f 1 <<< ${arr[-2]} 2>/dev/null || echo "0")
				end=$(cut -d . -f 1 <<< ${arr[-1]} 2>/dev/null || echo "0")
				# Prevent division by zero
				if [ "$end" -eq 0 ]; then
					end=1
				fi
			fi
			currTime=$(format_time $curr)
			endTime=$(format_time $end)
			if [ "$1" != "-t" ]
			then
				rm ~/Library/Scripts/tmp*
				osascript ~/Library/Scripts/album-art.applescript
				if [ -f ~/Library/Scripts/tmp.png ]; then
					art=$(clear; viu -b ~/Library/Scripts/tmp.png -w 31 -h 14)
				else
					art=$(clear; viu -b ~/Library/Scripts/tmp.jpg -w 31 -h 14)
				fi
			fi
			cyan=$(echo -e '\e[00;36m')
			magenta=$(echo -e '\033[01;35m')
			nocolor=$(echo -e '\033[0m')
		fi
		# Ensure vol is a number, default to 0 if not
		vol=${vol:-0}
		if [ "$vol" -eq 0 ] 2>/dev/null; then
			volIcon=🔇
		else
			volIcon=🔊
		fi
		# Calculate volume bar position (0-7 scale)
		vol=$(( vol / 12 ))
		# Ensure vol is within valid range
		if [ "$vol" -gt 7 ]; then
			vol=7
		elif [ "$vol" -lt 0 ]; then
			vol=0
		fi
		if [ $shuffle = 'false' ]; then
			shuffleIcon='➡️ '
		else
			shuffleIcon=🔀
		fi
		if [ $repeat = 'off' ]; then
			repeatIcon='↪️ '
		elif [ $repeat = 'one' ]; then
			repeatIcon=🔂
		else
			repeatIcon=🔁
		fi
		volBars='▁▂▃▄▅▆▇'
		volBG=${volBars:$vol}
		vol=${volBars:0:$vol}
		progressBars='▇▇▇▇▇▇▇▇▇'
		# Prevent division by zero
		if [ "$end" -gt 0 ]; then
			percentRemain=$(( (curr * 100) / end / 10 ))
		else
			percentRemain=0
		fi
		progBG=${progressBars:$percentRemain}
		prog=${progressBars:0:$percentRemain}
		if [ "$1" = "-t" ]
		then
			clear
			paste <(printf '%s\n' "$name" "$artist - $record" "$shuffleIcon $repeatIcon $(echo $currTime ${cyan}${prog}${nocolor}${progBG} $endTime)" "$volIcon $(echo "${magenta}$vol${nocolor}$volBG")") 
		else
			paste <(printf %s "$art") <(printf %s "") <(printf %s "") <(printf %s "") <(printf '%s\n' "$name" "$artist - $record" "$shuffleIcon $repeatIcon $(echo $currTime ${cyan}${prog}${nocolor}${progBG} $endTime)" "$volIcon $(echo "${magenta}$vol${nocolor}$volBG")") 
		fi
		if [ $help = 'true' ]; then
			printf '%s\n' "$keybindings"
		fi
		input=$(/bin/bash -c "read -n 1 -t 1 input; echo \$input | xargs")
		if [[ "${input}" == *"s"* ]]; then
			if $shuffle ; then
				osascript -e 'tell application "Music" to set shuffle enabled to false'
			else
				osascript -e 'tell application "Music" to set shuffle enabled to true'
			fi
		elif [[ "${input}" == *"r"* ]]; then
			if [ $repeat = 'off' ]; then
				osascript -e 'tell application "Music" to set song repeat to all'
			elif [ $repeat = 'all' ]; then
				osascript -e 'tell application "Music" to set song repeat to one'
			else
				osascript -e 'tell application "Music" to set song repeat to off'
			fi
		elif [[ "${input}" == *"+"* ]]; then
			osascript -e 'tell application "Music" to set sound volume to sound volume + 5'
		elif [[ "${input}" == *"-"* ]]; then
			osascript -e 'tell application "Music" to set sound volume to sound volume - 5'
		elif [[ "${input}" == *">"* ]]; then
			osascript -e 'tell application "Music" to fast forward'
		elif [[ "${input}" == *"<"* ]]; then
			osascript -e 'tell application "Music" to rewind'
		elif [[ "${input}" == *"R"* ]]; then
			osascript -e 'tell application "Music" to resume'
		elif [[ "${input}" == *"f"* ]]; then
			osascript -e 'tell app "Music" to play next track'
		elif [[ "${input}" == *"b"* ]]; then
			osascript -e 'tell app "Music" to back track'
		elif [[ "${input}" == *"p"* ]]; then
			osascript -e 'tell app "Music" to playpause'
		elif [[ "${input}" == *"q"* ]]; then
			clear
			exit
		elif [[ "${input}" == *"Q" ]]; then
			killall Music
			clear
			exit
		elif [[ "${input}" == *"?"* ]]; then
			if [ $help = 'false' ]; then
				help='true'
			else
				help='false'
			fi
		fi
		read -sk 1 -t 0.001
	done
}
list(){
	usage="Usage: list [-grouping] [name]

  -s                    List all songs.
  -r                    List all records.
  -r PATTERN            List all songs in the record PATTERN.
  -a                    List all artists.
  -a PATTERN            List all songs by the artist PATTERN.
  -p                    List all playlists.
  -p PATTERN            List all songs in the playlist PATTERN.
  -g                    List all genres.
  -g PATTERN            List all songs in the genre PATTERN."
	if [ "$#" -eq 0 ]; then
		printf '%s\n' "$usage";
	else
		if [ $1 = "-p" ]
		then
			# Playlists still need AppleScript since they're not in XML
			if [ "$#" -eq 1 ]; then
				shift
				osascript -e 'tell application "Music" to get name of playlists' "$*" | tr "," "\n" | sort | awk '!seen[$0]++' | /usr/bin/pr -t -a -3
			else
				shift
				osascript -e 'on run args' -e 'tell application "Music" to get name of every track of playlist (item 1 of args)' -e 'end' "$*" | tr "," "\n" | sort | awk '!seen[$0]++' | /usr/bin/pr -t -a -3
			fi
		elif [ $1 = "-s" ]
		then
			if [ "$#" -eq 1 ]; then
				shift
				get_tracks_from_xml | awk -F'|' '{print $1}' | sort | awk '!seen[$0]++' | /usr/bin/pr -t -a -3
			else
				echo $usage
			fi
		elif [ $1 = "-r" ]
		then
			if [ "$#" -eq 1 ]; then
				shift
				get_unique_from_xml album | /usr/bin/pr -t -a -3
			else
				shift
				get_tracks_by_field album "$*" | awk -F'|' '{print $1}' | sort | awk '!seen[$0]++' | /usr/bin/pr -t -a -3
			fi
		elif [ $1 = "-a" ]
		then
			if [ "$#" -eq 1 ]; then
				shift
				get_unique_from_xml artist | /usr/bin/pr -t -a -3
			else
				shift
				get_tracks_by_field artist "$*" | awk -F'|' '{print $1}' | sort | awk '!seen[$0]++' | /usr/bin/pr -t -a -3
			fi
		elif [ $1 = "-g" ]
		then
			if [ "$#" -eq 1 ]; then
				shift
				get_unique_from_xml genre | /usr/bin/pr -t -a -3
			else
				shift
				get_tracks_by_field genre "$*" | awk -F'|' '{print $1}' | sort | awk '!seen[$0]++' | /usr/bin/pr -t -a -3
			fi
		else
			printf '%s\n' "$usage";
		fi
	fi
}

play() {
	usage="Usage: play [-grouping] [name]

  -s                    Fzf for a song and begin playback.
  -s PATTERN            Play the song PATTERN.
  -r                    Fzf for a record and begin playback.
  -r PATTERN            Play from the record PATTERN.
  -a                    Fzf for an artist and begin playback.
  -a PATTERN            Play from the artist PATTERN.
  -p                    Fzf for a playlist and begin playback.
  -p PATTERN            Play from the playlist PATTERN.
  -g                    Fzf for a genre and begin playback.
  -g PATTERN            Play from the genre PATTERN.
  -l                    Play from your entire library."
	if [ "$#" -eq 0 ]; then
		printf '%s\n' "$usage"
	else
		if [ $1 = "-p" ]
		then
			if [ "$#" -eq 1 ]; then
				playlist=$(osascript -e 'tell application "Music" to get name of playlists' | tr "," "\n" | fzf)
				set -- ${playlist:1}
			else
				shift
			fi
			osascript -e 'on run argv
				tell application "Music" to play playlist (item 1 of argv)
			end' "$*"
		elif [ $1 = "-s" ]
		then
			if [ "$#" -eq 1 ]; then
				# Get only track names from XML (fast for large libraries)
				# Use case-insensitive sort to combine tracks with same name but different cases
				song=$(get_tracks_from_xml | awk -F'|' '{print $1}' | sort -uf | fzf)
				# Check if user cancelled fzf (empty selection)
				if [ -z "$song" ]; then
					exit 0
				fi
				# Check if there are multiple tracks with this name (case insensitive)
				# Get all tracks and filter for case-insensitive match (only when needed, after selection)
				all_tracks=$(get_tracks_from_xml)
				# Filter tracks with same name (case insensitive)
				track_list=$(echo "$all_tracks" | awk -F'|' -v song="$song" 'tolower($1) == tolower(song) {print $1 "|" $2 "|" $3}')
				# Count tracks with same name (case insensitive)
				match_count=$(echo "$track_list" | grep -v '^$' | wc -l | tr -d ' ')
				if [ "$match_count" -gt 1 ]; then
					# Multiple tracks with same name, show fzf with artist and album names
					formatted=$(echo "$track_list" | awk -F'|' '{print $1 " - " $2 " - " $3}' | fzf)
					# Check if user cancelled fzf
					if [ -z "$formatted" ]; then
						exit 0
					fi
					# Extract just the track name (before the first " - ")
					song=$(echo "$formatted" | sed 's/ - .*//' | xargs)
				fi
				set -- "$song"
			else
				shift
				query="$*"
				# Get all tracks from XML and filter by name containing the query
				track_list=$(get_tracks_from_xml)
				
				# Filter for case-insensitive match and format as "Track Name - Artist Name - Album Name"
				matches=$(echo "$track_list" | awk -F'|' -v query="$query" '
					tolower($1) ~ tolower(query) {
						print $1 " - " $2 " - " $3
					}
				')
				
				match_count=$(echo "$matches" | grep -v '^$' | wc -l | tr -d ' ')
				
				if [ "$match_count" -eq 0 ]; then
					echo "No tracks found matching: $query"
					exit 1
				fi
				
				# Count exact matches (case insensitive)
				exact_matches=$(echo "$track_list" | awk -F'|' -v query="$query" '
					tolower($1) == tolower(query) {
						print $1 " - " $2 " - " $3
					}
				')
				exact_count=$(echo "$exact_matches" | grep -v '^$' | wc -l | tr -d ' ')
				
				# If multiple matches or no exact match, show fzf with artist and album names
				if [ "$match_count" -gt 1 ] || [ "$exact_count" -ne 1 ]; then
					selected=$(echo "$matches" | fzf --query "$query")
					# Check if user cancelled fzf (empty selection)
					if [ -z "$selected" ]; then
						exit 0
					fi
					# Extract track name from the selected formatted string
					song=$(echo "$selected" | sed 's/ - .*//' | xargs)
					set -- "$song"
				else
					# Exactly one exact match, extract track name from exact_matches
					song=$(echo "$exact_matches" | sed 's/ - .*//' | xargs)
					set -- "$song"
				fi
			fi
		osascript -e 'on run argv
			tell application "Music"
				set trackName to item 1 of argv as string
				play track trackName
			end tell
		end' "$*"
		elif [ $1 = "-r" ]
		then
			if [ "$#" -eq 1 ]; then
				record=$(get_albums_with_artists | fzf)
				if [ -z "$record" ]; then
					exit 0
				fi
				# Extract just the album name (before " - ")
				record=$(echo "$record" | sed 's/ - .*//' | xargs)
				set -- "$record"
			else
				shift
				query="$*"
				record=$(get_albums_with_artists | fzf --query "$query")
				if [ -z "$record" ]; then
					exit 0
				fi
				# Extract just the album name (before " - ")
				record=$(echo "$record" | sed 's/ - .*//' | xargs)
				set -- "$record"
			fi
			osascript -e 'on run argv' -e 'tell application "Music"' -e 'if (exists playlist "temp_playlist") then' -e 'delete playlist "temp_playlist"' -e 'end if' -e 'set name of (make new playlist) to "temp_playlist"' -e 'set theseTracks to every track of playlist "Library" whose album is (item 1 of argv)' -e 'repeat with thisTrack in theseTracks' -e 'duplicate thisTrack to playlist "temp_playlist"' -e 'end repeat' -e 'play playlist "temp_playlist"' -e 'end tell' -e 'end' "$*"
		elif [ $1 = "-a" ]
		then
			if [ "$#" -eq 1 ]; then
				artist=$(get_unique_from_xml artist | fzf)
				if [ -z "$artist" ]; then
					exit 0
				fi
				set -- "$artist"
			else
				shift
			fi
			osascript -e 'on run argv' -e 'tell application "Music"' -e 'if (exists playlist "temp_playlist") then' -e 'delete playlist "temp_playlist"' -e 'end if' -e 'set name of (make new playlist) to "temp_playlist"' -e 'set theseTracks to every track of playlist "Library" whose artist is (item 1 of argv)' -e 'repeat with thisTrack in theseTracks' -e 'duplicate thisTrack to playlist "temp_playlist"' -e 'end repeat' -e 'play playlist "temp_playlist"' -e 'end tell' -e 'end' "$*"
		elif [ $1 = "-g" ]
		then
			if [ "$#" -eq 1 ]; then
				genre=$(get_unique_from_xml genre | fzf)
				if [ -z "$genre" ]; then
					exit 0
				fi
				set -- "$genre"
			else
				shift
			fi
			osascript -e 'on run argv' -e 'tell application "Music"' -e 'if (exists playlist "temp_playlist") then' -e 'delete playlist "temp_playlist"' -e 'end if' -e 'set name of (make new playlist) to "temp_playlist"' -e 'set theseTracks to every track of playlist "Library" whose genre is (item 1 of argv)' -e 'repeat with thisTrack in theseTracks' -e 'duplicate thisTrack to playlist "temp_playlist"' -e 'end repeat' -e 'play playlist "temp_playlist"' -e 'end tell' -e 'end' "$*"
		elif [ $1 = "-l" ]
		then
			osascript -e 'tell application "Music"' -e 'play playlist "Library"' -e 'end tell'
		else
			printf '%s\n' "$usage";
		fi
	fi
}

queue() {
	usage="Usage: queue [--next|--last] [-grouping] [name]

  --next                Add to beginning of queue (play next)
  --last                Add to end of queue (default)
  
  -s                    Fzf for a song and add to queue.
  -s PATTERN            Add the song PATTERN to queue.
  -r                    Fzf for a record and add to queue.
  -r PATTERN            Add tracks from the record PATTERN to queue."
	
	# Default to --last (add to end)
	queue_position="last"
	
	# Parse --next or --last flag
	if [ "$#" -gt 0 ] && [ "$1" = "--next" ]; then
		queue_position="next"
		shift
	elif [ "$#" -gt 0 ] && [ "$1" = "--last" ]; then
		queue_position="last"
		shift
	fi
	
	if [ "$#" -eq 0 ]; then
		printf '%s\n' "$usage"
		return
	fi
	
	case "$1" in
		-s)
			if [ "$#" -eq 1 ]; then
				song=$(get_tracks_from_xml | awk -F'|' '{print $1}' | sort -uf | fzf)
				[ -z "$song" ] && exit 0
				all_tracks=$(get_tracks_from_xml)
				track_list=$(echo "$all_tracks" | awk -F'|' -v song="$song" 'tolower($1) == tolower(song) {print $1 "|" $2 "|" $3}')
				match_count=$(echo "$track_list" | grep -v '^$' | wc -l | tr -d ' ')
				if [ "$match_count" -gt 1 ]; then
					formatted=$(echo "$track_list" | awk -F'|' '{print $1 " - " $2 " - " $3}' | fzf)
					[ -z "$formatted" ] && exit 0
					track_name=$(echo "$formatted" | sed 's/ - .*//' | xargs)
					artist_name=$(echo "$formatted" | sed 's/^[^\-]* - //' | sed 's/ - .*//' | xargs)
					album_name=$(echo "$formatted" | sed 's/^[^\-]* - [^\-]* - //' | xargs)
				else
					track_name=$(echo "$track_list" | awk -F'|' '{print $1}' | head -n 1 | xargs)
					artist_name=$(echo "$track_list" | awk -F'|' '{print $2}' | head -n 1 | xargs)
					album_name=$(echo "$track_list" | awk -F'|' '{print $3}' | head -n 1 | xargs)
				fi
				shortcuts_queue "$queue_position" "$track_name" "$artist_name" "$album_name"
			else
				shift
				query="$*"
				track_list=$(get_tracks_from_xml)
				matches=$(echo "$track_list" | awk -F'|' -v query="$query" 'tolower($1) ~ tolower(query) {print $1 " - " $2 " - " $3}')
				match_count=$(echo "$matches" | grep -v '^$' | wc -l | tr -d ' ')
				[ "$match_count" -eq 0 ] && echo "No tracks found matching: $query" && exit 1
				exact_matches=$(echo "$track_list" | awk -F'|' -v query="$query" 'tolower($1) == tolower(query) {print $1 " - " $2 " - " $3}')
				exact_count=$(echo "$exact_matches" | grep -v '^$' | wc -l | tr -d ' ')
				if [ "$match_count" -gt 1 ] || [ "$exact_count" -ne 1 ]; then
					selected=$(echo "$matches" | fzf --query "$query")
					[ -z "$selected" ] && exit 0
					track_name=$(echo "$selected" | sed 's/ - .*//' | xargs)
					artist_name=$(echo "$selected" | sed 's/^[^\-]* - //' | sed 's/ - .*//' | xargs)
					album_name=$(echo "$selected" | sed 's/^[^\-]* - [^\-]* - //' | xargs)
				else
					track_name=$(echo "$exact_matches" | sed 's/ - .*//' | xargs)
					artist_name=$(echo "$exact_matches" | sed 's/^[^\-]* - //' | sed 's/ - .*//' | xargs)
					album_name=$(echo "$exact_matches" | sed 's/^[^\-]* - [^\-]* - //' | xargs)
				fi
				shortcuts_queue "$queue_position" "$track_name" "$artist_name" "$album_name"
			fi
			;;
		-r)
			if [ "$#" -eq 1 ]; then
				record=$(get_albums_with_artists | fzf)
				[ -z "$record" ] && exit 0
				# Extract just the album name (before " - ")
				record=$(echo "$record" | sed 's/ - .*//' | xargs)
				set -- "$record"
			else
				shift
				query="$*"
				record=$(get_albums_with_artists | fzf --query "$query")
				[ -z "$record" ] && exit 0
				# Extract just the album name (before " - ")
				record=$(echo "$record" | sed 's/ - .*//' | xargs)
				set -- "$record"
			fi
			album_name="$*"
			# Get artist from the first track of this album from XML
			album_tracks=$(get_tracks_by_field album "$album_name")
			artist_name=$(echo "$album_tracks" | awk -F'|' '{if ($2 != "") {print $2; exit}}')
			# Pass album info as JSON to shortcuts_queue
			shortcuts_queue "$queue_position" "" "$artist_name" "$album_name" "album"
			;;
		*)
			printf '%s\n' "$usage"
			;;
	esac
}

shortcuts_queue() {
	# Helper function to invoke Apple Shortcut for queueing
	# Takes position, track name, artist, album/name, and type as arguments
	# Format: shortcuts_queue "next|last" "Track Name" "Artist Name" "Album/Name" "track|album"
	# For tracks: shortcuts_queue "next" "Song Name" "Artist" "Album" "track"
	# For albums: shortcuts_queue "next" "" "" "Album Name" "album"
	
	if [ "$#" -lt 2 ]; then
		echo "Error: Position required"
		exit 1
	fi
	
	queue_position="$1"
	track_name="${2:-}"
	artist_name="${3:-}"
	name_or_album="${4:-}"
	type="${5:-track}"
	shortcut_name="${SHORTCUT_QUEUE_NAME:-Add to Queue}"
	
	# Build JSON input for Apple Shortcuts (can be parsed into a dictionary)
	if [ "$type" = "album" ]; then
		# JSON format for album search
		if [ -n "$artist_name" ]; then
			input=$(printf '{"position":"%s","album":"%s","artist":"%s"}' "$queue_position" "$name_or_album" "$artist_name")
		else
			input=$(printf '{"position":"%s","album":"%s"}' "$queue_position" "$name_or_album")
		fi
		display_name="$name_or_album"
	else
		# JSON format for track
		input=$(printf '{"position":"%s","track":"%s","artist":"%s","album":"%s"}' "$queue_position" "$track_name" "$artist_name" "$name_or_album")
		display_name="$track_name"
	fi
	
	# Invoke the Shortcut
	shortcuts run "$shortcut_name" <<< "$input" 2>/dev/null
	
	if [ $? -eq 0 ]; then
		if [ "$type" = "album" ]; then
			echo "Added album to queue: $display_name"
		else
			echo "Added to queue: $display_name"
		fi
	else
		echo "Error: Failed to add to queue. Make sure the Shortcut '$shortcut_name' exists."
		exit 1
	fi
}

usage="Usage: am.sh [function] [-grouping] [name]

  list -s              	List all songs in your library.
  list -r              	List all records.
  list -r PATTERN       List all songs in the record PATTERN.
  list -a              	List all artists.
  list -a PATTERN       List all songs by the artist PATTERN.
  list -p              	List all playlists.
  list -p PATTERN       List all songs in the playlist PATTERN.
  list -g              	List all genres.
  list -g PATTERN       List all songs in the genre PATTERN.

  play -s               Fzf for a song and begin playback.
  play -s PATTERN       Play the song PATTERN.
  play -r              	Fzf for a record and begin playback.
  play -r PATTERN       Play from the record PATTERN.
  play -a              	Fzf for an artist and begin playback.
  play -a PATTERN       Play from the artist PATTERN.
  play -p              	Fzf for a playlist and begin playback.
  play -p PATTERN       Play from the playlist PATTERN.
  play -g              	Fzf for a genre and begin playback.
  play -g PATTERN       Play from the genre PATTERN.
  play -l              	Play from your entire library.
  
  queue [--next|--last] -s    Fzf for a song and add to queue.
  queue [--next|--last] -s PATTERN  Add the song PATTERN to queue.
  queue [--next|--last] -r    Fzf for a record and add to queue.
  queue [--next|--last] -r PATTERN  Add tracks from the record PATTERN to queue.
  
  --next                 Add to beginning of queue (play next)
  --last                 Add to end of queue (default)
  
  shortcuts-queue TRACK  Add track to queue (for Apple Shortcuts integration).
  
  np                    Open the \"Now Playing\" TUI widget.
                        (Music.app track must be actively
			playing or paused)
  np -t			Open in text mode (disables album art)
 
  np keybindings:

  p                     Play / Pause
  f                     Forward one track
  b                     Backward one track
  >                     Begin fast forwarding current track
  <                     Begin rewinding current track
  R                     Resume normal playback
  +                     Increase Music.app volume 5%
  -                     Decrease Music.app volume 5%
  s                     Toggle shuffle
  r                     Toggle song repeat
  q                     Quit np
  Q                     Quit np and Music.app
  ?                     Show / hide keybindings"
if [ "$#" -eq 0 ]; then
	printf '%s\n' "$usage";
else
	if [ $1 = "np" ]
	then
		shift
		np "$@"
	elif [ $1 = "list" ]
	then
		shift
		list "$@"
	elif [ $1 = "play" ]
	then
		shift
		play "$@"
	elif [ $1 = "queue" ]
	then
		shift
		queue "$@"
	elif [ $1 = "shortcuts-queue" ]
	then
		shift
		shortcuts_queue "$@"
	else
		printf '%s\n' "$usage";
	fi
fi
