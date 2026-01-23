#!/bin/bash
# Check durations of all MIDI files in the Songs directory

cd "$(dirname "$0")"
source .venv/bin/activate

python3 << 'EOF'
import mido
import os

songs_dir = "TilesRemake/Songs"
songs = []

for f in sorted(os.listdir(songs_dir)):
    if f.endswith('.mid'):
        path = os.path.join(songs_dir, f)
        try:
            mid = mido.MidiFile(path)
            duration = mid.length
            mins = int(duration // 60)
            secs = int(duration % 60)
            songs.append((f.replace('.mid', ''), mins, secs, duration))
        except Exception as e:
            print(f"Error reading {f}: {e}")

songs.sort(key=lambda x: x[3])

print(f"\n{'Song':<45} Duration")
print("-" * 60)
for name, mins, secs, dur in songs:
    print(f"{name:<45} {mins}:{secs:02d}")
print()
EOF

echo "Press any key to close..."
read -n 1
