#!/bin/bash
set -e

echo "Building Lambda deployment package..."

mkdir -p dist
rm -rf build/fetch_weather_data
mkdir -p build/fetch_weather_data

# Copy source
cp src/lambda/fetch_weather_data/handler.py build/fetch_weather_data/

# Package Lambda function
cd build/fetch_weather_data
zip -r ../../dist/fetch_weather_data.zip .
cd ../..

echo "Building Lambda layer (requests)..."

rm -rf build/layer
mkdir -p build/layer/python

docker run --rm \
    --entrypoint /bin/sh \
    -v "$(pwd)/build/layer:/build" \
    -v "$(pwd)/src/lambda/fetch_weather_data:/src" \
    public.ecr.aws/lambda/python:3.13 \
    -c "pip install -r /src/requirements.txt -t /build/python/"

cd build/layer
zip -r ../../dist/requests-layer.zip python/
cd ../..

echo "Done. Zips created in dist/"