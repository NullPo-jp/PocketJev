# Privacy

PocketJev is designed for local, on-device inference.

- Camera captures and selected photos are processed by the model on the iPhone.
- The app does not contain an image-upload or telemetry path.
- The AI model is downloaded from Hugging Face the first time the user prepares it, so network access is required for that initial model download.
- After the model is cached, inference itself does not require a cloud inference API.

The current model is `mlx-community/Qwen3-VL-2B-Instruct-4bit`.

If you modify the app to add analytics, remote inference, logging, or uploads,
this privacy description will no longer describe that modified build.
