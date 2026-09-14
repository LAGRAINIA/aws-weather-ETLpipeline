import json
import os
import boto3
import requests
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed

# --- Config ------------------------------------------------------------
S3_BUCKET = os.environ['S3_BUCKET']
SECRET_NAME = os.environ['SECRET_NAME']

CITIES = [
    ("Paris", "FR"), ("London", "GB"), ("Berlin", "DE"),
    ("Madrid", "ES"), ("Rome", "IT"), ("Amsterdam", "NL"),
    ("Brussels", "BE"), ("Vienna", "AT"), ("Warsaw", "PL"),
    ("Lisbon", "PT"), ("Athens", "GR"), ("Dublin", "IE"),
    ("Stockholm", "SE"), ("Oslo", "NO"), ("Copenhagen", "DK"),
    ("Helsinki", "FI"), ("Zurich", "CH"), ("Prague", "CZ"),
    ("Budapest", "HU"), ("Bucharest", "RO"),
]

s3 = boto3.client('s3')
secrets = boto3.client('secretsmanager')

# --- Fetch API key once at cold start ---------------------------------
_api_key = None
def get_api_key():
    global _api_key
    if _api_key is None:
        secret = secrets.get_secret_value(SecretId=SECRET_NAME)
        _api_key = json.loads(secret['SecretString'])['api_key']
    return _api_key


def fetch_city_weather(city, country):
    """Call OpenWeatherMap API with retries and return JSON payload."""
    api_key = get_api_key()
    url = f"https://api.openweathermap.org/data/2.5/weather"
    params = {
        "q": f"{city},{country}",
        "appid": api_key,
        "units": "metric",
        "lang": "en"
    }

    for attempt in range(3):
        try:
            response = requests.get(url, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            # Enrich with ingestion metadata
            data['_ingestion_timestamp'] = datetime.now(timezone.utc).isoformat()
            data['_source_city'] = city
            data['_source_country'] = country
            return data
        except Exception as e:
            print(f"Attempt {attempt+1} failed for {city}: {e}")
            if attempt == 2:
                raise
    return None


def write_to_s3(city, data):
    """Write JSON payload to S3 with Hive-style partitioning."""
    now = datetime.now(timezone.utc)
    key = (
        f"bronze/weather/"
        f"year={now.year}/month={now.month:02d}/day={now.day:02d}/hour={now.hour:02d}/"
        f"city={city}/data.json"
    )
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=json.dumps(data, indent=2),
        ContentType='application/json'
    )
    return key


def lambda_handler(event, context):
    """
    Triggered by EventBridge every hour.
    Fetches weather for 20 cities in parallel and drops JSON to Bronze.
    """
    print(f"Starting weather fetch for {len(CITIES)} cities")

    results = {"success": [], "failed": []}

    # Parallel fetch — 5 workers is a good balance for API rate limits
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = {
            executor.submit(fetch_city_weather, city, country): (city, country)
            for city, country in CITIES
        }

        for future in as_completed(futures):
            city, country = futures[future]
            try:
                data = future.result()
                key = write_to_s3(city, data)
                results["success"].append({"city": city, "s3_key": key})
                print(f"✅ {city}: written to {key}")
            except Exception as e:
                results["failed"].append({"city": city, "error": str(e)})
                print(f"❌ {city}: {e}")

    # If more than 20% failed, mark the run as failed for alerting
    total_failed = len(results["failed"])
    if total_failed > len(CITIES) * 0.2:
        raise Exception(
            f"Too many failures: {total_failed}/{len(CITIES)} cities failed. "
            f"Details: {results['failed']}"
        )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "cities_processed": len(results["success"]),
            "cities_failed": total_failed,
            "timestamp": datetime.now(timezone.utc).isoformat()
        })
    }