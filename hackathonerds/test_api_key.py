"""
Quick test to verify Google Gemini API key is working.
Run: python test_api_key.py
"""

import os
from dotenv import load_dotenv

load_dotenv()

api_key = os.getenv("GOOGLE_API_KEY")

if not api_key:
    print("[ERROR] GOOGLE_API_KEY not found in .env")
    exit(1)

print(f"[INFO] Key found: {api_key[:8]}...{api_key[-4:]}")

try:
    import google.generativeai as genai

    genai.configure(api_key=api_key)
    model = genai.GenerativeModel("gemini-2.0-flash")

    print("[INFO] Sending test request to Gemini...")
    response = model.generate_content("Reply with exactly: API key works")

    reply = response.text.strip()
    print(f"[OK]   Gemini response: {reply}")

except Exception as e:
    print(f"[ERROR] {e}")
