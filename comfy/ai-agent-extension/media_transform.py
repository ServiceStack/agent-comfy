from typing import Optional

import ffmpeg
from dataclasses import dataclass


@dataclass
class MediaTransformDTO:
    video_path: Optional[str] = None
    audio_path: Optional[str] = None
    image_path: Optional[str] = None
    watermark_path: Optional[str] = None
    output_path: str = None
    input_kwargs: dict = None
    output_kwargs: dict = None


def transform_media(dto: MediaTransformDTO) -> bool:
    try:
        # Start with the video input if available
        if dto.video_path:
            video_stream = ffmpeg.input(dto.video_path, **(dto.input_kwargs or {}))
            audio_stream = video_stream.audio  # Preserve original audio
        elif dto.audio_path:
            audio_stream = ffmpeg.input(dto.audio_path, **(dto.input_kwargs or {}))
            video_stream = None
        elif dto.image_path:
            video_stream = ffmpeg.input(dto.image_path, **(dto.input_kwargs or {}))
            audio_stream = None
        else:
            raise ValueError("No valid input provided")

        # Process video stream if present
        if video_stream:
            # Add image overlay if provided
            if dto.image_path and dto.video_path:
                image = ffmpeg.input(dto.image_path)
                video_stream = ffmpeg.overlay(video_stream, image)

            # Add watermark if provided
            if dto.watermark_path:
                watermark = ffmpeg.input(dto.watermark_path)
                video_stream = ffmpeg.overlay(video_stream, watermark)

        # Prepare output streams
        output_streams = []
        if video_stream:
            output_streams.append(video_stream)
        if audio_stream:
            output_streams.append(audio_stream)

        if not output_streams:
            raise ValueError("No output streams available")

        # Set up output
        if len(output_streams) == 1:
            output = ffmpeg.output(output_streams[0], dto.output_path, **(dto.output_kwargs or {}))
        else:
            output = ffmpeg.output(*output_streams, dto.output_path, **(dto.output_kwargs or {}))

        # Run FFmpeg command
        ffmpeg.run(output, overwrite_output=True)

        return True
    except ffmpeg.Error as e:
        print(f"An error occurred: {e.stderr.decode()}")
        return False