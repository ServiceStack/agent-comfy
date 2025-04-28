from aiohttp import web
import json
from .media_transform import MediaTransformDTO, transform_media
import os
import hashlib
import logging

# server comes from ComfyUI, only import if present
try:
    import server
    import folder_paths
except ImportError:
    # throw error if server is not present
    raise ImportError('ComfyUI `server` not found, extension requires ComfyUI to run.')

prompt_server = server.PromptServer.instance
app = prompt_server.app
routes = prompt_server.routes

# Configure upload folders
UPLOAD_FOLDER = '/data/input/ffmpeg'
OUTPUT_FOLDER = '/data/output/ffmpeg'

# Ensure upload and output folders exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(OUTPUT_FOLDER, exist_ok=True)

def allowed_file(filename):
    allowed_extensions = {
        # Image formats
        'png', 'jpg', 'jpeg', 'gif', 'bmp', 'tiff', 'webp',
        # Video formats
        'mp4', 'avi', 'mov', 'mkv', 'flv', 'wmv', 'webm', 'mpeg', '3gp',
        # Audio formats
        'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma'
    }
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in allowed_extensions


def save_file(file_content, filename):
    if file_content and allowed_file(filename):
        sha256_hash = hashlib.sha256(file_content).hexdigest()
        _, extension = os.path.splitext(filename)
        save_filename = f"{sha256_hash}{extension}"
        filepath = os.path.join(UPLOAD_FOLDER, save_filename)
        with open(filepath, 'wb') as f:
            f.write(file_content)
        return filepath
    return None

@routes.get('/status')
async def status(request):
    return web.json_response({'status': 'ok'})

@routes.post('/transform')
async def transform(request):
    try:
        reader = await request.multipart()
        files = {}
        form_data = {}

        while True:
            part = await reader.next()
            if part is None:
                break
            if part.filename:
                # It's a file
                file_type = part.name
                content = await part.read()
                input_path = save_file(content, part.filename)  # Note: This is now a synchronous call
                if input_path:
                    files[file_type] = input_path
                else:
                    logging.error(f'Invalid file type for {file_type}')
                    return web.json_response({'error': f'Invalid file type for {file_type}'}, status=400)
            else:
                # It's form data
                form_data[part.name] = await part.text()

        if not files:
            logging.error('No valid files provided')
            return web.json_response({'error': 'No valid files provided'}, status=400)

        # Determine the base filename for output
        base_filename = next((files[ft] for ft in ['video', 'audio', 'image', 'watermark'] if ft in files), None)
        if not base_filename:
            logging.error('No valid input file found')
            return web.json_response({'error': 'No valid input file found'}, status=400)

        output_filename = f"output_{os.path.basename(base_filename)}"
        output_path = os.path.join(OUTPUT_FOLDER, output_filename)

        # Deserialize input and output kwargs from JSON
        input_kwargs = json.loads(form_data.get('input_kwargs', '{}'))
        output_kwargs = json.loads(form_data.get('output_kwargs', '{}'))

        output_options = output_kwargs or {}
        # Check if output_options has a format key
        if 'format' in output_options:
            #replace extension with format in output_path
            output_path = output_path.split('.')[0] + '.' + output_options['format']
            
        # Log all the paths and options
        logging.info(f"Input files: video:{files.get('video')}, audio:{files.get('audio')}, image:{files.get('image')}, watermark:{files.get('watermark')}")
        logging.info(f"Input kwargs: {input_kwargs}")
        logging.info(f"Output kwargs: {output_kwargs}")
        logging.info(f"Output path: {output_path}")

        dto = MediaTransformDTO(
            video_path=files.get('video'),
            audio_path=files.get('audio'),
            image_path=files.get('image'),
            watermark_path=files.get('watermark'),
            output_path=output_path,
            input_kwargs=input_kwargs,
            output_kwargs=output_kwargs
        )

        result = transform_media(dto)

        return web.json_response({'success': result, 'output_path': output_path})
    except json.JSONDecodeError as e:
        logging.error(f"JSON decoding error: {str(e)}")
        return web.json_response({'error': 'Invalid JSON in input_kwargs or output_kwargs'}, status=400)
    except Exception as e:
        logging.error(f"Error occurred: {str(e)}")
        # log stack trace
        logging.exception(e)
        return web.json_response({'error': str(e)}, status=400)


import mimetypes


@routes.get('/download_output/{filename}')
async def download_output(request):
    filename = request.match_info['filename']
    file_path = os.path.join(OUTPUT_FOLDER, filename)

    if not os.path.exists(file_path):
        return web.json_response({'error': 'File not found'}, status=404)

    try:
        # Determine the MIME type
        mime_type, _ = mimetypes.guess_type(filename)

        # If mimetypes.guess_type fails, set a default for .flac files
        if mime_type is None and filename.lower().endswith('.flac'):
            mime_type = 'audio/flac'

        # If still None, fall back to application/octet-stream
        if mime_type is None:
            mime_type = 'application/octet-stream'

        return web.FileResponse(file_path, headers={
            'Content-Type': mime_type,
            'Content-Disposition': f'attachment; filename="{filename}"'
        })
    except Exception as e:
        logging.error(f"An error occurred while downloading the file: {str(e)}")
        return web.json_response({'error': 'An error occurred while downloading the file'}, status=500)