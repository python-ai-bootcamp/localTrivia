import urllib.request
import os

sounds = {
    "beep.mp3": "https://raw.githubusercontent.com/avelas68/Hablas/main/Beep.mp3",
    "correct.mp3": "https://raw.githubusercontent.com/ramzan/Virtuosity/main/app/src/main/res/raw/bell.mp3",
    "wrong.mp3": "https://raw.githubusercontent.com/matloughnane/family-fortune-game/master/assets/audio/buzzer.mp3",
    "applause.mp3": "https://raw.githubusercontent.com/millz83/Sound-Board-Project/master/sounds/applause.mp3"
}

dest_dir = "frontend/assets/sounds"
os.makedirs(dest_dir, exist_ok=True)

for name, url in sounds.items():
    dest_path = os.path.join(dest_dir, name)
    print(f"Downloading {url} to {dest_path}...")
    try:
        urllib.request.urlretrieve(url, dest_path)
        print(f"Successfully downloaded {name} ({os.path.getsize(dest_path)} bytes)")
    except Exception as e:
        print(f"Failed to download {name}: {e}")
