# AO3 Companion App - Promotion Setup Guide

This project is configured to promote your AO3 companion app using **Twitter/X** and **YouTube Shorts**.

## Pre-configured Accounts

Two promotion accounts are already seeded in `.mp/`:

| Platform | Nickname | Content Focus |
|---|---|---|
| Twitter/X | AO3 Companion Promo | Tweets about AO3 app features, fanfiction tips, fandom culture |
| YouTube | AO3 Companion Shorts | Short videos about AO3 tips, app features, reading recommendations |

## Setup Checklist

### 1. Install Dependencies

```bash
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
```

### 2. Install & Start Ollama

Ollama provides the LLM that generates tweet text and video scripts.

```bash
# Install Ollama (macOS/Linux)
curl -fsSL https://ollama.com/install.sh | sh

# Pull a model (lightweight and fast)
ollama pull llama3.2:3b

# Start the server (runs on http://127.0.0.1:11434)
ollama serve
```

To skip the model picker at startup, set `"ollama_model": "llama3.2:3b"` in `config.json`.

### 3. Set Up Firefox Profile

Both Twitter and YouTube automation require a Firefox profile that is **already logged in** to the target platform.

1. Open Firefox and create a new profile: `firefox -ProfileManager`
2. Log in to **x.com** (Twitter) in one profile
3. Log in to **YouTube Studio** in another profile (or the same if using one account)
4. Find the profile path:
   - **Linux**: `~/.mozilla/firefox/<profile-name>/`
   - **macOS**: `~/Library/Application Support/Firefox/Profiles/<profile-name>/`
5. Update `config.json`:
   ```json
   "firefox_profile": "/path/to/your/firefox/profile"
   ```
6. Also update the account entries in `.mp/twitter.json` and `.mp/youtube.json` with the correct `firefox_profile` path.

### 4. Set Up Image Generation (YouTube Shorts only)

YouTube Shorts need AI-generated images. Get a Gemini API key:

1. Go to Google AI Studio and create an API key
2. Set it in `config.json`:
   ```json
   "nanobanana2_api_key": "your-gemini-api-key-here"
   ```

### 5. Install ImageMagick (YouTube Shorts only)

Required for subtitle rendering in videos.

```bash
# Ubuntu/Debian
sudo apt install imagemagick

# macOS
brew install imagemagick
```

The default `imagemagick_path` is `/usr/bin/convert`. Update `config.json` if your path differs.

## Running

```bash
# From the project root
python src/main.py
```

### Twitter Promotion
1. Select **"Twitter Bot"** from the menu
2. Select the **"AO3 Companion Promo"** account
3. Choose **"Post something"** for a single post, or **"Setup CRON Job"** for automated daily posting

### YouTube Shorts Promotion
1. Select **"YouTube Shorts Automation"** from the menu
2. Select the **"AO3 Companion Shorts"** account
3. Choose **"Upload Short"** to generate and upload a video, or **"Setup CRON Job"** for scheduled uploads

## Customizing Content

### Twitter Topic
Edit `.mp/twitter.json` and change the `"topic"` field to adjust what the LLM generates tweets about.

### YouTube Niche
Edit `.mp/youtube.json` and change the `"niche"` field to adjust video topics and scripts.

### Adding More Accounts
You can add multiple Twitter/YouTube accounts through the app menu, each with different topics for varied promotion angles (e.g., one account focused on fandom culture, another on app features).
