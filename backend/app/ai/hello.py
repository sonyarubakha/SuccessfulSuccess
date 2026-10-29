"""Make the first LLM call for Lab 6."""

import os

import boto3

from app.config import settings


def main() -> None:
    client = boto3.client(
        "bedrock-runtime",
        region_name=os.getenv("AWS_REGION", "us-east-1"),
    )

    response = client.converse(
        modelId=settings.parser_model,
        messages=[
            {
                "role": "user",
                "content": [{"text": "In one sentence: what is an ISO week?"}],
            }
        ],
        inferenceConfig={
            "maxTokens": 100,
            "temperature": 0,
        },
    )

    answer = next(
        block["text"] for block in response["output"]["message"]["content"] if "text" in block
    )

    usage = response["usage"]

    print(answer)
    print(f"stop_reason: {response['stopReason']}")
    print(f"input_tokens: {usage['inputTokens']}")
    print(f"output_tokens: {usage['outputTokens']}")
    print(f"latency_ms: {response['metrics']['latencyMs']}")


if __name__ == "__main__":
    main()
