# oracles/src/domain/llm/openai_structured_llm.py
import backoff
from typing import Optional, Type
from pydantic import BaseModel
import openai
from openai import AsyncOpenAI
from openai.types.chat import ChatCompletion
from src.entities import Chat
from src.domain.llm.utils import TIMEOUT
import settings

# Base dynamic structure
class BaseDynamicModel(BaseModel):
    pass

# Retry logic using backoff
@backoff.on_exception(
    backoff.expo, (openai.RateLimitError, openai.APITimeoutError), max_tries=3
)
async def execute(chat: Chat, output_model: Optional[Type[BaseModel]] = None) -> Optional[ChatCompletion]:
    client = AsyncOpenAI(
        api_key=settings.OPEN_AI_API_KEY,
        timeout=TIMEOUT,
    )

    if output_model is not None:
        # Using parse for structured output with dynamic models
        chat_completion = await client.chat.completions.parse(
            messages=chat.messages,
            model=chat.config.model,
            frequency_penalty=chat.config.frequency_penalty,
            logit_bias=chat.config.logit_bias,
            max_tokens=chat.config.max_tokens,
            presence_penalty=chat.config.presence_penalty,
            response_format=output_model,  # Custom model passed here
            seed=chat.config.seed,
            temperature=chat.config.temperature,
            top_p=chat.config.top_p,
            tools=chat.config.tools,
            tool_choice=chat.config.tool_choice,
            user=chat.config.user,
        )
    else:
        # Default behavior using `create`
        chat_completion: ChatCompletion = await client.chat.completions.create(
            messages=chat.messages,
            model=chat.config.model,
            frequency_penalty=chat.config.frequency_penalty,
            logit_bias=chat.config.logit_bias,
            max_tokens=chat.config.max_tokens,
            presence_penalty=chat.config.presence_penalty,
            response_format=chat.config.response_format,
            seed=chat.config.seed,
            temperature=chat.config.temperature,
            top_p=chat.config.top_p,
            tools=chat.config.tools,
            tool_choice=chat.config.tool_choice,
            user=chat.config.user,
        )
    
    # Ensure we have either content or function calls
    assert (
        chat_completion.choices[0].message.content
        or chat_completion.choices[0].message.tool_calls
    )

    # Return parsed content if structured model is used
    if output_model is not None:
        return chat_completion.choices[0].message.parsed
    else:
        return chat_completion