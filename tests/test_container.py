import pytest
import requests
import time

TEST_URL = "https://civitai.com/api/download/models/9208"
TEST_FILE_NAME = "easynegative.safetensors"

@pytest.fixture(scope="module")
def api_url():
    return "http://localhost:7860/api"  # Adjust this to match your container's exposed port


@pytest.fixture(scope="module")
def wait_for_api(api_url):
    max_retries = 30
    for _ in range(max_retries):
        try:
            response = requests.get(f"{api_url}/")
            if response.status_code == 200:
                return
        except requests.ConnectionError:
            pass
        time.sleep(1)
    pytest.fail("API did not become available in time")


def test_engines_list(api_url, wait_for_api):
    response = requests.post(f'{api_url}/agent/delete?name={TEST_FILE_NAME}', json={})
    assert response.status_code == 200
    response = requests.get(f"{api_url}/engines/list")
    assert response.status_code == 200
    engines = response.json()
    assert isinstance(engines, list)
    assert len(engines) >= 0

    num_engines = len(engines)

    # Stopwatch the time it takes to download
    start_time = time.time()

    # Add an engine via /agent/pull
    response = requests.post(f"{api_url}/agent/pull", json={"name": TEST_FILE_NAME, "url": TEST_URL})

    # Print the response details
    print(response.status_code)
    print(response.text)

    assert response.status_code == 200
    assert response.json()['name'] == TEST_FILE_NAME

    # Loop status checks until the download is complete
    while True:
        response = requests.get(f"{api_url}/agent/pull?name={TEST_FILE_NAME}")
        assert response.status_code == 200
        data = response.json()
        print(data)
        if data['progress'] == 100:
            break
        time.sleep(1)

    # Stop
    end_time = time.time()
    print(f"Download took {end_time - start_time} seconds")

    # Check that the download was successful
    response = requests.get(f"{api_url}/engines/list")
    assert response.status_code == 200
    engines = response.json()
    assert isinstance(engines, list)
    assert len(engines) >= num_engines
    print(engines)
    # Assert any engine matches the name
    assert any(engine['name'] == TEST_FILE_NAME for engine in engines)

    # Delete
    response = requests.post(f"{api_url}/agent/delete?name={TEST_FILE_NAME}", json={})
    assert response.status_code == 200
    assert response.json()['message'] == 'Model deleted'


def test_agent_pull(api_url, wait_for_api):
    response = requests.get(f"{api_url}/agent/pull?name={TEST_FILE_NAME}")
    assert response.status_code == 200
    assert response.json().keys() >= {'name', 'progress'}