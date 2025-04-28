from typing import Optional

import ffmpeg
from dataclasses import dataclass
import logging


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
            # Safely attempt to get audio stream
            try:
                # Try to probe the input file to check if it has an audio stream
                probe = ffmpeg.probe(dto.video_path)
                audio_streams = [stream for stream in probe['streams'] if stream['codec_type'] == 'audio']
                
                if audio_streams:
                    audio_stream = video_stream.audio  # Only get audio if it exists
                else:
                    audio_stream = None
            except Exception:
                # If probing fails or any other error occurs, assume no audio
                audio_stream = None
                
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
        out, e = ffmpeg.run(output, overwrite_output=True, capture_stdout=True, capture_stderr=True)

        logging.info('stdout: %s', out.decode('utf8'))
        if e:
            logging.error('stderr: %s', e.decode('utf8'))

        return True
    except ffmpeg.Error as e:
        logging.error('FFmpeg error:  %s', e)
        logging.info('stdout: %s', e.stdout.decode('utf8'))
        logging.error('stderr: %s', e.stderr.decode('utf8'))
        return False