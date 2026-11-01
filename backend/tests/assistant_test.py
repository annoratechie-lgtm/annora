import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import asyncio
from app.api.v1.assistant import chat
from app.schemas.assistant import AssistantChatRequest

user_id = '97fe4f67-de72-40cc-9997-a7187b78d9e4'
message = AssistantChatRequest(message='How nutrition is most in my diet?')

response = asyncio.run(chat(message, user_id))
print(response)
