import torchaudio
import whisper
import tempfile
import json
import os


class AudioToText:
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "audio": ("AUDIO",),
                "model": (["base", "tiny", "small", "medium", "large"],),
            }
        }

    RETURN_TYPES = ("STRING","STRING")
    RETURN_NAMES = ("text","text_with_timestamps")
    FUNCTION = "apply_stt"
    CATEGORY = "whisper"

    def apply_stt(self, audio, model):
        # Load the whisper model and transcribe the audio
        model = whisper.load_model(model)
        results = []
        text_with_timestamps = []

        for (batch_number, waveform) in enumerate(audio["waveform"]):
            # Create a named temporary file
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_audio_file:
                # Write audio bytes to the temporary file
                print("Writing audio to temporary file")
                # Get the file path
                audio_save_path = temp_audio_file.name
                torchaudio.save(audio_save_path, waveform, audio["sample_rate"], format="FLAC")

            result_text = model.transcribe(audio_save_path, word_timestamps=True)
            segments = result_text["segments"]

            # Create a list of strings with timestamps text, start, end to nearest second

            for segment in segments:
                # Append dict to list
                text_with_timestamps.append({
                    "text": segment["text"].strip(),
                    "start": int(segment["start"]),
                    "end": int(segment["end"])
                })

            results.append(result_text["text"].strip())

            # Clean up: remove the temporary file
            os.remove(audio_save_path)

        return ("\n".join(results), json.dumps(text_with_timestamps))
