#!/usr/bin/env python
import json
import subprocess
import sys

# CORS configuration
cors_config = [
    {
        "origin": ["*"],
        "method": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        "maxAgeSeconds": 3600
    }
]

# Save to temporary file
with open('cors_temp.json', 'w') as f:
    json.dump(cors_config, f)

# Try using gcloud command
bucket_name = "gs://toocoob.firebasestorage.app"

try:
    # Use gcloud instead of gsutil
    result = subprocess.run(
        ["gcloud", "storage", "buckets", "update", bucket_name, "--cors-file", "cors_temp.json"],
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        print("CORS configuration set successfully!")
        print(result.stdout)
    else:
        print("Error setting CORS:")
        print(result.stderr)
except Exception as e:
    print(f"Error: {e}")
