from aiohttp import web
import os

# server comes from comfyui, only import if present
try:
    import server
    import folder_paths
except ImportError:
    # throw error if server is not present
    raise ImportError('ComfyUI `server` not found, extension requires comfyui to run.')

prompt_server = server.PromptServer.instance
app = prompt_server.app
routes = prompt_server.routes

# tts and others are not included by default
folder_paths.add_model_folder_path('tts', '/data/models/tts')
folder_paths.add_model_folder_path('LLM', '/data/models/LLM')
folder_paths.add_model_folder_path('tts', '/data/models/piper_tts')


# Get the primary download path, if array, get first, else return the path
primary_download_path = (
    folder_paths.get_folder_paths('checkpoints')) \
    if isinstance(folder_paths.get_folder_paths('checkpoints'), str) \
    else folder_paths.get_folder_paths('checkpoints')[0]


print('Primary download path:', primary_download_path)
print('Paths Info:', folder_paths.get_folder_paths('checkpoints'))



@routes.get('/engines/list')
async def engines_list(request):
    all_models = folder_paths.get_filename_list("checkpoints")
    all_unets = folder_paths.get_filename_list("diffusion_models")
    all_tts = folder_paths.get_filename_list("tts")
    all_llms = folder_paths.get_filename_list("LLM")
    if all_llms is None:
        all_llms = ['Florence-2-base']
    all_upscale = folder_paths.get_filename_list("upscale_models")
    # all_sst is different as it needs to list all files from `~/.cache/whisper/`
    if os.path.exists(os.path.expanduser('~/.cache/whisper/')):
        all_sst = os.listdir(os.path.expanduser('~/.cache/whisper/'))
    else:
        all_sst = ['base', 'tiny', 'small', 'medium', 'large']

    # Combine all models and unets
    all_models.extend(all_unets)
    # Filter to only safetensors files
    all_models = [model for model in all_models if model.endswith('.safetensors')]
    # Filter tts to only onnx files
    all_tts = [model for model in all_tts if model.endswith('.onnx')]
    # return json array of objects with description, id, name, as well as 'type' as 'PICTURE'.
    # `all_models` is a list of filenames
    image_model_results = [{
        'description': f'{model} model',
        'id': model,
        'name': model,
        # return type AUDIO if the model contains `stable_audio` else IMAGE
        'type': 'AUDIO' if 'stable_audio' in model else 'IMAGE'
    } for i, model in enumerate(all_models)]
    # For tts we need to split the name into `<quality>:<voice>` from original name like `en_US-lessac-high.onnx` turns into `high:en_US-lessac`
    # Split on last `-` and use both parts to create the name and id separated by `:` and drop the `.onnx` extension
    tts_model_results = [{
        'description': f'{model} model',
        'id': model,
        'name': f"{model.rsplit('-', 1)[-1].replace('.onnx', '')}:{model.rsplit('-', 1)[0]}",
        'type': 'AUDIO'
    } for model in all_tts]

    # For LLMs, we just want the one entry of the base directory from the file list
    # Split on first `/` and filter duplicates before returning
    all_llms = list(set([model.split('/')[0] for model in all_llms]))
    llm_model_results = [{
        'description': f'{model} model',
        'id': model,
        'name': model,
        'type': 'TEXT'
    } for model in all_llms]
    upscale_model_results = [{
        'description': f'{model} model',
        'id': model,
        'name': model,
        'type': 'IMAGE'
    } for i, model in enumerate(all_upscale)]

    # Drop the `.pt` extension and return the model name
    sst_results = [{
        'description': f'{model} model',
        'id': model,
        'name': model.replace('.pt', ''),
        'type': 'AUDIO'
    } for model in all_sst]
    # Combine all results
    all_results = image_model_results + tts_model_results + llm_model_results + upscale_model_results + sst_results
    return web.json_response(all_results)


@web.middleware
async def simple_api_key_auth(request, handler):
    # Check if an Authorization header is present
    if 'Authorization' not in request.headers:
        return web.json_response({'error': 'Authorization header required'}, status=401)
    # Check if Bearer token is used
    if not request.headers['Authorization'].startswith('Bearer '):
        return web.json_response({'error': 'Bearer token required'}, status=401)
    # Check if the token is valid
    if request.headers['Authorization'] != 'Bearer ' + os.getenv('AGENT_PASSWORD'):
        return web.json_response({'error': 'Invalid token'}, status=401)
    return await handler(request)


# Add the middleware to the app
if os.getenv('AGENT_PASSWORD') is not None:
    app.middlewares.append(simple_api_key_auth)


