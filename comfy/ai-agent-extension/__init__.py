try:
    import server
    import folder_paths
    from .main import *
    from .audio_to_text import AudioToText
    from .media_transform import MediaTransformDTO, transform_media
    from .ffmpeg_route import *

    NODE_CLASS_MAPPINGS = {
        "AudioToTextWhisper": AudioToText
    }

    NODE_DISPLAY_NAME_MAPPINGS = {
        "AudioToTextWhisper": "Audio to Text (Whisper)"
    }
except ImportError:
    # First print the exception
    import traceback
    traceback.print_exc()

    print('ComfyUI `server` not found, extension requires comfyui to run.')
    # Don't raise error, as this is a common case when running tests


