# Antigravity Manager: Render + Backblaze B2 deployment

This is a standalone project. It contains no Antigravity Manager source code and uses `lbjlaq/antigravity-manager:latest` as its base image.

## Render

Create a new GitHub repository containing only the contents of this directory. In Render, create a **Web Service**, connect that repository, select Docker, and add these environment variables:

```text
API_KEY=<API access key>
WEB_PASSWORD=<Web admin password>
B2_KEY_ID=<Backblaze application key ID>
B2_APP_KEY=<Backblaze application key>
B2_BUCKET_ID=<B2 bucket ID>
B2_BUCKET_NAME=<B2 bucket name>
B2_PREFIX=antigravity/backup.tar.gz
PORT=8045
```

Do not add a Dockerfile path: `Dockerfile` is at the root of this new repository.

## Backblaze B2

1. Create a private B2 bucket.
2. Create an application key restricted to that bucket with `readFiles`, `writeFiles`, and `listFiles` permissions.
3. Copy the key ID, application key, bucket ID, and bucket name into Render variables. The application key's display name is not used.

The first boot is empty because no B2 backup exists. Subsequent starts restore the saved `/root/.antigravity_tools` directory.

Backups run daily at 00:00 and 12:00 in `Asia/Shanghai` time. The service keeps its original port and request flow; no reverse proxy is used.
